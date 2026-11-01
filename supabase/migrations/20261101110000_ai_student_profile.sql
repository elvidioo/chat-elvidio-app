-- Profil d'étudiant pour le tuteur IA (Lumi) : niveau, série/filière, matières.
create table public.ai_student (
  user_id uuid primary key references auth.users (id) on delete cascade,
  level text,
  serie text,
  field text,
  subjects text[] not null default '{}',
  updated_at timestamptz not null default now(),
  constraint ai_student_level_len check (level is null or char_length(level) <= 30),
  constraint ai_student_serie_len check (serie is null or char_length(serie) <= 30),
  constraint ai_student_field_len check (field is null or char_length(field) <= 80),
  constraint ai_student_subjects_len check (cardinality(subjects) <= 12)
);
alter table public.ai_student enable row level security;
create policy "mon profil etudiant" on public.ai_student for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "creer mon profil etudiant" on public.ai_student for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "modifier mon profil etudiant" on public.ai_student for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
