create type public.inventory_lot_allocation_kind as enum ('consumption', 'reversal', 'legacy_backfill');
alter table public.inventory_lots add constraint inventory_lots_id_business_unique unique(id,business_id);
alter table public.inventory_movements add constraint inventory_movements_id_business_unique unique(id,business_id);
create table public.inventory_lot_allocations(
 id uuid primary key default gen_random_uuid(), business_id uuid not null, lot_id uuid not null, inventory_movement_id uuid not null, original_allocation_id uuid references public.inventory_lot_allocations(id) on delete restrict, allocation_kind public.inventory_lot_allocation_kind not null, quantity integer not null check(quantity>0), source_type text not null, source_id uuid not null, created_at timestamptz not null default now(),
 constraint inventory_lot_allocations_lot_business foreign key(lot_id,business_id) references public.inventory_lots(id,business_id) on delete restrict,
 constraint inventory_lot_allocations_movement_business foreign key(inventory_movement_id,business_id) references public.inventory_movements(id,business_id) on delete restrict,
 constraint inventory_lot_allocations_reversal check((allocation_kind='reversal' and original_allocation_id is not null) or (allocation_kind<>'reversal' and original_allocation_id is null)),
 constraint inventory_lot_allocations_movement_lot_unique unique(inventory_movement_id,lot_id)
);
create index inventory_lot_allocations_lot_idx on public.inventory_lot_allocations(lot_id,created_at);
alter table public.inventory_lot_allocations enable row level security;
create policy "owners read lot allocations" on public.inventory_lot_allocations for select to authenticated using(public.is_business_owner(business_id));

do $$
declare movement record; lot record; remaining integer; available integer;
begin
 for movement in select * from public.inventory_movements where inventory_state='available' and quantity_delta<0 and movement_type in ('sale','authorized_exit','adjustment') order by occurred_at,created_at,id loop
  remaining := -movement.quantity_delta;
  for lot in select lot.* from public.inventory_lots lot where lot.business_id=movement.business_id and lot.variant_id=movement.variant_id order by lot.received_at,lot.created_at,lot.id loop
   select lot.received_quantity-coalesce(sum(case when allocation_kind in ('consumption','legacy_backfill') then quantity else -quantity end),0)::integer into available from public.inventory_lot_allocations where lot_id=lot.id;
   if available>0 then
    insert into public.inventory_lot_allocations(business_id,lot_id,inventory_movement_id,allocation_kind,quantity,source_type,source_id) values(movement.business_id,lot.id,movement.id,'legacy_backfill',least(remaining,available),movement.source_type,movement.source_id);
    remaining:=remaining-least(remaining,available); if remaining=0 then exit; end if;
   end if;
  end loop;
  if remaining<>0 then raise exception 'FIFO backfill failed for movement %: insufficient lot quantity',movement.id; end if;
 end loop;
end $$;
