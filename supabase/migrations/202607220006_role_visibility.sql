-- Guarantee that every authenticated user can read their own active grants.
drop policy if exists roles_self_read on public.user_roles;
create policy roles_self_read on public.user_roles for select to authenticated using(user_id=auth.uid());

-- Keep the legacy primary role useful for display when the first non-applicant grant is issued.
create or replace function public.sync_primary_role_from_grant() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.active and new.role<>'applicant' then
    update public.profiles set role=new.role,updated_at=now() where id=new.user_id and role='applicant';
  end if;
  return new;
end$$;
drop trigger if exists sync_primary_role_from_grant_trigger on public.user_roles;
create trigger sync_primary_role_from_grant_trigger after insert or update of role,active on public.user_roles for each row execute function public.sync_primary_role_from_grant();
