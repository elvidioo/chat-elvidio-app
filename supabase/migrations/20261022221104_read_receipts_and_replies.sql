alter table public.messages add column if not exists read_at timestamptz,
  add column if not exists reply_to bigint references public.messages(id) on delete set null;
create index if not exists messages_reply_to_idx on public.messages(reply_to);
create or replace function public.mark_read(peer uuid) returns void language sql security definer set search_path = '' as $$
  update public.messages set read_at = now() where receiver = auth.uid() and sender = peer and read_at is null;
$$;
revoke all on function public.mark_read(uuid) from public, anon;
grant execute on function public.mark_read(uuid) to authenticated;
