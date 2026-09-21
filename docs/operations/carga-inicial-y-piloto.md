# Carga inicial y piloto controlado

## Propósito

La carga inicial establece el conteo físico verificado con el que inicia el
piloto. No representa una compra: no crea una cuenta por pagar, no cambia
precios y no sustituye la trazabilidad de las compras posteriores.

Solo el dueño puede confirmarla y el sistema admite una única carga por
negocio, antes de que exista cualquier movimiento de inventario. Cada línea
crea un lote especial y un movimiento `initial_import`, por lo que las ventas
posteriores siguen consumiendo unidades mediante FIFO. Si se conoce, el costo
unitario queda guardado en dicho lote; se puede dejar vacío cuando no se tenga
evidencia fiable de ese costo.

## Preparar la plantilla

1. En **Más → Carga inicial de inventario**, descargar la plantilla CSV.
2. Completar una fila por variante ya creada en el catálogo:

   ```csv
   variant_code,quantity,unit_cost
   ALM-000001-001,4,70.00
   ```

3. `variant_code` debe coincidir exactamente con el código interno de la
   variante, `quantity` debe ser un entero positivo y `unit_cost` admite un
   importe GTQ con dos decimales como máximo o puede quedar vacío.
4. Comparar el archivo con el conteo físico antes de subirlo. No usar datos
   reales en un entorno de prueba compartido.

La vista previa marca las variantes inexistentes y bloquea la confirmación.
Al confirmar, el servidor verifica de nuevo pertenencia al negocio, permisos,
duplicados, importación previa y ausencia de movimientos. La solicitud usa un
identificador idempotente: un reintento de la misma acción devuelve el
resultado existente.

## Piloto paralelo

Durante el piloto, mantener el registro actual como referencia y comparar cada
día comercial:

- Unidades vendidas y existencias por variante.
- Ventas por forma de pago y efectivo contado contra caja esperada.
- Compras, saldos con distribuidores y abonos confirmados.
- Operaciones pendientes, conflictos de sincronización y alertas de stock.

Una diferencia no se corrige editando existencias ni borrando operaciones. Se
usa el conteo, ajuste, cancelación u otro flujo correctivo auditado que
corresponda. Conservar las comparaciones y los motivos de cada diferencia como
evidencia del piloto.

## Condición antes de operar continuamente

La programación local usada para probar el respaldo externo debe trasladarse a
un ejecutor privado y permanente. Sus credenciales se mantienen únicamente en
ese entorno. Este paso requiere una decisión de infraestructura y no debe
hacerse desde el navegador ni con secretos versionados.
