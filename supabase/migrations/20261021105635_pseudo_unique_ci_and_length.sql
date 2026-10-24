create unique index if not exists profiles_pseudo_lower_idx on public.profiles (lower(pseudo));
alter table public.profiles add constraint profiles_pseudo_length check (char_length(pseudo) between 3 and 30);
