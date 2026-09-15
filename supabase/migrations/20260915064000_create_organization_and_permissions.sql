-- Base multinegocio. Las tablas operativas de fases posteriores referenciarán
-- businesses.id y reutilizarán estas funciones de autorización.

create type public.business_role_code as enum ('owner', 'employee');

create type public.membership_status as enum ('active', 'invited', 'suspended');

create type public.permission_code as enum (
  'business.manage',
  'memberships.manage',
  'catalog.read',
  'catalog.manage',
  'pricing.read',
  'pricing.manage',
  'inventory.read',
  'inventory.adjust',
  'sales.create',
  'sales.authorize_below_minimum',
  'purchases.create',
  'purchases.confirm',
  'suppliers.read',
  'payables.read',
  'payables.manage',
  'cash_register.open',
  'cash_register.close',
  'reports.read_sensitive',
  'audit.read',
  'files.upload'
);

create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_not_blank check (display_name is null or btrim(display_name) <> '')
);

create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  timezone text not null default 'America/Guatemala',
  currency_code text not null default 'GTQ',
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint businesses_name_not_blank check (btrim(name) <> ''),
  constraint businesses_currency_code_is_gtq check (currency_code = 'GTQ')
);

create table public.business_roles (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  code public.business_role_code not null,
  name text not null,
  is_system boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint business_roles_name_not_blank check (btrim(name) <> ''),
  constraint business_roles_id_business_id_unique unique (id, business_id),
  constraint business_roles_business_code_unique unique (business_id, code)
);

create table public.business_memberships (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  user_id uuid not null references auth.users (id) on delete restrict,
  role_id uuid not null,
  status public.membership_status not null default 'invited',
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint business_memberships_user_business_unique unique (business_id, user_id),
  constraint business_memberships_role_matches_business foreign key (role_id, business_id)
    references public.business_roles (id, business_id) on delete restrict
);

create table public.business_role_permissions (
  role_id uuid not null references public.business_roles (id) on delete cascade,
  permission public.permission_code not null,
  created_at timestamptz not null default now(),
  primary key (role_id, permission)
);

create table public.membership_permission_overrides (
  membership_id uuid not null references public.business_memberships (id) on delete cascade,
  permission public.permission_code not null,
  is_granted boolean not null,
  created_at timestamptz not null default now(),
  primary key (membership_id, permission)
);

create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  actor_user_id uuid references auth.users (id) on delete set null,
  event_type text not null,
  entity_type text not null,
  entity_id uuid,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint audit_events_event_type_not_blank check (btrim(event_type) <> ''),
  constraint audit_events_entity_type_not_blank check (btrim(entity_type) <> '')
);

create index business_memberships_user_status_idx
  on public.business_memberships (user_id, status);
create index business_memberships_business_status_idx
  on public.business_memberships (business_id, status);
create index audit_events_business_created_at_idx
  on public.audit_events (business_id, created_at desc);

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger set_profiles_updated_at
before update on public.profiles
for each row execute procedure public.set_updated_at();

create trigger set_businesses_updated_at
before update on public.businesses
for each row execute procedure public.set_updated_at();

create trigger set_business_roles_updated_at
before update on public.business_roles
for each row execute procedure public.set_updated_at();

create trigger set_business_memberships_updated_at
before update on public.business_memberships
for each row execute procedure public.set_updated_at();

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (new.id, nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''))
  on conflict (user_id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

create function public.is_active_business_member(p_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.business_memberships membership
    where membership.business_id = p_business_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
  );
$$;

create function public.is_business_owner(p_business_id uuid)
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
    where membership.business_id = p_business_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
      and role.code = 'owner'
  );
$$;

create function public.is_active_business_member_for_role(p_role_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_active_business_member(role.business_id)
  from public.business_roles role
  where role.id = p_role_id;
$$;

create function public.is_business_owner_for_role(p_role_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_business_owner(role.business_id)
  from public.business_roles role
  where role.id = p_role_id;
$$;

create function public.is_active_business_member_for_membership(p_membership_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_active_business_member(membership.business_id)
  from public.business_memberships membership
  where membership.id = p_membership_id;
$$;

create function public.is_business_owner_for_membership(p_membership_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_business_owner(membership.business_id)
  from public.business_memberships membership
  where membership.id = p_membership_id;
$$;

create function public.shares_active_business_with(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.business_memberships self_membership
    join public.business_memberships other_membership
      on other_membership.business_id = self_membership.business_id
    where self_membership.user_id = auth.uid()
      and self_membership.status = 'active'
      and other_membership.user_id = p_user_id
      and other_membership.status = 'active'
  );
$$;

create function public.has_business_permission(
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
      and membership.user_id = auth.uid()
      and membership.status = 'active'
      and (
        role.code = 'owner'
        or coalesce(override.is_granted, role_permission.permission is not null)
      )
  );
$$;

create function public.create_business(
  p_name text,
  p_timezone text default 'America/Guatemala'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_name text := btrim(p_name);
  business_id uuid;
  owner_role_id uuid;
  employee_role_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Se requiere una sesión autenticada.';
  end if;

  if normalized_name is null or char_length(normalized_name) < 2 then
    raise exception 'El nombre del negocio debe tener al menos dos caracteres.';
  end if;

  if char_length(normalized_name) > 120 then
    raise exception 'El nombre del negocio no puede exceder 120 caracteres.';
  end if;

  if not exists (select 1 from pg_timezone_names where name = p_timezone) then
    raise exception 'La zona horaria no es válida.';
  end if;

  insert into public.businesses (name, timezone, created_by)
  values (normalized_name, p_timezone, auth.uid())
  returning id into business_id;

  insert into public.business_roles (business_id, code, name, is_system)
  values (business_id, 'owner', 'Dueño', true)
  returning id into owner_role_id;

  insert into public.business_roles (business_id, code, name, is_system)
  values (business_id, 'employee', 'Empleado', true)
  returning id into employee_role_id;

  insert into public.business_role_permissions (role_id, permission)
  select owner_role_id, permission
  from unnest(enum_range(null::public.permission_code)) as permission;

  insert into public.business_role_permissions (role_id, permission)
  values
    (employee_role_id, 'catalog.read'),
    (employee_role_id, 'pricing.read'),
    (employee_role_id, 'inventory.read'),
    (employee_role_id, 'sales.create'),
    (employee_role_id, 'purchases.create'),
    (employee_role_id, 'suppliers.read'),
    (employee_role_id, 'cash_register.close'),
    (employee_role_id, 'files.upload');

  insert into public.business_memberships (business_id, user_id, role_id, status, created_by)
  values (business_id, auth.uid(), owner_role_id, 'active', auth.uid());

  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (
    business_id,
    auth.uid(),
    'business.created',
    'business',
    business_id,
    jsonb_build_object('name', normalized_name, 'timezone', p_timezone)
  );

  return business_id;
end;
$$;

revoke all on function public.create_business(text, text) from public;
grant execute on function public.create_business(text, text) to authenticated;

alter table public.profiles enable row level security;
alter table public.businesses enable row level security;
alter table public.business_roles enable row level security;
alter table public.business_memberships enable row level security;
alter table public.business_role_permissions enable row level security;
alter table public.membership_permission_overrides enable row level security;
alter table public.audit_events enable row level security;

create policy "profiles are visible to their owner or business peers"
on public.profiles for select to authenticated
using (user_id = auth.uid() or public.shares_active_business_with(user_id));

create policy "users update their own profile"
on public.profiles for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "members view their authorized businesses"
on public.businesses for select to authenticated
using (public.is_active_business_member(id));

create policy "owners update their business"
on public.businesses for update to authenticated
using (public.is_business_owner(id))
with check (public.is_business_owner(id));

create policy "members view roles in their business"
on public.business_roles for select to authenticated
using (public.is_active_business_member(business_id));

create policy "owners manage roles in their business"
on public.business_roles for all to authenticated
using (public.is_business_owner(business_id))
with check (public.is_business_owner(business_id));

create policy "members view assigned memberships"
on public.business_memberships for select to authenticated
using (user_id = auth.uid() or public.is_business_owner(business_id));

create policy "owners manage memberships"
on public.business_memberships for all to authenticated
using (public.is_business_owner(business_id))
with check (public.is_business_owner(business_id));

create policy "members view permissions for authorized roles"
on public.business_role_permissions for select to authenticated
using (public.is_active_business_member_for_role(role_id));

create policy "owners manage permissions for authorized roles"
on public.business_role_permissions for all to authenticated
using (public.is_business_owner_for_role(role_id))
with check (public.is_business_owner_for_role(role_id));

create policy "members view their own permission overrides"
on public.membership_permission_overrides for select to authenticated
using (
  exists (
    select 1
    from public.business_memberships membership
    where membership.id = membership_id
      and membership.user_id = auth.uid()
  )
  or public.is_business_owner_for_membership(membership_id)
);

create policy "owners manage permission overrides"
on public.membership_permission_overrides for all to authenticated
using (public.is_business_owner_for_membership(membership_id))
with check (public.is_business_owner_for_membership(membership_id));

create policy "owners view their business audit events"
on public.audit_events for select to authenticated
using (public.is_business_owner(business_id));
