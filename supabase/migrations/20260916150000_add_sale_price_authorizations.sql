create extension if not exists pgcrypto with schema extensions;
create type public.sale_authorization_status as enum ('pending', 'approved', 'consumed', 'revoked');

create table public.owner_authorization_pins (
  business_id uuid not null references public.businesses(id) on delete restrict,
  owner_id uuid not null references auth.users(id) on delete restrict,
  pin_hash text not null,
  failed_attempts integer not null default 0 check (failed_attempts between 0 and 5),
  locked_until timestamptz,
  updated_at timestamptz not null default now(),
  primary key (business_id, owner_id)
);

create table public.sale_price_authorizations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  requested_by uuid not null references auth.users(id) on delete restrict,
  requested_at timestamptz not null default now(),
  request_id uuid not null,
  lines jsonb not null,
  reason text not null,
  status public.sale_authorization_status not null default 'pending',
  authorized_by uuid references auth.users(id) on delete restrict,
  authorized_at timestamptz,
  expires_at timestamptz,
  consumed_sale_id uuid unique references public.sales(id) on delete restrict,
  constraint sale_price_authorizations_lines_array check (jsonb_typeof(lines) = 'array' and jsonb_array_length(lines) > 0),
  constraint sale_price_authorizations_reason_length check (char_length(btrim(reason)) between 3 and 300),
  constraint sale_price_authorizations_request_unique unique (business_id, request_id),
  constraint sale_price_authorizations_approval_fields check (
    (status in ('pending', 'revoked') and authorized_by is null and authorized_at is null and expires_at is null and consumed_sale_id is null)
    or (status = 'approved' and authorized_by is not null and authorized_at is not null and expires_at is not null and consumed_sale_id is null)
    or (status = 'consumed' and authorized_by is not null and authorized_at is not null and expires_at is not null and consumed_sale_id is not null)
  )
);

alter table public.sales add column sale_price_authorization_id uuid unique references public.sale_price_authorizations(id) on delete restrict;
alter table public.owner_authorization_pins enable row level security;
alter table public.sale_price_authorizations enable row level security;
create policy "owners manage their authorization pin" on public.owner_authorization_pins for select to authenticated using (owner_id = auth.uid() and public.is_business_owner(business_id));
create policy "owners or requesters read sale authorizations" on public.sale_price_authorizations for select to authenticated using (public.is_business_owner(business_id) or requested_by = auth.uid());

create function public.set_owner_authorization_pin(p_business_id uuid, p_pin text, p_confirmation text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare password_hash text;
begin
  if auth.uid() is null or not public.is_business_owner(p_business_id) then raise exception 'Solo el dueño puede configurar el PIN.'; end if;
  if p_pin !~ '^[0-9]{6}$' or p_pin <> p_confirmation then raise exception 'El PIN debe tener seis dígitos y coincidir con su confirmación.'; end if;
  select encrypted_password into password_hash from auth.users where id = auth.uid();
  if password_hash is not null and extensions.crypt(p_pin, password_hash) = password_hash then raise exception 'El PIN debe ser diferente de la contraseña.'; end if;
  insert into public.owner_authorization_pins (business_id, owner_id, pin_hash) values (p_business_id, auth.uid(), extensions.crypt(p_pin, extensions.gen_salt('bf')))
  on conflict (business_id, owner_id) do update set pin_hash = excluded.pin_hash, failed_attempts = 0, locked_until = null, updated_at = now();
  update public.sale_price_authorizations set status = 'revoked' where business_id = p_business_id and status in ('pending', 'approved');
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, data) values (p_business_id, auth.uid(), 'authorization_pin.changed', 'owner_authorization_pin', '{}'::jsonb);
end; $$;

create function public.request_sale_price_authorization(p_business_id uuid, p_lines jsonb, p_reason text, p_request_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare authorization_id uuid;
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'sales.create') then raise exception 'No tienes permiso para solicitar autorización.'; end if;
  select id into authorization_id from public.sale_price_authorizations where business_id = p_business_id and request_id = p_request_id;
  if authorization_id is not null then return authorization_id; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 or p_reason is null or char_length(btrim(p_reason)) < 3 then raise exception 'Incluye líneas y motivo para la autorización.'; end if;
  if not exists (select 1 from jsonb_to_recordset(p_lines) as line(variant_id uuid, quantity integer, unit_price numeric) join public.variant_current_prices price on price.variant_id = line.variant_id and price.business_id = p_business_id where line.quantity > 0 and line.unit_price >= 0 and line.unit_price < price.minimum_price) then raise exception 'La solicitud debe incluir al menos un precio menor al mínimo vigente.'; end if;
  insert into public.sale_price_authorizations (business_id, requested_by, request_id, lines, reason) values (p_business_id, auth.uid(), p_request_id, p_lines, btrim(p_reason)) returning id into authorization_id;
  return authorization_id;
end; $$;

create function public.approve_sale_price_authorization(p_business_id uuid, p_authorization_id uuid, p_pin text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare pin_row public.owner_authorization_pins%rowtype; authorization_row public.sale_price_authorizations%rowtype;
begin
  if auth.uid() is null or not public.is_business_owner(p_business_id) then raise exception 'Solo el dueño puede autorizar esta venta.'; end if;
  select * into pin_row from public.owner_authorization_pins where business_id = p_business_id and owner_id = auth.uid() for update;
  if not found then raise exception 'Configura tu PIN de autorización antes de aprobar ventas.'; end if;
  if pin_row.locked_until > now() then return false; end if;
  if extensions.crypt(p_pin, pin_row.pin_hash) <> pin_row.pin_hash then
    update public.owner_authorization_pins set failed_attempts = case when failed_attempts + 1 >= 5 then 5 else failed_attempts + 1 end, locked_until = case when failed_attempts + 1 >= 5 then now() + interval '15 minutes' else null end, updated_at = now() where business_id = p_business_id and owner_id = auth.uid();
    if pin_row.failed_attempts + 1 >= 5 then insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, data) values (p_business_id, auth.uid(), 'authorization_pin.locked', 'owner_authorization_pin', jsonb_build_object('locked_minutes', 15)); end if;
    return false;
  end if;
  select * into authorization_row from public.sale_price_authorizations where id = p_authorization_id and business_id = p_business_id for update;
  if not found or authorization_row.status <> 'pending' then raise exception 'La solicitud ya no está disponible.'; end if;
  update public.owner_authorization_pins set failed_attempts = 0, locked_until = null, updated_at = now() where business_id = p_business_id and owner_id = auth.uid();
  update public.sale_price_authorizations set status = 'approved', authorized_by = auth.uid(), authorized_at = now(), expires_at = now() + interval '5 minutes' where id = p_authorization_id;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data) values (p_business_id, auth.uid(), 'sale_price_authorization.approved', 'sale_price_authorization', p_authorization_id, jsonb_build_object('expires_in_minutes', 5));
  return true;
end; $$;

revoke all on function public.set_owner_authorization_pin(uuid, text, text) from public; grant execute on function public.set_owner_authorization_pin(uuid, text, text) to authenticated;
revoke all on function public.request_sale_price_authorization(uuid, jsonb, text, uuid) from public; grant execute on function public.request_sale_price_authorization(uuid, jsonb, text, uuid) to authenticated;
revoke all on function public.approve_sale_price_authorization(uuid, uuid, text) from public; grant execute on function public.approve_sale_price_authorization(uuid, uuid, text) to authenticated;
