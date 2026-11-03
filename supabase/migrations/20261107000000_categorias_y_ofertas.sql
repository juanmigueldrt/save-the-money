-- Categorías de impuestos, multas y tasas, y precios de oferta en los pagos fijos.
--
-- 1. Tres categorías nuevas de serie, en Necesidades (lo pidió Jean el 2026-11-03):
--    Impuestos, Multas y sanciones, y Tasas y trámites. La lista de serie vive ahora en
--    una sola función, que usan tanto los hogares nuevos como "empezar de cero", y se
--    añaden también a los hogares que ya existen.
-- 2. Un pago fijo puede empezar con precio de oferta durante unos cargos
--    (p. ej. 3 meses a 6,99 € y luego 11,99 €).

-- Categorías de serie -------------------------------------------------------------

create function private.default_categories()
returns table (name text, kind public.category_kind, budget_group public.budget_group, icon text)
language sql
immutable
set search_path = ''
as $$
  select c.name, c.kind::public.category_kind, c.budget_group::public.budget_group, c.icon
  from (values
    (1, 'Nómina', 'income', null, 'banknote'),
    (2, 'Otros ingresos', 'income', null, 'plus.circle'),
    (3, 'Vivienda', 'expense', 'needs', 'house'),
    (4, 'Supermercado', 'expense', 'needs', 'cart'),
    (5, 'Suministros', 'expense', 'needs', 'bolt'),
    (6, 'Transporte', 'expense', 'needs', 'car'),
    (7, 'Salud', 'expense', 'needs', 'cross.case'),
    (8, 'Seguros', 'expense', 'needs', 'shield'),
    (9, 'Impuestos', 'expense', 'needs', 'building.columns'),
    (10, 'Multas y sanciones', 'expense', 'needs', 'exclamationmark.triangle'),
    (11, 'Tasas y trámites', 'expense', 'needs', 'doc.text'),
    (12, 'Restaurantes', 'expense', 'wants', 'fork.knife'),
    (13, 'Ocio', 'expense', 'wants', 'ticket'),
    (14, 'Compras', 'expense', 'wants', 'bag'),
    (15, 'Viajes', 'expense', 'wants', 'airplane'),
    (16, 'Suscripciones', 'expense', 'wants', 'repeat'),
    (17, 'Ahorro', 'expense', 'savings', 'banknote'),
    (18, 'Inversión', 'expense', 'savings', 'chart.line.uptrend.xyaxis'),
    (19, 'Deudas', 'expense', 'savings', 'creditcard'),
    (20, 'Transferencia entre cuentas', 'transfer', null, 'arrow.left.arrow.right')
  ) as c (position, name, kind, budget_group, icon)
  order by c.position;
$$;

revoke all on function private.default_categories() from public, anon;
-- reset_household es security invoker: quien la llama necesita leer la lista.
grant execute on function private.default_categories() to authenticated;

create or replace function private.seed_default_categories()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.categories (household_id, name, kind, budget_group, icon)
  select new.id, d.name, d.kind, d.budget_group, d.icon from private.default_categories() d;
  return new;
end;
$$;

revoke all on function private.seed_default_categories() from public, anon, authenticated;

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

  delete from public.holdings where household_id = target_household;         -- y sus precios, operaciones y planes
  delete from public.goals where household_id = target_household;            -- y sus aportaciones
  delete from public.recurring_series where household_id = target_household;
  delete from public.budgets where household_id = target_household;          -- y sus líneas
  delete from public.transactions where household_id = target_household;
  delete from public.accounts where household_id = target_household;
  delete from public.categories where household_id = target_household;

  insert into public.categories (household_id, name, kind, budget_group, icon)
  select target_household, d.name, d.kind, d.budget_group, d.icon from private.default_categories() d;
end;
$$;

-- Las tres nuevas también en los hogares que ya existen, salvo que ya tengan una con ese nombre.
insert into public.categories (household_id, name, kind, budget_group, icon)
select h.id, d.name, d.kind, d.budget_group, d.icon
from public.households h
cross join private.default_categories() d
where d.name in ('Impuestos', 'Multas y sanciones', 'Tasas y trámites')
on conflict do nothing;

-- Precios de oferta ------------------------------------------------------------------

alter table public.recurring_series
  add column intro_amount_minor bigint check (intro_amount_minor > 0),
  add column intro_charges smallint check (intro_charges between 1 and 36),
  add constraint recurring_series_intro_both
    check ((intro_amount_minor is null) = (intro_charges is null));

comment on column public.recurring_series.intro_amount_minor is
  'Precio de oferta de los primeros cargos, en céntimos; después se cobra amount_minor.';
comment on column public.recurring_series.intro_charges is
  'Cuántos cargos, desde el primero, van al precio de oferta.';

grant insert (intro_amount_minor, intro_charges), update (intro_amount_minor, intro_charges)
  on public.recurring_series to authenticated;
