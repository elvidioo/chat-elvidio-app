create table public.reports (
  id bigint generated always as identity primary key,
  reporter uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('user','message','group_message','post')),
  target_user uuid references public.profiles(id) on delete set null,
  target_id bigint,
  reason text not null check (char_length(reason) between 1 and 500),
  created_at timestamptz not null default now()
);
alter table public.reports enable row level security;
create policy "signaler" on public.reports for insert to authenticated with check (reporter = auth.uid());
create policy "voir mes signalements" on public.reports for select to authenticated using (reporter = auth.uid());
