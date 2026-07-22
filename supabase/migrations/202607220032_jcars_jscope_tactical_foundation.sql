-- Private JCars tactical-control foundation. This system is intentionally
-- isolated from simulator radios, xPilot, VATSIM controller connections, and AFV.
create table public.tactical_positions(
  id text primary key check(id in ('nellis_control','dreamland','groom_ground','groom_tower','tonopah_ground','tonopah_tower')),
  display_name text not null,
  radio_callsign text not null,
  display_frequency text not null,
  channel_id text not null unique,
  coverage jsonb not null default '{}',
  training_allowed boolean not null default true,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);
insert into public.tactical_positions(id,display_name,radio_callsign,display_frequency,channel_id,coverage) values
('nellis_control','Nellis Control','Nellis Control','377.800','jcars-nellis-control','{"scope":"range_center"}'),
('dreamland','Dreamland','Dreamland','343.700','jcars-dreamland','{"airports":["STN3","STN7"]}'),
('groom_ground','Groom Ground','Groom Ground','121.800','jcars-groom-ground','{"airport":"STN3","service":"ground"}'),
('groom_tower','Groom Tower','Groom Tower','340.200','jcars-groom-tower','{"airport":"STN3","service":"tower"}'),
('tonopah_ground','Tonopah Ground','Tonopah Ground','121.900','jcars-tonopah-ground','{"airport":"STN7","service":"ground"}'),
('tonopah_tower','Tonopah Tower','Tonopah Tower','257.950','jcars-tonopah-tower','{"airport":"STN7","service":"tower"}');

create table public.controller_profiles(
  user_id uuid primary key references public.profiles(id) on delete cascade,
  approval_state text not null default 'not_applied' check(approval_state in ('not_applied','application_pending','trainee','approved','instructor','suspended','revoked')),
  controller_callsign text,
  restrictions jsonb not null default '[]',
  approved_at timestamptz,
  approved_by uuid references public.profiles(id),
  suspended_at timestamptz,
  suspension_reason text,
  updated_at timestamptz not null default now()
);
create table public.controller_applications(
  id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id),statement text not null,
  status text not null default 'pending' check(status in ('pending','approved','rejected','withdrawn')),
  reviewed_by uuid references public.profiles(id),reviewed_at timestamptz,review_notes text,created_at timestamptz not null default now()
);
create table public.controller_qualifications(
  id uuid primary key default gen_random_uuid(),controller_id uuid not null references public.controller_profiles(user_id) on delete cascade,
  position_id text not null references public.tactical_positions(id),
  qualification_level text not null check(qualification_level in ('observer','trainee','qualified','instructor')),
  training_authorized boolean not null default false,instructor_endorsed boolean not null default false,
  issued_at timestamptz not null default now(),expires_at timestamptz,issued_by uuid not null references public.profiles(id),
  restricted boolean not null default false,restriction_reason text,audit_metadata jsonb not null default '{}',
  unique(controller_id,position_id)
);
create table public.jscope_sessions(
  id uuid primary key default gen_random_uuid(),controller_id uuid not null references public.controller_profiles(user_id) on delete cascade,
  token_hash bytea not null unique,created_at timestamptz not null default now(),expires_at timestamptz not null,
  last_seen_at timestamptz not null default now(),revoked_at timestamptz,revocation_reason text,client_version text not null
);
create table public.instructor_supervision_sessions(
  id uuid primary key default gen_random_uuid(),trainee_id uuid not null references public.controller_profiles(user_id),
  instructor_id uuid not null references public.controller_profiles(user_id),position_id text not null references public.tactical_positions(id),
  status text not null default 'active' check(status in ('active','grace','ended','suspended')),
  started_at timestamptz not null default now(),grace_expires_at timestamptz,ended_at timestamptz
);
create unique index one_active_trainee_supervision_idx on public.instructor_supervision_sessions(trainee_id,position_id) where status in ('active','grace');
create table public.controller_position_sessions(
  id uuid primary key default gen_random_uuid(),jscope_session_id uuid not null references public.jscope_sessions(id) on delete cascade,
  controller_id uuid not null references public.controller_profiles(user_id),position_id text not null references public.tactical_positions(id),
  supervision_id uuid references public.instructor_supervision_sessions(id),is_primary boolean not null default true,
  safety_notice_accepted_at timestamptz not null,started_at timestamptz not null default now(),last_seen_at timestamptz not null default now(),ended_at timestamptz,end_reason text
);
create unique index tactical_position_one_primary_idx on public.controller_position_sessions(position_id) where ended_at is null and is_primary;

create table public.tactical_aircraft_sessions(
  id uuid primary key default gen_random_uuid(),acars_session_id uuid not null unique references public.acars_sessions(id) on delete cascade,
  pilot_id uuid not null references public.profiles(id),flight_id uuid not null references public.flights(id),
  status text not null default 'active' check(status in ('active','suspended','left','completed')),
  current_position_id text references public.tactical_positions(id),current_channel_id text,
  voice_state text not null default 'disconnected' check(voice_state in ('disconnected','connecting','connected','muted','failed')),
  safety_notice_accepted_at timestamptz not null,opted_in_at timestamptz not null default now(),ended_at timestamptz,
  suspension_reason text,last_event_at timestamptz not null default now()
);
create table public.tactical_instructions(
  id uuid primary key default gen_random_uuid(),event_version smallint not null default 1,
  position_session_id uuid not null references public.controller_position_sessions(id),issuing_controller_id uuid not null references public.controller_profiles(user_id),
  issuing_position_id text not null references public.tactical_positions(id),aircraft_session_id uuid not null references public.tactical_aircraft_sessions(id),
  instruction_type text not null check(instruction_type in ('taxi','hold_position','runway_crossing','line_up_wait','takeoff','landing','go_around','heading','altitude','speed','route','direct_to','hold','approach_assignment','range_entry','range_exit','operating_area','frequency_change','return_to_vatsim','advisory')),
  parameters jsonb not null default '{}',display_text text not null,issued_at timestamptz not null default now(),expires_at timestamptz,
  acknowledgement text check(acknowledgement in ('wilco','roger','unable','standby','request_clarification')),
  acknowledged_at timestamptz,status text not null default 'issued' check(status in ('issued','acknowledged','completed','cancelled','replaced','expired')),
  replaced_by uuid references public.tactical_instructions(id),cancelled_at timestamptz,cancellation_reason text,command_nonce uuid not null unique,
  audit_metadata jsonb not null default '{}'
);
create table public.tactical_handoffs(
  id uuid primary key default gen_random_uuid(),aircraft_session_id uuid not null references public.tactical_aircraft_sessions(id),
  from_position_id text not null references public.tactical_positions(id),to_position_id text references public.tactical_positions(id),
  requested_by uuid not null references public.controller_profiles(user_id),
  state text not null default 'requested' check(state in ('requested','accepted','standby','contacting','completed','unable','rejected','cancelled','expired')),
  requested_at timestamptz not null default now(),responded_at timestamptz,completed_at timestamptz,expires_at timestamptz,
  return_to_vatsim boolean not null default false,display_frequency text,command_nonce uuid not null unique
);
create table public.tactical_activity_log(
  id bigint generated always as identity primary key,event_version smallint not null default 1,event_type text not null,
  actor_id uuid,actor_kind text not null check(actor_kind in ('pilot','controller','instructor','administrator','system')),
  aircraft_session_id uuid,position_id text,payload jsonb not null default '{}',occurred_at timestamptz not null default now()
);

alter table public.tactical_positions enable row level security;
alter table public.controller_profiles enable row level security;
alter table public.controller_applications enable row level security;
alter table public.controller_qualifications enable row level security;
alter table public.jscope_sessions enable row level security;
alter table public.instructor_supervision_sessions enable row level security;
alter table public.controller_position_sessions enable row level security;
alter table public.tactical_aircraft_sessions enable row level security;
alter table public.tactical_instructions enable row level security;
alter table public.tactical_handoffs enable row level security;
alter table public.tactical_activity_log enable row level security;
create policy tactical_positions_authenticated_read on public.tactical_positions for select to authenticated using(active);
create policy controller_profile_self_read on public.controller_profiles for select to authenticated using(user_id=auth.uid());
create policy controller_qualification_self_read on public.controller_qualifications for select to authenticated using(controller_id=auth.uid());
create policy tactical_aircraft_own_read on public.tactical_aircraft_sessions for select to authenticated using(pilot_id=auth.uid());
create policy tactical_instruction_pilot_read on public.tactical_instructions for select to authenticated using(exists(select 1 from public.tactical_aircraft_sessions a where a.id=aircraft_session_id and a.pilot_id=auth.uid()));

create or replace function public.prevent_tactical_audit_mutation() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'Tactical activity history is immutable';end$$;
create trigger tactical_activity_immutable before update or delete on public.tactical_activity_log for each row execute function public.prevent_tactical_audit_mutation();

create or replace function public.valid_jscope_session(p_token text) returns public.jscope_sessions
language sql stable security definer set search_path='' as $$
  select s from public.jscope_sessions s join public.controller_profiles c on c.user_id=s.controller_id
  where s.controller_id=auth.uid() and s.token_hash=extensions.digest(p_token,'sha256') and s.revoked_at is null and s.expires_at>now()
    and c.approval_state in ('trainee','approved','instructor') and c.suspended_at is null
$$;
revoke all on function public.valid_jscope_session(text) from public,anon,authenticated;

create or replace function public.open_jscope_session(p_client_version text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); profile public.controller_profiles%rowtype; raw_token text; created public.jscope_sessions%rowtype;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  select * into profile from public.controller_profiles where user_id=actor for update;
  if not found or profile.approval_state not in ('trainee','approved','instructor') or profile.suspended_at is not null then
    insert into public.tactical_activity_log(event_type,actor_id,actor_kind,payload) values('jscope_login_denied',actor,'controller',jsonb_build_object('reason','controller_access_denied'));
    raise exception 'JScope controller approval is required';
  end if;
  raw_token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into public.jscope_sessions(controller_id,token_hash,expires_at,client_version)
  values(actor,extensions.digest(raw_token,'sha256'),now()+interval '30 minutes',left(p_client_version,40)) returning * into created;
  insert into public.tactical_activity_log(event_type,actor_id,actor_kind,payload) values('jscope_session_opened',actor,'controller',jsonb_build_object('session_id',created.id));
  return jsonb_build_object('sessionId',created.id,'token',raw_token,'expiresAt',created.expires_at,'callsign',profile.controller_callsign,
    'positions',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'displayName',p.display_name,'radioCallsign',p.radio_callsign,'displayFrequency',p.display_frequency,'channelId',p.channel_id)),'[]'::jsonb)
      from public.controller_qualifications q join public.tactical_positions p on p.id=q.position_id
      where q.controller_id=actor and not q.restricted and (q.expires_at is null or q.expires_at>now()) and p.active));
end$$;

create or replace function public.claim_tactical_position(p_token text,p_position_id text,p_safety_accepted boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare session public.jscope_sessions%rowtype; profile public.controller_profiles%rowtype; qualification public.controller_qualifications%rowtype; occupied public.controller_position_sessions%rowtype;
begin
  select * into session from public.valid_jscope_session(p_token);if not found then raise exception 'Invalid or expired JScope session';end if;
  if not p_safety_accepted then raise exception 'Operational safety notice must be accepted';end if;
  select * into profile from public.controller_profiles where user_id=session.controller_id;
  select * into qualification from public.controller_qualifications where controller_id=session.controller_id and position_id=p_position_id and not restricted and (expires_at is null or expires_at>now());
  if not found or qualification.qualification_level not in ('trainee','qualified','instructor') then raise exception 'Position qualification required';end if;
  if profile.approval_state='trainee' and not exists(select 1 from public.instructor_supervision_sessions s where s.trainee_id=session.controller_id and s.position_id=p_position_id and s.status='active') then raise exception 'Active instructor supervision required';end if;
  insert into public.controller_position_sessions(jscope_session_id,controller_id,position_id,safety_notice_accepted_at)
  values(session.id,session.controller_id,p_position_id,now()) returning * into occupied;
  insert into public.tactical_activity_log(event_type,actor_id,actor_kind,position_id,payload) values('position_acquired',session.controller_id,'controller',p_position_id,jsonb_build_object('position_session_id',occupied.id));
  return jsonb_build_object('positionSessionId',occupied.id,'positionId',p_position_id);
exception when unique_violation then raise exception 'Position is already occupied';
end$$;

create or replace function public.opt_in_tactical_control(p_acars_session_id uuid,p_safety_accepted boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare acars public.acars_sessions%rowtype; tactical public.tactical_aircraft_sessions%rowtype; position public.tactical_positions%rowtype;
begin
  if not p_safety_accepted then raise exception 'Safety notice must be accepted';end if;
  select * into acars from public.acars_sessions where id=p_acars_session_id and pilot_id=auth.uid() and status='active';
  if not found then raise exception 'Active owned JCars session required';end if;
  select * into position from public.tactical_positions where id='nellis_control' and active;
  insert into public.tactical_aircraft_sessions(acars_session_id,pilot_id,flight_id,current_position_id,current_channel_id,safety_notice_accepted_at)
  values(acars.id,acars.pilot_id,acars.flight_id,position.id,position.channel_id,now())
  on conflict(acars_session_id) do update set status='active',ended_at=null,suspension_reason=null,last_event_at=now()
  returning * into tactical;
  insert into public.tactical_activity_log(event_type,actor_id,actor_kind,aircraft_session_id,position_id) values('pilot_opted_in',auth.uid(),'pilot',tactical.id,tactical.current_position_id);
  return jsonb_build_object('id',tactical.id,'status',tactical.status,'positionId',position.id,'positionName',position.display_name,'controllerCallsign',position.radio_callsign,'displayFrequency',position.display_frequency,'channelId',position.channel_id,'voiceState',tactical.voice_state);
end$$;

create or replace function public.get_pilot_tactical_state(p_acars_session_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('session',jsonb_build_object('id',a.id,'status',a.status,'positionId',p.id,'positionName',p.display_name,'controllerCallsign',p.radio_callsign,'displayFrequency',p.display_frequency,'channelId',p.channel_id,'voiceState',a.voice_state,'suspensionReason',a.suspension_reason),
  'instructions',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'type',i.instruction_type,'text',i.display_text,'parameters',i.parameters,'issuedAt',i.issued_at,'status',i.status,'acknowledgement',i.acknowledgement) order by i.issued_at desc) from public.tactical_instructions i where i.aircraft_session_id=a.id and i.status in ('issued','acknowledged')),'[]'::jsonb))
 from public.tactical_aircraft_sessions a join public.tactical_positions p on p.id=a.current_position_id
 where a.acars_session_id=p_acars_session_id and a.pilot_id=auth.uid()
$$;

create or replace function public.get_jscope_snapshot(p_token text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare session public.jscope_sessions%rowtype;
begin
 select * into session from public.valid_jscope_session(p_token);if not found then raise exception 'Invalid or expired JScope session';end if;
 update public.jscope_sessions set last_seen_at=now() where id=session.id;
 return jsonb_build_object('generatedAt',now(),'aircraft',(
  select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'callsign',f.tracking_callsign,'aircraftType',t.code,'latitude',latest.latitude,'longitude',latest.longitude,'altitude',latest.altitude,'groundSpeed',latest.ground_speed,'heading',latest.heading,'verticalSpeed',latest.vertical_speed,'origin',o.local_code,'destination',d.local_code,'positionId',a.current_position_id,'channelId',a.current_channel_id,'tacticalStatus',a.status,'communicationsStatus',a.voice_state)),'[]'::jsonb)
  from public.tactical_aircraft_sessions a join public.acars_sessions ac on ac.id=a.acars_session_id join public.flights f on f.id=a.flight_id
  left join public.aircraft craft on craft.id=ac.aircraft_id left join public.aircraft_types t on t.id=craft.aircraft_type_id
  left join public.airports o on o.id=f.origin_airport_id left join public.airports d on d.id=f.destination_airport_id
  left join lateral(select tp.* from public.flight_telemetry_points tp where tp.session_id=ac.id order by tp.recorded_at desc limit 1) latest on true
  where a.status in ('active','suspended') and ac.status='active'
 ),'positions',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'displayName',p.display_name,'radioCallsign',p.radio_callsign,'displayFrequency',p.display_frequency,'channelId',p.channel_id)),'[]'::jsonb) from public.tactical_positions p where p.active));
end$$;

create or replace function public.issue_tactical_instruction(p_token text,p_position_session_id uuid,p_aircraft_session_id uuid,p_type text,p_parameters jsonb,p_text text,p_nonce uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare session public.jscope_sessions%rowtype; occupied public.controller_position_sessions%rowtype; aircraft public.tactical_aircraft_sessions%rowtype; created public.tactical_instructions%rowtype;
begin
 select * into session from public.valid_jscope_session(p_token);if not found then raise exception 'Invalid or expired JScope session';end if;
 select * into occupied from public.controller_position_sessions where id=p_position_session_id and jscope_session_id=session.id and controller_id=session.controller_id and ended_at is null for update;
 if not found then raise exception 'Active occupied position required';end if;
 select * into aircraft from public.tactical_aircraft_sessions where id=p_aircraft_session_id and status='active' for update;
 if not found then raise exception 'Aircraft is not under active tactical control';end if;
 if aircraft.current_position_id is distinct from occupied.position_id then raise exception 'Aircraft is controlled by another position';end if;
 insert into public.tactical_instructions(position_session_id,issuing_controller_id,issuing_position_id,aircraft_session_id,instruction_type,parameters,display_text,command_nonce)
 values(occupied.id,session.controller_id,occupied.position_id,aircraft.id,p_type,coalesce(p_parameters,'{}'),left(trim(p_text),500),p_nonce) returning * into created;
 insert into public.tactical_activity_log(event_type,actor_id,actor_kind,aircraft_session_id,position_id,payload) values('instruction_issued',session.controller_id,'controller',aircraft.id,occupied.position_id,jsonb_build_object('instruction_id',created.id,'type',created.instruction_type));
 return jsonb_build_object('id',created.id,'status',created.status,'issuedAt',created.issued_at);
exception when unique_violation then raise exception 'Duplicate or replayed command';
end$$;

create or replace function public.acknowledge_tactical_instruction(p_instruction_id uuid,p_response text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare instruction public.tactical_instructions%rowtype;
begin
 select i.* into instruction from public.tactical_instructions i join public.tactical_aircraft_sessions a on a.id=i.aircraft_session_id where i.id=p_instruction_id and a.pilot_id=auth.uid() and a.status='active' for update;
 if not found then raise exception 'Active owned tactical instruction required';end if;
 if instruction.status not in ('issued','acknowledged') then raise exception 'Instruction cannot be acknowledged in its current state';end if;
 if p_response not in ('wilco','roger','unable','standby','request_clarification') then raise exception 'Invalid acknowledgement';end if;
 update public.tactical_instructions set acknowledgement=p_response,acknowledged_at=now(),status='acknowledged' where id=instruction.id;
 insert into public.tactical_activity_log(event_type,actor_id,actor_kind,aircraft_session_id,position_id,payload) values('instruction_acknowledged',auth.uid(),'pilot',instruction.aircraft_session_id,instruction.issuing_position_id,jsonb_build_object('instruction_id',instruction.id,'response',p_response));
 return jsonb_build_object('id',instruction.id,'status','acknowledged','response',p_response);
end$$;

create or replace function public.suspend_pilot_tactical_control(p_acars_session_id uuid,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare tactical public.tactical_aircraft_sessions%rowtype;
begin
 update public.tactical_aircraft_sessions set status='suspended',suspension_reason=left(coalesce(nullif(trim(p_reason),''),'Pilot requested suspension'),300),last_event_at=now()
 where acars_session_id=p_acars_session_id and pilot_id=auth.uid() and status='active' returning * into tactical;
 if not found then raise exception 'Active owned tactical session required';end if;
 update public.tactical_instructions set status='cancelled',cancelled_at=now(),cancellation_reason='Tactical control suspended' where aircraft_session_id=tactical.id and status='issued';
 update public.tactical_handoffs set state='cancelled',responded_at=now() where aircraft_session_id=tactical.id and state in ('requested','accepted','standby','contacting');
 insert into public.tactical_activity_log(event_type,actor_id,actor_kind,aircraft_session_id,position_id,payload) values('tactical_control_suspended',auth.uid(),'pilot',tactical.id,tactical.current_position_id,jsonb_build_object('reason',tactical.suspension_reason));
 return jsonb_build_object('id',tactical.id,'status',tactical.status,'reason',tactical.suspension_reason);
end$$;

create or replace function public.admin_set_controller_access(p_user_id uuid,p_state text,p_callsign text,p_position_id text,p_level text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); qualification_id uuid;
begin
 if actor is null or not public.has_any_role(actor,array['owner','system_administrator']::public.app_role[]) then raise exception 'Controller administration permission required';end if;
 if p_state not in ('trainee','approved','instructor','suspended','revoked') then raise exception 'Invalid controller state';end if;
 if p_level not in ('observer','trainee','qualified','instructor') then raise exception 'Invalid qualification level';end if;
 if not exists(select 1 from public.profiles where id=p_user_id) then raise exception 'Controller identity not found';end if;
 if not exists(select 1 from public.tactical_positions where id=p_position_id and active) then raise exception 'Tactical position not found';end if;
 insert into public.controller_profiles(user_id,approval_state,controller_callsign,approved_at,approved_by,suspended_at,suspension_reason)
 values(p_user_id,p_state,nullif(trim(p_callsign),''),case when p_state in ('trainee','approved','instructor') then now() end,actor,case when p_state in ('suspended','revoked') then now() end,case when p_state in ('suspended','revoked') then 'Administrative action' end)
 on conflict(user_id) do update set approval_state=excluded.approval_state,controller_callsign=excluded.controller_callsign,approved_at=coalesce(public.controller_profiles.approved_at,excluded.approved_at),approved_by=actor,suspended_at=excluded.suspended_at,suspension_reason=excluded.suspension_reason,updated_at=now();
 insert into public.controller_qualifications(controller_id,position_id,qualification_level,training_authorized,instructor_endorsed,issued_by)
 values(p_user_id,p_position_id,p_level,p_level in ('trainee','qualified','instructor'),p_level='instructor',actor)
 on conflict(controller_id,position_id) do update set qualification_level=excluded.qualification_level,training_authorized=excluded.training_authorized,instructor_endorsed=excluded.instructor_endorsed,issued_at=now(),expires_at=null,issued_by=actor,restricted=false,restriction_reason=null returning id into qualification_id;
 if p_state in ('suspended','revoked') then
  update public.jscope_sessions set revoked_at=now(),revocation_reason='Controller access '||p_state where controller_id=p_user_id and revoked_at is null;
  update public.controller_position_sessions set ended_at=now(),end_reason='Controller access '||p_state where controller_id=p_user_id and ended_at is null;
 end if;
 insert into public.tactical_activity_log(event_type,actor_id,actor_kind,payload) values('controller_access_changed',actor,'administrator',jsonb_build_object('controller_id',p_user_id,'state',p_state,'position_id',p_position_id,'level',p_level));
 return jsonb_build_object('controllerId',p_user_id,'state',p_state,'positionId',p_position_id,'level',p_level,'qualificationId',qualification_id);
end$$;

revoke all on function public.open_jscope_session(text),public.claim_tactical_position(text,text,boolean),public.opt_in_tactical_control(uuid,boolean),public.get_pilot_tactical_state(uuid),public.get_jscope_snapshot(text),public.issue_tactical_instruction(text,uuid,uuid,text,jsonb,text,uuid),public.acknowledge_tactical_instruction(uuid,text),public.suspend_pilot_tactical_control(uuid,text),public.admin_set_controller_access(uuid,text,text,text,text) from public,anon;
grant execute on function public.open_jscope_session(text),public.claim_tactical_position(text,text,boolean),public.opt_in_tactical_control(uuid,boolean),public.get_pilot_tactical_state(uuid),public.get_jscope_snapshot(text),public.issue_tactical_instruction(text,uuid,uuid,text,jsonb,text,uuid),public.acknowledge_tactical_instruction(uuid,text),public.suspend_pilot_tactical_control(uuid,text),public.admin_set_controller_access(uuid,text,text,text,text) to authenticated;
notify pgrst,'reload schema';
