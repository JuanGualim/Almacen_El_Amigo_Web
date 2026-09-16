# ADR 005: Ventas atómicas y caja única

- Estado: aceptada
- Fecha: 2026-09-16

## Contexto

La venta debe ser rápida para la operación diaria, pero no puede confirmar un
ingreso sin afectar inventario, ni afectar efectivo sin una venta histórica.
El MVP controla una única caja de ventas y debe distinguir el efectivo físico
de QR, transferencia y tarjeta.

## Decisión

- Una caja se abre una sola vez por día comercial, calculado con la zona
  horaria configurada para el negocio. Reabrirla después del cierre requiere
  una decisión operativa posterior, no se habilita de forma implícita.
- Todas las ventas requieren una caja abierta. La confirmación de venta se
  ejecuta en una transacción: guarda encabezado, líneas con precios históricos,
  pago, movimiento de inventario y, solamente para efectivo, movimiento de
  caja.
- Las existencias se verifican en el servidor y se serializan por variante
  durante la venta para impedir sobreventas concurrentes. Un identificador de
  solicitud devuelve la misma venta ante un reintento.
- En esta fase ningún usuario puede vender debajo del precio mínimo. La
  autorización excepcional con PIN y evidencia permanece bloqueada para la
  fase 6.
- El cierre calcula el efectivo esperado desde fondo inicial y movimientos en
  efectivo. Un faltante o sobrante debe guardar una explicación y no se oculta
  ni se compensa automáticamente.

## Consecuencias

- QR, transferencia y tarjeta se reportan en el resumen de caja pero no
  aumentan el efectivo esperado.
- El empleado puede confirmar ventas y cerrar caja según los permisos
  iniciales; la apertura queda restringida a quien tenga `cash_register.open`.
- Salidas, retiros, entradas excepcionales, devoluciones, cambios y crédito de
  clientes no se incluyen todavía; tendrán movimientos y reglas propias en las
  fases posteriores.
