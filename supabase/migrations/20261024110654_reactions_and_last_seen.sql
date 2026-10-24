alter table public.profiles add column if not exists last_seen timestamptz;
create table public.message_reactions (
  message_id bigint not null references public.messages(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  emoji text not null check (char_length(emoji) <= 16),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);
alter table public.message_reactions enable row level security;
create function public.can_see_message(mid bigint) returns boolean language sql security definer stable set search_path = '' as $$
  select exists (select 1 from public.messages m where m.id = mid and (m.sender = auth.uid() or m.receiver = auth.uid()));
$$;
revoke execute on function public.can_see_message(bigint) from public, anon;
grant execute on function public.can_see_message(bigint) to authenticated;
create policy "voir reactions" on public.message_reactions for select to authenticated using (public.can_see_message(message_id));
create policy "reagir" on public.message_reactions for insert to authenticated with check (user_id = auth.uid() and public.can_see_message(message_id));
create policy "changer reaction" on public.message_reactions for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid() and public.can_see_message(message_id));
create policy "retirer reaction" on public.message_reactions for delete to authenticated using (user_id = auth.uid());
alter publication supabase_realtime add table public.message_reactions;
