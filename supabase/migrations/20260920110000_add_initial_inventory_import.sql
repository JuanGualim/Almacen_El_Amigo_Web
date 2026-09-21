-- La carga inicial representa el conteo verificado previo al piloto. No es una
-- compra: no crea saldos con distribuidores ni altera documentos históricos.
alter type public.inventory_movement_type add value if not exists 'initial_import';

create table public.initial_inventory_imports (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  request_id uuid not null,
  reason text not null,
  line_count integer not null,
  imported_by uuid not null references auth.users(id) on delete restrict,
  imported_at timestamptz not null default now(),
  constraint initial_inventory_imports_business_request_unique unique (business_id, request_id),
  constraint initial_inventory_imports_one_per_business unique (business_id),
  constraint initial_inventory_imports_reason_valid check (char_length(btrim(reason)) between 3 and 300),
  constraint initial_inventory_imports_line_count_positive check (line_count > 0)
);

create table public.initial_inventory_import_lines (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  initial_inventory_import_id uuid not null references public.initial_inventory_imports(id) on delete restrict,
  variant_id uuid not null,
  product_name_snapshot text not null,
  variant_code_snapshot text not null,
  quantity integer not null,
  unit_cost numeric(14, 2),
  created_at timestamptz not null default now(),
  constraint initial_inventory_import_lines_quantity_positive check (quantity > 0),
  constraint initial_inventory_import_lines_cost_non_negative check (unit_cost is null or unit_cost >= 0),
  constraint initial_inventory_import_lines_variant_business
    foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict,
  constraint initial_inventory_import_lines_variant_unique unique (initial_inventory_import_id, variant_id)
);

create index initial_inventory_import_lines_business_variant_idx
  on public.initial_inventory_import_lines(business_id, variant_id);

alter table public.initial_inventory_imports enable row level security;
alter table public.initial_inventory_import_lines enable row level security;

create policy "owners read initial inventory imports" on public.initial_inventory_imports
  for select to authenticated using (public.is_business_owner(business_id));

create policy "owners read initial inventory import lines" on public.initial_inventory_import_lines
  for select to authenticated using (public.is_business_owner(business_id));

create function public.import_initial_inventory(
  p_business_id uuid,
  p_lines jsonb,
  p_reason text,
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  import_id uuid;
  import_line_id uuid;
  item jsonb;
  variant_row public.product_variants%rowtype;
  product_name text;
  quantity_text text;
  parsed_quantity integer;
  unit_cost_text text;
  parsed_unit_cost numeric(14, 2);
  normalized_reason text := btrim(p_reason);
  seen_variant_ids uuid[] := '{}';
  parsed_line_count integer := 0;
begin
  if auth.uid() is null or not public.is_business_owner(p_business_id) then
    raise exception 'Solo el dueño puede confirmar la carga inicial de inventario.';
  end if;

  if normalized_reason is null or char_length(normalized_reason) not between 3 and 300 then
    raise exception 'Indica un motivo de entre 3 y 300 caracteres para la carga inicial.';
  end if;

  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'La carga inicial debe incluir al menos una variante.';
  end if;

  if jsonb_array_length(p_lines) > 1000 then
    raise exception 'La carga inicial admite como máximo 1000 líneas.';
  end if;

  select id into import_id
  from public.initial_inventory_imports
  where business_id = p_business_id and request_id = p_request_id;

  if import_id is not null then
    return import_id;
  end if;

  if exists (
    select 1 from public.initial_inventory_imports where business_id = p_business_id
  ) then
    raise exception 'Este negocio ya tiene una carga inicial confirmada. Usa un conteo o ajuste auditable para diferencias posteriores.';
  end if;

  if exists (
    select 1 from public.inventory_movements where business_id = p_business_id
  ) then
    raise exception 'La carga inicial solo se permite antes de registrar movimientos de inventario.';
  end if;

  import_id := gen_random_uuid();

  insert into public.initial_inventory_imports (
    id, business_id, request_id, reason, line_count, imported_by
  ) values (
    import_id, p_business_id, p_request_id, normalized_reason, 1, auth.uid()
  );

  for item in select value from jsonb_array_elements(p_lines)
  loop
    if jsonb_typeof(item) <> 'object' then
      raise exception 'Cada línea de la carga inicial debe ser un objeto válido.';
    end if;

    begin
      select * into variant_row
      from public.product_variants
      where id = (item ->> 'variant_id')::uuid
        and business_id = p_business_id
        and is_active
      for share;
    exception when invalid_text_representation then
      raise exception 'Una línea contiene una variante inválida.';
    end;

    if not found then
      raise exception 'Una variante de la carga no existe o no pertenece al negocio activo.';
    end if;

    if variant_row.id = any(seen_variant_ids) then
      raise exception 'La carga inicial no puede repetir una variante.';
    end if;
    seen_variant_ids := array_append(seen_variant_ids, variant_row.id);

    quantity_text := item ->> 'quantity';
    if quantity_text is null or quantity_text !~ '^[1-9][0-9]*$' then
      raise exception 'Cada cantidad debe ser un entero positivo.';
    end if;
    parsed_quantity := quantity_text::integer;

    unit_cost_text := nullif(btrim(coalesce(item ->> 'unit_cost', '')), '');
    if unit_cost_text is not null then
      if unit_cost_text !~ '^[0-9]{1,12}(\.[0-9]{1,2})?$' then
        raise exception 'El costo unitario debe ser un importe no negativo con hasta dos decimales.';
      end if;
      parsed_unit_cost := unit_cost_text::numeric(14, 2);
    else
      parsed_unit_cost := null;
    end if;

    select product.name into product_name from public.products product where product.id = variant_row.product_id;

    insert into public.initial_inventory_import_lines (
      business_id, initial_inventory_import_id, variant_id, product_name_snapshot,
      variant_code_snapshot, quantity, unit_cost
    ) values (
      p_business_id, import_id, variant_row.id, product_name,
      variant_row.internal_code, parsed_quantity, parsed_unit_cost
    ) returning id into import_line_id;

    insert into public.inventory_lots (
      business_id, variant_id, purchase_line_id, received_quantity, unit_cost,
      received_at, source_type, source_id
    ) values (
      p_business_id, variant_row.id, null, parsed_quantity, parsed_unit_cost,
      now(), 'initial_inventory_import', import_line_id
    );

    insert into public.inventory_movements (
      business_id, variant_id, lot_id, movement_type, inventory_state,
      quantity_delta, source_type, source_id, occurred_at, created_by
    ) values (
      p_business_id, variant_row.id,
      (select id from public.inventory_lots where source_type = 'initial_inventory_import' and source_id = import_line_id),
      'initial_import', 'available', parsed_quantity, 'initial_inventory_import',
      import_line_id, now(), auth.uid()
    );

    parsed_line_count := parsed_line_count + 1;
  end loop;

  update public.initial_inventory_imports
  set line_count = parsed_line_count
  where id = import_id;

  insert into public.audit_events (
    business_id, actor_user_id, event_type, entity_type, entity_id, data
  ) values (
    p_business_id, auth.uid(), 'inventory.initial_import_confirmed',
    'initial_inventory_import', import_id,
    jsonb_build_object('line_count', parsed_line_count, 'reason', normalized_reason)
  );

  return import_id;
end;
$$;

revoke all on function public.import_initial_inventory(uuid, jsonb, text, uuid) from public;
grant execute on function public.import_initial_inventory(uuid, jsonb, text, uuid) to authenticated;
