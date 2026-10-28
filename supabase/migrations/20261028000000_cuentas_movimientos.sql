-- Fase 2: cuentas, categorías y movimientos.
--
-- Todo cuelga de un hogar y sólo lo ven y lo tocan sus miembros (RLS).
-- Las claves foráneas compuestas (id, household_id) impiden que un movimiento
-- apunte a una cuenta o categoría de otro hogar aunque alguien lo intente.

-- Tipos ---------------------------------------------------------------------

create type public.account_kind as enum ('checking', 'savings', 'credit_card', 'cash', 'investment', 'loan', 'other');
create type public.category_kind as enum ('income', 'expense', 'transfer');
create type public.budget_group as enum ('needs', 'wants', 'savings');

-- Tablas --------------------------------------------------------------------

create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 60),
  kind public.account_kind not null default 'checking',
  currency char(3) not null default 'EUR' check (currency ~ '^[A-Z]{3}$'),
  opening_balance_minor bigint not null default 0,
  -- null = cuenta compartida; si no, de qué miembro es.
  owner_id uuid references public.profiles (id) on delete set null,
  archived_at timestamptz,
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, household_id)
);

create index accounts_household_id_idx on public.accounts (household_id);
create index accounts_owner_id_idx on public.accounts (owner_id);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 40),
  kind public.category_kind not null default 'expense',
  -- Grupo de la plantilla 50/30/20; sólo para gastos.
  budget_group public.budget_group,
  icon text check (char_length(icon) <= 40),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, household_id),
  check (kind = 'expense' or budget_group is null)
);

create unique index categories_household_name_idx on public.categories (household_id, kind, lower(name));

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  account_id uuid not null,
  category_id uuid,
  booked_on date not null,
  -- Céntimos: negativo es un gasto, positivo un ingreso.
  amount_minor bigint not null check (amount_minor <> 0),
  description text not null check (char_length(trim(description)) between 1 and 200),
  notes text check (char_length(notes) <= 500),
  -- Huella SHA-256 de la fila del CSV para no importar dos veces lo mismo.
  import_hash text check (import_hash ~ '^[0-9a-f]{64}$'),
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (account_id, household_id) references public.accounts (id, household_id) on delete cascade,
  foreign key (category_id, household_id) references public.categories (id, household_id) on delete set null (category_id),
  unique (account_id, import_hash)
);

create index transactions_household_booked_idx on public.transactions (household_id, booked_on desc);
create index transactions_account_booked_idx on public.transactions (account_id, booked_on desc);
create index transactions_category_id_idx on public.transactions (category_id);

create trigger accounts_touch before update on public.accounts
  for each row execute function private.touch_updated_at();
create trigger categories_touch before update on public.categories
  for each row execute function private.touch_updated_at();
create trigger transactions_touch before update on public.transactions
  for each row execute function private.touch_updated_at();

-- Saldo de cada cuenta. security_invoker: respeta el RLS de quien consulta.
create view public.account_balances
with (security_invoker = true)
as
select
  a.id as account_id,
  a.household_id,
  a.opening_balance_minor + coalesce(sum(t.amount_minor), 0)::bigint as balance_minor
from public.accounts a
left join public.transactions t on t.account_id = a.id
group by a.id;

-- Categorías iniciales de cada hogar -----------------------------------------------

create function private.seed_default_categories()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.categories (household_id, name, kind, budget_group, icon)
  values
    (new.id, 'Nómina', 'income', null, 'banknote'),
    (new.id, 'Otros ingresos', 'income', null, 'plus.circle'),
    (new.id, 'Vivienda', 'expense', 'needs', 'house'),
    (new.id, 'Supermercado', 'expense', 'needs', 'cart'),
    (new.id, 'Suministros', 'expense', 'needs', 'bolt'),
    (new.id, 'Transporte', 'expense', 'needs', 'car'),
    (new.id, 'Salud', 'expense', 'needs', 'cross.case'),
    (new.id, 'Seguros', 'expense', 'needs', 'shield'),
    (new.id, 'Restaurantes', 'expense', 'wants', 'fork.knife'),
    (new.id, 'Ocio', 'expense', 'wants', 'ticket'),
    (new.id, 'Compras', 'expense', 'wants', 'bag'),
    (new.id, 'Viajes', 'expense', 'wants', 'airplane'),
    (new.id, 'Suscripciones', 'expense', 'wants', 'repeat'),
    (new.id, 'Ahorro', 'expense', 'savings', 'banknote'),
    (new.id, 'Inversión', 'expense', 'savings', 'chart.line.uptrend.xyaxis'),
    (new.id, 'Deudas', 'expense', 'savings', 'creditcard'),
    (new.id, 'Transferencia entre cuentas', 'transfer', null, 'arrow.left.arrow.right');
  return new;
end;
$$;

revoke all on function private.seed_default_categories() from public, anon, authenticated;

create trigger households_seed_categories
  after insert on public.households
  for each row execute function private.seed_default_categories();

-- Los hogares creados antes de esta migración también reciben las categorías.
insert into public.categories (household_id, name, kind, budget_group, icon)
select h.id, c.name, c.kind::public.category_kind, c.budget_group::public.budget_group, c.icon
from public.households h
cross join (values
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
) as c (name, kind, budget_group, icon)
on conflict do nothing;

-- RLS ---------------------------------------------------------------------------

alter table public.accounts enable row level security;
alter table public.categories enable row level security;
alter table public.transactions enable row level security;

revoke all on public.accounts, public.categories, public.transactions, public.account_balances
  from anon, authenticated;

-- Ni household_id ni created_by se pueden cambiar después de crear la fila.
grant select, insert (household_id, name, kind, currency, opening_balance_minor, owner_id),
  update (name, kind, opening_balance_minor, owner_id, archived_at), delete
  on public.accounts to authenticated;
grant select, insert (household_id, name, kind, budget_group, icon),
  update (name, budget_group, icon), delete
  on public.categories to authenticated;
grant select, insert (household_id, account_id, category_id, booked_on, amount_minor, description, notes, import_hash),
  update (account_id, category_id, booked_on, amount_minor, description, notes), delete
  on public.transactions to authenticated;
grant select on public.account_balances to authenticated;

create policy accounts_select on public.accounts
  for select to authenticated
  using ((select private.is_member(household_id)));
create policy accounts_insert on public.accounts
  for insert to authenticated
  with check (
    (select private.is_member(household_id))
    and (owner_id is null or owner_id in (
      select m.user_id from public.household_members m where m.household_id = accounts.household_id
    ))
  );
create policy accounts_update on public.accounts
  for update to authenticated
  using ((select private.is_member(household_id)))
  with check (
    (select private.is_member(household_id))
    and (owner_id is null or owner_id in (
      select m.user_id from public.household_members m where m.household_id = accounts.household_id
    ))
  );
create policy accounts_delete on public.accounts
  for delete to authenticated
  using ((select private.is_member(household_id)));

create policy categories_select on public.categories
  for select to authenticated
  using ((select private.is_member(household_id)));
create policy categories_insert on public.categories
  for insert to authenticated
  with check ((select private.is_member(household_id)));
create policy categories_update on public.categories
  for update to authenticated
  using ((select private.is_member(household_id)))
  with check ((select private.is_member(household_id)));
create policy categories_delete on public.categories
  for delete to authenticated
  using ((select private.is_member(household_id)));

create policy transactions_select on public.transactions
  for select to authenticated
  using ((select private.is_member(household_id)));
create policy transactions_insert on public.transactions
  for insert to authenticated
  with check ((select private.is_member(household_id)));
create policy transactions_update on public.transactions
  for update to authenticated
  using ((select private.is_member(household_id)))
  with check ((select private.is_member(household_id)));
create policy transactions_delete on public.transactions
  for delete to authenticated
  using ((select private.is_member(household_id)));
