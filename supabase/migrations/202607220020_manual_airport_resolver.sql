-- Applied separately from 019 so projects that already recorded 019 receive the RLS fix.
create or replace function public.resolve_manual_airport(p_code text)
returns public.airports
language plpgsql
security definer
set search_path = public
as $$
declare v_code text := upper(trim(p_code)); v_airport public.airports;
begin
  if not public.has_any_role(auth.uid(), array['dispatcher','chief_pilot','operations_manager','owner','system_administrator']::public.app_role[]) then
    raise exception 'Not authorized to create operational airports';
  end if;
  if v_code !~ '^[A-Z0-9]{2,8}$' then raise exception 'Invalid airport code'; end if;
  select * into v_airport from public.airports where icao=v_code or iata=v_code or local_code=v_code limit 1;
  if found then return v_airport; end if;
  insert into public.airports(icao,iata,local_code,name,country,latitude,longitude,timezone,airport_type,simulator_airport_code,preferred_navigation_code,display_label,active,public_visibility,notes)
  values(case when length(v_code)=4 then v_code end,case when length(v_code)=3 then v_code end,v_code,'Manual airport '||v_code,'UN',0,0,'UTC','manual',v_code,v_code,v_code,true,false,'Created for SimBrief planning; geographic metadata pending verification.')
  returning * into v_airport;
  return v_airport;
end;
$$;
grant execute on function public.resolve_manual_airport(text) to authenticated;
notify pgrst, 'reload schema';
