-- Stable single-signature gateway for PostgREST plus explicit schema-cache refresh.
create or replace function public.admin_action(p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare action_name text:=p_payload->>'action'; result_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  case action_name
    when 'review_application' then
      perform public.review_application((p_payload->>'applicationId')::uuid,p_payload->>'status',p_payload->>'notes');
    when 'set_status' then
      perform public.set_user_operational_status((p_payload->>'userId')::uuid,p_payload->>'status',p_payload->>'reason');
    when 'grant_role' then
      perform public.admin_grant_role((p_payload->>'userId')::uuid,p_payload->>'role',nullif(p_payload->>'expiresAt','')::timestamptz);
    when 'issue_qualification' then
      perform public.issue_qualification((p_payload->>'userId')::uuid,(p_payload->>'qualificationId')::uuid,nullif(p_payload->>'expiresAt','')::timestamptz);
    when 'assign_crew' then
      result_id:=public.assign_crew_member((p_payload->>'flightId')::uuid,(p_payload->>'userId')::uuid,p_payload->>'position');
    else raise exception 'unsupported administrative action';
  end case;
  return jsonb_build_object('ok',true,'id',result_id);
end$$;
revoke all on function public.admin_action(jsonb) from public,anon;
grant execute on function public.admin_action(jsonb) to authenticated;
notify pgrst,'reload schema';
