-- PostgreSQL requiere confirmar el nuevo valor del enum antes de utilizarlo
-- en una restricción o función de la migración siguiente.
alter type public.cash_movement_type add value if not exists 'exchange_cash';
alter type public.purchase_status add value if not exists 'cancelled';
alter type public.supplier_account_entry_type add value if not exists 'purchase_cancellation';
