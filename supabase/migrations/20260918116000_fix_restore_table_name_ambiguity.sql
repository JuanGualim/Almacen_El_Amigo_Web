-- Evita la ambigüedad de PL/pgSQL entre la variable de iteración y
-- information_schema.columns.table_name durante una restauración aislada.

create or replace function public.restore_business_backup_data(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  restore_table_name text;
  table_rows jsonb;
  column_names text;
  sql text;
  restored_counts jsonb := '{}'::jsonb;
  ordered_tables text[] := array[
    'businesses', 'profiles', 'business_roles', 'business_role_permissions', 'business_memberships', 'membership_permission_overrides', 'business_invitations',
    'categories', 'brands', 'products', 'product_variants', 'variant_current_prices', 'variant_price_history', 'suppliers', 'purchases', 'purchase_lines',
    'inventory_lots', 'inventory_movements', 'supplier_account_entries', 'purchase_price_reviews', 'cash_register_sessions', 'sales', 'sale_lines', 'sale_payments',
    'owner_authorization_pins', 'sale_price_authorizations', 'supplier_payments', 'supplier_payment_applications', 'inventory_adjustments', 'inventory_lot_allocations',
    'inventory_authorized_exits', 'defective_products', 'inventory_lot_reclassifications', 'defective_product_deliveries',
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

  foreach restore_table_name in array ordered_tables loop
    table_rows := p_payload -> 'tables' -> restore_table_name;
    if table_rows is null or jsonb_typeof(table_rows) <> 'array' then
      raise exception 'Falta la tabla % en el respaldo.', restore_table_name;
    end if;
    if jsonb_array_length(table_rows) = 0 then
      restored_counts := restored_counts || jsonb_build_object(restore_table_name, 0);
      continue;
    end if;
    select string_agg(format('%I', c.column_name), ', ' order by c.ordinal_position)
    into column_names
    from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = restore_table_name and c.is_generated = 'NEVER';
    if restore_table_name = 'profiles' then
      insert into public.profiles (user_id, display_name, created_at, updated_at)
      select row.user_id, row.display_name, row.created_at, row.updated_at
      from jsonb_populate_recordset(null::public.profiles, table_rows) row
      on conflict (user_id) do update set display_name = excluded.display_name, created_at = excluded.created_at, updated_at = excluded.updated_at;
      restored_counts := restored_counts || jsonb_build_object(restore_table_name, jsonb_array_length(table_rows));
      continue;
    end if;
    if restore_table_name = 'sales' then
      select coalesce(jsonb_agg(value - 'sale_price_authorization_id'), '[]'::jsonb) into table_rows
      from jsonb_array_elements(table_rows);
    end if;
    sql := format(
      'insert into public.%1$I (%2$s) overriding system value select %2$s from jsonb_populate_recordset(null::public.%1$I, $1)',
      restore_table_name, column_names
    );
    execute sql using table_rows;
    restored_counts := restored_counts || jsonb_build_object(restore_table_name, jsonb_array_length(table_rows));
  end loop;
  update public.sales sale
  set sale_price_authorization_id = (source.value ->> 'sale_price_authorization_id')::uuid
  from jsonb_array_elements(p_payload -> 'tables' -> 'sales') source
  where sale.id = (source.value ->> 'id')::uuid
    and source.value ->> 'sale_price_authorization_id' is not null;
  return jsonb_build_object('business_id', p_payload ->> 'business_id', 'table_counts', restored_counts);
end;
$$;
