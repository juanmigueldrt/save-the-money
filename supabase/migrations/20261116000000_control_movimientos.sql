-- Fase B: control de cada movimiento y de cada cuenta.
--
-- Movimientos:
--   excluded     no cuenta en presupuesto, informes, flujo ni «gastado este mes»
--                (sí en el saldo de la cuenta y en el patrimonio, porque el dinero se movió).
--   reviewed_at  cuándo se marcó como revisado (null = sin revisar).
--   payee        a quién se paga o quién paga (persona o empresa), opcional.
--   tags         etiquetas en minúsculas, sin «#»: letras, números, «_» y «-», de 1 a 30, como mucho 10.
-- Cuentas:
--   is_default            la que sale elegida al apuntar un movimiento (una por persona).
--   include_in_net_worth  si suma en el patrimonio neto.
--
-- No cambia quién ve qué: las políticas de privacidad por usuario siguen igual.

create function private.valid_tags(tags text[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  select cardinality(tags) <= 10
     and coalesce(bool_and(t ~ '^[[:alnum:]_-]{1,30}$' and t = lower(t)), true)
  from unnest(tags) as t;
$$;

revoke all on function private.valid_tags(text[]) from public, anon;
grant execute on function private.valid_tags(text[]) to authenticated;

alter table public.transactions
  add column excluded boolean not null default false,
  add column reviewed_at timestamptz,
  add column payee text check (payee is null or char_length(trim(payee)) between 1 and 80),
  add column tags text[] not null default '{}' check (private.valid_tags(tags));

alter table public.accounts
  add column is_default boolean not null default false,
  add column include_in_net_worth boolean not null default true;

-- Una sola cuenta predeterminada por persona (las cuentas son de quien las crea).
create unique index accounts_one_default_per_user
  on public.accounts (created_by)
  where is_default and archived_at is null;

-- Para filtrar por etiqueta.
create index transactions_tags_idx on public.transactions using gin (tags);

grant insert (excluded, reviewed_at, payee, tags),
  update (excluded, reviewed_at, payee, tags)
  on public.transactions to authenticated;
grant insert (is_default, include_in_net_worth),
  update (is_default, include_in_net_worth)
  on public.accounts to authenticated;

-- Elegir otra cuenta predeterminada quita la marca a la anterior, en la misma operación.
create function private.single_default_account()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.is_default then
    update public.accounts
      set is_default = false
      where created_by = new.created_by and id <> new.id and is_default;
  end if;
  return new;
end;
$$;

create trigger accounts_single_default
  before insert or update of is_default on public.accounts
  for each row when (new.is_default)
  execute function private.single_default_account();
