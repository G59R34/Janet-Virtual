-- SimBrief planning records and employee integration preferences.
alter table public.profiles
  add column if not exists simbrief_pilot_id text
  check (simbrief_pilot_id is null or simbrief_pilot_id ~ '^[0-9]{1,12}$');

create table if not exists public.simbrief_plans (
  id uuid primary key default gen_random_uuid(),
  flight_id uuid not null unique references public.flights(id) on delete cascade,
  requested_by uuid references public.profiles(id) on delete set null,
  static_id text not null unique,
  status text not null default 'planning' check (status in ('planning','generated','import_failed')),
  simbrief_pilot_id text,
  route text,
  cruise_altitude_ft integer,
  airac text,
  block_fuel numeric,
  trip_fuel numeric,
  estimated_block_minutes integer,
  ofp_url text,
  payload jsonb not null default '{}'::jsonb,
  generated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.simbrief_plans enable row level security;
create policy ops_manage_manual_airports on public.airports for insert
  with check (public.has_any_role(auth.uid(), array['dispatcher','chief_pilot','operations_manager','owner','system_administrator']::public.app_role[]));
create policy simbrief_plan_access on public.simbrief_plans for select
  using (public.can_access_flight(auth.uid(), flight_id));
create policy simbrief_plan_create on public.simbrief_plans for insert
  with check (public.can_access_flight(auth.uid(), flight_id));
create policy simbrief_plan_update on public.simbrief_plans for update
  using (public.can_access_flight(auth.uid(), flight_id))
  with check (public.can_access_flight(auth.uid(), flight_id));

create or replace function public.touch_simbrief_plan_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin new.updated_at = now(); return new; end;
$$;
create trigger simbrief_plans_updated_at before update on public.simbrief_plans
for each row execute function public.touch_simbrief_plan_updated_at();

grant select,insert,update on public.simbrief_plans to authenticated;
notify pgrst, 'reload schema';
