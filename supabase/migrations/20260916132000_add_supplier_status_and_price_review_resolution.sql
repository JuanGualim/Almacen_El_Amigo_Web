create function public.set_supplier_active_status(
  p_business_id uuid,
  p_supplier_id uuid,
  p_is_active boolean
)
returns void
language plpgsql security definer set search_path = public as $$
declare previous_status boolean;
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'purchases.confirm') then
    raise exception 'No tienes permiso para cambiar el estado del distribuidor.';
  end if;

  select is_active into previous_status
  from public.suppliers
  where id = p_supplier_id and business_id = p_business_id
  for update;

  if previous_status is null then
    raise exception 'El distribuidor no está disponible en este negocio.';
  end if;

  if previous_status = p_is_active then
    return;
  end if;

  update public.suppliers
  set is_active = p_is_active
  where id = p_supplier_id and business_id = p_business_id;

  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (
    p_business_id,
    auth.uid(),
    'supplier.status_changed',
    'supplier',
    p_supplier_id,
    jsonb_build_object('previous_is_active', previous_status, 'is_active', p_is_active)
  );
end;
$$;

create function public.resolve_purchase_price_review(
  p_business_id uuid,
  p_review_id uuid,
  p_reason text
)
returns void
language plpgsql security definer set search_path = public as $$
declare review_status public.price_review_status;
begin
  if auth.uid() is null or not public.has_business_permission(p_business_id, 'pricing.manage') then
    raise exception 'No tienes permiso para resolver revisiones de precio.';
  end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 then
    raise exception 'Indica el motivo de la decisión sobre el precio.';
  end if;

  select status into review_status
  from public.purchase_price_reviews
  where id = p_review_id and business_id = p_business_id
  for update;

  if review_status is null then
    raise exception 'La revisión de precio no está disponible en este negocio.';
  end if;
  if review_status = 'resolved' then
    return;
  end if;

  update public.purchase_price_reviews
  set status = 'resolved'
  where id = p_review_id;

  insert into public.audit_events (business_id, actor_user_id, event_type, entity_type, entity_id, data)
  values (
    p_business_id,
    auth.uid(),
    'purchase_price_review.resolved',
    'purchase_price_review',
    p_review_id,
    jsonb_build_object('reason', btrim(p_reason))
  );
end;
$$;

revoke all on function public.set_supplier_active_status(uuid, uuid, boolean) from public;
grant execute on function public.set_supplier_active_status(uuid, uuid, boolean) to authenticated;
revoke all on function public.resolve_purchase_price_review(uuid, uuid, text) from public;
grant execute on function public.resolve_purchase_price_review(uuid, uuid, text) to authenticated;
