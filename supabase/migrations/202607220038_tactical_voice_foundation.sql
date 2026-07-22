-- Controller-hosted tactical voice. Signaling and authorization are centralized;
-- DTLS-SRTP media remains peer-to-peer or TURN-relayed and is never stored here.
create table public.voice_operations(
  id uuid primary key default gen_random_uuid(), organization_key text not null,
  operation_key text not null, status text not null default 'active' check(status in ('active','closed')),
  starts_at timestamptz not null default now(), ends_at timestamptz,
  unique(organization_key,operation_key)
);
insert into public.voice_operations(organization_key,operation_key) values('janet-va','nttr-current')
on conflict do nothing;

create table public.voice_rooms(
  id uuid primary key default gen_random_uuid(), operation_id uuid not null references public.voice_operations(id),
  position_id text not null references public.tactical_positions(id),
  position_session_id uuid not null references public.controller_position_sessions(id),
  host_jscope_session_id uuid not null references public.jscope_sessions(id),
  status text not null default 'starting' check(status in ('starting','online_direct','online_relayed','degraded','reconnecting','suspended','offline')),
  transport_mode text not null default 'direct-preferred' check(transport_mode='direct-preferred'),
  max_participants int not null default 8 check(max_participants between 1 and 32),
  created_at timestamptz not null default now(), last_seen_at timestamptz not null default now(), closed_at timestamptz
);
create unique index voice_one_room_per_position_session on public.voice_rooms(position_session_id) where closed_at is null;

create table public.voice_memberships(
  id uuid primary key default gen_random_uuid(),room_id uuid not null references public.voice_rooms(id) on delete cascade,
  subject_id uuid not null references public.profiles(id),role text not null check(role in ('controller','pilot','instructor')),
  aircraft_session_id uuid references public.tactical_aircraft_sessions(id),callsign text not null,
  state text not null default 'authorized' check(state in ('authorized','connecting','connected','disconnected','revoked')),
  connection_mode text check(connection_mode in ('direct','relay','unknown')),quality smallint check(quality between 0 and 100),
  transmitting boolean not null default false,joined_at timestamptz not null default now(),last_seen_at timestamptz not null default now(),left_at timestamptz,
  unique(room_id,subject_id)
);
create table public.voice_credentials(
  id uuid primary key default gen_random_uuid(),room_id uuid not null references public.voice_rooms(id) on delete cascade,
  subject_id uuid not null references public.profiles(id),membership_id uuid not null references public.voice_memberships(id) on delete cascade,
  token_hash bytea not null unique,issued_at timestamptz not null default now(),expires_at timestamptz not null,revoked_at timestamptz,
  transport_mode text not null check(transport_mode='direct-preferred')
);
create table public.voice_commands(
  id bigint generated always as identity primary key,credential_id uuid not null references public.voice_credentials(id),
  room_id uuid not null references public.voice_rooms(id),sequence bigint not null check(sequence>0),event_type text not null,
  recipient_id uuid references public.profiles(id),payload jsonb not null default '{}',created_at timestamptz not null default now(),
  unique(credential_id,sequence)
);

alter table public.voice_operations enable row level security;
alter table public.voice_rooms enable row level security;
alter table public.voice_memberships enable row level security;
alter table public.voice_credentials enable row level security;
alter table public.voice_commands enable row level security;

create or replace function public.open_voice_room(p_token text,p_position_session_id uuid,p_transport_mode text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare js public.jscope_sessions%rowtype; ps public.controller_position_sessions%rowtype; op public.voice_operations%rowtype;
 room public.voice_rooms%rowtype; member public.voice_memberships%rowtype; raw text;
begin
 select * into js from public.valid_jscope_session(p_token); if not found then raise exception 'Invalid or expired JScope session';end if;
 select * into ps from public.controller_position_sessions where id=p_position_session_id and jscope_session_id=js.id and controller_id=js.controller_id and ended_at is null for update;
 if not found then raise exception 'Authoritative position lock required';end if;
 if p_transport_mode<>'direct-preferred' then raise exception 'Only direct WebRTC is enabled';end if;
 select * into op from public.voice_operations where organization_key='janet-va' and operation_key='nttr-current' and status='active';
 if not found then raise exception 'No active voice operation';end if;
 insert into public.voice_rooms(operation_id,position_id,position_session_id,host_jscope_session_id,transport_mode,status)
 values(op.id,ps.position_id,ps.id,js.id,p_transport_mode,'starting')
 on conflict(position_session_id) where closed_at is null do update set last_seen_at=now() returning * into room;
 insert into public.voice_memberships(room_id,subject_id,role,callsign,state)
 select room.id,js.controller_id,'controller',coalesce(cp.controller_callsign,tp.radio_callsign),'connected'
 from public.controller_profiles cp join public.tactical_positions tp on tp.id=room.position_id where cp.user_id=js.controller_id
 on conflict(room_id,subject_id) do update set state='connected',left_at=null,last_seen_at=now() returning * into member;
 raw:=encode(extensions.gen_random_bytes(32),'hex');
 insert into public.voice_credentials(room_id,subject_id,membership_id,token_hash,expires_at,transport_mode)
 values(room.id,js.controller_id,member.id,extensions.digest(raw,'sha256'),now()+interval '5 minutes',p_transport_mode);
 update public.voice_rooms set status='starting',last_seen_at=now() where id=room.id;
 insert into public.tactical_activity_log(event_type,actor_id,actor_kind,position_id,payload)
 values('voice_room_created',js.controller_id,'controller',room.position_id,jsonb_build_object('room_id',room.id,'operation_id',op.id));
 return jsonb_build_object('roomId',room.id,'operationId',op.id,'positionId',room.position_id,'hostSessionId',js.id,
   'status','starting','transportMode',p_transport_mode,'credential',raw,'credentialExpiresAt',now()+interval '5 minutes','subjectId',js.controller_id);
end$$;

create or replace function public.join_voice_room(p_acars_session_id uuid,p_transport_mode text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare tactical public.tactical_aircraft_sessions%rowtype; room public.voice_rooms%rowtype; member public.voice_memberships%rowtype; raw text; pilot_callsign text; host uuid;
begin
 if p_transport_mode<>'direct-preferred' then raise exception 'Only direct WebRTC is enabled';end if;
 select ta.* into tactical from public.tactical_aircraft_sessions ta join public.acars_sessions ac on ac.id=ta.acars_session_id
 where ac.id=p_acars_session_id and ta.pilot_id=auth.uid() and ta.status='active' and ac.status='active' for update;
 if not found then raise exception 'Active owned tactical session required';end if;
 select vr.* into room from public.voice_rooms vr join public.controller_position_sessions ps on ps.id=vr.position_session_id
 join public.jscope_sessions js on js.id=vr.host_jscope_session_id
 where vr.position_id=tactical.current_position_id and vr.closed_at is null and vr.status in ('starting','online_direct','online_relayed','degraded','reconnecting')
 and ps.ended_at is null and js.revoked_at is null and js.expires_at>now() order by vr.created_at desc limit 1 for update;
 if not found then raise exception 'Assigned controller radio is offline';end if;
 if (select count(*) from public.voice_memberships where room_id=room.id and state in ('authorized','connecting','connected'))>=room.max_participants then raise exception 'Radio participant limit reached';end if;
 select f.tracking_callsign into pilot_callsign from public.acars_sessions ac join public.flights f on f.id=ac.flight_id where ac.id=p_acars_session_id;
 insert into public.voice_memberships(room_id,subject_id,role,aircraft_session_id,callsign,state)
 values(room.id,auth.uid(),'pilot',tactical.id,pilot_callsign,'connecting')
 on conflict(room_id,subject_id) do update set state='connecting',left_at=null,last_seen_at=now() returning * into member;
 raw:=encode(extensions.gen_random_bytes(32),'hex');
 insert into public.voice_credentials(room_id,subject_id,membership_id,token_hash,expires_at,transport_mode)
 values(room.id,auth.uid(),member.id,extensions.digest(raw,'sha256'),now()+interval '5 minutes',p_transport_mode);
 select subject_id into host from public.voice_memberships where room_id=room.id and role='controller' and state='connected';
 update public.tactical_aircraft_sessions set voice_state='connecting' where id=tactical.id;
 insert into public.tactical_activity_log(event_type,actor_id,actor_kind,aircraft_session_id,position_id,payload)
 values('voice_member_authorized',auth.uid(),'pilot',tactical.id,room.position_id,jsonb_build_object('room_id',room.id));
 return jsonb_build_object('roomId',room.id,'operationId',room.operation_id,'positionId',room.position_id,'status',room.status,
  'transportMode',p_transport_mode,'credential',raw,'credentialExpiresAt',now()+interval '5 minutes','subjectId',auth.uid(),'hostSubjectId',host);
end$$;

create or replace function public.voice_command(p_credential text,p_room_id uuid,p_sequence bigint,p_event_type text,p_recipient_id uuid,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cred public.voice_credentials%rowtype; room public.voice_rooms%rowtype; command_id bigint;
begin
 select * into cred from public.voice_credentials where room_id=p_room_id and token_hash=extensions.digest(p_credential,'sha256') and revoked_at is null and expires_at>now() for update;
 if not found then raise exception 'Expired or invalid voice credential';end if;
 select * into room from public.voice_rooms where id=p_room_id and closed_at is null for update;
 if not found or room.status in ('suspended','offline') then raise exception 'Voice room is unavailable';end if;
 if p_event_type not in ('radio.signal.offer','radio.signal.answer','radio.signal.ice_candidate','radio.connection.state','radio.ptt.start','radio.ptt.stop','radio.member.leave') then raise exception 'Unsupported voice event';end if;
 if p_recipient_id is not null and not exists(select 1 from public.voice_memberships where room_id=room.id and subject_id=p_recipient_id and state<>'revoked') then raise exception 'Invalid room recipient';end if;
 if octet_length(coalesce(p_payload,'{}')::text)>65536 then raise exception 'Signaling payload too large';end if;
 insert into public.voice_commands(credential_id,room_id,sequence,event_type,recipient_id,payload)
 values(cred.id,room.id,p_sequence,p_event_type,p_recipient_id,coalesce(p_payload,'{}')) returning id into command_id;
 update public.voice_memberships set last_seen_at=now(),transmitting=p_event_type='radio.ptt.start',
   state=case when p_event_type='radio.member.leave' then 'disconnected' else state end,
   left_at=case when p_event_type='radio.member.leave' then now() else left_at end
 where id=cred.membership_id;
 if p_event_type='radio.connection.state' then
   update public.voice_memberships set state=case when p_payload->>'state'='connected' then 'connected' else state end,
     connection_mode=case when p_payload->>'mode' in ('direct','relay','unknown') then p_payload->>'mode' else connection_mode end,
     quality=least(100,greatest(0,coalesce((p_payload->>'quality')::int,quality))) where id=cred.membership_id;
 end if;
 return jsonb_build_object('id',command_id,'accepted',true);
exception when unique_violation then raise exception 'Replayed or stale voice command';
end$$;

create or replace function public.poll_voice_events(p_credential text,p_room_id uuid,p_after bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cred public.voice_credentials%rowtype;
begin
 select * into cred from public.voice_credentials where room_id=p_room_id and token_hash=extensions.digest(p_credential,'sha256') and revoked_at is null and expires_at>now();
 if not found then raise exception 'Expired or invalid voice credential';end if;
 update public.voice_memberships set last_seen_at=now() where id=cred.membership_id;
 return jsonb_build_object('events',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'type',c.event_type,'senderId',vc.subject_id,'payload',c.payload,'createdAt',c.created_at) order by c.id)
   from public.voice_commands c join public.voice_credentials vc on vc.id=c.credential_id
   where c.room_id=p_room_id and c.id>p_after and vc.subject_id<>cred.subject_id and (c.recipient_id is null or c.recipient_id=cred.subject_id)),'[]'::jsonb),
   'participants',coalesce((select jsonb_agg(jsonb_build_object('subjectId',m.subject_id,'callsign',m.callsign,'role',m.role,'state',m.state,'mode',m.connection_mode,'quality',m.quality,'transmitting',m.transmitting)) from public.voice_memberships m where m.room_id=p_room_id and m.state<>'revoked'),'[]'::jsonb));
end$$;

create or replace function public.close_voice_room(p_token text,p_position_session_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare js public.jscope_sessions%rowtype; room public.voice_rooms%rowtype;
begin
 select * into js from public.valid_jscope_session(p_token);if not found then raise exception 'Invalid or expired JScope session';end if;
 update public.voice_rooms vr set status='offline',closed_at=now() from public.controller_position_sessions ps
 where vr.position_session_id=ps.id and ps.id=p_position_session_id and ps.jscope_session_id=js.id and vr.closed_at is null returning vr.* into room;
 if not found then raise exception 'Owned active voice room required';end if;
 update public.voice_credentials set revoked_at=now() where room_id=room.id and revoked_at is null;
 update public.voice_memberships set state='revoked',transmitting=false,left_at=now() where room_id=room.id;
 insert into public.tactical_activity_log(event_type,actor_id,actor_kind,position_id,payload) values('voice_room_closed',js.controller_id,'controller',room.position_id,jsonb_build_object('room_id',room.id));
 return jsonb_build_object('roomId',room.id,'status','offline');
end$$;

revoke all on function public.open_voice_room(text,uuid,text),public.join_voice_room(uuid,text),public.voice_command(text,uuid,bigint,text,uuid,jsonb),public.poll_voice_events(text,uuid,bigint),public.close_voice_room(text,uuid) from public,anon;
grant execute on function public.open_voice_room(text,uuid,text),public.join_voice_room(uuid,text),public.voice_command(text,uuid,bigint,text,uuid,jsonb),public.poll_voice_events(text,uuid,bigint),public.close_voice_room(text,uuid) to authenticated;
notify pgrst,'reload schema';
