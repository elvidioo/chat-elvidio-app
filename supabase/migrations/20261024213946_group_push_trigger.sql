-- Remplacer __PUSH_SECRET__ (valeur non publiée dans le dépôt).
create function public.notify_group_message() returns trigger language plpgsql security definer set search_path = '' as $$
declare recv uuid[]; gname text;
begin
  select array_agg(user_id) into recv from public.group_members where group_id = new.group_id and user_id <> new.sender;
  select name into gname from public.groups where id = new.group_id;
  if recv is not null then
    perform net.http_post(
      url := 'https://cokalbfyyhlrslautebc.supabase.co/functions/v1/push',
      headers := jsonb_build_object('Content-Type','application/json','x-push-secret','__PUSH_SECRET__'),
      body := jsonb_build_object('sender', new.sender, 'receivers', to_jsonb(recv), 'group', gname,
        'content', new.content, 'media_url', new.media_url, 'id', new.id));
  end if;
  return new;
exception when others then return new;
end; $$;
revoke execute on function public.notify_group_message() from public, anon, authenticated;
create trigger group_messages_push after insert on public.group_messages for each row execute function public.notify_group_message();
