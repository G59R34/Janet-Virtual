-- Identity bootstrap and idempotent schedule generation.
create sequence if not exists public.employee_number_seq start 1001;
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path='' as $$
declare next_number text;
begin
  next_number := 'JVA-' || lpad(nextval('public.employee_number_seq')::text, 4, '0');
  insert into public.profiles(id,employee_number,display_name,email,timezone)
  values(new.id,next_number,coalesce(nullif(new.raw_user_meta_data->>'display_name',''),split_part(new.email,'@',1)),new.email,coalesce(new.raw_user_meta_data->>'timezone','UTC'));
  insert into public.user_roles(user_id,role) values(new.id,'applicant');
  if new.raw_user_meta_data ? 'application_answers' then
    insert into public.applications(applicant_user_id,answers) values(new.id,new.raw_user_meta_data->'application_answers');
  end if;
  return new;
end$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.generate_scheduled_flights(p_from date default current_date,p_days int default 14)
returns table(created_count int, skipped_count int)
language plpgsql security definer set search_path='' as $$
declare d date; t public.schedule_templates%rowtype; dep timestamptz; arr timestamptz; jitter int; roll numeric; made int:=0; skipped int:=0;
begin
  if auth.uid() is not null and not public.has_any_role(auth.uid(),array['dispatcher','operations_manager','owner','system_administrator']::public.app_role[]) then raise exception 'insufficient role'; end if;
  if p_days<1 or p_days>60 then raise exception 'days must be between 1 and 60'; end if;
  for d in select generate_series(p_from,p_from+p_days-1,interval '1 day')::date loop
    for t in select * from public.schedule_templates s where s.active and extract(isodow from d)::int=any(s.days_of_week) and (s.start_date is null or s.start_date<=d) and (s.end_date is null or s.end_date>=d) and not exists(select 1 from public.schedule_exceptions e where e.schedule_template_id=s.id and e.date=d and e.exception_type='cancel') loop
      roll := ('x'||substr(md5(t.id::text||d::text),1,8))::bit(32)::bigint / 4294967295.0;
      if roll>t.operation_probability then skipped:=skipped+1; continue; end if;
      jitter := case when t.variability_minutes>0 then ((('x'||substr(md5(d::text||t.id::text||'j'),1,8))::bit(32)::bigint % (t.variability_minutes*2+1))-t.variability_minutes)::int else 0 end;
      dep := (d+t.scheduled_departure_local) at time zone 'America/Los_Angeles' + make_interval(mins=>jitter);
      arr := (d+t.scheduled_arrival_local) at time zone 'America/Los_Angeles' + make_interval(mins=>jitter);
      if arr<=dep then arr:=arr+interval '1 day'; end if;
      insert into public.flights(flight_number,spoken_callsign,tracking_callsign,schedule_template_id,origin_airport_id,destination_airport_id,scheduled_departure,scheduled_arrival,planned_altitude_ft,status,public_visibility,generation_reason)
      values(t.flight_number,replace(t.callsign_template,'JANET','Janet '),t.callsign_template,t.id,t.origin_airport_id,t.destination_airport_id,dep,arr,t.altitude_ft,'generated',false,jsonb_build_object('template',t.name,'probability',t.operation_probability,'roll',roll,'variation_minutes',jitter))
      on conflict(schedule_template_id,scheduled_departure) do nothing;
      if found then made:=made+1; else skipped:=skipped+1; end if;
    end loop;
  end loop;
  insert into public.audit_logs(actor_id,action,entity_type,new_values) values(auth.uid(),'schedule.generate','flight_batch',jsonb_build_object('from',p_from,'days',p_days,'created',made,'skipped',skipped));
  return query select made,skipped;
end$$;
grant execute on function public.generate_scheduled_flights(date,int) to authenticated,service_role;

create policy authenticated_stations on public.stations for select to authenticated using(true);
create policy authenticated_aircraft_types on public.aircraft_types for select to authenticated using(true);
create policy authenticated_aircraft on public.aircraft for select to authenticated using(true);
create policy ops_schedule_templates on public.schedule_templates for all to authenticated using(public.has_any_role(auth.uid(),array['dispatcher','operations_manager','owner','system_administrator']::public.app_role[])) with check(public.has_any_role(auth.uid(),array['dispatcher','operations_manager','owner','system_administrator']::public.app_role[]));
create policy crew_assignments_visible on public.crew_assignments for select to authenticated using(user_id=auth.uid() or public.has_any_role(auth.uid(),array['dispatcher','chief_pilot','operations_manager','owner','system_administrator']::public.app_role[]));
create policy qualifications_visible on public.qualifications for select to authenticated using(true);
create policy own_qualifications on public.user_qualifications for select to authenticated using(user_id=auth.uid() or public.has_any_role(auth.uid(),array['instructor','chief_pilot','owner','system_administrator']::public.app_role[]));

-- Editable reference preset. Probabilities and variability model non-daily/variable operations.
insert into public.schedule_templates(name,callsign_template,flight_number,origin_airport_id,destination_airport_id,scheduled_departure_local,scheduled_arrival_local,days_of_week,aircraft_category,preferred_aircraft_type_id,altitude_ft,operation_type,variability_minutes,operation_probability,active,source_reference,preset_name,generation_reason)
select v.name,v.callsign,v.callsign,o.id,d.id,v.dep,v.arr,v.days,'commuter',at.id,v.altitude,v.kind,v.variance,v.probability,false,'Dreamland Resort public schedule, reviewed 2026-07-21','Publicly Documented JANET-Inspired Weekday Schedule – 2026 Reference','weekday commuter preset'
from (values
 ('Early worker movement','JANET11','STN9','STN3','03:40'::time,'04:00'::time,array[1,2,3,4,5],14000,'commuter',10,1.0),
 ('Early worker return','JANET22','STN3','STN9','04:30'::time,'04:50'::time,array[1,2,3,4,5],15000,'commuter',10,1.0),
 ('TTR morning movement','JANET55','STN9','STN7','04:05'::time,'04:30'::time,array[1,2,3,4,5],20000,'commuter',15,0.95),
 ('TTR morning return','JANET24','STN7','STN9','05:05'::time,'05:40'::time,array[1,2,3,4,5],19000,'commuter',15,0.95),
 ('Afternoon shift movement','JANET51','STN9','STN3','15:10'::time,'15:30'::time,array[1,2,3,4,5],14000,'commuter',50,0.8),
 ('Evening shift return','JANET36','STN3','STN9','20:10'::time,'20:30'::time,array[1,2,3,4,5],15000,'commuter',20,0.85),
 ('Monday Palmdale arrival','JANET29','STN1','STN3','08:30'::time,'09:15'::time,array[1],15000,'personnel',30,0.9),
 ('Friday Palmdale return','JANET92','STN3','STN1','12:00'::time,'12:50'::time,array[5],14000,'personnel',45,0.9)
) as v(name,callsign,origin_code,dest_code,dep,arr,days,altitude,kind,variance,probability)
join public.airports o on o.local_code=v.origin_code join public.airports d on d.local_code=v.dest_code join public.aircraft_types at on at.code='B737'
on conflict do nothing;
