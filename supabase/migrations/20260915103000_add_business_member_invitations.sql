-- Las invitaciones conservan un historial separado de la membresía para que el
-- dueño pueda saber quién fue invitado, cuándo y si la invitación fue aceptada.
create type public.business_invitation_status as enum ('pending', 'accepted', 'cancelled');

create table public.business_invitations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  membership_id uuid not null unique references public.business_memberships (id) on delete restrict,
  email text not null,
  status public.business_invitation_status not null default 'pending',
  request_id uuid not null,
  invited_by uuid not null references auth.users (id) on delete restrict,
  invited_at timestamptz not null default now(),
  accepted_at timestamptz,
  constraint business_invitations_email_normalized check (email = lower(btrim(email))),
  constraint business_invitations_email_not_blank check (btrim(email) <> ''),
  constraint business_invitations_request_unique unique (business_id, request_id),
  constraint business_invitations_accepted_at_matches_status check (
    (status = 'accepted' and accepted_at is not null)
    or (status <> 'accepted' and accepted_at is null)
  )
);

create index business_invitations_business_status_idx
  on public.business_invitations (business_id, status, invited_at desc);

create function public.user_has_business_permission(
  p_user_id uuid,
  p_business_id uuid,
  p_permission public.permission_code
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.business_memberships membership
    join public.business_roles role on role.id = membership.role_id
    left join public.membership_permission_overrides override
      on override.membership_id = membership.id
      and override.permission = p_permission
    left join public.business_role_permissions role_permission
      on role_permission.role_id = role.id
      and role_permission.permission = p_permission
    where membership.business_id = p_business_id
      and membership.user_id = p_user_id
      and membership.status = 'active'
      and (
        role.code = 'owner'
        or coalesce(override.is_granted, role_permission.permission is not null)
      )
  );
$$;

-- Solo la Edge Function, autenticada con service_role, puede asociar una
-- identidad de Auth a una invitación. El actor se valida explícitamente para
-- evitar que el privilegio de servicio salte permisos de negocio.
create function public.create_business_invitation(
  p_actor_user_id uuid,
  p_business_id uuid,
  p_invited_user_id uuid,
  p_email text,
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_email text := lower(btrim(p_email));
  employee_role_id uuid;
  existing_membership public.business_memberships%rowtype;
  invitation_id uuid;
begin
  if p_actor_user_id is null or p_invited_user_id is null then
    raise exception 'La invitación requiere usuarios válidos.';
  end if;

  if normalized_email is null
    or char_length(normalized_email) > 254
    or normalized_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'El correo electrónico no es válido.';
  end if;

  if not public.user_has_business_permission(
    p_actor_user_id,
    p_business_id,
    'memberships.manage'
  ) then
    raise exception 'No tienes permiso para invitar personas a este negocio.';
  end if;

  select id
  into employee_role_id
  from public.business_roles
  where business_id = p_business_id
    and code = 'employee';

  if employee_role_id is null then
    raise exception 'El negocio no tiene un rol de empleado disponible.';
  end if;

  select id
  into invitation_id
  from public.business_invitations
  where business_id = p_business_id
    and request_id = p_request_id;

  if invitation_id is not null then
    return invitation_id;
  end if;

  select *
  into existing_membership
  from public.business_memberships
  where business_id = p_business_id
    and user_id = p_invited_user_id
  for update;

  if found then
    if existing_membership.status = 'active' then
      raise exception 'Esta persona ya pertenece al negocio.';
    end if;

    if existing_membership.status = 'suspended' then
      raise exception 'La membresía está suspendida y no puede reinvitarse.';
    end if;

    select id
    into invitation_id
    from public.business_invitations
    where membership_id = existing_membership.id;

    if invitation_id is not null then
      return invitation_id;
    end if;
  else
    insert into public.business_memberships (
      business_id,
      user_id,
      role_id,
      status,
      created_by
    )
    values (
      p_business_id,
      p_invited_user_id,
      employee_role_id,
      'invited',
      p_actor_user_id
    )
    returning * into existing_membership;
  end if;

  insert into public.business_invitations (
    business_id,
    membership_id,
    email,
    request_id,
    invited_by
  )
  values (
    p_business_id,
    existing_membership.id,
    normalized_email,
    p_request_id,
    p_actor_user_id
  )
  returning id into invitation_id;

  insert into public.audit_events (
    business_id,
    actor_user_id,
    event_type,
    entity_type,
    entity_id,
    data
  )
  values (
    p_business_id,
    p_actor_user_id,
    'membership.invited',
    'business_invitation',
    invitation_id,
    jsonb_build_object(
      'membership_id', existing_membership.id,
      'email', normalized_email,
      'initial_role', 'employee'
    )
  );

  return invitation_id;
end;
$$;

create function public.get_my_pending_business_invitations()
returns table (
  membership_id uuid,
  business_id uuid,
  business_name text,
  role_name text,
  invited_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    membership.id,
    business.id,
    business.name,
    role.name,
    invitation.invited_at
  from public.business_memberships membership
  join public.businesses business on business.id = membership.business_id
  join public.business_roles role on role.id = membership.role_id
  join public.business_invitations invitation on invitation.membership_id = membership.id
  where membership.user_id = auth.uid()
    and membership.status = 'invited'
    and invitation.status = 'pending'
  order by invitation.invited_at desc;
$$;

create function public.accept_business_invitation(p_membership_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_membership public.business_memberships%rowtype;
  target_invitation public.business_invitations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Se requiere una sesión autenticada.';
  end if;

  select *
  into target_membership
  from public.business_memberships
  where id = p_membership_id
    and user_id = auth.uid()
    and status = 'invited'
  for update;

  if not found then
    raise exception 'La invitación no está disponible para esta cuenta.';
  end if;

  select *
  into target_invitation
  from public.business_invitations
  where membership_id = target_membership.id
    and status = 'pending'
  for update;

  if not found then
    raise exception 'La invitación ya no está disponible.';
  end if;

  update public.business_memberships
  set status = 'active'
  where id = target_membership.id;

  update public.business_invitations
  set status = 'accepted', accepted_at = now()
  where id = target_invitation.id;

  insert into public.audit_events (
    business_id,
    actor_user_id,
    event_type,
    entity_type,
    entity_id,
    data
  )
  values (
    target_membership.business_id,
    auth.uid(),
    'membership.invitation_accepted',
    'business_invitation',
    target_invitation.id,
    jsonb_build_object('membership_id', target_membership.id)
  );

  return target_membership.business_id;
end;
$$;

alter table public.business_invitations enable row level security;

create policy "owners and invitees view business invitations"
on public.business_invitations for select to authenticated
using (
  public.is_business_owner(business_id)
  or exists (
    select 1
    from public.business_memberships membership
    where membership.id = membership_id
      and membership.user_id = auth.uid()
  )
);

revoke all on function public.user_has_business_permission(uuid, uuid, public.permission_code) from public;
revoke all on function public.create_business_invitation(uuid, uuid, uuid, text, uuid) from public;
grant execute on function public.create_business_invitation(uuid, uuid, uuid, text, uuid) to service_role;
revoke all on function public.get_my_pending_business_invitations() from public;
grant execute on function public.get_my_pending_business_invitations() to authenticated;
revoke all on function public.accept_business_invitation(uuid) from public;
grant execute on function public.accept_business_invitation(uuid) to authenticated;
