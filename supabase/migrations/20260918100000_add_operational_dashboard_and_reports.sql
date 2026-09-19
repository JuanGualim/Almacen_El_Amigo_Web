-- Fase 7: consultas operativas y reportes. Se entregan como JSON desde el
-- servidor para que los permisos no dependan de filtros de la interfaz.

create function public.get_operational_dashboard(p_business_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  business_timezone text;
  current_business_date date;
  can_read_inventory boolean;
  can_manage_pricing boolean;
  can_manage_payables boolean;
  can_manage_adjustments boolean;
  can_read_sensitive_reports boolean;
  is_owner boolean;
  open_cash_session jsonb;
  sensitive_summary jsonb := null;
begin
  if auth.uid() is null or not public.is_active_business_member(p_business_id) then
    raise exception 'No tienes acceso a este negocio.';
  end if;

  select timezone into business_timezone
  from public.businesses
  where id = p_business_id;

  if business_timezone is null then
    raise exception 'El negocio no está disponible.';
  end if;

  current_business_date := (now() at time zone business_timezone)::date;
  is_owner := public.is_business_owner(p_business_id);
  can_read_inventory := public.has_business_permission(p_business_id, 'inventory.read');
  can_manage_pricing := public.has_business_permission(p_business_id, 'pricing.manage');
  can_manage_payables := public.has_business_permission(p_business_id, 'payables.manage');
  can_manage_adjustments := public.has_business_permission(p_business_id, 'inventory.adjust');
  can_read_sensitive_reports := public.has_business_permission(p_business_id, 'reports.read_sensitive');

  select jsonb_build_object(
    'id', session.id,
    'business_date', session.business_date,
    'opening_fund', session.opening_fund
  )
  into open_cash_session
  from public.cash_register_sessions session
  where session.business_id = p_business_id
    and session.status = 'open'
  order by session.opened_at desc
  limit 1;

  if can_read_sensitive_reports then
    sensitive_summary := jsonb_build_object(
      'today_sales_amount', coalesce((
        select sum(sale.total_amount)
        from public.sales sale
        where sale.business_id = p_business_id
          and sale.status = 'confirmed'
          and (sale.confirmed_at at time zone business_timezone)::date = current_business_date
      ), 0),
      'today_sales_count', (
        select count(*)
        from public.sales sale
        where sale.business_id = p_business_id
          and sale.status = 'confirmed'
          and (sale.confirmed_at at time zone business_timezone)::date = current_business_date
      ),
      'open_supplier_balance', coalesce((
        select sum(balance)
        from public.get_supplier_balances(p_business_id)
      ), 0)
    );
  end if;

  return jsonb_build_object(
    'business_date', current_business_date,
    'open_cash_session', open_cash_session,
    'pending_price_reviews', case when can_manage_pricing then (
      select count(*) from public.purchase_price_reviews review
      where review.business_id = p_business_id and review.status = 'pending'
    ) else null end,
    'pending_supplier_payments', case when can_manage_payables then (
      select count(*) from public.supplier_payments payment
      where payment.business_id = p_business_id and payment.status = 'pending'
    ) else null end,
    'pending_defective_products', case when can_read_inventory then (
      select count(*) from public.defective_products defective
      where defective.business_id = p_business_id
        and defective.status in ('pending_supplier', 'delivered_to_supplier')
    ) else null end,
    'pending_defective_resolutions', case when can_read_inventory then (
      select count(*) from public.defective_product_resolutions resolution
      where resolution.business_id = p_business_id
        and resolution.status = 'pending_confirmation'
    ) else null end,
    'pending_inventory_adjustments', case
      when is_owner or can_manage_adjustments then (
        select count(*) from public.inventory_adjustments adjustment
        where adjustment.business_id = p_business_id
          and adjustment.status = 'pending'
          and (is_owner or adjustment.counted_by = auth.uid())
      )
      else null
    end,
    'pending_sale_authorizations', case when is_owner then (
      select count(*) from public.sale_price_authorizations price_authorization
      where price_authorization.business_id = p_business_id
        and price_authorization.status = 'pending'
    ) else null end,
    'sensitive_summary', sensitive_summary
  );
end;
$$;

create function public.get_operational_report(
  p_business_id uuid,
  p_start_date date,
  p_end_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  business_timezone text;
begin
  if auth.uid() is null
    or not public.has_business_permission(p_business_id, 'reports.read_sensitive') then
    raise exception 'No tienes permiso para consultar reportes sensibles.';
  end if;

  if p_start_date is null or p_end_date is null or p_start_date > p_end_date then
    raise exception 'El periodo del reporte no es válido.';
  end if;

  if p_end_date - p_start_date > 366 then
    raise exception 'El periodo máximo del reporte es de 367 días.';
  end if;

  select timezone into business_timezone
  from public.businesses
  where id = p_business_id;

  if business_timezone is null then
    raise exception 'El negocio no está disponible.';
  end if;

  return jsonb_build_object(
    'period', jsonb_build_object('start_date', p_start_date, 'end_date', p_end_date),
    'summary', jsonb_build_object(
      'sales_amount', coalesce((
        select sum(sale.total_amount)
        from public.sales sale
        where sale.business_id = p_business_id
          and sale.status = 'confirmed'
          and (sale.confirmed_at at time zone business_timezone)::date between p_start_date and p_end_date
      ), 0),
      'sales_count', (
        select count(*)
        from public.sales sale
        where sale.business_id = p_business_id
          and sale.status = 'confirmed'
          and (sale.confirmed_at at time zone business_timezone)::date between p_start_date and p_end_date
      ),
      'purchases_amount', coalesce((
        select sum(purchase.total_amount)
        from public.purchases purchase
        where purchase.business_id = p_business_id
          and purchase.status = 'confirmed'
          and (purchase.confirmed_at at time zone business_timezone)::date between p_start_date and p_end_date
      ), 0),
      'purchases_count', (
        select count(*)
        from public.purchases purchase
        where purchase.business_id = p_business_id
          and purchase.status = 'confirmed'
          and (purchase.confirmed_at at time zone business_timezone)::date between p_start_date and p_end_date
      ),
      'cash_difference_amount', coalesce((
        select sum(session.difference_amount)
        from public.cash_register_sessions session
        where session.business_id = p_business_id
          and session.status = 'closed'
          and session.business_date between p_start_date and p_end_date
      ), 0),
      'open_supplier_balance', coalesce((
        select sum(balance) from public.get_supplier_balances(p_business_id)
      ), 0)
    ),
    'sales_by_day', coalesce((
      select jsonb_agg(
        jsonb_build_object('date', daily.business_date, 'sales_amount', daily.sales_amount, 'sales_count', daily.sales_count)
        order by daily.business_date
      )
      from (
        select
          (sale.confirmed_at at time zone business_timezone)::date as business_date,
          sum(sale.total_amount) as sales_amount,
          count(*) as sales_count
        from public.sales sale
        where sale.business_id = p_business_id
          and sale.status = 'confirmed'
          and (sale.confirmed_at at time zone business_timezone)::date between p_start_date and p_end_date
        group by 1
      ) daily
    ), '[]'::jsonb),
    'sales_by_payment_method', coalesce((
      select jsonb_agg(
        jsonb_build_object('payment_method', payment.payment_method, 'sales_amount', payment.sales_amount, 'sales_count', payment.sales_count)
        order by payment.payment_method
      )
      from (
        select sale_payment.payment_method, sum(sale_payment.amount) as sales_amount, count(*) as sales_count
        from public.sale_payments sale_payment
        join public.sales sale on sale.id = sale_payment.sale_id
        where sale.business_id = p_business_id
          and sale.status = 'confirmed'
          and (sale.confirmed_at at time zone business_timezone)::date between p_start_date and p_end_date
        group by sale_payment.payment_method
      ) payment
    ), '[]'::jsonb),
    'top_sold_variants', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'product_name', variant.product_name,
          'variant_code', variant.variant_code,
          'quantity', variant.quantity,
          'sales_amount', variant.sales_amount
        )
        order by variant.quantity desc, variant.sales_amount desc, variant.product_name, variant.variant_code
      )
      from (
        select
          line.product_name_snapshot as product_name,
          line.variant_code_snapshot as variant_code,
          sum(line.quantity) as quantity,
          sum(line.line_total) as sales_amount
        from public.sale_lines line
        join public.sales sale on sale.id = line.sale_id
        where sale.business_id = p_business_id
          and sale.status = 'confirmed'
          and (sale.confirmed_at at time zone business_timezone)::date between p_start_date and p_end_date
        group by line.product_name_snapshot, line.variant_code_snapshot
        order by sum(line.quantity) desc, sum(line.line_total) desc, line.product_name_snapshot, line.variant_code_snapshot
        limit 10
      ) variant
    ), '[]'::jsonb),
    'purchases_by_supplier', coalesce((
      select jsonb_agg(
        jsonb_build_object('supplier_name', supplier.supplier_name, 'purchases_amount', supplier.purchases_amount, 'purchases_count', supplier.purchases_count)
        order by supplier.purchases_amount desc, supplier.supplier_name
      )
      from (
        select
          distributor.name as supplier_name,
          sum(purchase.total_amount) as purchases_amount,
          count(*) as purchases_count
        from public.purchases purchase
        join public.suppliers distributor on distributor.id = purchase.supplier_id
        where purchase.business_id = p_business_id
          and purchase.status = 'confirmed'
          and (purchase.confirmed_at at time zone business_timezone)::date between p_start_date and p_end_date
        group by distributor.name
        order by sum(purchase.total_amount) desc, distributor.name
      ) supplier
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_operational_dashboard(uuid) from public;
grant execute on function public.get_operational_dashboard(uuid) to authenticated;
revoke all on function public.get_operational_report(uuid, date, date) from public;
grant execute on function public.get_operational_report(uuid, date, date) to authenticated;
