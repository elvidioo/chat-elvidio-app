-- Signalisation des appels par table (suivie en temps réel) au lieu de canaux broadcast.
create table public.call_signals (
  id bigint generated always as identity primary key,
  call_id text not null check (char_length(call_id) <= 40),
  sender uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  receiver uuid not null references public.profiles(id) on delete cascade,
  type text not null check (char_length(type) <= 20),
  payload jsonb not null default '{}'::jsonb check (pg_column_size(payload) < 60000),
  created_at timestamptz not null default now()
);
create index call_signals_receiver_idx on public.call_signals (receiver, created_at desc);
alter table public.call_signals enable row level security;
create policy "voir mes signaux" on public.call_signals for select to authenticated
  using (auth.uid() in (sender, receiver));
create policy "envoyer un signal" on public.call_signals for insert to authenticated
  with check (sender = auth.uid() and private.are_friends(sender, receiver)
              and not private.is_blocked(sender, receiver));
alter publication supabase_realtime add table public.call_signals;

-- Nettoyage : les signaux de plus de 10 minutes sont supprimés à chaque nouvel insert.
create or replace function private.cleanup_call_signals() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.call_signals where created_at < now() - interval '10 minutes';
  return null;
end $$;
create trigger call_signals_cleanup after insert on public.call_signals
  for each statement execute function private.cleanup_call_signals();
