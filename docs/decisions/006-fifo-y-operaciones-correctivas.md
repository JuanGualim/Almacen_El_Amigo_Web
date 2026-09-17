# ADR 006: FIFO y operaciones correctivas auditables

- Estado: aceptada
- Fecha: 2026-09-16

## Contexto

Una existencia agregada por variante no permite saber qué costo o lote fue
afectado por una venta, una salida, una cancelación o un producto defectuoso.
Además, una corrección no puede elegir un lote nuevo al azar ni borrar el
rastro de la operación original.

## Decisión

- Cada salida nueva de venta, salida autorizada, ajuste negativo o cambio
  consume lotes disponibles en orden `received_at`, `created_at`, `id`, con
  bloqueo por variante dentro de la transacción.
- `inventory_lot_allocations` registra el consumo. Una cancelación de venta o
  el producto recibido en un cambio de la misma variante crea una asignación
  `reversal` ligada al consumo original; nunca modifica ni elimina el consumo.
- Los defectuosos se reclasifican desde lotes concretos a
  `defective_pending`; no son una salida definitiva. Los ajustes positivos y
  cambios que no recuperan una asignación original crean lotes especiales sin
  inventar una compra ni un costo.
- Los abonos generales se confirman antes de impactar el saldo y sus
  aplicaciones a compras son registros independientes. Una compra confirmada
  solo admite cancelación directa si sus lotes no tienen consumos,
  reversiones, reclasificaciones ni abonos aplicados.
- Los cambios no reembolsan: el valor del producto entregado debe ser igual o
  mayor al valor reconocido; la diferencia se cobra por la caja abierta del
  día cuando corresponde.

## Consecuencias

- El costo de un lote queda trazable en las salidas sin cambiar precios de
  venta históricos.
- Las operaciones con dependencias se corrigen mediante un flujo posterior,
  no mediante una cancelación directa que rompa la auditoría.
- El backfill existente y las operaciones nuevas fallan atómicamente si no hay
  cantidad de lote suficiente; el inventario no queda parcialmente aplicado.
