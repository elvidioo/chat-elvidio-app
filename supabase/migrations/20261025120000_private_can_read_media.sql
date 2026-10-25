-- Qui peut lire un fichier du bucket `media` : son propriétaire, les participants du message,
-- les membres du groupe, les amis pour un post, tout utilisateur connecté pour une photo de profil.
-- NB : recherche par LIKE sur les liens ; à remplacer par une colonne indexée si la table grossit.
create or replace function private.can_read_media(obj text) returns boolean
language sql security definer stable set search_path = '' as $$
  select
    (storage.foldername(obj))[1] = auth.uid()::text
    or exists (select 1 from public.profiles p where p.avatar_url like '%/media/' || obj || '%')
    or exists (select 1 from public.messages m
        where auth.uid() in (m.sender, m.receiver) and m.media_url like '%/media/' || obj || '%')
    or exists (select 1 from public.group_messages g
        where private.is_group_member(g.group_id) and g.media_url like '%/media/' || obj || '%')
    or exists (select 1 from public.posts po
        where (po.author = auth.uid() or private.are_friends(po.author, auth.uid()))
          and po.media_url like '%/media/' || obj || '%');
$$;
revoke execute on function private.can_read_media(text) from public, anon;
grant execute on function private.can_read_media(text) to authenticated;
