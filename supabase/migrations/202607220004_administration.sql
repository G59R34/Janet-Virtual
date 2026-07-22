-- Administrative control plane and crew assignment enforcement.
create table if not exists public.ranks(id uuid primary key default gen_random_uuid(),code text unique not null,name text not null,minimum_hours numeric default 0,sort_order int default 0,active boolean default true);
create table if not exists public.admin_settings(key text primary key,value jsonb not null,security_sensitive boolean default false,updated_by uuid references public.profiles,updated_at timestamptz default now());
alter table public.ranks enable row level security; alter table public.admin_settings enable row level security;
create policy ranks_read on public.ranks for select to authenticated using(true);
create policy admin_settings_ops_read on public.admin_settings for select to authenticated using(not security_sensitive and public.has_any_role(auth.uid(),array['operations_manager','owner','system_administrator']::public.app_role[]) or public.has_role(auth.uid(),'system_administrator'));
create policy admin_settings_sysadmin_write on public.admin_settings for all to authenticated using(public.has_role(auth.uid(),'system_administrator')) with check(public.has_role(auth.uid(),'system_administrator'));
insert into public.ranks(code,name,minimum_hours,sort_order) values ('TRN','Trainee',0,10),('FO','First Officer',10,20),('SFO','Senior First Officer',50,30),('CPT','Captain',100,40),('SCPT','Senior Captain',250,50) on conflict(code) do nothing;
insert into public.admin_settings(key,value,security_sensitive) values ('schedule_generation','{"days_ahead":14,"default_timezone":"America/Los_Angeles"}',false),('public_operations','{"position_delay_minutes":15,"show_callsigns":true}',false),('telemetry_retention','{"high_resolution_days":7,"downsample_after_days":2,"archive_days":365}',false) on conflict(key) do nothing;

create or replace function public.review_application(p_application_id uuid,p_status text,p_notes text default null) returns void language plpgsql security definer set search_path='' as $$
declare app public.applications%rowtype; old_app jsonb;
begin
 if not public.has_any_role(auth.uid(),array['chief_pilot','owner','system_administrator']::public.app_role[]) then raise exception 'insufficient role'; end if;
 if p_status not in ('approved','rejected','waitlisted') then raise exception 'invalid application status'; end if;
 select * into app from public.applications where id=p_application_id for update; if not found then raise exception 'application not found'; end if; old_app:=to_jsonb(app);
 update public.applications set status=p_status,reviewer_id=auth.uid(),reviewer_notes=p_notes,reviewed_at=now() where id=p_application_id;
 if p_status='approved' then
   update public.profiles set role='pilot',status='active',hire_date=coalesce(hire_date,current_date),updated_at=now() where id=app.applicant_user_id;
   update public.user_roles set active=false where user_id=app.applicant_user_id and role='applicant';
   insert into public.user_roles(user_id,role,granted_by) values(app.applicant_user_id,'pilot',auth.uid()) on conflict(user_id,role) do update set active=true,granted_by=excluded.granted_by,granted_at=now(),expires_at=null;
 end if;
 insert into public.notifications(user_id,type,title,body,entity_type,entity_id) values(app.applicant_user_id,'application_result','Application '||p_status,'Crew Administration has '||p_status||' your application.','application',app.id);
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,previous_values,new_values,reason) values(auth.uid(),'application.review','application',app.id,old_app,jsonb_build_object('status',p_status,'reviewer_notes',p_notes),p_notes);
end$$;

create or replace function public.set_user_operational_status(p_user_id uuid,p_status text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare old_profile jsonb;
begin
 if not public.has_any_role(auth.uid(),array['chief_pilot','owner','system_administrator']::public.app_role[]) then raise exception 'insufficient role'; end if;
 if p_status not in ('active','suspended','leave','terminated') then raise exception 'invalid status'; end if;
 select to_jsonb(p) into old_profile from public.profiles p where id=p_user_id for update;
 update public.profiles set status=p_status,updated_at=now() where id=p_user_id;
 if p_status<>'active' then update public.user_roles set active=false where user_id=p_user_id and role not in ('applicant'); end if;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,previous_values,new_values,reason) values(auth.uid(),'user.status_change','profile',p_user_id,old_profile,jsonb_build_object('status',p_status),p_reason);
end$$;

create or replace function public.admin_grant_role(p_user_id uuid,p_role text,p_expires_at timestamptz default null) returns void language plpgsql security definer set search_path='' as $$
declare target_role public.app_role;
begin
 target_role:=p_role::public.app_role;
 if target_role='system_administrator' and not public.has_role(auth.uid(),'system_administrator') then raise exception 'only system administrators may grant this role'; end if;
 if not public.has_any_role(auth.uid(),array['chief_pilot','owner','system_administrator']::public.app_role[]) then raise exception 'insufficient role'; end if;
 insert into public.user_roles(user_id,role,granted_by,expires_at) values(p_user_id,target_role,auth.uid(),p_expires_at) on conflict(user_id,role) do update set active=true,granted_by=excluded.granted_by,granted_at=now(),expires_at=excluded.expires_at;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_values) values(auth.uid(),'role.grant','profile',p_user_id,jsonb_build_object('role',target_role,'expires_at',p_expires_at));
end$$;

create or replace function public.issue_qualification(p_user_id uuid,p_qualification_id uuid,p_expires_at timestamptz default null) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.has_any_role(auth.uid(),array['instructor','chief_pilot','owner','system_administrator']::public.app_role[]) then raise exception 'insufficient role'; end if;
 insert into public.user_qualifications(user_id,qualification_id,issued_by,expires_at,status) values(p_user_id,p_qualification_id,auth.uid(),p_expires_at,'active') on conflict(user_id,qualification_id) do update set issued_by=excluded.issued_by,issued_at=now(),expires_at=excluded.expires_at,status='active';
 insert into public.notifications(user_id,type,title,body,entity_type,entity_id) select p_user_id,'qualification_issued','Qualification issued',q.name||' has been added to your operating record.','qualification',q.id from public.qualifications q where q.id=p_qualification_id;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_values) values(auth.uid(),'qualification.issue','profile',p_user_id,jsonb_build_object('qualification_id',p_qualification_id,'expires_at',p_expires_at));
end$$;

create or replace function public.assign_crew_member(p_flight_id uuid,p_user_id uuid,p_position text) returns uuid language plpgsql security definer set search_path='' as $$
declare f public.flights%rowtype; a public.aircraft%rowtype; assignment_id uuid; required_type uuid;
begin
 if not public.has_any_role(auth.uid(),array['dispatcher','chief_pilot','operations_manager','owner','system_administrator']::public.app_role[]) then raise exception 'insufficient role'; end if;
 if p_position not in ('captain','first_officer','observer','instructor') then raise exception 'invalid crew position'; end if;
 if not exists(select 1 from public.profiles where id=p_user_id and status='active') then raise exception 'crew member is not active'; end if;
 select * into f from public.flights where id=p_flight_id for update; if not found then raise exception 'flight not found'; end if;
 if exists(select 1 from public.crew_assignments ca join public.flights x on x.id=ca.flight_id where ca.user_id=p_user_id and ca.status<>'cancelled' and x.status not in ('cancelled','completed') and tstzrange(x.scheduled_departure,x.scheduled_arrival,'[)') && tstzrange(f.scheduled_departure,f.scheduled_arrival,'[)')) then raise exception 'crew member has an overlapping assignment'; end if;
 if p_position='captain' and not public.has_any_role(p_user_id,array['captain','chief_pilot','owner','system_administrator']::public.app_role[]) then raise exception 'captain role required'; end if;
 if f.aircraft_id is not null then select * into a from public.aircraft where id=f.aircraft_id; required_type:=a.aircraft_type_id; if not exists(select 1 from public.user_qualifications uq join public.qualifications q on q.id=uq.qualification_id where uq.user_id=p_user_id and uq.status='active' and (uq.expires_at is null or uq.expires_at>now()) and (q.aircraft_type_id is null or q.aircraft_type_id=required_type)) then raise exception 'active aircraft qualification required'; end if; end if;
 insert into public.crew_assignments(flight_id,user_id,position,assigned_by) values(p_flight_id,p_user_id,p_position,auth.uid()) returning id into assignment_id;
 update public.flights set captain_id=case when p_position='captain' then p_user_id else captain_id end,first_officer_id=case when p_position='first_officer' then p_user_id else first_officer_id end,status=case when p_position in ('captain','first_officer') then 'crew_assigned' else status end where id=p_flight_id;
 insert into public.notifications(user_id,type,title,body,entity_type,entity_id) values(p_user_id,'flight_assigned','Flight assigned',f.tracking_callsign||' has been assigned to you.','flight',f.id);
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_values) values(auth.uid(),'crew.assign','flight',f.id,jsonb_build_object('user_id',p_user_id,'position',p_position)); return assignment_id;
end$$;
grant execute on function public.review_application(uuid,text,text) to authenticated;
grant execute on function public.set_user_operational_status(uuid,text,text) to authenticated;
grant execute on function public.admin_grant_role(uuid,text,timestamptz) to authenticated;
grant execute on function public.issue_qualification(uuid,uuid,timestamptz) to authenticated;
grant execute on function public.assign_crew_member(uuid,uuid,text) to authenticated;
create policy applications_admin on public.applications for select to authenticated using(public.has_any_role(auth.uid(),array['chief_pilot','owner','system_administrator']::public.app_role[]));
create policy roles_admin_read on public.user_roles for select to authenticated using(user_id=auth.uid() or public.has_any_role(auth.uid(),array['chief_pilot','owner','system_administrator']::public.app_role[]));
create policy qualifications_admin_write on public.user_qualifications for select to authenticated using(user_id=auth.uid() or public.has_any_role(auth.uid(),array['instructor','chief_pilot','owner','system_administrator']::public.app_role[]));
