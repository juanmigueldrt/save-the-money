-- Fase 4: pagos recurrentes y metas.
--
-- Pagos recurrentes: suscripciones, gastos esenciales (alquiler, luz, agua...) e
-- ingresos fijos. Metas: de ahorro o de pagar una deuda, con sus aportaciones.
-- Todo se comparte dentro del hogar (lo decidió Jean el 2026-10-26) y sólo lo
-- ven y tocan sus miembros. Los avisos son locales en el dispositivo, así que
-- aquí no se guarda ningún token de notificaciones.

-- Tipos ---------------------------------------------------------------------

create type public.recurring_kind as enum ('subscription', 'essential', 'income');
create type public.recurrence_unit as enum ('week', 'month', 'year');
create type public.goal_kind as enum ('savings', 'debt');

-- Pagos recurrentes -----------------------------------------------------------

create table public.recurring_series (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 60),
  kind public.recurring_kind not null default 'subscription',
  -- Siempre en positivo: el signo lo da el tipo (los ingresos suman, el resto resta).
  amount_minor bigint not null check (amount_minor > 0),
  account_id uuid,
  category_id uuid,
  -- Cada cuántas unidades se repite: cada 1 mes, cada 3 meses, cada 2 semanas...
  every smallint not null default 1 check (every between 1 and 52),
  unit public.recurrence_unit not null default 'month',
  -- Primer cargo; los siguientes se calculan a partir de él.
  starts_on date not null,
  ends_on date,
  -- Días de antelación del aviso; null = sin aviso.
  remind_days_before smallint default 1 check (remind_days_before between 0 and 14),
  archived_at timestamptz,
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_on is null or ends_on >= starts_on),
  foreign key (account_id, household_id) references public.accounts (id, household_id) on delete set null (account_id),
  foreign key (category_id, household_id) references public.categories (id, household_id) on delete set null (category_id),
  unique (id, household_id)
);

create index recurring_series_household_id_idx on public.recurring_series (household_id);
create index recurring_series_account_id_idx on public.recurring_series (account_id);
create index recurring_series_category_id_idx on public.recurring_series (category_id);

-- Metas -------------------------------------------------------------------------

create table public.goals (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 60),
  kind public.goal_kind not null default 'savings',
  -- Ahorro: lo que se quiere juntar. Deuda: lo que se debía al empezar.
  target_minor bigint not null check (target_minor > 0),
  -- Lo que ya había (ahorrado o pagado) antes de llevar la cuenta aquí.
  starting_minor bigint not null default 0 check (starting_minor >= 0),
  -- Aportación mensual prevista, para la proyección.
  monthly_plan_minor bigint check (monthly_plan_minor >= 0),
  target_on date,
  account_id uuid,
  icon text check (char_length(icon) <= 40),
  completed_at timestamptz,
  archived_at timestamptz,
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (account_id, household_id) references public.accounts (id, household_id) on delete set null (account_id),
  unique (id, household_id)
);

create index goals_household_id_idx on public.goals (household_id);
create index goals_account_id_idx on public.goals (account_id);

create table public.goal_contributions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  goal_id uuid not null,
  -- Positivo: aportación o pago. Negativo: se saca dinero de la meta.
  amount_minor bigint not null check (amount_minor <> 0),
  made_on date not null,
  note text check (char_length(note) <= 200),
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (goal_id, household_id) references public.goals (id, household_id) on delete cascade
);

create index goal_contributions_goal_made_idx on public.goal_contributions (goal_id, made_on desc);
create index goal_contributions_household_id_idx on public.goal_contributions (household_id);

create trigger recurring_series_touch before update on public.recurring_series
  for each row execute function private.touch_updated_at();
create trigger goals_touch before update on public.goals
  for each row execute function private.touch_updated_at();
create trigger goal_contributions_touch before update on public.goal_contributions
  for each row execute function private.touch_updated_at();

-- RLS ---------------------------------------------------------------------------

alter table public.recurring_series enable row level security;
alter table public.goals enable row level security;
alter table public.goal_contributions enable row level security;

revoke all on public.recurring_series, public.goals, public.goal_contributions from anon, authenticated;

-- household_id y created_by no se pueden cambiar después de crear la fila.
grant select,
  insert (household_id, name, kind, amount_minor, account_id, category_id, every, unit, starts_on, ends_on,
          remind_days_before, archived_at),
  update (name, kind, amount_minor, account_id, category_id, every, unit, starts_on, ends_on,
          remind_days_before, archived_at),
  delete
  on public.recurring_series to authenticated;
grant select,
  insert (household_id, name, kind, target_minor, starting_minor, monthly_plan_minor, target_on, account_id,
          icon, completed_at, archived_at),
  update (name, kind, target_minor, starting_minor, monthly_plan_minor, target_on, account_id,
          icon, completed_at, archived_at),
  delete
  on public.goals to authenticated;
grant select,
  insert (household_id, goal_id, amount_minor, made_on, note),
  update (amount_minor, made_on, note),
  delete
  on public.goal_contributions to authenticated;

create policy recurring_series_select on public.recurring_series
  for select to authenticated
  using ((select private.is_member(household_id)));
create policy recurring_series_insert on public.recurring_series
  for insert to authenticated
  with check ((select private.is_member(household_id)));
create policy recurring_series_update on public.recurring_series
  for update to authenticated
  using ((select private.is_member(household_id)))
  with check ((select private.is_member(household_id)));
create policy recurring_series_delete on public.recurring_series
  for delete to authenticated
  using ((select private.is_member(household_id)));

create policy goals_select on public.goals
  for select to authenticated
  using ((select private.is_member(household_id)));
create policy goals_insert on public.goals
  for insert to authenticated
  with check ((select private.is_member(household_id)));
create policy goals_update on public.goals
  for update to authenticated
  using ((select private.is_member(household_id)))
  with check ((select private.is_member(household_id)));
create policy goals_delete on public.goals
  for delete to authenticated
  using ((select private.is_member(household_id)));

create policy goal_contributions_select on public.goal_contributions
  for select to authenticated
  using ((select private.is_member(household_id)));
create policy goal_contributions_insert on public.goal_contributions
  for insert to authenticated
  with check ((select private.is_member(household_id)));
create policy goal_contributions_update on public.goal_contributions
  for update to authenticated
  using ((select private.is_member(household_id)))
  with check ((select private.is_member(household_id)));
create policy goal_contributions_delete on public.goal_contributions
  for delete to authenticated
  using ((select private.is_member(household_id)));
