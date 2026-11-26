-- ORC-63, consulta 1 de 2: filas que apuntan a algo de otro miembro del hogar.
--
-- Solo lee (una sentencia select). Se ejecuta con el rol postgres, que no pasa por el RLS.
-- No devuelve nombres, conceptos ni importes: solo cuántas filas hay de cada tipo en cada hogar.
-- Sin filas en el resultado = no hay nada cruzado. Cómo leerlo: README.md de esta carpeta.
--
-- Una fila es de quien la creó (created_by). Desde la migración de privacidad por usuario
-- (20261115000000) cada miembro solo ve lo suyo, así que una fila que enlaza con algo de otro
-- miembro queda a medias: uno ve la fila y el otro ve aquello a lo que apunta.
with enlaces (household_id, tabla, tipo, creador, creador_destino) as (
  select t.household_id, 'transactions', 'cuenta_de_otro', t.created_by, a.created_by
  from public.transactions t join public.accounts a on a.id = t.account_id
  union all
  select t.household_id, 'transactions', 'categoria_de_otro', t.created_by, c.created_by
  from public.transactions t join public.categories c on c.id = t.category_id
  union all
  select s.household_id, 'recurring_series', 'cuenta_de_otro', s.created_by, a.created_by
  from public.recurring_series s join public.accounts a on a.id = s.account_id
  union all
  select s.household_id, 'recurring_series', 'categoria_de_otro', s.created_by, c.created_by
  from public.recurring_series s join public.categories c on c.id = s.category_id
  union all
  select r.household_id, 'recurring_charges', 'pago_fijo_de_otro', r.created_by, s.created_by
  from public.recurring_charges r join public.recurring_series s on s.id = r.series_id
  union all
  select r.household_id, 'recurring_charges', 'movimiento_de_otro', r.created_by, t.created_by
  from public.recurring_charges r join public.transactions t on t.id = r.transaction_id
  union all
  select g.household_id, 'goals', 'cuenta_de_otro', g.created_by, a.created_by
  from public.goals g join public.accounts a on a.id = g.account_id
  union all
  select k.household_id, 'goal_contributions', 'meta_de_otro', k.created_by, g.created_by
  from public.goal_contributions k join public.goals g on g.id = k.goal_id
  union all
  select h.household_id, 'holdings', 'cuenta_de_otro', h.created_by, a.created_by
  from public.holdings h join public.accounts a on a.id = h.account_id
  union all
  select p.household_id, 'holding_prices', 'activo_de_otro', p.created_by, h.created_by
  from public.holding_prices p join public.holdings h on h.id = p.holding_id
  union all
  select o.household_id, 'investment_trades', 'activo_de_otro', o.created_by, h.created_by
  from public.investment_trades o join public.holdings h on h.id = o.holding_id
  union all
  select p.household_id, 'investment_plans', 'activo_de_otro', p.created_by, h.created_by
  from public.investment_plans p join public.holdings h on h.id = p.holding_id
  union all
  select p.household_id, 'investment_plans', 'cuenta_de_otro', p.created_by, a.created_by
  from public.investment_plans p join public.accounts a on a.id = p.account_id
  union all
  select k.household_id, 'credit_cards', 'cuenta_de_otro', k.created_by, a.created_by
  from public.credit_cards k join public.accounts a on a.id = k.account_id
  union all
  select k.household_id, 'credit_cards', 'cuenta_de_pago_de_otro', k.created_by, a.created_by
  from public.credit_cards k join public.accounts a on a.id = k.pay_from_account_id
  union all
  select i.household_id, 'card_installments', 'tarjeta_de_otro', i.created_by, k.created_by
  from public.card_installments i join public.credit_cards k on k.account_id = i.account_id
  union all
  select i.household_id, 'card_installments', 'movimiento_de_otro', i.created_by, t.created_by
  from public.card_installments i join public.transactions t on t.id = i.transaction_id
  union all
  -- Las líneas no tienen created_by: son de quien creó su presupuesto.
  select l.household_id, 'budget_lines', 'categoria_de_otro', b.created_by, c.created_by
  from public.budget_lines l
  join public.budgets b on b.id = l.budget_id
  join public.categories c on c.id = l.category_id
  union all
  -- Los presupuestos extra guardan listas de ids sin clave foránea: aquí se cuenta cada id de la lista.
  select e.household_id, 'extra_budgets', 'categoria_de_otro', e.created_by, c.created_by
  from public.extra_budgets e join public.categories c on c.id = any (e.category_ids)
  union all
  select e.household_id, 'extra_budgets', 'cuenta_de_otro', e.created_by, a.created_by
  from public.extra_budgets e join public.accounts a on a.id = any (e.account_ids)
),
creadores (household_id, tabla, creador) as (
  select household_id, 'accounts', created_by from public.accounts
  union all select household_id, 'categories', created_by from public.categories
  union all select household_id, 'transactions', created_by from public.transactions
  union all select household_id, 'budgets', created_by from public.budgets
  union all select household_id, 'extra_budgets', created_by from public.extra_budgets
  union all select household_id, 'recurring_series', created_by from public.recurring_series
  union all select household_id, 'recurring_charges', created_by from public.recurring_charges
  union all select household_id, 'goals', created_by from public.goals
  union all select household_id, 'goal_contributions', created_by from public.goal_contributions
  union all select household_id, 'holdings', created_by from public.holdings
  union all select household_id, 'holding_prices', created_by from public.holding_prices
  union all select household_id, 'investment_trades', created_by from public.investment_trades
  union all select household_id, 'investment_plans', created_by from public.investment_plans
  union all select household_id, 'credit_cards', created_by from public.credit_cards
  union all select household_id, 'card_installments', created_by from public.card_installments
),
hallazgos (household_id, tabla, tipo) as (
  -- La fila tiene dueño y lo que enlaza es de otro (o de nadie).
  select household_id, tabla, tipo from enlaces
  where creador is not null and creador is distinct from creador_destino
  union all
  -- Sin dueño: nadie la ve.
  select household_id, tabla, 'sin_creador' from creadores where creador is null
  union all
  -- El dueño ya no es miembro del hogar: tampoco la ve nadie.
  select c.household_id, c.tabla, 'creador_no_miembro' from creadores c
  where c.creador is not null
    and not exists (select 1 from public.household_members m
                    where m.household_id = c.household_id and m.user_id = c.creador)
  union all
  -- Marcada como de un miembro (owner_id) pero creada por otro: su titular no la ve.
  select household_id, 'accounts', 'titular_de_otro' from public.accounts
  where owner_id is not null and created_by is not null and owner_id <> created_by
  union all
  select household_id, 'holdings', 'titular_de_otro' from public.holdings
  where owner_id is not null and created_by is not null and owner_id <> created_by
)
select household_id, tabla, tipo, count(*) as filas
from hallazgos
group by household_id, tabla, tipo
order by household_id, tabla, tipo;
