begin;

select plan(12);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('88888888-8888-8888-8888-888888888881', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'reports-owner@example.test', 'not-used-by-test', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Dueño de reportes"}', now(), now()),
  ('88888888-8888-8888-8888-888888888882', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'reports-employee@example.test', 'not-used-by-test', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Empleado de reportes"}', now(), now()),
  ('88888888-8888-8888-8888-888888888883', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'reports-outsider@example.test', 'not-used-by-test', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Ajeno de reportes"}', now(), now());

create temporary table report_context (
  business_id uuid,
  cash_session_id uuid,
  outsider_business_id uuid,
  supplier_id uuid,
  variant_id uuid
);
grant select, insert, update on report_context to authenticated, service_role;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '88888888-8888-8888-8888-888888888881', true);

insert into report_context (business_id)
select public.create_business('Negocio de reportes');

update report_context
set variant_id = public.create_catalog_product(
  business_id, 'Camisas', null, 'Camisa para reporte', '{}'::jsonb,
  '{"color":"Azul","size":"M"}'::jsonb, 185.00, 160.00
);

update report_context
set supplier_id = public.create_supplier(business_id, 'Distribuidor de reportes');

select lives_ok(
  $$ select public.confirm_purchase(
    business_id,
    public.record_purchase(
      business_id, supplier_id, 'cash', null, now(), 100.00,
      jsonb_build_array(jsonb_build_object('variant_id', variant_id, 'quantity', 2, 'unit_cost', 50.00)),
      '88888888-0000-4000-8000-000000000001'
    ),
    '88888888-0000-4000-8000-000000000002'
  ) from report_context $$,
  'la compra de prueba se confirma'
);

update report_context
set cash_session_id = public.open_cash_register(
  business_id, 0, null, '88888888-0000-4000-8000-000000000003'
);

select lives_ok(
  $$ select public.confirm_sale(
    business_id, cash_session_id, 'cash',
    jsonb_build_array(jsonb_build_object('variant_id', variant_id, 'quantity', 1, 'unit_price', 185.00)),
    '88888888-0000-4000-8000-000000000004'
  ) from report_context $$,
  'la venta de prueba se confirma'
);

select is(
  (public.get_operational_dashboard((select business_id from report_context)) ->> 'pending_defective_products')::integer,
  0,
  'el dueño recibe los pendientes operativos permitidos'
);

select is(
  (public.get_operational_dashboard((select business_id from report_context)) -> 'sensitive_summary' ->> 'today_sales_amount')::numeric,
  185.00::numeric,
  'el dueño recibe el total de ventas del día comercial'
);

select is(
  (public.get_operational_report((select business_id from report_context), (now() at time zone 'America/Guatemala')::date - 1, (now() at time zone 'America/Guatemala')::date) -> 'summary' ->> 'sales_amount')::numeric,
  185.00::numeric,
  'el reporte conserva el importe exacto de ventas'
);

select is(
  (public.get_operational_report((select business_id from report_context), (now() at time zone 'America/Guatemala')::date - 1, (now() at time zone 'America/Guatemala')::date) -> 'summary' ->> 'purchases_amount')::numeric,
  100.00::numeric,
  'el reporte incluye compras confirmadas del periodo'
);

select is(
  jsonb_array_length(public.get_operational_report((select business_id from report_context), (now() at time zone 'America/Guatemala')::date - 1, (now() at time zone 'America/Guatemala')::date) -> 'top_sold_variants'),
  1,
  'el reporte agrupa la variante vendida'
);

set local role service_role;
insert into public.business_memberships (business_id, user_id, role_id, status, created_by)
select context.business_id, '88888888-8888-8888-8888-888888888882', role.id, 'active', '88888888-8888-8888-8888-888888888881'
from report_context context
join public.business_roles role on role.business_id = context.business_id and role.code = 'employee';

set local role authenticated;
select set_config('request.jwt.claim.sub', '88888888-8888-8888-8888-888888888882', true);

select is(
  public.get_operational_dashboard((select business_id from report_context)) -> 'sensitive_summary',
  'null'::jsonb,
  'el empleado no recibe ventas ni saldo de distribuidores en el panel'
);

select throws_ok(
  $$ select public.get_operational_report((select business_id from report_context), (now() at time zone 'America/Guatemala')::date - 1, (now() at time zone 'America/Guatemala')::date) $$,
  'P0001',
  'No tienes permiso para consultar reportes sensibles.',
  'el empleado no puede consultar el reporte sensible'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '88888888-8888-8888-8888-888888888881', true);

select throws_ok(
  $$ select public.get_operational_report((select business_id from report_context), (now() at time zone 'America/Guatemala')::date, (now() at time zone 'America/Guatemala')::date - 1) $$,
  'P0001',
  'El periodo del reporte no es válido.',
  'el reporte rechaza un periodo invertido'
);

select throws_ok(
  $$ select public.get_operational_report((select business_id from report_context), (now() at time zone 'America/Guatemala')::date - 367, (now() at time zone 'America/Guatemala')::date) $$,
  'P0001',
  'El periodo máximo del reporte es de 367 días.',
  'el reporte limita el periodo para evitar consultas sin límite'
);

select set_config('request.jwt.claim.sub', '88888888-8888-8888-8888-888888888883', true);
insert into report_context (outsider_business_id)
select public.create_business('Negocio ajeno de reportes');

select throws_ok(
  $$ select public.get_operational_dashboard((select business_id from report_context limit 1)) $$,
  'P0001',
  'No tienes acceso a este negocio.',
  'un negocio ajeno no puede consultar el inicio operativo'
);

select * from finish();
rollback;
