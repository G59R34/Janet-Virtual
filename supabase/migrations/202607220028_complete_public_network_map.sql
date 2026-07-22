-- Return the complete active station network for the public operations map.
-- This exposes station labels and coordinates only; no restricted operational
-- metadata is included.
create or replace function public.get_public_network_map()
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
select jsonb_build_object(
  'stations',(
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',a.id,
      'code',coalesce(a.local_code,a.iata,a.icao),
      'label',coalesce(a.display_label,a.name),
      'latitude',a.latitude,
      'longitude',a.longitude
    ) order by a.local_code,a.display_label,a.name),'[]'::jsonb)
    from public.airports a
    where a.active
  ),
  'routes',(
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',r.id,
      'origin_latitude',o.latitude,
      'origin_longitude',o.longitude,
      'destination_latitude',d.latitude,
      'destination_longitude',d.longitude
    )),'[]'::jsonb)
    from public.routes r
    join public.airports o on o.id=r.origin_airport_id
    join public.airports d on d.id=r.destination_airport_id
    where r.active and o.active and d.active
  )
)
$$;
revoke all on function public.get_public_network_map() from public;
grant execute on function public.get_public_network_map() to anon,authenticated;
notify pgrst,'reload schema';
