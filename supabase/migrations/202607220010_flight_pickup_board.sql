-- Expose generated operations to qualified employees and reserve seats atomically.
update public.qualifications q set aircraft_type_id=t.id from public.aircraft_types t where q.code='B737' and t.code='B737' and q.aircraft_type_id is null;
update public.qualifications q set aircraft_type_id=t.id from public.aircraft_types t where q.code in ('B300','BEECH') and t.code='B300' and q.aircraft_type_id is null;

drop policy if exists employee_open_flight_board on public.flights;
create policy employee_open_flight_board on public.flights for select to authenticated using(
 status in ('generated','awaiting_dispatch','released') and
 exists(select 1 from public.profiles p where p.id=auth.uid() and p.status='active') and
 public.has_any_role(auth.uid(),array['pilot','captain','instructor','chief_pilot','owner','system_administrator']::public.app_role[])
);

create or replace function public.reserve_flight(p_flight_id uuid,p_position text default 'first_officer') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid(); f public.flights%rowtype; assignment_id uuid; required_type uuid; callsign text;
 privileged boolean; captain_ok boolean;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 if p_position not in ('captain','first_officer') then raise exception 'Only captain and first officer seats can be reserved'; end if;
 if not exists(select 1 from public.profiles where id=actor and status='active') then raise exception 'Your employee record is not active'; end if;
 if not public.has_any_role(actor,array['pilot','captain','instructor','chief_pilot','owner','system_administrator']::public.app_role[]) then raise exception 'A pilot role is required to pick up flights'; end if;
 privileged:=public.has_any_role(actor,array['chief_pilot','owner','system_administrator']::public.app_role[]);
 captain_ok:=public.has_any_role(actor,array['captain','instructor','chief_pilot','owner','system_administrator']::public.app_role[]);
 if p_position='captain' and not captain_ok then raise exception 'A captain qualification is required for this seat'; end if;

 select * into f from public.flights where id=p_flight_id for update;
 if not found then raise exception 'Flight not found'; end if;
 if f.status not in ('generated','awaiting_dispatch','released') then raise exception 'This flight is no longer open for pickup'; end if;
 if f.scheduled_arrival < now() then raise exception 'Past flights cannot be reserved'; end if;

 if exists(select 1 from public.crew_assignments ca join public.flights other on other.id=ca.flight_id where ca.user_id=actor and ca.status in ('assigned','accepted') and other.status not in ('completed','cancelled') and tstzrange(other.scheduled_departure,other.scheduled_arrival,'[)') && tstzrange(f.scheduled_departure,f.scheduled_arrival,'[)')) then raise exception 'This flight overlaps an existing assignment'; end if;

 select coalesce(a.aircraft_type_id,st.preferred_aircraft_type_id) into required_type from public.flights fl left join public.aircraft a on a.id=fl.aircraft_id left join public.schedule_templates st on st.id=fl.schedule_template_id where fl.id=f.id;
 if required_type is not null and not privileged and not exists(select 1 from public.user_qualifications uq join public.qualifications q on q.id=uq.qualification_id where uq.user_id=actor and uq.status='active' and (uq.expires_at is null or uq.expires_at>now()) and q.active and q.aircraft_type_id=required_type) then raise exception 'An active qualification for this aircraft type is required'; end if;
 if f.aircraft_id is not null and exists(select 1 from public.aircraft a where a.id=f.aircraft_id and (not a.active or a.status in ('maintenance','grounded','stored','retired') or a.current_airport_id is distinct from f.origin_airport_id)) then raise exception 'The assigned aircraft is not operationally available at the origin'; end if;

 insert into public.crew_assignments(flight_id,user_id,position,status,assigned_by) values(f.id,actor,p_position,'accepted',actor) returning id into assignment_id;
 if p_position='captain' then update public.flights set captain_id=actor,status='crew_assigned' where id=f.id; else update public.flights set first_officer_id=actor,status='crew_assigned' where id=f.id; end if;
 callsign:=f.tracking_callsign;
 insert into public.notifications(user_id,type,title,body,entity_type,entity_id) values(actor,'flight_assignment','Flight pickup confirmed',callsign||' is now in your assignments.','flight',f.id);
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_values) values(actor,'flight.reserve','flight',f.id,jsonb_build_object('position',p_position,'assignment_id',assignment_id));
 return jsonb_build_object('assignmentId',assignment_id,'flightId',f.id,'callsign',callsign,'position',p_position);
exception when unique_violation then raise exception 'That seat was just claimed or you are already assigned to this flight';
end$$;

revoke all on function public.reserve_flight(uuid,text) from public;
grant execute on function public.reserve_flight(uuid,text) to authenticated;
notify pgrst,'reload schema';
