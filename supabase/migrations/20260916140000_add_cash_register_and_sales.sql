create type public.cash_session_status as enum ('open', 'closed');
create type public.cash_movement_type as enum ('sale_cash', 'other_income', 'withdrawal');
create type public.sale_status as enum ('confirmed');
create type public.sale_payment_method as enum ('cash', 'qr', 'transfer', 'card');

alter type public.inventory_movement_type add value if not exists 'sale';

create table public.cash_register_sessions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  business_date date not null,
  status public.cash_session_status not null default 'open',
  opening_fund numeric(14, 2) not null,
  opening_notes text,
  opened_by uuid not null references auth.users (id) on delete restrict,
  opened_at timestamptz not null default now(),
  open_request_id uuid not null,
  closing_notes text,
  expected_cash numeric(14, 2),
  counted_cash numeric(14, 2),
  difference_amount numeric(14, 2),
  closed_by uuid references auth.users (id) on delete restrict,
  closed_at timestamptz,
  close_request_id uuid,
  constraint cash_register_sessions_opening_fund_non_negative check (opening_fund >= 0),
  constraint cash_register_sessions_opening_notes_length check (opening_notes is null or char_length(btrim(opening_notes)) <= 600),
  constraint cash_register_sessions_closing_notes_length check (closing_notes is null or char_length(btrim(closing_notes)) <= 600),
  constraint cash_register_sessions_id_business_id_unique unique (id, business_id),
  constraint cash_register_sessions_business_date_unique unique (business_id, business_date),
  constraint cash_register_sessions_business_open_request_unique unique (business_id, open_request_id),
  constraint cash_register_sessions_business_close_request_unique unique (business_id, close_request_id),
  constraint cash_register_sessions_closed_fields check (
    (status = 'open' and closed_by is null and closed_at is null and expected_cash is null and counted_cash is null and difference_amount is null)
    or (status = 'closed' and closed_by is not null and closed_at is not null and expected_cash is not null and counted_cash is not null and difference_amount is not null)
  )
);

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  number_sequence bigint generated always as identity unique,
  sale_number text generated always as ('VTA-' || lpad(number_sequence::text, 6, '0')) stored,
  cash_session_id uuid not null,
  status public.sale_status not null default 'confirmed',
  total_amount numeric(14, 2) not null,
  sold_by uuid not null references auth.users (id) on delete restrict,
  confirmed_at timestamptz not null default now(),
  request_id uuid not null,
  created_at timestamptz not null default now(),
  constraint sales_total_positive check (total_amount > 0),
  constraint sales_session_matches_business foreign key (cash_session_id, business_id)
    references public.cash_register_sessions (id, business_id) on delete restrict,
  constraint sales_business_request_unique unique (business_id, request_id)
);

create table public.sale_lines (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  sale_id uuid not null references public.sales (id) on delete restrict,
  variant_id uuid not null,
  product_name_snapshot text not null,
  variant_code_snapshot text not null,
  attributes_snapshot jsonb not null,
  quantity integer not null,
  suggested_price_snapshot numeric(14, 2) not null,
  minimum_price_snapshot numeric(14, 2) not null,
  unit_price numeric(14, 2) not null,
  line_total numeric(14, 2) generated always as (quantity * unit_price) stored,
  created_at timestamptz not null default now(),
  constraint sale_lines_quantity_positive check (quantity > 0),
  constraint sale_lines_prices_non_negative check (suggested_price_snapshot >= 0 and minimum_price_snapshot >= 0 and unit_price >= 0),
  constraint sale_lines_minimum_not_above_suggested check (minimum_price_snapshot <= suggested_price_snapshot),
  constraint sale_lines_attributes_is_object check (jsonb_typeof(attributes_snapshot) = 'object'),
  constraint sale_lines_variant_matches_business foreign key (variant_id, business_id)
    references public.product_variants (id, business_id) on delete restrict,
  constraint sale_lines_sale_variant_unique unique (sale_id, variant_id)
);

create table public.sale_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  sale_id uuid not null unique references public.sales (id) on delete restrict,
  payment_method public.sale_payment_method not null,
  amount numeric(14, 2) not null,
  created_at timestamptz not null default now(),
  constraint sale_payments_amount_positive check (amount > 0)
);

create table public.cash_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  cash_session_id uuid not null,
  sale_id uuid unique references public.sales (id) on delete restrict,
  movement_type public.cash_movement_type not null,
  amount numeric(14, 2) not null,
  occurred_at timestamptz not null default now(),
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint cash_movements_session_matches_business foreign key (cash_session_id, business_id)
    references public.cash_register_sessions (id, business_id) on delete restrict,
  constraint cash_movements_amount_non_zero check (amount <> 0),
  constraint cash_movements_sale_cash_positive check (movement_type <> 'sale_cash' or amount > 0),
  constraint cash_movements_sale_reference check (
    (movement_type = 'sale_cash' and sale_id is not null)
    or (movement_type <> 'sale_cash' and sale_id is null)
  )
);

create index cash_register_sessions_business_status_idx on public.cash_register_sessions (business_id, status, business_date desc);
create index sales_business_confirmed_at_idx on public.sales (business_id, confirmed_at desc);
create index sale_lines_sale_idx on public.sale_lines (sale_id);
create index cash_movements_session_idx on public.cash_movements (cash_session_id, occurred_at);

create function public.open_cash_register(
  p_business_id uuid,
  p_opening_fund numeric,
  p_opening_notes text,
  p_request_id uuid
)
returns uuid
language plpgsql security definer set search_path = public as $$
declare session_id uuid; business_timezone text; current_business_date date;
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'cash_register.open') then
    raise exception 'No tienes permiso para abrir caja.';
  end if;
  if p_opening_fund is null or p_opening_fund < 0 or p_opening_fund <> round(p_opening_fund, 2) then
    raise exception 'El fondo inicial debe ser un importe válido no negativo.';
  end if;

  select timezone into business_timezone from public.businesses where id = p_business_id;
  if business_timezone is null then raise exception 'El negocio no está disponible.'; end if;
  current_business_date := (now() at time zone business_timezone)::date;

  select id into session_id from public.cash_register_sessions
  where business_id = p_business_id and open_request_id = p_request_id;
  if session_id is not null then return session_id; end if;

  select id into session_id from public.cash_register_sessions
  where business_id = p_business_id and business_date = current_business_date
  for update;
  if session_id is not null then
    raise exception 'Ya existe una caja abierta o cerrada para el día comercial actual.';
  end if;

  insert into public.cash_register_sessions (business_id, business_date, opening_fund, opening_notes, opened_by, open_request_id)
  values (p_business_id, current_business_date, p_opening_fund, nullif(btrim(p_opening_notes), ''), auth.uid(), p_request_id)
  returning id into session_id;

  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'cash_register.opened', 'cash_register_session', session_id, jsonb_build_object('opening_fund', p_opening_fund, 'business_date', current_business_date));
  return session_id;
end;
$$;

create function public.confirm_sale(
  p_business_id uuid,
  p_cash_session_id uuid,
  p_payment_method public.sale_payment_method,
  p_lines jsonb,
  p_request_id uuid
)
returns uuid
language plpgsql security definer set search_path = public as $$
declare sale_id uuid; session_status public.cash_session_status; line_item record; variant_row record; available_quantity bigint; calculated_total numeric(14, 2) := 0; sale_line_id uuid;
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'sales.create') then
    raise exception 'No tienes permiso para registrar ventas.';
  end if;
  select id into sale_id from public.sales where business_id = p_business_id and request_id = p_request_id;
  if sale_id is not null then return sale_id; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'La venta debe contener al menos una línea.';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_lines) as line(variant_id uuid, quantity integer, unit_price numeric)
    where variant_id is null or quantity is null or quantity <= 0 or unit_price is null or unit_price < 0 or unit_price <> round(unit_price, 2)
  ) then raise exception 'Cada línea requiere variante, cantidad entera positiva y precio válido.'; end if;
  if (select count(*) from jsonb_to_recordset(p_lines) as line(variant_id uuid, quantity integer, unit_price numeric)) <> (select count(distinct variant_id) from jsonb_to_recordset(p_lines) as line(variant_id uuid, quantity integer, unit_price numeric)) then
    raise exception 'Una variante solo puede aparecer una vez en la venta.';
  end if;

  select status into session_status from public.cash_register_sessions
  where id = p_cash_session_id and business_id = p_business_id
  for update;
  if session_status is null or session_status <> 'open' then raise exception 'Debes tener una caja abierta para confirmar la venta.'; end if;

  for line_item in select * from jsonb_to_recordset(p_lines) as line(variant_id uuid, quantity integer, unit_price numeric) loop
    perform pg_advisory_xact_lock(hashtextextended(p_business_id::text || line_item.variant_id::text, 0));
    select product.name as product_name, variant.internal_code as variant_code, variant.attributes, price.suggested_price, price.minimum_price
    into variant_row
    from public.product_variants variant
    join public.products product on product.id = variant.product_id
    join public.variant_current_prices price on price.variant_id = variant.id
    where variant.id = line_item.variant_id and variant.business_id = p_business_id and variant.is_active and product.is_active;
    if not found then raise exception 'Una variante no está disponible para venta en este negocio.'; end if;
    if line_item.unit_price < variant_row.minimum_price then raise exception 'El precio negociado no puede ser menor al precio mínimo.'; end if;
    select coalesce(sum(quantity_delta), 0)::bigint into available_quantity
    from public.inventory_movements
    where business_id = p_business_id and variant_id = line_item.variant_id and inventory_state = 'available';
    if available_quantity < line_item.quantity then raise exception 'No hay existencias disponibles suficientes para esta venta.'; end if;
    calculated_total := calculated_total + (line_item.quantity * line_item.unit_price);
  end loop;

  insert into public.sales (business_id, cash_session_id, total_amount, sold_by, request_id)
  values (p_business_id, p_cash_session_id, calculated_total, auth.uid(), p_request_id)
  returning id into sale_id;

  for line_item in select * from jsonb_to_recordset(p_lines) as line(variant_id uuid, quantity integer, unit_price numeric) loop
    select product.name as product_name, variant.internal_code as variant_code, variant.attributes, price.suggested_price, price.minimum_price
    into variant_row
    from public.product_variants variant
    join public.products product on product.id = variant.product_id
    join public.variant_current_prices price on price.variant_id = variant.id
    where variant.id = line_item.variant_id;
    insert into public.sale_lines (business_id, sale_id, variant_id, product_name_snapshot, variant_code_snapshot, attributes_snapshot, quantity, suggested_price_snapshot, minimum_price_snapshot, unit_price)
    values (p_business_id, sale_id, line_item.variant_id, variant_row.product_name, variant_row.variant_code, variant_row.attributes, line_item.quantity, variant_row.suggested_price, variant_row.minimum_price, line_item.unit_price)
    returning id into sale_line_id;
    insert into public.inventory_movements (business_id, variant_id, movement_type, inventory_state, quantity_delta, source_type, source_id, occurred_at, created_by)
    values (p_business_id, line_item.variant_id, 'sale', 'available', -line_item.quantity, 'sale_line', sale_line_id, now(), auth.uid());
  end loop;

  insert into public.sale_payments (business_id, sale_id, payment_method, amount)
  values (p_business_id, sale_id, p_payment_method, calculated_total);
  if p_payment_method = 'cash' then
    insert into public.cash_movements (business_id, cash_session_id, sale_id, movement_type, amount, created_by)
    values (p_business_id, p_cash_session_id, sale_id, 'sale_cash', calculated_total, auth.uid());
  end if;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'sale.confirmed', 'sale', sale_id, jsonb_build_object('total', calculated_total, 'payment_method', p_payment_method));
  return sale_id;
end;
$$;

create function public.close_cash_register(
  p_business_id uuid,
  p_cash_session_id uuid,
  p_counted_cash numeric,
  p_closing_notes text,
  p_request_id uuid
)
returns uuid
language plpgsql security definer set search_path = public as $$
declare session_row public.cash_register_sessions%rowtype; expected_amount numeric(14, 2); difference numeric(14, 2);
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'cash_register.close') then
    raise exception 'No tienes permiso para cerrar caja.';
  end if;
  if p_counted_cash is null or p_counted_cash < 0 or p_counted_cash <> round(p_counted_cash, 2) then
    raise exception 'El efectivo contado debe ser un importe válido no negativo.';
  end if;
  select * into session_row from public.cash_register_sessions
  where id = p_cash_session_id and business_id = p_business_id
  for update;
  if not found then raise exception 'La caja no está disponible en este negocio.'; end if;
  if session_row.status = 'closed' then return session_row.id; end if;

  select session_row.opening_fund + coalesce(sum(amount), 0) into expected_amount
  from public.cash_movements where cash_session_id = session_row.id;
  difference := p_counted_cash - expected_amount;
  if difference <> 0 and (p_closing_notes is null or char_length(btrim(p_closing_notes)) < 3) then
    raise exception 'Debes explicar la diferencia de caja.';
  end if;
  update public.cash_register_sessions
  set status = 'closed', expected_cash = expected_amount, counted_cash = p_counted_cash, difference_amount = difference,
      closing_notes = nullif(btrim(p_closing_notes), ''), closed_by = auth.uid(), closed_at = now(), close_request_id = p_request_id
  where id = session_row.id;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'cash_register.closed', 'cash_register_session', session_row.id, jsonb_build_object('expected_cash', expected_amount, 'counted_cash', p_counted_cash, 'difference', difference));
  return session_row.id;
end;
$$;

alter table public.cash_register_sessions enable row level security;
alter table public.sales enable row level security;
alter table public.sale_lines enable row level security;
alter table public.sale_payments enable row level security;
alter table public.cash_movements enable row level security;

create policy "sales users read cash session state" on public.cash_register_sessions for select to authenticated using (public.has_business_permission(business_id, 'sales.create') or public.has_business_permission(business_id, 'cash_register.open') or public.has_business_permission(business_id, 'cash_register.close'));
create policy "owners or sellers read sales" on public.sales for select to authenticated using (public.is_business_owner(business_id) or sold_by = auth.uid());
create policy "owners or sellers read sale lines" on public.sale_lines for select to authenticated using (exists (select 1 from public.sales sale where sale.id = sale_id and (public.is_business_owner(sale.business_id) or sale.sold_by = auth.uid())));
create policy "owners or sellers read sale payments" on public.sale_payments for select to authenticated using (exists (select 1 from public.sales sale where sale.id = sale_id and (public.is_business_owner(sale.business_id) or sale.sold_by = auth.uid())));
create policy "cash closers read cash movements" on public.cash_movements for select to authenticated using (public.has_business_permission(business_id, 'cash_register.close') or public.is_business_owner(business_id));

revoke all on function public.open_cash_register(uuid, numeric, text, uuid) from public;
grant execute on function public.open_cash_register(uuid, numeric, text, uuid) to authenticated;
revoke all on function public.confirm_sale(uuid, uuid, public.sale_payment_method, jsonb, uuid) from public;
grant execute on function public.confirm_sale(uuid, uuid, public.sale_payment_method, jsonb, uuid) to authenticated;
revoke all on function public.close_cash_register(uuid, uuid, numeric, text, uuid) from public;
grant execute on function public.close_cash_register(uuid, uuid, numeric, text, uuid) to authenticated;
