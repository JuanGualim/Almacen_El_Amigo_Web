create function public.get_open_cash_register_summary(p_business_id uuid)
returns table(
  cash_session_id uuid,
  business_date date,
  opening_fund numeric,
  expected_cash numeric,
  cash_sales numeric,
  qr_sales numeric,
  transfer_sales numeric,
  card_sales numeric,
  sale_count bigint
)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or not (
    public.has_business_permission(p_business_id, 'sales.create')
    or public.has_business_permission(p_business_id, 'cash_register.open')
    or public.has_business_permission(p_business_id, 'cash_register.close')
  ) then
    raise exception 'No tienes permiso para consultar la caja.';
  end if;

  return query
  select
    session.id,
    session.business_date,
    session.opening_fund,
    session.opening_fund + movements.total_amount,
    payments.cash_total,
    payments.qr_total,
    payments.transfer_total,
    payments.card_total,
    payments.sales_count
  from public.cash_register_sessions session
  cross join lateral (
    select coalesce(sum(movement.amount), 0) as total_amount
    from public.cash_movements movement
    where movement.cash_session_id = session.id
  ) movements
  cross join lateral (
    select
      coalesce(sum(payment.amount) filter (where payment.payment_method = 'cash'), 0) as cash_total,
      coalesce(sum(payment.amount) filter (where payment.payment_method = 'qr'), 0) as qr_total,
      coalesce(sum(payment.amount) filter (where payment.payment_method = 'transfer'), 0) as transfer_total,
      coalesce(sum(payment.amount) filter (where payment.payment_method = 'card'), 0) as card_total,
      count(*)::bigint as sales_count
    from public.sales sale
    join public.sale_payments payment on payment.sale_id = sale.id
    where sale.cash_session_id = session.id
  ) payments
  where session.business_id = p_business_id and session.status = 'open';
end;
$$;

revoke all on function public.get_open_cash_register_summary(uuid) from public;
grant execute on function public.get_open_cash_register_summary(uuid) to authenticated;
