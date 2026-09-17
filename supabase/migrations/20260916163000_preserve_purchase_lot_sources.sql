-- Las compras siguen siendo el origen explícito de sus lotes después de
-- introducir lotes especiales para ajustes y cambios.
create or replace function public.confirm_purchase(
  p_business_id uuid,
  p_purchase_id uuid,
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  purchase_row public.purchases%rowtype;
  line_row public.purchase_lines%rowtype;
  lot_id uuid;
  previous_cost numeric(14, 2);
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'purchases.confirm') then
    raise exception 'No tienes permiso para confirmar compras.';
  end if;
  select * into purchase_row from public.purchases
  where id = p_purchase_id and business_id = p_business_id for update;
  if not found then raise exception 'La compra no está disponible en este negocio.'; end if;
  if purchase_row.status = 'confirmed' then return purchase_row.id; end if;
  if purchase_row.status <> 'pending_confirmation' then
    raise exception 'La compra no puede confirmarse en su estado actual.';
  end if;
  if exists (
    select 1 from public.purchases
    where business_id = p_business_id and confirmation_request_id = p_request_id
  ) then
    return purchase_row.id;
  end if;
  update public.purchases
  set status = 'confirmed', confirmed_by = auth.uid(), confirmed_at = now(),
      confirmation_request_id = p_request_id
  where id = purchase_row.id;
  for line_row in select * from public.purchase_lines where purchase_id = purchase_row.id loop
    select lot.unit_cost into previous_cost
    from public.inventory_lots lot
    where lot.variant_id = line_row.variant_id and lot.unit_cost is not null
    order by lot.received_at desc, lot.created_at desc, lot.id desc
    limit 1;
    insert into public.inventory_lots (
      business_id, variant_id, purchase_line_id, received_quantity, unit_cost,
      received_at, source_type, source_id
    ) values (
      p_business_id, line_row.variant_id, line_row.id, line_row.quantity,
      line_row.unit_cost, purchase_row.purchased_at, 'purchase_line', line_row.id
    ) returning id into lot_id;
    insert into public.inventory_movements (
      business_id, variant_id, lot_id, movement_type, inventory_state, quantity_delta,
      source_type, source_id, occurred_at, created_by
    ) values (
      p_business_id, line_row.variant_id, lot_id, 'purchase', 'available', line_row.quantity,
      'purchase_line', line_row.id, purchase_row.purchased_at, auth.uid()
    );
    if previous_cost is not null and line_row.unit_cost > previous_cost then
      insert into public.purchase_price_reviews (
        business_id, purchase_line_id, variant_id, previous_unit_cost, current_unit_cost
      ) values (
        p_business_id, line_row.id, line_row.variant_id, previous_cost, line_row.unit_cost
      );
    end if;
  end loop;
  if purchase_row.payment_type <> 'cash' then
    insert into public.supplier_account_entries (
      business_id, supplier_id, purchase_id, entry_type, amount, created_by
    ) values (
      p_business_id, purchase_row.supplier_id, purchase_row.id, 'purchase_charge', purchase_row.total_amount, auth.uid()
    );
    if purchase_row.initial_payment_amount > 0 then
      insert into public.supplier_account_entries (
        business_id, supplier_id, purchase_id, entry_type, amount, created_by
      ) values (
        p_business_id, purchase_row.supplier_id, purchase_row.id, 'initial_payment', -purchase_row.initial_payment_amount, auth.uid()
      );
    end if;
  end if;
  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (p_business_id, auth.uid(), 'purchase.confirmed', 'purchase', purchase_row.id,
          jsonb_build_object('total', purchase_row.total_amount));
  return purchase_row.id;
end;
$$;

revoke all on function public.confirm_purchase(uuid, uuid, uuid) from public;
grant execute on function public.confirm_purchase(uuid, uuid, uuid) to authenticated;
