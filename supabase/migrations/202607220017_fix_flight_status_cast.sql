-- Repair the flight-status enum assignment in complete_acars_session.
do $$
declare definition text;repaired text;
begin
 definition:=pg_get_functiondef('public.complete_acars_session(uuid,text)'::regprocedure);
 repaired:=replace(
  definition,
  'status=case when report.status=''automatically_accepted'' then ''completed'' else ''pirep_pending'' end where',
  'status=(case when report.status=''automatically_accepted'' then ''completed'' else ''pirep_pending'' end)::public.flight_status where'
 );
 if repaired=definition then
  repaired:=replace(
   definition,
   'status = CASE WHEN report.status = ''automatically_accepted'' THEN ''completed'' ELSE ''pirep_pending'' END',
   'status = (CASE WHEN report.status = ''automatically_accepted'' THEN ''completed'' ELSE ''pirep_pending'' END)::public.flight_status'
  );
 end if;
 if repaired=definition then raise exception 'complete_acars_session flight status expression was not found';end if;
 execute repaired;
end$$;
notify pgrst,'reload schema';
