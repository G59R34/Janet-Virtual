-- Allocate the six-aircraft fleet across generated flights without double-booking an airframe.
create or replace function public.validate_flight_aircraft() returns trigger language plpgsql set search_path='' as $$
declare a public.aircraft%rowtype; previous_destination uuid;
begin
 if new.aircraft_id is null then return new; end if;
 select * into a from public.aircraft where id=new.aircraft_id for update;
 if not a.active or a.status in ('grounded','maintenance','stored','retired') then raise exception 'aircraft is not operationally available'; end if;
 if exists(select 1 from public.flights f where f.aircraft_id=new.aircraft_id and f.id<>new.id and f.status not in ('completed','cancelled') and tstzrange(f.scheduled_departure,f.scheduled_arrival,'[)') && tstzrange(new.scheduled_departure,new.scheduled_arrival,'[)')) then raise exception 'aircraft has an overlapping assignment'; end if;
 select f.destination_airport_id into previous_destination from public.flights f where f.aircraft_id=new.aircraft_id and f.id<>new.id and f.status<>'cancelled' and f.scheduled_arrival<=new.scheduled_departure order by f.scheduled_arrival desc limit 1;
 if coalesce(previous_destination,a.current_airport_id) is distinct from new.origin_airport_id then raise exception 'aircraft is not positioned at flight origin'; end if;
 return new;
end$$;

create or replace function public.allocate_open_flight_aircraft() returns jsonb language plpgsql security definer set search_path='' as $$
declare fl public.flights%rowtype; chosen uuid; allocated int:=0; pending int:=0;
begin
 for fl in select * from public.flights where aircraft_id is null and status in ('generated','awaiting_dispatch','released') order by scheduled_departure,id for update loop
  select a.id into chosen
  from public.aircraft a
  where a.active and a.registration in ('N319BD','N869HH','N859WP','N273RH','N365SR','N288DP')
   and a.status not in ('grounded','maintenance','stored','retired')
   and not exists(select 1 from public.flights x where x.aircraft_id=a.id and x.status not in ('completed','cancelled') and tstzrange(x.scheduled_departure,x.scheduled_arrival,'[)') && tstzrange(fl.scheduled_departure,fl.scheduled_arrival,'[)'))
   and coalesce((select p.destination_airport_id from public.flights p where p.aircraft_id=a.id and p.status<>'cancelled' and p.scheduled_arrival<=fl.scheduled_departure order by p.scheduled_arrival desc limit 1),a.current_airport_id)=fl.origin_airport_id
  order by (select max(p.scheduled_arrival) from public.flights p where p.aircraft_id=a.id),a.fleet_number limit 1;
  if chosen is null then pending:=pending+1; else update public.flights set aircraft_id=chosen where id=fl.id;allocated:=allocated+1;end if;
 end loop;
 return jsonb_build_object('allocated',allocated,'pending',pending);
end$$;
grant execute on function public.allocate_open_flight_aircraft() to authenticated,service_role;

-- Positioning is validated against the aircraft's preceding scheduled leg by the
-- flight trigger above; remove the older static-current-airport check from pickup.
do $$
declare definition text;
begin
 definition:=pg_get_functiondef('public.reserve_flight(uuid,text)'::regprocedure);
 definition:=replace(definition,' or a.current_airport_id is distinct from f.origin_airport_id','');
 execute definition;
end$$;

create or replace function public.run_schedule_automation() returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.schedule_automation_state%rowtype;r record;allocation jsonb;
begin select * into s from public.schedule_automation_state where id=true for update;if not s.enabled then return jsonb_build_object('enabled',false);end if;
begin select * into r from public.generate_scheduled_flights(current_date,s.horizon_days);allocation:=public.allocate_open_flight_aircraft();update public.schedule_automation_state set last_run_at=now(),last_created=r.created_count,last_skipped=r.skipped_count,last_error=null,updated_at=now() where id=true;return jsonb_build_object('enabled',true,'created',r.created_count,'skipped',r.skipped_count,'aircraft',allocation);
exception when others then update public.schedule_automation_state set last_run_at=now(),last_error=sqlerrm,updated_at=now() where id=true;raise;end;end$$;

select public.allocate_open_flight_aircraft();
notify pgrst,'reload schema';
