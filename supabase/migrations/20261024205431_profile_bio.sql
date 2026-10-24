alter table public.profiles add column if not exists bio text check (char_length(bio) <= 200);
