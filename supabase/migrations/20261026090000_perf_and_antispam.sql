-- Index sur les clés étrangères
create index if not exists blocks_blocked_idx on public.blocks (blocked);
create index if not exists call_signals_sender_idx on public.call_signals (sender, created_at desc);
create index if not exists device_tokens_user_idx on public.device_tokens (user_id);
create index if not exists friendships_addressee_idx on public.friendships (addressee);
create index if not exists friendships_requester_idx on public.friendships (requester, created_at desc);
create index if not exists group_invites_created_by_idx on public.group_invites (created_by);
create index if not exists group_invites_group_idx on public.group_invites (group_id);
create index if not exists group_members_user_idx on public.group_members (user_id);
create index if not exists group_message_reactions_user_idx on public.group_message_reactions (user_id);
create index if not exists group_messages_sender_idx on public.group_messages (sender, created_at desc);
create index if not exists groups_created_by_idx on public.groups (created_by);
create index if not exists message_reactions_user_idx on public.message_reactions (user_id);
create index if not exists post_reactions_user_idx on public.post_reactions (user_id);
create index if not exists posts_author_idx on public.posts (author, created_at desc);
create index if not exists reports_reporter_idx on public.reports (reporter, created_at desc);
create index if not exists reports_target_user_idx on public.reports (target_user);
create index if not exists messages_sender_created_idx on public.messages (sender, created_at desc);

-- Politiques RLS : auth.uid() évalué une seule fois par requête ("(select auth.uid())").
do $$
declare r record; cmd text;
begin
  for r in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where schemaname = 'public'
      and (coalesce(qual,'') ~ 'auth\.(uid|role)\(\)' or coalesce(with_check,'') ~ 'auth\.(uid|role)\(\)')
      and not (coalesce(qual,'') ~* 'select auth\.' or coalesce(with_check,'') ~* 'select auth\.')
  loop
    cmd := format('alter policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
    if r.qual is not null then
      cmd := cmd || ' using (' || replace(replace(r.qual, 'auth.uid()', '(select auth.uid())'), 'auth.role()', '(select auth.role())') || ')';
    end if;
    if r.with_check is not null then
      cmd := cmd || ' with check (' || replace(replace(r.with_check, 'auth.uid()', '(select auth.uid())'), 'auth.role()', '(select auth.role())') || ')';
    end if;
    execute cmd;
  end loop;
end $$;

-- Anti-spam : limite de débit par expéditeur
create or replace function private.rate_limit() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  col text := tg_argv[0];
  max_n int := tg_argv[1]::int;
  win interval := tg_argv[2]::interval;
  who uuid;
  n int;
begin
  execute format('select ($1).%I', col) into who using new;
  execute format('select count(*) from %I.%I where %I = $1 and created_at > now() - $2', tg_table_schema, tg_table_name, col)
    into n using who, win;
  if n >= max_n then
    raise exception 'trop de requetes, ralentis un peu' using errcode = 'P0001';
  end if;
  return new;
end $$;
create trigger messages_rate_limit before insert on public.messages
  for each row execute function private.rate_limit('sender', '25', '10 seconds');
create trigger group_messages_rate_limit before insert on public.group_messages
  for each row execute function private.rate_limit('sender', '25', '10 seconds');
create trigger friendships_rate_limit before insert on public.friendships
  for each row execute function private.rate_limit('requester', '20', '1 minute');
create trigger reports_rate_limit before insert on public.reports
  for each row execute function private.rate_limit('reporter', '10', '1 minute');
create trigger call_signals_rate_limit before insert on public.call_signals
  for each row execute function private.rate_limit('sender', '200', '10 seconds');
create trigger posts_rate_limit before insert on public.posts
  for each row execute function private.rate_limit('author', '20', '1 minute');

create policy "supprimer mes medias" on storage.objects for delete to authenticated
  using (bucket_id = 'media' and (storage.foldername(name))[1] = (select auth.uid())::text);
