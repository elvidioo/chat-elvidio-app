create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  pseudo text unique not null,
  created_at timestamptz default now()
);
create table public.messages (
  id bigint generated always as identity primary key,
  sender uuid not null references public.profiles(id) on delete cascade,
  receiver uuid not null references public.profiles(id) on delete cascade,
  content text,
  media_url text,
  created_at timestamptz default now()
);
create index messages_sender_idx on public.messages(sender);
create index messages_receiver_idx on public.messages(receiver);
alter table public.profiles enable row level security;
alter table public.messages enable row level security;
create policy "profils visibles" on public.profiles for select using (auth.role() = 'authenticated');
create policy "mon profil" on public.profiles for insert with check (auth.uid() = id);
create policy "modifier mon profil" on public.profiles for update using (auth.uid() = id);
create policy "lire mes messages" on public.messages for select using (auth.uid() in (sender, receiver));
create policy "envoyer un message" on public.messages for insert with check (auth.uid() = sender);
