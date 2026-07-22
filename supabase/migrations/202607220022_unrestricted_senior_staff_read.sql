-- Owners and system administrators can inspect every RLS-protected public table.
-- Mutation rules remain capability-specific.
create or replace function public.has_unrestricted_read_access(p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path=''
as $$select public.has_any_role(p_user,array['owner','system_administrator']::public.app_role[])$$;
revoke all on function public.has_unrestricted_read_access(uuid) from public,anon;
grant execute on function public.has_unrestricted_read_access(uuid) to authenticated;

do $$
declare target record;
begin
  for target in
    select n.nspname schema_name,c.relname table_name
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind in ('r','p') and c.relrowsecurity
  loop
    execute format('drop policy if exists senior_staff_unrestricted_read on %I.%I',target.schema_name,target.table_name);
    execute format('create policy senior_staff_unrestricted_read on %I.%I for select to authenticated using (public.has_unrestricted_read_access(auth.uid()))',target.schema_name,target.table_name);
  end loop;
end$$;
notify pgrst,'reload schema';
