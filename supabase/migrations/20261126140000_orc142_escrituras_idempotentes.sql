-- El resto de tablas: dar de alta sin duplicar y cambiar sin pisar (ORC-142).
--
-- Mismo modelo que los movimientos (ORC-69, 20261126080000_movimientos_idempotentes.sql):
--
-- 1. Alta (`create_…`): la app elige el identificador de la fila, uno por formulario. Repetir la
--    petición (por ejemplo tras un corte de red) devuelve lo guardado y no crea nada; con otros
--    datos falla (STM01). Un identificador que ya usó otra persona falla con 23505: el RLS no
--    deja ver esa fila, así que ni se lee ni se cambia.
-- 2. Cambio (`update_…`): la app manda el `updated_at` que leyó. Si la fila ha cambiado desde
--    entonces, ya no existe o no es de quien llama, no se cambia nada y falla con STM05: la app
--    recarga y avisa. La comparación va en el mismo update: entre dos cambios a la vez solo entra
--    el primero.
--
-- Todas las funciones corren con los permisos de quien llama (security invoker): el RLS y los
-- permisos por columna siguen decidiendo quién crea y quién cambia qué. Ningún parámetro se
-- llama como una columna, para que dentro de las funciones no haya nombres ambiguos.
--
-- No cambia quién ve qué ni toca filas existentes: solo añade el permiso de insertar `id` y las
-- funciones. Las apps anteriores siguen funcionando: sus insert y update directos conservan los
-- permisos que tenían (sin estas dos protecciones), igual que se decidió para los movimientos.

-- Solo al crear la fila. Un identificador repetido choca con la clave primaria: nunca
-- sobrescribe ni deja leer la fila de otra persona. (extra_budgets ya lo tenía.)
grant insert (id) on public.accounts to authenticated;

-- Cuentas -------------------------------------------------------------------------------

create function public.create_account(
  account uuid,
  household uuid,
  label text,
  account_kind public.account_kind,
  opening bigint,
  owner uuid default null
) returns setof public.accounts
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved public.accounts;
begin
  if account is null then
    raise exception 'Falta el identificador de la cuenta' using errcode = '23514';
  end if;

  -- Si la cuenta ya estaba guardada no se crea nada.
  insert into public.accounts (id, household_id, name, kind, opening_balance_minor, owner_id)
  values (account, household, label, account_kind, opening, owner)
  on conflict (id) do nothing;

  -- El RLS solo deja ver las cuentas propias: si no se ve, ese identificador es de otra persona.
  select a.* into saved from public.accounts a where a.id = account;
  if not found then
    raise exception 'Ese identificador de cuenta ya está usado' using errcode = '23505';
  end if;

  -- Repetir la petición solo vale con los mismos datos (STM01, como create_movement).
  if (saved.household_id = household and saved.name = label and saved.kind = account_kind
      and saved.opening_balance_minor = opening) is not true then
    raise exception 'Esa cuenta ya está guardada con otros datos' using errcode = 'STM01';
  end if;

  return next saved;
end;
$$;

revoke all on function public.create_account(uuid, uuid, text, public.account_kind, bigint, uuid) from public, anon;
grant execute on function public.create_account(uuid, uuid, text, public.account_kind, bigint, uuid) to authenticated;

-- `seen` es el `updated_at` tal cual lo devolvió el servidor (con microsegundos y zona).
create function public.update_account(
  account uuid,
  seen timestamptz,
  label text,
  account_kind public.account_kind,
  opening bigint,
  owner uuid,
  archived timestamptz,
  make_default boolean,
  in_net_worth boolean
) returns setof public.accounts
language plpgsql
security invoker
set search_path = ''
as $$
begin
  return query
    update public.accounts a
    set name = label, kind = account_kind, opening_balance_minor = opening, owner_id = owner,
        archived_at = archived, is_default = make_default, include_in_net_worth = in_net_worth
    where a.id = account and a.updated_at = seen
    returning a.*;

  -- Sin fila: ha cambiado desde que se leyó, se ha borrado o no es de quien llama (el RLS no la
  -- deja ver). STM05, como update_movement: las apps recargan y avisan.
  if not found then
    raise exception 'La cuenta ha cambiado desde que se leyó' using errcode = 'STM05';
  end if;
end;
$$;

revoke all on function public.update_account(uuid, timestamptz, text, public.account_kind, bigint, uuid, timestamptz, boolean, boolean)
  from public, anon;
grant execute on function public.update_account(uuid, timestamptz, text, public.account_kind, bigint, uuid, timestamptz, boolean, boolean)
  to authenticated;

-- Metas y aportaciones --------------------------------------------------------------------

grant insert (id) on public.goals, public.goal_contributions to authenticated;

create function public.create_goal(
  goal uuid,
  household uuid,
  label text,
  goal_kind public.goal_kind,
  target bigint,
  starting bigint,
  monthly_plan bigint,
  due date,
  account uuid,
  icon_name text,
  completed timestamptz,
  archived timestamptz
) returns setof public.goals
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved public.goals;
begin
  if goal is null then
    raise exception 'Falta el identificador de la meta' using errcode = '23514';
  end if;

  insert into public.goals (id, household_id, name, kind, target_minor, starting_minor, monthly_plan_minor,
                            target_on, account_id, icon, completed_at, archived_at)
  values (goal, household, label, goal_kind, target, starting, monthly_plan, due, account, icon_name,
          completed, archived)
  on conflict (id) do nothing;

  select g.* into saved from public.goals g where g.id = goal;
  if not found then
    raise exception 'Ese identificador de meta ya está usado' using errcode = '23505';
  end if;

  if (saved.household_id = household and saved.name = label and saved.kind = goal_kind
      and saved.target_minor = target) is not true then
    raise exception 'Esa meta ya está guardada con otros datos' using errcode = 'STM01';
  end if;

  return next saved;
end;
$$;

revoke all on function public.create_goal(uuid, uuid, text, public.goal_kind, bigint, bigint, bigint, date, uuid, text, timestamptz, timestamptz)
  from public, anon;
grant execute on function public.create_goal(uuid, uuid, text, public.goal_kind, bigint, bigint, bigint, date, uuid, text, timestamptz, timestamptz)
  to authenticated;

create function public.update_goal(
  goal uuid,
  seen timestamptz,
  label text,
  goal_kind public.goal_kind,
  target bigint,
  starting bigint,
  monthly_plan bigint,
  due date,
  account uuid,
  icon_name text,
  completed timestamptz,
  archived timestamptz
) returns setof public.goals
language plpgsql
security invoker
set search_path = ''
as $$
begin
  return query
    update public.goals g
    set name = label, kind = goal_kind, target_minor = target, starting_minor = starting,
        monthly_plan_minor = monthly_plan, target_on = due, account_id = account, icon = icon_name,
        completed_at = completed, archived_at = archived
    where g.id = goal and g.updated_at = seen
    returning g.*;

  if not found then
    raise exception 'La meta ha cambiado desde que se leyó' using errcode = 'STM05';
  end if;
end;
$$;

revoke all on function public.update_goal(uuid, timestamptz, text, public.goal_kind, bigint, bigint, bigint, date, uuid, text, timestamptz, timestamptz)
  from public, anon;
grant execute on function public.update_goal(uuid, timestamptz, text, public.goal_kind, bigint, bigint, bigint, date, uuid, text, timestamptz, timestamptz)
  to authenticated;

-- Una aportación no se cambia desde las apps: solo se apunta o se borra.
create function public.create_goal_contribution(
  contribution uuid,
  household uuid,
  goal uuid,
  amount bigint,
  made date,
  remark text default null
) returns setof public.goal_contributions
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved public.goal_contributions;
begin
  if contribution is null then
    raise exception 'Falta el identificador de la aportación' using errcode = '23514';
  end if;

  insert into public.goal_contributions (id, household_id, goal_id, amount_minor, made_on, note)
  values (contribution, household, goal, amount, made, remark)
  on conflict (id) do nothing;

  select c.* into saved from public.goal_contributions c where c.id = contribution;
  if not found then
    raise exception 'Ese identificador de aportación ya está usado' using errcode = '23505';
  end if;

  if (saved.goal_id = goal and saved.amount_minor = amount and saved.made_on = made) is not true then
    raise exception 'Esa aportación ya está guardada con otros datos' using errcode = 'STM01';
  end if;

  return next saved;
end;
$$;

revoke all on function public.create_goal_contribution(uuid, uuid, uuid, bigint, date, text) from public, anon;
grant execute on function public.create_goal_contribution(uuid, uuid, uuid, bigint, date, text) to authenticated;

-- Pagos fijos -----------------------------------------------------------------------------

grant insert (id) on public.recurring_series to authenticated;

-- `pending_start` nulo: los cargos pendientes empiezan hoy, como el valor por defecto de la columna.
create function public.create_recurring_series(
  series uuid,
  household uuid,
  label text,
  series_kind public.recurring_kind,
  amount bigint,
  account uuid,
  category uuid,
  step integer,
  step_unit public.recurrence_unit,
  starts date,
  ends date,
  remind_days integer,
  archived timestamptz,
  intro_amount bigint,
  intro_count integer,
  pending boolean,
  pending_start date
) returns setof public.recurring_series
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved public.recurring_series;
begin
  if series is null then
    raise exception 'Falta el identificador del pago fijo' using errcode = '23514';
  end if;

  insert into public.recurring_series (id, household_id, name, kind, amount_minor, account_id, category_id,
                                       every, unit, starts_on, ends_on, remind_days_before, archived_at,
                                       intro_amount_minor, intro_charges, creates_pending, pending_from)
  values (series, household, label, series_kind, amount, account, category, step, step_unit, starts, ends,
          remind_days, archived, intro_amount, intro_count, pending, coalesce(pending_start, current_date))
  on conflict (id) do nothing;

  select r.* into saved from public.recurring_series r where r.id = series;
  if not found then
    raise exception 'Ese identificador de pago fijo ya está usado' using errcode = '23505';
  end if;

  if (saved.household_id = household and saved.name = label and saved.kind = series_kind
      and saved.amount_minor = amount and saved.starts_on = starts) is not true then
    raise exception 'Ese pago fijo ya está guardado con otros datos' using errcode = 'STM01';
  end if;

  return next saved;
end;
$$;

revoke all on function public.create_recurring_series(uuid, uuid, text, public.recurring_kind, bigint, uuid, uuid, integer, public.recurrence_unit, date, date, integer, timestamptz, bigint, integer, boolean, date)
  from public, anon;
grant execute on function public.create_recurring_series(uuid, uuid, text, public.recurring_kind, bigint, uuid, uuid, integer, public.recurrence_unit, date, date, integer, timestamptz, bigint, integer, boolean, date)
  to authenticated;

-- `pending_start` nulo: se queda el día que tenía.
create function public.update_recurring_series(
  series uuid,
  seen timestamptz,
  label text,
  series_kind public.recurring_kind,
  amount bigint,
  account uuid,
  category uuid,
  step integer,
  step_unit public.recurrence_unit,
  starts date,
  ends date,
  remind_days integer,
  archived timestamptz,
  intro_amount bigint,
  intro_count integer,
  pending boolean,
  pending_start date
) returns setof public.recurring_series
language plpgsql
security invoker
set search_path = ''
as $$
begin
  return query
    update public.recurring_series r
    set name = label, kind = series_kind, amount_minor = amount, account_id = account, category_id = category,
        every = step, unit = step_unit, starts_on = starts, ends_on = ends, remind_days_before = remind_days,
        archived_at = archived, intro_amount_minor = intro_amount, intro_charges = intro_count,
        creates_pending = pending, pending_from = coalesce(pending_start, r.pending_from)
    where r.id = series and r.updated_at = seen
    returning r.*;

  if not found then
    raise exception 'El pago fijo ha cambiado desde que se leyó' using errcode = 'STM05';
  end if;
end;
$$;

revoke all on function public.update_recurring_series(uuid, timestamptz, text, public.recurring_kind, bigint, uuid, uuid, integer, public.recurrence_unit, date, date, integer, timestamptz, bigint, integer, boolean, date)
  from public, anon;
grant execute on function public.update_recurring_series(uuid, timestamptz, text, public.recurring_kind, bigint, uuid, uuid, integer, public.recurrence_unit, date, date, integer, timestamptz, bigint, integer, boolean, date)
  to authenticated;

-- Tarjetas de crédito y compras aplazadas ----------------------------------------------------
-- Las condiciones de una tarjeta no tienen identificador propio: su clave es la cuenta, así que
-- el alta ya no se puede duplicar. `create_credit_card` da además la misma respuesta que las
-- demás altas: lo guardado si se repite, STM01 si ya había otras condiciones distintas.

grant insert (id) on public.card_installments to authenticated;

create function public.create_credit_card(
  card uuid,
  household uuid,
  credit_limit bigint,
  statement integer,
  payment integer,
  delay_months integer,
  mode public.card_payment_mode,
  fixed_payment bigint,
  min_percent numeric,
  min_payment bigint,
  revolving numeric,
  installments numeric,
  pay_from uuid,
  remind_days integer,
  alert integer
) returns setof public.credit_cards
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved public.credit_cards;
begin
  if card is null then
    raise exception 'Falta la cuenta de la tarjeta' using errcode = '23514';
  end if;

  insert into public.credit_cards (account_id, household_id, credit_limit_minor, statement_day, payment_day,
                                   payment_delay_months, payment_mode, fixed_payment_minor, min_payment_percent,
                                   min_payment_minor, revolving_rate, installment_rate, pay_from_account_id,
                                   remind_days_before, alert_percent)
  values (card, household, credit_limit, statement, payment, delay_months, mode, fixed_payment, min_percent,
          min_payment, revolving, installments, pay_from, remind_days, alert)
  on conflict (account_id) do nothing;

  select c.* into saved from public.credit_cards c where c.account_id = card;
  if not found then
    raise exception 'Esa tarjeta ya tiene condiciones' using errcode = '23505';
  end if;

  if (saved.household_id = household and saved.credit_limit_minor = credit_limit and saved.statement_day = statement
      and saved.payment_day = payment and saved.payment_mode = mode) is not true then
    raise exception 'Esa tarjeta ya está guardada con otras condiciones' using errcode = 'STM01';
  end if;

  return next saved;
end;
$$;

revoke all on function public.create_credit_card(uuid, uuid, bigint, integer, integer, integer, public.card_payment_mode, bigint, numeric, bigint, numeric, numeric, uuid, integer, integer)
  from public, anon;
grant execute on function public.create_credit_card(uuid, uuid, bigint, integer, integer, integer, public.card_payment_mode, bigint, numeric, bigint, numeric, numeric, uuid, integer, integer)
  to authenticated;

create function public.update_credit_card(
  card uuid,
  seen timestamptz,
  credit_limit bigint,
  statement integer,
  payment integer,
  delay_months integer,
  mode public.card_payment_mode,
  fixed_payment bigint,
  min_percent numeric,
  min_payment bigint,
  revolving numeric,
  installments numeric,
  pay_from uuid,
  remind_days integer,
  alert integer
) returns setof public.credit_cards
language plpgsql
security invoker
set search_path = ''
as $$
begin
  return query
    update public.credit_cards c
    set credit_limit_minor = credit_limit, statement_day = statement, payment_day = payment,
        payment_delay_months = delay_months, payment_mode = mode, fixed_payment_minor = fixed_payment,
        min_payment_percent = min_percent, min_payment_minor = min_payment, revolving_rate = revolving,
        installment_rate = installments, pay_from_account_id = pay_from, remind_days_before = remind_days,
        alert_percent = alert
    where c.account_id = card and c.updated_at = seen
    returning c.*;

  if not found then
    raise exception 'Las condiciones de la tarjeta han cambiado desde que se leyeron' using errcode = 'STM05';
  end if;
end;
$$;

revoke all on function public.update_credit_card(uuid, timestamptz, bigint, integer, integer, integer, public.card_payment_mode, bigint, numeric, bigint, numeric, numeric, uuid, integer, integer)
  from public, anon;
grant execute on function public.update_credit_card(uuid, timestamptz, bigint, integer, integer, integer, public.card_payment_mode, bigint, numeric, bigint, numeric, numeric, uuid, integer, integer)
  to authenticated;

-- Hay un aplazado por compra (transaction_id es único): otro con un identificador distinto para
-- la misma compra choca con ese índice (23505), no con el identificador.
create function public.create_card_installment(
  installment uuid,
  household uuid,
  card uuid,
  movement uuid,
  plan_months integer,
  plan_rate numeric
) returns setof public.card_installments
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved public.card_installments;
begin
  if installment is null then
    raise exception 'Falta el identificador del aplazado' using errcode = '23514';
  end if;

  insert into public.card_installments (id, household_id, account_id, transaction_id, months, rate)
  values (installment, household, card, movement, plan_months, plan_rate)
  on conflict (id) do nothing;

  select i.* into saved from public.card_installments i where i.id = installment;
  if not found then
    raise exception 'Ese identificador de aplazado ya está usado' using errcode = '23505';
  end if;

  if (saved.transaction_id = movement and saved.months = plan_months and saved.rate = plan_rate) is not true then
    raise exception 'Ese aplazado ya está guardado con otros datos' using errcode = 'STM01';
  end if;

  return next saved;
end;
$$;

revoke all on function public.create_card_installment(uuid, uuid, uuid, uuid, integer, numeric) from public, anon;
grant execute on function public.create_card_installment(uuid, uuid, uuid, uuid, integer, numeric) to authenticated;

-- Solo plazo e interés: la tarjeta y la compra de un aplazado no se cambian.
create function public.update_card_installment(
  installment uuid,
  seen timestamptz,
  plan_months integer,
  plan_rate numeric
) returns setof public.card_installments
language plpgsql
security invoker
set search_path = ''
as $$
begin
  return query
    update public.card_installments i
    set months = plan_months, rate = plan_rate
    where i.id = installment and i.updated_at = seen
    returning i.*;

  if not found then
    raise exception 'El aplazado ha cambiado desde que se leyó' using errcode = 'STM05';
  end if;
end;
$$;

revoke all on function public.update_card_installment(uuid, timestamptz, integer, numeric) from public, anon;
grant execute on function public.update_card_installment(uuid, timestamptz, integer, numeric) to authenticated;

-- Activos y planes de aportación ----------------------------------------------------------------

grant insert (id) on public.holdings, public.investment_plans to authenticated;

-- La moneda no es un parámetro: la app no la manda al crear y vale la de la columna, como hasta ahora.
create function public.create_holding(
  holding uuid,
  household uuid,
  label text,
  ticker text,
  holding_kind public.investment_kind,
  asset public.asset_class,
  account uuid,
  owner uuid,
  unit_price numeric,
  priced date,
  fee numeric,
  remark text,
  archived timestamptz
) returns setof public.holdings
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved public.holdings;
begin
  if holding is null then
    raise exception 'Falta el identificador del activo' using errcode = '23514';
  end if;

  insert into public.holdings (id, household_id, name, symbol, kind, asset_class, account_id, owner_id, price,
                               price_on, fee_rate, note, archived_at)
  values (holding, household, label, ticker, holding_kind, asset, account, owner, unit_price, priced, fee,
          remark, archived)
  on conflict (id) do nothing;

  select h.* into saved from public.holdings h where h.id = holding;
  if not found then
    raise exception 'Ese identificador de activo ya está usado' using errcode = '23505';
  end if;

  if (saved.household_id = household and saved.name = label and saved.kind = holding_kind) is not true then
    raise exception 'Ese activo ya está guardado con otros datos' using errcode = 'STM01';
  end if;

  return next saved;
end;
$$;

revoke all on function public.create_holding(uuid, uuid, text, text, public.investment_kind, public.asset_class, uuid, uuid, numeric, date, numeric, text, timestamptz)
  from public, anon;
grant execute on function public.create_holding(uuid, uuid, text, text, public.investment_kind, public.asset_class, uuid, uuid, numeric, date, numeric, text, timestamptz)
  to authenticated;

-- Apuntar un precio (record_holding_price) también cambia la versión del activo.
create function public.update_holding(
  holding uuid,
  seen timestamptz,
  label text,
  ticker text,
  holding_kind public.investment_kind,
  asset public.asset_class,
  account uuid,
  owner uuid,
  unit_price numeric,
  priced date,
  fee numeric,
  remark text,
  archived timestamptz
) returns setof public.holdings
language plpgsql
security invoker
set search_path = ''
as $$
begin
  return query
    update public.holdings h
    set name = label, symbol = ticker, kind = holding_kind, asset_class = asset, account_id = account,
        owner_id = owner, price = unit_price, price_on = priced, fee_rate = fee, note = remark,
        archived_at = archived
    where h.id = holding and h.updated_at = seen
    returning h.*;

  if not found then
    raise exception 'El activo ha cambiado desde que se leyó' using errcode = 'STM05';
  end if;
end;
$$;

revoke all on function public.update_holding(uuid, timestamptz, text, text, public.investment_kind, public.asset_class, uuid, uuid, numeric, date, numeric, text, timestamptz)
  from public, anon;
grant execute on function public.update_holding(uuid, timestamptz, text, text, public.investment_kind, public.asset_class, uuid, uuid, numeric, date, numeric, text, timestamptz)
  to authenticated;

create function public.create_investment_plan(
  plan uuid,
  household uuid,
  holding uuid,
  account uuid,
  amount bigint,
  step integer,
  step_unit public.recurrence_unit,
  starts date,
  ends date,
  annual_return numeric,
  remind_days integer,
  paused timestamptz,
  archived timestamptz
) returns setof public.investment_plans
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved public.investment_plans;
begin
  if plan is null then
    raise exception 'Falta el identificador del plan' using errcode = '23514';
  end if;

  insert into public.investment_plans (id, household_id, holding_id, account_id, amount_minor, every, unit,
                                       starts_on, ends_on, expected_annual_return, remind_days_before,
                                       paused_at, archived_at)
  values (plan, household, holding, account, amount, step, step_unit, starts, ends, annual_return, remind_days,
          paused, archived)
  on conflict (id) do nothing;

  select p.* into saved from public.investment_plans p where p.id = plan;
  if not found then
    raise exception 'Ese identificador de plan ya está usado' using errcode = '23505';
  end if;

  if (saved.holding_id = holding and saved.amount_minor = amount and saved.starts_on = starts) is not true then
    raise exception 'Ese plan ya está guardado con otros datos' using errcode = 'STM01';
  end if;

  return next saved;
end;
$$;

revoke all on function public.create_investment_plan(uuid, uuid, uuid, uuid, bigint, integer, public.recurrence_unit, date, date, numeric, integer, timestamptz, timestamptz)
  from public, anon;
grant execute on function public.create_investment_plan(uuid, uuid, uuid, uuid, bigint, integer, public.recurrence_unit, date, date, numeric, integer, timestamptz, timestamptz)
  to authenticated;

-- El activo de un plan no se cambia.
create function public.update_investment_plan(
  plan uuid,
  seen timestamptz,
  account uuid,
  amount bigint,
  step integer,
  step_unit public.recurrence_unit,
  starts date,
  ends date,
  annual_return numeric,
  remind_days integer,
  paused timestamptz,
  archived timestamptz
) returns setof public.investment_plans
language plpgsql
security invoker
set search_path = ''
as $$
begin
  return query
    update public.investment_plans p
    set account_id = account, amount_minor = amount, every = step, unit = step_unit, starts_on = starts,
        ends_on = ends, expected_annual_return = annual_return, remind_days_before = remind_days,
        paused_at = paused, archived_at = archived
    where p.id = plan and p.updated_at = seen
    returning p.*;

  if not found then
    raise exception 'El plan ha cambiado desde que se leyó' using errcode = 'STM05';
  end if;
end;
$$;

revoke all on function public.update_investment_plan(uuid, timestamptz, uuid, bigint, integer, public.recurrence_unit, date, date, numeric, integer, timestamptz, timestamptz)
  from public, anon;
grant execute on function public.update_investment_plan(uuid, timestamptz, uuid, bigint, integer, public.recurrence_unit, date, date, numeric, integer, timestamptz, timestamptz)
  to authenticated;

-- Categorías ------------------------------------------------------------------------------
-- El nombre sigue sin poder repetirse entre las categorías propias: ese índice único falla con
-- 23505 como antes, también dentro de `create_category` (solo el identificador se resuelve con
-- `on conflict`).

grant insert (id) on public.categories to authenticated;

create function public.create_category(
  category uuid,
  household uuid,
  label text,
  category_kind public.category_kind,
  budget public.budget_group,
  icon_name text
) returns setof public.categories
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved public.categories;
begin
  if category is null then
    raise exception 'Falta el identificador de la categoría' using errcode = '23514';
  end if;

  insert into public.categories (id, household_id, name, kind, budget_group, icon)
  values (category, household, label, category_kind, budget, icon_name)
  on conflict (id) do nothing;

  select c.* into saved from public.categories c where c.id = category;
  if not found then
    raise exception 'Ese identificador de categoría ya está usado' using errcode = '23505';
  end if;

  if (saved.household_id = household and saved.name = label and saved.kind = category_kind) is not true then
    raise exception 'Esa categoría ya está guardada con otros datos' using errcode = 'STM01';
  end if;

  return next saved;
end;
$$;

revoke all on function public.create_category(uuid, uuid, text, public.category_kind, public.budget_group, text) from public, anon;
grant execute on function public.create_category(uuid, uuid, text, public.category_kind, public.budget_group, text) to authenticated;

-- Solo nombre, grupo e icono: el tipo de una categoría no se cambia.
create function public.update_category(
  category uuid,
  seen timestamptz,
  label text,
  budget public.budget_group,
  icon_name text
) returns setof public.categories
language plpgsql
security invoker
set search_path = ''
as $$
begin
  return query
    update public.categories c
    set name = label, budget_group = budget, icon = icon_name
    where c.id = category and c.updated_at = seen
    returning c.*;

  if not found then
    raise exception 'La categoría ha cambiado desde que se leyó' using errcode = 'STM05';
  end if;
end;
$$;

revoke all on function public.update_category(uuid, timestamptz, text, public.budget_group, text) from public, anon;
grant execute on function public.update_category(uuid, timestamptz, text, public.budget_group, text) to authenticated;

-- Presupuestos extra ------------------------------------------------------------------------
-- extra_budgets ya dejaba insertar `id`; faltaban la respuesta a un alta repetida y la versión.

-- Si el presupuesto ya está guardado no se intenta insertar: el disparador del favorito corre
-- antes de mirar el identificador, y un alta repetida le quitaría la marca al favorito actual.
create function public.create_extra_budget(
  budget uuid,
  household uuid,
  label text,
  cap bigint,
  starts date,
  ends date,
  category_list uuid[],
  account_list uuid[],
  favorite boolean
) returns setof public.extra_budgets
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved public.extra_budgets;
begin
  if budget is null then
    raise exception 'Falta el identificador del presupuesto extra' using errcode = '23514';
  end if;

  select e.* into saved from public.extra_budgets e where e.id = budget;
  if not found then
    insert into public.extra_budgets (id, household_id, name, limit_minor, starts_on, ends_on, category_ids,
                                      account_ids, is_favorite)
    values (budget, household, label, cap, starts, ends, category_list, account_list, favorite)
    on conflict (id) do nothing;

    -- El RLS solo deja ver los propios: si sigue sin verse, ese identificador es de otra persona.
    select e.* into saved from public.extra_budgets e where e.id = budget;
    if not found then
      raise exception 'Ese identificador de presupuesto extra ya está usado' using errcode = '23505';
    end if;
  end if;

  if (saved.household_id = household and saved.name = label and saved.limit_minor = cap
      and saved.starts_on = starts) is not true then
    raise exception 'Ese presupuesto extra ya está guardado con otros datos' using errcode = 'STM01';
  end if;

  return next saved;
end;
$$;

revoke all on function public.create_extra_budget(uuid, uuid, text, bigint, date, date, uuid[], uuid[], boolean) from public, anon;
grant execute on function public.create_extra_budget(uuid, uuid, text, bigint, date, date, uuid[], uuid[], boolean) to authenticated;

-- Marcar uno como favorito le quita la marca al anterior (disparador): ese también cambia de versión.
create function public.update_extra_budget(
  budget uuid,
  seen timestamptz,
  label text,
  cap bigint,
  starts date,
  ends date,
  category_list uuid[],
  account_list uuid[],
  favorite boolean
) returns setof public.extra_budgets
language plpgsql
security invoker
set search_path = ''
as $$
begin
  return query
    update public.extra_budgets e
    set name = label, limit_minor = cap, starts_on = starts, ends_on = ends, category_ids = category_list,
        account_ids = account_list, is_favorite = favorite
    where e.id = budget and e.updated_at = seen
    returning e.*;

  if not found then
    raise exception 'El presupuesto extra ha cambiado desde que se leyó' using errcode = 'STM05';
  end if;
end;
$$;

revoke all on function public.update_extra_budget(uuid, timestamptz, text, bigint, date, date, uuid[], uuid[], boolean) from public, anon;
grant execute on function public.update_extra_budget(uuid, timestamptz, text, bigint, date, date, uuid[], uuid[], boolean) to authenticated;

-- Cargos de los pagos fijos ---------------------------------------------------------------------
-- Los cargos no tienen alta desde un formulario: la app los crea en lote y `unique (series_id,
-- due_on)` ya impide repetirlos. Aquí solo falta la versión al enlazarlos con un movimiento que
-- ya existe o al saltarlos. (Confirmar uno creando su movimiento sigue siendo
-- `confirm_recurring_charge`, que ya comprueba que siga pendiente.)
create function public.update_recurring_charge(
  charge uuid,
  seen timestamptz,
  new_status text,
  movement uuid
) returns setof public.recurring_charges
language plpgsql
security invoker
set search_path = ''
as $$
begin
  return query
    update public.recurring_charges c
    set status = new_status, transaction_id = movement
    where c.id = charge and c.updated_at = seen
    returning c.*;

  if not found then
    raise exception 'El cargo ha cambiado desde que se leyó' using errcode = 'STM05';
  end if;
end;
$$;

revoke all on function public.update_recurring_charge(uuid, timestamptz, text, uuid) from public, anon;
grant execute on function public.update_recurring_charge(uuid, timestamptz, text, uuid) to authenticated;
