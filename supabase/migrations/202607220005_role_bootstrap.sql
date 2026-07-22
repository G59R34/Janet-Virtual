-- Repair primary-role/user_roles drift for existing accounts and prevent self-escalation.
insert into public.user_roles(user_id,role,granted_at,active)
select p.id,p.role,now(),true from public.profiles p
where p.role is not null
on conflict(user_id,role) do update set active=true,expires_at=null;

create or replace function public.protect_profile_privileged_fields() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if auth.uid()=old.id and not public.has_any_role(auth.uid(),array['chief_pilot','owner','system_administrator']::public.app_role[]) then
    if new.role is distinct from old.role or new.status is distinct from old.status or new.employee_number is distinct from old.employee_number or new.hire_date is distinct from old.hire_date or new.forced_password_reset is distinct from old.forced_password_reset then
      raise exception 'privileged profile fields cannot be changed by the user';
    end if;
  end if;
  new.updated_at=now(); return new;
end$$;
drop trigger if exists protect_profile_privileged_fields_trigger on public.profiles;
create trigger protect_profile_privileged_fields_trigger before update on public.profiles for each row execute function public.protect_profile_privileged_fields();

create or replace function public.current_access_summary() returns jsonb language sql stable security definer set search_path='' as $$
select jsonb_build_object(
  'user_id',auth.uid(),
  'primary_role',p.role,
  'status',p.status,
  'roles',coalesce((select jsonb_agg(ur.role order by ur.role) from public.user_roles ur where ur.user_id=auth.uid() and ur.active and (ur.expires_at is null or ur.expires_at>now())),'[]'::jsonb)
) from public.profiles p where p.id=auth.uid()
$$;
grant execute on function public.current_access_summary() to authenticated;
