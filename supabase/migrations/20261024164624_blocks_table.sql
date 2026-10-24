create table public.blocks (
  blocker uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  blocked uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked), check (blocker <> blocked)
);
alter table public.blocks enable row level security;
create policy "voir mes blocages" on public.blocks for select to authenticated using (blocker = auth.uid());
create policy "bloquer" on public.blocks for insert to authenticated with check (blocker = auth.uid());
create policy "debloquer" on public.blocks for delete to authenticated using (blocker = auth.uid());
create function public.is_blocked(a uuid, b uuid) returns boolean language sql security definer stable set search_path = '' as $$
  select exists (select 1 from public.blocks where (blocker = a and blocked = b) or (blocker = b and blocked = a));
$$;
revoke execute on function public.is_blocked(uuid, uuid) from public, anon;
grant execute on function public.is_blocked(uuid, uuid) to authenticated;
