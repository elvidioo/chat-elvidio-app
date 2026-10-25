-- Supprimer pour tous : l'expéditeur supprime son message ; un admin peut supprimer dans son groupe.
-- (Les réactions disparaissent avec le message, ON DELETE CASCADE.)
create policy "supprimer mon message" on public.messages for delete to authenticated using (sender = auth.uid());
create policy "supprimer message groupe" on public.group_messages for delete to authenticated
  using (sender = auth.uid() or private.is_group_admin(group_id));
