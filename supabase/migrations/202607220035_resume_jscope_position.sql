-- Allow a controller to resume/reclaim their own position after a browser reload
-- without permitting takeover of another controller's active position.
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

  select * into occupied from public.controller_position_sessions where position_id=p_position_id and ended_at is null and is_primary for update;
  if found then
    if occupied.controller_id<>session.controller_id then raise exception 'Position is already occupied';end if;
    if occupied.jscope_session_id=session.id then
      update public.controller_position_sessions set last_seen_at=now() where id=occupied.id;
      return jsonb_build_object('positionSessionId',occupied.id,'positionId',p_position_id,'resumed',true);
    end if;
    update public.controller_position_sessions set ended_at=now(),end_reason='Same controller resumed from a new JScope session' where id=occupied.id;
  end if;

  insert into public.controller_position_sessions(jscope_session_id,controller_id,position_id,safety_notice_accepted_at)
  values(session.id,session.controller_id,p_position_id,now()) returning * into occupied;
  insert into public.tactical_activity_log(event_type,actor_id,actor_kind,position_id,payload) values('position_acquired',session.controller_id,'controller',p_position_id,jsonb_build_object('position_session_id',occupied.id));
  return jsonb_build_object('positionSessionId',occupied.id,'positionId',p_position_id,'resumed',false);
end$$;

revoke all on function public.claim_tactical_position(text,text,boolean) from public,anon;
grant execute on function public.claim_tactical_position(text,text,boolean) to authenticated;
notify pgrst,'reload schema';
