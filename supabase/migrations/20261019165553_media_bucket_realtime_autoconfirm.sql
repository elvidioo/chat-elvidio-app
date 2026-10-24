insert into storage.buckets (id, name, public, file_size_limit)
values ('media', 'media', true, 52428800) on conflict (id) do nothing;
create policy "lecture média" on storage.objects for select using (bucket_id = 'media');
create policy "envoi média dans son dossier" on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);
alter publication supabase_realtime add table public.messages;
create or replace function public.auto_confirm_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin new.email_confirmed_at := coalesce(new.email_confirmed_at, now()); return new; end $$;
create trigger auto_confirm_before_insert before insert on auth.users for each row execute function public.auto_confirm_user();
