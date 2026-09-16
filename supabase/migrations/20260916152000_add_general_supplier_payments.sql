create type public.supplier_payment_status as enum ('pending', 'confirmed');
create type public.supplier_payment_method as enum ('cash', 'qr', 'transfer', 'card');
create table public.supplier_payments (
 id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id) on delete restrict, supplier_id uuid not null,
 amount numeric(14,2) not null check(amount>0), payment_method public.supplier_payment_method not null, reference text, notes text,
 status public.supplier_payment_status not null default 'pending', request_id uuid not null, registered_by uuid not null references auth.users(id), registered_at timestamptz not null default now(), confirmed_by uuid references auth.users(id), confirmed_at timestamptz,
 constraint supplier_payments_supplier_business foreign key(supplier_id,business_id) references public.suppliers(id,business_id) on delete restrict,
 constraint supplier_payments_request_unique unique(business_id,request_id),
 constraint supplier_payments_confirmed_fields check((status='pending' and confirmed_by is null and confirmed_at is null) or(status='confirmed' and confirmed_by is not null and confirmed_at is not null))
);
create index supplier_payments_business_supplier_idx on public.supplier_payments(business_id,supplier_id,status);
alter table public.supplier_payments enable row level security;
create policy "owners or registrars read supplier payments" on public.supplier_payments for select to authenticated using(public.has_business_permission(business_id,'payables.read') or registered_by=auth.uid());
create function public.record_general_supplier_payment(p_business_id uuid,p_supplier_id uuid,p_amount numeric,p_method public.supplier_payment_method,p_reference text,p_notes text,p_request_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$ declare payment_id uuid; begin
 if auth.uid() is null or not public.has_business_permission(p_business_id,'purchases.create') then raise exception 'No tienes permiso para registrar abonos.'; end if;
 select id into payment_id from public.supplier_payments where business_id=p_business_id and request_id=p_request_id; if payment_id is not null then return payment_id; end if;
 if p_amount is null or p_amount<=0 or p_amount<>round(p_amount,2) then raise exception 'El importe del abono no es válido.'; end if;
 if not exists(select 1 from public.suppliers where id=p_supplier_id and business_id=p_business_id and is_active) then raise exception 'El distribuidor no está activo en este negocio.'; end if;
 insert into public.supplier_payments(business_id,supplier_id,amount,payment_method,reference,notes,request_id,registered_by) values(p_business_id,p_supplier_id,p_amount,p_method,nullif(btrim(p_reference),''),nullif(btrim(p_notes),''),p_request_id,auth.uid()) returning id into payment_id;
 insert into public.audit_events(business_id,actor_user_id,event_type,entity_type,entity_id,data) values(p_business_id,auth.uid(),'supplier_payment.recorded','supplier_payment',payment_id,jsonb_build_object('status','pending','amount',p_amount)); return payment_id; end; $$;
create function public.confirm_general_supplier_payment(p_business_id uuid,p_payment_id uuid,p_request_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$ declare payment_row public.supplier_payments%rowtype; begin
 if auth.uid() is null or not public.has_business_permission(p_business_id,'payables.manage') then raise exception 'No tienes permiso para confirmar abonos.'; end if;
 select * into payment_row from public.supplier_payments where id=p_payment_id and business_id=p_business_id for update; if not found then raise exception 'El abono no está disponible.'; end if; if payment_row.status='confirmed' then return payment_row.id; end if;
 update public.supplier_payments set status='confirmed',confirmed_by=auth.uid(),confirmed_at=now() where id=payment_row.id;
 insert into public.audit_events(business_id,actor_user_id,event_type,entity_type,entity_id,data) values(p_business_id,auth.uid(),'supplier_payment.confirmed','supplier_payment',payment_row.id,jsonb_build_object('amount',payment_row.amount)); return payment_row.id; end; $$;
create function public.get_supplier_balances(p_business_id uuid) returns table(supplier_id uuid,supplier_name text,balance numeric)
language plpgsql stable security definer set search_path=public as $$ begin if auth.uid() is null or not public.has_business_permission(p_business_id,'payables.read') then raise exception 'No tienes permiso para consultar saldos.'; end if; return query select supplier.id,supplier.name,coalesce(entries.total,0)-coalesce(payments.total,0) from public.suppliers supplier left join lateral(select sum(amount) total from public.supplier_account_entries entry where entry.supplier_id=supplier.id) entries on true left join lateral(select sum(amount) total from public.supplier_payments payment where payment.supplier_id=supplier.id and payment.status='confirmed') payments on true where supplier.business_id=p_business_id order by supplier.name; end; $$;
revoke all on function public.record_general_supplier_payment(uuid,uuid,numeric,public.supplier_payment_method,text,text,uuid) from public; grant execute on function public.record_general_supplier_payment(uuid,uuid,numeric,public.supplier_payment_method,text,text,uuid) to authenticated;
revoke all on function public.confirm_general_supplier_payment(uuid,uuid,uuid) from public; grant execute on function public.confirm_general_supplier_payment(uuid,uuid,uuid) to authenticated;
revoke all on function public.get_supplier_balances(uuid) from public; grant execute on function public.get_supplier_balances(uuid) to authenticated;
