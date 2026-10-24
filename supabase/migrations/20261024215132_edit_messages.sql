alter table public.messages add column if not exists edited_at timestamptz;
alter table public.group_messages add column if not exists edited_at timestamptz;
create function public.edit_message(mid bigint, new_content text) returns void language sql security definer set search_path = '' as $$
  update public.messages set content = left(trim(new_content), 4000), edited_at = now()
   where id = mid and sender = auth.uid() and media_url is null and char_length(trim(new_content)) > 0; $$;
create function public.edit_group_message(mid bigint, new_content text) returns void language sql security definer set search_path = '' as $$
  update public.group_messages set content = left(trim(new_content), 4000), edited_at = now()
   where id = mid and sender = auth.uid() and media_url is null and char_length(trim(new_content)) > 0; $$;
revoke execute on function public.edit_message(bigint, text) from public, anon;
revoke execute on function public.edit_group_message(bigint, text) from public, anon;
grant execute on function public.edit_message(bigint, text) to authenticated;
grant execute on function public.edit_group_message(bigint, text) to authenticated;
