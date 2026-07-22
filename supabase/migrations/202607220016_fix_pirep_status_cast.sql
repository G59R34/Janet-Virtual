-- Repair complete_acars_session installations created by migration 014.
do $$
declare definition text;repaired text;
begin
 definition:=pg_get_functiondef('public.complete_acars_session(uuid,text)'::regprocedure);
 repaired:=replace(
  definition,
  'case when score>=85 then ''automatically_accepted'' else ''manual_review'' end)',
  '(case when score>=85 then ''automatically_accepted'' else ''manual_review'' end)::public.pirep_status)'
 );
 if repaired=definition then raise exception 'complete_acars_session status expression was not found';end if;
 execute repaired;
end$$;
notify pgrst,'reload schema';
