-- Pilot career progression, an immutable merit-credit ledger, achievements, and weekly objectives.
-- Credits are recognition currency only; qualifications and operational roles remain authoritative.

-- The 20260722 foundation does not include the legacy timestamp trigger helper.
-- Keep this migration compatible with both foundation histories.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

alter table public.ranks
  add column if not exists minimum_sectors integer not null default 0,
  add column if not exists minimum_proficiency numeric(5,2) not null default 0,
  add column if not exists description text;

update public.ranks set minimum_hours=0,minimum_sectors=0,minimum_proficiency=0,description='Complete initial training and supervised operations.' where code='TRN';
update public.ranks set minimum_hours=3,minimum_sectors=5,minimum_proficiency=75,description='Qualified for standard line operations.' where code='FO';
update public.ranks set minimum_hours=15,minimum_sectors=20,minimum_proficiency=80,description='Demonstrated consistency across the network.' where code='SFO';
update public.ranks set minimum_hours=40,minimum_sectors=50,minimum_proficiency=85,description='Eligible for captain development and command duties.' where code='CPT';
update public.ranks set minimum_hours=100,minimum_sectors=125,minimum_proficiency=88,description='Trusted for advanced missions and mentorship.' where code='SCPT';
insert into public.ranks(code,name,minimum_hours,minimum_sectors,minimum_proficiency,sort_order,active,description)
values('CCPT','Check Captain',200,250,90,60,true,'Career milestone; instructor authority still requires a staff-issued qualification.')
on conflict(code) do update set name=excluded.name,minimum_hours=excluded.minimum_hours,minimum_sectors=excluded.minimum_sectors,minimum_proficiency=excluded.minimum_proficiency,sort_order=excluded.sort_order,description=excluded.description;

create table public.pilot_progression(
  user_id uuid primary key references public.profiles(id) on delete cascade,
  grade_code text not null default 'TRN' references public.ranks(code),
  accepted_sectors integer not null default 0 check(accepted_sectors>=0),
  accepted_minutes integer not null default 0 check(accepted_minutes>=0),
  proficiency numeric(5,2) not null default 0 check(proficiency between 0 and 100),
  credit_balance integer not null default 0 check(credit_balance>=0),
  lifetime_credits integer not null default 0 check(lifetime_credits>=0),
  distinct_routes integer not null default 0 check(distinct_routes>=0),
  last_rewarded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.economy_ledger(
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount integer not null check(amount<>0),
  balance_after integer not null check(balance_after>=0),
  entry_type text not null check(entry_type in ('flight_reward','achievement_reward','objective_reward','redemption','adjustment')),
  description text not null,
  source_pirep_id uuid references public.pireps(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now()
);
create unique index economy_ledger_one_flight_reward_idx on public.economy_ledger(source_pirep_id) where source_pirep_id is not null and entry_type='flight_reward';
create index economy_ledger_user_time_idx on public.economy_ledger(user_id,created_at desc);

create table public.achievement_definitions(
  code text primary key,
  name text not null,
  description text not null,
  credit_reward integer not null default 0 check(credit_reward>=0),
  sort_order integer not null default 0,
  active boolean not null default true
);
create table public.pilot_achievements(
  user_id uuid not null references public.profiles(id) on delete cascade,
  achievement_code text not null references public.achievement_definitions(code) on delete restrict,
  awarded_at timestamptz not null default now(),
  source_pirep_id uuid references public.pireps(id) on delete set null,
  primary key(user_id,achievement_code)
);

create table public.pilot_weekly_objectives(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  week_start date not null,
  objective_code text not null check(objective_code in ('SECTORS_3','QUALITY_85','ROUTE_VARIETY')),
  title text not null,
  target integer not null check(target>0),
  progress integer not null default 0 check(progress>=0),
  credit_reward integer not null check(credit_reward>=0),
  completed_at timestamptz,
  rewarded_at timestamptz,
  created_at timestamptz not null default now(),
  unique(user_id,week_start,objective_code),
  check(rewarded_at is null or completed_at is not null)
);

insert into public.achievement_definitions(code,name,description,credit_reward,sort_order) values
 ('FIRST_FLIGHT','First Flight','Complete an accepted JANET Virtual operation.',100,10),
 ('TEN_SECTORS','Line Regular','Complete 10 accepted sectors.',150,20),
 ('FIFTY_SECTORS','Network Veteran','Complete 50 accepted sectors.',400,30),
 ('FIVE_ROUTES','Route Explorer','Complete five distinct city pairs.',150,40),
 ('TEN_ROUTES','Network Explorer','Complete ten distinct city pairs.',300,50),
 ('EXEMPLARY','Exemplary Proficiency','Reach a rolling proficiency of 93 or higher after at least five flights.',250,60)
on conflict(code) do update set name=excluded.name,description=excluded.description,credit_reward=excluded.credit_reward,sort_order=excluded.sort_order;

alter table public.pilot_progression enable row level security;
alter table public.economy_ledger enable row level security;
alter table public.achievement_definitions enable row level security;
alter table public.pilot_achievements enable row level security;
alter table public.pilot_weekly_objectives enable row level security;

create policy progression_own_read on public.pilot_progression for select to authenticated using(user_id=auth.uid() or public.has_any_role(auth.uid(),array['chief_pilot','owner','system_administrator']::public.app_role[]));
create policy ledger_own_read on public.economy_ledger for select to authenticated using(user_id=auth.uid() or public.has_any_role(auth.uid(),array['chief_pilot','owner','system_administrator']::public.app_role[]));
create policy achievements_catalog_read on public.achievement_definitions for select to authenticated using(active);
create policy pilot_achievements_own_read on public.pilot_achievements for select to authenticated using(user_id=auth.uid() or public.has_any_role(auth.uid(),array['chief_pilot','owner','system_administrator']::public.app_role[]));
create policy objectives_own_read on public.pilot_weekly_objectives for select to authenticated using(user_id=auth.uid() or public.has_any_role(auth.uid(),array['chief_pilot','owner','system_administrator']::public.app_role[]));

create or replace function public.process_pirep_progression(p_pirep_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  report public.pireps%rowtype; fl public.flights%rowtype; progress public.pilot_progression%rowtype;
  accepted_count int; accepted_minutes_total int; route_count int; same_route_recent int; same_route_ever int; weekly_sectors int; weekly_quality int; weekly_routes int;
  rolling_score numeric; quality_multiplier numeric; variety_multiplier numeric; base_credits int; awarded_credits int; mission_bonus int; first_route_bonus int;
  new_grade text; old_grade text; week_monday date; achievement record; objective record; achievement_balance int;
begin
  select * into report from public.pireps where id=p_pirep_id and status in ('automatically_accepted','accepted') for update;
  if not found then return jsonb_build_object('processed',false,'reason','pirep_not_accepted'); end if;
  if exists(select 1 from public.economy_ledger where source_pirep_id=report.id and entry_type='flight_reward') then
    return jsonb_build_object('processed',false,'reason','already_rewarded');
  end if;
  select * into fl from public.flights where id=report.flight_id;
  insert into public.pilot_progression(user_id) values(report.pilot_id) on conflict(user_id) do nothing;
  select * into progress from public.pilot_progression where user_id=report.pilot_id for update;
  old_grade:=progress.grade_code;

  select count(*),coalesce(sum(p.flight_minutes),0),coalesce(avg(p.score),0)
    into accepted_count,accepted_minutes_total,rolling_score
  from (select pr.flight_minutes,pr.score from public.pireps pr where pr.pilot_id=report.pilot_id and pr.status in ('automatically_accepted','accepted') order by pr.submitted_at desc limit 10) p;
  select count(distinct (f.origin_airport_id,f.destination_airport_id)) into route_count
  from public.pireps pr join public.flights f on f.id=pr.flight_id
  where pr.pilot_id=report.pilot_id and pr.status in ('automatically_accepted','accepted');
  select count(*) into same_route_recent
  from public.pireps pr join public.flights prior on prior.id=pr.flight_id
  where pr.pilot_id=report.pilot_id and pr.id<>report.id and pr.status in ('automatically_accepted','accepted')
    and pr.submitted_at>=now()-interval '30 days' and prior.origin_airport_id=fl.origin_airport_id and prior.destination_airport_id=fl.destination_airport_id;
  select count(*) into same_route_ever
  from public.pireps pr join public.flights prior on prior.id=pr.flight_id
  where pr.pilot_id=report.pilot_id and pr.id<>report.id and pr.status in ('automatically_accepted','accepted')
    and prior.origin_airport_id=fl.origin_airport_id and prior.destination_airport_id=fl.destination_airport_id;

  quality_multiplier:=least(1.20,greatest(0.75,0.75+(coalesce(report.score,0)/100.0)*0.45));
  variety_multiplier:=case when same_route_recent>=5 then 0.65 when same_route_recent=4 then 0.75 when same_route_recent=3 then 0.85 else 1 end;
  first_route_bonus:=case when same_route_ever=0 then 40 else 0 end;
  mission_bonus:=case when fl.mission_id is not null then 100 else 0 end;
  base_credits:=100+least(coalesce(report.flight_minutes,0),180);
  awarded_credits:=greatest(1,round(base_credits*quality_multiplier*variety_multiplier)+first_route_bonus+mission_bonus);

  select r.code into new_grade from public.ranks r
  where r.active and accepted_minutes_total/60.0>=r.minimum_hours and accepted_count>=r.minimum_sectors
    and (r.code='TRN' or rolling_score>=r.minimum_proficiency)
  order by r.sort_order desc limit 1;
  new_grade:=coalesce(new_grade,'TRN');
  update public.pilot_progression set grade_code=new_grade,accepted_sectors=accepted_count,accepted_minutes=accepted_minutes_total,
    proficiency=round(rolling_score,2),credit_balance=credit_balance+awarded_credits,lifetime_credits=lifetime_credits+awarded_credits,
    distinct_routes=route_count,last_rewarded_at=now(),updated_at=now() where user_id=report.pilot_id returning * into progress;
  update public.profiles set rank=new_grade where id=report.pilot_id;
  insert into public.economy_ledger(user_id,amount,balance_after,entry_type,description,source_pirep_id,metadata)
  values(report.pilot_id,awarded_credits,progress.credit_balance,'flight_reward','Accepted flight reward',report.id,
    jsonb_build_object('base',base_credits,'quality_multiplier',quality_multiplier,'variety_multiplier',variety_multiplier,'first_route_bonus',first_route_bonus,'mission_bonus',mission_bonus,'score',report.score));

  for achievement in
    select a.* from public.achievement_definitions a where a.active and not exists(select 1 from public.pilot_achievements pa where pa.user_id=report.pilot_id and pa.achievement_code=a.code)
      and ((a.code='FIRST_FLIGHT' and accepted_count>=1) or (a.code='TEN_SECTORS' and accepted_count>=10) or (a.code='FIFTY_SECTORS' and accepted_count>=50)
        or (a.code='FIVE_ROUTES' and route_count>=5) or (a.code='TEN_ROUTES' and route_count>=10) or (a.code='EXEMPLARY' and accepted_count>=5 and rolling_score>=93))
  loop
    insert into public.pilot_achievements(user_id,achievement_code,source_pirep_id) values(report.pilot_id,achievement.code,report.id);
    update public.pilot_progression set credit_balance=credit_balance+achievement.credit_reward,lifetime_credits=lifetime_credits+achievement.credit_reward,updated_at=now()
      where user_id=report.pilot_id returning credit_balance into achievement_balance;
    insert into public.economy_ledger(user_id,amount,balance_after,entry_type,description,metadata)
      values(report.pilot_id,achievement.credit_reward,achievement_balance,'achievement_reward',achievement.name,jsonb_build_object('achievement_code',achievement.code));
    insert into public.notifications(user_id,type,title,body,entity_type,entity_id)
      values(report.pilot_id,'achievement','Achievement unlocked: '||achievement.name,achievement.description||' +'||achievement.credit_reward||' credits.','pirep',report.id);
  end loop;

  week_monday:=(current_date-(extract(isodow from current_date)::int-1));
  insert into public.pilot_weekly_objectives(user_id,week_start,objective_code,title,target,credit_reward) values
    (report.pilot_id,week_monday,'SECTORS_3','Complete 3 accepted sectors',3,150),
    (report.pilot_id,week_monday,'QUALITY_85','Complete 2 flights scoring 85+',2,125),
    (report.pilot_id,week_monday,'ROUTE_VARIETY','Fly 2 distinct routes',2,125)
  on conflict(user_id,week_start,objective_code) do nothing;
  select count(*) into weekly_sectors from public.pireps pr where pr.pilot_id=report.pilot_id and pr.status in ('automatically_accepted','accepted') and pr.submitted_at>=week_monday;
  select count(*) into weekly_quality from public.pireps pr where pr.pilot_id=report.pilot_id and pr.status in ('automatically_accepted','accepted') and pr.score>=85 and pr.submitted_at>=week_monday;
  select count(distinct (wf.origin_airport_id,wf.destination_airport_id)) into weekly_routes from public.pireps pr join public.flights wf on wf.id=pr.flight_id where pr.pilot_id=report.pilot_id and pr.status in ('automatically_accepted','accepted') and pr.submitted_at>=week_monday;
  update public.pilot_weekly_objectives set progress=case objective_code when 'SECTORS_3' then weekly_sectors when 'QUALITY_85' then weekly_quality else weekly_routes end,
    completed_at=case when case objective_code when 'SECTORS_3' then weekly_sectors when 'QUALITY_85' then weekly_quality else weekly_routes end>=target then coalesce(completed_at,now()) else null end
  where user_id=report.pilot_id and week_start=week_monday;
  for objective in select * from public.pilot_weekly_objectives where user_id=report.pilot_id and week_start=week_monday and completed_at is not null and rewarded_at is null for update
  loop
    update public.pilot_progression set credit_balance=credit_balance+objective.credit_reward,lifetime_credits=lifetime_credits+objective.credit_reward,updated_at=now()
      where user_id=report.pilot_id returning credit_balance into achievement_balance;
    update public.pilot_weekly_objectives set rewarded_at=now() where id=objective.id;
    insert into public.economy_ledger(user_id,amount,balance_after,entry_type,description,metadata)
      values(report.pilot_id,objective.credit_reward,achievement_balance,'objective_reward',objective.title,jsonb_build_object('objective_id',objective.id));
  end loop;

  if new_grade<>old_grade then
    insert into public.notifications(user_id,type,title,body,entity_type,entity_id)
    select report.pilot_id,'promotion','Career grade advanced','You have advanced to '||r.name||'.','pirep',report.id from public.ranks r where r.code=new_grade;
  end if;
  select * into progress from public.pilot_progression where user_id=report.pilot_id;
  return jsonb_build_object('processed',true,'credits',awarded_credits,'balance',progress.credit_balance,'grade',new_grade,'proficiency',progress.proficiency);
end$$;
revoke all on function public.process_pirep_progression(uuid) from public,anon,authenticated;

create or replace function public.reward_accepted_pirep() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.status in ('automatically_accepted','accepted') and (tg_op='INSERT' or old.status is distinct from new.status) then
    perform public.process_pirep_progression(new.id);
  end if;
  return new;
end$$;
drop trigger if exists pirep_progression_reward on public.pireps;
create trigger pirep_progression_reward after insert or update of status on public.pireps for each row execute function public.reward_accepted_pirep();

create trigger pilot_progression_set_updated_at before update on public.pilot_progression for each row execute function public.set_updated_at();

-- Initialize current totals for existing pilots. Existing reports receive career history but no retroactive credits.
insert into public.pilot_progression(user_id,grade_code,accepted_sectors,accepted_minutes,proficiency,distinct_routes)
select p.id,coalesce(best.code,'TRN'),coalesce(stats.sectors,0),coalesce(stats.minutes,0),coalesce(stats.proficiency,0),coalesce(stats.routes,0)
from public.profiles p
left join lateral(
  select count(*)::int sectors,coalesce(sum(pr.flight_minutes),0)::int minutes,
    coalesce((select avg(recent.score) from (select score from public.pireps rp where rp.pilot_id=p.id and rp.status in ('automatically_accepted','accepted') order by submitted_at desc limit 10) recent),0) proficiency,
    count(distinct (f.origin_airport_id,f.destination_airport_id))::int routes
  from public.pireps pr join public.flights f on f.id=pr.flight_id where pr.pilot_id=p.id and pr.status in ('automatically_accepted','accepted')
) stats on true
left join lateral(select r.code from public.ranks r where r.active and stats.minutes/60.0>=r.minimum_hours and stats.sectors>=r.minimum_sectors and (r.code='TRN' or stats.proficiency>=r.minimum_proficiency) order by r.sort_order desc limit 1) best on true
on conflict(user_id) do nothing;

notify pgrst,'reload schema';
