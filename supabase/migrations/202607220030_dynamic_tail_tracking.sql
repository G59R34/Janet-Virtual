-- Dynamic tail board: only offer flights from each aircraft's physical airport.
create or replace function public.validate_flight_aircraft() returns trigger
language plpgsql set search_path='' as $$
declare a public.aircraft%rowtype;
begin
  if new.aircraft_id is null then return new; end if;
  select * into a from public.aircraft where id=new.aircraft_id for update;
  if not found or not a.active or a.status in ('grounded','maintenance','stored','retired') then
    raise exception 'aircraft is not operationally available';
  end if;
  if a.current_airport_id is distinct from new.origin_airport_id then
    raise exception 'aircraft is not currently positioned at flight origin';
  end if;
  if exists(
    select 1 from public.flights f
    where f.aircraft_id=new.aircraft_id and f.id<>new.id
      and f.status not in ('generated','awaiting_dispatch','released','completed','cancelled')
  ) then raise exception 'aircraft is committed to another active flight'; end if;
  return new;
end$$;

create or replace function public.refresh_dynamic_tail_board() returns jsonb
language plpgsql security definer set search_path='' as $$
declare tail public.aircraft%rowtype; chosen uuid; offered int:=0; waiting int:=0;
begin
  perform pg_catalog.pg_advisory_xact_lock(820260730);

  -- Open flights are offers, not future tail reservations. Rebuild them from
  -- the current physical fleet position every time operational state changes.
  update public.flights set aircraft_id=null
  where status in ('generated','awaiting_dispatch','released') and aircraft_id is not null;

  update public.aircraft a set status='available'
  where a.status='assigned' and not exists(
    select 1 from public.flights f where f.aircraft_id=a.id
      and f.status not in ('generated','awaiting_dispatch','released','completed','cancelled')
  );

  for tail in
    select * from public.aircraft a
    where a.active and a.status='available' and a.current_airport_id is not null
      and not exists(
        select 1 from public.flights active_flight where active_flight.aircraft_id=a.id
          and active_flight.status not in ('generated','awaiting_dispatch','released','completed','cancelled')
      )
    order by a.fleet_number,a.registration
    for update
  loop
    select f.id into chosen from public.flights f
    where f.aircraft_id is null
      and f.status in ('generated','awaiting_dispatch','released')
      and f.origin_airport_id=tail.current_airport_id
      and f.scheduled_arrival>now()
    order by case when f.scheduled_departure>=now() then 0 else 1 end,
      abs(extract(epoch from (f.scheduled_departure-now()))),f.scheduled_departure,f.id
    limit 1 for update skip locked;
    if chosen is not null then
      update public.flights set aircraft_id=tail.id where id=chosen;
      offered:=offered+1;
    end if;
    chosen:=null;
  end loop;

  select count(*) into waiting from public.flights
  where aircraft_id is null and status in ('generated','awaiting_dispatch','released') and scheduled_arrival>now();
  return jsonb_build_object('offered',offered,'waiting',waiting);
end$$;

create or replace function public.allocate_open_flight_aircraft() returns jsonb
language sql security definer set search_path='' as $$
  select public.refresh_dynamic_tail_board()
$$;

create or replace function public.track_aircraft_stand_from_flight() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.aircraft_id is null then return new; end if;
  if new.status='crew_assigned' and old.status is distinct from new.status then
    update public.aircraft set status='assigned' where id=new.aircraft_id;
    perform public.refresh_dynamic_tail_board();
  elsif new.status='off_block' and old.status is distinct from new.status then
    update public.aircraft set current_stand_id=null,status='assigned' where id=new.aircraft_id;
  elsif new.status in ('on_block','completed') and old.status is distinct from new.status then
    update public.aircraft set current_airport_id=new.destination_airport_id,current_stand_id=new.arrival_stand_id,status='available' where id=new.aircraft_id;
    perform public.refresh_dynamic_tail_board();
  elsif new.status='cancelled' and old.status is distinct from new.status then
    update public.aircraft set status='available' where id=new.aircraft_id and status='assigned';
    perform public.refresh_dynamic_tail_board();
  end if;
  return new;
end$$;

revoke all on function public.refresh_dynamic_tail_board() from public,anon,authenticated;
grant execute on function public.refresh_dynamic_tail_board() to service_role;
revoke all on function public.allocate_open_flight_aircraft() from public;
grant execute on function public.allocate_open_flight_aircraft() to authenticated,service_role;

select public.refresh_dynamic_tail_board();
notify pgrst,'reload schema';
