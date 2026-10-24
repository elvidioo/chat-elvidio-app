-- Version initiale ; redéfinie avec le schéma private dans private_helpers_schema.
create function public.suggest_friends() returns table (id uuid, pseudo text, avatar_url text, mutual int)
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
      and not public.is_blocked((select uid from me),p.id))
  select id,pseudo,avatar_url,mutual from scored order by mutual desc, random() limit 15;
$$;
revoke execute on function public.suggest_friends() from public, anon;
grant execute on function public.suggest_friends() to authenticated;
