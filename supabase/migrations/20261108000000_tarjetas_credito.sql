-- Tarjetas de crédito: cuánto se va a pagar cada mes.
--
-- Una tarjeta es una cuenta de tipo credit_card (ya existe) con sus condiciones aquí:
-- límite, día del extracto, día y mes del cargo, forma de pago (todo a fin de mes,
-- cuota fija o pago mínimo) y los tipos de interés. Los valores por defecto son los de
-- un contrato habitual en España; todos se pueden cambiar en la app.
-- Las compras aplazadas (pagar una compra en N meses) apuntan a su movimiento.
-- El cálculo del próximo cargo, el calendario y los intereses se hace en la app.
-- Como las cuentas, se ve dentro del hogar y sólo lo tocan sus miembros (RLS).

create type public.card_payment_mode as enum ('full', 'fixed', 'minimum');

-- Para que una compra aplazada sólo pueda apuntar a un movimiento de esa misma tarjeta.
alter table public.transactions add constraint transactions_id_account_key unique (id, account_id);

create table public.credit_cards (
  account_id uuid primary key,
  household_id uuid not null,
  credit_limit_minor bigint not null check (credit_limit_minor > 0),
  -- Día en que se cierra el extracto: lo gastado hasta el día anterior entra en él.
  statement_day smallint not null default 1 check (statement_day between 1 and 28),
  -- Día del cargo en la cuenta, y cuántos meses después del extracto
  -- (1 = el extracto del 1 de febrero se cobra el 1 de marzo).
  payment_day smallint not null default 1 check (payment_day between 1 and 28),
  payment_delay_months smallint not null default 1 check (payment_delay_months between 0 and 2),
  payment_mode public.card_payment_mode not null default 'full',
  -- Cuota fija al mes, sólo para payment_mode = 'fixed'.
  fixed_payment_minor bigint check (fixed_payment_minor > 0),
  -- Pago mínimo = máx(min_payment_percent % del capital + intereses, min_payment_minor).
  min_payment_percent numeric(5, 2) not null default 3 check (min_payment_percent between 0 and 100),
  min_payment_minor bigint not null default 1500 check (min_payment_minor >= 0),
  -- TIN anual en % del pago aplazado (cuota fija o mínimo) y de las compras a plazos.
  revolving_rate numeric(5, 2) not null default 20 check (revolving_rate between 0 and 60),
  installment_rate numeric(5, 2) not null default 14 check (installment_rate between 0 and 60),
  -- Cuenta de la que sale el cargo, para avisar si no hay saldo.
  pay_from_account_id uuid,
  remind_days_before smallint default 2 check (remind_days_before between 0 and 14),
  -- Aviso al pasar de este % del límite; null = sin aviso.
  alert_percent smallint default 80 check (alert_percent between 1 and 100),
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (payment_mode <> 'fixed' or fixed_payment_minor is not null),
  check (pay_from_account_id is null or pay_from_account_id <> account_id),
  foreign key (account_id, household_id) references public.accounts (id, household_id) on delete cascade,
  foreign key (pay_from_account_id, household_id) references public.accounts (id, household_id)
    on delete set null (pay_from_account_id),
  unique (account_id, household_id)
);

create index credit_cards_household_id_idx on public.credit_cards (household_id);
create index credit_cards_pay_from_idx on public.credit_cards (pay_from_account_id);

-- Compra pagada a plazos: el movimiento sigue siendo la compra entera; esto dice en
-- cuántos meses y a qué interés se paga, para sumar la cuota al cargo de cada mes.
create table public.card_installments (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  account_id uuid not null,
  transaction_id uuid not null unique,
  months smallint not null check (months between 2 and 48),
  rate numeric(5, 2) not null default 14 check (rate between 0 and 60),
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (account_id, household_id) references public.credit_cards (account_id, household_id) on delete cascade,
  foreign key (transaction_id, account_id) references public.transactions (id, account_id) on delete cascade
);

create index card_installments_household_id_idx on public.card_installments (household_id);
create index card_installments_account_id_idx on public.card_installments (account_id);

create trigger credit_cards_touch before update on public.credit_cards
  for each row execute function private.touch_updated_at();
create trigger card_installments_touch before update on public.card_installments
  for each row execute function private.touch_updated_at();

-- Sólo una cuenta de tipo tarjeta puede tener condiciones de tarjeta.
create function private.check_credit_card_account()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.accounts a where a.id = new.account_id and a.kind = 'credit_card'
  ) then
    raise exception 'la cuenta no es una tarjeta de crédito' using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke execute on function private.check_credit_card_account() from public;

create trigger credit_cards_kind before insert or update on public.credit_cards
  for each row execute function private.check_credit_card_account();

-- RLS ---------------------------------------------------------------------------

alter table public.credit_cards enable row level security;
alter table public.card_installments enable row level security;

revoke all on public.credit_cards, public.card_installments from anon, authenticated;

-- account_id, household_id y created_by no se pueden cambiar después de crear la fila.
grant select,
  insert (account_id, household_id, credit_limit_minor, statement_day, payment_day, payment_delay_months,
          payment_mode, fixed_payment_minor, min_payment_percent, min_payment_minor, revolving_rate,
          installment_rate, pay_from_account_id, remind_days_before, alert_percent),
  update (credit_limit_minor, statement_day, payment_day, payment_delay_months, payment_mode, fixed_payment_minor,
          min_payment_percent, min_payment_minor, revolving_rate, installment_rate, pay_from_account_id,
          remind_days_before, alert_percent),
  delete
  on public.credit_cards to authenticated;
grant select,
  insert (household_id, account_id, transaction_id, months, rate),
  update (months, rate),
  delete
  on public.card_installments to authenticated;

create policy credit_cards_select on public.credit_cards
  for select to authenticated
  using ((select private.is_member(household_id)));
create policy credit_cards_insert on public.credit_cards
  for insert to authenticated
  with check ((select private.is_member(household_id)));
create policy credit_cards_update on public.credit_cards
  for update to authenticated
  using ((select private.is_member(household_id)))
  with check ((select private.is_member(household_id)));
create policy credit_cards_delete on public.credit_cards
  for delete to authenticated
  using ((select private.is_member(household_id)));

create policy card_installments_select on public.card_installments
  for select to authenticated
  using ((select private.is_member(household_id)));
create policy card_installments_insert on public.card_installments
  for insert to authenticated
  with check ((select private.is_member(household_id)));
create policy card_installments_update on public.card_installments
  for update to authenticated
  using ((select private.is_member(household_id)))
  with check ((select private.is_member(household_id)));
create policy card_installments_delete on public.card_installments
  for delete to authenticated
  using ((select private.is_member(household_id)));
