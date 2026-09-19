-- Respaldos externos completos. El proveedor se implementa fuera de PostgreSQL
-- mediante una interfaz S3; esta migración conserva el estado auditable y el
-- formato lógico que una instancia local aislada puede reconstruir.

create type public.external_backup_status as enum (
  'uploading', 'valid', 'failed', 'deletion_failed', 'deleted'
);

create table public.external_backup_sets (
  id uuid primary key,
  business_id uuid not null references public.businesses(id) on delete restrict,
  backup_kind public.business_backup_kind not null,
  status public.external_backup_status not null default 'uploading',
  storage_provider text not null check (storage_provider in ('s3-compatible')),
  storage_prefix text not null check (char_length(btrim(storage_prefix)) between 1 and 500),
  manifest jsonb,
  manifest_sha256 text check (manifest_sha256 is null or manifest_sha256 ~ '^[0-9a-f]{64}$'),
  failure_reason text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  verified_at timestamptz,
  deleted_at timestamptz,
  constraint external_backup_sets_state check (
    (status = 'uploading' and manifest is null and manifest_sha256 is null and verified_at is null and deleted_at is null)
    or (status = 'valid' and manifest is not null and manifest_sha256 is not null and verified_at is not null and deleted_at is null)
    or (status in ('failed', 'deletion_failed') and deleted_at is null)
    or (status = 'deleted' and manifest is not null and manifest_sha256 is not null and verified_at is not null and deleted_at is not null)
  )
);

create index external_backup_sets_retention_idx
  on public.external_backup_sets (business_id, backup_kind, status, created_at desc);

alter table public.external_backup_sets enable row level security;
create policy "owners read external backup sets" on public.external_backup_sets
  for select to authenticated using (public.is_business_owner(business_id));

create function public.get_business_backup_data(p_business_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null and auth.role() <> 'service_role' then
    raise exception 'Se requiere una identidad autorizada para exportar el respaldo.';
  end if;
  if auth.role() <> 'service_role' and not public.is_business_owner(p_business_id) then
    raise exception 'Solo el dueño puede generar un respaldo completo.';
  end if;

  return jsonb_build_object(
    'format', 'almacen-el-amigo-backup-data-v2',
    'generated_at', now(),
    'business_id', p_business_id,
    'auth_users', coalesce((
      select jsonb_agg(to_jsonb(user_row) order by user_row.id)
      from auth.users user_row
      where user_row.id in (
        select membership.user_id from public.business_memberships membership where membership.business_id = p_business_id
        union select business.created_by from public.businesses business where business.id = p_business_id
        union select invitation.invited_by from public.business_invitations invitation where invitation.business_id = p_business_id
      )
    ), '[]'::jsonb),
    'tables', jsonb_build_object(
      'profiles', coalesce((select jsonb_agg(to_jsonb(row) order by row.user_id) from public.profiles row where row.user_id in (select membership.user_id from public.business_memberships membership where membership.business_id = p_business_id)), '[]'::jsonb),
      'businesses', coalesce((select jsonb_agg(to_jsonb(row)) from public.businesses row where row.id = p_business_id), '[]'::jsonb),
      'business_roles', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.business_roles row where row.business_id = p_business_id), '[]'::jsonb),
      'business_role_permissions', coalesce((select jsonb_agg(to_jsonb(row)) from public.business_role_permissions row join public.business_roles role on role.id = row.role_id where role.business_id = p_business_id), '[]'::jsonb),
      'business_memberships', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.business_memberships row where row.business_id = p_business_id), '[]'::jsonb),
      'membership_permission_overrides', coalesce((select jsonb_agg(to_jsonb(row)) from public.membership_permission_overrides row join public.business_memberships membership on membership.id = row.membership_id where membership.business_id = p_business_id), '[]'::jsonb),
      'business_invitations', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.business_invitations row where row.business_id = p_business_id), '[]'::jsonb),
      'categories', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.categories row where row.business_id = p_business_id), '[]'::jsonb),
      'brands', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.brands row where row.business_id = p_business_id), '[]'::jsonb),
      'products', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.products row where row.business_id = p_business_id), '[]'::jsonb),
      'product_variants', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.product_variants row where row.business_id = p_business_id), '[]'::jsonb),
      'variant_current_prices', coalesce((select jsonb_agg(to_jsonb(row) order by row.variant_id) from public.variant_current_prices row where row.business_id = p_business_id), '[]'::jsonb),
      'variant_price_history', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.variant_price_history row where row.business_id = p_business_id), '[]'::jsonb),
      'suppliers', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.suppliers row where row.business_id = p_business_id), '[]'::jsonb),
      'purchases', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.purchases row where row.business_id = p_business_id), '[]'::jsonb),
      'purchase_lines', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.purchase_lines row where row.business_id = p_business_id), '[]'::jsonb),
      'inventory_lots', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.inventory_lots row where row.business_id = p_business_id), '[]'::jsonb),
      'inventory_movements', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.inventory_movements row where row.business_id = p_business_id), '[]'::jsonb),
      'supplier_account_entries', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.supplier_account_entries row where row.business_id = p_business_id), '[]'::jsonb),
      'purchase_price_reviews', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.purchase_price_reviews row where row.business_id = p_business_id), '[]'::jsonb),
      'cash_register_sessions', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.cash_register_sessions row where row.business_id = p_business_id), '[]'::jsonb),
      'sales', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.sales row where row.business_id = p_business_id), '[]'::jsonb),
      'sale_lines', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.sale_lines row join public.sales sale on sale.id = row.sale_id where sale.business_id = p_business_id), '[]'::jsonb),
      'sale_payments', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.sale_payments row join public.sales sale on sale.id = row.sale_id where sale.business_id = p_business_id), '[]'::jsonb),
      'cash_movements', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.cash_movements row where row.business_id = p_business_id), '[]'::jsonb),
      'owner_authorization_pins', coalesce((select jsonb_agg(to_jsonb(row) order by row.owner_id) from public.owner_authorization_pins row where row.business_id = p_business_id), '[]'::jsonb),
      'sale_price_authorizations', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.sale_price_authorizations row where row.business_id = p_business_id), '[]'::jsonb),
      'supplier_payments', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.supplier_payments row where row.business_id = p_business_id), '[]'::jsonb),
      'supplier_payment_applications', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.supplier_payment_applications row where row.business_id = p_business_id), '[]'::jsonb),
      'inventory_adjustments', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.inventory_adjustments row where row.business_id = p_business_id), '[]'::jsonb),
      'inventory_authorized_exits', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.inventory_authorized_exits row where row.business_id = p_business_id), '[]'::jsonb),
      'inventory_lot_allocations', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.inventory_lot_allocations row where row.business_id = p_business_id), '[]'::jsonb),
      'inventory_lot_reclassifications', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.inventory_lot_reclassifications row where row.business_id = p_business_id), '[]'::jsonb),
      'defective_products', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.defective_products row where row.business_id = p_business_id), '[]'::jsonb),
      'defective_product_deliveries', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.defective_product_deliveries row where row.business_id = p_business_id), '[]'::jsonb),
      'defective_product_delivery_lots', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.defective_product_delivery_lots row join public.defective_product_deliveries delivery on delivery.id = row.delivery_id where delivery.business_id = p_business_id), '[]'::jsonb),
      'defective_product_replacements', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.defective_product_replacements row where row.business_id = p_business_id), '[]'::jsonb),
      'defective_product_resolutions', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.defective_product_resolutions row where row.business_id = p_business_id), '[]'::jsonb),
      'defective_product_resolution_lots', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.defective_product_resolution_lots row join public.defective_product_resolutions resolution on resolution.id = row.resolution_id where resolution.business_id = p_business_id), '[]'::jsonb),
      'inventory_lot_reclassification_releases', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.inventory_lot_reclassification_releases row join public.defective_product_resolution_lots resolution_lot on resolution_lot.id = row.resolution_lot_id join public.defective_product_resolutions resolution on resolution.id = resolution_lot.resolution_id where resolution.business_id = p_business_id), '[]'::jsonb),
      'supplier_credits', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.supplier_credits row where row.business_id = p_business_id), '[]'::jsonb),
      'supplier_refunds', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.supplier_refunds row where row.business_id = p_business_id), '[]'::jsonb),
      'sale_cancellations', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.sale_cancellations row where row.business_id = p_business_id), '[]'::jsonb),
      'product_exchanges', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.product_exchanges row where row.business_id = p_business_id), '[]'::jsonb),
      'product_exchange_payments', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.product_exchange_payments row where row.business_id = p_business_id), '[]'::jsonb),
      'purchase_cancellations', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.purchase_cancellations row where row.business_id = p_business_id), '[]'::jsonb),
      'variant_stock_alert_settings', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.variant_stock_alert_settings row where row.business_id = p_business_id), '[]'::jsonb),
      'offline_sale_sync_conflicts', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.offline_sale_sync_conflicts row where row.business_id = p_business_id), '[]'::jsonb),
      'audit_events', coalesce((select jsonb_agg(to_jsonb(row) order by row.id) from public.audit_events row where row.business_id = p_business_id), '[]'::jsonb)
    )
  );
end;
$$;

create or replace function public.get_business_structured_export(p_business_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null and auth.role() <> 'service_role' then
    raise exception 'Se requiere una identidad autorizada para exportar.';
  end if;
  if auth.role() <> 'service_role' and not public.is_business_owner(p_business_id) then
    raise exception 'Solo el dueño puede generar una exportación estructurada.';
  end if;
  return public.build_business_structured_export(p_business_id);
end;
$$;

create function public.restore_business_backup_data(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  table_name text;
  table_rows jsonb;
  column_names text;
  sql text;
  restored_counts jsonb := '{}'::jsonb;
  ordered_tables text[] := array[
    'businesses', 'profiles', 'business_roles', 'business_role_permissions', 'business_memberships', 'membership_permission_overrides', 'business_invitations',
    'categories', 'brands', 'products', 'product_variants', 'variant_current_prices', 'variant_price_history', 'suppliers', 'purchases', 'purchase_lines',
    'inventory_lots', 'inventory_movements', 'supplier_account_entries', 'purchase_price_reviews', 'cash_register_sessions', 'sales', 'sale_lines', 'sale_payments',
    'owner_authorization_pins', 'sale_price_authorizations', 'supplier_payments', 'supplier_payment_applications', 'inventory_adjustments',
    'inventory_authorized_exits', 'inventory_lot_allocations', 'defective_products', 'inventory_lot_reclassifications', 'defective_product_deliveries',
    'defective_product_delivery_lots', 'defective_product_replacements', 'defective_product_resolutions', 'defective_product_resolution_lots',
    'inventory_lot_reclassification_releases', 'supplier_credits', 'supplier_refunds',
    'purchase_cancellations', 'variant_stock_alert_settings', 'offline_sale_sync_conflicts', 'sale_cancellations', 'product_exchanges', 'product_exchange_payments',
    'cash_movements', 'audit_events'
  ];
begin
  if current_setting('app.backup_restore_isolated', true) <> 'true' then
    raise exception 'La restauración requiere una instancia local aislada.';
  end if;
  if p_payload ->> 'format' <> 'almacen-el-amigo-backup-data-v2' then
    raise exception 'El formato de respaldo no es compatible.';
  end if;
  if jsonb_typeof(p_payload -> 'auth_users') <> 'array' or jsonb_typeof(p_payload -> 'tables') <> 'object' then
    raise exception 'El respaldo no contiene la estructura requerida.';
  end if;
  if exists (select 1 from public.businesses where id = (p_payload ->> 'business_id')::uuid) then
    raise exception 'El negocio ya existe en el destino aislado.';
  end if;

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  select row.id, row.instance_id, row.aud, row.role, row.email, row.encrypted_password, row.email_confirmed_at, row.raw_app_meta_data, row.raw_user_meta_data, row.created_at, row.updated_at
  from jsonb_populate_recordset(null::auth.users, p_payload -> 'auth_users') row;

  foreach table_name in array ordered_tables loop
    table_rows := p_payload -> 'tables' -> table_name;
    if table_rows is null or jsonb_typeof(table_rows) <> 'array' then
      raise exception 'Falta la tabla % en el respaldo.', table_name;
    end if;
    if jsonb_array_length(table_rows) = 0 then
      restored_counts := restored_counts || jsonb_build_object(table_name, 0);
      continue;
    end if;
    select string_agg(format('%I', c.column_name), ', ' order by c.ordinal_position)
    into column_names
    from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = table_name and c.is_generated = 'NEVER';
    if table_name = 'profiles' then
      insert into public.profiles (user_id, display_name, created_at, updated_at)
      select row.user_id, row.display_name, row.created_at, row.updated_at
      from jsonb_populate_recordset(null::public.profiles, table_rows) row
      on conflict (user_id) do update set display_name = excluded.display_name, created_at = excluded.created_at, updated_at = excluded.updated_at;
      restored_counts := restored_counts || jsonb_build_object(table_name, jsonb_array_length(table_rows));
      continue;
    end if;
    if table_name = 'sales' then
      select coalesce(jsonb_agg(value - 'sale_price_authorization_id'), '[]'::jsonb) into table_rows
      from jsonb_array_elements(table_rows);
    end if;
    sql := format(
      'insert into public.%1$I (%2$s) overriding system value select %2$s from jsonb_populate_recordset(null::public.%1$I, $1)',
      table_name, column_names
    );
    execute sql using table_rows;
    restored_counts := restored_counts || jsonb_build_object(table_name, jsonb_array_length(table_rows));
  end loop;
  update public.sales sale
  set sale_price_authorization_id = (source.value ->> 'sale_price_authorization_id')::uuid
  from jsonb_array_elements(p_payload -> 'tables' -> 'sales') source
  where sale.id = (source.value ->> 'id')::uuid
    and source.value ->> 'sale_price_authorization_id' is not null;
  return jsonb_build_object('business_id', p_payload ->> 'business_id', 'table_counts', restored_counts);
end;
$$;

create function public.validate_restored_business_backup(p_business_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare errors jsonb;
begin
  if current_setting('app.backup_restore_isolated', true) <> 'true' then
    raise exception 'La validación de restauración requiere una instancia local aislada.';
  end if;
  select coalesce(jsonb_agg(error), '[]'::jsonb) into errors from (
    select jsonb_build_object('rule', 'sale_totals', 'sale_id', sale.id) as error
    from public.sales sale
    where sale.business_id = p_business_id
      and (select coalesce(sum(line.line_total), 0) from public.sale_lines line where line.sale_id = sale.id) <> sale.total_amount
    union all
    select jsonb_build_object('rule', 'sale_payments', 'sale_id', sale.id)
    from public.sales sale
    where sale.business_id = p_business_id
      and (select coalesce(sum(payment.amount), 0) from public.sale_payments payment where payment.sale_id = sale.id) <> sale.total_amount
    union all
    select jsonb_build_object('rule', 'purchase_totals', 'purchase_id', purchase.id)
    from public.purchases purchase
    where purchase.business_id = p_business_id
      and (select coalesce(sum(line.line_total), 0) from public.purchase_lines line where line.purchase_id = purchase.id) <> purchase.total_amount
    union all
    select jsonb_build_object('rule', 'lot_quantity', 'lot_id', lot.id)
    from public.inventory_lots lot
    where lot.business_id = p_business_id and lot.received_quantity <= 0
  ) violations;
  return jsonb_build_object('valid', jsonb_array_length(errors) = 0, 'errors', errors);
end;
$$;

revoke all on function public.get_business_backup_data(uuid) from public;
grant execute on function public.get_business_backup_data(uuid) to authenticated, service_role;
revoke all on function public.restore_business_backup_data(jsonb) from public;
revoke all on function public.validate_restored_business_backup(uuid) from public;
