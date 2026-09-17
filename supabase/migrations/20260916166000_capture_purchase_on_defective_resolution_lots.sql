-- La compra se conserva como referencia explícita de la resolución, además de
-- ser derivable desde el lote. Los lotes especiales mantienen este valor nulo.
alter table public.defective_product_resolution_lots
  add column purchase_id uuid references public.purchases(id) on delete restrict;

create or replace function public.set_defective_resolution_lot_purchase()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.purchase_id is null then
    select line.purchase_id into new.purchase_id
    from public.inventory_lots lot
    join public.purchase_lines line on line.id = lot.purchase_line_id
    where lot.id = new.lot_id;
  end if;
  return new;
end;
$$;

create trigger set_defective_resolution_lot_purchase_before_insert
before insert on public.defective_product_resolution_lots
for each row execute procedure public.set_defective_resolution_lot_purchase();

update public.defective_product_resolution_lots resolution_lot
set purchase_id = line.purchase_id
from public.inventory_lots lot
join public.purchase_lines line on line.id = lot.purchase_line_id
where lot.id = resolution_lot.lot_id
  and resolution_lot.purchase_id is null;
