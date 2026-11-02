-- Fase 5B: score crediticio apuntado a mano.
-- Es un dato personal, así que NO se comparte con el hogar: cada persona sólo ve,
-- apunta y borra los suyos. El patrimonio, los informes, el presupuesto flexible y
-- los avisos de límites se calculan en la app con lo que ya hay; no necesitan tablas.

create table public.credit_scores (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  score smallint not null check (score between 0 and 1000),
  -- Escala del proveedor: p. ej. 850 (FICO), 1000 u otra.
  max_score smallint not null default 850 check (max_score between 100 and 1000),
  provider text check (char_length(trim(provider)) between 1 and 60),
  recorded_on date not null default current_date,
  note text check (char_length(note) <= 200),
  created_at timestamptz not null default now(),
  check (score <= max_score)
);

create index credit_scores_user_idx on public.credit_scores (user_id, recorded_on desc);

alter table public.credit_scores enable row level security;

revoke all on public.credit_scores from anon, authenticated;
-- user_id lo pone el servidor (auth.uid()) y no se puede cambiar.
grant select, insert (score, max_score, provider, recorded_on, note),
  update (score, max_score, provider, recorded_on, note), delete
  on public.credit_scores to authenticated;

create policy credit_scores_select on public.credit_scores
  for select to authenticated
  using (user_id = (select auth.uid()));
create policy credit_scores_insert on public.credit_scores
  for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy credit_scores_update on public.credit_scores
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy credit_scores_delete on public.credit_scores
  for delete to authenticated
  using (user_id = (select auth.uid()));
