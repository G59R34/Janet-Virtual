-- Missions and manifests, dispatch releases, and maintenance control.

create table public.missions (
  id uuid primary key default gen_random_uuid(),
  mission_code text not null unique check (mission_code ~ '^[A-Z0-9-]{3,24}$'),
  title text not null,
  description text,
  classification text not null default 'internal' check (classification in ('public', 'internal', 'restricted')),
  status public.mission_status not null default 'planning',
  priority smallint not null default 3 check (priority between 1 and 5),
  owning_station_id uuid references public.stations(id) on delete set null,
  starts_at timestamptz,
  ends_at timestamptz,
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at >= starts_at),
  check ((approved_at is null) = (approved_by is null))
);

create table public.mission_legs (
  id uuid primary key default gen_random_uuid(),
  mission_id uuid not null references public.missions(id) on delete cascade,
  sequence_number smallint not null check (sequence_number > 0),
  flight_id uuid references public.flights(id) on delete set null,
  origin_airport_id uuid not null references public.airports(id) on delete restrict,
  destination_airport_id uuid not null references public.airports(id) on delete restrict,
  planned_departure timestamptz,
  planned_arrival timestamptz,
  purpose text,
  notes text,
  unique (mission_id, sequence_number),
  check (origin_airport_id <> destination_airport_id),
  check (planned_arrival is null or planned_departure is null or planned_arrival > planned_departure)
);

create table public.personnel (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid unique references public.profiles(id) on delete set null,
  external_reference text unique,
  display_name text not null,
  organization text,
  personnel_type text not null default 'passenger' check (personnel_type in ('crew', 'passenger', 'escort', 'detainee', 'other')),
  citizenship_code char(2) check (citizenship_code is null or citizenship_code ~ '^[A-Z]{2}$'),
  date_of_birth date,
  emergency_details jsonb not null default '{}'::jsonb check (jsonb_typeof(emergency_details) = 'object'),
  medical_notes text,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (profile_id is not null or external_reference is not null)
);

create table public.mission_personnel (
  mission_id uuid not null references public.missions(id) on delete cascade,
  personnel_id uuid not null references public.personnel(id) on delete restrict,
  mission_role text,
  clearance_confirmed boolean not null default false,
  added_by uuid references public.profiles(id) on delete set null,
  added_at timestamptz not null default now(),
  primary key (mission_id, personnel_id)
);

create table public.manifests (
  id uuid primary key default gen_random_uuid(),
  flight_id uuid not null references public.flights(id) on delete cascade,
  mission_id uuid references public.missions(id) on delete set null,
  version_number integer not null check (version_number > 0),
  is_final boolean not null default false,
  finalized_by uuid references public.profiles(id) on delete set null,
  finalized_at timestamptz,
  notes text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (flight_id, version_number),
  check ((finalized_at is null) = (finalized_by is null)),
  check (not is_final or finalized_at is not null)
);

create unique index manifests_one_final_per_flight_uidx
  on public.manifests(flight_id) where is_final;

create table public.manifest_entries (
  id uuid primary key default gen_random_uuid(),
  manifest_id uuid not null references public.manifests(id) on delete cascade,
  personnel_id uuid not null references public.personnel(id) on delete restrict,
  seat text,
  boarding_status text not null default 'expected' check (boarding_status in ('expected', 'boarded', 'no_show', 'offloaded')),
  baggage_weight_lb integer check (baggage_weight_lb is null or baggage_weight_lb >= 0),
  special_requirements text,
  boarded_at timestamptz,
  unique (manifest_id, personnel_id),
  unique (manifest_id, seat)
);

create table public.dispatch_releases (
  id uuid primary key default gen_random_uuid(),
  flight_id uuid not null references public.flights(id) on delete cascade,
  version_number integer not null check (version_number > 0),
  status public.release_status not null default 'draft',
  route_version_id uuid not null references public.route_versions(id) on delete restrict,
  alternate_airport_id uuid references public.airports(id) on delete restrict,
  planned_fuel_lb integer check (planned_fuel_lb is null or planned_fuel_lb > 0),
  reserve_fuel_lb integer check (reserve_fuel_lb is null or reserve_fuel_lb >= 0),
  weather_snapshot jsonb not null default '{}'::jsonb check (jsonb_typeof(weather_snapshot) = 'object'),
  notams jsonb not null default '[]'::jsonb check (jsonb_typeof(notams) = 'array'),
  remarks text,
  document_path text,
  dispatcher_id uuid references public.profiles(id) on delete set null,
  released_at timestamptz,
  accepted_by uuid references public.profiles(id) on delete set null,
  accepted_at timestamptz,
  supersedes_id uuid references public.dispatch_releases(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (flight_id, version_number),
  check (accepted_at is null or accepted_by is not null),
  check (released_at is null or dispatcher_id is not null)
);

create unique index dispatch_releases_one_current_uidx
  on public.dispatch_releases(flight_id) where status in ('released', 'accepted');

create table public.maintenance_discrepancies (
  id uuid primary key default gen_random_uuid(),
  aircraft_id uuid not null references public.aircraft(id) on delete restrict,
  flight_id uuid references public.flights(id) on delete set null,
  ata_chapter text,
  title text not null,
  description text not null,
  severity public.maintenance_severity not null default 'minor',
  status public.maintenance_status not null default 'open',
  reported_by uuid references public.profiles(id) on delete set null,
  reported_at timestamptz not null default now(),
  deferred_until timestamptz,
  deferral_reference text,
  closed_by uuid references public.profiles(id) on delete set null,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (closed_at is null or closed_by is not null),
  check (status <> 'deferred' or deferred_until is not null)
);

create table public.maintenance_work_orders (
  id uuid primary key default gen_random_uuid(),
  work_order_number text not null unique,
  aircraft_id uuid not null references public.aircraft(id) on delete restrict,
  discrepancy_id uuid references public.maintenance_discrepancies(id) on delete set null,
  title text not null,
  description text,
  status public.maintenance_status not null default 'open',
  opened_at timestamptz not null default now(),
  due_at timestamptz,
  completed_at timestamptz,
  assigned_to uuid references public.profiles(id) on delete set null,
  opened_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (completed_at is null or completed_at >= opened_at)
);

create table public.maintenance_actions (
  id bigint generated always as identity primary key,
  work_order_id uuid not null references public.maintenance_work_orders(id) on delete cascade,
  action_type text not null check (action_type in ('inspection', 'repair', 'replacement', 'test', 'deferral', 'signoff', 'note')),
  description text not null,
  parts_used jsonb not null default '[]'::jsonb check (jsonb_typeof(parts_used) = 'array'),
  labor_hours numeric(7,2) check (labor_hours is null or labor_hours >= 0),
  performed_by uuid references public.profiles(id) on delete set null,
  inspected_by uuid references public.profiles(id) on delete set null,
  performed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index missions_status_time_idx on public.missions(status, starts_at);
create index mission_legs_flight_idx on public.mission_legs(flight_id) where flight_id is not null;
create index manifest_entries_manifest_idx on public.manifest_entries(manifest_id, boarding_status);
create index dispatch_releases_flight_idx on public.dispatch_releases(flight_id, version_number desc);
create index maintenance_discrepancies_aircraft_idx on public.maintenance_discrepancies(aircraft_id, status, reported_at desc);
create index maintenance_work_orders_aircraft_idx on public.maintenance_work_orders(aircraft_id, status, due_at);
create index maintenance_actions_work_order_idx on public.maintenance_actions(work_order_id, performed_at desc);

create trigger missions_set_updated_at before update on public.missions
for each row execute function public.set_updated_at();
create trigger personnel_set_updated_at before update on public.personnel
for each row execute function public.set_updated_at();
create trigger dispatch_releases_set_updated_at before update on public.dispatch_releases
for each row execute function public.set_updated_at();
create trigger maintenance_discrepancies_set_updated_at before update on public.maintenance_discrepancies
for each row execute function public.set_updated_at();
create trigger maintenance_work_orders_set_updated_at before update on public.maintenance_work_orders
for each row execute function public.set_updated_at();
