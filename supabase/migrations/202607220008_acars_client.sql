-- Website-managed ACARS client configuration and narrow RLS policies.
create table if not exists public.client_versions(id uuid primary key default gen_random_uuid(),version text unique not null,platform text not null default 'windows',minimum_supported boolean default false,mandatory boolean default false,download_url text,release_notes text,active boolean default true,released_at timestamptz default now());
create table if not exists public.acars_client_settings(key text primary key,value jsonb not null,updated_by uuid references public.profiles,updated_at timestamptz default now());
alter table public.client_versions enable row level security;alter table public.acars_client_settings enable row level security;
create policy client_versions_authenticated_read on public.client_versions for select to authenticated using(active);
create policy acars_settings_authenticated_read on public.acars_client_settings for select to authenticated using(true);
create policy acars_settings_sysadmin_write on public.acars_client_settings for all to authenticated using(public.has_role(auth.uid(),'system_administrator')) with check(public.has_role(auth.uid(),'system_administrator'));
insert into public.client_versions(version,minimum_supported,mandatory,release_notes) values('0.1.0',true,false,'Initial JCars preview') on conflict(version) do nothing;
insert into public.acars_client_settings(key,value) values('telemetry','{"interval_seconds":5,"batch_size":1,"offline_buffer_points":240,"high_resolution":true}'),('simulator','{"allowed":["msfs"],"require_connection":true}'),('behavior','{"minimize_to_tray":true,"allow_autostart":true,"assignment_refresh_seconds":30}') on conflict(key) do nothing;

create policy acars_session_own_read on public.acars_sessions for select to authenticated using(pilot_id=auth.uid() or public.has_any_role(auth.uid(),array['dispatcher','operations_manager','owner','system_administrator']::public.app_role[]));
create policy acars_session_own_insert on public.acars_sessions for insert to authenticated with check(pilot_id=auth.uid() and public.is_flight_crew(auth.uid(),flight_id));
create policy telemetry_own_insert on public.flight_telemetry_points for insert to authenticated with check(exists(select 1 from public.acars_sessions s where s.id=session_id and s.pilot_id=auth.uid() and s.status='active'));
create policy telemetry_own_read on public.flight_telemetry_points for select to authenticated using(exists(select 1 from public.acars_sessions s where s.id=session_id and (s.pilot_id=auth.uid() or public.has_any_role(auth.uid(),array['dispatcher','operations_manager','owner','system_administrator']::public.app_role[]))));
create policy flight_events_own_insert on public.flight_events for insert to authenticated with check(exists(select 1 from public.acars_sessions s where s.id=session_id and s.pilot_id=auth.uid() and s.status='active'));
create policy flight_events_own_read on public.flight_events for select to authenticated using(exists(select 1 from public.acars_sessions s where s.id=session_id and (s.pilot_id=auth.uid() or public.has_any_role(auth.uid(),array['dispatcher','operations_manager','owner','system_administrator']::public.app_role[]))));
notify pgrst,'reload schema';
