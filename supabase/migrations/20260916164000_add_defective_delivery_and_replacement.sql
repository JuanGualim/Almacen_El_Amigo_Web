-- Completa el ciclo de defectuosos sin convertir una reclasificación en una
-- salida silenciosa: se entrega por lote y el reemplazo entra como lote nuevo.
create table public.defective_product_deliveries (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  defective_product_id uuid not null unique references public.defective_products(id) on delete restrict,
  request_id uuid not null,
  delivered_by uuid not null references auth.users(id) on delete restrict,
  delivered_at timestamptz not null default now(),
  constraint defective_product_deliveries_product_business
    foreign key (defective_product_id, business_id) references public.defective_products(id, business_id) on delete restrict,
  constraint defective_product_deliveries_request_unique unique (business_id, request_id)
);

create table public.defective_product_delivery_lots (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.defective_product_deliveries(id) on delete restrict,
  reclassification_id uuid not null unique references public.inventory_lot_reclassifications(id) on delete restrict,
  quantity integer not null check (quantity > 0)
);

create table public.defective_product_replacements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  defective_product_id uuid not null unique references public.defective_products(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  request_id uuid not null,
  replaced_by uuid not null references auth.users(id) on delete restrict,
  replaced_at timestamptz not null default now(),
  constraint defective_product_replacements_product_business
    foreign key (defective_product_id, business_id) references public.defective_products(id, business_id) on delete restrict,
  constraint defective_product_replacements_request_unique unique (business_id, request_id)
);

alter table public.defective_product_deliveries enable row level security;
alter table public.defective_product_delivery_lots enable row level security;
alter table public.defective_product_replacements enable row level security;
create policy "members read defective deliveries" on public.defective_product_deliveries
  for select to authenticated using (public.has_business_permission(business_id, 'inventory.read'));
create policy "members read defective delivery lots" on public.defective_product_delivery_lots
  for select to authenticated using (exists (
    select 1 from public.defective_product_deliveries delivery
    where delivery.id = delivery_id and public.has_business_permission(delivery.business_id, 'inventory.read')
  ));
create policy "members read defective replacements" on public.defective_product_replacements
  for select to authenticated using (public.has_business_permission(business_id, 'inventory.read'));

create or replace function public.deliver_defective_product(
  p_business_id uuid,
  p_defective_product_id uuid,
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare defective_row public.defective_products%rowtype;
declare delivery_id uuid;
declare reclassification_row public.inventory_lot_reclassifications%rowtype;
declare delivery_lot_id uuid;
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'inventory.adjust') then
    raise exception 'No tienes permiso para entregar productos defectuosos.';
  end if;
  select id into delivery_id from public.defective_product_deliveries
  where business_id = p_business_id and request_id = p_request_id;
  if delivery_id is not null then return delivery_id; end if;
  select * into defective_row from public.defective_products
  where id = p_defective_product_id and business_id = p_business_id for update;
  if not found or defective_row.status <> 'pending_supplier' then
    raise exception 'El producto defectuoso no está pendiente de entrega.';
  end if;
  insert into public.defective_product_deliveries (
    business_id, defective_product_id, request_id, delivered_by
  ) values (
    p_business_id, defective_row.id, p_request_id, auth.uid()
  ) returning id into delivery_id;
  for reclassification_row in
    select * from public.inventory_lot_reclassifications
    where defective_product_id = defective_row.id
    order by created_at, id
  loop
    insert into public.defective_product_delivery_lots (delivery_id, reclassification_id, quantity)
    values (delivery_id, reclassification_row.id, reclassification_row.quantity)
    returning id into delivery_lot_id;
    insert into public.inventory_movements (
      business_id, variant_id, lot_id, movement_type, inventory_state, quantity_delta,
      source_type, source_id, occurred_at, created_by
    ) values (
      p_business_id, defective_row.variant_id, reclassification_row.lot_id, 'defective',
      'defective_pending', -reclassification_row.quantity, 'defective_delivery_from_pending',
      delivery_lot_id, now(), auth.uid()
    );
    insert into public.inventory_movements (
      business_id, variant_id, lot_id, movement_type, inventory_state, quantity_delta,
      source_type, source_id, occurred_at, created_by
    ) values (
      p_business_id, defective_row.variant_id, reclassification_row.lot_id, 'defective',
      'with_supplier', reclassification_row.quantity, 'defective_delivery_to_supplier',
      delivery_lot_id, now(), auth.uid()
    );
  end loop;
  update public.defective_products set status = 'delivered' where id = defective_row.id;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'defective_product.delivered', 'defective_product', defective_row.id,
          jsonb_build_object('delivery_id', delivery_id, 'quantity', defective_row.quantity));
  return delivery_id;
end;
$$;

create or replace function public.replace_defective_product(
  p_business_id uuid,
  p_defective_product_id uuid,
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare defective_row public.defective_products%rowtype;
declare replacement_id uuid;
declare lot_id uuid;
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'inventory.adjust') then
    raise exception 'No tienes permiso para registrar reemplazos de defectuosos.';
  end if;
  select id into replacement_id from public.defective_product_replacements
  where business_id = p_business_id and request_id = p_request_id;
  if replacement_id is not null then return replacement_id; end if;
  select * into defective_row from public.defective_products
  where id = p_defective_product_id and business_id = p_business_id for update;
  if not found or defective_row.status <> 'delivered' then
    raise exception 'El producto defectuoso debe estar entregado antes de registrar su reemplazo.';
  end if;
  insert into public.defective_product_replacements (
    business_id, defective_product_id, quantity, request_id, replaced_by
  ) values (
    p_business_id, defective_row.id, defective_row.quantity, p_request_id, auth.uid()
  ) returning id into replacement_id;
  insert into public.inventory_lots (
    business_id, variant_id, purchase_line_id, received_quantity, unit_cost,
    received_at, source_type, source_id
  ) values (
    p_business_id, defective_row.variant_id, null, defective_row.quantity, null,
    now(), 'defective_replacement', replacement_id
  ) returning id into lot_id;
  insert into public.inventory_movements (
    business_id, variant_id, lot_id, movement_type, inventory_state, quantity_delta,
    source_type, source_id, occurred_at, created_by
  ) values (
    p_business_id, defective_row.variant_id, lot_id, 'defective', 'available',
    defective_row.quantity, 'defective_replacement', replacement_id, now(), auth.uid()
  );
  update public.defective_products set status = 'replaced' where id = defective_row.id;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'defective_product.replaced', 'defective_product', defective_row.id,
          jsonb_build_object('replacement_id', replacement_id, 'quantity', defective_row.quantity));
  return replacement_id;
end;
$$;

revoke all on function public.deliver_defective_product(uuid, uuid, uuid) from public;
grant execute on function public.deliver_defective_product(uuid, uuid, uuid) to authenticated;
revoke all on function public.replace_defective_product(uuid, uuid, uuid) from public;
grant execute on function public.replace_defective_product(uuid, uuid, uuid) to authenticated;
