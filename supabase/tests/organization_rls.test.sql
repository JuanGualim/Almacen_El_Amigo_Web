begin;

select plan(31);

insert into auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '11111111-1111-1111-1111-111111111111',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'owner@example.test',
    'not-used-by-test',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Dueño de prueba"}',
    now(),
    now()
  ),
  (
    '22222222-2222-2222-2222-222222222222',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'employee@example.test',
    'not-used-by-test',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Empleado de prueba"}',
    now(),
    now()
  );

create temporary table test_context (
  first_business_id uuid,
  second_business_id uuid,
  invitation_id uuid,
  catalog_variant_id uuid,
  supplier_id uuid,
  first_purchase_id uuid,
  second_purchase_id uuid
);

grant select, insert, update on test_context to authenticated, service_role;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);

insert into test_context (first_business_id)
select public.create_business('Negocio Uno de Prueba');

select ok(
  exists (
    select 1 from public.profiles where user_id = '11111111-1111-1111-1111-111111111111'
  ),
  'crear un usuario de Auth crea su perfil público'
);

select is(
  (select count(*) from public.businesses),
  1::bigint,
  'el dueño ve su negocio'
);

select is(
  (select count(*) from public.business_memberships),
  1::bigint,
  'el dueño ve su membresía inicial'
);

select ok(
  public.has_business_permission(
    (select first_business_id from test_context),
    'payables.read'
  ),
  'el dueño tiene el permiso sensible de cuentas por pagar'
);

update test_context
set catalog_variant_id = public.create_catalog_product(
  first_business_id,
  'Camisas',
  'Manhattan',
  'Camisa lisa de manga larga',
  '{"design":"Liso"}'::jsonb,
  '{"color":"Blanca","size":"15"}'::jsonb,
  185.00,
  160.00
);

select ok(
  exists (
    select 1
    from public.product_variants variant
    join public.variant_current_prices price on price.variant_id = variant.id
    where variant.id = (select catalog_variant_id from test_context)
      and variant.internal_code like 'ALM-%-001'
      and price.suggested_price = 185.00
      and price.minimum_price = 160.00
  ),
  'crear un producto genera su primera variante y precios exactos'
);

select is(
  (
    select count(*)
    from public.variant_price_history
    where variant_id = (select catalog_variant_id from test_context)
  ),
  2::bigint,
  'los precios iniciales quedan en el historial inmutable'
);

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);

update test_context
set second_business_id = public.create_business('Negocio Dos de Prueba');

select is(
  (select count(*) from public.businesses),
  1::bigint,
  'el segundo dueño solo ve su propio negocio'
);

select ok(
  not exists (
    select 1
    from public.businesses
    where id = (select first_business_id from test_context)
  ),
  'un negocio no se filtra a otro usuario'
);

select ok(
  not exists (
    select 1
    from public.business_memberships
    where business_id = (select first_business_id from test_context)
  ),
  'las membresías de otro negocio no se filtran'
);

select ok(
  not public.has_business_permission(
    (select first_business_id from test_context),
    'payables.read'
  ),
  'un usuario sin membresía no obtiene permisos del otro negocio'
);

select throws_ok(
  $$
    select *
    from public.get_catalog_variants((select first_business_id from test_context), null)
  $$,
  'P0001',
  'No tienes permiso para consultar el catálogo de este negocio.',
  'un usuario no puede consultar el catálogo de otro negocio'
);

set local role service_role;

select throws_ok(
  $$
    select public.create_business_invitation(
      '22222222-2222-2222-2222-222222222222',
      (select first_business_id from test_context),
      '11111111-1111-1111-1111-111111111111',
      'owner@example.test',
      '55555555-5555-4555-8555-555555555555'
    )
  $$,
  'P0001',
  'No tienes permiso para invitar personas a este negocio.',
  'un usuario sin permiso no puede invitar personas a otro negocio'
);

update test_context
set invitation_id = public.create_business_invitation(
  '11111111-1111-1111-1111-111111111111',
  first_business_id,
  '22222222-2222-2222-2222-222222222222',
  'employee@example.test',
  '33333333-3333-4333-8333-333333333333'
);

select ok(
  public.create_business_invitation(
    '11111111-1111-1111-1111-111111111111',
    (select first_business_id from test_context),
    '22222222-2222-2222-2222-222222222222',
    'employee@example.test',
    '33333333-3333-4333-8333-333333333333'
  ) = (select invitation_id from test_context),
  'un reintento con la misma solicitud devuelve la invitación existente'
);

set local role authenticated;

select ok(
  exists (
    select 1
    from public.business_invitations invitation
    join public.business_memberships membership on membership.id = invitation.membership_id
    where invitation.id = (select invitation_id from test_context)
      and membership.business_id = (select first_business_id from test_context)
      and membership.user_id = '22222222-2222-2222-2222-222222222222'
      and membership.status = 'invited'
  ),
  'la invitación crea una membresía pendiente para el empleado'
);

select is(
  (select count(*) from public.get_my_pending_business_invitations()),
  1::bigint,
  'la persona invitada puede consultar solo su invitación pendiente'
);

select ok(
  public.accept_business_invitation(
    (
      select membership_id
      from public.business_invitations
      where id = (select invitation_id from test_context)
    )
  ) = (select first_business_id from test_context),
  'la persona invitada puede aceptar su propia invitación'
);

select ok(
  public.has_business_permission(
    (select first_business_id from test_context),
    'sales.create'
  )
  and exists (
    select 1
    from public.business_invitations
    where id = (select invitation_id from test_context)
      and status = 'accepted'
  ),
  'al aceptar, el empleado queda activo con sus permisos iniciales'
);

select ok(
  exists (
    select 1
    from public.get_catalog_variants((select first_business_id from test_context), 'Blanca') catalog
    where catalog.variant_id = (select catalog_variant_id from test_context)
      and catalog.suggested_price = 185.00
      and catalog.minimum_price = 160.00
  ),
  'el empleado autorizado puede buscar la variante y sus precios permitidos'
);

update test_context
set supplier_id = public.create_supplier(
  first_business_id,
  'Distribuidor de Prueba',
  'Contacto de prueba'
);

update test_context
set first_purchase_id = public.record_purchase(
  first_business_id,
  supplier_id,
  'credit',
  'FAC-001',
  now(),
  0,
  jsonb_build_array(jsonb_build_object(
    'variant_id', catalog_variant_id,
    'quantity', 2,
    'unit_cost', 80.00
  )),
  '66666666-6666-4666-8666-666666666666'
);

select ok(
  exists (
    select 1 from public.purchases
    where id = (select first_purchase_id from test_context)
      and status = 'pending_confirmation'
  )
  and not exists (
    select 1 from public.inventory_movements
    where source_id in (
      select id from public.purchase_lines where purchase_id = (select first_purchase_id from test_context)
    )
  ),
  'registrar una compra pendiente no altera el inventario'
);

select throws_ok(
  $$
    select public.confirm_purchase(
      (select first_business_id from test_context),
      (select first_purchase_id from test_context),
      '77777777-7777-4777-8777-777777777777'
    )
  $$,
  'P0001',
  'No tienes permiso para confirmar compras.',
  'un empleado no puede confirmar una compra sin permiso adicional'
);

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);

select lives_ok(
  $$
    select public.update_variant_prices(
      (select first_business_id from test_context),
      (select catalog_variant_id from test_context),
      190.00,
      160.00,
      'Revisión de etiqueta'
    )
  $$,
  'el dueño puede actualizar un precio vigente con motivo'
);

select ok(
  exists (
    select 1
    from public.variant_current_prices
    where variant_id = (select catalog_variant_id from test_context)
      and suggested_price = 190.00
      and minimum_price = 160.00
  )
  and (
    select count(*)
    from public.variant_price_history
    where variant_id = (select catalog_variant_id from test_context)
  ) = 3,
  'actualizar un precio conserva el anterior en el historial y no duplica el mínimo sin cambio'
);

select lives_ok(
  $$
    select public.confirm_purchase(
      (select first_business_id from test_context),
      (select first_purchase_id from test_context),
      '77777777-7777-4777-8777-777777777777'
    )
  $$,
  'el dueño confirma una compra pendiente'
);

select ok(
  exists (
    select 1 from public.inventory_lots lot
    join public.inventory_movements movement on movement.lot_id = lot.id
    where lot.purchase_line_id in (
      select id from public.purchase_lines where purchase_id = (select first_purchase_id from test_context)
    )
      and movement.quantity_delta = 2
      and movement.inventory_state = 'available'
  )
  and exists (
    select 1 from public.supplier_account_entries
    where purchase_id = (select first_purchase_id from test_context)
      and entry_type = 'purchase_charge'
      and amount = 160.00
  ),
  'confirmar la compra crea lote, movimiento y cargo trazable exactamente una vez'
);

update test_context
set second_purchase_id = public.record_purchase(
  first_business_id,
  supplier_id,
  'partial',
  'FAC-002',
  now(),
  20.00,
  jsonb_build_array(jsonb_build_object(
    'variant_id', catalog_variant_id,
    'quantity', 1,
    'unit_cost', 90.00
  )),
  '88888888-8888-4888-8888-888888888888'
);

select lives_ok(
  $$
    select public.confirm_purchase(
      (select first_business_id from test_context),
      (select second_purchase_id from test_context),
      '99999999-9999-4999-8999-999999999999'
    )
  $$,
  'el dueño confirma una compra parcial'
);

select ok(
  exists (
    select 1 from public.purchase_price_reviews
    where purchase_line_id in (
      select id from public.purchase_lines where purchase_id = (select second_purchase_id from test_context)
    )
      and previous_unit_cost = 80.00
      and current_unit_cost = 90.00
      and status = 'pending'
  ),
  'un costo mayor deja una revisión de precio pendiente'
);

select lives_ok(
  $$
    select public.resolve_purchase_price_review(
      (select first_business_id from test_context),
      (select id from public.purchase_price_reviews limit 1),
      'El dueño mantendrá el precio actual.'
    )
  $$,
  'el dueño puede resolver una revisión sin cambiar precios automáticamente'
);

select ok(
  exists (
    select 1 from public.purchase_price_reviews where status = 'resolved'
  )
  and exists (
    select 1 from public.audit_events
    where event_type = 'purchase_price_review.resolved'
  ),
  'la decisión sobre el precio queda auditada'
);

select is(
  (
    select available_quantity
    from public.get_inventory_variants((select first_business_id from test_context), null)
    where variant_id = (select catalog_variant_id from test_context)
  ),
  3::bigint,
  'la existencia se deriva de los movimientos confirmados'
);

select lives_ok(
  $$
    select public.set_supplier_active_status(
      (select first_business_id from test_context),
      (select supplier_id from test_context),
      false
    )
  $$,
  'el dueño puede desactivar un distribuidor sin borrar su historial'
);

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);

select throws_ok(
  $$
    select public.record_purchase(
      (select first_business_id from test_context),
      (select supplier_id from test_context),
      'cash',
      'FAC-003',
      now(),
      1.00,
      jsonb_build_array(jsonb_build_object(
        'variant_id', (select catalog_variant_id from test_context),
        'quantity', 1,
        'unit_cost', 1.00
      )),
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    )
  $$,
  'P0001',
  'El distribuidor no está activo en este negocio.',
  'una compra no puede registrarse contra un distribuidor inactivo'
);

select * from finish();

rollback;
