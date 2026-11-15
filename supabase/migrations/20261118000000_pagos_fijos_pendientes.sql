-- Fase D: los pagos fijos crean su cargo pendiente de confirmar.
--
-- Cuando llega el día de un pago fijo, la app apunta aquí un cargo «pendiente». No es un
-- movimiento: no cuenta en saldos, presupuesto ni informes hasta que se confirma.
--   confirmar  crea el movimiento real (confirm_recurring_charge) y lo enlaza;
--   emparejar  si el cargo ya llegó por CSV o a mano, se enlaza con ese movimiento, sin duplicar;
--   saltar     ese mes no hubo cargo.
-- Un cargo por serie y día (unique), así que dos dispositivos no lo crean dos veces.
-- Como las series, cada cargo es de quien lo crea: el resto del hogar no lo ve.

alter table public.recurring_series
  -- Si crea cargos pendientes al llegar su día.
  add column creates_pending boolean not null default true,
  -- Desde qué día crea cargos: así las series que ya había no rellenan meses pasados.
  add column pending_from date not null default current_date;

grant insert (creates_pending, pending_from), update (creates_pending, pending_from)
  on public.recurring_series to authenticated;

create table public.recurring_charges (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  series_id uuid not null references public.recurring_series (id) on delete cascade,
  due_on date not null,
  -- Céntimos con signo, como los movimientos: negativo es un gasto.
  amount_minor bigint not null check (amount_minor <> 0),
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'skipped')),
  -- El movimiento que lo confirma (creado al confirmar o emparejado).
  transaction_id uuid references public.transactions (id) on delete set null,
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (series_id, due_on),
  check (status <> 'pending' or transaction_id is null)
);

create index recurring_charges_household_idx on public.recurring_charges (household_id, status);
create index recurring_charges_transaction_idx on public.recurring_charges (transaction_id);

alter table public.recurring_charges enable row level security;
revoke all on public.recurring_charges from anon, authenticated;

grant select,
  insert (household_id, series_id, due_on, amount_minor),
  update (amount_minor, status, transaction_id),
  delete
  on public.recurring_charges to authenticated;

create policy recurring_charges_select on public.recurring_charges for select to authenticated
  using ((select private.is_mine(household_id, created_by)));
-- Sólo de una serie propia (la select de las series ya filtra por dueño).
create policy recurring_charges_insert on public.recurring_charges for insert to authenticated
  with check ((select private.is_member(household_id))
    and exists (select 1 from public.recurring_series s where s.id = series_id and s.household_id = household_id));
-- Sólo se enlaza con un movimiento propio.
create policy recurring_charges_update on public.recurring_charges for update to authenticated
  using ((select private.is_mine(household_id, created_by)))
  with check ((select private.is_mine(household_id, created_by))
    and (transaction_id is null or exists (select 1 from public.transactions t where t.id = transaction_id)));
create policy recurring_charges_delete on public.recurring_charges for delete to authenticated
  using ((select private.is_mine(household_id, created_by)));

create trigger recurring_charges_updated_at before update on public.recurring_charges
  for each row execute function private.touch_updated_at();

-- Confirmar un cargo: crea el movimiento y enlaza el cargo en la misma transacción.
-- Con los permisos de quien llama (RLS): la cuenta y el cargo tienen que ser suyos.
create function public.confirm_recurring_charge(
  charge uuid,
  account uuid,
  booked date,
  amount bigint,
  category uuid,
  label text
) returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  item public.recurring_charges;
  movement uuid;
begin
  select * into item from public.recurring_charges where id = charge for update;
  if item.id is null then
    raise exception 'El cargo no existe' using errcode = 'P0002';
  end if;
  if item.status <> 'pending' then
    raise exception 'El cargo ya no está pendiente' using errcode = '23514';
  end if;

  insert into public.transactions (household_id, account_id, category_id, booked_on, amount_minor, description)
  values (item.household_id, account, category, booked, amount, label)
  returning id into movement;

  update public.recurring_charges
    set status = 'confirmed', transaction_id = movement, amount_minor = amount
    where id = charge;
  return movement;
end;
$$;

revoke all on function public.confirm_recurring_charge(uuid, uuid, date, bigint, uuid, text) from public, anon;
grant execute on function public.confirm_recurring_charge(uuid, uuid, date, bigint, uuid, text) to authenticated;
