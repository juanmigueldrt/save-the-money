-- Privacidad dentro del hogar: cada miembro ve y toca solo lo suyo. Datos inventados.
begin;
create extension if not exists pgtap with schema extensions;

select plan(16);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@savethemoney.invalid', '{"username":"ana"}'),
  ('00000000-0000-0000-0000-00000000000b', 'bruno@savethemoney.invalid', '{"username":"bruno"}');

create function pg_temp.login(user_id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', user_id, 'role', 'authenticated')::text, true);
$$;

-- Ana crea el hogar e invita a Bruno.
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
create temp table hogar on commit drop as select * from public.create_household('Casa de prueba');
create temp table invitacion on commit drop as select * from public.create_invite((select id from hogar));
create temp table ids (name text primary key, id uuid) on commit drop;
grant select on hogar, invitacion to authenticated;
grant select, insert on ids to authenticated;

with x as (insert into public.accounts (household_id, name) select id, 'Cuenta de Ana' from hogar returning id)
insert into ids select 'cuenta_ana', id from x;
insert into public.transactions (household_id, account_id, booked_on, amount_minor, description)
  select h.id, i.id, '2026-11-02', -4500, 'Compra de Ana' from hogar h, ids i where i.name = 'cuenta_ana';
insert into ids select 'cat_ana', id from public.categories where name = 'Supermercado';
select public.save_budget((select id from hogar), '2026-11-01', 200000, 50::smallint, 30::smallint, 20::smallint);

select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select public.accept_invite((select code from invitacion));

-- Bruno -------------------------------------------------------------------------------
select is((select count(*)::int from public.accounts), 0, 'Bruno no ve las cuentas de Ana');
select is((select count(*)::int from public.transactions), 0, 'ni sus movimientos');
select is((select count(*)::int from public.budgets), 0, 'ni su presupuesto');
select is((select count(*)::int from public.categories), 20, 'Bruno tiene sus propias categorías de partida');
select is(
  (select count(*)::int from public.categories where id = (select id from ids where name = 'cat_ana')),
  0, 'y no ve las de Ana'
);
select throws_ok(
  $$ insert into public.transactions (household_id, account_id, booked_on, amount_minor, description)
     select h.id, i.id, '2026-11-03', -100, 'Truco' from hogar h, ids i where i.name = 'cuenta_ana' $$,
  '42501', null, 'Bruno no apunta en la cuenta de Ana'
);

with x as (insert into public.accounts (household_id, name) select id, 'Cuenta de Bruno' from hogar returning id)
insert into ids select 'cuenta_bruno', id from x;
select throws_ok(
  $$ insert into public.transactions (household_id, account_id, category_id, booked_on, amount_minor, description)
     select h.id, b.id, a.id, '2026-11-03', -100, 'Con categoría ajena'
     from hogar h, ids b, ids a where b.name = 'cuenta_bruno' and a.name = 'cat_ana' $$,
  '42501', null, 'ni usa una categoría de Ana'
);
select lives_ok(
  $$ insert into public.transactions (household_id, account_id, booked_on, amount_minor, description)
     select h.id, i.id, '2026-11-03', -2000, 'Compra de Bruno' from hogar h, ids i where i.name = 'cuenta_bruno' $$,
  'Bruno apunta en su cuenta'
);
select lives_ok(
  $$ select public.save_budget((select id from hogar), '2026-11-01', 150000, 50::smallint, 30::smallint, 20::smallint) $$,
  'Bruno guarda su presupuesto del mismo mes'
);
select is((select count(*)::int from public.budgets), 1, 'y solo ve el suyo');
with borrados as (delete from public.accounts returning 1)
select is((select count(*)::int from borrados), 1, 'Bruno solo puede borrar su cuenta');
select lives_ok($$ select public.reset_household((select id from hogar)) $$, 'Bruno empieza de cero');

-- Ana -----------------------------------------------------------------------------------
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select is((select count(*)::int from public.accounts), 1, 'Ana sigue con su cuenta');
select is((select description from public.transactions), 'Compra de Ana', 'y ve solo su movimiento');
select is((select expected_income_minor::int from public.budgets), 200000, 'y su presupuesto no ha cambiado');
select is(
  (select count(*)::int from public.categories where id = (select id from ids where name = 'cat_ana')),
  1, 'el borrado de Bruno no toca las categorías de Ana'
);

select * from finish();
rollback;
