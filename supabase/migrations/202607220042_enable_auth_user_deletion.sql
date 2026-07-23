-- Permit permanent Auth user deletion without leaving public profile foreign keys
-- in a state that blocks the auth.users -> profiles cascade.
--
-- Nullable historical/audit references retain their row and become NULL.
-- Required ownership references cascade with the account. This migration discovers
-- every current FK referencing public.profiles, including ones added by prior
-- migrations, rather than relying on a fragile hand-maintained table list.

do $$
declare
  fk record;
  local_columns text;
  referenced_columns text;
  all_nullable boolean;
  update_action text;
  match_clause text;
  deferrable_clause text;
begin
  for fk in
    select
      constraint_row.oid,
      table_namespace.nspname as table_schema,
      table_relation.relname as table_name,
      constraint_row.conname,
      constraint_row.conkey,
      constraint_row.confkey,
      constraint_row.confupdtype,
      constraint_row.confmatchtype,
      constraint_row.condeferrable,
      constraint_row.condeferred
    from pg_constraint constraint_row
    join pg_class table_relation on table_relation.oid = constraint_row.conrelid
    join pg_namespace table_namespace on table_namespace.oid = table_relation.relnamespace
    where constraint_row.contype = 'f'
      and constraint_row.confrelid = 'public.profiles'::regclass
  loop
    select
      string_agg(format('%I', attribute_row.attname), ', ' order by key_column.ordinality),
      bool_and(not attribute_row.attnotnull)
    into local_columns, all_nullable
    from unnest(fk.conkey) with ordinality as key_column(attribute_number, ordinality)
    join pg_attribute attribute_row
      on attribute_row.attrelid = (
        select conrelid from pg_constraint where oid = fk.oid
      )
      and attribute_row.attnum = key_column.attribute_number;

    select string_agg(format('%I', attribute_row.attname), ', ' order by key_column.ordinality)
    into referenced_columns
    from unnest(fk.confkey) with ordinality as key_column(attribute_number, ordinality)
    join pg_attribute attribute_row
      on attribute_row.attrelid = 'public.profiles'::regclass
      and attribute_row.attnum = key_column.attribute_number;

    update_action := case fk.confupdtype
      when 'a' then 'NO ACTION'
      when 'r' then 'RESTRICT'
      when 'c' then 'CASCADE'
      when 'n' then 'SET NULL'
      when 'd' then 'SET DEFAULT'
    end;
    match_clause := case fk.confmatchtype
      when 'f' then ' MATCH FULL'
      when 'p' then ' MATCH PARTIAL'
      else ''
    end;
    deferrable_clause := case
      when fk.condeferrable and fk.condeferred then ' DEFERRABLE INITIALLY DEFERRED'
      when fk.condeferrable then ' DEFERRABLE INITIALLY IMMEDIATE'
      else ' NOT DEFERRABLE'
    end;

    execute format(
      'alter table %I.%I drop constraint %I, add constraint %I foreign key (%s) references public.profiles (%s)%s on update %s on delete %s%s',
      fk.table_schema,
      fk.table_name,
      fk.conname,
      fk.conname,
      local_columns,
      referenced_columns,
      match_clause,
      update_action,
      case when all_nullable then 'SET NULL' else 'CASCADE' end,
      deferrable_clause
    );
  end loop;
end;
$$;
