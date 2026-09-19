-- Exportaciones estructuradas y registro privado de respaldos.

create type public.business_backup_kind as enum ('manual', 'automatic_daily', 'automatic_monthly');

create table public.business_backups (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  backup_kind public.business_backup_kind not null,
  snapshot jsonb not null,
  manifest jsonb not null,
  checksum_sha256 text not null check (checksum_sha256 ~ '^[0-9a-f]{64}$'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint business_backups_manifest_object check (jsonb_typeof(manifest) = 'object'),
  constraint business_backups_snapshot_object check (jsonb_typeof(snapshot) = 'object')
);

create index business_backups_business_kind_created_idx
  on public.business_backups (business_id, backup_kind, created_at desc);

alter table public.business_backups enable row level security;
create policy "owners read business backups" on public.business_backups for select to authenticated
using (public.is_business_owner(business_id));

create function public.build_business_structured_export(p_business_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, storage
as $$
  select jsonb_build_object(
    'format', 'almacen-el-amigo-structured-export-v1',
    'generated_at', now(),
    'business', (select to_jsonb(business) from public.businesses business where business.id = p_business_id),
    'catalog', jsonb_build_object(
      'categories', coalesce((select jsonb_agg(to_jsonb(category)) from public.categories category where category.business_id = p_business_id), '[]'::jsonb),
      'brands', coalesce((select jsonb_agg(to_jsonb(brand)) from public.brands brand where brand.business_id = p_business_id), '[]'::jsonb),
      'products', coalesce((select jsonb_agg(to_jsonb(product)) from public.products product where product.business_id = p_business_id), '[]'::jsonb),
      'variants', coalesce((select jsonb_agg(to_jsonb(variant)) from public.product_variants variant where variant.business_id = p_business_id), '[]'::jsonb),
      'current_prices', coalesce((select jsonb_agg(to_jsonb(price)) from public.variant_current_prices price where price.business_id = p_business_id), '[]'::jsonb)
    ),
    'operations', jsonb_build_object(
      'suppliers', coalesce((select jsonb_agg(to_jsonb(supplier)) from public.suppliers supplier where supplier.business_id = p_business_id), '[]'::jsonb),
      'purchases', coalesce((select jsonb_agg(to_jsonb(purchase)) from public.purchases purchase where purchase.business_id = p_business_id), '[]'::jsonb),
      'lots', coalesce((select jsonb_agg(to_jsonb(lot)) from public.inventory_lots lot where lot.business_id = p_business_id), '[]'::jsonb),
      'inventory_movements', coalesce((select jsonb_agg(to_jsonb(movement)) from public.inventory_movements movement where movement.business_id = p_business_id), '[]'::jsonb),
      'sales', coalesce((select jsonb_agg(to_jsonb(sale)) from public.sales sale where sale.business_id = p_business_id), '[]'::jsonb),
      'cash_sessions', coalesce((select jsonb_agg(to_jsonb(session)) from public.cash_register_sessions session where session.business_id = p_business_id), '[]'::jsonb),
      'supplier_payments', coalesce((select jsonb_agg(to_jsonb(payment)) from public.supplier_payments payment where payment.business_id = p_business_id), '[]'::jsonb)
    ),
    'attachments_manifest', coalesce((
      select jsonb_agg(jsonb_build_object('bucket_id', object.bucket_id, 'name', object.name, 'metadata', object.metadata, 'updated_at', object.updated_at))
      from storage.objects object
      where object.name like p_business_id::text || '/%'
    ), '[]'::jsonb)
  );
$$;

create function public.get_business_structured_export(p_business_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_business_owner(p_business_id) then
    raise exception 'Solo el dueño puede generar una exportación estructurada.';
  end if;
  return public.build_business_structured_export(p_business_id);
end;
$$;

create function public.create_manual_business_backup(p_business_id uuid)
returns table (backup_id uuid, snapshot jsonb, checksum_sha256 text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare payload jsonb; checksum text; created_backup_id uuid;
begin
  if auth.uid() is null or not public.is_business_owner(p_business_id) then
    raise exception 'Solo el dueño puede generar respaldos completos.';
  end if;
  payload := public.build_business_structured_export(p_business_id);
  checksum := encode(digest(convert_to(payload::text, 'UTF8'), 'sha256'), 'hex');
  insert into public.business_backups (business_id, backup_kind, snapshot, manifest, checksum_sha256, created_by)
  values (p_business_id, 'manual', payload,
    jsonb_build_object('format', 'almacen-el-amigo-backup-v1', 'attachments_included', payload -> 'attachments_manifest', 'checksum_algorithm', 'sha256'),
    checksum, auth.uid()) returning id into created_backup_id;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'business_backup.created', 'business_backup', created_backup_id, jsonb_build_object('kind', 'manual', 'checksum_sha256', checksum));
  return query select created_backup_id, payload, checksum;
end;
$$;

revoke all on function public.get_business_structured_export(uuid) from public;
grant execute on function public.get_business_structured_export(uuid) to authenticated;
revoke all on function public.create_manual_business_backup(uuid) from public;
grant execute on function public.create_manual_business_backup(uuid) to authenticated;
