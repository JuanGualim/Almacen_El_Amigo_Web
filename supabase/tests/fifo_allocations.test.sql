begin;

select plan(26);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '33333333-3333-3333-3333-333333333333',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'fifo-owner@example.test', 'not-used-by-test', now(),
  '{"provider":"email","providers":["email"]}', '{"display_name":"Dueño FIFO"}', now(), now()
);

create temporary table fifo_context (
  business_id uuid,
  variant_id uuid,
  second_variant_id uuid,
  supplier_id uuid,
  first_purchase_id uuid,
  second_purchase_id uuid,
  credit_purchase_id uuid,
  cash_session_id uuid,
  sale_id uuid,
  cancellation_id uuid
);
grant select, insert, update on fifo_context to authenticated, service_role;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);

insert into fifo_context (business_id)
select public.create_business('Negocio FIFO de prueba');

update fifo_context
set variant_id = public.create_catalog_product(
  business_id, 'Pantalones', null, 'Pantalón FIFO', '{}'::jsonb,
  '{"size":"32","color":"Azul"}'::jsonb, 185.00, 160.00
);

update fifo_context
set second_variant_id = public.create_catalog_product(
  business_id, 'Camisas', null, 'Camisa de salida', '{}'::jsonb,
  '{"size":"M","color":"Blanca"}'::jsonb, 200.00, 170.00
);

update fifo_context
set supplier_id = public.create_supplier(business_id, 'Distribuidor FIFO');

update fifo_context
set first_purchase_id = public.record_purchase(
  business_id, supplier_id, 'cash', null, now() - interval '2 days', 100.00,
  jsonb_build_array(jsonb_build_object('variant_id', variant_id, 'quantity', 2, 'unit_cost', 50.00)),
  '30000000-0000-4000-8000-000000000001'
);

select lives_ok(
  $$ select public.confirm_purchase(
    (select business_id from fifo_context),
    (select first_purchase_id from fifo_context),
    '30000000-0000-4000-8000-000000000002'
  ) $$,
  'la primera compra crea su lote FIFO'
);

update fifo_context
set second_purchase_id = public.record_purchase(
  business_id, supplier_id, 'cash', null, now() - interval '1 day', 180.00,
  jsonb_build_array(jsonb_build_object('variant_id', variant_id, 'quantity', 3, 'unit_cost', 60.00)),
  '30000000-0000-4000-8000-000000000003'
);

select lives_ok(
  $$ select public.confirm_purchase(
    (select business_id from fifo_context),
    (select second_purchase_id from fifo_context),
    '30000000-0000-4000-8000-000000000004'
  ) $$,
  'la segunda compra crea el segundo lote FIFO'
);

update fifo_context
set cash_session_id = public.open_cash_register(
  business_id, 0, null, '30000000-0000-4000-8000-000000000005'
);

update fifo_context
set sale_id = public.confirm_sale(
  business_id, cash_session_id, 'cash',
  jsonb_build_array(jsonb_build_object('variant_id', variant_id, 'quantity', 4, 'unit_price', 185.00)),
  '30000000-0000-4000-8000-000000000006'
);

select is(
  (select count(*) from public.inventory_lot_allocations allocation
   join public.inventory_movements movement on movement.id = allocation.inventory_movement_id
   where movement.source_type = 'sale_line' and allocation.allocation_kind = 'consumption'),
  2::bigint,
  'una venta que cruza lotes crea dos asignaciones de consumo'
);

select is(
  (select allocation.quantity from public.inventory_lot_allocations allocation
   join public.inventory_lots lot on lot.id = allocation.lot_id
   join public.purchase_lines line on line.id = lot.purchase_line_id
   where line.purchase_id = (select first_purchase_id from fifo_context)
     and allocation.allocation_kind = 'consumption'),
  2,
  'FIFO consume por completo el lote más antiguo'
);

select is(
  (select allocation.quantity from public.inventory_lot_allocations allocation
   join public.inventory_lots lot on lot.id = allocation.lot_id
   join public.purchase_lines line on line.id = lot.purchase_line_id
   where line.purchase_id = (select second_purchase_id from fifo_context)
     and allocation.allocation_kind = 'consumption'),
  2,
  'FIFO continúa con el segundo lote'
);

select is(
  public.confirm_sale(
    (select business_id from fifo_context), (select cash_session_id from fifo_context), 'cash',
    jsonb_build_array(jsonb_build_object('variant_id', (select variant_id from fifo_context), 'quantity', 4, 'unit_price', 185.00)),
    '30000000-0000-4000-8000-000000000006'
  ),
  (select sale_id from fifo_context),
  'un reintento de venta devuelve la venta existente'
);

select is(
  (select sum(quantity_delta) from public.inventory_movements
   where business_id = (select business_id from fifo_context)
     and variant_id = (select variant_id from fifo_context)
     and inventory_state = 'available'),
  1::bigint,
  'la venta reduce la existencia exactamente una vez'
);

select lives_ok(
  $$ select public.report_defective_product(
    (select business_id from fifo_context), (select variant_id from fifo_context),
    (select supplier_id from fifo_context), 1, 'Costura defectuosa',
    '30000000-0000-4000-8000-000000000007'
  ) $$,
  'un defectuoso se reclasifica desde un lote disponible'
);

select is(
  (select sum(quantity_delta) from public.inventory_movements
   where business_id = (select business_id from fifo_context)
     and variant_id = (select variant_id from fifo_context)
     and inventory_state = 'defective_pending'),
  1::bigint,
  'el defectuoso queda pendiente y no desaparece'
);

select is(
  (select count(*) from public.inventory_lot_reclassifications
   where business_id = (select business_id from fifo_context)),
  1::bigint,
  'la reclasificación conserva el lote concreto'
);

update fifo_context
set cancellation_id = public.cancel_sale(
  business_id, sale_id, cash_session_id, 'Venta anulada durante la prueba',
  '30000000-0000-4000-8000-000000000008'
);

select is(
  (select count(*) from public.inventory_lot_allocations
   where allocation_kind = 'reversal'
     and source_type = 'sale_cancellation_line'),
  2::bigint,
  'cancelar una venta crea reversiones ligadas a sus consumos originales'
);

select is(
  (select sum(quantity_delta) from public.inventory_movements
   where business_id = (select business_id from fifo_context)
     and variant_id = (select variant_id from fifo_context)
     and inventory_state = 'available'),
  4::bigint,
  'la cancelación restaura inventario sin restaurar el defectuoso'
);

select is(
  public.cancel_sale(
    (select business_id from fifo_context), (select sale_id from fifo_context),
    (select cash_session_id from fifo_context), 'Venta anulada durante la prueba',
    '30000000-0000-4000-8000-000000000008'
  ),
  (select cancellation_id from fifo_context),
  'un reintento de cancelación no duplica reversiones'
);

select lives_ok(
  $$ select public.confirm_sale(
    (select business_id from fifo_context), (select cash_session_id from fifo_context), 'cash',
    jsonb_build_array(jsonb_build_object('variant_id', (select variant_id from fifo_context), 'quantity', 1, 'unit_price', 185.00)),
    '30000000-0000-4000-8000-000000000019'
  ) $$,
  'una venta nueva deja asignaciones disponibles para un cambio con venta original'
);

select lives_ok(
  $$ select public.record_product_exchange(
    (select business_id from fifo_context), null,
    (select id from public.sales where request_id = '30000000-0000-4000-8000-000000000019'),
    (select variant_id from fifo_context), 1, (select variant_id from fifo_context), 1,
    null, null, 'Cambio de talla de la misma variante',
    '30000000-0000-4000-8000-000000000020'
  ) $$,
  'un cambio con venta original revierte la asignación original antes de entregar'
);

select throws_ok(
  $$ select public.confirm_sale(
    (select business_id from fifo_context), (select cash_session_id from fifo_context), 'cash',
    jsonb_build_array(jsonb_build_object('variant_id', (select variant_id from fifo_context), 'quantity', 5, 'unit_price', 185.00)),
    '30000000-0000-4000-8000-000000000021'
  ) $$,
  'P0001',
  'No hay lotes disponibles suficientes para completar la operación.',
  'FIFO rechaza una salida mayor a los lotes disponibles'
);

select lives_ok(
  $$ select public.record_purchase(
    (select business_id from fifo_context), (select supplier_id from fifo_context), 'cash', null, now(), 40.00,
    jsonb_build_array(jsonb_build_object('variant_id', (select second_variant_id from fifo_context), 'quantity', 1, 'unit_cost', 40.00)),
    '30000000-0000-4000-8000-000000000022'
  ) $$,
  'se registra una compra cancelable sin dependencias'
);

select lives_ok(
  $$ select public.confirm_purchase(
    (select business_id from fifo_context),
    (select id from public.purchases where request_id = '30000000-0000-4000-8000-000000000022'),
    '30000000-0000-4000-8000-000000000023'
  ) $$,
  'se confirma la compra cancelable'
);

select lives_ok(
  $$ select public.cancel_purchase(
    (select business_id from fifo_context),
    (select id from public.purchases where request_id = '30000000-0000-4000-8000-000000000022'),
    'Factura recibida por error', '30000000-0000-4000-8000-000000000024'
  ) $$,
  'una compra sin dependencias se cancela mediante compensación'
);

select is(
  (select status::text from public.purchases where request_id = '30000000-0000-4000-8000-000000000022'),
  'cancelled',
  'la compra cancelada conserva su documento histórico'
);

update fifo_context
set credit_purchase_id = public.record_purchase(
  business_id, supplier_id, 'credit', null, now(), 0,
  jsonb_build_array(jsonb_build_object('variant_id', variant_id, 'quantity', 1, 'unit_cost', 40.00)),
  '30000000-0000-4000-8000-000000000025'
);

select lives_ok(
  $$ select public.confirm_purchase(
    (select business_id from fifo_context), (select credit_purchase_id from fifo_context),
    '30000000-0000-4000-8000-000000000026'
  ) $$,
  'se confirma una compra a crédito para probar aplicaciones'
);

select lives_ok(
  $$ select public.apply_supplier_payment_to_purchase(
    (select business_id from fifo_context),
    public.confirm_general_supplier_payment(
      (select business_id from fifo_context),
      public.record_general_supplier_payment(
        (select business_id from fifo_context), (select supplier_id from fifo_context), 40.00,
        'transfer', null, null, '30000000-0000-4000-8000-000000000027'
      ),
      '30000000-0000-4000-8000-000000000028'
    ),
    (select credit_purchase_id from fifo_context), 40.00,
    '30000000-0000-4000-8000-000000000029'
  ) $$,
  'un abono confirmado puede aplicarse a una compra'
);

select throws_ok(
  $$ select public.cancel_purchase(
    (select business_id from fifo_context), (select credit_purchase_id from fifo_context),
    'No debe cancelar con abono aplicado', '30000000-0000-4000-8000-000000000030'
  ) $$,
  'P0001',
  'La compra no puede cancelarse porque tiene abonos aplicados.',
  'un abono aplicado bloquea la cancelación directa de compra'
);

select lives_ok(
  $$ select public.deliver_defective_product(
    (select business_id from fifo_context),
    (select id from public.defective_products where request_id = '30000000-0000-4000-8000-000000000007'),
    '30000000-0000-4000-8000-000000000031'
  ) $$,
  'el dueño entrega al distribuidor los lotes defectuosos reclasificados'
);

select is(
  (select status::text from public.defective_products where request_id = '30000000-0000-4000-8000-000000000007'),
  'delivered',
  'la entrega conserva el defectuoso en estado entregado'
);

select lives_ok(
  $$ select public.replace_defective_product(
    (select business_id from fifo_context),
    (select id from public.defective_products where request_id = '30000000-0000-4000-8000-000000000007'),
    '30000000-0000-4000-8000-000000000032'
  ) $$,
  'el reemplazo entra como lote especial disponible y auditable'
);

select * from finish();
rollback;
