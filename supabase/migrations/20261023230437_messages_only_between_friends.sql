alter policy "envoyer un message" on public.messages
  with check (auth.uid() = sender and public.are_friends(sender, receiver));
