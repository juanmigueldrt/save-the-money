-- ORC-71: la moneda del hogar no se cambia con importes guardados.
--
-- El dueño podía cambiar households.base_currency en cualquier momento. Los importes se
-- guardan en unidades menores sin moneda propia (céntimos de la moneda del hogar), así que
-- cambiarla convertía 100,00 € en 100,00 $ sin tocar ni una cifra. Aquí no se convierte ni se
-- reescribe ningún importe: el cambio se rechaza mientras el hogar tenga algo apuntado. Un
-- hogar vacío (recién creado, o después de reset_household) sí puede cambiarla.
--
-- Qué cuenta como «importes guardados»: una cuenta, un presupuesto, un presupuesto extra, un
-- pago fijo, una meta o un activo. Todo lo demás con importe cuelga de uno de ellos
-- (movimientos y tarjetas de una cuenta, líneas de un presupuesto, cargos de un pago fijo,
-- aportaciones de una meta, operaciones, precios y planes de un activo).
--
-- Las apps reciben STM06 y enseñan su aviso en español. Decisión completa en
-- docs/decisiones/varias-monedas.md.

-- SECURITY DEFINER a propósito: desde la migración de privacidad cada persona solo ve lo que
-- creó, así que el dueño no ve las cuentas de los demás miembros y con sus permisos el hogar
-- parecería vacío. La función no devuelve datos: solo deja pasar o falla. Vive en `private` y
-- nadie puede llamarla directamente.
create function private.keep_base_currency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- No cierra la carrera con un alta simultánea aún sin confirmar (no la ve); esa cuenta
  -- quedaría en la moneda con la que se creó, que es la suya (accounts.currency).
  if exists (select 1 from public.accounts a where a.household_id = new.id)
    or exists (select 1 from public.budgets b where b.household_id = new.id)
    or exists (select 1 from public.extra_budgets e where e.household_id = new.id)
    or exists (select 1 from public.recurring_series r where r.household_id = new.id)
    or exists (select 1 from public.goals g where g.household_id = new.id)
    or exists (select 1 from public.holdings h where h.household_id = new.id)
  then
    raise exception 'La moneda del hogar no se puede cambiar con importes guardados' using errcode = 'STM06';
  end if;
  return new;
end;
$$;

revoke all on function private.keep_base_currency() from public, anon, authenticated;

-- Solo cuando la moneda cambia de verdad: guardar la misma, o cambiar el nombre, no falla.
create trigger households_keep_base_currency
  before update of base_currency on public.households
  for each row when (new.base_currency is distinct from old.base_currency)
  execute function private.keep_base_currency();
