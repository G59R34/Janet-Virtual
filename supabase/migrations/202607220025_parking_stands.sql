-- Airport parking stands, automatic stand assignment, and aircraft stand position.
create table public.airport_stands(
  id uuid primary key default gen_random_uuid(),
  airport_id uuid not null references public.airports(id) on delete cascade,
  code text not null,
  name text not null,
  stand_type text not null default 'remote' check(stand_type in ('janet_terminal','janet_ramp','remote','general_aviation','generated')),
  data_source text not null default 'generated' check(data_source in ('public_reference','satellite_inferred','generated','manual')),
  latitude double precision,
  longitude double precision,
  heading_degrees smallint check(heading_degrees between 0 and 359),
  max_aircraft_category text not null default 'C',
  priority integer not null default 100,
  active boolean not null default true,
  source_reference text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(airport_id,code)
);

alter table public.aircraft add column current_stand_id uuid references public.airport_stands(id) on delete set null;
alter table public.flights
  add column departure_stand_id uuid references public.airport_stands(id) on delete set null,
  add column arrival_stand_id uuid references public.airport_stands(id) on delete set null;

create index airport_stands_airport_priority_idx on public.airport_stands(airport_id,active,priority,code);
create index flights_departure_stand_time_idx on public.flights(departure_stand_id,scheduled_departure) where departure_stand_id is not null;
create index flights_arrival_stand_time_idx on public.flights(arrival_stand_id,scheduled_arrival) where arrival_stand_id is not null;

create trigger airport_stands_set_updated_at before update on public.airport_stands
for each row execute function public.set_updated_at();

create or replace function public.ensure_airport_stands(p_airport_id uuid,p_count integer default 4)
returns integer language plpgsql security definer set search_path='' as $$
declare existing_count integer; next_number integer; target_count integer:=greatest(1,least(coalesce(p_count,4),20));
begin
  if not exists(select 1 from public.airports where id=p_airport_id) then raise exception 'Airport not found'; end if;
  select count(*) into existing_count from public.airport_stands where airport_id=p_airport_id and active;
  next_number:=existing_count+1;
  while existing_count<target_count loop
    insert into public.airport_stands(airport_id,code,name,stand_type,data_source,priority,notes)
    values(p_airport_id,'AUTO-'||lpad(next_number::text,2,'0'),'Operational stand '||next_number,'generated','generated',500+next_number,'Automatically created pending airport-specific parking data')
    on conflict(airport_id,code) do nothing;
    existing_count:=existing_count+1;next_number:=next_number+1;
  end loop;
  return existing_count;
end$$;

create or replace function public.create_default_airport_stands() returns trigger
language plpgsql security definer set search_path='' as $$
begin perform public.ensure_airport_stands(new.id,4);return new;end$$;
create trigger create_default_airport_stands_trigger after insert on public.airports
for each row execute function public.create_default_airport_stands();

-- Existing operating fields receive defaults; known JANET facilities are refined below.
select public.ensure_airport_stands(id,4) from public.airports;
delete from public.airport_stands s using public.airports a
where s.airport_id=a.id and s.data_source='generated' and (a.icao in ('KLAS','KXTA') or a.local_code in ('STN9','STN3'));

insert into public.airport_stands(airport_id,code,name,stand_type,data_source,priority,source_reference,notes)
select a.id,v.code,v.name,v.stand_type,v.data_source,v.priority,'https://en.wikipedia.org/wiki/Janet_(airline)',v.notes
from public.airports a cross join (values
  ('JNT-01','JANET Terminal Stand 1','janet_terminal','satellite_inferred',10,'West-side private JANET terminal apron; stand numbering is virtual and based on supplied satellite imagery.'),
  ('JNT-02','JANET Terminal Stand 2','janet_terminal','satellite_inferred',20,'West-side private JANET terminal apron; stand numbering is virtual and based on supplied satellite imagery.'),
  ('JNT-03','JANET Terminal Stand 3','janet_terminal','satellite_inferred',30,'West-side private JANET terminal apron; stand numbering is virtual and based on supplied satellite imagery.'),
  ('JNT-04','JANET Terminal Stand 4','janet_terminal','satellite_inferred',40,'West-side private JANET terminal apron; stand numbering is virtual and based on supplied satellite imagery.'),
  ('JNT-05','JANET Terminal Stand 5','janet_terminal','satellite_inferred',50,'West-side private JANET terminal apron; stand numbering is virtual and based on supplied satellite imagery.'),
  ('JNT-06','JANET Terminal Stand 6','janet_terminal','satellite_inferred',60,'West-side private JANET terminal apron; stand numbering is virtual and based on supplied satellite imagery.')
) as v(code,name,stand_type,data_source,priority,notes)
where a.icao='KLAS' or a.local_code='STN9'
on conflict(airport_id,code) do update set name=excluded.name,stand_type=excluded.stand_type,data_source=excluded.data_source,priority=excluded.priority,source_reference=excluded.source_reference,notes=excluded.notes,active=true;

insert into public.airport_stands(airport_id,code,name,stand_type,data_source,priority,source_reference,notes)
select a.id,v.code,v.name,v.stand_type,v.data_source,v.priority,'https://www.dreamlandresort.com/area51/groom_overflight.html',v.notes
from public.airports a cross join (values
  ('JR-01','Janet Ramp Stand 1','janet_ramp','satellite_inferred',10,'Janet Ramp is publicly documented; individual stand numbering is virtual and follows the supplied east-apron satellite image, north to south.'),
  ('JR-02','Janet Ramp Stand 2','janet_ramp','satellite_inferred',20,'Janet Ramp is publicly documented; individual stand numbering is virtual and follows the supplied east-apron satellite image, north to south.'),
  ('JR-03','Janet Ramp Stand 3','janet_ramp','satellite_inferred',30,'Janet Ramp is publicly documented; individual stand numbering is virtual and follows the supplied east-apron satellite image, north to south.'),
  ('JR-04','Janet Ramp Stand 4','janet_ramp','satellite_inferred',40,'Janet Ramp is publicly documented; individual stand numbering is virtual and follows the supplied east-apron satellite image, north to south.'),
  ('JR-05','Janet Ramp Stand 5','janet_ramp','satellite_inferred',50,'Janet Ramp is publicly documented; individual stand numbering is virtual and follows the supplied east-apron satellite image, north to south.'),
  ('JR-06','Janet Ramp Stand 6','janet_ramp','satellite_inferred',60,'Janet Ramp is publicly documented; individual stand numbering is virtual and follows the supplied east-apron satellite image, north to south.'),
  ('JR-07','Janet Ramp Stand 7','janet_ramp','satellite_inferred',70,'Janet Ramp is publicly documented; individual stand numbering is virtual and follows the supplied east-apron satellite image, north to south.'),
  ('JR-08','Janet Ramp Stand 8','janet_ramp','satellite_inferred',80,'Janet Ramp is publicly documented; individual stand numbering is virtual and follows the supplied east-apron satellite image, north to south.')
) as v(code,name,stand_type,data_source,priority,notes)
where a.icao='KXTA' or a.local_code='STN3'
on conflict(airport_id,code) do update set name=excluded.name,stand_type=excluded.stand_type,data_source=excluded.data_source,priority=excluded.priority,source_reference=excluded.source_reference,notes=excluded.notes,active=true;

create or replace function public.assign_flight_parking_stands() returns trigger
language plpgsql security definer set search_path='' as $$
declare chosen uuid; aircraft_stand uuid;
begin
  -- Serialize assignment for the two airports so concurrent schedule generation
  -- cannot select the same stand before either flight is visible.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(new.origin_airport_id,new.destination_airport_id)::text,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(greatest(new.origin_airport_id,new.destination_airport_id)::text,0));
  perform public.ensure_airport_stands(new.origin_airport_id,4);
  perform public.ensure_airport_stands(new.destination_airport_id,4);
  if new.aircraft_id is not null then
    select current_stand_id into aircraft_stand from public.aircraft where id=new.aircraft_id;
  end if;

  select s.id into chosen from public.airport_stands s
  where s.airport_id=new.origin_airport_id and s.active
    and not exists(
      select 1 from public.flights f where f.id<>new.id and f.status<>'cancelled'
      and ((f.departure_stand_id=s.id and abs(extract(epoch from (f.scheduled_departure-new.scheduled_departure)))<2700)
        or (f.arrival_stand_id=s.id and abs(extract(epoch from (f.scheduled_arrival-new.scheduled_departure)))<2700))
    )
  order by case when s.id=aircraft_stand then 0 else 1 end,s.priority,s.code limit 1;
  if chosen is null then
    perform public.ensure_airport_stands(new.origin_airport_id,(select (count(*)+1)::integer from public.airport_stands where airport_id=new.origin_airport_id));
    select id into chosen from public.airport_stands where airport_id=new.origin_airport_id and active order by priority desc,code desc limit 1;
  end if;
  new.departure_stand_id:=chosen;

  select s.id into chosen from public.airport_stands s
  where s.airport_id=new.destination_airport_id and s.active
    and not exists(
      select 1 from public.flights f where f.id<>new.id and f.status<>'cancelled'
      and ((f.departure_stand_id=s.id and abs(extract(epoch from (f.scheduled_departure-new.scheduled_arrival)))<2700)
        or (f.arrival_stand_id=s.id and abs(extract(epoch from (f.scheduled_arrival-new.scheduled_arrival)))<2700))
    )
  order by s.priority,s.code limit 1;
  if chosen is null then
    perform public.ensure_airport_stands(new.destination_airport_id,(select (count(*)+1)::integer from public.airport_stands where airport_id=new.destination_airport_id));
    select id into chosen from public.airport_stands where airport_id=new.destination_airport_id and active order by priority desc,code desc limit 1;
  end if;
  new.arrival_stand_id:=chosen;
  return new;
end$$;

create trigger assign_flight_parking_stands_trigger
before insert or update of origin_airport_id,destination_airport_id,aircraft_id,scheduled_departure,scheduled_arrival on public.flights
for each row execute function public.assign_flight_parking_stands();

-- Assign stands to flights created before this migration.
update public.flights set scheduled_departure=scheduled_departure where status<>'cancelled';

-- Give each parked aircraft a distinct stand at its current airport where possible.
with positioned as(
  select a.id,row_number() over(partition by a.current_airport_id order by a.fleet_number,a.registration) position,a.current_airport_id
  from public.aircraft a where a.current_airport_id is not null
), stands as(
  select s.id,s.airport_id,row_number() over(partition by s.airport_id order by s.priority,s.code) position
  from public.airport_stands s where s.active
)
update public.aircraft a set current_stand_id=s.id
from positioned p join stands s on s.airport_id=p.current_airport_id and s.position=p.position
where a.id=p.id;

create or replace function public.track_aircraft_stand_from_flight() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.aircraft_id is null then return new; end if;
  if new.status='off_block' and old.status is distinct from new.status then
    update public.aircraft set current_stand_id=null,status='assigned' where id=new.aircraft_id;
  elsif new.status in ('on_block','completed') and old.status is distinct from new.status then
    update public.aircraft set current_airport_id=new.destination_airport_id,current_stand_id=new.arrival_stand_id,status='available' where id=new.aircraft_id;
  end if;
  return new;
end$$;
create trigger track_aircraft_stand_from_flight_trigger after update of status on public.flights
for each row execute function public.track_aircraft_stand_from_flight();

alter table public.airport_stands enable row level security;
create policy airport_stands_authenticated_read on public.airport_stands for select to authenticated using(true);
create policy airport_stands_operations_write on public.airport_stands for all to authenticated
using(public.has_any_role(auth.uid(),array['dispatcher','operations_manager','owner','system_administrator']::public.app_role[]))
with check(public.has_any_role(auth.uid(),array['dispatcher','operations_manager','owner','system_administrator']::public.app_role[]));
grant select on public.airport_stands to authenticated;
revoke all on function public.ensure_airport_stands(uuid,integer) from public,anon,authenticated;
grant execute on function public.ensure_airport_stands(uuid,integer) to service_role;
notify pgrst,'reload schema';
