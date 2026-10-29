-- Suggestions d'amis : amis en commun, groupes en commun, puis comptes recemment actifs.
create function public.suggest_people() returns table (id uuid, pseudo text, avatar_url text, mutual int, shared_groups int)
language sql stable security definer set search_path = '' as $$
  with me as (select (select auth.uid()) as uid),
  mine as (
    select case when f.requester = (select uid from me) then f.addressee else f.requester end as friend
    from public.friendships f
    where f.status = 'accepted' and (select uid from me) in (f.requester, f.addressee)
  ),
  related as (
    select case when f.requester = (select uid from me) then f.addressee else f.requester end as other
    from public.friendships f
    where (select uid from me) in (f.requester, f.addressee)
  ),
  fof as (
    select case when f.requester = m.friend then f.addressee else f.requester end as cand, count(*)::int as mutual
    from public.friendships f join mine m on m.friend in (f.requester, f.addressee)
    where f.status = 'accepted'
    group by 1
  ),
  grp as (
    select g2.user_id as cand, count(*)::int as shared
    from public.group_members g1
    join public.group_members g2 on g2.group_id = g1.group_id and g2.user_id <> g1.user_id
    where g1.user_id = (select uid from me)
    group by 1
  ),
  scored as (
    select p.id, p.pseudo, p.avatar_url,
           coalesce(fof.mutual, 0) as mutual, coalesce(grp.shared, 0) as shared_groups,
           p.last_seen, p.created_at
    from public.profiles p
    left join fof on fof.cand = p.id
    left join grp on grp.cand = p.id
    where p.id <> (select uid from me)
      and p.pseudo is not null and btrim(p.pseudo) <> ''
      and p.id not in (select other from related)
      and not private.is_blocked((select uid from me), p.id)
  )
  select id, pseudo, avatar_url, mutual, shared_groups from scored
  order by (mutual * 3 + shared_groups * 2) desc, last_seen desc nulls last, created_at desc
  limit 20;
$$;
revoke execute on function public.suggest_people() from public, anon;
grant execute on function public.suggest_people() to authenticated;
