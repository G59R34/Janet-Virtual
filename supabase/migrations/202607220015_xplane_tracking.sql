-- Enable the X-Plane 11/12 provider in website-managed JCars configuration.
insert into public.client_versions(version,minimum_supported,mandatory,release_notes)
values('0.3.0',true,false,'Adds native X-Plane UDP dataref tracking alongside MSFS SimConnect')
on conflict(version) do nothing;
insert into public.acars_client_settings(key,value)
values('simulator','{"allowed":["msfs","xplane11","xplane12"],"require_connection":true,"xplane_udp_port":49000}')
on conflict(key) do update set value=excluded.value,updated_at=now();
notify pgrst,'reload schema';
