begin;

select plan(8);

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
  second_business_id uuid
);

grant select, insert, update on test_context to authenticated;

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

select * from finish();

rollback;
