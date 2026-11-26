-- ORC-63, consulta 2 de 2: cuentas cuyo saldo no cuenta todos sus movimientos.
--
-- Solo lee (una sentencia select). Se ejecuta con el rol postgres, que no pasa por el RLS.
-- No devuelve nombres ni conceptos. La única cifra de dinero es diferencia_minor, en céntimos.
-- Sin filas en el resultado = todos los saldos cuentan todos sus movimientos.
-- Cómo leerlo: README.md de esta carpeta.
--
-- Una cuenta solo la ve quien la creó, y su saldo (vista account_balances) solo suma los
-- movimientos que ve esa persona: los suyos. Los que apuntó otro miembro en esa cuenta no
-- entran en el saldo. Aquí sale cada cuenta con movimientos así:
--   movimientos_total      todos los movimientos de la cuenta
--   movimientos_visibles   los que cuenta hoy el saldo que ve quien creó la cuenta
--   movimientos_ocultos    los que no cuenta
--   otros_creadores        cuántas personas distintas apuntaron los ocultos (sin contar los sin creador)
--   diferencia_minor       saldo con todos los movimientos menos saldo que se ve hoy, en céntimos
select
  a.household_id,
  a.id as account_id,
  count(*) as movimientos_total,
  count(*) filter (where v.visible) as movimientos_visibles,
  count(*) filter (where not v.visible) as movimientos_ocultos,
  count(distinct t.created_by) filter (where not v.visible) as otros_creadores,
  coalesce(sum(t.amount_minor) filter (where not v.visible), 0)::bigint as diferencia_minor
from public.accounts a
join public.transactions t on t.account_id = a.id
cross join lateral (
  -- Misma regla que private.is_mine: mismo creador y que siga siendo miembro del hogar.
  select coalesce(t.created_by = a.created_by, false)
     and exists (select 1 from public.household_members m
                 where m.household_id = a.household_id and m.user_id = a.created_by) as visible
) v
group by a.household_id, a.id
having count(*) filter (where not v.visible) > 0
order by a.household_id, a.id;
