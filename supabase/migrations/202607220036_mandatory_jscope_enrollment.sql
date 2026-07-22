-- Every JCars tracking session is atomically enrolled in tactical ATC.
create or replace function public.start_mandatory_acars_session(
  p_flight_id uuid,p_aircraft_id uuid,p_simulator text,p_client_version text
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); created public.acars_sessions%rowtype; tactical public.tactical_aircraft_sessions%rowtype; position public.tactical_positions%rowtype;
begin
  if actor is null then raise exception 'Authentication required';end if;
  if not exists(select 1 from public.crew_assignments ca join public.flights f on f.id=ca.flight_id where ca.flight_id=p_flight_id and ca.user_id=actor and f.aircraft_id=p_aircraft_id) then raise exception 'No eligible assignment for this aircraft';end if;
  select * into position from public.tactical_positions where id='nellis_control' and active;
  if not found then raise exception 'Mandatory ATC position is unavailable';end if;
  insert into public.acars_sessions(flight_id,pilot_id,aircraft_id,simulator,client_version)
  values(p_flight_id,actor,p_aircraft_id,left(p_simulator,80),left(p_client_version,40)) returning * into created;
  insert into public.tactical_aircraft_sessions(acars_session_id,pilot_id,flight_id,current_position_id,current_channel_id,safety_notice_accepted_at)
  values(created.id,actor,p_flight_id,position.id,position.channel_id,now()) returning * into tactical;
  insert into public.tactical_activity_log(event_type,actor_id,actor_kind,aircraft_session_id,position_id,payload)
  values('mandatory_atc_enrollment',actor,'pilot',tactical.id,position.id,jsonb_build_object('acars_session_id',created.id));
  return jsonb_build_object('id',created.id,'tactical',jsonb_build_object('id',tactical.id,'status',tactical.status,'positionId',position.id,'positionName',position.display_name,'controllerCallsign',position.radio_callsign,'displayFrequency',position.display_frequency,'channelId',position.channel_id,'voiceState',tactical.voice_state,'suspensionReason',null));
end$$;
revoke all on function public.start_mandatory_acars_session(uuid,uuid,text,text) from public,anon;
grant execute on function public.start_mandatory_acars_session(uuid,uuid,text,text) to authenticated;
notify pgrst,'reload schema';
