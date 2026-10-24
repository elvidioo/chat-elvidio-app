-- Les fonctions d'aide SECURITY DEFINER sortent du schéma public (non exposé par l'API REST).
create schema if not exists private;
grant usage on schema private to authenticated;
alter function public.are_friends(uuid, uuid) set schema private;
alter function public.is_blocked(uuid, uuid) set schema private;
alter function public.can_see_message(bigint) set schema private;
alter function public.can_see_post(bigint) set schema private;
alter function public.can_see_group_message(bigint) set schema private;
alter function public.is_group_member(bigint) set schema private;
alter function public.is_group_admin(bigint) set schema private;
-- create_group / add_group_member / suggest_friends sont ensuite redéfinies avec private.* ;
-- voir l'historique de la base (corps identiques à ceux des migrations précédentes, préfixe private.).
create or replace function public.create_group(group_name text, members uuid[]) returns bigint language plpgsql security definer set search_path = '' as $$
declare gid bigint; m uuid;
begin
  if char_length(trim(group_name)) < 1 then raise exception 'nom invalide'; end if;
  insert into public.groups (name, created_by) values (trim(group_name), auth.uid()) returning id into gid;
  insert into public.group_members (group_id, user_id, role) values (gid, auth.uid(), 'admin');
  foreach m in array members loop
    if m <> auth.uid() and private.are_friends(auth.uid(), m) then
      insert into public.group_members (group_id, user_id) values (gid, m) on conflict do nothing; end if;
  end loop;
  return gid;
end; $$;
create or replace function public.add_group_member(gid bigint, member uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_group_admin(gid) then raise exception 'reserve aux admins'; end if;
  if not private.are_friends(auth.uid(), member) then raise exception 'pas ami'; end if;
  insert into public.group_members (group_id, user_id) values (gid, member) on conflict do nothing;
end; $$;
create or replace function public.suggest_friends() returns table (id uuid, pseudo text, avatar_url text, mutual int)
language sql security definer stable set search_path = '' as $$
  with me as (select auth.uid() as uid),
  mine as (select case when f.requester=(select uid from me) then f.addressee else f.requester end as friend
    from public.friendships f where f.status='accepted' and (select uid from me) in (f.requester,f.addressee)),
  related as (select case when f.requester=(select uid from me) then f.addressee else f.requester end as other
    from public.friendships f where (select uid from me) in (f.requester,f.addressee)),
  fof as (select case when f.requester=m.friend then f.addressee else f.requester end as cand, count(*)::int as mutual
    from public.friendships f join mine m on m.friend in (f.requester,f.addressee) where f.status='accepted' group by 1),
  scored as (select p.id,p.pseudo,p.avatar_url,coalesce(fof.mutual,0) as mutual from public.profiles p
    left join fof on fof.cand=p.id where p.id<>(select uid from me) and p.id not in (select other from related)
      and not private.is_blocked((select uid from me),p.id))
  select id,pseudo,avatar_url,mutual from scored order by mutual desc, random() limit 15;
$$;
alter policy "envoyer un message" on public.messages to authenticated;
alter policy "lire mes messages" on public.messages to authenticated;
alter policy "mon profil" on public.profiles to authenticated;
alter policy "profils visibles" on public.profiles to authenticated;
alter policy "modifier mon profil" on public.profiles to authenticated with check (auth.uid() = id);
