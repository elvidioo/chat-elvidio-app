alter table public.messages add column if not exists client_id uuid;
create unique index if not exists messages_sender_client_id_key on public.messages (sender, client_id);
