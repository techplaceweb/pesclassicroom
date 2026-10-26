-- PES Classic Room: comunicazioni ufficiali. Non modifica auth.users, profiles o credenziali.
create table if not exists public.pcr_official_notices (
  id uuid primary key default gen_random_uuid(),
  body text not null check (char_length(trim(body)) between 1 and 5000),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
create table if not exists public.pcr_official_notice_recipients (
  notice_id uuid not null references public.pcr_official_notices(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  primary key(notice_id,user_id)
);
create index if not exists pcr_official_recipient_unread_idx on public.pcr_official_notice_recipients(user_id,created_at) where read_at is null;

alter table public.pcr_official_notices enable row level security;
alter table public.pcr_official_notice_recipients enable row level security;

-- L'utente vede soltanto le comunicazioni destinate a lui.
drop policy if exists pcr_official_notices_read on public.pcr_official_notices;
create policy pcr_official_notices_read on public.pcr_official_notices for select to authenticated
using (exists(select 1 from public.pcr_official_notice_recipients r where r.notice_id=id and r.user_id=(select auth.uid())));
drop policy if exists pcr_official_recipients_read on public.pcr_official_notice_recipients;
create policy pcr_official_recipients_read on public.pcr_official_notice_recipients for select to authenticated
using (user_id=(select auth.uid()));

grant select on public.pcr_official_notices, public.pcr_official_notice_recipients to authenticated;

-- Solo l'ADMIN può inviare. SECURITY DEFINER consente l'inserimento
-- senza dare agli utenti permessi di scrittura sulle tabelle.
create or replace function public.pcr_send_official_notice(p_body text)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_count integer;
begin
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin' and coalesce(p.archived,false)=false) then
    raise exception 'Operazione riservata ad ADMIN';
  end if;
  if p_body is null or char_length(trim(p_body)) not between 1 and 5000 then
    raise exception 'Il messaggio deve contenere da 1 a 5000 caratteri';
  end if;
  insert into public.pcr_official_notices(body,created_by) values(trim(p_body),auth.uid()) returning id into v_id;
  insert into public.pcr_official_notice_recipients(notice_id,user_id)
  select v_id,p.id from public.profiles p
  where p.role='user' and coalesce(p.archived,false)=false;
  get diagnostics v_count=row_count;
  return v_count;
end $$;

create or replace function public.pcr_ack_official_notice(p_notice_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Accesso richiesto'; end if;
  update public.pcr_official_notice_recipients
  set read_at=coalesce(read_at,now())
  where notice_id=p_notice_id and user_id=auth.uid();
end $$;

revoke all on function public.pcr_send_official_notice(text) from public;
revoke all on function public.pcr_ack_official_notice(uuid) from public;
grant execute on function public.pcr_send_official_notice(text) to authenticated;
grant execute on function public.pcr_ack_official_notice(uuid) to authenticated;
