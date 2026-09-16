# ADR 004: Compras confirmadas e inventario derivado

- Estado: aceptada
- Fecha: 2026-09-16

## Contexto

Una existencia no puede editarse directamente: una compra confirmada debe
conservar sus líneas y costos, generar lotes y producir movimientos que puedan
auditarse. Las compras a crédito o con pago parcial también deben dejar un
saldo trazable, sin adelantar la fase de abonos.

## Decisión

- Los distribuidores, compras, líneas, lotes, movimientos, revisiones de costo
  y cargos a distribuidores pertenecen a un negocio y se protegen con RLS.
- Registrar una compra crea un documento pendiente e idempotente; no altera
  existencias. Solo alguien con permiso de confirmación puede confirmarla.
- La confirmación crea en una única transacción el lote y movimiento de cada
  línea, y los cargos iniciales que correspondan por crédito o pago parcial.
  Reintentar la confirmación devuelve la misma compra sin duplicar movimientos.
- La existencia disponible se calcula sumando movimientos, en vez de guardarse
  como un contador editable.
- Un costo superior al último lote genera una revisión pendiente. Resolverla
  exige motivo y queda en auditoría; no modifica automáticamente los precios
  de venta.
- Desactivar un distribuidor conserva todo su historial y evita nuevas compras
  para ese distribuidor. Esta acción se audita y requiere permiso de
  confirmación de compras.

## Consecuencias

- El formulario admite varias líneas, facturas opcionales, fecha de compra y
  las tres modalidades de pago previstas. Los costos se calculan en unidades
  menores exactas en el cliente y como `numeric` en PostgreSQL.
- El saldo se representa con cargos y pagos iniciales inmutables. Registrar,
  confirmar y aplicar abonos seguirá siendo parte de la fase 6.
- La creación de productos y variantes se conserva en el flujo autorizado del
  catálogo antes de agregarlos a una compra. La fase actual no duplica una
  variante por diferencias de costo: crea lotes distintos.
