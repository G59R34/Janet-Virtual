-- Normalize controller qualification records written by earlier controller-access
-- deployments, then use a null-safe qualification predicate during position claim.
update public.controller_qualifications
set qualification_level = lower(trim(qualification_level)),
    restricted = coalesce(restricted, false)
where qualification_level is distinct from lower(trim(qualification_level))
   or restricted is null;

create or replace function public.claim_tactical_position(
  p_token text,
  p_position_id text,
  p_safety_accepted boolean
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  session public.jscope_sessions%rowtype;
  profile public.controller_profiles%rowtype;
  occupied public.controller_position_sessions%rowtype;
begin
  select * into session from public.valid_jscope_session(p_token);
  if not found then
    raise exception 'Invalid or expired JScope session';
  end if;
  if not p_safety_accepted then
    raise exception 'Operational safety notice must be accepted';
  end if;

  select * into profile
  from public.controller_profiles
  where user_id = session.controller_id;

  if not exists (
    select 1
    from public.controller_qualifications qualification
    where qualification.controller_id = session.controller_id
      and qualification.position_id = p_position_id
      and coalesce(qualification.restricted, false) = false
      and lower(trim(qualification.qualification_level)) in ('trainee', 'qualified', 'instructor')
      and coalesce(qualification.expires_at, 'infinity'::timestamptz) > now()
  ) then
    raise exception 'Position qualification required for %', p_position_id;
  end if;

  if profile.approval_state = 'trainee' and not exists (
    select 1
    from public.instructor_supervision_sessions supervision
    where supervision.trainee_id = session.controller_id
      and supervision.position_id = p_position_id
      and supervision.status = 'active'
  ) then
    raise exception 'Active instructor supervision required';
  end if;

  select * into occupied
  from public.controller_position_sessions
  where position_id = p_position_id
    and ended_at is null
    and is_primary
  for update;

  if found then
    if occupied.controller_id <> session.controller_id then
      raise exception 'Position is already occupied';
    end if;
    if occupied.jscope_session_id = session.id then
      update public.controller_position_sessions
      set last_seen_at = now()
      where id = occupied.id;
      return jsonb_build_object('positionSessionId', occupied.id, 'positionId', p_position_id, 'resumed', true);
    end if;
    update public.controller_position_sessions
    set ended_at = now(), end_reason = 'Same controller resumed from a new JScope session'
    where id = occupied.id;
  end if;

  insert into public.controller_position_sessions(
    jscope_session_id, controller_id, position_id, safety_notice_accepted_at
  ) values (
    session.id, session.controller_id, p_position_id, now()
  ) returning * into occupied;

  insert into public.tactical_activity_log(event_type, actor_id, actor_kind, position_id, payload)
  values (
    'position_acquired',
    session.controller_id,
    'controller',
    p_position_id,
    jsonb_build_object('position_session_id', occupied.id)
  );

  return jsonb_build_object('positionSessionId', occupied.id, 'positionId', p_position_id, 'resumed', false);
end;
$$;

revoke all on function public.claim_tactical_position(text, text, boolean) from public, anon;
grant execute on function public.claim_tactical_position(text, text, boolean) to authenticated;
notify pgrst, 'reload schema';
