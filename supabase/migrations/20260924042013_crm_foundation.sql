-- Additive CRM namespace. Existing motor/e-commerce data is untouched.
create schema if not exists crm_private;
revoke all on schema crm_private from public, anon;
grant usage on schema crm_private to authenticated, service_role;
create table public.crm_companies (
 id uuid primary key default gen_random_uuid(), name text not null check(length(name) between 1 and 120), niche text not null default 'Serviços',
 settings jsonb not null default '{"stages":["Novo lead","Em contato","Qualificado","Proposta","Ganho","Perdido"],"criteria":["Necessidade identificada","Orçamento disponível","Poder de decisão","Prazo definido"],"followup":true,"qualify":true,"threshold":75}', created_at timestamptz not null default now());
create table public.crm_members (
 user_id uuid primary key references auth.users(id) on delete cascade, company_id uuid not null references public.crm_companies(id), name text not null, email text not null, role text not null check(role in ('admin','member')));
create index crm_members_company_idx on public.crm_members(company_id);
create table public.crm_records (
 id uuid primary key default gen_random_uuid(),company_id uuid not null references public.crm_companies(id),kind text not null check(kind in ('leads','campaigns','tasks','activity')),data jsonb not null check(jsonb_typeof(data)='object' and octet_length(data::text)<=30000),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create index crm_records_company_kind_idx on public.crm_records(company_id,kind,created_at desc);
create table public.crm_channels(id uuid primary key default gen_random_uuid(),company_id uuid not null references public.crm_companies(id),provider text not null check(provider in ('instagram','whatsapp')),external_id text not null, label text not null,enabled boolean not null default false,unique(provider,external_id));
create index crm_channels_company_idx on public.crm_channels(company_id);
create table public.crm_jobs(id uuid primary key default gen_random_uuid(),company_id uuid not null references public.crm_companies(id),dedup_key text not null,payload jsonb not null check(octet_length(payload::text)<=30000),status text not null default 'pending' check(status in ('pending','running','done','failed')),attempts integer not null default 0,next_run timestamptz not null default now(),lease_until timestamptz,lease_token uuid,last_error text,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(company_id,dedup_key));
create index crm_jobs_ready_idx on public.crm_jobs(next_run,created_at) where status in ('pending','running');
create index crm_jobs_company_idx on public.crm_jobs(company_id,created_at desc);
create table crm_private.capture_tokens(company_id uuid primary key references public.crm_companies(id),token_hash text not null unique);
create table crm_private.invites(token_hash text primary key,company_id uuid not null references public.crm_companies(id),email text not null,name text not null,expires_at timestamptz not null default now()+interval '7 days');
create table crm_private.contact_links(company_id uuid not null references public.crm_companies(id),contact_key text not null,lead_id uuid not null references public.crm_records(id),primary key(company_id,contact_key));
create index crm_contact_links_lead_idx on crm_private.contact_links(lead_id);
create function crm_private.company() returns uuid language sql stable security definer set search_path='' as $$ select company_id from public.crm_members where user_id=(select auth.uid()) $$;
create function crm_private.is_admin() returns boolean language sql stable security definer set search_path='' as $$ select coalesce((select role='admin' from public.crm_members where user_id=(select auth.uid())),false) $$;
alter table public.crm_companies enable row level security;
alter table public.crm_members enable row level security;
alter table public.crm_records enable row level security;
alter table public.crm_channels enable row level security;
alter table public.crm_jobs enable row level security;
create policy company_read on public.crm_companies for select to authenticated using(id=(select crm_private.company()));
create policy member_read on public.crm_members for select to authenticated using(company_id=(select crm_private.company()));
create policy records_read on public.crm_records for select to authenticated using(company_id=(select crm_private.company()));
create policy channels_read on public.crm_channels for select to authenticated using(company_id=(select crm_private.company()));
create policy jobs_read on public.crm_jobs for select to authenticated using(company_id=(select crm_private.company()));
revoke all on public.crm_companies,public.crm_members,public.crm_records,public.crm_channels,public.crm_jobs from anon,authenticated;
grant select on public.crm_companies,public.crm_members,public.crm_records,public.crm_channels,public.crm_jobs to authenticated;
grant all on public.crm_companies,public.crm_members,public.crm_records,public.crm_channels,public.crm_jobs to service_role;
-- Only the caller's verified Auth identity can bootstrap a company.
create function crm_private.bootstrap(p_name text,p_company text,p_niche text,p_invite text default null) returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); tid uuid; em text; inv crm_private.invites%rowtype;
begin
 if uid is null then raise exception 'Faça login'; end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,0));
 select company_id into tid from public.crm_members where user_id=uid;
 if tid is not null then return tid; end if;
 select email into em from auth.users where id=uid and email_confirmed_at is not null;
 if em is null then raise exception 'Confirme seu e-mail'; end if;
 if p_invite is not null and p_invite<>'' then
  select * into inv from crm_private.invites where token_hash=encode(extensions.digest(p_invite,'sha256'),'hex') and lower(email)=lower(em) and expires_at>now() for update;
  if not found then raise exception 'Convite inválido ou expirado'; end if;
  tid:=inv.company_id;
  insert into public.crm_members values(uid,tid,left(inv.name,120),em,'member');
  delete from crm_private.invites where token_hash=inv.token_hash;
 else
  if length(trim(p_name))<1 or length(trim(p_company))<1 then raise exception 'Informe nome e empresa'; end if;
  insert into public.crm_companies(name,niche) values(left(trim(p_company),120),left(coalesce(p_niche,'Serviços'),120)) returning id into tid;
  insert into public.crm_members values(uid,tid,left(trim(p_name),120),em,'admin');
 end if;
 return tid;
end $$;
create function public.crm_bootstrap(p_name text,p_company text,p_niche text,p_invite text default null) returns uuid language sql security invoker set search_path='' as $$ select crm_private.bootstrap(p_name,p_company,p_niche,p_invite) $$;
create function crm_private.save(p_kind text,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare tid uuid:=crm_private.company(); rid uuid; d jsonb:=p_data; s jsonb; old jsonb; sc int; new_record boolean; stage text;
begin
 if tid is null then raise exception 'Faça login'; end if;
 if p_kind not in ('leads','campaigns','tasks') or jsonb_typeof(d)<>'object' or octet_length(d::text)>20000 then raise exception 'Dados inválidos'; end if;
 select settings into s from public.crm_companies where id=tid for share;
 new_record:=coalesce(d->>'id','')='';
 if new_record then rid:=gen_random_uuid(); else
  rid:=(d->>'id')::uuid;
  select data into old from public.crm_records where id=rid and company_id=tid and kind=p_kind for update;
  if not found then raise exception 'Registro não encontrado'; end if;
 end if;
 if p_kind='leads' then
  if length(trim(coalesce(d->>'name','')))=0 or coalesce((d->>'value')::numeric,0)<0 then raise exception 'Nome ou valor inválido'; end if;
  if coalesce(d->>'campaignId','')<>'' and not exists(select 1 from public.crm_records where id=(d->>'campaignId')::uuid and company_id=tid and kind='campaigns') then raise exception 'Campanha inválida'; end if;
  d:=jsonb_set(d,'{checks}',(select jsonb_agg(coalesce(d->'checks'->i='true'::jsonb,false)) from generate_series(0,3) i));
  select count(*)*25 into sc from jsonb_array_elements(d->'checks') x where x='true'::jsonb;
  stage:=case when new_record then s->'stages'->>0 else d->>'stage' end;
  if not s->'stages' ? stage then raise exception 'Etapa inválida'; end if;
  if coalesce((s->>'qualify')::boolean,false) and sc>=(s->>'threshold')::int and s->'stages' ? 'Qualificado' and stage not in ('Ganho','Perdido') and (select ordinality from jsonb_array_elements_text(s->'stages') with ordinality where value=stage)<(select ordinality from jsonb_array_elements_text(s->'stages') with ordinality where value='Qualificado') then stage:='Qualificado'; end if;
  d:=d||jsonb_build_object('score',sc,'stage',stage);
 elsif p_kind='campaigns' then
  if length(trim(coalesce(d->>'name','')))=0 or coalesce((d->>'spend')::numeric,-1)<0 then raise exception 'Campanha inválida'; end if;
 else
  if length(trim(coalesce(d->>'title','')))=0 or coalesce(d->>'due','')!~'^\d{4}-\d{2}-\d{2}$' then raise exception 'Tarefa inválida'; end if;
 end if;
 d:=d||jsonb_build_object('id',rid,'created',coalesce(old->'created',to_jsonb(now())),'updated',now());
 insert into public.crm_records(id,company_id,kind,data) values(rid,tid,p_kind,d) on conflict(id) do update set data=excluded.data,updated_at=now();
 if new_record and p_kind='leads' then
  if coalesce((s->>'followup')::boolean,false) then
   insert into public.crm_records(company_id,kind,data) values(tid,'tasks',jsonb_build_object('title','Primeiro contato · '||(d->>'name'),'leadId',rid,'due',(current_date+1)::text,'done',false,'owner',coalesce(d->>'owner','Equipe'),'created',now()));
  end if;
  insert into public.crm_records(company_id,kind,data) values(tid,'activity',jsonb_build_object('text','Novo lead: '||(d->>'name'),'created',now()));
 end if;
 return rid;
end $$;
create function public.crm_save(p_kind text,p_data jsonb) returns uuid language sql security invoker set search_path='' as $$ select crm_private.save(p_kind,p_data) $$;
create function crm_private.settings(p_name text,p_niche text,p_settings jsonb) returns void language plpgsql security definer set search_path='' as $$
declare tid uuid:=crm_private.company(); s jsonb:=p_settings;
begin
 if not crm_private.is_admin() then raise exception 'Apenas administradores'; end if;
 perform 1 from public.crm_companies where id=tid for update;
 if jsonb_typeof(s->'stages') is distinct from 'array' or jsonb_array_length(s->'stages') not between 3 and 8 or not(s->'stages' ?& array['Ganho','Perdido']) or jsonb_typeof(s->'criteria') is distinct from 'array' or jsonb_array_length(s->'criteria')<>4 or coalesce((s->>'threshold')::int,0) not between 25 and 100 or jsonb_typeof(s->'followup') is distinct from 'boolean' or jsonb_typeof(s->'qualify') is distinct from 'boolean' then raise exception 'Configurações inválidas'; end if;
 if (select count(distinct value) from jsonb_array_elements_text(s->'stages'))<>jsonb_array_length(s->'stages') or exists(select 1 from jsonb_array_elements_text(s->'stages') where length(trim(value)) not between 1 and 35) or exists(select 1 from jsonb_array_elements_text(s->'criteria') where length(trim(value)) not between 1 and 100) then raise exception 'Etapas ou critérios inválidos'; end if;
 if exists(select 1 from public.crm_records where company_id=tid and kind='leads' and not(s->'stages' ? (data->>'stage'))) then raise exception 'Mova os leads antes de remover a etapa'; end if;
 update public.crm_companies set name=left(coalesce(nullif(trim(p_name),''),name),120),niche=left(coalesce(p_niche,niche),120),settings=s where id=tid;
end $$;
create function public.crm_settings(p_name text,p_niche text,p_settings jsonb) returns void language sql security invoker set search_path='' as $$ select crm_private.settings(p_name,p_niche,p_settings) $$;
create function crm_private.token(p_email text default null,p_name text default null) returns text language plpgsql security definer set search_path='' as $$
declare token text:=encode(extensions.gen_random_bytes(32),'hex'); tid uuid:=crm_private.company();
begin
 if not crm_private.is_admin() then raise exception 'Apenas administradores'; end if;
 if p_email is null then insert into crm_private.capture_tokens values(tid,encode(extensions.digest(token,'sha256'),'hex')) on conflict(company_id) do update set token_hash=excluded.token_hash;
 else
  if p_email!~'^[^\s@]+@[^\s@]+\.[^\s@]+$' or length(trim(coalesce(p_name,'')))=0 then raise exception 'Nome ou e-mail inválido'; end if;
  insert into crm_private.invites(token_hash,company_id,email,name) values(encode(extensions.digest(token,'sha256'),'hex'),tid,lower(p_email),left(p_name,120));
 end if; return token;
end $$;
create function public.crm_token(p_email text default null,p_name text default null) returns text language sql security invoker set search_path='' as $$ select crm_private.token(p_email,p_name) $$;
-- Queue producer and worker are server-only. No browser role can claim or insert jobs.
create function public.crm_capture(p_token text,p_key text,p_payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare tid uuid; jid uuid;
begin
 select company_id into tid from crm_private.capture_tokens where token_hash=encode(extensions.digest(p_token,'sha256'),'hex');
 if tid is null then raise exception 'Token inválido'; end if;
 if length(p_key) not between 1 and 200 then raise exception 'Idempotency-Key obrigatório'; end if;
 insert into public.crm_jobs(company_id,dedup_key,payload) values(tid,'capture:'||p_key,p_payload) on conflict(company_id,dedup_key) do update set dedup_key=excluded.dedup_key returning id into jid;
 return jid;
end $$;
create function public.crm_claim(p_limit int default 10) returns setof public.crm_jobs language sql security invoker set search_path='' as $$
 update public.crm_jobs set status='running',attempts=attempts+1,lease_until=now()+interval '2 minutes',lease_token=gen_random_uuid(),updated_at=now()
 where id in(select id from public.crm_jobs where attempts<8 and ((status='pending' and next_run<=now()) or (status='running' and lease_until<now())) order by next_run,created_at for update skip locked limit greatest(1,least(p_limit,20))) returning *;
$$;
create function public.crm_process(p_id uuid,p_lease uuid) returns void language plpgsql security definer set search_path='' as $$
declare j public.crm_jobs%rowtype; rid uuid; contact text; s jsonb; d jsonb; nm text;
begin
 select * into j from public.crm_jobs where id=p_id and status='running' and lease_token=p_lease and lease_until>now() for update;
 if not found then raise exception 'Lease inválido'; end if;
 d:=j.payload; contact:=coalesce(nullif(d->>'contactKey',''),'event:'||j.dedup_key);
 perform pg_advisory_xact_lock(hashtextextended(j.company_id::text||contact,0));
 select lead_id into rid from crm_private.contact_links where company_id=j.company_id and contact_key=contact;
 nm:=left(coalesce(nullif(d->>'name',''),'Contato '||coalesce(d->>'source','integrado')),120);
 if rid is null then
  select settings into s from public.crm_companies where id=j.company_id;
  rid:=gen_random_uuid();
  insert into public.crm_records(id,company_id,kind,data) values(rid,j.company_id,'leads',jsonb_build_object('id',rid,'name',nm,'source',coalesce(d->>'source','Site'),'phone',coalesce(d->>'phone',''),'email',coalesce(d->>'email',''),'business',coalesce(d->>'business',''),'notes',left(coalesce(d->>'message',''),6000),'utm_campaign',coalesce(d->>'utm_campaign',''),'stage',s->'stages'->>0,'owner','Equipe','value',0,'score',0,'checks','[false,false,false,false]'::jsonb,'created',now()));
  insert into crm_private.contact_links values(j.company_id,contact,rid);
  if coalesce((s->>'followup')::boolean,false) then insert into public.crm_records(company_id,kind,data) values(j.company_id,'tasks',jsonb_build_object('title','Primeiro contato · '||nm,'leadId',rid,'due',(current_date+1)::text,'done',false,'owner','Equipe','created',now())); end if;
 else
  update public.crm_records set data=data||jsonb_build_object('lastMessage',left(coalesce(d->>'message',''),6000),'updated',now()),updated_at=now() where id=rid and company_id=j.company_id;
 end if;
 insert into public.crm_records(company_id,kind,data) values(j.company_id,'activity',jsonb_build_object('text','Entrada via '||coalesce(d->>'source','Site')||': '||nm,'leadId',rid,'created',now()));
 update public.crm_jobs set status='done',lease_until=null,last_error=null,updated_at=now() where id=p_id;
end $$;
create function public.crm_retry(p_id uuid,p_lease uuid,p_error text) returns void language sql security invoker set search_path='' as $$
 update public.crm_jobs set status=case when attempts>=8 then 'failed' else 'pending' end,next_run=now()+make_interval(secs=>least(3600,power(2,attempts)::int*15)+floor(random()*15)::int),lease_until=null,last_error=left(p_error,200),updated_at=now() where id=p_id and status='running' and lease_token=p_lease;
$$;
-- Explicit grants prevent Supabase's default PUBLIC function EXECUTE from exposing definer helpers.
revoke all on all functions in schema crm_private from public,anon,authenticated;
grant execute on function crm_private.company(),crm_private.is_admin(),crm_private.bootstrap(text,text,text,text),crm_private.save(text,jsonb),crm_private.settings(text,text,jsonb),crm_private.token(text,text) to authenticated;
revoke all on function public.crm_bootstrap(text,text,text,text),public.crm_save(text,jsonb),public.crm_settings(text,text,jsonb),public.crm_token(text,text),public.crm_capture(text,text,jsonb),public.crm_claim(int),public.crm_process(uuid,uuid),public.crm_retry(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.crm_bootstrap(text,text,text,text),public.crm_save(text,jsonb),public.crm_settings(text,text,jsonb),public.crm_token(text,text) to authenticated;
grant execute on function public.crm_capture(text,text,jsonb),public.crm_claim(int),public.crm_process(uuid,uuid),public.crm_retry(uuid,uuid,text) to service_role;
