-- Fase 6: las salidas nuevas se asignan por lote y las reversiones nunca
-- modifican las asignaciones originales. Esta migración no modifica datos
-- históricos: agrega trazabilidad complementaria para los ajustes y
-- reclasificaciones que existían antes de FIFO.

alter type public.inventory_movement_type add value if not exists 'sale_cancellation';
alter type public.inventory_movement_type add value if not exists 'exchange';
alter type public.inventory_movement_type add value if not exists 'purchase_cancellation';

alter table public.inventory_lots alter column purchase_line_id drop not null;
alter table public.inventory_lots alter column unit_cost drop not null;
alter table public.inventory_lots add column source_type text;
alter table public.inventory_lots add column source_id uuid;

update public.inventory_lots
set source_type = 'purchase_line', source_id = purchase_line_id
where source_type is null;

alter table public.inventory_lots
  alter column source_type set not null,
  alter column source_id set not null;

alter table public.inventory_lots add constraint inventory_lots_source_not_blank
  check (btrim(source_type) <> '');

alter table public.defective_products add constraint defective_products_id_business_unique unique (id, business_id);

create table public.inventory_lot_reclassifications (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  lot_id uuid not null,
  defective_product_id uuid references public.defective_products(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  source_inventory_movement_id uuid references public.inventory_movements(id) on delete restrict,
  target_inventory_movement_id uuid references public.inventory_movements(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint inventory_lot_reclassifications_lot_business
    foreign key (lot_id, business_id) references public.inventory_lots(id, business_id) on delete restrict,
  constraint inventory_lot_reclassifications_defective_business
    foreign key (defective_product_id, business_id) references public.defective_products(id, business_id) on delete restrict,
  constraint inventory_lot_reclassifications_movements_different
    check (source_inventory_movement_id is null or target_inventory_movement_id is null or source_inventory_movement_id <> target_inventory_movement_id)
);

create index inventory_lot_reclassifications_lot_idx
  on public.inventory_lot_reclassifications (lot_id, created_at);

alter table public.inventory_lot_reclassifications enable row level security;
create policy "members read lot reclassifications" on public.inventory_lot_reclassifications
  for select to authenticated using (public.has_business_permission(business_id, 'inventory.read'));

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

-- Los ajustes positivos previos a FIFO son entradas físicas auditables, no
-- compras ficticias. Se les da un lote especial para que puedan consumirse.
insert into public.inventory_lots (
  business_id, variant_id, purchase_line_id, received_quantity, unit_cost,
  received_at, source_type, source_id
)
select movement.business_id, movement.variant_id, null, movement.quantity_delta,
       null, movement.occurred_at, 'legacy_inventory_adjustment', movement.id
from public.inventory_movements movement
where movement.movement_type = 'adjustment'
  and movement.inventory_state = 'available'
  and movement.quantity_delta > 0
  and movement.lot_id is null;

-- Las reclasificaciones antiguas de defectuosos no son consumos definitivos.
-- Se distribuyen sobre los lotes remanentes para que no vuelvan a venderse.
do $$
declare
  movement_row record;
  lot_row record;
  reclassification_id uuid;
  remaining integer;
  lot_available integer;
begin
  for movement_row in
    select movement.*
    from public.inventory_movements movement
    where movement.movement_type = 'defective'
      and movement.inventory_state = 'available'
      and movement.quantity_delta < 0
      and movement.lot_id is null
    order by movement.occurred_at, movement.created_at, movement.id
  loop
    remaining := -movement_row.quantity_delta;
    for lot_row in
      select lot.*
      from public.inventory_lots lot
      where lot.business_id = movement_row.business_id
        and lot.variant_id = movement_row.variant_id
      order by lot.received_at, lot.created_at, lot.id
    loop
      lot_available := public.get_inventory_lot_available_quantity(lot_row.id);
      if lot_available > 0 then
        reclassification_id := gen_random_uuid();
        insert into public.inventory_lot_reclassifications (
          id, business_id, lot_id, defective_product_id, quantity,
          source_inventory_movement_id
        )
        select reclassification_id, movement_row.business_id, lot_row.id,
               defective.id, least(remaining, lot_available), movement_row.id
        from public.defective_products defective
        where defective.id = movement_row.source_id
          and defective.business_id = movement_row.business_id;
        if not found then
          raise exception 'FIFO defective backfill failed for movement %: missing defective product', movement_row.id;
        end if;
        remaining := remaining - least(remaining, lot_available);
        exit when remaining = 0;
      end if;
    end loop;
    if remaining <> 0 then
      raise exception 'FIFO defective backfill failed for movement %: insufficient lot quantity', movement_row.id;
    end if;
  end loop;
end;
$$;

create or replace function public.validate_inventory_lot_allocation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  lot_row public.inventory_lots%rowtype;
  movement_row public.inventory_movements%rowtype;
  original_row public.inventory_lot_allocations%rowtype;
  reversed_quantity integer;
begin
  select * into lot_row
  from public.inventory_lots
  where id = new.lot_id and business_id = new.business_id;
  if not found then
    raise exception 'El lote no pertenece al negocio de la asignación.';
  end if;

  select * into movement_row
  from public.inventory_movements
  where id = new.inventory_movement_id and business_id = new.business_id;
  if not found or movement_row.variant_id <> lot_row.variant_id then
    raise exception 'El movimiento y el lote deben pertenecer a la misma variante y negocio.';
  end if;

  if new.allocation_kind in ('consumption', 'legacy_backfill') then
    if movement_row.inventory_state <> 'available' or movement_row.quantity_delta >= 0 then
      raise exception 'Un consumo FIFO requiere un movimiento negativo de disponible.';
    end if;
    if new.quantity > public.get_inventory_lot_available_quantity(new.lot_id) then
      raise exception 'La asignación excede la cantidad disponible del lote.';
    end if;
  else
    select * into original_row
    from public.inventory_lot_allocations
    where id = new.original_allocation_id
    for update;
    if not found
      or original_row.business_id <> new.business_id
      or original_row.lot_id <> new.lot_id
      or original_row.allocation_kind not in ('consumption', 'legacy_backfill') then
      raise exception 'La reversión debe referir un consumo original del mismo lote y negocio.';
    end if;
    if movement_row.inventory_state <> 'available' or movement_row.quantity_delta <= 0 then
      raise exception 'Una reversión FIFO requiere un movimiento positivo de disponible.';
    end if;
    select coalesce(sum(quantity), 0)::integer into reversed_quantity
    from public.inventory_lot_allocations
    where original_allocation_id = original_row.id;
    if reversed_quantity + new.quantity > original_row.quantity then
      raise exception 'La reversión excede la asignación original.';
    end if;
  end if;
  return new;
end;
$$;

create trigger validate_inventory_lot_allocation_before_insert
before insert on public.inventory_lot_allocations
for each row execute procedure public.validate_inventory_lot_allocation();

create or replace function public.allocate_fifo_inventory_lots(
  p_business_id uuid,
  p_variant_id uuid,
  p_inventory_movement_id uuid,
  p_quantity integer,
  p_source_type text,
  p_source_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  lot_row public.inventory_lots%rowtype;
  remaining integer := p_quantity;
  lot_available integer;
  allocated_quantity integer;
begin
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'La cantidad FIFO debe ser un entero positivo.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_business_id::text || p_variant_id::text, 0));
  for lot_row in
    select *
    from public.inventory_lots
    where business_id = p_business_id and variant_id = p_variant_id
    order by received_at, created_at, id
    for update
  loop
    lot_available := public.get_inventory_lot_available_quantity(lot_row.id);
    if lot_available > 0 then
      allocated_quantity := least(remaining, lot_available);
      insert into public.inventory_lot_allocations (
        business_id, lot_id, inventory_movement_id, allocation_kind, quantity,
        source_type, source_id
      ) values (
        p_business_id, lot_row.id, p_inventory_movement_id, 'consumption',
        allocated_quantity, p_source_type, p_source_id
      );
      remaining := remaining - allocated_quantity;
      exit when remaining = 0;
    end if;
  end loop;
  if remaining <> 0 then
    raise exception 'No hay lotes disponibles suficientes para completar la operación.';
  end if;
end;
$$;

create or replace function public.create_fifo_consumption_movement(
  p_business_id uuid,
  p_variant_id uuid,
  p_movement_type public.inventory_movement_type,
  p_quantity integer,
  p_source_type text,
  p_source_id uuid,
  p_created_by uuid,
  p_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare movement_id uuid;
begin
  insert into public.inventory_movements (
    business_id, variant_id, movement_type, inventory_state, quantity_delta,
    source_type, source_id, occurred_at, created_by
  ) values (
    p_business_id, p_variant_id, p_movement_type, 'available', -p_quantity,
    p_source_type, p_source_id, p_occurred_at, p_created_by
  ) returning id into movement_id;

  perform public.allocate_fifo_inventory_lots(
    p_business_id, p_variant_id, movement_id, p_quantity, p_source_type, p_source_id
  );
  return movement_id;
end;
$$;

create or replace function public.reverse_fifo_source_allocations(
  p_business_id uuid,
  p_variant_id uuid,
  p_quantity integer,
  p_original_source_type text,
  p_original_source_id uuid,
  p_movement_type public.inventory_movement_type,
  p_source_type text,
  p_source_id uuid,
  p_created_by uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  original_row public.inventory_lot_allocations%rowtype;
  movement_id uuid;
  remaining integer := p_quantity;
  reversible_quantity integer;
  selected_quantity integer;
begin
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'La cantidad a revertir debe ser un entero positivo.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_business_id::text || p_variant_id::text, 0));

  select coalesce(sum(allocation.quantity - coalesce(reversed.quantity, 0)), 0)::integer
  into reversible_quantity
  from public.inventory_lot_allocations allocation
  left join lateral (
    select sum(reversal.quantity)::integer as quantity
    from public.inventory_lot_allocations reversal
    where reversal.original_allocation_id = allocation.id
  ) reversed on true
  where allocation.business_id = p_business_id
    and allocation.allocation_kind in ('consumption', 'legacy_backfill')
    and allocation.source_type = p_original_source_type
    and allocation.source_id = p_original_source_id;
  if reversible_quantity < p_quantity then
    raise exception 'No existe una asignación original suficiente para la reversión.';
  end if;

  insert into public.inventory_movements (
    business_id, variant_id, movement_type, inventory_state, quantity_delta,
    source_type, source_id, occurred_at, created_by
  ) values (
    p_business_id, p_variant_id, p_movement_type, 'available', p_quantity,
    p_source_type, p_source_id, now(), p_created_by
  ) returning id into movement_id;

  for original_row in
    select allocation.*
    from public.inventory_lot_allocations allocation
    left join lateral (
      select coalesce(sum(reversal.quantity), 0)::integer as quantity
      from public.inventory_lot_allocations reversal
      where reversal.original_allocation_id = allocation.id
    ) reversed on true
    where allocation.business_id = p_business_id
      and allocation.allocation_kind in ('consumption', 'legacy_backfill')
      and allocation.source_type = p_original_source_type
      and allocation.source_id = p_original_source_id
      and allocation.quantity > reversed.quantity
    order by allocation.created_at, allocation.id
  loop
    selected_quantity := least(remaining, original_row.quantity - coalesce((
      select sum(reversal.quantity)::integer
      from public.inventory_lot_allocations reversal
      where reversal.original_allocation_id = original_row.id
    ), 0));
    insert into public.inventory_lot_allocations (
      business_id, lot_id, inventory_movement_id, original_allocation_id,
      allocation_kind, quantity, source_type, source_id
    ) values (
      p_business_id, original_row.lot_id, movement_id, original_row.id,
      'reversal', selected_quantity, p_source_type, p_source_id
    );
    remaining := remaining - selected_quantity;
    exit when remaining = 0;
  end loop;
  if remaining <> 0 then
    raise exception 'No fue posible completar la reversión FIFO.';
  end if;
  return movement_id;
end;
$$;

create or replace function public.confirm_sale(
  p_business_id uuid,
  p_cash_session_id uuid,
  p_payment_method public.sale_payment_method,
  p_lines jsonb,
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  sale_id uuid;
  session_status public.cash_session_status;
  line_item record;
  variant_row record;
  calculated_total numeric(14, 2) := 0;
  sale_line_id uuid;
  authorized_lines text := current_setting('app.authorized_sale_lines', true);
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'sales.create') then
    raise exception 'No tienes permiso para registrar ventas.';
  end if;
  select id into sale_id from public.sales
  where business_id = p_business_id and request_id = p_request_id;
  if sale_id is not null then return sale_id; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'La venta debe contener al menos una línea.';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_lines) as line(variant_id uuid, quantity integer, unit_price numeric)
    where variant_id is null or quantity is null or quantity <= 0
      or unit_price is null or unit_price < 0 or unit_price <> round(unit_price, 2)
  ) then
    raise exception 'Cada línea requiere variante, cantidad entera positiva y precio válido.';
  end if;
  if (select count(*) from jsonb_to_recordset(p_lines) as line(variant_id uuid, quantity integer, unit_price numeric))
     <> (select count(distinct variant_id) from jsonb_to_recordset(p_lines) as line(variant_id uuid, quantity integer, unit_price numeric)) then
    raise exception 'Una variante solo puede aparecer una vez en la venta.';
  end if;
  select status into session_status from public.cash_register_sessions
  where id = p_cash_session_id and business_id = p_business_id for update;
  if session_status is distinct from 'open' then
    raise exception 'Debes tener una caja abierta para confirmar la venta.';
  end if;

  for line_item in
    select * from jsonb_to_recordset(p_lines) as line(variant_id uuid, quantity integer, unit_price numeric)
    order by variant_id
  loop
    perform pg_advisory_xact_lock(hashtextextended(p_business_id::text || line_item.variant_id::text, 0));
    select product.name as product_name, variant.internal_code as variant_code,
           variant.attributes, price.suggested_price, price.minimum_price
    into variant_row
    from public.product_variants variant
    join public.products product on product.id = variant.product_id
    join public.variant_current_prices price on price.variant_id = variant.id
    where variant.id = line_item.variant_id and variant.business_id = p_business_id
      and variant.is_active and product.is_active;
    if not found then raise exception 'Una variante no está disponible para venta en este negocio.'; end if;
    if line_item.unit_price < variant_row.minimum_price and authorized_lines is distinct from p_lines::text then
      raise exception 'El precio negociado no puede ser menor al precio mínimo.';
    end if;
    calculated_total := calculated_total + line_item.quantity * line_item.unit_price;
  end loop;

  insert into public.sales (business_id, cash_session_id, total_amount, sold_by, request_id)
  values (p_business_id, p_cash_session_id, calculated_total, auth.uid(), p_request_id)
  returning id into sale_id;

  for line_item in
    select * from jsonb_to_recordset(p_lines) as line(variant_id uuid, quantity integer, unit_price numeric)
    order by variant_id
  loop
    select product.name as product_name, variant.internal_code as variant_code,
           variant.attributes, price.suggested_price, price.minimum_price
    into variant_row
    from public.product_variants variant
    join public.products product on product.id = variant.product_id
    join public.variant_current_prices price on price.variant_id = variant.id
    where variant.id = line_item.variant_id and variant.business_id = p_business_id;
    insert into public.sale_lines (
      business_id, sale_id, variant_id, product_name_snapshot, variant_code_snapshot,
      attributes_snapshot, quantity, suggested_price_snapshot, minimum_price_snapshot, unit_price
    ) values (
      p_business_id, sale_id, line_item.variant_id, variant_row.product_name,
      variant_row.variant_code, variant_row.attributes, line_item.quantity,
      variant_row.suggested_price, variant_row.minimum_price, line_item.unit_price
    ) returning id into sale_line_id;
    perform public.create_fifo_consumption_movement(
      p_business_id, line_item.variant_id, 'sale', line_item.quantity,
      'sale_line', sale_line_id, auth.uid(), now()
    );
  end loop;

  insert into public.sale_payments (business_id, sale_id, payment_method, amount)
  values (p_business_id, sale_id, p_payment_method, calculated_total);
  if p_payment_method = 'cash' then
    insert into public.cash_movements (business_id, cash_session_id, sale_id, movement_type, amount, created_by)
    values (p_business_id, p_cash_session_id, sale_id, 'sale_cash', calculated_total, auth.uid());
  end if;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'sale.confirmed', 'sale', sale_id,
          jsonb_build_object('total', calculated_total, 'payment_method', p_payment_method));
  return sale_id;
end;
$$;

create or replace function public.confirm_sale_with_price_authorization(
  p_business_id uuid,
  p_cash_session_id uuid,
  p_payment_method public.sale_payment_method,
  p_lines jsonb,
  p_request_id uuid,
  p_authorization_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare authorization_row public.sale_price_authorizations%rowtype;
declare sale_id uuid;
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'sales.create') then
    raise exception 'No tienes permiso para registrar ventas.';
  end if;
  select id into sale_id from public.sales where business_id = p_business_id and request_id = p_request_id;
  if sale_id is not null then return sale_id; end if;
  select * into authorization_row from public.sale_price_authorizations
  where id = p_authorization_id and business_id = p_business_id for update;
  if not found or authorization_row.requested_by <> auth.uid()
    or authorization_row.status <> 'approved' or authorization_row.expires_at <= now()
    or authorization_row.lines <> p_lines then
    raise exception 'La autorización no es válida para esta venta.';
  end if;
  perform set_config('app.authorized_sale_lines', p_lines::text, true);
  sale_id := public.confirm_sale(p_business_id, p_cash_session_id, p_payment_method, p_lines, p_request_id);
  update public.sale_price_authorizations
  set status = 'consumed', consumed_sale_id = sale_id
  where id = p_authorization_id;
  update public.sales set sale_price_authorization_id = p_authorization_id where id = sale_id;
  return sale_id;
end;
$$;

create or replace function public.record_authorized_exit(
  p_business_id uuid,
  p_variant_id uuid,
  p_quantity integer,
  p_reason text,
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare exit_id uuid;
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'inventory.adjust') then
    raise exception 'No tienes permiso para registrar salidas.';
  end if;
  select id into exit_id from public.inventory_authorized_exits
  where business_id = p_business_id and request_id = p_request_id;
  if exit_id is not null then return exit_id; end if;
  if p_quantity is null or p_quantity <= 0 or p_reason is null or char_length(btrim(p_reason)) < 3 then
    raise exception 'La salida requiere cantidad positiva y un motivo válido.';
  end if;
  if not exists (select 1 from public.product_variants where id = p_variant_id and business_id = p_business_id) then
    raise exception 'La variante no pertenece al negocio.';
  end if;
  insert into public.inventory_authorized_exits (business_id, variant_id, quantity, reason, request_id, created_by)
  values (p_business_id, p_variant_id, p_quantity, btrim(p_reason), p_request_id, auth.uid())
  returning id into exit_id;
  perform public.create_fifo_consumption_movement(
    p_business_id, p_variant_id, 'authorized_exit', p_quantity,
    'authorized_exit', exit_id, auth.uid(), now()
  );
  return exit_id;
end;
$$;

create or replace function public.confirm_inventory_adjustment(
  p_business_id uuid,
  p_adjustment_id uuid,
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare adjustment_row public.inventory_adjustments%rowtype;
declare lot_id uuid;
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'inventory.adjust') then
    raise exception 'No tienes permiso para confirmar ajustes.';
  end if;
  select * into adjustment_row from public.inventory_adjustments
  where id = p_adjustment_id and business_id = p_business_id for update;
  if not found then raise exception 'El ajuste no está disponible.'; end if;
  if adjustment_row.status = 'confirmed' then return adjustment_row.id; end if;

  if adjustment_row.quantity_delta < 0 then
    perform public.create_fifo_consumption_movement(
      p_business_id, adjustment_row.variant_id, 'adjustment', -adjustment_row.quantity_delta,
      'inventory_adjustment', adjustment_row.id, auth.uid(), now()
    );
  else
    insert into public.inventory_lots (
      business_id, variant_id, purchase_line_id, received_quantity, unit_cost,
      received_at, source_type, source_id
    ) values (
      p_business_id, adjustment_row.variant_id, null, adjustment_row.quantity_delta,
      null, now(), 'inventory_adjustment', adjustment_row.id
    ) returning id into lot_id;
    insert into public.inventory_movements (
      business_id, variant_id, lot_id, movement_type, inventory_state, quantity_delta,
      source_type, source_id, occurred_at, created_by
    ) values (
      p_business_id, adjustment_row.variant_id, lot_id, 'adjustment', 'available',
      adjustment_row.quantity_delta, 'inventory_adjustment', adjustment_row.id, now(), auth.uid()
    );
  end if;
  update public.inventory_adjustments
  set status = 'confirmed', confirmed_by = auth.uid(), confirmed_at = now()
  where id = adjustment_row.id;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'inventory_adjustment.confirmed', 'inventory_adjustment', adjustment_row.id,
          jsonb_build_object('quantity_delta', adjustment_row.quantity_delta));
  return adjustment_row.id;
end;
$$;

create or replace function public.report_defective_product(
  p_business_id uuid,
  p_variant_id uuid,
  p_supplier_id uuid,
  p_quantity integer,
  p_description text,
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare defective_id uuid;
declare lot_row public.inventory_lots%rowtype;
declare remaining integer := p_quantity;
declare lot_available integer;
declare moved_quantity integer;
declare reclassification_id uuid;
declare source_movement_id uuid;
declare target_movement_id uuid;
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'inventory.read') then
    raise exception 'No tienes permiso para reportar defectuosos.';
  end if;
  select id into defective_id from public.defective_products
  where business_id = p_business_id and request_id = p_request_id;
  if defective_id is not null then return defective_id; end if;
  if p_quantity is null or p_quantity <= 0 or p_description is null or char_length(btrim(p_description)) < 3 then
    raise exception 'El reporte requiere cantidad positiva y una descripción válida.';
  end if;
  if not exists (select 1 from public.product_variants where id = p_variant_id and business_id = p_business_id) then
    raise exception 'La variante no pertenece al negocio.';
  end if;
  if p_supplier_id is not null and not exists (
    select 1 from public.suppliers where id = p_supplier_id and business_id = p_business_id
  ) then
    raise exception 'El distribuidor no pertenece al negocio.';
  end if;
  insert into public.defective_products (
    business_id, variant_id, supplier_id, quantity, description, request_id, reported_by
  ) values (
    p_business_id, p_variant_id, p_supplier_id, p_quantity, btrim(p_description), p_request_id, auth.uid()
  ) returning id into defective_id;

  perform pg_advisory_xact_lock(hashtextextended(p_business_id::text || p_variant_id::text, 0));
  for lot_row in
    select * from public.inventory_lots
    where business_id = p_business_id and variant_id = p_variant_id
    order by received_at, created_at, id
    for update
  loop
    lot_available := public.get_inventory_lot_available_quantity(lot_row.id);
    if lot_available > 0 then
      moved_quantity := least(remaining, lot_available);
      reclassification_id := gen_random_uuid();
      insert into public.inventory_lot_reclassifications (
        id, business_id, lot_id, defective_product_id, quantity
      ) values (
        reclassification_id, p_business_id, lot_row.id, defective_id, moved_quantity
      );
      insert into public.inventory_movements (
        business_id, variant_id, lot_id, movement_type, inventory_state, quantity_delta,
        source_type, source_id, occurred_at, created_by
      ) values (
        p_business_id, p_variant_id, lot_row.id, 'defective', 'available', -moved_quantity,
        'defective_available_lot', reclassification_id, now(), auth.uid()
      ) returning id into source_movement_id;
      insert into public.inventory_movements (
        business_id, variant_id, lot_id, movement_type, inventory_state, quantity_delta,
        source_type, source_id, occurred_at, created_by
      ) values (
        p_business_id, p_variant_id, lot_row.id, 'defective', 'defective_pending', moved_quantity,
        'defective_pending_lot', reclassification_id, now(), auth.uid()
      ) returning id into target_movement_id;
      update public.inventory_lot_reclassifications
      set source_inventory_movement_id = source_movement_id,
          target_inventory_movement_id = target_movement_id
      where id = reclassification_id;
      remaining := remaining - moved_quantity;
      exit when remaining = 0;
    end if;
  end loop;
  if remaining <> 0 then
    raise exception 'No hay existencias disponibles suficientes para reportar los defectuosos.';
  end if;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'defective_product.reported', 'defective_product', defective_id,
          jsonb_build_object('quantity', p_quantity));
  return defective_id;
end;
$$;

alter table public.cash_movements add column sale_cancellation_id uuid unique
  references public.sale_cancellations(id) on delete restrict;

create or replace function public.cancel_sale(
  p_business_id uuid,
  p_sale_id uuid,
  p_cash_session_id uuid,
  p_reason text,
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare cancellation_id uuid;
declare sale_row public.sales%rowtype;
declare session_status public.cash_session_status;
declare line_row public.sale_lines%rowtype;
declare payment_row public.sale_payments%rowtype;
begin
  if auth.uid() is null or not public.is_business_owner(p_business_id) then
    raise exception 'Solo el dueño puede cancelar ventas confirmadas.';
  end if;
  select id into cancellation_id from public.sale_cancellations
  where business_id = p_business_id and request_id = p_request_id;
  if cancellation_id is not null then return cancellation_id; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 then
    raise exception 'Indica un motivo de cancelación válido.';
  end if;
  select * into sale_row from public.sales
  where id = p_sale_id and business_id = p_business_id for update;
  if not found or sale_row.status <> 'confirmed' then
    raise exception 'La venta no puede cancelarse.';
  end if;
  select status into session_status from public.cash_register_sessions
  where id = p_cash_session_id and business_id = p_business_id for update;
  if session_status is distinct from 'open' then
    raise exception 'La cancelación requiere una caja abierta para registrar el movimiento compensatorio.';
  end if;
  insert into public.sale_cancellations (
    business_id, sale_id, cash_session_id, reason, request_id, requested_by, authorized_by
  ) values (
    p_business_id, p_sale_id, p_cash_session_id, btrim(p_reason), p_request_id,
    sale_row.sold_by, auth.uid()
  ) returning id into cancellation_id;
  for line_row in select * from public.sale_lines where sale_id = p_sale_id order by id loop
    perform public.reverse_fifo_source_allocations(
      p_business_id, line_row.variant_id, line_row.quantity,
      'sale_line', line_row.id, 'sale_cancellation',
      'sale_cancellation_line', line_row.id, auth.uid()
    );
  end loop;
  select * into payment_row from public.sale_payments where sale_id = p_sale_id;
  if payment_row.payment_method = 'cash' then
    insert into public.cash_movements (
      business_id, cash_session_id, sale_id, sale_cancellation_id, movement_type, amount, created_by
    ) values (
      p_business_id, p_cash_session_id, null, cancellation_id, 'withdrawal', -payment_row.amount, auth.uid()
    );
  end if;
  update public.sales set status = 'cancelled' where id = p_sale_id;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'sale.cancelled', 'sale', p_sale_id,
          jsonb_build_object('reason', btrim(p_reason), 'cancellation_id', cancellation_id));
  return cancellation_id;
end;
$$;

revoke all on function public.get_inventory_lot_available_quantity(uuid) from public;
revoke all on function public.allocate_fifo_inventory_lots(uuid, uuid, uuid, integer, text, uuid) from public;
revoke all on function public.create_fifo_consumption_movement(uuid, uuid, public.inventory_movement_type, integer, text, uuid, uuid, timestamptz) from public;
revoke all on function public.reverse_fifo_source_allocations(uuid, uuid, integer, text, uuid, public.inventory_movement_type, text, uuid, uuid) from public;

revoke all on function public.confirm_sale(uuid, uuid, public.sale_payment_method, jsonb, uuid) from public;
grant execute on function public.confirm_sale(uuid, uuid, public.sale_payment_method, jsonb, uuid) to authenticated;
revoke all on function public.confirm_sale_with_price_authorization(uuid, uuid, public.sale_payment_method, jsonb, uuid, uuid) from public;
grant execute on function public.confirm_sale_with_price_authorization(uuid, uuid, public.sale_payment_method, jsonb, uuid, uuid) to authenticated;
revoke all on function public.record_authorized_exit(uuid, uuid, integer, text, uuid) from public;
grant execute on function public.record_authorized_exit(uuid, uuid, integer, text, uuid) to authenticated;
revoke all on function public.confirm_inventory_adjustment(uuid, uuid, uuid) from public;
grant execute on function public.confirm_inventory_adjustment(uuid, uuid, uuid) to authenticated;
revoke all on function public.report_defective_product(uuid, uuid, uuid, integer, text, uuid) from public;
grant execute on function public.report_defective_product(uuid, uuid, uuid, integer, text, uuid) to authenticated;
revoke all on function public.cancel_sale(uuid, uuid, uuid, text, uuid) from public;
grant execute on function public.cancel_sale(uuid, uuid, uuid, text, uuid) to authenticated;
