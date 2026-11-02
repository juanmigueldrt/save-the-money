-- Fase 5: "Borrar datos y empezar de cero".
-- Borra todo lo que el hogar ha apuntado (cuentas, movimientos, categorías, presupuestos,
-- pagos fijos y metas) y le vuelve a dar las categorías de partida. El hogar, sus miembros
-- y sus invitaciones se quedan como están.
-- security invoker: cada borrado pasa por el RLS de quien llama, así que nadie puede
-- vaciar un hogar del que no es miembro aunque se salte la comprobación de abajo.

create function public.reset_household(target_household uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if target_household is null or not (select private.is_member(target_household)) then
    raise exception 'no eres miembro de ese hogar' using errcode = '42501';
  end if;

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

revoke all on function public.reset_household(uuid) from public, anon;
grant execute on function public.reset_household(uuid) to authenticated;
