create type public.purchase_payment_type as enum ('cash', 'credit', 'partial');
create type public.purchase_status as enum ('pending_confirmation', 'confirmed');
create type public.inventory_state as enum ('available', 'defective_pending', 'with_supplier');
create type public.inventory_movement_type as enum ('purchase');
create type public.supplier_account_entry_type as enum ('purchase_charge', 'initial_payment');
create type public.price_review_status as enum ('pending', 'resolved');

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  name text not null,
  contact_name text,
  phone text,
  address text,
  supplied_categories text[] not null default '{}',
  credit_terms text,
  notes text,
  is_active boolean not null default true,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint suppliers_name_not_blank check (btrim(name) <> ''),
  constraint suppliers_name_length check (char_length(btrim(name)) <= 160),
  constraint suppliers_id_business_id_unique unique (id, business_id)
);

create table public.purchases (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  number_sequence bigint generated always as identity unique,
  purchase_number text generated always as ('COM-' || lpad(number_sequence::text, 6, '0')) stored,
  supplier_id uuid not null,
  payment_type public.purchase_payment_type not null,
  status public.purchase_status not null default 'pending_confirmation',
  invoice_number text,
  purchased_at timestamptz not null default now(),
  total_amount numeric(14, 2) not null,
  initial_payment_amount numeric(14, 2) not null default 0,
  created_by uuid not null references auth.users (id) on delete restrict,
  confirmed_by uuid references auth.users (id) on delete restrict,
  confirmed_at timestamptz,
  request_id uuid not null,
  confirmation_request_id uuid,
  created_at timestamptz not null default now(),
  constraint purchases_total_non_negative check (total_amount >= 0),
  constraint purchases_initial_payment_non_negative check (initial_payment_amount >= 0),
  constraint purchases_supplier_matches_business foreign key (supplier_id, business_id)
    references public.suppliers (id, business_id) on delete restrict,
  constraint purchases_business_request_unique unique (business_id, request_id),
  constraint purchases_business_confirmation_request_unique unique (business_id, confirmation_request_id),
  constraint purchases_confirmed_fields check (
    (status = 'pending_confirmation' and confirmed_by is null and confirmed_at is null)
    or (status = 'confirmed' and confirmed_by is not null and confirmed_at is not null)
  )
);

create table public.purchase_lines (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  purchase_id uuid not null references public.purchases (id) on delete restrict,
  variant_id uuid not null,
  product_name_snapshot text not null,
  variant_code_snapshot text not null,
  attributes_snapshot jsonb not null,
  quantity integer not null,
  unit_cost numeric(14, 2) not null,
  line_total numeric(14, 2) generated always as (quantity * unit_cost) stored,
  created_at timestamptz not null default now(),
  constraint purchase_lines_quantity_positive check (quantity > 0),
  constraint purchase_lines_unit_cost_non_negative check (unit_cost >= 0),
  constraint purchase_lines_attributes_is_object check (jsonb_typeof(attributes_snapshot) = 'object'),
  constraint purchase_lines_variant_matches_business foreign key (variant_id, business_id)
    references public.product_variants (id, business_id) on delete restrict
);

create table public.inventory_lots (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  variant_id uuid not null,
  purchase_line_id uuid not null unique references public.purchase_lines (id) on delete restrict,
  received_quantity integer not null,
  unit_cost numeric(14, 2) not null,
  received_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint inventory_lots_quantity_positive check (received_quantity > 0),
  constraint inventory_lots_unit_cost_non_negative check (unit_cost >= 0),
  constraint inventory_lots_variant_matches_business foreign key (variant_id, business_id)
    references public.product_variants (id, business_id) on delete restrict
);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  variant_id uuid not null,
  lot_id uuid references public.inventory_lots (id) on delete restrict,
  movement_type public.inventory_movement_type not null,
  inventory_state public.inventory_state not null,
  quantity_delta integer not null,
  source_type text not null,
  source_id uuid not null,
  occurred_at timestamptz not null,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint inventory_movements_non_zero check (quantity_delta <> 0),
  constraint inventory_movements_variant_matches_business foreign key (variant_id, business_id)
    references public.product_variants (id, business_id) on delete restrict,
  constraint inventory_movements_purchase_source_unique unique (source_type, source_id, variant_id)
);

create table public.supplier_account_entries (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  supplier_id uuid not null,
  purchase_id uuid not null references public.purchases (id) on delete restrict,
  entry_type public.supplier_account_entry_type not null,
  amount numeric(14, 2) not null,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint supplier_account_entries_amount_non_zero check (amount <> 0),
  constraint supplier_account_entries_supplier_matches_business foreign key (supplier_id, business_id)
    references public.suppliers (id, business_id) on delete restrict,
  constraint supplier_account_entries_purchase_type_unique unique (purchase_id, entry_type)
);

create table public.purchase_price_reviews (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  purchase_line_id uuid not null unique references public.purchase_lines (id) on delete restrict,
  variant_id uuid not null,
  previous_unit_cost numeric(14, 2) not null,
  current_unit_cost numeric(14, 2) not null,
  status public.price_review_status not null default 'pending',
  created_at timestamptz not null default now(),
  constraint purchase_price_reviews_cost_increased check (current_unit_cost > previous_unit_cost),
  constraint purchase_price_reviews_variant_matches_business foreign key (variant_id, business_id)
    references public.product_variants (id, business_id) on delete restrict
);

create index suppliers_business_active_idx on public.suppliers (business_id, is_active, name);
create index purchases_business_status_idx on public.purchases (business_id, status, purchased_at desc);
create index purchase_lines_purchase_idx on public.purchase_lines (purchase_id);
create index inventory_movements_variant_state_idx
  on public.inventory_movements (business_id, variant_id, inventory_state, occurred_at desc);

create trigger set_suppliers_updated_at before update on public.suppliers
for each row execute procedure public.set_updated_at();

create function public.create_supplier(
  p_business_id uuid,
  p_name text,
  p_contact_name text default null,
  p_phone text default null,
  p_address text default null,
  p_credit_terms text default null,
  p_notes text default null
)
returns uuid
language plpgsql security definer set search_path = public as $$
declare supplier_id uuid;
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'purchases.create') then
    raise exception 'No tienes permiso para registrar distribuidores.';
  end if;
  if p_name is null or char_length(btrim(p_name)) < 2 then
    raise exception 'El nombre del distribuidor debe tener al menos dos caracteres.';
  end if;
  insert into public.suppliers (business_id, name, contact_name, phone, address, credit_terms, notes, created_by)
  values (p_business_id, btrim(p_name), nullif(btrim(p_contact_name), ''), nullif(btrim(p_phone), ''), nullif(btrim(p_address), ''), nullif(btrim(p_credit_terms), ''), nullif(btrim(p_notes), ''), auth.uid())
  returning id into supplier_id;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'supplier.created', 'supplier', supplier_id, jsonb_build_object('name', btrim(p_name)));
  return supplier_id;
end;
$$;

create function public.record_purchase(
  p_business_id uuid,
  p_supplier_id uuid,
  p_payment_type public.purchase_payment_type,
  p_invoice_number text,
  p_purchased_at timestamptz,
  p_initial_payment_amount numeric,
  p_lines jsonb,
  p_request_id uuid
)
returns uuid
language plpgsql security definer set search_path = public as $$
declare purchase_id uuid; calculated_total numeric(14,2); supplier_is_active boolean;
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'purchases.create') then
    raise exception 'No tienes permiso para registrar compras.';
  end if;
  select id into purchase_id from public.purchases where business_id = p_business_id and request_id = p_request_id;
  if purchase_id is not null then return purchase_id; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'La compra debe contener al menos una línea.';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_lines) as line(variant_id uuid, quantity integer, unit_cost numeric)
    where variant_id is null or quantity is null or quantity <= 0 or unit_cost is null or unit_cost < 0
  ) then raise exception 'Cada línea requiere una variante, cantidad entera positiva y costo válido.'; end if;
  select is_active into supplier_is_active from public.suppliers where id = p_supplier_id and business_id = p_business_id;
  if supplier_is_active is distinct from true then raise exception 'El distribuidor no está activo en este negocio.'; end if;
  if (select count(*) from jsonb_to_recordset(p_lines) as line(variant_id uuid, quantity integer, unit_cost numeric)) <>
     (select count(*) from jsonb_to_recordset(p_lines) as line(variant_id uuid, quantity integer, unit_cost numeric)
       join public.product_variants variant on variant.id = line.variant_id and variant.business_id = p_business_id and variant.is_active) then
    raise exception 'Una variante no está disponible en este negocio.';
  end if;
  select sum(line.quantity * line.unit_cost) into calculated_total
  from jsonb_to_recordset(p_lines) as line(variant_id uuid, quantity integer, unit_cost numeric);
  if p_initial_payment_amount is null or p_initial_payment_amount < 0
    or (p_payment_type = 'cash' and p_initial_payment_amount <> calculated_total)
    or (p_payment_type = 'credit' and p_initial_payment_amount <> 0)
    or (p_payment_type = 'partial' and (p_initial_payment_amount <= 0 or p_initial_payment_amount >= calculated_total)) then
    raise exception 'El pago inicial no corresponde al tipo de compra.';
  end if;
  insert into public.purchases (business_id, supplier_id, payment_type, invoice_number, purchased_at, total_amount, initial_payment_amount, created_by, request_id)
  values (p_business_id, p_supplier_id, p_payment_type, nullif(btrim(p_invoice_number), ''), coalesce(p_purchased_at, now()), calculated_total, p_initial_payment_amount, auth.uid(), p_request_id)
  returning id into purchase_id;
  insert into public.purchase_lines (business_id, purchase_id, variant_id, product_name_snapshot, variant_code_snapshot, attributes_snapshot, quantity, unit_cost)
  select p_business_id, purchase_id, line.variant_id, product.name, variant.internal_code, variant.attributes, line.quantity, line.unit_cost
  from jsonb_to_recordset(p_lines) as line(variant_id uuid, quantity integer, unit_cost numeric)
  join public.product_variants variant on variant.id = line.variant_id
  join public.products product on product.id = variant.product_id;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'purchase.recorded', 'purchase', purchase_id, jsonb_build_object('status', 'pending_confirmation', 'total', calculated_total));
  return purchase_id;
end;
$$;

create function public.confirm_purchase(p_business_id uuid, p_purchase_id uuid, p_request_id uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare purchase_row public.purchases%rowtype; line_row public.purchase_lines%rowtype; lot_id uuid; previous_cost numeric(14,2);
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'purchases.confirm') then
    raise exception 'No tienes permiso para confirmar compras.';
  end if;
  select * into purchase_row from public.purchases where id = p_purchase_id and business_id = p_business_id for update;
  if not found then raise exception 'La compra no está disponible en este negocio.'; end if;
  if purchase_row.status = 'confirmed' then return purchase_row.id; end if;
  if exists (select 1 from public.purchases where business_id = p_business_id and confirmation_request_id = p_request_id) then return purchase_row.id; end if;
  update public.purchases set status = 'confirmed', confirmed_by = auth.uid(), confirmed_at = now(), confirmation_request_id = p_request_id where id = purchase_row.id;
  for line_row in select * from public.purchase_lines where purchase_id = purchase_row.id loop
    select lot.unit_cost into previous_cost from public.inventory_lots lot
    where lot.variant_id = line_row.variant_id order by lot.received_at desc, lot.created_at desc limit 1;
    insert into public.inventory_lots (business_id, variant_id, purchase_line_id, received_quantity, unit_cost, received_at)
    values (p_business_id, line_row.variant_id, line_row.id, line_row.quantity, line_row.unit_cost, purchase_row.purchased_at)
    returning id into lot_id;
    insert into public.inventory_movements (business_id, variant_id, lot_id, movement_type, inventory_state, quantity_delta, source_type, source_id, occurred_at, created_by)
    values (p_business_id, line_row.variant_id, lot_id, 'purchase', 'available', line_row.quantity, 'purchase_line', line_row.id, purchase_row.purchased_at, auth.uid());
    if previous_cost is not null and line_row.unit_cost > previous_cost then
      insert into public.purchase_price_reviews (business_id, purchase_line_id, variant_id, previous_unit_cost, current_unit_cost)
      values (p_business_id, line_row.id, line_row.variant_id, previous_cost, line_row.unit_cost);
    end if;
  end loop;
  if purchase_row.payment_type <> 'cash' then
    insert into public.supplier_account_entries (business_id, supplier_id, purchase_id, entry_type, amount, created_by)
    values (p_business_id, purchase_row.supplier_id, purchase_row.id, 'purchase_charge', purchase_row.total_amount, auth.uid());
    if purchase_row.initial_payment_amount > 0 then
      insert into public.supplier_account_entries (business_id, supplier_id, purchase_id, entry_type, amount, created_by)
      values (p_business_id, purchase_row.supplier_id, purchase_row.id, 'initial_payment', -purchase_row.initial_payment_amount, auth.uid());
    end if;
  end if;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'purchase.confirmed', 'purchase', purchase_row.id, jsonb_build_object('total', purchase_row.total_amount));
  return purchase_row.id;
end;
$$;

create function public.get_inventory_variants(p_business_id uuid, p_query text default null)
returns table(variant_id uuid, product_name text, variant_code text, attributes jsonb, available_quantity bigint, suggested_price numeric, minimum_price numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'inventory.read') then raise exception 'No tienes permiso para consultar el inventario.'; end if;
  return query select variant.id, product.name, variant.internal_code, variant.attributes,
    coalesce(sum(movement.quantity_delta) filter (where movement.inventory_state = 'available'), 0)::bigint,
    case when public.has_business_permission(p_business_id, 'pricing.read') then price.suggested_price else null end,
    case when public.has_business_permission(p_business_id, 'pricing.read') then price.minimum_price else null end
  from public.product_variants variant join public.products product on product.id = variant.product_id
  left join public.inventory_movements movement on movement.variant_id = variant.id
  left join public.variant_current_prices price on price.variant_id = variant.id
  where variant.business_id = p_business_id and variant.is_active and product.is_active
    and (nullif(btrim(p_query), '') is null or product.name ilike '%' || btrim(p_query) || '%' or variant.internal_code ilike '%' || btrim(p_query) || '%' or variant.attributes::text ilike '%' || btrim(p_query) || '%')
  group by variant.id, product.name, variant.internal_code, variant.attributes, price.suggested_price, price.minimum_price
  order by product.name, variant.internal_code;
end;
$$;

alter table public.suppliers enable row level security; alter table public.purchases enable row level security; alter table public.purchase_lines enable row level security; alter table public.inventory_lots enable row level security; alter table public.inventory_movements enable row level security; alter table public.supplier_account_entries enable row level security; alter table public.purchase_price_reviews enable row level security;
create policy "members read suppliers" on public.suppliers for select to authenticated using (public.has_business_permission(business_id, 'suppliers.read'));
create policy "owners or creators read purchases" on public.purchases for select to authenticated using (public.has_business_permission(business_id, 'purchases.confirm') or created_by = auth.uid());
create policy "owners or creators read purchase lines" on public.purchase_lines for select to authenticated using (exists (select 1 from public.purchases purchase where purchase.id = purchase_id and (public.has_business_permission(purchase.business_id, 'purchases.confirm') or purchase.created_by = auth.uid())));
create policy "members read inventory movements" on public.inventory_movements for select to authenticated using (public.has_business_permission(business_id, 'inventory.read'));
create policy "owners read inventory lots" on public.inventory_lots for select to authenticated using (public.has_business_permission(business_id, 'purchases.confirm'));
create policy "owners read supplier account entries" on public.supplier_account_entries for select to authenticated using (public.has_business_permission(business_id, 'payables.read'));
create policy "owners read price reviews" on public.purchase_price_reviews for select to authenticated using (public.has_business_permission(business_id, 'pricing.manage'));
revoke all on function public.create_supplier(uuid, text, text, text, text, text, text) from public; grant execute on function public.create_supplier(uuid, text, text, text, text, text, text) to authenticated;
revoke all on function public.record_purchase(uuid, uuid, public.purchase_payment_type, text, timestamptz, numeric, jsonb, uuid) from public; grant execute on function public.record_purchase(uuid, uuid, public.purchase_payment_type, text, timestamptz, numeric, jsonb, uuid) to authenticated;
revoke all on function public.confirm_purchase(uuid, uuid, uuid) from public; grant execute on function public.confirm_purchase(uuid, uuid, uuid) to authenticated;
revoke all on function public.get_inventory_variants(uuid, text) from public; grant execute on function public.get_inventory_variants(uuid, text) to authenticated;
