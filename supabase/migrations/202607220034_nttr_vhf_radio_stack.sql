-- Civil VHF channel plan for simulator COM-stack compatibility.
update public.tactical_positions set display_frequency=case id
 when 'nellis_control' then '125.100' when 'dreamland' then '128.850'
 when 'groom_ground' then '121.800' when 'groom_tower' then '118.300'
 when 'tonopah_ground' then '121.900' when 'tonopah_tower' then '120.800'
 else display_frequency end
where id in ('nellis_control','dreamland','groom_ground','groom_tower','tonopah_ground','tonopah_tower');

create or replace function public.get_jscope_snapshot(p_token text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare session public.jscope_sessions%rowtype;
begin
 select * into session from public.valid_jscope_session(p_token);if not found then raise exception 'Invalid or expired JScope session';end if;
 update public.jscope_sessions set last_seen_at=now() where id=session.id;
 return jsonb_build_object('generatedAt',now(),'aircraft',(
  select coalesce(jsonb_agg(jsonb_build_object(
   'id',a.id,'callsign',f.tracking_callsign,'aircraftType',t.code,'latitude',latest.latitude,'longitude',latest.longitude,
   'altitude',latest.altitude,'groundSpeed',latest.ground_speed,'heading',latest.heading,'verticalSpeed',latest.vertical_speed,
   'origin',o.local_code,'destination',d.local_code,'positionId',a.current_position_id,'channelId',a.current_channel_id,
   'tacticalStatus',a.status,'communicationsStatus',a.voice_state,'requiredFrequency',position.display_frequency,
   'com1Active',(latest.payload->>'com1Active')::numeric,'com1Standby',(latest.payload->>'com1Standby')::numeric,
   'com2Active',(latest.payload->>'com2Active')::numeric,'com2Standby',(latest.payload->>'com2Standby')::numeric,
   'transponderCode',(latest.payload->>'transponderCode')::numeric,
   'radioTuned',abs(coalesce((latest.payload->>'com1Active')::numeric,0)-position.display_frequency::numeric)<0.006 or abs(coalesce((latest.payload->>'com2Active')::numeric,0)-position.display_frequency::numeric)<0.006
  )),'[]'::jsonb)
  from public.tactical_aircraft_sessions a join public.acars_sessions ac on ac.id=a.acars_session_id join public.flights f on f.id=a.flight_id
  join public.tactical_positions position on position.id=a.current_position_id
  left join public.aircraft craft on craft.id=ac.aircraft_id left join public.aircraft_types t on t.id=craft.aircraft_type_id
  left join public.airports o on o.id=f.origin_airport_id left join public.airports d on d.id=f.destination_airport_id
  left join lateral(select tp.* from public.flight_telemetry_points tp where tp.session_id=ac.id order by tp.recorded_at desc limit 1) latest on true
  where a.status in ('active','suspended') and ac.status='active'
 ),'positions',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'displayName',p.display_name,'radioCallsign',p.radio_callsign,'displayFrequency',p.display_frequency,'channelId',p.channel_id)),'[]'::jsonb) from public.tactical_positions p where p.active));
end$$;

notify pgrst,'reload schema';
