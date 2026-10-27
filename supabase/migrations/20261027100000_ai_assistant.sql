-- Assistant IA : répond aux messages à ta place quand tu es indisponible.
alter table public.messages add column is_ai boolean not null default false;

create table public.ai_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  enabled boolean not null default false,
  always boolean not null default true,
  from_min integer not null default 1320 check (from_min between 0 and 1439),
  to_min integer not null default 420 check (to_min between 0 and 1439),
  tz_offset_min integer not null default 60 check (tz_offset_min between -720 and 840),
  instructions text not null default '' check (char_length(instructions) <= 500),
  updated_at timestamptz not null default now()
);
alter table public.ai_settings enable row level security;
create policy "mes reglages ia" on public.ai_settings for select to authenticated using (user_id = (select auth.uid()));
create policy "creer reglages ia" on public.ai_settings for insert to authenticated with check (user_id = (select auth.uid()));
create policy "modifier reglages ia" on public.ai_settings for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

insert into public.app_config (key, value) values ('ai_ready', '0') on conflict do nothing;

-- Déclenche la fonction ai-reply quand le destinataire a activé son assistant.
-- Le secret __AI_HOOK_SECRET__ est remplacé au déploiement (jamais écrit dans le dépôt).
create function public.notify_ai_reply() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.is_ai or new.media_url is not null or coalesce(new.media_name, '') <> ''
     or new.content is null or btrim(new.content) = '' then
    return new;
  end if;
  if exists (select 1 from public.ai_settings s where s.user_id = new.receiver and s.enabled) then
    perform net.http_post(
      url := 'https://cokalbfyyhlrslautebc.supabase.co/functions/v1/ai-reply',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-hook-secret', '__AI_HOOK_SECRET__'),
      body := jsonb_build_object('id', new.id));
  end if;
  return new;
exception when others then
  return new;
end $$;
revoke execute on function public.notify_ai_reply() from public, anon, authenticated;
create trigger messages_ai_reply after insert on public.messages
  for each row execute function public.notify_ai_reply();

-- Secret interne lu uniquement par la fonction ai-reply (clé de service) : aucune politique, accès fermé aux utilisateurs.
create table public.internal_secrets (key text primary key, value text not null);
alter table public.internal_secrets enable row level security;
revoke all on public.internal_secrets from anon, authenticated;
-- insert into public.internal_secrets (key, value) values ('ai_hook', '<valeur aléatoire, identique à celle du déclencheur>');

-- Discussion directe avec l'IA (écrite uniquement par la fonction ai-chat)
create table public.ai_chats (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('user','assistant')),
  content text not null check (char_length(content) <= 4000),
  created_at timestamptz not null default now()
);
create index ai_chats_user_idx on public.ai_chats (user_id, created_at desc);
alter table public.ai_chats enable row level security;
create policy "voir ma discussion ia" on public.ai_chats for select to authenticated using (user_id = (select auth.uid()));
create policy "vider ma discussion ia" on public.ai_chats for delete to authenticated using (user_id = (select auth.uid()));
