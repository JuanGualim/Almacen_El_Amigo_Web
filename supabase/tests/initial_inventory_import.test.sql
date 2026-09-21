begin;

select plan(8);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('77777777-7777-7777-7777-777777777771', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'initial-owner@example.test', 'not-used-by-test', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('77777777-7777-7777-7777-777777777772', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'initial-employee@example.test', 'not-used-by-test', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

create temporary table initial_context (business_id uuid, variant_id uuid, import_id uuid);
grant select, insert, update on initial_context to authenticated, service_role;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-777777777771', true);

insert into initial_context (business_id)
select public.create_business('Negocio carga inicial');

update initial_context
set variant_id = public.create_catalog_product(
  business_id, 'Camisas', null, 'Camisa inicial', '{}'::jsonb,
  '{"color":"Azul","talla":"M"}'::jsonb, 150.00, 120.00
);

update initial_context
set import_id = public.import_initial_inventory(
  business_id,
  jsonb_build_array(jsonb_build_object('variant_id', variant_id, 'quantity', 4, 'unit_cost', '70.00')),
  'Conteo físico inicial verificado',
  '77777777-0000-4000-8000-000000000001'
);

select is(
  (select line_count from public.initial_inventory_imports where id = (select import_id from initial_context)),
  1,
  'la carga inicial conserva su cantidad de líneas'
);

select is(
  (select coalesce(sum(quantity_delta), 0)::integer from public.inventory_movements where business_id = (select business_id from initial_context)),
  4,
  'la carga inicial crea una entrada de inventario trazable'
);

select is(
  (select unit_cost from public.inventory_lots where source_type = 'initial_inventory_import'),
  70.00::numeric,
  'el lote inicial conserva el costo conocido'
);

select is(
  public.import_initial_inventory(
    (select business_id from initial_context),
    jsonb_build_array(jsonb_build_object('variant_id', (select variant_id from initial_context), 'quantity', 4, 'unit_cost', '70.00')),
    'Conteo físico inicial verificado',
    '77777777-0000-4000-8000-000000000001'
  ),
  (select import_id from initial_context),
  'el mismo identificador idempotente devuelve la carga existente'
);

select throws_ok(
  $$ select public.import_initial_inventory(
    (select business_id from initial_context),
    jsonb_build_array(jsonb_build_object('variant_id', (select variant_id from initial_context), 'quantity', 1)),
    'Segundo intento no permitido',
    '77777777-0000-4000-8000-000000000002'
  ) $$,
  'P0001',
  'Este negocio ya tiene una carga inicial confirmada. Usa un conteo o ajuste auditable para diferencias posteriores.',
  'no permite una segunda carga inicial'
);

set local role service_role;
insert into public.business_memberships (business_id, user_id, role_id, status, created_by)
select context.business_id, '77777777-7777-7777-7777-777777777772', role.id, 'active', '77777777-7777-7777-7777-777777777771'
from initial_context context
join public.business_roles role on role.business_id = context.business_id and role.code = 'employee';

set local role authenticated;
select set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-777777777772', true);

select throws_ok(
  $$ select public.import_initial_inventory(
    (select business_id from initial_context), '[]'::jsonb, 'Intento empleado', '77777777-0000-4000-8000-000000000003'
  ) $$,
  'P0001',
  'Solo el dueño puede confirmar la carga inicial de inventario.',
  'el empleado no puede cargar el inventario inicial'
);

select is_empty(
  $$ select * from public.initial_inventory_imports where business_id = (select business_id from initial_context) $$,
  'el empleado no puede leer el costo de la carga inicial'
);

select set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-777777777771', true);

select ok(
  exists(select 1 from public.audit_events where entity_id = (select import_id from initial_context) and event_type = 'inventory.initial_import_confirmed'),
  'la carga inicial deja evidencia de auditoría'
);

select * from finish();
rollback;
