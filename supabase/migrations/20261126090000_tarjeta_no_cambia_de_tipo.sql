-- Una cuenta con condiciones de tarjeta no puede dejar de ser tarjeta.
--
-- La comprobación de 20261109000000 sólo corre al insertar las condiciones, así que se podía
-- cambiar el tipo de la cuenta (accounts.kind sí se puede actualizar) y las condiciones quedaban
-- colgando de una cuenta corriente. Esto lo rechaza en el servidor: no borra nada.
--
-- Sólo se mira cuando el tipo cambia a algo que no es tarjeta, así que no toca filas existentes
-- ni bloquea renombrar o editar otros datos de una cuenta que ya esté inconsistente.
-- Cambiar a tarjeta (o crear una tarjeta con condiciones) sigue igual.

create function private.check_card_kind_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if exists (select 1 from public.credit_cards c where c.account_id = new.id) then
    raise exception 'la cuenta tiene condiciones de tarjeta de crédito y no puede cambiar de tipo'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke execute on function private.check_card_kind_change() from public;

create trigger accounts_card_kind before update of kind on public.accounts
  for each row when (old.kind is distinct from new.kind and new.kind <> 'credit_card')
  execute function private.check_card_kind_change();
