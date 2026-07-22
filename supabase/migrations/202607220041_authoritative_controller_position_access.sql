-- A position is selectable only when the controller has an active operational
-- qualification. Claiming then checks that same authoritative qualification row,
-- instead of reinterpreting a legacy level value a second time.
create or replace function public.open_jscope_session(p_client_version text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  profile public.controller_profiles%rowtype;
  raw_token text;
  created public.jscope_sessions%rowtype;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  select * into profile
  from public.controller_profiles
  where user_id = actor
  for update;

  if not found
    or profile.approval_state not in ('trainee', 'approved', 'instructor')
    or profile.suspended_at is not null then
    raise exception 'JScope controller approval is required';
  end if;

  raw_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.jscope_sessions(controller_id, token_hash, expires_at, client_version)
  values(actor, extensions.digest(raw_token, 'sha256'), now() + interval '30 minutes', left(p_client_version, 40))
  returning * into created;

  return jsonb_build_object(
    'sessionId', created.id,
    'token', raw_token,
    'expiresAt', created.expires_at,
    'callsign', profile.controller_callsign,
    'positions', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', position.id,
        'displayName', position.display_name,
        'radioCallsign', position.radio_callsign,
        'displayFrequency', position.display_frequency,
        'channelId', position.channel_id
      ) order by position.display_name), '[]'::jsonb)
      from public.controller_qualifications qualification
      join public.tactical_positions position on position.id = qualification.position_id
      where qualification.controller_id = actor
        and coalesce(qualification.restricted, false) = false
        and coalesce(qualification.expires_at, 'infinity'::timestamptz) > now()
        and lower(trim(qualification.qualification_level)) in ('trainee', 'qualified', 'instructor')
        and position.active
    )
  );
end;
$$;

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

  if not exists (
    select 1
    from public.controller_qualifications qualification
    where qualification.controller_id = session.controller_id
      and qualification.position_id = p_position_id
      and coalesce(qualification.restricted, false) = false
      and coalesce(qualification.expires_at, 'infinity'::timestamptz) > now()
  ) then
    raise exception 'Position qualification required for %', p_position_id;
  end if;

  select * into profile from public.controller_profiles where user_id = session.controller_id;
  if profile.approval_state = 'trainee' and not exists (
    select 1 from public.instructor_supervision_sessions supervision
    where supervision.trainee_id = session.controller_id
      and supervision.position_id = p_position_id
      and supervision.status = 'active'
  ) then
    raise exception 'Active instructor supervision required';
  end if;

  select * into occupied
  from public.controller_position_sessions
  where position_id = p_position_id and ended_at is null and is_primary
  for update;
  if found then
    if occupied.controller_id <> session.controller_id then
      raise exception 'Position is already occupied';
    end if;
    if occupied.jscope_session_id = session.id then
      update public.controller_position_sessions set last_seen_at = now() where id = occupied.id;
      return jsonb_build_object('positionSessionId', occupied.id, 'positionId', p_position_id, 'resumed', true);
    end if;
    update public.controller_position_sessions
    set ended_at = now(), end_reason = 'Same controller resumed from a new JScope session'
    where id = occupied.id;
  end if;

  insert into public.controller_position_sessions(jscope_session_id, controller_id, position_id, safety_notice_accepted_at)
  values(session.id, session.controller_id, p_position_id, now())
  returning * into occupied;
  return jsonb_build_object('positionSessionId', occupied.id, 'positionId', p_position_id, 'resumed', false);
end;
$$;

create or replace function public.admin_set_controller_access(
  p_user_id uuid,
  p_state text,
  p_callsign text,
  p_position_id text,
  p_level text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  qualification_id uuid;
begin
  if actor is null or not public.has_any_role(actor, array['owner', 'system_administrator']::public.app_role[]) then
    raise exception 'Controller administration permission required';
  end if;
  if p_state not in ('trainee', 'approved', 'instructor', 'suspended', 'revoked')
    or p_level not in ('observer', 'trainee', 'qualified', 'instructor') then
    raise exception 'Invalid controller access state';
  end if;
  if not exists(select 1 from public.tactical_positions where id = p_position_id and active) then
    raise exception 'Tactical position not found';
  end if;

  insert into public.controller_profiles(user_id, approval_state, controller_callsign, approved_at, approved_by, suspended_at, suspension_reason)
  values(p_user_id, p_state, nullif(trim(p_callsign), ''), case when p_state in ('trainee', 'approved', 'instructor') then now() end, actor, case when p_state in ('suspended', 'revoked') then now() end, case when p_state in ('suspended', 'revoked') then 'Administrative action' end)
  on conflict(user_id) do update set
    approval_state = excluded.approval_state,
    controller_callsign = excluded.controller_callsign,
    approved_at = coalesce(public.controller_profiles.approved_at, excluded.approved_at),
    approved_by = actor,
    suspended_at = excluded.suspended_at,
    suspension_reason = excluded.suspension_reason,
    updated_at = now();

  insert into public.controller_qualifications(controller_id, position_id, qualification_level, training_authorized, instructor_endorsed, issued_by, restricted, expires_at)
  values(p_user_id, p_position_id, lower(trim(p_level)), p_level in ('trainee', 'qualified', 'instructor'), p_level = 'instructor', actor, false, null)
  on conflict(controller_id, position_id) do update set
    qualification_level = excluded.qualification_level,
    training_authorized = excluded.training_authorized,
    instructor_endorsed = excluded.instructor_endorsed,
    issued_at = now(),
    expires_at = null,
    issued_by = actor,
    restricted = false,
    restriction_reason = null
  returning id into qualification_id;

  -- Permission changes invalidate cached desktop/controller sessions immediately.
  update public.jscope_sessions
  set revoked_at = now(), revocation_reason = 'Controller access changed'
  where controller_id = p_user_id and revoked_at is null;
  update public.controller_position_sessions
  set ended_at = now(), end_reason = 'Controller access changed'
  where controller_id = p_user_id and ended_at is null;

  return jsonb_build_object('controllerId', p_user_id, 'state', p_state, 'positionId', p_position_id, 'level', lower(trim(p_level)), 'qualificationId', qualification_id);
end;
$$;

revoke all on function public.open_jscope_session(text), public.claim_tactical_position(text, text, boolean), public.admin_set_controller_access(uuid, text, text, text, text) from public, anon;
grant execute on function public.open_jscope_session(text), public.claim_tactical_position(text, text, boolean), public.admin_set_controller_access(uuid, text, text, text, text) to authenticated;
notify pgrst, 'reload schema';
