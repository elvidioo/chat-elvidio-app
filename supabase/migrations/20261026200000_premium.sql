-- Soutien / Premium : paiement Mobile Money, validation manuelle par l'administrateur.
create table public.admins (user_id uuid primary key references auth.users(id) on delete cascade);
alter table public.admins enable row level security;
create policy "voir admins" on public.admins for select to authenticated using (user_id = (select auth.uid()));

create function private.is_admin() returns boolean language sql security definer stable set search_path = '' as $$
  select exists (select 1 from public.admins where user_id = (select auth.uid())); $$;
revoke execute on function private.is_admin() from public, anon;
grant execute on function private.is_admin() to authenticated;

create table public.app_config (key text primary key, value text not null default '');
alter table public.app_config enable row level security;
create policy "lire config" on public.app_config for select to authenticated using (true);
create policy "ecrire config" on public.app_config for insert to authenticated with check (private.is_admin());
create policy "modifier config" on public.app_config for update to authenticated using (private.is_admin()) with check (private.is_admin());

create table public.premium (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  until timestamptz not null);
alter table public.premium enable row level security;
create policy "voir premium" on public.premium for select to authenticated using (true);

create table public.premium_requests (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  reference text not null check (char_length(btrim(reference)) between 3 and 80),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now());
create index premium_requests_user_idx on public.premium_requests (user_id, created_at desc);
alter table public.premium_requests enable row level security;
create policy "mes demandes" on public.premium_requests for select to authenticated
  using (user_id = (select auth.uid()) or private.is_admin());
create policy "demander premium" on public.premium_requests for insert to authenticated
  with check (user_id = (select auth.uid()) and status = 'pending');
create trigger premium_requests_rate_limit before insert on public.premium_requests
  for each row execute function private.rate_limit('user_id', '5', '1 hour');

create function public.approve_premium(rid bigint, days integer default 30) returns void
language plpgsql security definer set search_path = '' as $$
declare u uuid;
begin
  if not private.is_admin() then raise exception 'interdit'; end if;
  update public.premium_requests set status = 'approved' where id = rid and status = 'pending' returning user_id into u;
  if u is null then raise exception 'demande introuvable'; end if;
  insert into public.premium (user_id, until) values (u, now() + make_interval(days => days))
    on conflict (user_id) do update set until = greatest(public.premium.until, now()) + make_interval(days => days);
end $$;
create function public.reject_premium(rid bigint) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_admin() then raise exception 'interdit'; end if;
  update public.premium_requests set status = 'rejected' where id = rid and status = 'pending';
end $$;
revoke execute on function public.approve_premium(bigint, integer) from public, anon;
revoke execute on function public.reject_premium(bigint) from public, anon;
grant execute on function public.approve_premium(bigint, integer) to authenticated;
grant execute on function public.reject_premium(bigint) to authenticated;
alter publication supabase_realtime add table public.premium;

insert into public.admins (user_id) values ('6d96ab8a-2827-4267-95a2-8af35c99ea59');
insert into public.app_config (key, value) values ('payment_info', ''), ('premium_price', '1000 FCFA / mois');
