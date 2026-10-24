alter table public.profiles add column if not exists avatar_url text;
alter table public.messages add column if not exists media_name text;
