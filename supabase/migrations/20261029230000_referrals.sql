-- Parrainage : chaque compte a un code (8 premiers caractères de son identifiant).
-- Celui qui entre le code devient ami avec l'inviteur ; les deux gagnent 3 jours de Premium
-- (l'inviteur est récompensé pour 10 invitations au maximum).
create table public.referrals (
  invitee uuid primary key references auth.users (id) on delete cascade,
  inviter uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
create index referrals_inviter_idx on public.referrals (inviter);
alter table public.referrals enable row level security;
create policy "voir mes parrainages" on public.referrals for select to authenticated
  using ((select auth.uid()) in (inviter, invitee));

create function public.my_invite_code() returns text
language sql stable security definer set search_path = '' as $$
  select upper(substr((select auth.uid())::text, 1, 8));
$$;

create function public.redeem_invite(code text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
  c text := lower(btrim(code));
  inv uuid;
  inv_name text;
  n int;
begin
  if me is null then raise exception 'Connexion requise'; end if;
  if c !~ '^[0-9a-f]{8}$' then raise exception 'Code invalide'; end if;
  select p.id, p.pseudo into inv, inv_name from public.profiles p where p.id::text like c || '-%' limit 1;
  if inv is null then raise exception 'Code invalide'; end if;
  if inv = me then raise exception 'Tu ne peux pas utiliser ton propre code'; end if;
  if exists (select 1 from public.referrals where invitee = me) then
    raise exception 'Tu as déjà utilisé un code d''invitation';
  end if;
  insert into public.referrals (invitee, inviter) values (me, inv);

  if exists (select 1 from public.friendships f
             where (f.requester = me and f.addressee = inv) or (f.requester = inv and f.addressee = me)) then
    update public.friendships set status = 'accepted'
      where (requester = me and addressee = inv) or (requester = inv and addressee = me);
  else
    insert into public.friendships (requester, addressee, status) values (me, inv, 'accepted');
  end if;

  insert into public.premium (user_id, until) values (me, now() + interval '3 days')
    on conflict (user_id) do update set until = greatest(public.premium.until, now()) + interval '3 days';
  select count(*) into n from public.referrals where inviter = inv;
  if n <= 10 then
    insert into public.premium (user_id, until) values (inv, now() + interval '3 days')
      on conflict (user_id) do update set until = greatest(public.premium.until, now()) + interval '3 days';
  end if;
  return coalesce(inv_name, 'ton ami');
end $$;

revoke execute on function public.my_invite_code() from public, anon;
revoke execute on function public.redeem_invite(text) from public, anon;
grant execute on function public.my_invite_code() to authenticated;
grant execute on function public.redeem_invite(text) to authenticated;
