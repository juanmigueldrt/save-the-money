-- Privacidad dentro del hogar: cada miembro ve y toca solo lo que ha creado.
--
-- Hasta ahora cualquier miembro del hogar veía y podía cambiar todo (cuentas, movimientos,
-- tarjetas, inversiones, pagos fijos, metas y presupuestos). Ahora cada fila es de quien la
-- creó (created_by, que se rellena con auth.uid() y no se puede cambiar), también las
-- categorías y el presupuesto de cada mes. Compartir algo concreto con el otro miembro llega en otra
-- migración (enlaces para compartir).
--
-- Las tablas hijas (líneas de presupuesto, aportaciones, precios, operaciones, plazos)
-- siguen a su padre: solo se ven si se ve el padre. Al crear una fila que apunta a una
-- cuenta, tarjeta, meta, activo o presupuesto, ese padre tiene que ser tuyo.

create function private.is_mine(target_household uuid, creator uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select creator is not null
     and creator = (select auth.uid())
     and (select private.is_member(target_household));
$$;

revoke all on function private.is_mine(uuid, uuid) from public, anon;
grant execute on function private.is_mine(uuid, uuid) to authenticated;

-- Tablas con dueño propio --------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array[
    'accounts', 'transactions', 'budgets', 'recurring_series', 'goals', 'goal_contributions',
    'holdings', 'holding_prices', 'investment_trades', 'investment_plans',
    'credit_cards', 'card_installments'
  ] loop
    execute format('drop policy %I on public.%I', t || '_select', t);
    execute format('drop policy %I on public.%I', t || '_update', t);
    execute format('drop policy %I on public.%I', t || '_delete', t);
    execute format('drop policy %I on public.%I', t || '_insert', t);

    execute format($p$create policy %I on public.%I for select to authenticated
      using ((select private.is_mine(household_id, created_by)))$p$, t || '_select', t);
    execute format($p$create policy %I on public.%I for delete to authenticated
      using ((select private.is_mine(household_id, created_by)))$p$, t || '_delete', t);
  end loop;
end;
$$;

-- Altas y cambios: la fila es tuya y lo que enlaza también.

create policy accounts_insert on public.accounts for insert to authenticated
  with check ((select private.is_member(household_id))
    and (owner_id is null or owner_id in (
      select m.user_id from public.household_members m where m.household_id = accounts.household_id)));
create policy accounts_update on public.accounts for update to authenticated
  using ((select private.is_mine(household_id, created_by)))
  with check ((select private.is_mine(household_id, created_by))
    and (owner_id is null or owner_id in (
      select m.user_id from public.household_members m where m.household_id = accounts.household_id)));

create policy transactions_insert on public.transactions for insert to authenticated
  with check ((select private.is_member(household_id))
    and exists (select 1 from public.accounts a where a.id = account_id)
    and (category_id is null or exists (select 1 from public.categories c where c.id = category_id)));
create policy transactions_update on public.transactions for update to authenticated
  using ((select private.is_mine(household_id, created_by)))
  with check ((select private.is_mine(household_id, created_by))
    and exists (select 1 from public.accounts a where a.id = account_id)
    and (category_id is null or exists (select 1 from public.categories c where c.id = category_id)));

create policy budgets_insert on public.budgets for insert to authenticated
  with check ((select private.is_member(household_id)));
create policy budgets_update on public.budgets for update to authenticated
  using ((select private.is_mine(household_id, created_by)))
  with check ((select private.is_mine(household_id, created_by)));

create policy recurring_series_insert on public.recurring_series for insert to authenticated
  with check ((select private.is_member(household_id))
    and (account_id is null or exists (select 1 from public.accounts a where a.id = account_id))
    and (category_id is null or exists (select 1 from public.categories c where c.id = category_id)));
create policy recurring_series_update on public.recurring_series for update to authenticated
  using ((select private.is_mine(household_id, created_by)))
  with check ((select private.is_mine(household_id, created_by))
    and (account_id is null or exists (select 1 from public.accounts a where a.id = account_id))
    and (category_id is null or exists (select 1 from public.categories c where c.id = category_id)));

create policy goals_insert on public.goals for insert to authenticated
  with check ((select private.is_member(household_id))
    and (account_id is null or exists (select 1 from public.accounts a where a.id = account_id)));
create policy goals_update on public.goals for update to authenticated
  using ((select private.is_mine(household_id, created_by)))
  with check ((select private.is_mine(household_id, created_by))
    and (account_id is null or exists (select 1 from public.accounts a where a.id = account_id)));

create policy goal_contributions_insert on public.goal_contributions for insert to authenticated
  with check ((select private.is_member(household_id))
    and exists (select 1 from public.goals g where g.id = goal_id));
create policy goal_contributions_update on public.goal_contributions for update to authenticated
  using ((select private.is_mine(household_id, created_by)))
  with check ((select private.is_mine(household_id, created_by)));

create policy holdings_insert on public.holdings for insert to authenticated
  with check ((select private.is_member(household_id))
    and (account_id is null or exists (select 1 from public.accounts a where a.id = account_id))
    and (owner_id is null or owner_id in (
      select m.user_id from public.household_members m where m.household_id = holdings.household_id)));
create policy holdings_update on public.holdings for update to authenticated
  using ((select private.is_mine(household_id, created_by)))
  with check ((select private.is_mine(household_id, created_by))
    and (account_id is null or exists (select 1 from public.accounts a where a.id = account_id))
    and (owner_id is null or owner_id in (
      select m.user_id from public.household_members m where m.household_id = holdings.household_id)));

create policy holding_prices_insert on public.holding_prices for insert to authenticated
  with check ((select private.is_member(household_id))
    and exists (select 1 from public.holdings h where h.id = holding_id));
create policy holding_prices_update on public.holding_prices for update to authenticated
  using ((select private.is_mine(household_id, created_by)))
  with check ((select private.is_mine(household_id, created_by)));

create policy investment_trades_insert on public.investment_trades for insert to authenticated
  with check ((select private.is_member(household_id))
    and exists (select 1 from public.holdings h where h.id = holding_id));
create policy investment_trades_update on public.investment_trades for update to authenticated
  using ((select private.is_mine(household_id, created_by)))
  with check ((select private.is_mine(household_id, created_by)));

create policy investment_plans_insert on public.investment_plans for insert to authenticated
  with check ((select private.is_member(household_id))
    and exists (select 1 from public.holdings h where h.id = holding_id)
    and (account_id is null or exists (select 1 from public.accounts a where a.id = account_id)));
create policy investment_plans_update on public.investment_plans for update to authenticated
  using ((select private.is_mine(household_id, created_by)))
  with check ((select private.is_mine(household_id, created_by))
    and (account_id is null or exists (select 1 from public.accounts a where a.id = account_id)));

create policy credit_cards_insert on public.credit_cards for insert to authenticated
  with check ((select private.is_member(household_id))
    and exists (select 1 from public.accounts a where a.id = account_id)
    and (pay_from_account_id is null or exists (select 1 from public.accounts a where a.id = pay_from_account_id)));
create policy credit_cards_update on public.credit_cards for update to authenticated
  using ((select private.is_mine(household_id, created_by)))
  with check ((select private.is_mine(household_id, created_by))
    and (pay_from_account_id is null or exists (select 1 from public.accounts a where a.id = pay_from_account_id)));

create policy card_installments_insert on public.card_installments for insert to authenticated
  with check ((select private.is_member(household_id))
    and exists (select 1 from public.credit_cards c where c.account_id = card_installments.account_id)
    and exists (select 1 from public.transactions m where m.id = transaction_id));
create policy card_installments_update on public.card_installments for update to authenticated
  using ((select private.is_mine(household_id, created_by)))
  with check ((select private.is_mine(household_id, created_by)));

-- Líneas de presupuesto: no tienen created_by, siguen a su presupuesto.

drop policy budget_lines_select on public.budget_lines;
drop policy budget_lines_insert on public.budget_lines;
drop policy budget_lines_update on public.budget_lines;
drop policy budget_lines_delete on public.budget_lines;

create policy budget_lines_select on public.budget_lines for select to authenticated
  using (exists (select 1 from public.budgets b where b.id = budget_id));
create policy budget_lines_insert on public.budget_lines for insert to authenticated
  with check ((select private.is_member(household_id))
    and exists (select 1 from public.budgets b where b.id = budget_id)
    and exists (select 1 from public.categories c where c.id = category_id));
create policy budget_lines_update on public.budget_lines for update to authenticated
  using (exists (select 1 from public.budgets b where b.id = budget_id))
  with check (exists (select 1 from public.budgets b where b.id = budget_id));
create policy budget_lines_delete on public.budget_lines for delete to authenticated
  using (exists (select 1 from public.budgets b where b.id = budget_id));

-- Presupuestos: uno por persona y mes (antes, uno por hogar y mes) -----------------------

alter table public.budgets drop constraint budgets_household_id_month_key;
alter table public.budgets add constraint budgets_household_creator_month_key
  unique (household_id, created_by, month);

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
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved public.budgets;
begin
  insert into public.budgets (household_id, month, expected_income_minor, needs_pct, wants_pct, savings_pct)
  values (target_household, date_trunc('month', target_month)::date, expected_income, needs, wants, savings)
  on conflict (household_id, created_by, month) do update
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

-- Categorías: también de cada persona ---------------------------------------------------

alter table public.categories
  add column created_by uuid references auth.users (id) on delete set null default auth.uid();

-- Las que ya hay son de quien creó el hogar; el resto de miembros recibe las de partida.
update public.categories c set created_by = h.created_by
from public.households h where h.id = c.household_id;

drop index public.categories_household_name_idx;
create unique index categories_household_name_idx
  on public.categories (household_id, created_by, kind, lower(name));
create index categories_created_by_idx on public.categories (created_by);

insert into public.categories (household_id, created_by, name, kind, budget_group, icon)
select m.household_id, m.user_id, d.name, d.kind, d.budget_group, d.icon
from public.household_members m
join public.households h on h.id = m.household_id
cross join private.default_categories() d
where m.user_id is distinct from h.created_by
on conflict do nothing;

-- Cada miembro nuevo (también quien crea el hogar) recibe sus categorías de partida.
drop trigger households_seed_categories on public.households;

create or replace function private.seed_default_categories()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.categories (household_id, created_by, name, kind, budget_group, icon)
  select new.household_id, new.user_id, d.name, d.kind, d.budget_group, d.icon
  from private.default_categories() d
  on conflict do nothing;
  return new;
end;
$$;

revoke all on function private.seed_default_categories() from public, anon, authenticated;

create trigger household_members_seed_categories
  after insert on public.household_members
  for each row execute function private.seed_default_categories();

drop policy categories_select on public.categories;
drop policy categories_insert on public.categories;
drop policy categories_update on public.categories;
drop policy categories_delete on public.categories;

create policy categories_select on public.categories for select to authenticated
  using ((select private.is_mine(household_id, created_by)));
create policy categories_insert on public.categories for insert to authenticated
  with check ((select private.is_member(household_id)));
create policy categories_update on public.categories for update to authenticated
  using ((select private.is_mine(household_id, created_by)))
  with check ((select private.is_mine(household_id, created_by)));
create policy categories_delete on public.categories for delete to authenticated
  using ((select private.is_mine(household_id, created_by)));

-- Empezar de cero también repone tus categorías.
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
  delete from public.budgets where household_id = target_household;          -- y sus líneas
  delete from public.transactions where household_id = target_household;
  delete from public.accounts where household_id = target_household;         -- y sus tarjetas y plazos
  delete from public.categories where household_id = target_household;

  insert into public.categories (household_id, name, kind, budget_group, icon)
  select target_household, d.name, d.kind, d.budget_group, d.icon from private.default_categories() d;
end;
$$;
