-- Forward-only repair for environments where migration 032 was applied before
-- the controller administration RPC was added to its final form.
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
  if actor is null or not public.has_any_role(actor, array['owner','system_administrator']::public.app_role[]) then
    raise exception 'Controller administration permission required';
  end if;
  if p_state not in ('trainee','approved','instructor','suspended','revoked') then raise exception 'Invalid controller state'; end if;
  if p_level not in ('observer','trainee','qualified','instructor') then raise exception 'Invalid qualification level'; end if;
  if not exists(select 1 from public.profiles where id=p_user_id) then raise exception 'Controller identity not found'; end if;
  if not exists(select 1 from public.tactical_positions where id=p_position_id and active) then raise exception 'Tactical position not found'; end if;

  insert into public.controller_profiles(user_id,approval_state,controller_callsign,approved_at,approved_by,suspended_at,suspension_reason)
  values(p_user_id,p_state,nullif(trim(p_callsign),''),case when p_state in ('trainee','approved','instructor') then now() end,actor,case when p_state in ('suspended','revoked') then now() end,case when p_state in ('suspended','revoked') then 'Administrative action' end)
  on conflict(user_id) do update set approval_state=excluded.approval_state,controller_callsign=excluded.controller_callsign,approved_at=coalesce(public.controller_profiles.approved_at,excluded.approved_at),approved_by=actor,suspended_at=excluded.suspended_at,suspension_reason=excluded.suspension_reason,updated_at=now();

  insert into public.controller_qualifications(controller_id,position_id,qualification_level,training_authorized,instructor_endorsed,issued_by)
  values(p_user_id,p_position_id,p_level,p_level in ('trainee','qualified','instructor'),p_level='instructor',actor)
  on conflict(controller_id,position_id) do update set qualification_level=excluded.qualification_level,training_authorized=excluded.training_authorized,instructor_endorsed=excluded.instructor_endorsed,issued_at=now(),expires_at=null,issued_by=actor,restricted=false,restriction_reason=null
  returning id into qualification_id;

  if p_state in ('suspended','revoked') then
    update public.jscope_sessions set revoked_at=now(),revocation_reason='Controller access '||p_state where controller_id=p_user_id and revoked_at is null;
    update public.controller_position_sessions set ended_at=now(),end_reason='Controller access '||p_state where controller_id=p_user_id and ended_at is null;
  end if;

  insert into public.tactical_activity_log(event_type,actor_id,actor_kind,payload)
  values('controller_access_changed',actor,'administrator',jsonb_build_object('controller_id',p_user_id,'state',p_state,'position_id',p_position_id,'level',p_level));
  return jsonb_build_object('controllerId',p_user_id,'state',p_state,'positionId',p_position_id,'level',p_level,'qualificationId',qualification_id);
end
$$;

revoke all on function public.admin_set_controller_access(uuid,text,text,text,text) from public, anon;
grant execute on function public.admin_set_controller_access(uuid,text,text,text,text) to authenticated;
notify pgrst, 'reload schema';
