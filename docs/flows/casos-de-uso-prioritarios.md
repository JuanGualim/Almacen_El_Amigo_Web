# Casos de uso prioritarios

> Fase: diseño. Estos casos definen el comportamiento esperado antes de crear
> pantallas, servicios o migraciones. Los importes se representan como valores
> monetarios exactos; la interfaz los muestra en GTQ con dos decimales.

## Convenciones compartidas

- Todo caso se ejecuta dentro del negocio activo y autorizado. El sistema debe
  impedir en el servidor el acceso a datos de otro negocio.
- Los estados de una operación son `local`, `pending_sync`, `syncing`,
  `confirmed` y `conflict`. Una operación local no equivale a una operación
  confirmada.
- Las confirmaciones de venta y compra requieren un identificador idempotente.
  Reintentar la misma solicitud debe devolver su resultado y no duplicar
  movimientos, caja, lotes ni saldos.
- Los registros confirmados no se eliminan físicamente. Las correcciones se
  harán mediante los flujos auditables que se diseñen para ello.

## CU-01: Consultar inicio operativo

**Actor principal:** dueño o empleado autorizado.  
**Objetivo:** conocer el estado del día y entrar rápidamente a las tareas
frecuentes.

### Precondiciones

- La persona inició sesión y tiene un negocio activo.
- El usuario cuenta con permiso para consultar el inicio.

### Flujo principal

1. El usuario abre Inicio.
2. El sistema obtiene los datos operativos del negocio activo y del día
   comercial en la zona horaria configurada del negocio.
3. El sistema muestra el resumen de ventas y caja permitido para el rol.
4. El sistema muestra alertas y pendientes visibles para el usuario,
   ordenados por prioridad.
5. El usuario puede iniciar una venta, una compra o ir al inventario desde un
   acceso rápido.

### Reglas y excepciones

- Un empleado no ve saldos totales de distribuidores, costos, ganancias ni
  datos financieros que no tenga autorizados.
- Las alertas pueden incluir stock bajo, producto agotado, sincronizaciones en
  conflicto, abonos pendientes (solo dueño), costos mayores con precio por
  revisar y defectuosos pendientes.
- Si no hay conexión, se muestra el último resumen local con su fecha de
  actualización y el estado de conexión; nunca se presenta como información
  actualizada.
- Si no hay datos para una tarjeta, se muestra un estado vacío explicativo en
  lugar de un cero ambiguo.

### Resultado

El usuario ve únicamente la información autorizada de su negocio y puede
continuar a una operación prioritaria.

## CU-02: Registrar una nueva venta

**Actor principal:** empleado o dueño.  
**Objetivo:** confirmar una venta detallada, reducir existencias y registrar el
efecto de caja exactamente una vez.

### Precondiciones

- El usuario inició sesión, tiene negocio activo y permiso para vender.
- Existe una caja de ventas abierta cuando la política de operación lo exija.
- Las variantes añadidas están disponibles, salvo el tratamiento explícito de
  conflicto durante la sincronización.

### Flujo principal

1. El usuario abre Nueva venta.
2. Busca por nombre, código interno, categoría, marca, diseño, talla, color o
   disponibilidad; selecciona una variante.
3. Indica la cantidad y el precio negociado. El sistema muestra precio
   sugerido, precio mínimo y existencia disponible.
4. El sistema valida cantidad entera positiva y precio negociado.
5. El usuario añade una o más líneas al carrito; líneas de la misma variante y
   mismo precio se consolidan.
6. El usuario elige la forma de pago. Inicialmente se propone una sola forma:
   efectivo, QR, transferencia, tarjeta o crédito excepcional autorizado.
7. El sistema muestra total, pago y confirmación explícita.
8. El usuario confirma. El sistema envía la operación atómica con un
   identificador idempotente.
9. Al confirmarse, el sistema crea la venta, sus líneas históricas, el
   movimiento de inventario y el movimiento de caja aplicable.
10. El sistema muestra el número de venta y estado `confirmed`.

### Reglas y excepciones

- Cada línea conserva variante, cantidad, precio usado, precio mínimo vigente,
  total y la autorización relacionada si existe.
- El empleado puede vender entre el precio sugerido y el mínimo. Si el precio
  es menor al mínimo, se bloquea la confirmación hasta tener una autorización
  válida del dueño; debe conservar dueño, empleado, importe, motivo, fecha y
  operación.
- Una venta a crédito requiere autorización del dueño e identificación del
  cliente. El crédito no se suma al efectivo de caja.
- Si el stock cambió antes de confirmar, el servidor rechaza o marca conflicto
  sin crear una venta parcial ni ocultar la situación.
- Si se pierde conexión antes de recibir respuesta, la aplicación guarda una
  sola operación `pending_sync` con su identificador. Al reintentar, no crea
  otra venta.
- Si el usuario cancela antes de confirmar, no se modifica inventario ni caja.

### Resultado

La venta confirmada deja una trazabilidad inmutable y afecta inventario y caja
una sola vez. Si no pudo confirmarse, el estado visible indica qué debe hacer
el usuario.

## CU-03: Consultar y buscar inventario

**Actor principal:** empleado o dueño.  
**Objetivo:** localizar rápidamente una variante y conocer su existencia y
estado operativo.

### Precondiciones

- El usuario inició sesión, tiene negocio activo y permiso de lectura de
  inventario.

### Flujo principal

1. El usuario abre Inventario.
2. El sistema muestra un listado paginado de variantes disponibles y sus
   existencias, limitado al negocio activo.
3. El usuario busca o combina filtros de categoría, marca, talla, color,
   disponibilidad y estado de stock.
4. El usuario selecciona una variante para consultar sus datos operativos.
5. El sistema muestra producto, atributos, código interno, existencia por
   estado, precio permitido para el usuario y alertas de stock.
6. Desde una variante, el usuario puede iniciar una venta o, si tiene permiso,
   consultar su historial de movimientos.

### Reglas y excepciones

- La existencia se deriva de movimientos trazables; no se edita directamente
  desde este listado.
- El empleado no recibe datos de costos, márgenes ni información financiera no
  autorizada.
- El filtro de stock bajo se basa en la configuración aprobada para la
  variante o producto. La decisión de cuál nivel prevalece sigue pendiente y
  no se codificará hasta definirla.
- Si se consultan datos cacheados sin conexión, el sistema muestra cuándo se
  actualizaron y evita permitir acciones que requieran datos actuales sin
  indicar el riesgo.

### Resultado

El usuario encuentra una variante dentro de su negocio y conoce su existencia
sin alterar el inventario.

## CU-04: Registrar una nueva compra

**Actor principal:** empleado o dueño autorizado.  
**Objetivo:** registrar una compra con sus lotes y reflejar inventario y deuda
de forma consistente al confirmarse.

### Precondiciones

- El usuario inició sesión, tiene negocio activo y permiso para registrar
  compras.
- Existe o se puede crear un distribuidor dentro del negocio activo.

### Flujo principal

1. El usuario abre Nueva compra y selecciona o crea un distribuidor.
2. Agrega líneas seleccionando un producto y una variante existentes o creando
   los datos mínimos de un producto y variante nuevos según su permiso.
3. Para cada línea indica cantidad entera positiva y costo unitario exacto.
4. Indica tipo de compra: contado, crédito o parcial; si aplica, registra pago
   inicial y referencia/factura opcionales.
5. El sistema calcula total, pago inicial y saldo pendiente.
6. El sistema compara cada costo con el último costo conocido y advierte si es
   mayor; no modifica precios automáticamente.
7. El usuario revisa el resumen y confirma la compra con una operación
   idempotente.
8. Al confirmarse, el sistema crea compra y líneas históricas, un lote por
   línea, movimientos de inventario y, si hay saldo, el movimiento de cuenta
   por pagar correspondiente.
9. El sistema marca como pendiente la revisión de precio cuando corresponde y
   muestra número y estado de la compra.

### Reglas y excepciones

- El costo pertenece al lote de esta compra; una compra posterior a otro costo
  no crea una variante duplicada ni cambia los precios vigentes.
- El empleado puede registrar la compra y dejar una revisión de precio
  pendiente, pero no cambia precios mínimos sin permiso.
- Para contado, el pago inicial debe cubrir el total. Para crédito debe ser
  cero; para parcial debe ser mayor que cero y menor que el total.
- Si el usuario pierde conexión, la compra queda como `pending_sync`; no se
  debe asumir que inventario o saldo ya cambiaron hasta confirmar.
- Una compra confirmada no puede borrarse desde la interfaz. El flujo de
  cancelación o ajuste está pendiente de diseño.

### Resultado

La compra confirmada deja lotes, movimientos y saldo auditables. Si no se
confirma, el usuario conoce el estado exacto y puede sincronizarla sin
duplicarla.

## Criterios de aceptación transversales

- Los cuatro casos se prueban al menos en un ancho móvil y uno de escritorio.
- Cada consulta y mutación valida negocio, identidad y permiso en el backend,
  además de controlar la experiencia en la interfaz.
- Ninguna pantalla usa números de punto flotante para dinero ni permite
  cantidades fraccionarias de inventario en el MVP.
- Los mensajes de error explican la causa y la acción siguiente, sin exponer
  información sensible ni datos de otros negocios.
