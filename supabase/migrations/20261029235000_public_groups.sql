-- Groupes publics rejoignables en un clic (créés par l'administrateur).
alter table public.groups add column is_public boolean not null default false;

create function public.public_groups() returns table (id bigint, name text, avatar_url text, members int, joined boolean)
language sql stable security definer set search_path = '' as $$
  select g.id, g.name, g.avatar_url,
         (select count(*)::int from public.group_members m where m.group_id = g.id),
         exists (select 1 from public.group_members m where m.group_id = g.id and m.user_id = (select auth.uid()))
  from public.groups g
  where g.is_public
  order by 4 desc, g.created_at;
$$;

create function public.join_public_group(gid bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare me uuid := (select auth.uid());
begin
  if me is null then raise exception 'Connexion requise'; end if;
  if not exists (select 1 from public.groups g where g.id = gid and g.is_public) then
    raise exception 'Groupe introuvable';
  end if;
  insert into public.group_members (group_id, user_id, role) values (gid, me, 'member') on conflict do nothing;
end $$;

revoke execute on function public.public_groups() from public, anon;
revoke execute on function public.join_public_group(bigint) from public, anon;
grant execute on function public.public_groups() to authenticated;
grant execute on function public.join_public_group(bigint) to authenticated;
-- Les groupes de départ (Terminale C - Entraide, Bac Bénin - Révisions, Football) ont été créés une fois dans la base.
