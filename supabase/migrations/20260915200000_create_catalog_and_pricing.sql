-- El catálogo no contiene existencias. Las fases posteriores crearán lotes y
-- movimientos que referenciarán estas variantes, sin modificar su identidad ni
-- su historial de precios.
create type public.price_kind as enum ('suggested', 'minimum');

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  name text not null,
  name_key text generated always as (lower(btrim(name))) stored,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint categories_name_not_blank check (btrim(name) <> ''),
  constraint categories_name_length check (char_length(btrim(name)) <= 120),
  constraint categories_id_business_id_unique unique (id, business_id),
  constraint categories_business_name_unique unique (business_id, name_key)
);

create table public.brands (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  name text not null,
  name_key text generated always as (lower(btrim(name))) stored,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint brands_name_not_blank check (btrim(name) <> ''),
  constraint brands_name_length check (char_length(btrim(name)) <= 120),
  constraint brands_id_business_id_unique unique (id, business_id),
  constraint brands_business_name_unique unique (business_id, name_key)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  code_sequence bigint generated always as identity unique,
  internal_code text generated always as ('ALM-' || lpad(code_sequence::text, 6, '0')) stored,
  category_id uuid not null,
  brand_id uuid,
  name text not null,
  details jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint products_name_not_blank check (btrim(name) <> ''),
  constraint products_name_length check (char_length(btrim(name)) <= 180),
  constraint products_details_is_object check (jsonb_typeof(details) = 'object'),
  constraint products_category_matches_business foreign key (category_id, business_id)
    references public.categories (id, business_id) on delete restrict,
  constraint products_brand_matches_business foreign key (brand_id, business_id)
    references public.brands (id, business_id) on delete restrict,
  constraint products_id_business_id_unique unique (id, business_id),
  constraint products_business_internal_code_unique unique (business_id, internal_code)
);

create table public.product_variants (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  product_id uuid not null,
  sequence_number integer not null,
  internal_code text not null,
  attributes jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_variants_sequence_positive check (sequence_number > 0),
  constraint product_variants_code_not_blank check (btrim(internal_code) <> ''),
  constraint product_variants_attributes_is_object check (jsonb_typeof(attributes) = 'object'),
  constraint product_variants_product_matches_business foreign key (product_id, business_id)
    references public.products (id, business_id) on delete restrict,
  constraint product_variants_product_sequence_unique unique (product_id, sequence_number),
  constraint product_variants_product_attributes_unique unique (product_id, attributes),
  constraint product_variants_business_internal_code_unique unique (business_id, internal_code),
  constraint product_variants_id_business_id_unique unique (id, business_id)
);

create table public.variant_current_prices (
  variant_id uuid primary key,
  business_id uuid not null,
  suggested_price numeric(14, 2) not null,
  minimum_price numeric(14, 2) not null,
  updated_by uuid not null references auth.users (id) on delete restrict,
  updated_at timestamptz not null default now(),
  constraint variant_current_prices_non_negative check (
    suggested_price >= 0 and minimum_price >= 0
  ),
  constraint variant_current_prices_minimum_not_above_suggested check (
    minimum_price <= suggested_price
  ),
  constraint variant_current_prices_variant_matches_business foreign key (variant_id, business_id)
    references public.product_variants (id, business_id) on delete restrict
);

create table public.variant_price_history (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  variant_id uuid not null,
  price_kind public.price_kind not null,
  amount numeric(14, 2) not null,
  changed_by uuid not null references auth.users (id) on delete restrict,
  changed_at timestamptz not null default now(),
  reason text,
  constraint variant_price_history_amount_non_negative check (amount >= 0),
  constraint variant_price_history_reason_length check (
    reason is null or char_length(btrim(reason)) between 3 and 300
  ),
  constraint variant_price_history_variant_matches_business foreign key (variant_id, business_id)
    references public.product_variants (id, business_id) on delete restrict
);

create index products_business_name_idx on public.products (business_id, name);
create index product_variants_business_code_idx on public.product_variants (business_id, internal_code);
create index variant_price_history_variant_changed_at_idx
  on public.variant_price_history (variant_id, changed_at desc);

create trigger set_categories_updated_at
before update on public.categories
for each row execute procedure public.set_updated_at();

create trigger set_brands_updated_at
before update on public.brands
for each row execute procedure public.set_updated_at();

create trigger set_products_updated_at
before update on public.products
for each row execute procedure public.set_updated_at();

create trigger set_product_variants_updated_at
before update on public.product_variants
for each row execute procedure public.set_updated_at();

create function public.validate_catalog_attributes(p_attributes jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  normalized_attributes jsonb := coalesce(p_attributes, '{}'::jsonb);
begin
  if jsonb_typeof(normalized_attributes) <> 'object' then
    raise exception 'Los atributos deben ser un objeto de pares nombre y valor.';
  end if;

  if exists (
    select 1
    from jsonb_each(normalized_attributes) attribute
    where btrim(attribute.key) = ''
      or char_length(attribute.key) > 60
      or jsonb_typeof(attribute.value) <> 'string'
      or btrim(attribute.value #>> '{}') = ''
      or char_length(attribute.value #>> '{}') > 120
  ) then
    raise exception 'Cada atributo debe tener un nombre y valor de texto válidos.';
  end if;

  return normalized_attributes;
end;
$$;

create function public.create_catalog_product(
  p_business_id uuid,
  p_category_name text,
  p_brand_name text,
  p_product_name text,
  p_product_details jsonb,
  p_variant_attributes jsonb,
  p_suggested_price numeric,
  p_minimum_price numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_category text := btrim(p_category_name);
  normalized_brand text := nullif(btrim(p_brand_name), '');
  normalized_product_name text := btrim(p_product_name);
  normalized_details jsonb := public.validate_catalog_attributes(p_product_details);
  normalized_variant_attributes jsonb := public.validate_catalog_attributes(p_variant_attributes);
  category_id uuid;
  brand_id uuid;
  product_row public.products%rowtype;
  variant_id uuid;
begin
  if auth.uid() is null
    or not public.has_business_permission(p_business_id, 'catalog.manage')
    or not public.has_business_permission(p_business_id, 'pricing.manage') then
    raise exception 'No tienes permiso para crear productos y definir sus precios.';
  end if;

  if normalized_category is null or char_length(normalized_category) < 2 then
    raise exception 'La categoría debe tener al menos dos caracteres.';
  end if;

  if normalized_product_name is null or char_length(normalized_product_name) < 2 then
    raise exception 'El nombre del producto debe tener al menos dos caracteres.';
  end if;

  if p_suggested_price is null or p_minimum_price is null
    or p_suggested_price < 0 or p_minimum_price < 0
    or p_minimum_price > p_suggested_price then
    raise exception 'El precio mínimo debe ser mayor o igual a cero y no superar el sugerido.';
  end if;

  insert into public.categories (business_id, name, created_by)
  values (p_business_id, normalized_category, auth.uid())
  on conflict (business_id, name_key) do update set name = excluded.name
  returning id into category_id;

  if normalized_brand is not null then
    insert into public.brands (business_id, name, created_by)
    values (p_business_id, normalized_brand, auth.uid())
    on conflict (business_id, name_key) do update set name = excluded.name
    returning id into brand_id;
  end if;

  insert into public.products (
    business_id,
    category_id,
    brand_id,
    name,
    details,
    created_by
  )
  values (
    p_business_id,
    category_id,
    brand_id,
    normalized_product_name,
    normalized_details,
    auth.uid()
  )
  returning * into product_row;

  insert into public.product_variants (
    business_id,
    product_id,
    sequence_number,
    internal_code,
    attributes,
    created_by
  )
  values (
    p_business_id,
    product_row.id,
    1,
    product_row.internal_code || '-001',
    normalized_variant_attributes,
    auth.uid()
  )
  returning id into variant_id;

  insert into public.variant_current_prices (
    variant_id,
    business_id,
    suggested_price,
    minimum_price,
    updated_by
  )
  values (
    variant_id,
    p_business_id,
    p_suggested_price,
    p_minimum_price,
    auth.uid()
  );

  insert into public.variant_price_history (
    business_id,
    variant_id,
    price_kind,
    amount,
    changed_by,
    reason
  )
  values
    (p_business_id, variant_id, 'suggested', p_suggested_price, auth.uid(), 'Precio inicial'),
    (p_business_id, variant_id, 'minimum', p_minimum_price, auth.uid(), 'Precio inicial');

  insert into public.audit_events (
    business_id,
    actor_user_id,
    event_type,
    entity_type,
    entity_id,
    data
  )
  values (
    p_business_id,
    auth.uid(),
    'catalog.product_created',
    'product',
    product_row.id,
    jsonb_build_object(
      'product_code', product_row.internal_code,
      'variant_id', variant_id,
      'variant_code', product_row.internal_code || '-001'
    )
  );

  return variant_id;
end;
$$;

create function public.create_product_variant(
  p_business_id uuid,
  p_product_id uuid,
  p_attributes jsonb,
  p_suggested_price numeric,
  p_minimum_price numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_attributes jsonb := public.validate_catalog_attributes(p_attributes);
  product_row public.products%rowtype;
  next_sequence integer;
  variant_id uuid;
begin
  if auth.uid() is null
    or not public.has_business_permission(p_business_id, 'catalog.manage')
    or not public.has_business_permission(p_business_id, 'pricing.manage') then
    raise exception 'No tienes permiso para crear variantes y definir sus precios.';
  end if;

  if p_suggested_price is null or p_minimum_price is null
    or p_suggested_price < 0 or p_minimum_price < 0
    or p_minimum_price > p_suggested_price then
    raise exception 'El precio mínimo debe ser mayor o igual a cero y no superar el sugerido.';
  end if;

  select *
  into product_row
  from public.products
  where id = p_product_id
    and business_id = p_business_id
    and is_active
  for update;

  if not found then
    raise exception 'El producto no está disponible en este negocio.';
  end if;

  select coalesce(max(sequence_number), 0) + 1
  into next_sequence
  from public.product_variants
  where product_id = product_row.id;

  insert into public.product_variants (
    business_id,
    product_id,
    sequence_number,
    internal_code,
    attributes,
    created_by
  )
  values (
    p_business_id,
    product_row.id,
    next_sequence,
    product_row.internal_code || '-' || lpad(next_sequence::text, 3, '0'),
    normalized_attributes,
    auth.uid()
  )
  returning id into variant_id;

  insert into public.variant_current_prices (
    variant_id,
    business_id,
    suggested_price,
    minimum_price,
    updated_by
  )
  values (
    variant_id,
    p_business_id,
    p_suggested_price,
    p_minimum_price,
    auth.uid()
  );

  insert into public.variant_price_history (
    business_id,
    variant_id,
    price_kind,
    amount,
    changed_by,
    reason
  )
  values
    (p_business_id, variant_id, 'suggested', p_suggested_price, auth.uid(), 'Precio inicial'),
    (p_business_id, variant_id, 'minimum', p_minimum_price, auth.uid(), 'Precio inicial');

  insert into public.audit_events (
    business_id,
    actor_user_id,
    event_type,
    entity_type,
    entity_id,
    data
  )
  values (
    p_business_id,
    auth.uid(),
    'catalog.variant_created',
    'product_variant',
    variant_id,
    jsonb_build_object('product_id', product_row.id, 'variant_code', product_row.internal_code || '-' || lpad(next_sequence::text, 3, '0'))
  );

  return variant_id;
end;
$$;

create function public.update_variant_prices(
  p_business_id uuid,
  p_variant_id uuid,
  p_suggested_price numeric,
  p_minimum_price numeric,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_price public.variant_current_prices%rowtype;
  normalized_reason text := nullif(btrim(p_reason), '');
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'pricing.manage') then
    raise exception 'No tienes permiso para modificar precios.';
  end if;

  if p_suggested_price is null or p_minimum_price is null
    or p_suggested_price < 0 or p_minimum_price < 0
    or p_minimum_price > p_suggested_price then
    raise exception 'El precio mínimo debe ser mayor o igual a cero y no superar el sugerido.';
  end if;

  select *
  into current_price
  from public.variant_current_prices
  where variant_id = p_variant_id
    and business_id = p_business_id
  for update;

  if not found then
    raise exception 'La variante no está disponible en este negocio.';
  end if;

  if current_price.suggested_price = p_suggested_price
    and current_price.minimum_price = p_minimum_price then
    return;
  end if;

  update public.variant_current_prices
  set
    suggested_price = p_suggested_price,
    minimum_price = p_minimum_price,
    updated_by = auth.uid(),
    updated_at = now()
  where variant_id = p_variant_id;

  if current_price.suggested_price <> p_suggested_price then
    insert into public.variant_price_history (business_id, variant_id, price_kind, amount, changed_by, reason)
    values (p_business_id, p_variant_id, 'suggested', p_suggested_price, auth.uid(), normalized_reason);
  end if;

  if current_price.minimum_price <> p_minimum_price then
    insert into public.variant_price_history (business_id, variant_id, price_kind, amount, changed_by, reason)
    values (p_business_id, p_variant_id, 'minimum', p_minimum_price, auth.uid(), normalized_reason);
  end if;

  insert into public.audit_events (
    business_id,
    actor_user_id,
    event_type,
    entity_type,
    entity_id,
    data
  )
  values (
    p_business_id,
    auth.uid(),
    'catalog.variant_prices_updated',
    'product_variant',
    p_variant_id,
    jsonb_build_object(
      'previous_suggested_price', current_price.suggested_price,
      'previous_minimum_price', current_price.minimum_price,
      'suggested_price', p_suggested_price,
      'minimum_price', p_minimum_price,
      'reason', normalized_reason
    )
  );
end;
$$;

create function public.get_catalog_variants(
  p_business_id uuid,
  p_query text default null
)
returns table (
  product_id uuid,
  variant_id uuid,
  product_name text,
  product_code text,
  variant_code text,
  category_name text,
  brand_name text,
  attributes jsonb,
  suggested_price numeric,
  minimum_price numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'catalog.read') then
    raise exception 'No tienes permiso para consultar el catálogo de este negocio.';
  end if;

  return query
  select
    product.id,
    variant.id,
    product.name,
    product.internal_code,
    variant.internal_code,
    category.name,
    brand.name,
    variant.attributes,
    case when public.has_business_permission(p_business_id, 'pricing.read') then price.suggested_price else null end,
    case when public.has_business_permission(p_business_id, 'pricing.read') then price.minimum_price else null end
  from public.product_variants variant
  join public.products product on product.id = variant.product_id
  join public.categories category on category.id = product.category_id
  left join public.brands brand on brand.id = product.brand_id
  left join public.variant_current_prices price on price.variant_id = variant.id
  where variant.business_id = p_business_id
    and variant.is_active
    and product.is_active
    and (
      nullif(btrim(p_query), '') is null
      or product.name ilike '%' || btrim(p_query) || '%'
      or product.internal_code ilike '%' || btrim(p_query) || '%'
      or variant.internal_code ilike '%' || btrim(p_query) || '%'
      or category.name ilike '%' || btrim(p_query) || '%'
      or coalesce(brand.name, '') ilike '%' || btrim(p_query) || '%'
      or variant.attributes::text ilike '%' || btrim(p_query) || '%'
    )
  order by product.name, variant.sequence_number;
end;
$$;

alter table public.categories enable row level security;
alter table public.brands enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.variant_current_prices enable row level security;
alter table public.variant_price_history enable row level security;

create policy "members read categories with catalog permission"
on public.categories for select to authenticated
using (public.has_business_permission(business_id, 'catalog.read'));

create policy "members read brands with catalog permission"
on public.brands for select to authenticated
using (public.has_business_permission(business_id, 'catalog.read'));

create policy "members read products with catalog permission"
on public.products for select to authenticated
using (public.has_business_permission(business_id, 'catalog.read'));

create policy "members read variants with catalog permission"
on public.product_variants for select to authenticated
using (public.has_business_permission(business_id, 'catalog.read'));

create policy "members read current prices with pricing permission"
on public.variant_current_prices for select to authenticated
using (public.has_business_permission(business_id, 'pricing.read'));

create policy "members read price history with pricing permission"
on public.variant_price_history for select to authenticated
using (public.has_business_permission(business_id, 'pricing.read'));

revoke all on function public.validate_catalog_attributes(jsonb) from public;
revoke all on function public.create_catalog_product(uuid, text, text, text, jsonb, jsonb, numeric, numeric) from public;
grant execute on function public.create_catalog_product(uuid, text, text, text, jsonb, jsonb, numeric, numeric) to authenticated;
revoke all on function public.create_product_variant(uuid, uuid, jsonb, numeric, numeric) from public;
grant execute on function public.create_product_variant(uuid, uuid, jsonb, numeric, numeric) to authenticated;
revoke all on function public.update_variant_prices(uuid, uuid, numeric, numeric, text) from public;
grant execute on function public.update_variant_prices(uuid, uuid, numeric, numeric, text) to authenticated;
revoke all on function public.get_catalog_variants(uuid, text) from public;
grant execute on function public.get_catalog_variants(uuid, text) to authenticated;
