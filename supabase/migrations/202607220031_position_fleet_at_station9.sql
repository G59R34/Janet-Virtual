-- Temporary operating-state reset: position the active fleet at Station 9.
do $$
declare station9_id uuid;
begin
  select id into station9_id from public.airports
  where local_code='STN9' or icao='KLAS'
  order by case when local_code='STN9' then 0 else 1 end
  limit 1;
  if station9_id is null then raise exception 'Station 9 airport record not found'; end if;

  perform public.ensure_airport_stands(station9_id,6);

  with fleet as (
    select a.id,row_number() over(order by a.fleet_number,a.registration) slot
    from public.aircraft a
    where a.active and a.status<>'retired'
  ), stands as (
    select s.id,row_number() over(order by s.priority,s.code) slot
    from public.airport_stands s
    where s.airport_id=station9_id and s.active
  )
  update public.aircraft a
  set current_airport_id=station9_id,
      current_stand_id=stands.id,
      status=case when a.status in ('grounded','maintenance','stored') then a.status else 'available' end
  from fleet join stands on stands.slot=fleet.slot
  where a.id=fleet.id;

  -- Any aircraft beyond the available named stands is still positioned at STN9.
  update public.aircraft
  set current_airport_id=station9_id,
      current_stand_id=null,
      status=case when status in ('grounded','maintenance','stored') then status else 'available' end
  where active and status<>'retired' and current_airport_id is distinct from station9_id;

  perform public.refresh_dynamic_tail_board();
end$$;
notify pgrst,'reload schema';
