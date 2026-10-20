-- PES Classic Room: installare in Supabase SQL Editor prima dell'HTML.
create table if not exists public.pcr_competitions (
 id uuid primary key default gen_random_uuid(), name text not null check(length(trim(name)) between 1 and 150),
 kind text not null check(kind in ('league','tournament')),
 format text not null check(format in ('single','return','knockout_single','knockout_return','groups')),
 teams text not null check(teams in ('clubs','national','both')),
 duration integer not null check(duration in (5,10,15,20,25,30)),
 condition text not null check(condition in ('random','red')),
 archived boolean not null default false,
 last_notice text not null default '',
 created_at timestamptz not null default now()
);
create table if not exists public.pcr_competition_members (
 competition_id uuid not null references public.pcr_competitions(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 wins integer not null default 0 check(wins>=0), losses integer not null default 0 check(losses>=0),
 draws integer not null default 0 check(draws>=0), points integer not null default 0 check(points>=0),
 score_updated_at timestamptz,
 primary key(competition_id,user_id)
);
create table if not exists public.pcr_competition_matches (
 id uuid primary key default gen_random_uuid(),
 competition_id uuid not null references public.pcr_competitions(id) on delete cascade,
 round_no integer not null check(round_no>=1),match_no integer not null check(match_no>=1),
 home_id uuid not null references public.profiles(id),away_id uuid not null references public.profiles(id),
 home_score integer not null default 0 check(home_score>=0),away_score integer not null default 0 check(away_score>=0),
 played boolean not null default false,winner_id uuid references public.profiles(id),
 unique(competition_id,round_no,match_no),check(home_id<>away_id)
);
create table if not exists public.pcr_competition_notifications (
 id uuid primary key default gen_random_uuid(),
 competition_id uuid not null references public.pcr_competitions(id) on delete cascade,
 recipient_id uuid not null references public.profiles(id) on delete cascade,
 body text not null check(length(trim(body)) between 1 and 5000),
 created_at timestamptz not null default now(),read_at timestamptz
);
create index if not exists pcr_comp_notices_recipient on public.pcr_competition_notifications(recipient_id,created_at desc);
create index if not exists pcr_comp_matches_comp on public.pcr_competition_matches(competition_id,round_no);
create or replace function public.pcr_comp_is_admin() returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.profiles where id=auth.uid() and role='admin' and not coalesce(archived,false));
$$;
revoke all on function public.pcr_comp_is_admin() from public;
grant execute on function public.pcr_comp_is_admin() to authenticated;
alter table public.pcr_competitions enable row level security;
alter table public.pcr_competition_members enable row level security;
alter table public.pcr_competition_matches enable row level security;
alter table public.pcr_competition_notifications enable row level security;
drop policy if exists pcr_comp_select on public.pcr_competitions;
create policy pcr_comp_select on public.pcr_competitions for select to authenticated using (not archived or public.pcr_comp_is_admin());
drop policy if exists pcr_comp_admin_all on public.pcr_competitions;
create policy pcr_comp_admin_all on public.pcr_competitions for all to authenticated using (public.pcr_comp_is_admin()) with check(public.pcr_comp_is_admin());
drop policy if exists pcr_comp_members_select on public.pcr_competition_members;
create policy pcr_comp_members_select on public.pcr_competition_members for select to authenticated using (exists(select 1 from public.pcr_competitions c where c.id=competition_id and (not c.archived or public.pcr_comp_is_admin())));
drop policy if exists pcr_comp_members_admin on public.pcr_competition_members;
create policy pcr_comp_members_admin on public.pcr_competition_members for all to authenticated using (public.pcr_comp_is_admin()) with check(public.pcr_comp_is_admin());
drop policy if exists pcr_comp_matches_select on public.pcr_competition_matches;
create policy pcr_comp_matches_select on public.pcr_competition_matches for select to authenticated using (exists(select 1 from public.pcr_competitions c where c.id=competition_id and (not c.archived or public.pcr_comp_is_admin())));
drop policy if exists pcr_comp_matches_admin on public.pcr_competition_matches;
create policy pcr_comp_matches_admin on public.pcr_competition_matches for all to authenticated using (public.pcr_comp_is_admin()) with check(public.pcr_comp_is_admin());
drop policy if exists pcr_comp_notices_select on public.pcr_competition_notifications;
create policy pcr_comp_notices_select on public.pcr_competition_notifications for select to authenticated using (recipient_id=auth.uid());
drop policy if exists pcr_comp_notices_update on public.pcr_competition_notifications;
create policy pcr_comp_notices_update on public.pcr_competition_notifications for update to authenticated using (recipient_id=auth.uid()) with check(recipient_id=auth.uid());
create or replace function public.pcr_send_competition_notice(p_competition_id uuid,p_body text)
returns integer language plpgsql security definer set search_path=public as $$
declare n integer;
begin
 if not public.pcr_comp_is_admin() then raise exception 'Operazione riservata all ADMIN'; end if;
 if length(trim(coalesce(p_body,''))) not between 1 and 5000 then raise exception 'Messaggio non valido'; end if;
 if not exists(select 1 from public.pcr_competitions where id=p_competition_id) then raise exception 'Competizione non trovata'; end if;
 update public.pcr_competitions set last_notice=trim(p_body) where id=p_competition_id;
 insert into public.pcr_competition_notifications(competition_id,recipient_id,body)
 select p_competition_id,m.user_id,trim(p_body) from public.pcr_competition_members m where m.competition_id=p_competition_id;
 get diagnostics n=row_count;
 return n;
end;$$;
revoke all on function public.pcr_send_competition_notice(uuid,text) from public;
grant execute on function public.pcr_send_competition_notice(uuid,text) to authenticated;
grant select,insert,update,delete on public.pcr_competitions,public.pcr_competition_members,public.pcr_competition_matches to authenticated;
grant select on public.pcr_competition_notifications to authenticated;
grant update(read_at) on public.pcr_competition_notifications to authenticated;
