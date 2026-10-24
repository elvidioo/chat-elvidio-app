create table public.friendships (
  id bigint generated always as identity primary key,
  requester uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  addressee uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  unique (requester, addressee), check (requester <> addressee)
);
alter table public.friendships enable row level security;
-- NB: are_friends a ensuite été déplacée dans le schéma private (voir private_helpers_schema)
create function public.are_friends(a uuid, b uuid) returns boolean language sql security definer stable set search_path = '' as $$
  select exists (select 1 from public.friendships f where f.status = 'accepted'
    and ((f.requester = a and f.addressee = b) or (f.requester = b and f.addressee = a)));
$$;
revoke execute on function public.are_friends(uuid, uuid) from public, anon;
grant execute on function public.are_friends(uuid, uuid) to authenticated;
create policy "voir mes amities" on public.friendships for select to authenticated using (auth.uid() = requester or auth.uid() = addressee);
create policy "demander en ami" on public.friendships for insert to authenticated with check (auth.uid() = requester and status = 'pending');
create policy "accepter une demande" on public.friendships for update to authenticated using (auth.uid() = addressee) with check (auth.uid() = addressee and status = 'accepted');
create policy "supprimer mon amitie" on public.friendships for delete to authenticated using (auth.uid() = requester or auth.uid() = addressee);
alter publication supabase_realtime add table public.friendships;
