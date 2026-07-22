-- Airports, stations, versioned routes, and fleet registry.

create table public.airports (
  id uuid primary key default gen_random_uuid(),
  icao_code text not null unique check (icao_code ~ '^[A-Z0-9]{4}$'),
  iata_code text unique check (iata_code is null or iata_code ~ '^[A-Z0-9]{3}$'),
  faa_code text unique,
  name text not null,
  city text,
  region_code text,
  country_code char(2) not null default 'US' check (country_code ~ '^[A-Z]{2}$'),
  latitude numeric(9,6) not null check (latitude between -90 and 90),
  longitude numeric(9,6) not null check (longitude between -180 and 180),
  elevation_ft integer,
  timezone text not null,
  is_sensitive boolean not null default false,
  status public.record_status not null default 'active',
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.stations (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9]{2,12}$'),
  name text not null,
  airport_id uuid not null references public.airports(id) on delete restrict,
  manager_id uuid references public.profiles(id) on delete set null,
  status public.record_status not null default 'active',
  opened_on date,
  closed_on date,
  contact_details jsonb not null default '{}'::jsonb check (jsonb_typeof(contact_details) = 'object'),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (closed_on is null or opened_on is null or closed_on >= opened_on)
);

create table public.station_memberships (
  station_id uuid not null references public.stations(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  is_primary boolean not null default false,
  assigned_at timestamptz not null default now(),
  assigned_by uuid references public.profiles(id) on delete set null,
  primary key (station_id, profile_id)
);

create unique index station_memberships_one_primary_uidx
  on public.station_memberships(profile_id) where is_primary;

create table public.routes (
  id uuid primary key default gen_random_uuid(),
  route_code text not null unique check (route_code ~ '^[A-Z0-9-]{2,20}$'),
  origin_airport_id uuid not null references public.airports(id) on delete restrict,
  destination_airport_id uuid not null references public.airports(id) on delete restrict,
  status public.record_status not null default 'draft',
  current_version_id uuid,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (origin_airport_id <> destination_airport_id)
);

create table public.route_versions (
  id uuid primary key default gen_random_uuid(),
  route_id uuid not null references public.routes(id) on delete cascade,
  version_number integer not null check (version_number > 0),
  valid_during daterange not null,
  distance_nm numeric(8,2) check (distance_nm > 0),
  planned_duration interval not null check (planned_duration > interval '0'),
  minimum_altitude_ft integer check (minimum_altitude_ft is null or minimum_altitude_ft >= 0),
  standard_route text,
  notes text,
  is_published boolean not null default false,
  created_by uuid references public.profiles(id) on delete set null,
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  unique (route_id, version_number),
  check (not isempty(valid_during)),
  check ((approved_at is null) = (approved_by is null)),
  exclude using gist (route_id with =, valid_during with &&) where (is_published)
);

alter table public.routes
  add constraint routes_current_version_fk
  foreign key (current_version_id) references public.route_versions(id) on delete set null;

create table public.route_waypoints (
  id uuid primary key default gen_random_uuid(),
  route_version_id uuid not null references public.route_versions(id) on delete cascade,
  sequence_number smallint not null check (sequence_number > 0),
  identifier text not null,
  waypoint_type text not null default 'fix' check (waypoint_type in ('airport', 'fix', 'navaid', 'coordinate')),
  latitude numeric(9,6) check (latitude between -90 and 90),
  longitude numeric(9,6) check (longitude between -180 and 180),
  airway text,
  altitude_constraint_ft integer,
  notes text,
  unique (route_version_id, sequence_number)
);

create table public.aircraft_types (
  id uuid primary key default gen_random_uuid(),
  icao_type_code text not null unique check (icao_type_code ~ '^[A-Z0-9]{2,4}$'),
  manufacturer text not null,
  model text not null,
  variant text,
  passenger_capacity smallint not null default 0 check (passenger_capacity >= 0),
  crew_capacity smallint not null default 2 check (crew_capacity > 0),
  max_takeoff_weight_lb integer check (max_takeoff_weight_lb > 0),
  cruise_speed_kts integer check (cruise_speed_kts > 0),
  range_nm integer check (range_nm > 0),
  equipment jsonb not null default '{}'::jsonb check (jsonb_typeof(equipment) = 'object'),
  status public.record_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.aircraft (
  id uuid primary key default gen_random_uuid(),
  registration text not null unique check (registration ~ '^[A-Z0-9-]{3,12}$'),
  serial_number text unique,
  aircraft_type_id uuid not null references public.aircraft_types(id) on delete restrict,
  home_station_id uuid references public.stations(id) on delete set null,
  status public.aircraft_operational_status not null default 'available',
  airworthiness_expires_on date,
  total_time_hours numeric(12,2) not null default 0 check (total_time_hours >= 0),
  total_cycles integer not null default 0 check (total_cycles >= 0),
  livery text,
  notes text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.aircraft_status_events (
  id bigint generated always as identity primary key,
  aircraft_id uuid not null references public.aircraft(id) on delete cascade,
  previous_status public.aircraft_operational_status,
  new_status public.aircraft_operational_status not null,
  reason text,
  effective_at timestamptz not null default now(),
  recorded_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index airports_location_idx on public.airports(latitude, longitude);
create index stations_airport_idx on public.stations(airport_id);
create index routes_airports_idx on public.routes(origin_airport_id, destination_airport_id);
create index route_versions_route_published_idx on public.route_versions(route_id, is_published, lower(valid_during));
create index aircraft_type_status_idx on public.aircraft(aircraft_type_id, status);
create index aircraft_status_events_history_idx on public.aircraft_status_events(aircraft_id, effective_at desc);

create trigger airports_set_updated_at before update on public.airports
for each row execute function public.set_updated_at();
create trigger stations_set_updated_at before update on public.stations
for each row execute function public.set_updated_at();
create trigger routes_set_updated_at before update on public.routes
for each row execute function public.set_updated_at();
create trigger aircraft_types_set_updated_at before update on public.aircraft_types
for each row execute function public.set_updated_at();
create trigger aircraft_set_updated_at before update on public.aircraft
for each row execute function public.set_updated_at();
