-- Alertes administrateur : nouveau compte (déclencheur) et nouveaux téléchargements (tâche planifiée toutes les 15 min).
-- Les secrets (admin_hook, push) sont dans public.internal_secrets, jamais dans le dépôt.
create table public.admin_events (
  id bigint generated always as identity primary key,
  kind text not null,
  text text not null,
  created_at timestamptz not null default now()
);
alter table public.admin_events enable row level security;
create policy "admins voient les alertes" on public.admin_events for select to authenticated
  using (exists (select 1 from public.admins a where a.user_id = (select auth.uid())));
alter publication supabase_realtime add table public.admin_events;
-- Fonctions public.notify_admin_signup() (déclencheur sur profiles) et public.check_downloads()
-- (planifiée avec pg_cron) : elles appellent la fonction edge admin-notify avec x-hook-secret lu dans internal_secrets.
