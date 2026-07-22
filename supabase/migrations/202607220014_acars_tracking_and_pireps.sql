-- Authoritative ACARS ingestion, automatic phase events, and server-compiled PIREPs.
insert into public.client_versions(version,minimum_supported,mandatory,release_notes) values('0.2.0',true,false,'Native MSFS SimConnect tracking, automatic flight phases, and compiled PIREPs') on conflict(version) do nothing;
create or replace function public.ingest_acars_point(p_session_id uuid,p_latitude double precision,p_longitude double precision,p_altitude int,p_heading int,p_ground_speed int,p_vertical_speed int,p_fuel numeric,p_on_ground boolean,p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.acars_sessions%rowtype;fl public.flights%rowtype;previous public.flight_telemetry_points%rowtype;phase public.flight_status;event_name text;
begin
 select * into s from public.acars_sessions where id=p_session_id and pilot_id=auth.uid() and status='active' for update;
 if not found then raise exception 'Invalid or inactive ACARS session'; end if;
 select * into fl from public.flights where id=s.flight_id for update;
 select * into previous from public.flight_telemetry_points where session_id=s.id order by recorded_at desc limit 1;
 insert into public.flight_telemetry_points(session_id,latitude,longitude,altitude,heading,ground_speed,vertical_speed,fuel,on_ground,payload) values(s.id,p_latitude,p_longitude,p_altitude,p_heading,p_ground_speed,p_vertical_speed,p_fuel,p_on_ground,coalesce(p_payload,'{}'));

 phase:=fl.status;
 if not p_on_ground then phase:='airborne';
 elsif previous.id is not null and not previous.on_ground and p_on_ground then phase:='landed';event_name:='landing';
 elsif p_ground_speed>=3 and fl.status in ('crew_assigned','briefing_ready','preflight','boarding','ready','released') then phase:='off_block';event_name:='off_block';
 elsif p_ground_speed<2 and coalesce((p_payload->>'engineState')::boolean,false)=false and fl.status='landed' then phase:='on_block';event_name:='on_block';
 elsif fl.status in ('crew_assigned','briefing_ready','released') and coalesce((p_payload->>'engineState')::boolean,false) then phase:='preflight';
 end if;
 if phase is distinct from fl.status then
  update public.flights set status=phase,
   actual_off_block=case when phase='off_block' then coalesce(actual_off_block,now()) else actual_off_block end,
   actual_takeoff=case when phase='airborne' then coalesce(actual_takeoff,now()) else actual_takeoff end,
   actual_landing=case when phase='landed' then coalesce(actual_landing,now()) else actual_landing end,
   actual_on_block=case when phase='on_block' then coalesce(actual_on_block,now()) else actual_on_block end
  where id=fl.id;
  insert into public.flight_events(session_id,event_type,payload) values(s.id,coalesce(event_name,phase::text),jsonb_build_object('altitude',p_altitude,'ground_speed',p_ground_speed,'vertical_speed',p_vertical_speed));
 end if;
 return jsonb_build_object('accepted',true,'phase',phase,'recordedAt',now());
end$$;
revoke all on function public.ingest_acars_point(uuid,double precision,double precision,int,int,int,int,numeric,boolean,jsonb) from public;
grant execute on function public.ingest_acars_point(uuid,double precision,double precision,int,int,int,int,numeric,boolean,jsonb) to authenticated;

create or replace function public.complete_acars_session(p_session_id uuid,p_remarks text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.acars_sessions%rowtype;fl public.flights%rowtype;first_point public.flight_telemetry_points%rowtype;last_point public.flight_telemetry_points%rowtype;started timestamptz;ended timestamptz;air_start timestamptz;air_end timestamptz;landing_rate int;point_count int;air_points int;violations jsonb:='[]';score numeric:=100;report public.pireps%rowtype;
begin
 select * into s from public.acars_sessions where id=p_session_id and pilot_id=auth.uid() and status='active' for update;
 if not found then raise exception 'Active ACARS session not found'; end if;
 select * into fl from public.flights where id=s.flight_id for update;
 select count(*),min(recorded_at),max(recorded_at),count(*) filter(where not on_ground),min(recorded_at) filter(where not on_ground),max(recorded_at) filter(where not on_ground) into point_count,started,ended,air_points,air_start,air_end from public.flight_telemetry_points where session_id=s.id;
 if point_count<2 then raise exception 'Not enough telemetry has been recorded to compile a trip report'; end if;
 select * into first_point from public.flight_telemetry_points where session_id=s.id order by recorded_at limit 1;
 select * into last_point from public.flight_telemetry_points where session_id=s.id order by recorded_at desc limit 1;
 select min(vertical_speed) into landing_rate from (select vertical_speed,on_ground,lag(on_ground) over(order by recorded_at) was_on_ground from public.flight_telemetry_points where session_id=s.id) x where on_ground and was_on_ground=false;
 if air_points=0 then violations:=violations||'"No airborne phase detected"'::jsonb;score:=score-35;end if;
 if landing_rate is null then violations:=violations||'"Landing not detected"'::jsonb;score:=score-20;end if;
 if exists(select 1 from public.flight_telemetry_points where session_id=s.id and coalesce((payload->>'paused')::boolean,false)) then violations:=violations||'"Simulator pause detected"'::jsonb;score:=score-10;end if;
 score:=greatest(0,score-case when landing_rate < -600 then 15 else 0 end);
 insert into public.pireps(flight_id,pilot_id,aircraft_id,simulator,addon,block_minutes,flight_minutes,fuel_used,landing_rate,route_flown,remarks,detected_violations,score,status)
 values(fl.id,s.pilot_id,s.aircraft_id,s.simulator,'JCars '||s.client_version,greatest(1,ceil(extract(epoch from ended-started)/60)::int),greatest(1,coalesce(ceil(extract(epoch from air_end-air_start)/60)::int,0)),greatest(0,first_point.fuel-last_point.fuel),landing_rate,coalesce(fl.route_string,fl.tracking_callsign),nullif(trim(p_remarks),''),violations,score,(case when score>=85 then 'automatically_accepted' else 'manual_review' end)::public.pirep_status)
 on conflict(flight_id) do update set block_minutes=excluded.block_minutes,flight_minutes=excluded.flight_minutes,fuel_used=excluded.fuel_used,landing_rate=excluded.landing_rate,route_flown=excluded.route_flown,remarks=excluded.remarks,detected_violations=excluded.detected_violations,score=excluded.score,status=excluded.status,submitted_at=now() returning * into report;
 update public.acars_sessions set status='completed',ended_at=now() where id=s.id;
 update public.flights set status=(case when report.status='automatically_accepted' then 'completed' else 'pirep_pending' end)::public.flight_status where id=fl.id;
 update public.crew_assignments set status='completed' where flight_id=fl.id and user_id=s.pilot_id;
 update public.aircraft set current_airport_id=fl.destination_airport_id,status='available',total_hours=total_hours+(report.flight_minutes/60.0),total_cycles=total_cycles+case when landing_rate is null then 0 else 1 end where id=s.aircraft_id;
 insert into public.notifications(user_id,type,title,body,entity_type,entity_id) values(s.pilot_id,'pirep_submitted','Trip report compiled',fl.tracking_callsign||' scored '||report.score||' and was submitted.','pirep',report.id);
 return jsonb_build_object('pirepId',report.id,'status',report.status,'score',report.score,'blockMinutes',report.block_minutes,'flightMinutes',report.flight_minutes,'fuelUsed',report.fuel_used,'landingRate',report.landing_rate,'violations',report.detected_violations);
end$$;
revoke all on function public.complete_acars_session(uuid,text) from public;
grant execute on function public.complete_acars_session(uuid,text) to authenticated;
notify pgrst,'reload schema';
