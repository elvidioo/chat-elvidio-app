-- ATTENTION : la valeur réelle du secret x-push-secret n'est PAS dans le dépôt.
-- Remplacer __PUSH_SECRET__ avant d'exécuter (même valeur que dans la fonction Edge `push`).
create extension if not exists pg_net with schema extensions;
create table public.device_tokens (
  token text primary key,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  updated_at timestamptz not null default now()
);
alter table public.device_tokens enable row level security;
create policy "mes appareils lecture" on public.device_tokens for select to authenticated using (user_id = auth.uid());
create policy "mes appareils ajout" on public.device_tokens for insert to authenticated with check (user_id = auth.uid());
create policy "mes appareils maj" on public.device_tokens for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "mes appareils suppression" on public.device_tokens for delete to authenticated using (user_id = auth.uid());
create function public.notify_new_message() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform net.http_post(
    url := 'https://cokalbfyyhlrslautebc.supabase.co/functions/v1/push',
    headers := jsonb_build_object('Content-Type','application/json','x-push-secret','__PUSH_SECRET__'),
    body := jsonb_build_object('sender', new.sender, 'receiver', new.receiver,
      'content', new.content, 'media_url', new.media_url, 'id', new.id));
  return new;
exception when others then return new;
end; $$;
revoke execute on function public.notify_new_message() from public, anon, authenticated;
create trigger messages_push after insert on public.messages for each row execute function public.notify_new_message();
