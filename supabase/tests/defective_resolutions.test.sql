begin;

select plan(19);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('55555555-5555-5555-5555-555555555555', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'resolution-owner@example.test', 'not-used-by-test', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('66666666-6666-6666-6666-666666666666', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'resolution-employee@example.test', 'not-used-by-test', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

create temporary table resolution_context (business_id uuid, variant_id uuid, supplier_id uuid, lot_id uuid);
grant select, insert, update on resolution_context to authenticated, service_role;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', true);

insert into resolution_context (business_id) select public.create_business('Negocio de resoluciones');
update resolution_context set variant_id = public.create_catalog_product(
  business_id, 'Camisas', null, 'Camisa con resolución', '{}'::jsonb, '{}', 200.00, 160.00
);
update resolution_context set supplier_id = public.create_supplier(business_id, 'Distribuidor de resoluciones');

select public.create_business_invitation(
  '55555555-5555-5555-5555-555555555555', (select business_id from resolution_context),
  '66666666-6666-6666-6666-666666666666', 'resolution-employee@example.test',
  '60000000-0000-4000-8000-000000000001'
);
select set_config('request.jwt.claim.sub', '66666666-6666-6666-6666-666666666666', true);
select public.accept_business_invitation((select membership_id from public.business_invitations where request_id = '60000000-0000-4000-8000-000000000001'));
select set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', true);

select public.confirm_purchase(
  (select business_id from resolution_context),
  public.record_purchase(
    (select business_id from resolution_context), (select supplier_id from resolution_context), 'cash', null, now(), 500.00,
    jsonb_build_array(jsonb_build_object('variant_id', (select variant_id from resolution_context), 'quantity', 5, 'unit_cost', 100.00)),
    '60000000-0000-4000-8000-000000000002'
  ),
  '60000000-0000-4000-8000-000000000003'
);
update resolution_context set lot_id = (select id from public.inventory_lots where variant_id = resolution_context.variant_id);

select set_config('request.jwt.claim.sub', '66666666-6666-6666-6666-666666666666', true);
select lives_ok(
  $$ select public.report_defective_product((select business_id from resolution_context), (select variant_id from resolution_context), (select supplier_id from resolution_context), 1, 'Se puede vender tras revisión', '60000000-0000-4000-8000-000000000004') $$,
  'el empleado registra un defectuoso'
);
select lives_ok(
  $$ select public.record_defective_product_resolution((select business_id from resolution_context), (select id from public.defective_products where request_id = '60000000-0000-4000-8000-000000000004'), null, 'returned_to_stock', 'La prenda no tenía defecto', null, null, '60000000-0000-4000-8000-000000000005') $$,
  'el empleado registra el proceso de retorno a disponible'
);
select throws_ok(
  $$ select public.confirm_defective_product_resolution((select business_id from resolution_context), (select id from public.defective_product_resolutions where request_id = '60000000-0000-4000-8000-000000000005'), '60000000-0000-4000-8000-000000000006') $$,
  'P0001', 'Solo el dueño puede confirmar una resolución sin reemplazo.',
  'el empleado no confirma una resolución sin reemplazo'
);

select set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', true);
select lives_ok(
  $$ select public.confirm_defective_product_resolution((select business_id from resolution_context), (select id from public.defective_product_resolutions where request_id = '60000000-0000-4000-8000-000000000005'), '60000000-0000-4000-8000-000000000007') $$,
  'el dueño confirma el retorno a disponible'
);
select is(
  (select sum(quantity_delta) from public.inventory_movements where business_id = (select business_id from resolution_context) and variant_id = (select variant_id from resolution_context) and inventory_state = 'available'),
  5::bigint, 'returned_to_stock restaura la unidad al lote original'
);
select is(
  (select lot_id from public.defective_product_resolution_lots where resolution_id = (select id from public.defective_product_resolutions where request_id = '60000000-0000-4000-8000-000000000005')),
  (select lot_id from resolution_context), 'la resolución usa el lote original del defectuoso'
);
select ok(
  (select purchase_id is not null from public.defective_product_resolution_lots where resolution_id = (select id from public.defective_product_resolutions where request_id = '60000000-0000-4000-8000-000000000005')),
  'la resolución conserva la referencia explícita a la compra original'
);
select is(
  public.confirm_defective_product_resolution((select business_id from resolution_context), (select id from public.defective_product_resolutions where request_id = '60000000-0000-4000-8000-000000000005'), '60000000-0000-4000-8000-000000000008'),
  (select id from public.defective_product_resolutions where request_id = '60000000-0000-4000-8000-000000000005'),
  'un reintento de confirmación no duplica movimientos'
);

select public.report_defective_product((select business_id from resolution_context), (select variant_id from resolution_context), (select supplier_id from resolution_context), 1, 'Crédito acordado', '60000000-0000-4000-8000-000000000009');
select public.deliver_defective_product((select business_id from resolution_context), (select id from public.defective_products where request_id = '60000000-0000-4000-8000-000000000009'), '60000000-0000-4000-8000-000000000010');
select public.record_defective_product_resolution((select business_id from resolution_context), (select id from public.defective_products where request_id = '60000000-0000-4000-8000-000000000009'), (select supplier_id from resolution_context), 'supplier_credit', 'Crédito confirmado por distribuidor', 75.00, 'evidence/credit.pdf', '60000000-0000-4000-8000-000000000011');
select lives_ok(
  $$ select public.confirm_defective_product_resolution((select business_id from resolution_context), (select id from public.defective_product_resolutions where request_id = '60000000-0000-4000-8000-000000000011'), '60000000-0000-4000-8000-000000000012') $$,
  'un crédito de distribuidor se confirma por el dueño'
);
select is((select amount from public.supplier_credits), 75.00::numeric, 'el crédito se registra separado de abonos');
select is((select balance from public.get_supplier_balances((select business_id from resolution_context))), -75.00::numeric, 'el crédito puede dejar saldo a favor del distribuidor');

select public.report_defective_product((select business_id from resolution_context), (select variant_id from resolution_context), (select supplier_id from resolution_context), 1, 'Reembolso acordado', '60000000-0000-4000-8000-000000000013');
select public.record_defective_product_resolution((select business_id from resolution_context), (select id from public.defective_products where request_id = '60000000-0000-4000-8000-000000000013'), (select supplier_id from resolution_context), 'supplier_refund', 'Reembolso fuera de caja de ventas', 50.00, null, '60000000-0000-4000-8000-000000000014');
select lives_ok(
  $$ select public.confirm_defective_product_resolution((select business_id from resolution_context), (select id from public.defective_product_resolutions where request_id = '60000000-0000-4000-8000-000000000014'), '60000000-0000-4000-8000-000000000015') $$,
  'un reembolso se confirma sin movimiento de caja de ventas'
);
select is((select count(*) from public.supplier_refunds), 1::bigint, 'el reembolso queda registrado por separado');
select is((select count(*) from public.cash_movements), 0::bigint, 'el reembolso no afecta automáticamente la caja de ventas');

select public.report_defective_product((select business_id from resolution_context), (select variant_id from resolution_context), null, 1, 'Desecho autorizado', '60000000-0000-4000-8000-000000000016');
select public.record_defective_product_resolution((select business_id from resolution_context), (select id from public.defective_products where request_id = '60000000-0000-4000-8000-000000000016'), null, 'accepted_loss', 'Desecho por daño irreversible', null, null, '60000000-0000-4000-8000-000000000017');
select lives_ok(
  $$ select public.confirm_defective_product_resolution((select business_id from resolution_context), (select id from public.defective_product_resolutions where request_id = '60000000-0000-4000-8000-000000000017'), '60000000-0000-4000-8000-000000000018') $$,
  'la pérdida aceptada saca definitivamente la unidad'
);
select is((select status::text from public.defective_products where request_id = '60000000-0000-4000-8000-000000000016'), 'resolved', 'la pérdida no deja el producto apartado');

select set_config('request.jwt.claim.sub', '66666666-6666-6666-6666-666666666666', true);
select public.report_defective_product((select business_id from resolution_context), (select variant_id from resolution_context), null, 1, 'Reemplazo recibido', '60000000-0000-4000-8000-000000000019');
select public.record_defective_product_resolution((select business_id from resolution_context), (select id from public.defective_products where request_id = '60000000-0000-4000-8000-000000000019'), null, 'replacement', 'Reemplazo físico recibido', null, null, '60000000-0000-4000-8000-000000000020');
select lives_ok(
  $$ select public.confirm_defective_product_resolution((select business_id from resolution_context), (select id from public.defective_product_resolutions where request_id = '60000000-0000-4000-8000-000000000020'), '60000000-0000-4000-8000-000000000021') $$,
  'el empleado puede confirmar la resolución con reemplazo'
);
select is((select status::text from public.defective_products where request_id = '60000000-0000-4000-8000-000000000019'), 'resolved', 'el reemplazo también deja el caso resuelto');

select throws_ok(
  $$ select public.record_defective_product_resolution('77777777-7777-7777-7777-777777777777', (select id from public.defective_products limit 1), null, 'accepted_loss', 'Intento cruzado', null, null, '60000000-0000-4000-8000-000000000022') $$,
  'P0001', 'No tienes permiso para registrar la resolución de un defectuoso.',
  'un miembro no puede registrar resoluciones en otro negocio'
);

select * from finish();
rollback;
