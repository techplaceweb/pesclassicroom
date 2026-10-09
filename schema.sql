-- Run once in Supabase SQL Editor. Run on a NEW project.
create extension if not exists pgcrypto;
create table public.profiles (id uuid primary key references auth.users(id) on delete cascade, username text not null unique, role text not null default 'user' check(role in ('admin','user')), archived boolean not null default false, created_at timestamptz not null default now());
create table public.rooms (id uuid primary key default gen_random_uuid(), name text not null check(length(trim(name)) between 1 and 100), closed boolean not null default false, archived boolean not null default false, created_at timestamptz not null default now());
create table public.room_access (room_id uuid references public.rooms(id) on delete cascade, user_id uuid references public.profiles(id) on delete cascade, primary key(room_id,user_id));
create table public.messages (id uuid primary key default gen_random_uuid(), room_id uuid not null references public.rooms(id) on delete cascade, author_id uuid not null references public.profiles(id), body text not null default '' check(length(body)<=5000), image_path text, hidden boolean not null default false, created_at timestamptz not null default now(), check(length(trim(body))>0 or image_path is not null));
create table public.private_messages (id uuid primary key default gen_random_uuid(), sender_id uuid not null references public.profiles(id), receiver_id uuid not null references public.profiles(id), body text not null check(length(trim(body)) between 1 and 5000), read_at timestamptz, created_at timestamptz not null default now());
create table public.settings (id boolean primary key default true check(id), maintenance boolean not null default false);
insert into public.settings(id) values(true);
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.profiles where id=(select auth.uid()) and role='admin' and not archived) $$;
create or replace function public.active_user() returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.profiles where id=(select auth.uid()) and not archived) $$;
create or replace function public.can_room(r uuid) returns boolean language sql stable security definer set search_path='' as $$ select public.is_admin() or (public.active_user() and exists(select 1 from public.rooms x where x.id=r and not x.closed) and exists(select 1 from public.room_access a where a.room_id=r and a.user_id=(select auth.uid()))) $$;
create or replace function public.handle_signup() returns trigger language plpgsql security definer set search_path='' as $$ begin insert into public.profiles(id,username) values(new.id,coalesce(nullif(new.raw_user_meta_data->>'username',''),split_part(new.email,'@',1))); return new; end $$;
create trigger auth_profile after insert on auth.users for each row execute function public.handle_signup();
alter table public.profiles enable row level security;alter table public.rooms enable row level security;alter table public.room_access enable row level security;alter table public.messages enable row level security;alter table public.private_messages enable row level security;alter table public.settings enable row level security;
create policy profiles_read on public.profiles for select to authenticated using(public.active_user());
create policy profiles_admin_update on public.profiles for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy rooms_read on public.rooms for select to authenticated using(public.can_room(id));
create policy rooms_admin_all on public.rooms for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy access_read on public.room_access for select to authenticated using(public.is_admin() or (public.active_user() and user_id=(select auth.uid())));
create policy access_admin_all on public.room_access for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy messages_read on public.messages for select to authenticated using(public.can_room(room_id) and (public.is_admin() or (not hidden and not (select archived from public.rooms where id=room_id))));
create policy messages_insert on public.messages for insert to authenticated with check(public.can_room(room_id) and author_id=(select auth.uid()) and not hidden);
create policy messages_admin_update on public.messages for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy messages_admin_delete on public.messages for delete to authenticated using(public.is_admin());
create policy private_read on public.private_messages for select to authenticated using(public.active_user() and (sender_id=(select auth.uid()) or receiver_id=(select auth.uid())));
create policy private_insert on public.private_messages for insert to authenticated with check(public.active_user() and sender_id=(select auth.uid()) and (public.is_admin() or exists(select 1 from public.profiles where id=receiver_id and role='admin' and not archived)) and (public.is_admin() or receiver_id<>(select auth.uid())));
create policy private_mark_read on public.private_messages for update to authenticated using(public.active_user() and receiver_id=(select auth.uid())) with check(receiver_id=(select auth.uid()));
create policy settings_read on public.settings for select to authenticated using(public.active_user());
create policy settings_admin on public.settings for update to authenticated using(public.is_admin()) with check(public.is_admin());
-- Images: only authenticated participants may read. Uploaded files use room-id/user-id/random-name path.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('room-images','room-images',false,5242880,array['image/jpeg','image/png','image/webp','image/gif']) on conflict(id) do nothing;
create policy image_insert on storage.objects for insert to authenticated with check(bucket_id='room-images' and public.active_user() and public.can_room((split_part(name,'/',1))::uuid) and split_part(name,'/',2)=(select auth.uid())::text);
create policy image_read on storage.objects for select to authenticated using(bucket_id='room-images' and public.can_room((split_part(name,'/',1))::uuid));
-- Realtime changes, with RLS filtering.
alter publication supabase_realtime add table public.rooms,public.room_access,public.messages,public.private_messages,public.profiles,public.settings;
-- IMPORTANT: After creating the first Auth user in Dashboard with email admin@pcr.invalid,
-- run this command with the UUID shown in Authentication > Users:
-- update public.profiles set role='admin' where id='PASTE-ADMIN-UUID-HERE';
