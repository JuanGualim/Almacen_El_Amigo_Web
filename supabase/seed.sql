-- Datos completamente ficticios para explorar la PWA local.
-- Se crean en un negocio independiente y nunca deben usarse fuera del entorno
-- local. Las credenciales se documentan en README únicamente como acceso demo.
begin;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  phone_change_token, reauthentication_token, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
) values
  ('d0000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'dueno.demo@almacen.test', extensions.crypt('Demo1234!', extensions.gen_salt('bf')), now(), '', '', '', '', '', '', '{"provider":"email","providers":["email"]}', '{"display_name":"Lucía Dueña (demo)"}', now(), now()),
  ('d0000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'empleado.demo@almacen.test', extensions.crypt('Demo1234!', extensions.gen_salt('bf')), now(), '', '', '', '', '', '', '{"provider":"email","providers":["email"]}', '{"display_name":"Marco Empleado (demo)"}', now(), now())
on conflict (id) do update
set encrypted_password = excluded.encrypted_password,
    email_confirmed_at = excluded.email_confirmed_at,
    confirmation_token = excluded.confirmation_token,
    recovery_token = excluded.recovery_token,
    email_change_token_new = excluded.email_change_token_new,
    email_change = excluded.email_change,
    phone_change_token = excluded.phone_change_token,
    reauthentication_token = excluded.reauthentication_token,
    raw_app_meta_data = excluded.raw_app_meta_data,
    raw_user_meta_data = excluded.raw_user_meta_data,
    updated_at = now();

insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
values
  ('dueno.demo@almacen.test', 'd0000000-0000-4000-8000-000000000001', '{"sub":"d0000000-0000-4000-8000-000000000001","email":"dueno.demo@almacen.test","email_verified":true,"phone_verified":false}', 'email', now(), now(), now()),
  ('empleado.demo@almacen.test', 'd0000000-0000-4000-8000-000000000002', '{"sub":"d0000000-0000-4000-8000-000000000002","email":"empleado.demo@almacen.test","email_verified":true,"phone_verified":false}', 'email', now(), now(), now())
on conflict (provider_id, provider) do update
set identity_data = excluded.identity_data,
    updated_at = now();

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'd0000000-0000-4000-8000-000000000001', true);

do $$
begin
  if not exists (
    select 1 from public.businesses
    where created_by = 'd0000000-0000-4000-8000-000000000001'
      and name = 'Almacén El Amigo · Modo demostración'
  ) then
    perform public.create_business('Almacén El Amigo · Modo demostración', 'America/Guatemala');
  end if;
end;
$$;

reset role;

insert into public.business_memberships (business_id, user_id, role_id, status, created_by)
select business.id, 'd0000000-0000-4000-8000-000000000002', role.id, 'active', 'd0000000-0000-4000-8000-000000000001'
from public.businesses business
join public.business_roles role on role.business_id = business.id and role.code = 'employee'
where business.created_by = 'd0000000-0000-4000-8000-000000000001'
  and business.name = 'Almacén El Amigo · Modo demostración'
on conflict (business_id, user_id) do nothing;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'd0000000-0000-4000-8000-000000000001', true);

do $$
declare
  demo_business_id uuid;
  shirt_blue_id uuid;
  shirt_white_id uuid;
  pants_id uuid;
  belt_id uuid;
  fragrance_id uuid;
  shirt_product_id uuid;
  supplier_textile_id uuid;
  supplier_accessories_id uuid;
  confirmed_purchase_id uuid;
begin
  select business.id into demo_business_id
  from public.businesses business
  where business.created_by = 'd0000000-0000-4000-8000-000000000001'
    and business.name = 'Almacén El Amigo · Modo demostración';

  if exists (select 1 from public.products product where product.business_id = demo_business_id) then
    return;
  end if;

  shirt_blue_id := public.create_catalog_product(
    demo_business_id, 'Camisas', 'Manhattan', 'Camisa Oxford manga larga', '{}'::jsonb,
    '{"color":"Azul","talla":"M"}'::jsonb, 220.00, 180.00
  );
  select product_id into shirt_product_id from public.product_variants where id = shirt_blue_id;
  shirt_white_id := public.create_product_variant(
    demo_business_id, shirt_product_id, '{"color":"Blanca","talla":"L"}'::jsonb, 220.00, 180.00
  );
  pants_id := public.create_catalog_product(
    demo_business_id, 'Pantalones', 'Denim Norte', 'Pantalón jean slim fit', '{}'::jsonb,
    '{"color":"Índigo","talla":"32"}'::jsonb, 300.00, 250.00
  );
  belt_id := public.create_catalog_product(
    demo_business_id, 'Accesorios', 'Cuero GT', 'Cinturón de cuero reversible', '{}'::jsonb,
    '{"color":"Café","talla":"Única"}'::jsonb, 160.00, 120.00
  );
  fragrance_id := public.create_catalog_product(
    demo_business_id, 'Lociones', 'Aroma Local', 'Loción Sport 100 ml', '{}'::jsonb,
    '{"presentación":"100 ml"}'::jsonb, 185.00, 145.00
  );

  supplier_textile_id := public.create_supplier(
    demo_business_id, 'Distribuidora Textil del Centro', 'Ana López', '5555-0101'
  );
  supplier_accessories_id := public.create_supplier(
    demo_business_id, 'Accesorios La Plaza', 'Diego Ruiz', '5555-0102'
  );

  perform public.import_initial_inventory(
    demo_business_id,
    jsonb_build_array(
      jsonb_build_object('variant_id', shirt_blue_id, 'quantity', 8, 'unit_cost', '80.00'),
      jsonb_build_object('variant_id', shirt_white_id, 'quantity', 4, 'unit_cost', '80.00'),
      jsonb_build_object('variant_id', pants_id, 'quantity', 5, 'unit_cost', '145.00'),
      jsonb_build_object('variant_id', belt_id, 'quantity', 3, 'unit_cost', '60.00'),
      jsonb_build_object('variant_id', fragrance_id, 'quantity', 2, 'unit_cost', '95.00')
    ),
    'Conteo físico ficticio para explorar el modo demostración',
    'd0000000-0000-4000-8000-000000000101'
  );

  confirmed_purchase_id := public.record_purchase(
    demo_business_id, supplier_textile_id, 'partial', 'DEMO-FACT-001', now() - interval '1 hour', 200.00,
    jsonb_build_array(jsonb_build_object('variant_id', shirt_blue_id, 'quantity', 6, 'unit_cost', 92.00)),
    'd0000000-0000-4000-8000-000000000102'
  );
  perform public.confirm_purchase(demo_business_id, confirmed_purchase_id, 'd0000000-0000-4000-8000-000000000103');

  perform public.record_purchase(
    demo_business_id, supplier_accessories_id, 'credit', 'DEMO-FACT-002', now(), 0.00,
    jsonb_build_array(jsonb_build_object('variant_id', fragrance_id, 'quantity', 5, 'unit_cost', 104.00)),
    'd0000000-0000-4000-8000-000000000104'
  );

  perform public.set_variant_stock_alert(demo_business_id, belt_id, 2, true);
  perform public.set_owner_authorization_pin(demo_business_id, '246810', '246810');
  perform public.open_cash_register(
    demo_business_id, 500.00, 'Fondo ficticio para demostración', 'd0000000-0000-4000-8000-000000000105'
  );
end;
$$;

select set_config('request.jwt.claim.sub', 'd0000000-0000-4000-8000-000000000002', true);

do $$
declare
  demo_business_id uuid;
  cash_session_id uuid;
  shirt_blue_id uuid;
  pants_id uuid;
  belt_id uuid;
  supplier_textile_id uuid;
begin
  select business.id into demo_business_id from public.businesses business
  where business.created_by = 'd0000000-0000-4000-8000-000000000001'
    and business.name = 'Almacén El Amigo · Modo demostración';
  select session.id into cash_session_id from public.cash_register_sessions session
  where session.business_id = demo_business_id and session.status = 'open';
  select variant.id into shirt_blue_id from public.product_variants variant
  join public.products product on product.id = variant.product_id
  where product.business_id = demo_business_id and product.name = 'Camisa Oxford manga larga'
  order by variant.sequence_number limit 1;
  select variant.id into pants_id from public.product_variants variant
  join public.products product on product.id = variant.product_id
  where product.business_id = demo_business_id and product.name = 'Pantalón jean slim fit';
  select variant.id into belt_id from public.product_variants variant
  join public.products product on product.id = variant.product_id
  where product.business_id = demo_business_id and product.name = 'Cinturón de cuero reversible';
  select supplier.id into supplier_textile_id from public.suppliers supplier
  where supplier.business_id = demo_business_id and supplier.name = 'Distribuidora Textil del Centro';

  perform public.confirm_sale(
    demo_business_id, cash_session_id, 'cash',
    jsonb_build_array(jsonb_build_object('variant_id', shirt_blue_id, 'quantity', 1, 'unit_price', 220.00)),
    'd0000000-0000-4000-8000-000000000106'
  );
  perform public.confirm_sale(
    demo_business_id, cash_session_id, 'qr',
    jsonb_build_array(jsonb_build_object('variant_id', pants_id, 'quantity', 1, 'unit_price', 300.00)),
    'd0000000-0000-4000-8000-000000000107'
  );
  perform public.request_sale_price_authorization(
    demo_business_id,
    jsonb_build_array(jsonb_build_object('variant_id', shirt_blue_id, 'quantity', 1, 'unit_price', 170.00)),
    'Cliente frecuente solicita una excepción ficticia',
    'd0000000-0000-4000-8000-000000000108'
  );
  perform public.record_general_supplier_payment(
    demo_business_id, supplier_textile_id, 150.00, 'transfer', 'DEMO-DEP-001', 'Abono ficticio pendiente de confirmación',
    'd0000000-0000-4000-8000-000000000109'
  );
  perform public.record_inventory_count_difference(
    demo_business_id, pants_id, 3, 'Conteo ficticio para revisar durante el piloto',
    'd0000000-0000-4000-8000-000000000110'
  );
  perform public.report_defective_product(
    demo_business_id, belt_id, supplier_textile_id, 1, 'Costura desprendida en unidad ficticia',
    'd0000000-0000-4000-8000-000000000111'
  );
end;
$$;

commit;
