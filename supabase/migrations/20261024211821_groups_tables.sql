create table public.groups (
  id bigint generated always as identity primary key,
  name text not null check (char_length(name) between 1 and 60),
  avatar_url text,
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table public.group_members (
  group_id bigint not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('admin','member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create table public.group_messages (
  id bigint generated always as identity primary key,
  group_id bigint not null references public.groups(id) on delete cascade,
  sender uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  content text, media_url text, media_name text,
  created_at timestamptz not null default now()
);
create index group_messages_idx on public.group_messages (group_id, created_at desc);
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.group_messages enable row level security;
create function public.is_group_member(gid bigint) returns boolean language sql security definer stable set search_path = '' as $$
  select exists (select 1 from public.group_members where group_id = gid and user_id = auth.uid()); $$;
create function public.is_group_admin(gid bigint) returns boolean language sql security definer stable set search_path = '' as $$
  select exists (select 1 from public.group_members where group_id = gid and user_id = auth.uid() and role = 'admin'); $$;
revoke execute on function public.is_group_member(bigint) from public, anon;
revoke execute on function public.is_group_admin(bigint) from public, anon;
grant execute on function public.is_group_member(bigint) to authenticated;
grant execute on function public.is_group_admin(bigint) to authenticated;
create policy "voir mes groupes" on public.groups for select to authenticated using (public.is_group_member(id));
create policy "renommer groupe" on public.groups for update to authenticated using (public.is_group_admin(id)) with check (public.is_group_admin(id));
create policy "voir membres" on public.group_members for select to authenticated using (public.is_group_member(group_id));
create policy "quitter ou retirer" on public.group_members for delete to authenticated using (user_id = auth.uid() or public.is_group_admin(group_id));
create policy "voir messages groupe" on public.group_messages for select to authenticated using (public.is_group_member(group_id));
create policy "ecrire dans groupe" on public.group_messages for insert to authenticated with check (sender = auth.uid() and public.is_group_member(group_id));
create function public.create_group(group_name text, members uuid[]) returns bigint language plpgsql security definer set search_path = '' as $$
declare gid bigint; m uuid;
begin
  if char_length(trim(group_name)) < 1 then raise exception 'nom invalide'; end if;
  insert into public.groups (name, created_by) values (trim(group_name), auth.uid()) returning id into gid;
  insert into public.group_members (group_id, user_id, role) values (gid, auth.uid(), 'admin');
  foreach m in array members loop
    if m <> auth.uid() and public.are_friends(auth.uid(), m) then
      insert into public.group_members (group_id, user_id) values (gid, m) on conflict do nothing; end if;
  end loop;
  return gid;
end; $$;
create function public.add_group_member(gid bigint, member uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_group_admin(gid) then raise exception 'reserve aux admins'; end if;
  if not public.are_friends(auth.uid(), member) then raise exception 'pas ami'; end if;
  insert into public.group_members (group_id, user_id) values (gid, member) on conflict do nothing;
end; $$;
revoke execute on function public.create_group(text, uuid[]) from public, anon;
revoke execute on function public.add_group_member(bigint, uuid) from public, anon;
grant execute on function public.create_group(text, uuid[]) to authenticated;
grant execute on function public.add_group_member(bigint, uuid) to authenticated;
alter publication supabase_realtime add table public.group_messages;
alter publication supabase_realtime add table public.group_members;
