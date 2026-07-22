-- JANET Virtual Airline Ecosystem: core types, identities, roles, and applications.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists citext with schema extensions;
create extension if not exists btree_gist with schema extensions;

create type public.app_role as enum (
  'administrator',
  'operations_manager',
  'dispatcher',
  'station_manager',
  'pilot',
  'flight_attendant',
  'maintenance',
  'mission_planner',
  'auditor'
);

create type public.application_status as enum (
  'draft', 'submitted', 'under_review', 'accepted', 'rejected', 'withdrawn'
);

create type public.record_status as enum ('draft', 'active', 'inactive', 'archived');
create type public.aircraft_operational_status as enum (
  'available', 'assigned', 'in_service', 'maintenance', 'grounded', 'retired'
);
create type public.crew_role as enum ('captain', 'first_officer', 'flight_attendant', 'observer', 'relief_pilot');
create type public.flight_status as enum (
  'scheduled', 'boarding', 'departed', 'enroute', 'arrived', 'completed',
  'delayed', 'cancelled', 'diverted'
);
create type public.release_status as enum ('draft', 'released', 'accepted', 'superseded', 'cancelled');
create type public.maintenance_status as enum ('open', 'deferred', 'in_progress', 'closed', 'cancelled');
create type public.maintenance_severity as enum ('information', 'minor', 'major', 'grounding');
create type public.mission_status as enum ('planning', 'approved', 'active', 'completed', 'cancelled');
create type public.notification_channel as enum ('in_app', 'email', 'sms', 'webhook');
create type public.notification_status as enum ('pending', 'sent', 'failed', 'read', 'cancelled');
create type public.acars_direction as enum ('uplink', 'downlink');
create type public.pirep_status as enum ('draft', 'submitted', 'accepted', 'rejected', 'amended');

create sequence public.employee_number_seq start with 1001;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  employee_number text not null unique default ('JVA-' || lpad(nextval('public.employee_number_seq')::text, 5, '0')),
  display_name text not null check (length(trim(display_name)) between 2 and 100),
  legal_name text,
  callsign text unique,
  email extensions.citext,
  phone text,
  timezone text not null default 'UTC',
  avatar_path text,
  status public.record_status not null default 'active',
  hired_on date,
  last_seen_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_roles (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  role public.app_role not null,
  granted_by uuid references public.profiles(id) on delete set null,
  granted_at timestamptz not null default now(),
  expires_at timestamptz,
  notes text,
  primary key (profile_id, role),
  check (expires_at is null or expires_at > granted_at)
);

create table public.membership_applications (
  id uuid primary key default gen_random_uuid(),
  applicant_id uuid references public.profiles(id) on delete set null,
  email extensions.citext not null,
  display_name text not null,
  requested_roles public.app_role[] not null default array['pilot']::public.app_role[],
  experience jsonb not null default '{}'::jsonb check (jsonb_typeof(experience) = 'object'),
  motivation text,
  status public.application_status not null default 'draft',
  submitted_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  review_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (cardinality(requested_roles) > 0),
  check ((status in ('submitted', 'under_review', 'accepted', 'rejected')) = (submitted_at is not null)),
  check (reviewed_at is null or reviewed_by is not null)
);

create index user_roles_active_lookup_idx
  on public.user_roles (profile_id, role) where expires_at is null;
create index membership_applications_status_idx
  on public.membership_applications (status, submitted_at desc);
create unique index membership_applications_open_email_uidx
  on public.membership_applications (email)
  where status in ('draft', 'submitted', 'under_review');

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger membership_applications_set_updated_at
before update on public.membership_applications
for each row execute function public.set_updated_at();

create function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  insert into public.profiles (id, display_name, email)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(coalesce(new.email, 'member'), '@', 1)),
    new.email
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function public.handle_new_auth_user() from public;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();
