-- Commentaires des publications
create table public.post_comments (
  id bigint generated always as identity primary key,
  post_id bigint not null references public.posts(id) on delete cascade,
  author uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  content text not null check (char_length(btrim(content)) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index post_comments_post_idx on public.post_comments (post_id, created_at);
create index post_comments_author_idx on public.post_comments (author, created_at desc);
alter table public.post_comments enable row level security;

create function private.is_post_author(pid bigint) returns boolean
language sql security definer stable set search_path = '' as $$
  select exists (select 1 from public.posts p where p.id = pid and p.author = (select auth.uid())); $$;
revoke execute on function private.is_post_author(bigint) from public, anon;
grant execute on function private.is_post_author(bigint) to authenticated;

create policy "voir commentaires" on public.post_comments for select to authenticated
  using (private.can_see_post(post_id));
create policy "commenter" on public.post_comments for insert to authenticated
  with check (author = (select auth.uid()) and private.can_see_post(post_id));
create policy "supprimer commentaire" on public.post_comments for delete to authenticated
  using (author = (select auth.uid()) or private.is_post_author(post_id));

-- Qui a vu une story
create table public.story_views (
  post_id bigint not null references public.posts(id) on delete cascade,
  viewer uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (post_id, viewer)
);
create index story_views_viewer_idx on public.story_views (viewer);
alter table public.story_views enable row level security;
create policy "marquer vu" on public.story_views for insert to authenticated
  with check (viewer = (select auth.uid()) and private.can_see_post(post_id));
create policy "voir les vues" on public.story_views for select to authenticated
  using (viewer = (select auth.uid()) or private.is_post_author(post_id));

-- Réactions : sur une story, seul l'auteur voit qui a réagi (et chacun voit la sienne)
create function private.can_see_post_reaction(pid bigint, reactor uuid) returns boolean
language sql security definer stable set search_path = '' as $$
  select exists (
    select 1 from public.posts p
    where p.id = pid
      and (p.author = (select auth.uid()) or private.are_friends(p.author, (select auth.uid())))
      and (p.kind = 'post' or p.author = (select auth.uid()) or reactor = (select auth.uid()))); $$;
revoke execute on function private.can_see_post_reaction(bigint, uuid) from public, anon;
grant execute on function private.can_see_post_reaction(bigint, uuid) to authenticated;
alter policy "voir reactions posts" on public.post_reactions
  using (private.can_see_post_reaction(post_id, user_id));

-- Nombre de commentaires par publication (respecte les règles d'accès de l'appelant)
create function public.post_comment_counts(ids bigint[]) returns table (post_id bigint, n bigint)
language sql stable security invoker set search_path = '' as $$
  select c.post_id, count(*) from public.post_comments c where c.post_id = any(ids) group by c.post_id; $$;
revoke execute on function public.post_comment_counts(bigint[]) from public, anon;
grant execute on function public.post_comment_counts(bigint[]) to authenticated;

alter publication supabase_realtime add table public.post_comments;

create trigger post_comments_rate_limit before insert on public.post_comments
  for each row execute function private.rate_limit('author', '30', '1 minute');

-- Notification push quand quelqu'un commente (le secret est repris de la fonction
-- notify_new_message déjà en place ; il n'est jamais écrit dans le dépôt).
do $$
declare d text; secret text;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'notify_new_message';
  secret := substring(d from '[0-9a-f]{40,}');
  if secret is null then raise exception 'secret introuvable'; end if;
  if d not like '%''media_name''%' then
    d := replace(d, '''media_url'', new.media_url,', '''media_url'', new.media_url, ''media_name'', new.media_name,');
    execute d;
  end if;
  execute format($f$
    create or replace function public.notify_new_comment() returns trigger
    language plpgsql security definer set search_path = '' as $b$
    declare owner uuid;
    begin
      select author into owner from public.posts where id = new.post_id;
      if owner is not null and owner <> new.author then
        perform net.http_post(
          url := 'https://cokalbfyyhlrslautebc.supabase.co/functions/v1/push',
          headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', %L),
          body := jsonb_build_object('kind', 'comment', 'sender', new.author, 'receiver', owner,
                                     'content', new.content, 'id', new.id));
      end if;
      return new;
    exception when others then
      return new;
    end $b$;
  $f$, secret);
end $$;
revoke execute on function public.notify_new_comment() from public, anon, authenticated;
create trigger post_comments_push after insert on public.post_comments
  for each row execute function public.notify_new_comment();

-- Réponses aux commentaires (un niveau)
alter table public.post_comments add column parent_id bigint references public.post_comments(id) on delete cascade;
create index post_comments_parent_idx on public.post_comments (parent_id);
