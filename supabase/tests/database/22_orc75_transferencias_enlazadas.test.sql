-- Transferencias como una sola operación (ORC-75): las dos patas se cambian y se borran juntas. Datos inventados.
begin;
create extension if not exists pgtap with schema extensions;

select plan(26);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@savethemoney.invalid', '{"username":"ana"}'),
  ('00000000-0000-0000-0000-00000000000c', 'carla@savethemoney.invalid', '{"username":"carla"}');

create function pg_temp.login(user_id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', user_id, 'role', 'authenticated')::text, true);
$$;

select pg_temp.login('00000000-0000-0000-0000-00000000000a');
create temp table hogar on commit drop as select * from public.create_household('Casa de prueba');
create temp table ids (name text primary key, id uuid) on commit drop;
grant select on hogar to authenticated;
grant select, insert on ids to authenticated;

with x as (insert into public.accounts (household_id, name, opening_balance_minor)
           select id, 'Corriente', 100000 from hogar returning id)
insert into ids select 'corriente', id from x;
with x as (insert into public.accounts (household_id, name) select id, 'Ahorro' from hogar returning id)
insert into ids select 'ahorro', id from x;
with x as (insert into public.accounts (household_id, name) select id, 'Hucha' from hogar returning id)
insert into ids select 'hucha', id from x;

-- Una transferencia de prueba de `origen` a `destino` con la categoría de transferencia.
create function pg_temp.transferir(transfer uuid, origen text, destino text, importe bigint)
returns setof public.transactions language sql as $$
  select * from public.create_transfer(
    transfer, (select id from hogar), (select id from ids where name = origen), (select id from ids where name = destino),
    '2026-11-04', importe, (select c.id from public.categories c where c.kind = 'transfer' limit 1), 'Al ahorro', 'Al ahorro');
$$;

-- Las dos patas de una transferencia: "cuenta importe día" de la salida y de la entrada.
create function pg_temp.patas(transfer uuid) returns text language sql as $$
  select string_agg(format('%s %s %s', (select name from ids where id = t.account_id), t.amount_minor, t.booked_on), ' | '
                    order by t.transfer_out desc)
  from public.transactions t where t.transfer_id = transfer;
$$;

-- Permisos ------------------------------------------------------------------------------
select is(
  (select format('%s %s',
     has_function_privilege('anon', 'public.delete_transfer(uuid)', 'execute'),
     has_function_privilege('authenticated', 'public.delete_transfer(uuid)', 'execute'))),
  'f t', 'solo quien ha entrado puede borrar transferencias');
select is(
  (select string_agg(format('%s %s', proname, prosecdef), ' | ' order by proname) from pg_proc
   where proname in ('delete_transfer', 'keep_transfer_legs_together')),
  'delete_transfer f | keep_transfer_legs_together f', 'las dos funciones corren con los permisos de quien llama');
select is(
  (select format('%s %s', p.proconfig = array['search_path=""'], has_function_privilege('authenticated', p.oid, 'execute'))
   from pg_proc p where p.proname = 'keep_transfer_legs_together'),
  't f', 'el trigger tiene el search_path vacío y nadie lo llama directamente');

-- Cambiar una pata cambia la otra -------------------------------------------------------
select lives_ok(
  $$ select pg_temp.transferir('30000000-0000-0000-0000-000000000001', 'corriente', 'ahorro', 30000) $$,
  'Ana pasa 300 € al ahorro');
select lives_ok(
  $$ update public.transactions set amount_minor = 25000, booked_on = '2026-11-06', notes = 'Solo en la entrada'
     where transfer_id = '30000000-0000-0000-0000-000000000001' and not transfer_out $$,
  'Ana cambia el importe y el día de la entrada');
select is(
  pg_temp.patas('30000000-0000-0000-0000-000000000001'),
  'corriente -25000 2026-11-06 | ahorro 25000 2026-11-06', 'la salida cambia igual');
select is(
  (select string_agg(coalesce(notes, '-'), ' | ' order by transfer_out desc)
   from public.transactions where transfer_id = '30000000-0000-0000-0000-000000000001'),
  '- | Solo en la entrada', 'lo demás de la otra pata no se toca');
select is(
  (select string_agg(format('%s %s', (select name from ids where id = b.account_id), b.balance_minor), ' | '
                     order by b.balance_minor desc)
   from public.account_balances b),
  'corriente 75000 | ahorro 25000 | hucha 0', 'y los saldos cuadran');

select lives_ok(
  $$ select public.update_movement(t.id, t.updated_at, t.account_id, t.category_id, '2026-11-07', -20000, t.description,
                                   t.notes, t.excluded, t.reviewed_at, t.payee, t.tags)
     from public.transactions t where t.transfer_id = '30000000-0000-0000-0000-000000000001' and t.transfer_out $$,
  'también al cambiar la salida con update_movement');
select is(
  pg_temp.patas('30000000-0000-0000-0000-000000000001'),
  'corriente -20000 2026-11-07 | ahorro 20000 2026-11-07', 'la entrada cambia igual');

select lives_ok(
  $$ update public.transactions set account_id = (select id from ids where name = 'hucha')
     where transfer_id = '30000000-0000-0000-0000-000000000001' and not transfer_out $$,
  'la entrada se puede llevar a otra cuenta');
select throws_ok(
  $$ update public.transactions set amount_minor = 20000
     where transfer_id = '30000000-0000-0000-0000-000000000001' and transfer_out $$,
  '23514', null, 'la salida no se vuelve positiva');
select throws_ok(
  $$ update public.transactions set amount_minor = -20000
     where transfer_id = '30000000-0000-0000-0000-000000000001' and not transfer_out $$,
  '23514', null, 'ni la entrada negativa');
select throws_ok(
  $$ update public.transactions set account_id = (select id from ids where name = 'corriente')
     where transfer_id = '30000000-0000-0000-0000-000000000001' and not transfer_out $$,
  '23514', null, 'ni las dos patas quedan en la misma cuenta');
select is(
  pg_temp.patas('30000000-0000-0000-0000-000000000001'),
  'corriente -20000 2026-11-07 | hucha 20000 2026-11-07', 'después de los fallos no ha cambiado nada');

-- Otra persona no cambia ni borra nada ---------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
select lives_ok(
  $$ select public.delete_transfer('30000000-0000-0000-0000-000000000001') $$,
  'Carla puede llamar a delete_transfer con el identificador de Ana');
update public.transactions set amount_minor = 1 where transfer_id = '30000000-0000-0000-0000-000000000001';
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is(
  pg_temp.patas('30000000-0000-0000-0000-000000000001'),
  'corriente -20000 2026-11-07 | hucha 20000 2026-11-07', 'pero la transferencia de Ana sigue igual');

-- Borrar ----------------------------------------------------------------------------------
select lives_ok(
  $$ select public.delete_transfer('30000000-0000-0000-0000-000000000001') $$,
  'Ana borra la transferencia');
select is(
  (select count(*)::int from public.transactions where transfer_id = '30000000-0000-0000-0000-000000000001'),
  0, 'se borran las dos patas');
select lives_ok(
  $$ select public.delete_transfer('30000000-0000-0000-0000-000000000001') $$,
  'repetir la petición no falla');

-- La otra pata ya no existe ---------------------------------------------------------------
select count(*) from pg_temp.transferir('30000000-0000-0000-0000-000000000002', 'corriente', 'ahorro', 5000);
-- Una versión anterior de la app borra solo la entrada.
delete from public.transactions where transfer_id = '30000000-0000-0000-0000-000000000002' and not transfer_out;
select lives_ok(
  $$ update public.transactions set amount_minor = -4000 where transfer_id = '30000000-0000-0000-0000-000000000002' $$,
  'la pata que queda se cambia como un movimiento normal');
select lives_ok(
  $$ select public.delete_transfer('30000000-0000-0000-0000-000000000002') $$,
  'y se borra');
select is(
  (select count(*)::int from public.transactions where transfer_id = '30000000-0000-0000-0000-000000000002'),
  0, 'sin dejar nada');

-- Borrar una cuenta no se lleva la pata de la otra cuenta ---------------------------------
select count(*) from pg_temp.transferir('30000000-0000-0000-0000-000000000003', 'corriente', 'hucha', 1000);
delete from public.accounts where id = (select id from ids where name = 'hucha');
select is(
  pg_temp.patas('30000000-0000-0000-0000-000000000003'),
  'corriente -1000 2026-11-04', 'la salida se queda en la corriente, como antes');

-- Las transferencias de antes de ORC-62 (sin transfer_id) siguen igual ---------------------
insert into public.transactions (household_id, account_id, booked_on, amount_minor, description)
select h.id, i.id, '2026-11-01', case when i.name = 'corriente' then -700 else 700 end, 'Transferencia antigua'
from hogar h, ids i where i.name in ('corriente', 'ahorro');
update public.transactions set amount_minor = -900 where description = 'Transferencia antigua' and amount_minor < 0;
select is(
  (select string_agg(amount_minor::text, ' ' order by amount_minor) from public.transactions where description = 'Transferencia antigua'),
  '-900 700', 'cambiar una no toca la otra: no se adivina qué filas van juntas');
select lives_ok(
  $$ delete from public.transactions where description = 'Transferencia antigua' and amount_minor < 0 $$,
  'y se borran una a una, como antes');

select * from finish();
rollback;
