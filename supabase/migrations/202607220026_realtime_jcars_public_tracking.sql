-- Publish the latest JCars telemetry point for every actively tracked public flight.
-- The browser refreshes this sanitized snapshot every five seconds, matching the
-- default JCars telemetry cadence.
create or replace function public.get_public_operations_snapshot()
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
with public_movements as (
  select f.*,coalesce(o.display_label,o.local_code,o.iata,o.icao,'—') origin_label,
    coalesce(d.display_label,d.local_code,d.iata,d.icao,'—') destination_label,a.registration
  from public.flights f
  left join public.airports o on o.id=f.origin_airport_id
  left join public.airports d on d.id=f.destination_airport_id
  left join public.aircraft a on a.id=f.aircraft_id
  where f.public_visibility and f.status not in ('draft','cancelled')
    and f.scheduled_departure>=date_trunc('day',now() at time zone 'America/Los_Angeles') at time zone 'America/Los_Angeles'
    and f.scheduled_departure<(date_trunc('day',now() at time zone 'America/Los_Angeles')+interval '1 day') at time zone 'America/Los_Angeles'
), live_positions as (
  select distinct on (s.flight_id) s.flight_id,s.pilot_id,f.tracking_callsign,
    coalesce(o.display_label,o.local_code,o.iata,o.icao,'—') origin_label,
    coalesce(d.display_label,d.local_code,d.iata,d.icao,'—') destination_label,
    a.registration,t.latitude,t.longitude,t.altitude,t.heading,t.ground_speed,t.recorded_at
  from public.acars_sessions s
  join public.flight_telemetry_points t on t.session_id=s.id
  join public.flights f on f.id=s.flight_id
  left join public.airports o on o.id=f.origin_airport_id
  left join public.airports d on d.id=f.destination_airport_id
  left join public.aircraft a on a.id=s.aircraft_id
  where s.status='active' and t.recorded_at>now()-interval '2 minutes'
  order by s.flight_id,t.recorded_at desc
), positions_json as (
 select coalesce(jsonb_agg(jsonb_build_object('flight_id',p.flight_id,'callsign',p.tracking_callsign,'latitude',p.latitude,'longitude',p.longitude,'altitude',p.altitude,'heading',p.heading,'ground_speed',p.ground_speed,'recorded_at',p.recorded_at,'origin',p.origin_label,'destination',p.destination_label,'aircraft',p.registration)),'[]'::jsonb) value
 from live_positions p
), movements_json as (
 select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'callsign',m.tracking_callsign,'origin',m.origin_label,'destination',m.destination_label,'departure',coalesce(m.estimated_departure,m.scheduled_departure),'arrival',coalesce(m.estimated_arrival,m.scheduled_arrival),'status',m.status,'aircraft',m.registration) order by m.scheduled_departure),'[]'::jsonb) value from public_movements m
), fleet_json as (
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'registration',a.registration,'fleet_number',a.fleet_number,'type_code',t.code,'type_name',t.name,'status',a.status,'location',coalesce(ap.display_label,ap.local_code,ap.iata,ap.icao,'IN TRANSIT'),'hours',round(a.total_hours,1),'cycles',a.total_cycles,'capacity',coalesce(a.passenger_capacity,t.default_capacity,0)) order by t.code,a.registration),'[]'::jsonb) value
 from public.aircraft a join public.aircraft_types t on t.id=a.aircraft_type_id left join public.airports ap on ap.id=a.current_airport_id
 where a.active and a.status<>'retired'
), station_json as (
 select coalesce(jsonb_agg(jsonb_build_object('id',ap.id,'code',coalesce(ap.local_code,ap.iata,ap.icao),'label',coalesce(ap.display_label,ap.name),'departures',(select count(*) from public_movements m where m.origin_airport_id=ap.id),'arrivals',(select count(*) from public_movements m where m.destination_airport_id=ap.id)) order by ap.display_label,ap.name),'[]'::jsonb) value
 from public.airports ap where ap.active and ap.public_visibility
)
select jsonb_build_object(
 'generated_at',now(),'position_delay_minutes',0,
 'movements',(select value from movements_json),'positions',(select value from positions_json),'fleet',(select value from fleet_json),'station_activity',(select value from station_json),
 'metrics',jsonb_build_object(
   'active_flights',(select count(distinct flight_id) from live_positions),
   'pilots_online',(select count(distinct pilot_id) from live_positions),
   'today_movements',(select count(*) from public_movements),
   'fleet_size',(select count(*) from public.aircraft where active and status<>'retired'),
   'stations',(select count(*) from public.airports where active and public_visibility),
   'routes',(select count(*) from public.routes where active and public_visibility),
   'completed_flights',(select count(*) from public.flights where public_visibility and status='completed'),
   'flight_hours',(select coalesce(round(sum(p.flight_minutes)/60.0,1),0) from public.pireps p join public.flights f on f.id=p.flight_id where f.public_visibility and p.status in ('automatically_accepted','accepted')),
   'active_pilots',(select count(distinct ur.user_id) from public.user_roles ur join public.profiles p on p.id=ur.user_id where ur.active and ur.role in ('pilot','captain','instructor','chief_pilot','owner') and p.status='active'),
   'on_time_rate',(select coalesce(round(100.0*count(*) filter(where actual_off_block<=scheduled_departure+interval '15 minutes')/nullif(count(*),0),1),0) from public.flights where public_visibility and actual_off_block is not null)
 ))
$$;
revoke all on function public.get_public_operations_snapshot() from public;
grant execute on function public.get_public_operations_snapshot() to anon,authenticated;
notify pgrst,'reload schema';
