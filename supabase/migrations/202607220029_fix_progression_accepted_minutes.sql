-- Avoid ambiguity between the progression column and the PL/pgSQL accumulator.
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
notify pgrst,'reload schema';
