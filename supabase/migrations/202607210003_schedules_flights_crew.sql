-- Recurring schedules, generated flights, status history, and crew records.

create table public.schedule_templates (
  id uuid primary key default gen_random_uuid(),
  service_number text not null check (service_number ~ '^[A-Z0-9-]{2,16}$'),
  route_version_id uuid not null references public.route_versions(id) on delete restrict,
  aircraft_type_id uuid not null references public.aircraft_types(id) on delete restrict,
  departure_local_time time not null,
  block_duration interval not null check (block_duration > interval '0' and block_duration < interval '24 hours'),
  operating_days smallint[] not null check (
    cardinality(operating_days) between 1 and 7
    and operating_days <@ array[0,1,2,3,4,5,6]::smallint[]
  ),
  effective_during daterange not null,
  status public.record_status not null default 'draft',
  default_aircraft_id uuid references public.aircraft(id) on delete set null,
  notes text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (not isempty(effective_during)),
  unique (service_number, route_version_id, lower(effective_during))
);

create table public.schedule_generation_runs (
  id uuid primary key default gen_random_uuid(),
  range_start date not null,
  range_end date not null,
  requested_by uuid references public.profiles(id) on delete set null,
  request_key text not null unique,
  templates_considered integer not null default 0,
  flights_created integer not null default 0,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  error_message text,
  check (range_end >= range_start)
);

create table public.flights (
  id uuid primary key default gen_random_uuid(),
  schedule_template_id uuid references public.schedule_templates(id) on delete set null,
  flight_number text not null check (flight_number ~ '^[A-Z0-9-]{2,20}$'),
  route_version_id uuid not null references public.route_versions(id) on delete restrict,
  origin_airport_id uuid not null references public.airports(id) on delete restrict,
  destination_airport_id uuid not null references public.airports(id) on delete restrict,
  aircraft_type_id uuid not null references public.aircraft_types(id) on delete restrict,
  aircraft_id uuid references public.aircraft(id) on delete set null,
  scheduled_departure timestamptz not null,
  scheduled_arrival timestamptz not null,
  estimated_departure timestamptz,
  estimated_arrival timestamptz,
  actual_departure timestamptz,
  actual_arrival timestamptz,
  status public.flight_status not null default 'scheduled',
  cancellation_reason text,
  gate_out text,
  gate_in text,
  payload_lb integer check (payload_lb is null or payload_lb >= 0),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (origin_airport_id <> destination_airport_id),
  check (scheduled_arrival > scheduled_departure),
  check (actual_arrival is null or actual_departure is null or actual_arrival >= actual_departure),
  unique (schedule_template_id, scheduled_departure)
);

create table public.flight_status_events (
  id bigint generated always as identity primary key,
  flight_id uuid not null references public.flights(id) on delete cascade,
  previous_status public.flight_status,
  new_status public.flight_status not null,
  occurred_at timestamptz not null default now(),
  source text not null default 'manual' check (source in ('manual', 'acars', 'system', 'import')),
  reason text,
  position jsonb,
  recorded_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.crew_qualifications (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  aircraft_type_id uuid not null references public.aircraft_types(id) on delete cascade,
  crew_role public.crew_role not null,
  qualification_code text,
  valid_during daterange not null,
  limitations text,
  document_path text,
  verified_by uuid references public.profiles(id) on delete set null,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (not isempty(valid_during)),
  check ((verified_at is null) = (verified_by is null)),
  exclude using gist (profile_id with =, aircraft_type_id with =, crew_role with =, valid_during with &&)
);

create table public.flight_crew_assignments (
  id uuid primary key default gen_random_uuid(),
  flight_id uuid not null references public.flights(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete restrict,
  crew_role public.crew_role not null,
  report_at timestamptz,
  release_at timestamptz,
  is_confirmed boolean not null default false,
  confirmed_at timestamptz,
  assigned_by uuid references public.profiles(id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (flight_id, profile_id),
  check (release_at is null or report_at is null or release_at > report_at),
  check (not is_confirmed or confirmed_at is not null)
);

create index schedule_templates_active_idx
  on public.schedule_templates(status, lower(effective_during), upper(effective_during));
create index flights_departure_idx on public.flights(scheduled_departure, status);
create index flights_aircraft_time_idx on public.flights(aircraft_id, scheduled_departure) where aircraft_id is not null;
create index flights_route_idx on public.flights(route_version_id, scheduled_departure desc);
create index flight_status_events_history_idx on public.flight_status_events(flight_id, occurred_at desc);
create index crew_qualifications_lookup_idx
  on public.crew_qualifications(profile_id, aircraft_type_id, crew_role, lower(valid_during), upper(valid_during));
create index flight_crew_profile_time_idx on public.flight_crew_assignments(profile_id, flight_id);

create trigger schedule_templates_set_updated_at before update on public.schedule_templates
for each row execute function public.set_updated_at();
create trigger flights_set_updated_at before update on public.flights
for each row execute function public.set_updated_at();
create trigger crew_qualifications_set_updated_at before update on public.crew_qualifications
for each row execute function public.set_updated_at();
create trigger flight_crew_assignments_set_updated_at before update on public.flight_crew_assignments
for each row execute function public.set_updated_at();
