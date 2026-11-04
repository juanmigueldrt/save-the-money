-- Arreglo: "Borrar datos y empezar de cero" fallaba con una tarjeta que tiene cuenta de pago.
--
-- Al borrar las cuentas, la clave foránea pone a null pay_from_account_id con un UPDATE
-- sobre credit_cards. Ese UPDATE disparaba la comprobación "la cuenta es una tarjeta",
-- y si la cuenta de la tarjeta ya se había borrado en la misma orden, fallaba
-- ("la cuenta no es una tarjeta de crédito") y no se borraba nada.
-- account_id no se puede cambiar después de crear la fila (no hay permiso de UPDATE en esa
-- columna), así que basta con comprobarlo al crearla.

drop trigger credit_cards_kind on public.credit_cards;

create trigger credit_cards_kind before insert on public.credit_cards
  for each row execute function private.check_credit_card_account();
