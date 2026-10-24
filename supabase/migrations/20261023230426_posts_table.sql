create table public.posts (
  id bigint generated always as identity primary key,
  author uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  content text, media_url text, media_name text,
  kind text not null default 'post' check (kind in ('post','status')),
  created_at timestamptz not null default now(), expires_at timestamptz
);
alter table public.posts enable row level security;
create policy "voir posts amis" on public.posts for select to authenticated
  using ((author = auth.uid() or public.are_friends(author, auth.uid())) and (kind = 'post' or expires_at > now()));
create policy "publier" on public.posts for insert to authenticated with check (author = auth.uid());
create policy "supprimer mon post" on public.posts for delete to authenticated using (author = auth.uid());
create index posts_created_idx on public.posts (created_at desc);
