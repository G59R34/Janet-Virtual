-- Controlled audit write path for authenticated operational mutations.
create or replace function public.record_audit(p_action text,p_entity_type text,p_entity_id uuid,p_previous_values jsonb default null,p_new_values jsonb default null,p_reason text default null)
returns void language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,previous_values,new_values,reason)
  values(auth.uid(),p_action,p_entity_type,p_entity_id,p_previous_values,p_new_values,p_reason);
end$$;
grant execute on function public.record_audit(text,text,uuid,jsonb,jsonb,text) to authenticated;

-- Database enforcement for aircraft positioning on insert/update.
create or replace function public.validate_flight_aircraft() returns trigger language plpgsql set search_path='' as $$
declare a public.aircraft%rowtype;
begin
  if new.aircraft_id is null then return new; end if;
  select * into a from public.aircraft where id=new.aircraft_id for update;
  if a.status in ('grounded','maintenance','stored','retired') then raise exception 'aircraft is not operationally available'; end if;
  if a.current_airport_id is distinct from new.origin_airport_id then raise exception 'aircraft is not positioned at flight origin'; end if;
  if exists(select 1 from public.flights f where f.aircraft_id=new.aircraft_id and f.id<>new.id and f.status not in ('completed','cancelled') and tstzrange(f.scheduled_departure,f.scheduled_arrival,'[)') && tstzrange(new.scheduled_departure,new.scheduled_arrival,'[)')) then raise exception 'aircraft has an overlapping assignment'; end if;
  return new;
end$$;
drop trigger if exists validate_flight_aircraft_trigger on public.flights;
create trigger validate_flight_aircraft_trigger before insert or update of aircraft_id,origin_airport_id,scheduled_departure,scheduled_arrival on public.flights for each row execute function public.validate_flight_aircraft();
