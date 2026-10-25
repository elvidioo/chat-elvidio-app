-- Invitations de groupe par code/QR : table + fonctions (voir la version appliquée en base).
create table public.group_invites (
  code text primary key,
  group_id bigint not null references public.groups(id) on delete cascade,
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  max_uses int not null default 100 check (max_uses between 1 and 1000),
  uses int not null default 0,
  revoked boolean not null default false
);
alter table public.group_invites enable row level security;
create policy "admins voient les invitations" on public.group_invites for select to authenticated
  using (private.is_group_admin(group_id));

create or replace function public.create_group_invite(gid bigint, days int default 7)
returns text language plpgsql security definer set search_path = '' as $$
declare c text;
begin
  if auth.uid() is null or not private.is_group_admin(gid) then raise exception 'reserve aux admins'; end if;
  c := upper(substr(translate(encode(extensions.gen_random_bytes(12), 'base64'), '+/=0O1IlL', ''), 1, 10));
  if char_length(c) < 10 then raise exception 'code invalide, reessayer'; end if;
  insert into public.group_invites (code, group_id, created_by, expires_at)
  values (c, gid, auth.uid(), now() + make_interval(days => greatest(1, least(days, 30))));
  return c;
end $$;

create or replace function public.preview_group_invite(invite_code text)
returns table (group_id bigint, name text, members bigint, already_member boolean)
language sql security definer stable set search_path = '' as $$
  select g.id, g.name,
         (select count(*) from public.group_members m where m.group_id = g.id),
         exists (select 1 from public.group_members m where m.group_id = g.id and m.user_id = auth.uid())
  from public.group_invites i join public.groups g on g.id = i.group_id
  where i.code = upper(trim(invite_code)) and not i.revoked and i.expires_at > now()
    and i.uses < i.max_uses and auth.uid() is not null;
$$;

create or replace function public.join_group_by_code(invite_code text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare inv public.group_invites%rowtype;
begin
  if auth.uid() is null then raise exception 'connexion requise'; end if;
  select * into inv from public.group_invites
   where code = upper(trim(invite_code)) and not revoked and expires_at > now() and uses < max_uses
   for update;
  if not found then raise exception 'invitation invalide ou expiree'; end if;
  if private.is_blocked(auth.uid(), inv.created_by) then raise exception 'invitation indisponible'; end if;
  if not exists (select 1 from public.group_members where group_id = inv.group_id and user_id = auth.uid()) then
    insert into public.group_members (group_id, user_id) values (inv.group_id, auth.uid());
    update public.group_invites set uses = uses + 1 where code = inv.code;
  end if;
  return inv.group_id;
end $$;

create or replace function public.revoke_group_invites(gid bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_group_admin(gid) then raise exception 'reserve aux admins'; end if;
  update public.group_invites set revoked = true where group_id = gid and not revoked;
end $$;

revoke execute on function public.create_group_invite(bigint, int) from public, anon;
revoke execute on function public.preview_group_invite(text) from public, anon;
revoke execute on function public.join_group_by_code(text) from public, anon;
revoke execute on function public.revoke_group_invites(bigint) from public, anon;
grant execute on function public.create_group_invite(bigint, int) to authenticated;
grant execute on function public.preview_group_invite(text) to authenticated;
grant execute on function public.join_group_by_code(text) to authenticated;
grant execute on function public.revoke_group_invites(bigint) to authenticated;
