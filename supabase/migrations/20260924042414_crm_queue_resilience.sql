create table crm_private.capture_windows(company_id uuid primary key references public.crm_companies(id),window_start timestamptz not null default now(),count int not null default 0);
revoke all on all tables in schema crm_private from public,anon,authenticated;
create or replace function public.crm_capture(p_token text,p_key text,p_payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare tid uuid; jid uuid; n int;
begin
 select company_id into tid from crm_private.capture_tokens where token_hash=encode(extensions.digest(p_token,'sha256'),'hex');
 if tid is null then raise exception 'Token inválido'; end if;
 if length(p_key) not between 1 and 200 then raise exception 'Idempotency-Key obrigatório'; end if;
 select id into jid from public.crm_jobs where company_id=tid and dedup_key='capture:'||p_key;
 if jid is not null then return jid; end if;
 insert into crm_private.capture_windows(company_id,count) values(tid,1) on conflict(company_id) do update set count=case when capture_windows.window_start<now()-interval '1 minute' then 1 else capture_windows.count+1 end,window_start=case when capture_windows.window_start<now()-interval '1 minute' then now() else capture_windows.window_start end returning count into n;
 if n>120 then raise exception 'Muitas entradas. Tente novamente em 60 segundos.' using errcode='P0429';end if;
 insert into public.crm_jobs(company_id,dedup_key,payload) values(tid,'capture:'||p_key,p_payload) on conflict(company_id,dedup_key) do update set dedup_key=excluded.dedup_key returning id into jid;
 return jid;
end $$;
create or replace function public.crm_claim(p_limit int default 10) returns setof public.crm_jobs language plpgsql security invoker set search_path='' as $$
begin
 update public.crm_jobs set status='failed',last_error='Limite de tentativas atingido após expiração da execução',updated_at=now() where status='running' and lease_until<now() and attempts>=8;
 return query update public.crm_jobs set status='running',attempts=attempts+1,lease_until=now()+interval '2 minutes',lease_token=gen_random_uuid(),updated_at=now()
 where id in(select id from public.crm_jobs where attempts<8 and ((status='pending' and next_run<=now()) or (status='running' and lease_until<now())) order by next_run,created_at for update skip locked limit greatest(1,least(p_limit,20))) returning *;
end $$;
revoke all on function public.crm_capture(text,text,jsonb),public.crm_claim(int) from public,anon,authenticated;
grant execute on function public.crm_capture(text,text,jsonb),public.crm_claim(int) to service_role;
