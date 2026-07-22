-- Authorization helpers and transactional domain APIs.

create function public.current_profile_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select auth.uid()
$$;

create function public.has_role(requested_role public.app_role)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.user_roles ur
    where ur.profile_id = auth.uid()
      and ur.role = requested_role
      and (ur.expires_at is null or ur.expires_at > now())
  )
$$;

create function public.has_any_role(requested_roles public.app_role[])
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.user_roles ur
    where ur.profile_id = auth.uid()
      and ur.role = any(requested_roles)
      and (ur.expires_at is null or ur.expires_at > now())
  )
$$;

create function public.is_service_role()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(auth.role() = 'service_role', false)
$$;

create function public.can_manage_operations()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select public.is_service_role() or public.has_any_role(array[
    'administrator', 'operations_manager', 'dispatcher'
  ]::public.app_role[])
$$;

create function public.can_manage_people()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select public.is_service_role() or public.has_any_role(array[
    'administrator', 'operations_manager', 'mission_planner'
  ]::public.app_role[])
$$;

create function public.can_manage_maintenance()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select public.is_service_role() or public.has_any_role(array[
    'administrator', 'operations_manager', 'maintenance'
  ]::public.app_role[])
$$;

create function public.is_assigned_to_flight(requested_flight_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.flight_crew_assignments fca
    where fca.flight_id = requested_flight_id and fca.profile_id = auth.uid()
  )
$$;

create function public.validate_route_current_version()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.current_version_id is not null and not exists (
    select 1 from public.route_versions rv
    where rv.id = new.current_version_id
      and rv.route_id = new.id
      and rv.is_published
  ) then
    raise exception 'current route version must be a published version of this route'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger routes_validate_current_version
before insert or update of current_version_id on public.routes
for each row execute function public.validate_route_current_version();

create function public.validate_schedule_template()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if not exists (
    select 1 from public.route_versions rv
    where rv.id = new.route_version_id
      and rv.is_published
      and new.effective_during <@ rv.valid_during
  ) then
    raise exception 'schedule requires a published route version valid for its full effective range'
      using errcode = '23514';
  end if;

  if new.default_aircraft_id is not null and not exists (
    select 1 from public.aircraft a
    where a.id = new.default_aircraft_id
      and a.aircraft_type_id = new.aircraft_type_id
      and a.status not in ('grounded', 'maintenance', 'retired')
  ) then
    raise exception 'default aircraft is unavailable or does not match the scheduled type'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger schedule_templates_validate
before insert or update on public.schedule_templates
for each row execute function public.validate_schedule_template();

create function public.validate_flight()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  route_origin uuid;
  route_destination uuid;
  route_validity daterange;
  assigned_type uuid;
  assigned_status public.aircraft_operational_status;
  airworthiness_date date;
begin
  select r.origin_airport_id, r.destination_airport_id, rv.valid_during
  into route_origin, route_destination, route_validity
  from public.route_versions rv
  join public.routes r on r.id = rv.route_id
  where rv.id = new.route_version_id and rv.is_published;

  if not found or route_origin <> new.origin_airport_id or route_destination <> new.destination_airport_id then
    raise exception 'flight airports must match a published route version' using errcode = '23514';
  end if;

  if not (new.scheduled_departure::date <@ route_validity) then
    raise exception 'flight departure falls outside route version validity' using errcode = '23514';
  end if;

  if new.aircraft_id is not null then
    select a.aircraft_type_id, a.status, a.airworthiness_expires_on
    into assigned_type, assigned_status, airworthiness_date
    from public.aircraft a where a.id = new.aircraft_id;

    if assigned_type <> new.aircraft_type_id or assigned_status in ('grounded', 'maintenance', 'retired') then
      raise exception 'assigned aircraft is unavailable or has the wrong type' using errcode = '23514';
    end if;
    if airworthiness_date is not null and airworthiness_date < new.scheduled_departure::date then
      raise exception 'aircraft airworthiness expires before departure' using errcode = '23514';
    end if;
    if exists (
      select 1 from public.flights f
      where f.aircraft_id = new.aircraft_id
        and f.id <> new.id
        and f.status not in ('cancelled', 'completed')
        and tstzrange(f.scheduled_departure, f.scheduled_arrival, '[)') &&
            tstzrange(new.scheduled_departure, new.scheduled_arrival, '[)')
    ) then
      raise exception 'aircraft has an overlapping flight assignment' using errcode = '23P01';
    end if;
  end if;
  return new;
end;
$$;

create trigger flights_validate
before insert or update of route_version_id, origin_airport_id, destination_airport_id,
  aircraft_type_id, aircraft_id, scheduled_departure, scheduled_arrival
on public.flights
for each row execute function public.validate_flight();

create function public.validate_flight_status_transition()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.status = old.status then return new; end if;
  if not (
    (old.status = 'scheduled' and new.status in ('boarding', 'delayed', 'cancelled')) or
    (old.status = 'delayed' and new.status in ('scheduled', 'boarding', 'departed', 'cancelled')) or
    (old.status = 'boarding' and new.status in ('departed', 'delayed', 'cancelled')) or
    (old.status = 'departed' and new.status in ('enroute', 'diverted', 'arrived')) or
    (old.status = 'enroute' and new.status in ('diverted', 'arrived')) or
    (old.status = 'diverted' and new.status in ('arrived', 'cancelled')) or
    (old.status = 'arrived' and new.status = 'completed')
  ) then
    raise exception 'invalid flight status transition: % -> %', old.status, new.status
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger flights_validate_status_transition
before update of status on public.flights
for each row execute function public.validate_flight_status_transition();

create function public.record_flight_status_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.flight_status_events (
      flight_id, previous_status, new_status, occurred_at, source, recorded_by
    ) values (
      new.id, case when tg_op = 'UPDATE' then old.status else null end,
      new.status, now(), 'system', auth.uid()
    );
  end if;
  return new;
end;
$$;

revoke all on function public.record_flight_status_event() from public;
create trigger flights_record_status
  after insert or update of status on public.flights
  for each row execute function public.record_flight_status_event();

create function public.record_aircraft_status_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.aircraft_status_events (
      aircraft_id, previous_status, new_status, recorded_by
    ) values (
      new.id, case when tg_op = 'UPDATE' then old.status else null end,
      new.status, auth.uid()
    );
  end if;
  return new;
end;
$$;

revoke all on function public.record_aircraft_status_event() from public;
create trigger aircraft_record_status
  after insert or update of status on public.aircraft
  for each row execute function public.record_aircraft_status_event();

create function public.validate_crew_assignment()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  target_flight public.flights%rowtype;
  duty_start timestamptz;
  duty_end timestamptz;
begin
  select * into target_flight from public.flights where id = new.flight_id;
  duty_start := coalesce(new.report_at, target_flight.scheduled_departure - interval '1 hour');
  duty_end := coalesce(new.release_at, target_flight.scheduled_arrival + interval '30 minutes');

  if not exists (
    select 1 from public.crew_qualifications cq
    where cq.profile_id = new.profile_id
      and cq.aircraft_type_id = target_flight.aircraft_type_id
      and cq.crew_role = new.crew_role
      and target_flight.scheduled_departure::date <@ cq.valid_during
      and cq.verified_at is not null
  ) then
    raise exception 'crew member lacks a verified qualification valid at departure'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.flight_crew_assignments other
    join public.flights f on f.id = other.flight_id
    where other.profile_id = new.profile_id
      and other.id <> new.id
      and f.status not in ('cancelled', 'completed')
      and tstzrange(
        coalesce(other.report_at, f.scheduled_departure - interval '1 hour'),
        coalesce(other.release_at, f.scheduled_arrival + interval '30 minutes'), '[)'
      ) && tstzrange(duty_start, duty_end, '[)')
  ) then
    raise exception 'crew member has an overlapping duty assignment' using errcode = '23P01';
  end if;
  return new;
end;
$$;

create trigger flight_crew_assignments_validate
before insert or update on public.flight_crew_assignments
for each row execute function public.validate_crew_assignment();

create function public.prevent_final_manifest_changes()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  target_manifest_id uuid;
begin
  target_manifest_id := coalesce(new.manifest_id, old.manifest_id);
  if exists (select 1 from public.manifests m where m.id = target_manifest_id and m.is_final) then
    raise exception 'finalized manifests are immutable; create a new version'
      using errcode = '55000';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger manifest_entries_protect_final
before insert or update or delete on public.manifest_entries
for each row execute function public.prevent_final_manifest_changes();

create function public.prevent_manifest_reopen()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if old.is_final and (not new.is_final or new.finalized_at is distinct from old.finalized_at) then
    raise exception 'finalized manifests are immutable; create a new version' using errcode = '55000';
  end if;
  return new;
end;
$$;

create trigger manifests_protect_final
before update on public.manifests
for each row execute function public.prevent_manifest_reopen();

create function public.publish_route_version(requested_version_id uuid)
returns public.route_versions
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  published public.route_versions;
begin
  if not public.can_manage_operations() then raise exception 'not authorized' using errcode = '42501'; end if;

  select * into published from public.route_versions where id = requested_version_id for update;
  if not found then raise exception 'route version not found' using errcode = 'P0002'; end if;

  update public.route_versions
  set is_published = true, approved_by = auth.uid(), approved_at = now()
  where id = requested_version_id
  returning * into published;

  update public.routes
  set current_version_id = published.id, status = 'active'
  where id = published.route_id;

  return published;
end;
$$;

create function public.generate_scheduled_flights(range_start date, range_end date)
returns table (generation_run_id uuid, created_count integer)
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  run_key text;
  run_id uuid;
  existing_count integer;
  template_count integer;
  inserted_count integer;
begin
  if not public.can_manage_operations() then raise exception 'not authorized' using errcode = '42501'; end if;
  if range_start is null or range_end is null or range_end < range_start or range_end > range_start + 366 then
    raise exception 'generation range must be between 1 and 367 days' using errcode = '22007';
  end if;

  run_key := encode(digest(range_start::text || ':' || range_end::text, 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(run_key, 0));

  select id, flights_created into run_id, existing_count
  from public.schedule_generation_runs where request_key = run_key;
  if found and exists (select 1 from public.schedule_generation_runs where id = run_id and completed_at is not null) then
    return query select run_id, existing_count;
    return;
  end if;

  if run_id is null then
    insert into public.schedule_generation_runs (range_start, range_end, requested_by, request_key)
    values (range_start, range_end, auth.uid(), run_key)
    returning id into run_id;
  end if;

  select count(*) into template_count
  from public.schedule_templates t
  where t.status = 'active' and t.effective_during && daterange(range_start, range_end, '[]');

  insert into public.flights (
    schedule_template_id, flight_number, route_version_id, origin_airport_id,
    destination_airport_id, aircraft_type_id, aircraft_id,
    scheduled_departure, scheduled_arrival, created_by
  )
  select
    t.id, t.service_number, t.route_version_id, r.origin_airport_id,
    r.destination_airport_id, t.aircraft_type_id, t.default_aircraft_id,
    (g.service_date + t.departure_local_time) at time zone origin.timezone,
    ((g.service_date + t.departure_local_time) at time zone origin.timezone) + t.block_duration,
    auth.uid()
  from public.schedule_templates t
  join public.route_versions rv on rv.id = t.route_version_id and rv.is_published
  join public.routes r on r.id = rv.route_id
  join public.airports origin on origin.id = r.origin_airport_id
  cross join lateral generate_series(range_start, range_end, interval '1 day') as g(service_date)
  where t.status = 'active'
    and g.service_date::date <@ t.effective_during
    and extract(dow from g.service_date)::smallint = any(t.operating_days)
  on conflict (schedule_template_id, scheduled_departure) do nothing;
  get diagnostics inserted_count = row_count;

  update public.schedule_generation_runs
  set templates_considered = template_count,
      flights_created = inserted_count,
      completed_at = now(),
      error_message = null
  where id = run_id;

  return query select run_id, inserted_count;
end;
$$;

create function public.transition_flight_status(
  requested_flight_id uuid,
  requested_status public.flight_status,
  transition_reason text default null,
  transition_source text default 'manual'
)
returns public.flights
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  changed_flight public.flights;
begin
  if not (public.can_manage_operations() or public.is_assigned_to_flight(requested_flight_id)) then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  if transition_source not in ('manual', 'acars', 'system', 'import') then
    raise exception 'invalid transition source' using errcode = '22023';
  end if;

  update public.flights
  set status = requested_status,
      cancellation_reason = case when requested_status = 'cancelled' then transition_reason else cancellation_reason end,
      actual_departure = case when requested_status = 'departed' and actual_departure is null then now() else actual_departure end,
      actual_arrival = case when requested_status = 'arrived' and actual_arrival is null then now() else actual_arrival end
  where id = requested_flight_id
  returning * into changed_flight;

  if not found then raise exception 'flight not found' using errcode = 'P0002'; end if;

  update public.flight_status_events
  set source = transition_source, reason = transition_reason, recorded_by = auth.uid()
  where id = (
    select id from public.flight_status_events
    where flight_id = requested_flight_id order by id desc limit 1
  );
  return changed_flight;
end;
$$;

create function public.assign_crew_member(
  requested_flight_id uuid,
  requested_profile_id uuid,
  requested_role public.crew_role,
  requested_report_at timestamptz default null,
  requested_release_at timestamptz default null
)
returns public.flight_crew_assignments
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  assignment public.flight_crew_assignments;
begin
  if not public.can_manage_operations() then raise exception 'not authorized' using errcode = '42501'; end if;
  insert into public.flight_crew_assignments (
    flight_id, profile_id, crew_role, report_at, release_at, assigned_by
  ) values (
    requested_flight_id, requested_profile_id, requested_role,
    requested_report_at, requested_release_at, auth.uid()
  )
  returning * into assignment;
  return assignment;
end;
$$;

create function public.release_dispatch_release(requested_release_id uuid)
returns public.dispatch_releases
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_release public.dispatch_releases;
begin
  if not (public.is_service_role() or public.has_any_role(array['administrator', 'operations_manager', 'dispatcher']::public.app_role[])) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  select * into target_release from public.dispatch_releases
  where id = requested_release_id for update;
  if not found then raise exception 'dispatch release not found' using errcode = 'P0002'; end if;
  if target_release.status <> 'draft' then raise exception 'only draft releases can be released' using errcode = '23514'; end if;

  update public.dispatch_releases
  set status = 'superseded'
  where flight_id = target_release.flight_id and status in ('released', 'accepted');

  update public.dispatch_releases
  set status = 'released', dispatcher_id = auth.uid(), released_at = now()
  where id = requested_release_id
  returning * into target_release;
  return target_release;
end;
$$;

create function public.submit_pirep(requested_pirep_id uuid)
returns public.pireps
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  submitted public.pireps;
begin
  update public.pireps
  set status = 'submitted',
      submitted_at = now(),
      block_time_minutes = case when block_off_at is not null and block_on_at is not null
        then floor(extract(epoch from (block_on_at - block_off_at)) / 60)::integer else block_time_minutes end,
      flight_time_minutes = case when takeoff_at is not null and landing_at is not null
        then floor(extract(epoch from (landing_at - takeoff_at)) / 60)::integer else flight_time_minutes end
  where id = requested_pirep_id
    and submitted_by = auth.uid()
    and status in ('draft', 'rejected')
  returning * into submitted;

  if not found then raise exception 'editable PIREP not found' using errcode = 'P0002'; end if;
  return submitted;
end;
$$;

revoke all on function public.current_profile_id() from public;
revoke all on function public.has_role(public.app_role) from public;
revoke all on function public.has_any_role(public.app_role[]) from public;
revoke all on function public.is_service_role() from public;
revoke all on function public.can_manage_operations() from public;
revoke all on function public.can_manage_people() from public;
revoke all on function public.can_manage_maintenance() from public;
revoke all on function public.is_assigned_to_flight(uuid) from public;
revoke all on function public.publish_route_version(uuid) from public;
revoke all on function public.generate_scheduled_flights(date, date) from public;
revoke all on function public.transition_flight_status(uuid, public.flight_status, text, text) from public;
revoke all on function public.assign_crew_member(uuid, uuid, public.crew_role, timestamptz, timestamptz) from public;
revoke all on function public.release_dispatch_release(uuid) from public;
revoke all on function public.submit_pirep(uuid) from public;
