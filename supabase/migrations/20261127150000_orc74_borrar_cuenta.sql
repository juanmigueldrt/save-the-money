-- ORC-74: borrar mi cuenta y todos mis datos desde la app.
--
-- Las tiendas de Apple y Google lo exigen cuando la app deja crear cuentas. Basta con borrar la fila de
-- auth.users; el resto ya está resuelto por las claves foráneas y los triggers de ORC-56 y ORC-59:
--
--   * todo lo que creó, en todos sus hogares (created_by ... on delete cascade);
--   * su perfil, su historial de crédito, su calendario de cobro y sus intentos de invitación (user_id);
--   * sus membresías: un hogar donde era el propietario pasa al miembro más antiguo, y un hogar que se
--     queda sin miembros se borra;
--   * sus plazos de exportación pendientes, si le habían quitado de algún hogar.
--
-- La app pide antes la contraseña actual (vuelve a iniciar sesión con ella): aquí sólo se comprueba que hay sesión.

create function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  -- Sólo la propia: no hay argumento con el que señalar a otro usuario.
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
