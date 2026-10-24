create function public.can_see_post(pid bigint) returns boolean language sql security definer stable set search_path = '' as $$
  select exists (select 1 from public.posts p where p.id = pid and (p.author = auth.uid() or public.are_friends(p.author, auth.uid()))); $$;
create function public.can_see_group_message(mid bigint) returns boolean language sql security definer stable set search_path = '' as $$
  select exists (select 1 from public.group_messages g where g.id = mid and public.is_group_member(g.group_id)); $$;
revoke execute on function public.can_see_post(bigint) from public, anon;
revoke execute on function public.can_see_group_message(bigint) from public, anon;
grant execute on function public.can_see_post(bigint) to authenticated;
grant execute on function public.can_see_group_message(bigint) to authenticated;
create table public.post_reactions (
  post_id bigint not null references public.posts(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  emoji text not null check (char_length(emoji) <= 16),
  created_at timestamptz not null default now(), primary key (post_id, user_id));
alter table public.post_reactions enable row level security;
create policy "voir reactions posts" on public.post_reactions for select to authenticated using (public.can_see_post(post_id));
create policy "reagir post" on public.post_reactions for insert to authenticated with check (user_id = auth.uid() and public.can_see_post(post_id));
create policy "changer reaction post" on public.post_reactions for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid() and public.can_see_post(post_id));
create policy "retirer reaction post" on public.post_reactions for delete to authenticated using (user_id = auth.uid());
create table public.group_message_reactions (
  message_id bigint not null references public.group_messages(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  emoji text not null check (char_length(emoji) <= 16),
  created_at timestamptz not null default now(), primary key (message_id, user_id));
alter table public.group_message_reactions enable row level security;
create policy "voir reactions groupe" on public.group_message_reactions for select to authenticated using (public.can_see_group_message(message_id));
create policy "reagir groupe" on public.group_message_reactions for insert to authenticated with check (user_id = auth.uid() and public.can_see_group_message(message_id));
create policy "changer reaction groupe" on public.group_message_reactions for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid() and public.can_see_group_message(message_id));
create policy "retirer reaction groupe" on public.group_message_reactions for delete to authenticated using (user_id = auth.uid());
alter publication supabase_realtime add table public.post_reactions;
alter publication supabase_realtime add table public.group_message_reactions;
