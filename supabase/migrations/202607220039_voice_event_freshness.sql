-- Fresh credentials must not replay signaling left by an earlier peer connection.
create or replace function public.poll_voice_events(p_credential text,p_room_id uuid,p_after bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cred public.voice_credentials%rowtype;
begin
 select * into cred from public.voice_credentials where room_id=p_room_id and token_hash=extensions.digest(p_credential,'sha256') and revoked_at is null and expires_at>now();
 if not found then raise exception 'Expired or invalid voice credential';end if;
 update public.voice_memberships set last_seen_at=now() where id=cred.membership_id;
 return jsonb_build_object('events',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'type',c.event_type,'senderId',vc.subject_id,'payload',c.payload,'createdAt',c.created_at) order by c.id)
   from public.voice_commands c join public.voice_credentials vc on vc.id=c.credential_id
   where c.room_id=p_room_id and c.id>p_after and c.created_at>=cred.issued_at
     and vc.subject_id<>cred.subject_id and (c.recipient_id is null or c.recipient_id=cred.subject_id)),'[]'::jsonb),
   'participants',coalesce((select jsonb_agg(jsonb_build_object('subjectId',m.subject_id,'callsign',m.callsign,'role',m.role,'state',m.state,'mode',m.connection_mode,'quality',m.quality,'transmitting',m.transmitting)) from public.voice_memberships m where m.room_id=p_room_id and m.state<>'revoked'),'[]'::jsonb));
end$$;
revoke all on function public.poll_voice_events(text,uuid,bigint) from public,anon;
grant execute on function public.poll_voice_events(text,uuid,bigint) to authenticated;
notify pgrst,'reload schema';
