-- Las resoluciones son un documento separado del estado operativo del
-- defectuoso. Así se conserva qué ocurrió y se evita que una unidad quede
-- apartada indefinidamente después de un acuerdo final.
alter type public.defective_product_status rename value 'delivered' to 'delivered_to_supplier';
create type public.defective_resolution_type as enum (
  'replacement',
  'returned_to_stock',
  'supplier_credit',
  'supplier_refund',
  'accepted_loss'
);
create type public.defective_resolution_status as enum ('pending_confirmation', 'confirmed');

create table public.defective_product_resolutions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  defective_product_id uuid not null unique references public.defective_products(id) on delete restrict,
  supplier_id uuid,
  resolution_type public.defective_resolution_type not null,
  status public.defective_resolution_status not null default 'pending_confirmation',
  reason text not null check (char_length(btrim(reason)) between 3 and 500),
  amount numeric(14, 2),
  evidence_path text,
  request_id uuid not null,
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  confirmed_by uuid references auth.users(id) on delete restrict,
  confirmed_at timestamptz,
  confirmation_request_id uuid,
  constraint defective_product_resolutions_supplier_business
    foreign key (supplier_id, business_id) references public.suppliers(id, business_id) on delete restrict,
  constraint defective_product_resolutions_request_unique unique (business_id, request_id),
  constraint defective_product_resolutions_confirmation_request_unique unique (business_id, confirmation_request_id),
  constraint defective_product_resolutions_amount check (
    (resolution_type in ('supplier_credit', 'supplier_refund') and amount is not null and amount > 0)
    or (resolution_type not in ('supplier_credit', 'supplier_refund') and amount is null)
  ),
  constraint defective_product_resolutions_evidence_length check (
    evidence_path is null or char_length(btrim(evidence_path)) between 1 and 500
  ),
  constraint defective_product_resolutions_confirmed_fields check (
    (status = 'pending_confirmation' and confirmed_by is null and confirmed_at is null)
    or (status = 'confirmed' and confirmed_by is not null and confirmed_at is not null)
  )
);

create table public.defective_product_resolution_lots (
  id uuid primary key default gen_random_uuid(),
  resolution_id uuid not null references public.defective_product_resolutions(id) on delete restrict,
  reclassification_id uuid not null references public.inventory_lot_reclassifications(id) on delete restrict,
  lot_id uuid not null references public.inventory_lots(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  source_inventory_movement_id uuid references public.inventory_movements(id) on delete restrict,
  target_inventory_movement_id uuid references public.inventory_movements(id) on delete restrict,
  constraint defective_product_resolution_lots_resolution_reclassification_unique unique (resolution_id, reclassification_id)
);

create table public.inventory_lot_reclassification_releases (
  id uuid primary key default gen_random_uuid(),
  reclassification_id uuid not null unique references public.inventory_lot_reclassifications(id) on delete restrict,
  resolution_lot_id uuid not null unique references public.defective_product_resolution_lots(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  created_at timestamptz not null default now()
);

create table public.supplier_credits (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  supplier_id uuid not null,
  defective_resolution_id uuid not null unique references public.defective_product_resolutions(id) on delete restrict,
  amount numeric(14, 2) not null check (amount > 0),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint supplier_credits_supplier_business
    foreign key (supplier_id, business_id) references public.suppliers(id, business_id) on delete restrict
);

create table public.supplier_refunds (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  supplier_id uuid not null,
  defective_resolution_id uuid not null unique references public.defective_product_resolutions(id) on delete restrict,
  amount numeric(14, 2) not null check (amount > 0),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint supplier_refunds_supplier_business
    foreign key (supplier_id, business_id) references public.suppliers(id, business_id) on delete restrict
);

create index defective_product_resolutions_business_status_idx
  on public.defective_product_resolutions (business_id, status, recorded_at desc);
create index supplier_credits_business_supplier_idx on public.supplier_credits (business_id, supplier_id);
create index supplier_refunds_business_supplier_idx on public.supplier_refunds (business_id, supplier_id);

alter table public.defective_product_resolutions enable row level security;
alter table public.defective_product_resolution_lots enable row level security;
alter table public.inventory_lot_reclassification_releases enable row level security;
alter table public.supplier_credits enable row level security;
alter table public.supplier_refunds enable row level security;
create policy "owners or recorders read defective resolutions" on public.defective_product_resolutions
  for select to authenticated using (public.is_business_owner(business_id) or recorded_by = auth.uid());
create policy "owners or recorders read resolution lots" on public.defective_product_resolution_lots
  for select to authenticated using (exists (
    select 1 from public.defective_product_resolutions resolution
    where resolution.id = resolution_id
      and (public.is_business_owner(resolution.business_id) or resolution.recorded_by = auth.uid())
  ));
create policy "owners read reclassification releases" on public.inventory_lot_reclassification_releases
  for select to authenticated using (exists (
    select 1 from public.defective_product_resolution_lots resolution_lot
    join public.defective_product_resolutions resolution on resolution.id = resolution_lot.resolution_id
    where resolution_lot.id = resolution_lot_id and public.is_business_owner(resolution.business_id)
  ));
create policy "owners read supplier credits" on public.supplier_credits
  for select to authenticated using (public.has_business_permission(business_id, 'payables.read'));
create policy "owners read supplier refunds" on public.supplier_refunds
  for select to authenticated using (public.has_business_permission(business_id, 'payables.read'));

create or replace function public.get_inventory_lot_available_quantity(p_lot_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select lot.received_quantity
    - coalesce((
        select sum(allocation.quantity)
        from public.inventory_lot_allocations allocation
        where allocation.lot_id = lot.id
          and allocation.allocation_kind in ('consumption', 'legacy_backfill')
      ), 0)::integer
    + coalesce((
        select sum(allocation.quantity)
        from public.inventory_lot_allocations allocation
        where allocation.lot_id = lot.id
          and allocation.allocation_kind = 'reversal'
      ), 0)::integer
    - coalesce((
        select sum(reclassification.quantity)
        from public.inventory_lot_reclassifications reclassification
        where reclassification.lot_id = lot.id
      ), 0)::integer
    + coalesce((
        select sum(release.quantity)
        from public.inventory_lot_reclassification_releases release
        join public.defective_product_resolution_lots resolution_lot
          on resolution_lot.id = release.resolution_lot_id
        where resolution_lot.lot_id = lot.id
      ), 0)::integer
    - coalesce((
        select sum(-movement.quantity_delta)
        from public.inventory_movements movement
        where movement.lot_id = lot.id
          and movement.inventory_state = 'available'
          and movement.quantity_delta < 0
          and movement.movement_type <> 'defective'
      ), 0)::integer
  from public.inventory_lots lot
  where lot.id = p_lot_id;
$$;

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
  insert into public.defective_product_deliveries (business_id, defective_product_id, request_id, delivered_by)
  values (p_business_id, defective_row.id, p_request_id, auth.uid()) returning id into delivery_id;
  for reclassification_row in
    select * from public.inventory_lot_reclassifications
    where defective_product_id = defective_row.id order by created_at, id
  loop
    insert into public.defective_product_delivery_lots (delivery_id, reclassification_id, quantity)
    values (delivery_id, reclassification_row.id, reclassification_row.quantity)
    returning id into delivery_lot_id;
    insert into public.inventory_movements (business_id, variant_id, lot_id, movement_type, inventory_state, quantity_delta, source_type, source_id, occurred_at, created_by)
    values (p_business_id, defective_row.variant_id, reclassification_row.lot_id, 'defective', 'defective_pending', -reclassification_row.quantity, 'defective_delivery_from_pending', delivery_lot_id, now(), auth.uid());
    insert into public.inventory_movements (business_id, variant_id, lot_id, movement_type, inventory_state, quantity_delta, source_type, source_id, occurred_at, created_by)
    values (p_business_id, defective_row.variant_id, reclassification_row.lot_id, 'defective', 'with_supplier', reclassification_row.quantity, 'defective_delivery_to_supplier', delivery_lot_id, now(), auth.uid());
  end loop;
  update public.defective_products set status = 'delivered_to_supplier' where id = defective_row.id;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'defective_product.delivered', 'defective_product', defective_row.id, jsonb_build_object('delivery_id', delivery_id));
  return delivery_id;
end;
$$;

create or replace function public.record_defective_product_resolution(
  p_business_id uuid,
  p_defective_product_id uuid,
  p_supplier_id uuid,
  p_resolution_type public.defective_resolution_type,
  p_reason text,
  p_amount numeric,
  p_evidence_path text,
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare resolution_id uuid;
declare defective_row public.defective_products%rowtype;
declare effective_supplier_id uuid;
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'inventory.read') then
    raise exception 'No tienes permiso para registrar la resolución de un defectuoso.';
  end if;
  select id into resolution_id from public.defective_product_resolutions
  where business_id = p_business_id and request_id = p_request_id;
  if resolution_id is not null then return resolution_id; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 then
    raise exception 'Indica un motivo de resolución válido.';
  end if;
  if p_resolution_type is null then raise exception 'Selecciona un tipo de resolución.'; end if;
  select * into defective_row from public.defective_products
  where id = p_defective_product_id and business_id = p_business_id for update;
  if not found or defective_row.status not in ('pending_supplier', 'delivered_to_supplier') then
    raise exception 'El producto defectuoso no está disponible para resolución.';
  end if;
  effective_supplier_id := coalesce(p_supplier_id, defective_row.supplier_id);
  if p_resolution_type in ('supplier_credit', 'supplier_refund') and effective_supplier_id is null then
    raise exception 'El crédito o reembolso requiere un distribuidor.';
  end if;
  if effective_supplier_id is not null and not exists (
    select 1 from public.suppliers where id = effective_supplier_id and business_id = p_business_id
  ) then
    raise exception 'El distribuidor no pertenece al negocio.';
  end if;
  if (p_resolution_type in ('supplier_credit', 'supplier_refund') and (p_amount is null or p_amount <= 0 or p_amount <> round(p_amount, 2)))
    or (p_resolution_type not in ('supplier_credit', 'supplier_refund') and p_amount is not null) then
    raise exception 'El importe solo es obligatorio para crédito o reembolso y debe ser válido.';
  end if;
  insert into public.defective_product_resolutions (
    business_id, defective_product_id, supplier_id, resolution_type, reason, amount,
    evidence_path, request_id, recorded_by
  ) values (
    p_business_id, defective_row.id, effective_supplier_id, p_resolution_type, btrim(p_reason),
    p_amount, nullif(btrim(p_evidence_path), ''), p_request_id, auth.uid()
  ) returning id into resolution_id;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'defective_product_resolution.recorded', 'defective_product_resolution', resolution_id,
          jsonb_build_object('type', p_resolution_type));
  return resolution_id;
end;
$$;

create or replace function public.confirm_defective_product_resolution(
  p_business_id uuid,
  p_resolution_id uuid,
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare resolution_row public.defective_product_resolutions%rowtype;
declare defective_row public.defective_products%rowtype;
declare reclassification_row public.inventory_lot_reclassifications%rowtype;
declare resolution_lot_id uuid;
declare source_movement_id uuid;
declare target_movement_id uuid;
declare source_state public.inventory_state;
declare replacement_lot_id uuid;
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'inventory.read') then
    raise exception 'No tienes permiso para confirmar resoluciones.';
  end if;
  select * into resolution_row from public.defective_product_resolutions
  where id = p_resolution_id and business_id = p_business_id for update;
  if not found then raise exception 'La resolución no está disponible.'; end if;
  if resolution_row.status = 'confirmed' then return resolution_row.id; end if;
  if resolution_row.resolution_type <> 'replacement' and not public.is_business_owner(p_business_id) then
    raise exception 'Solo el dueño puede confirmar una resolución sin reemplazo.';
  end if;
  select * into defective_row from public.defective_products
  where id = resolution_row.defective_product_id and business_id = p_business_id for update;
  if not found or defective_row.status not in ('pending_supplier', 'delivered_to_supplier') then
    raise exception 'El estado operativo del defectuoso ya no permite esta resolución.';
  end if;
  if exists (
    select 1 from public.defective_product_resolutions
    where business_id = p_business_id and confirmation_request_id = p_request_id
  ) then return resolution_row.id; end if;
  source_state := case when defective_row.status = 'pending_supplier' then 'defective_pending'::public.inventory_state else 'with_supplier'::public.inventory_state end;
  for reclassification_row in
    select * from public.inventory_lot_reclassifications
    where defective_product_id = defective_row.id order by created_at, id
  loop
    insert into public.defective_product_resolution_lots (resolution_id, reclassification_id, lot_id, quantity)
    values (resolution_row.id, reclassification_row.id, reclassification_row.lot_id, reclassification_row.quantity)
    returning id into resolution_lot_id;
    insert into public.inventory_movements (business_id, variant_id, lot_id, movement_type, inventory_state, quantity_delta, source_type, source_id, occurred_at, created_by)
    values (p_business_id, defective_row.variant_id, reclassification_row.lot_id, 'defective', source_state, -reclassification_row.quantity, 'defective_resolution_out', resolution_lot_id, now(), auth.uid())
    returning id into source_movement_id;
    if resolution_row.resolution_type = 'returned_to_stock' then
      insert into public.inventory_movements (business_id, variant_id, lot_id, movement_type, inventory_state, quantity_delta, source_type, source_id, occurred_at, created_by)
      values (p_business_id, defective_row.variant_id, reclassification_row.lot_id, 'defective', 'available', reclassification_row.quantity, 'defective_resolution_return', resolution_lot_id, now(), auth.uid())
      returning id into target_movement_id;
      insert into public.inventory_lot_reclassification_releases (reclassification_id, resolution_lot_id, quantity)
      values (reclassification_row.id, resolution_lot_id, reclassification_row.quantity);
      update public.defective_product_resolution_lots
      set source_inventory_movement_id = source_movement_id, target_inventory_movement_id = target_movement_id
      where id = resolution_lot_id;
    else
      update public.defective_product_resolution_lots
      set source_inventory_movement_id = source_movement_id
      where id = resolution_lot_id;
    end if;
  end loop;
  if resolution_row.resolution_type = 'replacement' then
    insert into public.inventory_lots (business_id, variant_id, purchase_line_id, received_quantity, unit_cost, received_at, source_type, source_id)
    values (p_business_id, defective_row.variant_id, null, defective_row.quantity, null, now(), 'defective_replacement', resolution_row.id)
    returning id into replacement_lot_id;
    insert into public.inventory_movements (business_id, variant_id, lot_id, movement_type, inventory_state, quantity_delta, source_type, source_id, occurred_at, created_by)
    values (p_business_id, defective_row.variant_id, replacement_lot_id, 'defective', 'available', defective_row.quantity, 'defective_replacement', resolution_row.id, now(), auth.uid());
  elsif resolution_row.resolution_type = 'supplier_credit' then
    insert into public.supplier_credits (business_id, supplier_id, defective_resolution_id, amount, created_by)
    values (p_business_id, resolution_row.supplier_id, resolution_row.id, resolution_row.amount, auth.uid());
  elsif resolution_row.resolution_type = 'supplier_refund' then
    insert into public.supplier_refunds (business_id, supplier_id, defective_resolution_id, amount, created_by)
    values (p_business_id, resolution_row.supplier_id, resolution_row.id, resolution_row.amount, auth.uid());
  end if;
  update public.defective_product_resolutions
  set status = 'confirmed', confirmed_by = auth.uid(), confirmed_at = now(), confirmation_request_id = p_request_id
  where id = resolution_row.id;
  update public.defective_products set status = 'resolved' where id = defective_row.id;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'defective_product_resolution.confirmed', 'defective_product_resolution', resolution_row.id,
          jsonb_build_object('type', resolution_row.resolution_type, 'amount', resolution_row.amount));
  return resolution_row.id;
end;
$$;

create or replace function public.get_supplier_balances(p_business_id uuid)
returns table(supplier_id uuid, supplier_name text, balance numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'payables.read') then
    raise exception 'No tienes permiso para consultar saldos.';
  end if;
  return query
  select supplier.id, supplier.name,
    coalesce(entries.total, 0) - coalesce(payments.total, 0) - coalesce(credits.total, 0)
  from public.suppliers supplier
  left join lateral (
    select sum(entry.amount) as total from public.supplier_account_entries entry where entry.supplier_id = supplier.id
  ) entries on true
  left join lateral (
    select sum(payment.amount) as total from public.supplier_payments payment
    where payment.supplier_id = supplier.id and payment.status = 'confirmed'
  ) payments on true
  left join lateral (
    select sum(credit.amount) as total from public.supplier_credits credit where credit.supplier_id = supplier.id
  ) credits on true
  where supplier.business_id = p_business_id
  order by supplier.name;
end;
$$;

revoke all on function public.replace_defective_product(uuid, uuid, uuid) from authenticated;
revoke all on function public.record_defective_product_resolution(uuid, uuid, uuid, public.defective_resolution_type, text, numeric, text, uuid) from public;
grant execute on function public.record_defective_product_resolution(uuid, uuid, uuid, public.defective_resolution_type, text, numeric, text, uuid) to authenticated;
revoke all on function public.confirm_defective_product_resolution(uuid, uuid, uuid) from public;
grant execute on function public.confirm_defective_product_resolution(uuid, uuid, uuid) to authenticated;
revoke all on function public.get_supplier_balances(uuid) from public;
grant execute on function public.get_supplier_balances(uuid) to authenticated;
