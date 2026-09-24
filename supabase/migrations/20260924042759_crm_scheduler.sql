create extension if not exists pg_cron;
create function crm_private.run_queue() returns jsonb language plpgsql security invoker set search_path='' as $$
declare j public.crm_jobs%rowtype; completed int:=0; failed int:=0;
begin
 if not pg_try_advisory_xact_lock(hashtextextended('vertice-crm-queue-worker',0)) then return '{"busy":true}'::jsonb;end if;
 for j in select * from public.crm_claim(20) loop
  begin
   perform public.crm_process(j.id,j.lease_token);
   completed:=completed+1;
  exception when others then
   perform public.crm_retry(j.id,j.lease_token,'Falha no processamento; SQLSTATE '||sqlstate);
   failed:=failed+1;
  end;
 end loop;
 return jsonb_build_object('completed',completed,'failed',failed);
end $$;
revoke all on function crm_private.run_queue() from public,anon,authenticated,service_role;
select cron.schedule('vertice-crm-process-events','* * * * *','select crm_private.run_queue();');
