-- ACARS and telemetry ingestion, PIREPs, notifications, and immutable audit history.

create table public.acars_messages (
  id uuid primary key default gen_random_uuid(),
  flight_id uuid references public.flights(id) on delete set null,
  aircraft_id uuid references public.aircraft(id) on delete set null,
  direction public.acars_direction not null,
  message_type text not null,
  message_text text not null,
  raw_payload jsonb not null default '{}'::jsonb check (jsonb_typeof(raw_payload) = 'object'),
  external_message_id text,
  sent_at timestamptz,
  received_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (aircraft_id, external_message_id)
);

create table public.telemetry_points (
  id bigint generated always as identity primary key,
  flight_id uuid not null references public.flights(id) on delete cascade,
  aircraft_id uuid references public.aircraft(id) on delete set null,
  recorded_at timestamptz not null,
  received_at timestamptz not null default now(),
  sequence_number bigint,
  latitude numeric(9,6) check (latitude between -90 and 90),
  longitude numeric(9,6) check (longitude between -180 and 180),
  altitude_ft integer,
  ground_speed_kts integer check (ground_speed_kts is null or ground_speed_kts >= 0),
  heading_degrees numeric(6,3) check (heading_degrees is null or heading_degrees between 0 and 360),
  vertical_speed_fpm integer,
  on_ground boolean,
  fuel_remaining_lb integer check (fuel_remaining_lb is null or fuel_remaining_lb >= 0),
  source text not null default 'acars',
  metrics jsonb not null default '{}'::jsonb check (jsonb_typeof(metrics) = 'object'),
  unique (flight_id, source, sequence_number)
);

create table public.pireps (
  id uuid primary key default gen_random_uuid(),
  flight_id uuid not null references public.flights(id) on delete restrict,
  submitted_by uuid not null references public.profiles(id) on delete restrict,
  status public.pirep_status not null default 'draft',
  block_off_at timestamptz,
  takeoff_at timestamptz,
  landing_at timestamptz,
  block_on_at timestamptz,
  block_time_minutes integer check (block_time_minutes is null or block_time_minutes >= 0),
  flight_time_minutes integer check (flight_time_minutes is null or flight_time_minutes >= 0),
  fuel_used_lb integer check (fuel_used_lb is null or fuel_used_lb >= 0),
  landings smallint not null default 1 check (landings >= 0),
  remarks text,
  score numeric(5,2) check (score is null or score between 0 and 100),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  review_notes text,
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (flight_id, submitted_by),
  check (takeoff_at is null or block_off_at is null or takeoff_at >= block_off_at),
  check (landing_at is null or takeoff_at is null or landing_at >= takeoff_at),
  check (block_on_at is null or landing_at is null or block_on_at >= landing_at),
  check (reviewed_at is null or reviewed_by is not null)
);

create table public.notification_preferences (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  channel public.notification_channel not null,
  event_type text not null,
  enabled boolean not null default true,
  quiet_hours tstzrange,
  destination text,
  updated_at timestamptz not null default now(),
  primary key (profile_id, channel, event_type)
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  channel public.notification_channel not null default 'in_app',
  event_type text not null,
  subject text not null,
  body text not null,
  action_url text,
  status public.notification_status not null default 'pending',
  deduplication_key text,
  scheduled_for timestamptz not null default now(),
  sent_at timestamptz,
  read_at timestamptz,
  attempts smallint not null default 0 check (attempts >= 0),
  last_error text,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  created_at timestamptz not null default now()
);

create unique index notifications_deduplication_uidx
  on public.notifications(recipient_id, channel, deduplication_key)
  where deduplication_key is not null;

create table public.audit_logs (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default clock_timestamp(),
  actor_id uuid,
  actor_role text,
  action text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  schema_name text not null,
  table_name text not null,
  record_id text,
  old_data jsonb,
  new_data jsonb,
  request_id text,
  client_address inet default inet_client_addr(),
  transaction_id bigint not null default txid_current()
);

create index acars_messages_flight_time_idx on public.acars_messages(flight_id, received_at desc);
create index acars_messages_aircraft_time_idx on public.acars_messages(aircraft_id, received_at desc);
create index telemetry_points_flight_time_idx on public.telemetry_points(flight_id, recorded_at);
create index telemetry_points_recorded_brin_idx on public.telemetry_points using brin(recorded_at);
create index pireps_submitter_idx on public.pireps(submitted_by, created_at desc);
create index notifications_delivery_idx on public.notifications(status, scheduled_for) where status = 'pending';
create index notifications_recipient_idx on public.notifications(recipient_id, created_at desc);
create index audit_logs_record_idx on public.audit_logs(table_name, record_id, occurred_at desc);
create index audit_logs_actor_idx on public.audit_logs(actor_id, occurred_at desc);
create index audit_logs_time_brin_idx on public.audit_logs using brin(occurred_at);

create trigger pireps_set_updated_at before update on public.pireps
for each row execute function public.set_updated_at();
create trigger notification_preferences_set_updated_at before update on public.notification_preferences
for each row execute function public.set_updated_at();

create function public.write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  old_row jsonb;
  new_row jsonb;
  row_id text;
begin
  old_row := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end;
  new_row := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end;
  row_id := coalesce(new_row ->> 'id', old_row ->> 'id', new_row ->> 'profile_id', old_row ->> 'profile_id');

  insert into public.audit_logs (
    actor_id, actor_role, action, schema_name, table_name, record_id,
    old_data, new_data, request_id
  ) values (
    auth.uid(), auth.role(), tg_op, tg_table_schema, tg_table_name, row_id,
    old_row, new_row, current_setting('request.headers', true)::jsonb ->> 'x-request-id'
  );

  return coalesce(new, old);
end;
$$;

revoke all on function public.write_audit_log() from public;

create function public.prevent_audit_log_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  raise exception 'audit logs are immutable' using errcode = '55000';
end;
$$;

create trigger audit_logs_immutable
before update or delete on public.audit_logs
for each row execute function public.prevent_audit_log_mutation();

-- Telemetry is intentionally omitted: auditing each point would double high-volume writes.
do $audit_triggers$
declare
  table_name text;
begin
  foreach table_name in array array[
    'profiles', 'user_roles', 'membership_applications', 'airports', 'stations',
    'station_memberships', 'routes', 'route_versions', 'route_waypoints',
    'aircraft_types', 'aircraft', 'schedule_templates', 'flights',
    'crew_qualifications', 'flight_crew_assignments', 'missions', 'mission_legs',
    'personnel', 'mission_personnel', 'manifests', 'manifest_entries',
    'dispatch_releases', 'maintenance_discrepancies', 'maintenance_work_orders',
    'maintenance_actions', 'acars_messages', 'pireps', 'notification_preferences'
  ] loop
    execute format(
      'create trigger %I after insert or update or delete on public.%I for each row execute function public.write_audit_log()',
      table_name || '_audit', table_name
    );
  end loop;
end;
$audit_triggers$;
