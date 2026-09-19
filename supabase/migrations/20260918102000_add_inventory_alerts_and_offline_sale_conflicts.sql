-- Fase 7: alertas de existencias por variante y conflictos de ventas offline.

create table public.variant_stock_alert_settings (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  variant_id uuid not null,
  low_stock_threshold integer not null default 2 check (low_stock_threshold >= 1),
  is_enabled boolean not null default true,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint variant_stock_alert_settings_variant_business
    foreign key (variant_id, business_id) references public.product_variants(id, business_id) on delete restrict,
  constraint variant_stock_alert_settings_variant_unique unique (business_id, variant_id)
);

create index variant_stock_alert_settings_business_enabled_idx
  on public.variant_stock_alert_settings (business_id, is_enabled);

create trigger set_variant_stock_alert_settings_updated_at
before update on public.variant_stock_alert_settings
for each row execute procedure public.set_updated_at();

alter table public.variant_stock_alert_settings enable row level security;

create policy "owners read stock alert settings"
on public.variant_stock_alert_settings for select to authenticated
using (public.is_business_owner(business_id));

create function public.set_variant_stock_alert(
  p_business_id uuid,
  p_variant_id uuid,
  p_low_stock_threshold integer,
  p_is_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_business_owner(p_business_id) then
    raise exception 'Solo el dueño puede configurar alertas de existencias.';
  end if;

  if p_low_stock_threshold is null or p_low_stock_threshold < 1 then
    raise exception 'El límite de stock bajo debe ser al menos una unidad.';
  end if;

  if not exists (
    select 1 from public.product_variants variant
    where variant.id = p_variant_id and variant.business_id = p_business_id
  ) then
    raise exception 'La variante no pertenece al negocio activo.';
  end if;

  insert into public.variant_stock_alert_settings (
    business_id, variant_id, low_stock_threshold, is_enabled, updated_by
  ) values (
    p_business_id, p_variant_id, p_low_stock_threshold, coalesce(p_is_enabled, true), auth.uid()
  )
  on conflict (business_id, variant_id) do update
  set low_stock_threshold = excluded.low_stock_threshold,
      is_enabled = excluded.is_enabled,
      updated_by = auth.uid();

  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (
    p_business_id, auth.uid(), 'variant_stock_alert.updated', 'product_variant', p_variant_id,
    jsonb_build_object('low_stock_threshold', p_low_stock_threshold, 'is_enabled', coalesce(p_is_enabled, true))
  );
end;
$$;

create function public.get_inventory_alerts(p_business_id uuid)
returns table (
  product_id uuid,
  product_name text,
  out_of_stock_count integer,
  low_stock_count integer,
  variants jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'inventory.read') then
    raise exception 'No tienes permiso para consultar alertas de inventario.';
  end if;

  return query
  with variant_availability as (
    select
      variant.id as variant_id,
      variant.product_id,
      variant.internal_code as variant_code,
      coalesce(sum(movement.quantity_delta) filter (where movement.inventory_state = 'available'), 0)::integer as available_quantity,
      coalesce(setting.low_stock_threshold, 2) as low_stock_threshold,
      coalesce(setting.is_enabled, true) as is_enabled
    from public.product_variants variant
    join public.products product on product.id = variant.product_id
    left join public.inventory_movements movement
      on movement.variant_id = variant.id and movement.business_id = p_business_id
    left join public.variant_stock_alert_settings setting
      on setting.variant_id = variant.id and setting.business_id = p_business_id
    where variant.business_id = p_business_id
      and variant.is_active
      and product.is_active
    group by variant.id, variant.product_id, variant.internal_code, setting.low_stock_threshold, setting.is_enabled
  ), alert_variants as (
    select *, case when available_quantity = 0 then 'out_of_stock' else 'low_stock' end as alert_status
    from variant_availability
    where is_enabled
      and available_quantity >= 0
      and available_quantity <= low_stock_threshold
  )
  select
    product.id,
    product.name,
    count(*) filter (where alert_variant.alert_status = 'out_of_stock')::integer,
    count(*) filter (where alert_variant.alert_status = 'low_stock')::integer,
    jsonb_agg(
      jsonb_build_object(
        'variant_id', alert_variant.variant_id,
        'variant_code', alert_variant.variant_code,
        'available_quantity', alert_variant.available_quantity,
        'low_stock_threshold', alert_variant.low_stock_threshold,
        'status', alert_variant.alert_status
      ) order by alert_variant.alert_status desc, alert_variant.variant_code
    )
  from alert_variants alert_variant
  join public.products product on product.id = alert_variant.product_id
  group by product.id, product.name
  order by product.name;
end;
$$;

create type public.offline_sale_conflict_status as enum ('open', 'resolved');

create table public.offline_sale_sync_conflicts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  request_id uuid not null,
  cash_session_id uuid not null,
  payment_method public.sale_payment_method not null,
  sale_lines jsonb not null,
  error_message text not null check (char_length(btrim(error_message)) between 3 and 600),
  status public.offline_sale_conflict_status not null default 'open',
  submitted_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  resolved_by uuid references auth.users(id) on delete restrict,
  resolved_at timestamptz,
  resolution_notes text,
  constraint offline_sale_sync_conflicts_request_unique unique (business_id, request_id),
  constraint offline_sale_sync_conflicts_lines_array check (jsonb_typeof(sale_lines) = 'array'),
  constraint offline_sale_sync_conflicts_resolution check (
    (status = 'open' and resolved_by is null and resolved_at is null and resolution_notes is null)
    or (status = 'resolved' and resolved_by is not null and resolved_at is not null and char_length(btrim(resolution_notes)) between 3 and 600)
  ),
  constraint offline_sale_sync_conflicts_session_business
    foreign key (cash_session_id, business_id) references public.cash_register_sessions(id, business_id) on delete restrict
);

create index offline_sale_sync_conflicts_business_status_idx
  on public.offline_sale_sync_conflicts (business_id, status, created_at desc);

alter table public.offline_sale_sync_conflicts enable row level security;

create policy "owners read offline sale conflicts"
on public.offline_sale_sync_conflicts for select to authenticated
using (public.is_business_owner(business_id));

create function public.record_offline_sale_sync_conflict(
  p_business_id uuid,
  p_cash_session_id uuid,
  p_payment_method public.sale_payment_method,
  p_sale_lines jsonb,
  p_error_message text,
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  conflict_id uuid;
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'sales.create') then
    raise exception 'No tienes permiso para registrar conflictos de venta.';
  end if;

  select id into conflict_id
  from public.offline_sale_sync_conflicts
  where business_id = p_business_id and request_id = p_request_id;
  if conflict_id is not null then return conflict_id; end if;

  if exists (select 1 from public.sales sale where sale.business_id = p_business_id and sale.request_id = p_request_id) then
    raise exception 'La venta ya fue confirmada y no requiere conflicto.';
  end if;

  if jsonb_typeof(p_sale_lines) <> 'array' or jsonb_array_length(p_sale_lines) = 0 then
    raise exception 'El conflicto debe conservar al menos una línea de venta.';
  end if;

  if p_error_message is null or char_length(btrim(p_error_message)) < 3 then
    raise exception 'El conflicto debe incluir el motivo devuelto por el servidor.';
  end if;

  insert into public.offline_sale_sync_conflicts (
    business_id, request_id, cash_session_id, payment_method, sale_lines, error_message, submitted_by
  ) values (
    p_business_id, p_request_id, p_cash_session_id, p_payment_method, p_sale_lines,
    left(btrim(p_error_message), 600), auth.uid()
  ) returning id into conflict_id;

  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (
    p_business_id, auth.uid(), 'offline_sale.conflict_recorded', 'offline_sale_sync_conflict', conflict_id,
    jsonb_build_object('request_id', p_request_id)
  );
  return conflict_id;
end;
$$;

create function public.resolve_offline_sale_sync_conflict(
  p_business_id uuid,
  p_conflict_id uuid,
  p_resolution_notes text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  conflict_row public.offline_sale_sync_conflicts%rowtype;
begin
  if auth.uid() is null or not public.is_business_owner(p_business_id) then
    raise exception 'Solo el dueño puede resolver conflictos de ventas pendientes.';
  end if;
  if p_resolution_notes is null or char_length(btrim(p_resolution_notes)) < 3 then
    raise exception 'Indica cómo se resolvió el conflicto.';
  end if;

  select * into conflict_row
  from public.offline_sale_sync_conflicts
  where id = p_conflict_id and business_id = p_business_id
  for update;
  if not found then raise exception 'El conflicto no está disponible.'; end if;
  if conflict_row.status = 'resolved' then return conflict_row.id; end if;

  update public.offline_sale_sync_conflicts
  set status = 'resolved', resolved_by = auth.uid(), resolved_at = now(), resolution_notes = btrim(p_resolution_notes)
  where id = conflict_row.id;

  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (
    p_business_id, auth.uid(), 'offline_sale.conflict_resolved', 'offline_sale_sync_conflict', conflict_row.id,
    jsonb_build_object('resolution_notes', btrim(p_resolution_notes))
  );
  return conflict_row.id;
end;
$$;

revoke all on function public.set_variant_stock_alert(uuid, uuid, integer, boolean) from public;
grant execute on function public.set_variant_stock_alert(uuid, uuid, integer, boolean) to authenticated;
revoke all on function public.get_inventory_alerts(uuid) from public;
grant execute on function public.get_inventory_alerts(uuid) to authenticated;
revoke all on function public.record_offline_sale_sync_conflict(uuid, uuid, public.sale_payment_method, jsonb, text, uuid) from public;
grant execute on function public.record_offline_sale_sync_conflict(uuid, uuid, public.sale_payment_method, jsonb, text, uuid) to authenticated;
revoke all on function public.resolve_offline_sale_sync_conflict(uuid, uuid, text) from public;
grant execute on function public.resolve_offline_sale_sync_conflict(uuid, uuid, text) to authenticated;
