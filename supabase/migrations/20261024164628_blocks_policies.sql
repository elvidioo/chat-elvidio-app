alter policy "envoyer un message" on public.messages
  with check (auth.uid() = sender and public.are_friends(sender, receiver) and not public.is_blocked(sender, receiver));
alter policy "demander en ami" on public.friendships
  with check (auth.uid() = requester and status = 'pending' and not public.is_blocked(requester, addressee));
