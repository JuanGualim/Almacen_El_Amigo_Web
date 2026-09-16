begin;

select plan(14);

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
  invitation_id uuid
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

select * from finish();

rollback;
