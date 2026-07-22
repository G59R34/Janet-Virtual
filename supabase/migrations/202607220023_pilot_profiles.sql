-- Editable member profiles and sanitized public/internal pilot directories.
alter table public.profiles add column if not exists public_profile boolean not null default false;
alter table public.profiles add column if not exists bio text check(bio is null or char_length(bio)<=600);

create or replace function public.get_public_pilots()
returns table(id uuid,employee_number text,display_name text,primary_role text,rank text,bio text,home_station text,hire_date date,vatsim_cid text,flight_hours numeric,completed_flights bigint)
language sql stable security definer set search_path=''
as $$
 select p.id,p.employee_number,p.display_name,p.role::text,p.rank,p.bio,coalesce(a.display_label,a.local_code,a.iata,a.icao),p.hire_date,p.vatsim_cid,
  coalesce(round(sum(pr.flight_minutes) filter(where pr.status in ('automatically_accepted','accepted'))/60.0,1),0),
  count(pr.id) filter(where pr.status in ('automatically_accepted','accepted'))
 from public.profiles p
 left join public.airports a on a.id=p.home_base_id
 left join public.pireps pr on pr.pilot_id=p.id
 where p.public_profile and p.status='active'
 group by p.id,a.display_label,a.local_code,a.iata,a.icao
 order by p.display_name
$$;
revoke all on function public.get_public_pilots() from public;
grant execute on function public.get_public_pilots() to anon,authenticated;

create or replace function public.get_internal_pilots()
returns table(id uuid,employee_number text,display_name text,primary_role text,rank text,bio text,home_station text,hire_date date,vatsim_cid text,ivao_id text,status text,public_profile boolean,roles text[],flight_hours numeric,completed_flights bigint)
language plpgsql stable security definer set search_path=''
as $$
begin
 if auth.uid() is null then raise exception 'authentication required'; end if;
 return query
 select p.id,p.employee_number,p.display_name,p.role::text,p.rank,p.bio,coalesce(a.display_label,a.local_code,a.iata,a.icao),p.hire_date,p.vatsim_cid,p.ivao_id,p.status,p.public_profile,
  coalesce((select array_agg(ur.role::text order by ur.role::text) from public.user_roles ur where ur.user_id=p.id and ur.active and (ur.expires_at is null or ur.expires_at>now())),array[]::text[]),
  coalesce(round(sum(pr.flight_minutes) filter(where pr.status in ('automatically_accepted','accepted'))/60.0,1),0),
  count(pr.id) filter(where pr.status in ('automatically_accepted','accepted'))
 from public.profiles p
 left join public.airports a on a.id=p.home_base_id
 left join public.pireps pr on pr.pilot_id=p.id
 where p.status<>'terminated' and exists(select 1 from public.user_roles ur where ur.user_id=p.id and ur.active and ur.role in ('pilot','captain','instructor','chief_pilot','owner','system_administrator'))
 group by p.id,a.display_label,a.local_code,a.iata,a.icao
 order by p.display_name;
end$$;
revoke all on function public.get_internal_pilots() from public,anon;
grant execute on function public.get_internal_pilots() to authenticated;
notify pgrst,'reload schema';
