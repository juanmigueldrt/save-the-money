-- Fase 3: presupuesto mensual.
--
-- Un presupuesto por hogar y mes con el reparto 50/30/20 (o el que elija el hogar)
-- y, opcionalmente, un límite por categoría de gasto. Lo gastado no se guarda:
-- se calcula a partir de los movimientos.

create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  -- Primer día del mes al que se refiere (el periodo real lo marca month_start_day del hogar).
  month date not null check (extract(day from month) = 1),
  expected_income_minor bigint not null default 0 check (expected_income_minor >= 0),
  needs_pct smallint not null default 50 check (needs_pct between 0 and 100),
  wants_pct smallint not null default 30 check (wants_pct between 0 and 100),
  savings_pct smallint not null default 20 check (savings_pct between 0 and 100),
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (needs_pct + wants_pct + savings_pct = 100),
  unique (household_id, month),
  unique (id, household_id)
);

create table public.budget_lines (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  budget_id uuid not null,
  category_id uuid not null,
  limit_minor bigint not null check (limit_minor >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (budget_id, household_id) references public.budgets (id, household_id) on delete cascade,
  foreign key (category_id, household_id) references public.categories (id, household_id) on delete cascade,
  unique (budget_id, category_id)
);

create index budget_lines_household_id_idx on public.budget_lines (household_id);
create index budget_lines_category_id_idx on public.budget_lines (category_id);

create trigger budgets_touch before update on public.budgets
  for each row execute function private.touch_updated_at();
create trigger budget_lines_touch before update on public.budget_lines
  for each row execute function private.touch_updated_at();

-- RLS ---------------------------------------------------------------------------

alter table public.budgets enable row level security;
alter table public.budget_lines enable row level security;

revoke all on public.budgets, public.budget_lines from anon, authenticated;

grant select, insert (household_id, month, expected_income_minor, needs_pct, wants_pct, savings_pct),
  update (expected_income_minor, needs_pct, wants_pct, savings_pct), delete
  on public.budgets to authenticated;
grant select, insert (household_id, budget_id, category_id, limit_minor),
  update (limit_minor), delete
  on public.budget_lines to authenticated;

create policy budgets_select on public.budgets
  for select to authenticated
  using ((select private.is_member(household_id)));
create policy budgets_insert on public.budgets
  for insert to authenticated
  with check ((select private.is_member(household_id)));
create policy budgets_update on public.budgets
  for update to authenticated
  using ((select private.is_member(household_id)))
  with check ((select private.is_member(household_id)));
create policy budgets_delete on public.budgets
  for delete to authenticated
  using ((select private.is_member(household_id)));

create policy budget_lines_select on public.budget_lines
  for select to authenticated
  using ((select private.is_member(household_id)));
create policy budget_lines_insert on public.budget_lines
  for insert to authenticated
  with check ((select private.is_member(household_id)));
create policy budget_lines_update on public.budget_lines
  for update to authenticated
  using ((select private.is_member(household_id)))
  with check ((select private.is_member(household_id)));
create policy budget_lines_delete on public.budget_lines
  for delete to authenticated
  using ((select private.is_member(household_id)));

-- Guardar un presupuesto entero de una vez ---------------------------------------
-- security invoker: corre con los permisos y el RLS de quien llama, así que no
-- abre nada que las políticas de arriba no permitan ya.

create function public.save_budget(
  target_household uuid,
  target_month date,
  expected_income bigint,
  needs smallint,
  wants smallint,
  savings smallint,
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
  insert into public.budgets (household_id, month, expected_income_minor, needs_pct, wants_pct, savings_pct)
  values (target_household, date_trunc('month', target_month)::date, expected_income, needs, wants, savings)
  on conflict (household_id, month) do update
    set expected_income_minor = excluded.expected_income_minor,
        needs_pct = excluded.needs_pct,
        wants_pct = excluded.wants_pct,
        savings_pct = excluded.savings_pct
  returning * into saved;

  delete from public.budget_lines where budget_id = saved.id;

  insert into public.budget_lines (household_id, budget_id, category_id, limit_minor)
  select saved.household_id, saved.id, (line ->> 'category_id')::uuid, (line ->> 'limit_minor')::bigint
  from jsonb_array_elements(coalesce(lines, '[]'::jsonb)) as line;

  return saved;
end;
$$;

revoke all on function public.save_budget(uuid, date, bigint, smallint, smallint, smallint, jsonb) from public, anon;
grant execute on function public.save_budget(uuid, date, bigint, smallint, smallint, smallint, jsonb) to authenticated;
