-- Fase 7: inversiones.
--
-- Activos (fondos, ETF, acciones...), las compras y ventas de cada uno y los planes de
-- inversión periódica. Los precios se apuntan a mano (lo decidió Jean el 2026-11-03):
-- no hay ningún servicio de cotizaciones ni claves de terceros.
-- Como las cuentas, todo se ve dentro del hogar y sólo lo tocan sus miembros (RLS);
-- owner_id dice de quién es un activo, igual que en accounts.

-- Tipos ---------------------------------------------------------------------

create type public.investment_kind as enum ('fund', 'etf', 'stock', 'bond', 'crypto', 'pension', 'other');
create type public.trade_side as enum ('buy', 'sell');

-- Activos ---------------------------------------------------------------------

create table public.holdings (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 60),
  -- Ticker o ISIN, opcional y sólo para reconocerlo.
  symbol text check (char_length(trim(symbol)) between 1 and 20),
  kind public.investment_kind not null default 'fund',
  currency char(3) not null default 'EUR' check (currency ~ '^[A-Z]{3}$'),
  -- Cuenta del bróker o del banco donde está, si se quiere enlazar.
  account_id uuid,
  -- null = compartido; si no, de qué miembro es.
  owner_id uuid references public.profiles (id) on delete set null,
  -- Último precio por participación, apuntado a mano, en unidades de la moneda.
  price numeric(18, 6) not null default 0 check (price >= 0),
  price_on date,
  note text check (char_length(note) <= 200),
  archived_at timestamptz,
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (account_id, household_id) references public.accounts (id, household_id) on delete set null (account_id),
  unique (id, household_id)
);

create index holdings_household_id_idx on public.holdings (household_id);
create index holdings_account_id_idx on public.holdings (account_id);
create index holdings_owner_id_idx on public.holdings (owner_id);

-- Compras y ventas --------------------------------------------------------------

create table public.investment_trades (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  holding_id uuid not null,
  traded_on date not null,
  side public.trade_side not null default 'buy',
  -- Participaciones: admite fracciones (fondos, cripto).
  quantity numeric(20, 8) not null check (quantity > 0),
  -- Precio por participación en la operación, en unidades de la moneda.
  price numeric(18, 6) not null check (price >= 0),
  fee_minor bigint not null default 0 check (fee_minor >= 0),
  note text check (char_length(note) <= 200),
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (holding_id, household_id) references public.holdings (id, household_id) on delete cascade
);

create index investment_trades_holding_traded_idx on public.investment_trades (holding_id, traded_on desc);
create index investment_trades_household_id_idx on public.investment_trades (household_id);

-- Planes de inversión periódica ---------------------------------------------------

create table public.investment_plans (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  holding_id uuid not null,
  -- Lo que se invierte cada vez, en céntimos.
  amount_minor bigint not null check (amount_minor > 0),
  every smallint not null default 1 check (every between 1 and 52),
  unit public.recurrence_unit not null default 'month',
  starts_on date not null,
  ends_on date,
  -- Rentabilidad anual supuesta para la proyección, en %.
  expected_annual_return numeric(5, 2) not null default 5 check (expected_annual_return between -50 and 50),
  remind_days_before smallint default 1 check (remind_days_before between 0 and 14),
  archived_at timestamptz,
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_on is null or ends_on >= starts_on),
  foreign key (holding_id, household_id) references public.holdings (id, household_id) on delete cascade
);

create index investment_plans_holding_id_idx on public.investment_plans (holding_id);
create index investment_plans_household_id_idx on public.investment_plans (household_id);

create trigger holdings_touch before update on public.holdings
  for each row execute function private.touch_updated_at();
create trigger investment_trades_touch before update on public.investment_trades
  for each row execute function private.touch_updated_at();
create trigger investment_plans_touch before update on public.investment_plans
  for each row execute function private.touch_updated_at();

-- RLS ---------------------------------------------------------------------------

alter table public.holdings enable row level security;
alter table public.investment_trades enable row level security;
alter table public.investment_plans enable row level security;

revoke all on public.holdings, public.investment_trades, public.investment_plans from anon, authenticated;

-- household_id, holding_id y created_by no se pueden cambiar después de crear la fila.
grant select,
  insert (household_id, name, symbol, kind, currency, account_id, owner_id, price, price_on, note, archived_at),
  update (name, symbol, kind, account_id, owner_id, price, price_on, note, archived_at),
  delete
  on public.holdings to authenticated;
grant select,
  insert (household_id, holding_id, traded_on, side, quantity, price, fee_minor, note),
  update (traded_on, side, quantity, price, fee_minor, note),
  delete
  on public.investment_trades to authenticated;
grant select,
  insert (household_id, holding_id, amount_minor, every, unit, starts_on, ends_on, expected_annual_return,
          remind_days_before, archived_at),
  update (amount_minor, every, unit, starts_on, ends_on, expected_annual_return, remind_days_before, archived_at),
  delete
  on public.investment_plans to authenticated;

create policy holdings_select on public.holdings
  for select to authenticated
  using ((select private.is_member(household_id)));
create policy holdings_insert on public.holdings
  for insert to authenticated
  with check (
    (select private.is_member(household_id))
    and (owner_id is null or owner_id in (
      select m.user_id from public.household_members m where m.household_id = holdings.household_id
    ))
  );
create policy holdings_update on public.holdings
  for update to authenticated
  using ((select private.is_member(household_id)))
  with check (
    (select private.is_member(household_id))
    and (owner_id is null or owner_id in (
      select m.user_id from public.household_members m where m.household_id = holdings.household_id
    ))
  );
create policy holdings_delete on public.holdings
  for delete to authenticated
  using ((select private.is_member(household_id)));

create policy investment_trades_select on public.investment_trades
  for select to authenticated
  using ((select private.is_member(household_id)));
create policy investment_trades_insert on public.investment_trades
  for insert to authenticated
  with check ((select private.is_member(household_id)));
create policy investment_trades_update on public.investment_trades
  for update to authenticated
  using ((select private.is_member(household_id)))
  with check ((select private.is_member(household_id)));
create policy investment_trades_delete on public.investment_trades
  for delete to authenticated
  using ((select private.is_member(household_id)));

create policy investment_plans_select on public.investment_plans
  for select to authenticated
  using ((select private.is_member(household_id)));
create policy investment_plans_insert on public.investment_plans
  for insert to authenticated
  with check ((select private.is_member(household_id)));
create policy investment_plans_update on public.investment_plans
  for update to authenticated
  using ((select private.is_member(household_id)))
  with check ((select private.is_member(household_id)));
create policy investment_plans_delete on public.investment_plans
  for delete to authenticated
  using ((select private.is_member(household_id)));

-- "Borrar datos y empezar de cero" también borra las inversiones ---------------------

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

  delete from public.holdings where household_id = target_household;         -- y sus operaciones y planes
  delete from public.goals where household_id = target_household;            -- y sus aportaciones
  delete from public.recurring_series where household_id = target_household;
  delete from public.budgets where household_id = target_household;          -- y sus líneas
  delete from public.transactions where household_id = target_household;
  delete from public.accounts where household_id = target_household;
  delete from public.categories where household_id = target_household;

  insert into public.categories (household_id, name, kind, budget_group, icon)
  select target_household, c.name, c.kind::public.category_kind, c.budget_group::public.budget_group, c.icon
  from (values
    ('Nómina', 'income', null, 'banknote'),
    ('Otros ingresos', 'income', null, 'plus.circle'),
    ('Vivienda', 'expense', 'needs', 'house'),
    ('Supermercado', 'expense', 'needs', 'cart'),
    ('Suministros', 'expense', 'needs', 'bolt'),
    ('Transporte', 'expense', 'needs', 'car'),
    ('Salud', 'expense', 'needs', 'cross.case'),
    ('Seguros', 'expense', 'needs', 'shield'),
    ('Restaurantes', 'expense', 'wants', 'fork.knife'),
    ('Ocio', 'expense', 'wants', 'ticket'),
    ('Compras', 'expense', 'wants', 'bag'),
    ('Viajes', 'expense', 'wants', 'airplane'),
    ('Suscripciones', 'expense', 'wants', 'repeat'),
    ('Ahorro', 'expense', 'savings', 'banknote'),
    ('Inversión', 'expense', 'savings', 'chart.line.uptrend.xyaxis'),
    ('Deudas', 'expense', 'savings', 'creditcard'),
    ('Transferencia entre cuentas', 'transfer', null, 'arrow.left.arrow.right')
  ) as c (name, kind, budget_group, icon);
end;
$$;

