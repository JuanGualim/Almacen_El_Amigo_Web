create or replace function public.confirm_sale(
  p_business_id uuid, p_cash_session_id uuid, p_payment_method public.sale_payment_method, p_lines jsonb, p_request_id uuid
) returns uuid language plpgsql security definer set search_path = public as $$
declare sale_id uuid; session_status public.cash_session_status; line_item record; variant_row record; available_quantity bigint; calculated_total numeric(14,2):=0; sale_line_id uuid; authorized_lines text := current_setting('app.authorized_sale_lines', true);
begin
 if auth.uid() is null or not public.has_business_permission(p_business_id,'sales.create') then raise exception 'No tienes permiso para registrar ventas.'; end if;
 select id into sale_id from public.sales where business_id=p_business_id and request_id=p_request_id; if sale_id is not null then return sale_id; end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'La venta debe contener al menos una línea.'; end if;
 if exists(select 1 from jsonb_to_recordset(p_lines) as line(variant_id uuid,quantity integer,unit_price numeric) where variant_id is null or quantity is null or quantity<=0 or unit_price is null or unit_price<0 or unit_price<>round(unit_price,2)) then raise exception 'Cada línea requiere variante, cantidad entera positiva y precio válido.'; end if;
 select status into session_status from public.cash_register_sessions where id=p_cash_session_id and business_id=p_business_id for update; if session_status is distinct from 'open' then raise exception 'Debes tener una caja abierta para confirmar la venta.'; end if;
 for line_item in select * from jsonb_to_recordset(p_lines) as line(variant_id uuid,quantity integer,unit_price numeric) loop
  perform pg_advisory_xact_lock(hashtextextended(p_business_id::text||line_item.variant_id::text,0));
  select product.name product_name,variant.internal_code variant_code,variant.attributes,price.suggested_price,price.minimum_price into variant_row from public.product_variants variant join public.products product on product.id=variant.product_id join public.variant_current_prices price on price.variant_id=variant.id where variant.id=line_item.variant_id and variant.business_id=p_business_id and variant.is_active and product.is_active;
  if not found then raise exception 'Una variante no está disponible para venta en este negocio.'; end if;
  if line_item.unit_price<variant_row.minimum_price and authorized_lines is distinct from p_lines::text then raise exception 'El precio negociado no puede ser menor al precio mínimo.'; end if;
  select coalesce(sum(quantity_delta),0)::bigint into available_quantity from public.inventory_movements where business_id=p_business_id and variant_id=line_item.variant_id and inventory_state='available'; if available_quantity<line_item.quantity then raise exception 'No hay existencias disponibles suficientes para esta venta.'; end if;
  calculated_total:=calculated_total+line_item.quantity*line_item.unit_price;
 end loop;
 insert into public.sales(business_id,cash_session_id,total_amount,sold_by,request_id) values(p_business_id,p_cash_session_id,calculated_total,auth.uid(),p_request_id) returning id into sale_id;
 for line_item in select * from jsonb_to_recordset(p_lines) as line(variant_id uuid,quantity integer,unit_price numeric) loop
  select product.name product_name,variant.internal_code variant_code,variant.attributes,price.suggested_price,price.minimum_price into variant_row from public.product_variants variant join public.products product on product.id=variant.product_id join public.variant_current_prices price on price.variant_id=variant.id where variant.id=line_item.variant_id;
  insert into public.sale_lines(business_id,sale_id,variant_id,product_name_snapshot,variant_code_snapshot,attributes_snapshot,quantity,suggested_price_snapshot,minimum_price_snapshot,unit_price) values(p_business_id,sale_id,line_item.variant_id,variant_row.product_name,variant_row.variant_code,variant_row.attributes,line_item.quantity,variant_row.suggested_price,variant_row.minimum_price,line_item.unit_price) returning id into sale_line_id;
  insert into public.inventory_movements(business_id,variant_id,movement_type,inventory_state,quantity_delta,source_type,source_id,occurred_at,created_by) values(p_business_id,line_item.variant_id,'sale','available',-line_item.quantity,'sale_line',sale_line_id,now(),auth.uid());
 end loop;
 insert into public.sale_payments(business_id,sale_id,payment_method,amount) values(p_business_id,sale_id,p_payment_method,calculated_total); if p_payment_method='cash' then insert into public.cash_movements(business_id,cash_session_id,sale_id,movement_type,amount,created_by) values(p_business_id,p_cash_session_id,sale_id,'sale_cash',calculated_total,auth.uid()); end if;
 insert into public.audit_events(business_id,actor_user_id,event_type,entity_type,entity_id,data) values(p_business_id,auth.uid(),'sale.confirmed','sale',sale_id,jsonb_build_object('total',calculated_total,'payment_method',p_payment_method)); return sale_id;
end; $$;

create function public.confirm_sale_with_price_authorization(p_business_id uuid,p_cash_session_id uuid,p_payment_method public.sale_payment_method,p_lines jsonb,p_request_id uuid,p_authorization_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare authorization_row public.sale_price_authorizations%rowtype; sale_id uuid;
begin
 if auth.uid() is null or not public.has_business_permission(p_business_id,'sales.create') then raise exception 'No tienes permiso para registrar ventas.'; end if;
 select * into authorization_row from public.sale_price_authorizations where id=p_authorization_id and business_id=p_business_id for update;
 if not found or authorization_row.requested_by<>auth.uid() or authorization_row.status<>'approved' or authorization_row.expires_at<=now() or authorization_row.lines<>p_lines then raise exception 'La autorización no es válida para esta venta.'; end if;
 perform set_config('app.authorized_sale_lines',p_lines::text,true); sale_id:=public.confirm_sale(p_business_id,p_cash_session_id,p_payment_method,p_lines,p_request_id);
 update public.sale_price_authorizations set status='consumed',consumed_sale_id=sale_id where id=p_authorization_id; update public.sales set sale_price_authorization_id=p_authorization_id where id=sale_id;
 return sale_id;
end; $$;
revoke all on function public.confirm_sale_with_price_authorization(uuid,uuid,public.sale_payment_method,jsonb,uuid,uuid) from public; grant execute on function public.confirm_sale_with_price_authorization(uuid,uuid,public.sale_payment_method,jsonb,uuid,uuid) to authenticated;
