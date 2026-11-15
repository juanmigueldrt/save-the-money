-- Fase C: presupuesto por periodos.
--
-- 1. Cada persona guarda su día y frecuencia de cobro (privado: sólo lo ve quien lo guarda).
-- 2. El presupuesto deja de ser «de un mes»: la columna month pasa a ser el primer día del
--    periodo y se añade ends_on, el arrastre y el % de aviso. Los que ya hay se convierten
--    al periodo real que marcaba month_start_day del hogar, sin perder nada.
-- 3. Presupuestos extra con nombre, límite, fechas, categorías y cuentas (p. ej. «Vacaciones»).

-- 1. Día de cobro ------------------------------------------------------------------------

create table public.pay_schedules (
  user_id uuid primary key references auth.users (id) on delete cascade default auth.uid(),
  -- monthly: día day1 de cada mes · twice_monthly: días day1 y day2 · weekly/biweekly: cada
  -- 7/14 días desde anchor_on · yearly: cada año desde anchor_on.
  frequency text not null default 'monthly'
    check (frequency in ('weekly', 'biweekly', 'twice_monthly', 'monthly', 'yearly')),
  day1 smallint not null default 1 check (day1 between 1 and 31),
  day2 smallint check (day2 between 1 and 31),
  anchor_on date,
  updated_at timestamptz not null default now(),
  check (frequency <> 'twice_monthly' or (day2 is not null and day2 > day1)),
  check (frequency not in ('weekly', 'biweekly', 'yearly') or anchor_on is not null)
);

create trigger pay_schedules_touch before update on public.pay_schedules
  for each row execute function private.touch_updated_at();

alter table public.pay_schedules enable row level security;
revoke all on public.pay_schedules from anon, authenticated;
grant select, insert (frequency, day1, day2, anchor_on), update (frequency, day1, day2, anchor_on), delete
  on public.pay_schedules to authenticated;

create policy pay_schedules_select on public.pay_schedules for select to authenticated
  using (user_id = (select auth.uid()));
create policy pay_schedules_insert on public.pay_schedules for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy pay_schedules_update on public.pay_schedules for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy pay_schedules_delete on public.pay_schedules for delete to authenticated
  using (user_id = (select auth.uid()));

-- Quien ya está en un hogar empieza con el día de inicio de mes que tenía el hogar.
insert into public.pay_schedules (user_id, frequency, day1)
select distinct on (m.user_id) m.user_id, 'monthly', h.month_start_day
from public.household_members m
join public.households h on h.id = m.household_id
order by m.user_id, m.created_at
on conflict (user_id) do nothing;

-- 2. Presupuesto por periodo ---------------------------------------------------------------

alter table public.budgets drop constraint budgets_month_check;
alter table public.budgets
  add column ends_on date,
  add column carry_over boolean not null default false,
  add column warn_pct smallint not null default 80 check (warn_pct between 50 and 100);

comment on column public.budgets.month is 'Primer día del periodo del presupuesto (antes, primer día del mes).';

-- Los guardados por mes pasan a su periodo real: con month_start_day = 25, el de noviembre
-- va del 25 de octubre al 24 de noviembre.
update public.budgets b
set month = case when h.month_start_day = 1 then b.month
                 else (b.month - interval '1 month' + (h.month_start_day - 1) * interval '1 day')::date end,
    ends_on = case when h.month_start_day = 1 then (b.month + interval '1 month' - interval '1 day')::date
                   else (b.month + (h.month_start_day - 2) * interval '1 day')::date end
from public.households h
where h.id = b.household_id;

alter table public.budgets alter column ends_on set not null;
alter table public.budgets add constraint budgets_period_check check (ends_on >= month);

-- Quien guarde sin fecha de fin (versiones antiguas o inserciones directas): el mes natural.
create function private.default_budget_ends_on() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.ends_on is null then
    new.ends_on := (date_trunc('month', new.month) + interval '1 month' - interval '1 day')::date;
  end if;
  return new;
end;
$$;

revoke all on function private.default_budget_ends_on() from public, anon, authenticated;

create trigger budgets_default_ends_on before insert or update on public.budgets
  for each row execute function private.default_budget_ends_on();

grant insert (ends_on, carry_over, warn_pct), update (ends_on, carry_over, warn_pct) on public.budgets to authenticated;

-- Guardar un presupuesto de un periodo, con sus límites, en una transacción.
create function public.save_period_budget(
  target_household uuid,
  starts_on date,
  ends_on date,
  expected_income bigint,
  needs smallint,
  wants smallint,
  savings smallint,
  carry boolean default false,
  warn smallint default 80,
  lines jsonb default '[]'::jsonb
)
returns public.budgets
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved public.budgets;
begin
  insert into public.budgets (household_id, month, ends_on, expected_income_minor, needs_pct, wants_pct,
                              savings_pct, carry_over, warn_pct)
  values (target_household, starts_on, ends_on, expected_income, needs, wants, savings, carry, warn)
  on conflict (household_id, created_by, month) do update
    set ends_on = excluded.ends_on,
        expected_income_minor = excluded.expected_income_minor,
        needs_pct = excluded.needs_pct,
        wants_pct = excluded.wants_pct,
        savings_pct = excluded.savings_pct,
        carry_over = excluded.carry_over,
        warn_pct = excluded.warn_pct
  returning * into saved;

  delete from public.budget_lines where budget_id = saved.id;

  insert into public.budget_lines (household_id, budget_id, category_id, limit_minor)
  select saved.household_id, saved.id, (line ->> 'category_id')::uuid, (line ->> 'limit_minor')::bigint
  from jsonb_array_elements(coalesce(lines, '[]'::jsonb)) as line;

  return saved;
end;
$$;

revoke all on function public.save_period_budget(uuid, date, date, bigint, smallint, smallint, smallint, boolean, smallint, jsonb)
  from public, anon;
grant execute on function public.save_period_budget(uuid, date, date, bigint, smallint, smallint, smallint, boolean, smallint, jsonb)
  to authenticated;

-- La versión por meses sigue para las apps sin actualizar: guarda el mes natural.
create or replace function public.save_budget(
  target_household uuid,
  target_month date,
  expected_income bigint,
  needs smallint,
  wants smallint,
  savings smallint,
  lines jsonb default '[]'::jsonb
)
returns public.budgets
language sql
security invoker
set search_path = ''
as $$
  select * from public.save_period_budget(
    target_household, date_trunc('month', target_month)::date,
    (date_trunc('month', target_month) + interval '1 month' - interval '1 day')::date,
    expected_income, needs, wants, savings, false, 80::smallint, lines);
$$;

-- 3. Presupuestos extra --------------------------------------------------------------------

create table public.extra_budgets (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  name text not null check (length(trim(name)) between 1 and 60),
  limit_minor bigint not null check (limit_minor > 0),
  starts_on date not null,
  ends_on date,
  -- Vacías = todas las categorías de gasto / todas las cuentas.
  category_ids uuid[] not null default '{}' check (cardinality(category_ids) <= 50),
  account_ids uuid[] not null default '{}' check (cardinality(account_ids) <= 50),
  is_favorite boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_on is null or ends_on >= starts_on)
);

create index extra_budgets_household_id_idx on public.extra_budgets (household_id);
create index extra_budgets_created_by_idx on public.extra_budgets (created_by);
-- Un favorito por persona.
create unique index extra_budgets_one_favorite on public.extra_budgets (created_by) where is_favorite;

create trigger extra_budgets_touch before update on public.extra_budgets
  for each row execute function private.touch_updated_at();

alter table public.extra_budgets enable row level security;
revoke all on public.extra_budgets from anon, authenticated;
grant select,
  insert (id, household_id, name, limit_minor, starts_on, ends_on, category_ids, account_ids, is_favorite),
  update (name, limit_minor, starts_on, ends_on, category_ids, account_ids, is_favorite),
  delete
  on public.extra_budgets to authenticated;

create policy extra_budgets_select on public.extra_budgets for select to authenticated
  using ((select private.is_mine(household_id, created_by)));
create policy extra_budgets_insert on public.extra_budgets for insert to authenticated
  with check ((select private.is_member(household_id)) and created_by = (select auth.uid()));
create policy extra_budgets_update on public.extra_budgets for update to authenticated
  using ((select private.is_mine(household_id, created_by)))
  with check ((select private.is_mine(household_id, created_by)));
create policy extra_budgets_delete on public.extra_budgets for delete to authenticated
  using ((select private.is_mine(household_id, created_by)));

-- Al marcar uno como favorito, se desmarca el anterior de la misma persona.
create function private.single_favorite_extra_budget()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.is_favorite then
    update public.extra_budgets set is_favorite = false
    where created_by = new.created_by and id <> new.id and is_favorite;
  end if;
  return new;
end;
$$;

create trigger extra_budgets_single_favorite
  before insert or update of is_favorite on public.extra_budgets
  for each row when (new.is_favorite) execute function private.single_favorite_extra_budget();

-- Empezar de cero también borra los presupuestos extra de quien lo pide.

create or replace function public.reset_household(target_household uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if target_household is null or not (select private.is_member(target_household)) then
    raise exception 'no eres miembro de ese hogar' using errcode = '42501';
  end if;

  -- El RLS limita cada borrado a lo tuyo.
  delete from public.holdings where household_id = target_household;         -- y sus precios, operaciones y planes
  delete from public.goals where household_id = target_household;            -- y sus aportaciones
  delete from public.recurring_series where household_id = target_household;
  delete from public.extra_budgets where household_id = target_household;
  delete from public.budgets where household_id = target_household;          -- y sus líneas
  delete from public.transactions where household_id = target_household;
  delete from public.accounts where household_id = target_household;         -- y sus tarjetas y plazos
  delete from public.categories where household_id = target_household;

  insert into public.categories (household_id, name, kind, budget_group, icon)
  select target_household, d.name, d.kind, d.budget_group, d.icon from private.default_categories() d;
end;
$$;
