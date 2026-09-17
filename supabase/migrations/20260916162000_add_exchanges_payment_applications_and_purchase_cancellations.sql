-- Fase 6: cambios sin reembolso, aplicaciones explícitas de abonos y
-- cancelaciones de compra compensatorias. Ninguna de estas operaciones borra
-- documentos, lotes, movimientos ni abonos históricos.

alter table public.purchases add constraint purchases_id_business_unique unique (id, business_id);
alter table public.supplier_payments add constraint supplier_payments_id_business_unique unique (id, business_id);
alter table public.sales add constraint sales_id_business_unique unique (id, business_id);

create table public.supplier_payment_applications (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  supplier_payment_id uuid not null,
  purchase_id uuid not null,
  amount numeric(14, 2) not null check (amount > 0),
  request_id uuid not null,
  applied_by uuid not null references auth.users(id) on delete restrict,
  applied_at timestamptz not null default now(),
  constraint supplier_payment_applications_payment_business
    foreign key (supplier_payment_id, business_id) references public.supplier_payments(id, business_id) on delete restrict,
  constraint supplier_payment_applications_purchase_business
    foreign key (purchase_id, business_id) references public.purchases(id, business_id) on delete restrict,
  constraint supplier_payment_applications_request_unique unique (business_id, request_id)
);

create index supplier_payment_applications_payment_idx
  on public.supplier_payment_applications (supplier_payment_id);
create index supplier_payment_applications_purchase_idx
  on public.supplier_payment_applications (purchase_id);

alter table public.supplier_payment_applications enable row level security;
create policy "owners read payment applications" on public.supplier_payment_applications
  for select to authenticated using (public.has_business_permission(business_id, 'payables.read'));

create or replace function public.apply_supplier_payment_to_purchase(
  p_business_id uuid,
  p_supplier_payment_id uuid,
  p_purchase_id uuid,
  p_amount numeric,
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare application_id uuid;
declare payment_row public.supplier_payments%rowtype;
declare purchase_row public.purchases%rowtype;
declare payment_remaining numeric(14, 2);
declare purchase_remaining numeric(14, 2);
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'payables.manage') then
    raise exception 'No tienes permiso para aplicar abonos.';
  end if;
  select id into application_id from public.supplier_payment_applications
  where business_id = p_business_id and request_id = p_request_id;
  if application_id is not null then return application_id; end if;
  if p_amount is null or p_amount <= 0 or p_amount <> round(p_amount, 2) then
    raise exception 'El importe aplicado no es válido.';
  end if;
  select * into payment_row from public.supplier_payments
  where id = p_supplier_payment_id and business_id = p_business_id for update;
  if not found or payment_row.status <> 'confirmed' then
    raise exception 'El abono debe estar confirmado antes de aplicarlo.';
  end if;
  select * into purchase_row from public.purchases
  where id = p_purchase_id and business_id = p_business_id for update;
  if not found or purchase_row.status <> 'confirmed' then
    raise exception 'La compra no está disponible para aplicar el abono.';
  end if;
  if payment_row.supplier_id <> purchase_row.supplier_id then
    raise exception 'El abono y la compra deben pertenecer al mismo distribuidor.';
  end if;
  perform 1 from public.supplier_payment_applications
  where supplier_payment_id = payment_row.id for update;
  perform 1 from public.supplier_payment_applications
  where purchase_id = purchase_row.id for update;
  select payment_row.amount - coalesce(sum(amount), 0) into payment_remaining
  from public.supplier_payment_applications where supplier_payment_id = payment_row.id;
  select coalesce(sum(entry.amount), 0) - coalesce((
    select sum(application.amount)
    from public.supplier_payment_applications application
    where application.purchase_id = purchase_row.id
  ), 0) into purchase_remaining
  from public.supplier_account_entries entry where entry.purchase_id = purchase_row.id;
  if payment_remaining < p_amount then
    raise exception 'El abono no tiene saldo suficiente para esta aplicación.';
  end if;
  if purchase_remaining < p_amount then
    raise exception 'La compra no tiene saldo suficiente para esta aplicación.';
  end if;
  insert into public.supplier_payment_applications (
    business_id, supplier_payment_id, purchase_id, amount, request_id, applied_by
  ) values (
    p_business_id, payment_row.id, purchase_row.id, p_amount, p_request_id, auth.uid()
  ) returning id into application_id;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'supplier_payment.applied', 'supplier_payment_application', application_id,
          jsonb_build_object('supplier_payment_id', payment_row.id, 'purchase_id', purchase_row.id, 'amount', p_amount));
  return application_id;
end;
$$;

alter table public.cash_movements drop constraint cash_movements_sale_reference;
alter table public.cash_movements add constraint cash_movements_sale_reference check (
  (movement_type = 'sale_cash' and sale_id is not null and sale_cancellation_id is null)
  or (movement_type = 'exchange_cash' and sale_id is null and sale_cancellation_id is null)
  or (movement_type = 'withdrawal' and sale_id is null)
);

create table public.product_exchanges (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  original_sale_id uuid,
  cash_session_id uuid,
  received_variant_id uuid not null,
  received_quantity integer not null check (received_quantity > 0),
  delivered_variant_id uuid not null,
  delivered_quantity integer not null check (delivered_quantity > 0),
  recognized_unit_value numeric(14, 2) not null check (recognized_unit_value >= 0),
  recognized_amount numeric(14, 2) not null check (recognized_amount >= 0),
  delivered_unit_value numeric(14, 2) not null check (delivered_unit_value >= 0),
  delivered_amount numeric(14, 2) not null check (delivered_amount >= 0),
  difference_amount numeric(14, 2) not null check (difference_amount >= 0),
  request_id uuid not null,
  reason text not null check (char_length(btrim(reason)) between 3 and 300),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  constraint product_exchanges_original_sale_business
    foreign key (original_sale_id, business_id) references public.sales(id, business_id) on delete restrict,
  constraint product_exchanges_cash_session_business
    foreign key (cash_session_id, business_id) references public.cash_register_sessions(id, business_id) on delete restrict,
  constraint product_exchanges_received_variant_business
    foreign key (received_variant_id, business_id) references public.product_variants(id, business_id) on delete restrict,
  constraint product_exchanges_delivered_variant_business
    foreign key (delivered_variant_id, business_id) references public.product_variants(id, business_id) on delete restrict,
  constraint product_exchanges_request_unique unique (business_id, request_id),
  constraint product_exchanges_id_business_unique unique (id, business_id),
  constraint product_exchanges_totals_match check (
    recognized_amount = received_quantity * recognized_unit_value
    and delivered_amount = delivered_quantity * delivered_unit_value
    and difference_amount = delivered_amount - recognized_amount
  )
);

create table public.product_exchange_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  product_exchange_id uuid not null unique references public.product_exchanges(id) on delete restrict,
  payment_method public.sale_payment_method not null,
  amount numeric(14, 2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  constraint product_exchange_payments_exchange_business
    foreign key (product_exchange_id, business_id) references public.product_exchanges(id, business_id) on delete restrict
);

alter table public.product_exchanges enable row level security;
alter table public.product_exchange_payments enable row level security;
create policy "owners or recorders read exchanges" on public.product_exchanges
  for select to authenticated using (public.is_business_owner(business_id) or recorded_by = auth.uid());
create policy "owners or recorders read exchange payments" on public.product_exchange_payments
  for select to authenticated using (
    exists (
      select 1 from public.product_exchanges exchange
      where exchange.id = product_exchange_id
        and (public.is_business_owner(exchange.business_id) or exchange.recorded_by = auth.uid())
    )
  );

create or replace function public.record_product_exchange(
  p_business_id uuid,
  p_cash_session_id uuid,
  p_original_sale_id uuid,
  p_received_variant_id uuid,
  p_received_quantity integer,
  p_delivered_variant_id uuid,
  p_delivered_quantity integer,
  p_recognized_unit_value numeric,
  p_payment_method public.sale_payment_method,
  p_reason text,
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare exchange_id uuid;
declare original_sale public.sales%rowtype;
declare original_line public.sale_lines%rowtype;
declare received_price public.variant_current_prices%rowtype;
declare delivered_price public.variant_current_prices%rowtype;
declare recognized_value numeric(14, 2);
declare recognized_amount numeric(14, 2);
declare delivered_amount numeric(14, 2);
declare difference_amount numeric(14, 2);
declare special_lot_id uuid;
declare session_status public.cash_session_status;
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'sales.create') then
    raise exception 'No tienes permiso para registrar cambios.';
  end if;
  select id into exchange_id from public.product_exchanges
  where business_id = p_business_id and request_id = p_request_id;
  if exchange_id is not null then return exchange_id; end if;
  if p_received_quantity is null or p_received_quantity <= 0
    or p_delivered_quantity is null or p_delivered_quantity <= 0
    or p_reason is null or char_length(btrim(p_reason)) < 3 then
    raise exception 'El cambio requiere cantidades positivas y un motivo válido.';
  end if;
  if not exists (select 1 from public.product_variants where id = p_received_variant_id and business_id = p_business_id and is_active)
    or not exists (select 1 from public.product_variants where id = p_delivered_variant_id and business_id = p_business_id and is_active) then
    raise exception 'Las variantes del cambio deben pertenecer al negocio y estar activas.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_business_id::text || least(p_received_variant_id, p_delivered_variant_id)::text, 0));
  if p_received_variant_id <> p_delivered_variant_id then
    perform pg_advisory_xact_lock(hashtextextended(p_business_id::text || greatest(p_received_variant_id, p_delivered_variant_id)::text, 0));
  end if;

  if p_original_sale_id is not null then
    select * into original_sale from public.sales
    where id = p_original_sale_id and business_id = p_business_id for update;
    if not found or original_sale.status <> 'confirmed' then
      raise exception 'La venta original no está disponible para el cambio.';
    end if;
    select * into original_line from public.sale_lines
    where sale_id = original_sale.id and variant_id = p_received_variant_id;
  end if;
  select * into received_price from public.variant_current_prices
  where business_id = p_business_id and variant_id = p_received_variant_id;
  select * into delivered_price from public.variant_current_prices
  where business_id = p_business_id and variant_id = p_delivered_variant_id;
  if not found then raise exception 'La variante entregada no tiene precio vigente.'; end if;

  if original_line.id is not null then
    recognized_value := original_line.unit_price;
  else
    if not public.is_business_owner(p_business_id) then
      raise exception 'Un cambio sin venta original o con variante distinta requiere autorización del dueño.';
    end if;
    recognized_value := coalesce(p_recognized_unit_value, received_price.minimum_price);
    if recognized_value < 0 or recognized_value <> round(recognized_value, 2) then
      raise exception 'El valor reconocido no es válido.';
    end if;
  end if;
  recognized_amount := p_received_quantity * recognized_value;
  delivered_amount := p_delivered_quantity * delivered_price.suggested_price;
  if delivered_amount < recognized_amount then
    raise exception 'El producto entregado debe tener un valor igual o mayor al valor reconocido.';
  end if;
  difference_amount := delivered_amount - recognized_amount;
  if difference_amount > 0 then
    if p_payment_method is null then
      raise exception 'Selecciona una forma de pago para cobrar la diferencia.';
    end if;
    select status into session_status from public.cash_register_sessions
    where id = p_cash_session_id and business_id = p_business_id for update;
    if session_status is distinct from 'open' then
      raise exception 'Se requiere una caja abierta para cobrar la diferencia del cambio.';
    end if;
  end if;

  insert into public.product_exchanges (
    business_id, original_sale_id, cash_session_id, received_variant_id, received_quantity,
    delivered_variant_id, delivered_quantity, recognized_unit_value, recognized_amount,
    delivered_unit_value, delivered_amount, difference_amount, request_id, reason, recorded_by
  ) values (
    p_business_id, p_original_sale_id,
    case when difference_amount > 0 then p_cash_session_id else null end,
    p_received_variant_id, p_received_quantity, p_delivered_variant_id, p_delivered_quantity,
    recognized_value, recognized_amount, delivered_price.suggested_price, delivered_amount,
    difference_amount, p_request_id, btrim(p_reason), auth.uid()
  ) returning id into exchange_id;

  if original_line.id is not null then
    perform public.reverse_fifo_source_allocations(
      p_business_id, p_received_variant_id, p_received_quantity,
      'sale_line', original_line.id, 'exchange',
      'exchange_received_reversal', exchange_id, auth.uid()
    );
  else
    insert into public.inventory_lots (
      business_id, variant_id, purchase_line_id, received_quantity, unit_cost,
      received_at, source_type, source_id
    ) values (
      p_business_id, p_received_variant_id, null, p_received_quantity, null,
      now(), 'exchange_received', exchange_id
    ) returning id into special_lot_id;
    insert into public.inventory_movements (
      business_id, variant_id, lot_id, movement_type, inventory_state, quantity_delta,
      source_type, source_id, occurred_at, created_by
    ) values (
      p_business_id, p_received_variant_id, special_lot_id, 'exchange', 'available', p_received_quantity,
      'exchange_received', exchange_id, now(), auth.uid()
    );
  end if;
  perform public.create_fifo_consumption_movement(
    p_business_id, p_delivered_variant_id, 'exchange', p_delivered_quantity,
    'exchange_delivered', exchange_id, auth.uid(), now()
  );
  if difference_amount > 0 then
    insert into public.product_exchange_payments (business_id, product_exchange_id, payment_method, amount)
    values (p_business_id, exchange_id, p_payment_method, difference_amount);
    if p_payment_method = 'cash' then
      insert into public.cash_movements (
        business_id, cash_session_id, movement_type, amount, created_by
      ) values (
        p_business_id, p_cash_session_id, 'exchange_cash', difference_amount, auth.uid()
      );
    end if;
  end if;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'product_exchange.recorded', 'product_exchange', exchange_id,
          jsonb_build_object('recognized_amount', recognized_amount, 'difference_amount', difference_amount));
  return exchange_id;
end;
$$;

create table public.purchase_cancellations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  purchase_id uuid not null unique references public.purchases(id) on delete restrict,
  reason text not null check (char_length(btrim(reason)) between 3 and 300),
  request_id uuid not null,
  cancelled_by uuid not null references auth.users(id) on delete restrict,
  cancelled_at timestamptz not null default now(),
  constraint purchase_cancellations_purchase_business
    foreign key (purchase_id, business_id) references public.purchases(id, business_id) on delete restrict,
  constraint purchase_cancellations_request_unique unique (business_id, request_id)
);

alter table public.purchase_cancellations enable row level security;
create policy "owners read purchase cancellations" on public.purchase_cancellations
  for select to authenticated using (public.has_business_permission(business_id, 'purchases.confirm'));

alter table public.purchases drop constraint purchases_confirmed_fields;
alter table public.purchases add constraint purchases_confirmed_fields check (
  (status = 'pending_confirmation' and confirmed_by is null and confirmed_at is null)
  or (status in ('confirmed', 'cancelled') and confirmed_by is not null and confirmed_at is not null)
);

create or replace function public.cancel_purchase(
  p_business_id uuid,
  p_purchase_id uuid,
  p_reason text,
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare cancellation_id uuid;
declare purchase_row public.purchases%rowtype;
declare lot_row public.inventory_lots%rowtype;
declare remaining_account_balance numeric(14, 2);
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'purchases.confirm') then
    raise exception 'No tienes permiso para cancelar compras.';
  end if;
  select id into cancellation_id from public.purchase_cancellations
  where business_id = p_business_id and request_id = p_request_id;
  if cancellation_id is not null then return cancellation_id; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 then
    raise exception 'Indica un motivo de cancelación válido.';
  end if;
  select * into purchase_row from public.purchases
  where id = p_purchase_id and business_id = p_business_id for update;
  if not found or purchase_row.status <> 'confirmed' then
    raise exception 'Solo se pueden cancelar compras confirmadas.';
  end if;
  if exists (
    select 1 from public.supplier_payment_applications
    where purchase_id = purchase_row.id
  ) then
    raise exception 'La compra no puede cancelarse porque tiene abonos aplicados.';
  end if;
  if exists (
    select 1
    from public.inventory_lots lot
    where lot.purchase_line_id in (select id from public.purchase_lines where purchase_id = purchase_row.id)
      and (
        exists (select 1 from public.inventory_lot_allocations allocation where allocation.lot_id = lot.id)
        or exists (select 1 from public.inventory_lot_reclassifications reclassification where reclassification.lot_id = lot.id)
        or exists (
          select 1 from public.inventory_movements movement
          where movement.lot_id = lot.id
            and not (movement.movement_type = 'purchase' and movement.source_type = 'purchase_line' and movement.source_id = lot.purchase_line_id)
        )
      )
  ) then
    raise exception 'La compra no puede cancelarse porque sus lotes tienen consumos, reversiones o reclasificaciones.';
  end if;
  insert into public.purchase_cancellations (business_id, purchase_id, reason, request_id, cancelled_by)
  values (p_business_id, purchase_row.id, btrim(p_reason), p_request_id, auth.uid())
  returning id into cancellation_id;
  for lot_row in
    select lot.* from public.inventory_lots lot
    where lot.purchase_line_id in (select id from public.purchase_lines where purchase_id = purchase_row.id)
    order by lot.id
    for update
  loop
    insert into public.inventory_movements (
      business_id, variant_id, lot_id, movement_type, inventory_state, quantity_delta,
      source_type, source_id, occurred_at, created_by
    ) values (
      p_business_id, lot_row.variant_id, lot_row.id, 'purchase_cancellation', 'available',
      -lot_row.received_quantity, 'purchase_cancellation_lot', lot_row.id, now(), auth.uid()
    );
  end loop;
  select coalesce(sum(amount), 0) into remaining_account_balance
  from public.supplier_account_entries where purchase_id = purchase_row.id;
  if remaining_account_balance <> 0 then
    insert into public.supplier_account_entries (
      business_id, supplier_id, purchase_id, entry_type, amount, created_by
    ) values (
      p_business_id, purchase_row.supplier_id, purchase_row.id, 'purchase_cancellation',
      -remaining_account_balance, auth.uid()
    );
  end if;
  update public.purchases set status = 'cancelled' where id = purchase_row.id;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'purchase.cancelled', 'purchase', purchase_row.id,
          jsonb_build_object('reason', btrim(p_reason), 'cancellation_id', cancellation_id));
  return cancellation_id;
end;
$$;

revoke all on function public.apply_supplier_payment_to_purchase(uuid, uuid, uuid, numeric, uuid) from public;
grant execute on function public.apply_supplier_payment_to_purchase(uuid, uuid, uuid, numeric, uuid) to authenticated;
revoke all on function public.record_product_exchange(uuid, uuid, uuid, uuid, integer, uuid, integer, numeric, public.sale_payment_method, text, uuid) from public;
grant execute on function public.record_product_exchange(uuid, uuid, uuid, uuid, integer, uuid, integer, numeric, public.sale_payment_method, text, uuid) to authenticated;
revoke all on function public.cancel_purchase(uuid, uuid, text, uuid) from public;
grant execute on function public.cancel_purchase(uuid, uuid, text, uuid) to authenticated;
