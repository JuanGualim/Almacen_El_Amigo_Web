# Wireframes de pantallas prioritarias

> Wireframes funcionales, mobile-first y sin identidad visual definitiva. Los
> datos son ficticios. Las acciones de negocio permanecen sujetas a permisos y
> validaciones del servidor.

## Patrones compartidos

- Barra superior: negocio activo, estado de conexión/sincronización y menú de
  cuenta. Cambiar de negocio solo aparece para usuarios autorizados.
- Navegación inferior móvil: Inicio, Vender, Inventario, Operaciones y Más.
- Los importes se muestran con `Q` y dos decimales. Los datos internos usan una
  representación monetaria exacta.
- Los estados nunca dependen solo del color: cada uno incluye icono y texto.
- Acciones sensibles muestran un resumen antes de confirmar. Un botón
  deshabilitado indica el motivo y la forma de resolverlo.

## 1. Inicio

### Móvil

```text
┌─────────────────────────────────┐
│ Almacén El Amigo         ◉ En línea│
│ Lunes, 14 de septiembre           │
├─────────────────────────────────┤
│ Buenos días, Ana                  │
│ Caja de ventas: Abierta           │
│                                  │
│ ┌───────────┐ ┌────────────────┐ │
│ │ Ventas hoy│ │ Efectivo esp.  │ │
│ │ Q 1,250.00│ │ Q   730.00     │ │
│ └───────────┘ └────────────────┘ │
│                                  │
│ [ + Nueva venta ]                 │
│ [ + Nueva compra ]                │
│                                  │
│ Pendientes                         │
│ ⚠ 3 variantes con stock bajo  ›   │
│ ◷ 1 operación por sincronizar ›   │
│                                  │
│ Alertas                            │
│ □ Precio por revisar: Camisa... › │
├─────────────────────────────────┤
│ Inicio  Vender  Invent.  Oper. Más│
└─────────────────────────────────┘
```

### Comportamiento

- Las tarjetas y alertas se adaptan al permiso: el empleado no recibe deuda,
  costos o ganancias; el dueño puede ver sus pendientes financieros.
- El indicador de conexión abre el detalle de operaciones pendientes o en
  conflicto cuando existe alguno.
- Sin caja abierta, el acceso principal guía a la apertura o deja claro si el
  permiso no la permite. No habilita implícitamente una venta confirmable.
- En escritorio, las tarjetas pasan a una cuadrícula de dos a cuatro columnas;
  alertas y accesos rápidos quedan en columnas separadas.

## 2. Nueva venta

### Móvil: búsqueda y carrito

```text
┌─────────────────────────────────┐
│ ‹ Nueva venta              Carrito│
│ [ Buscar producto o código     ] │
│ [Categoría⌄] [Talla⌄] [Disponible⌄]│
├─────────────────────────────────┤
│ Camisa Manhattan lisa            │
│ Blanca · Talla 15 · 2 disponibles│
│ Sugerido Q185.00 · Mín. Q160.00  │
│                           [Agregar]│
├─────────────────────────────────┤
│ Pantalón Wrangler                │
│ Azul · Talla 36 · 1 disponible   │
│ Sugerido Q200.00 · Mín. Q175.00  │
│                           [Agregar]│
├─────────────────────────────────┤
│ 2 artículos · Q385.00            │
│                  [Ver carrito ›] │
└─────────────────────────────────┘
```

### Móvil: revisión y pago

```text
┌─────────────────────────────────┐
│ ‹ Revisar venta                  │
├─────────────────────────────────┤
│ Camisa Manhattan · Blanca · 15   │
│ [ − ] 1 [ + ]  Precio [Q 185.00] │
│ Mínimo permitido: Q160.00        │
│                                  │
│ Pantalón Wrangler · Azul · 36    │
│ [ − ] 1 [ + ]  Precio [Q 200.00] │
│ Mínimo permitido: Q175.00        │
├─────────────────────────────────┤
│ Forma de pago                    │
│ [ Efectivo ✓ ] [ QR ]             │
│ [ Transferencia ] [ Tarjeta ]     │
│                                  │
│ Total                       Q385.00│
│ [ Confirmar venta ]              │
└─────────────────────────────────┘
```

### Validaciones y estados

- Al ingresar un precio menor al mínimo, la línea muestra texto de bloqueo y
  el botón pasa a `Solicitar autorización`; no permite confirmar sin una
  autorización segura, motivo y vínculo con la venta.
- Una venta a crédito muestra el campo obligatorio de cliente y la autorización
  del dueño antes de habilitar la confirmación.
- Antes de la respuesta del servidor, el botón evita doble envío. Luego se
  presenta `Confirmada`, `Pendiente de sincronizar` o `En conflicto` con una
  explicación accionable.
- En escritorio, la búsqueda ocupa la columna izquierda y el carrito fijo la
  derecha; el resumen y las mismas validaciones no desaparecen.

## 3. Inventario

### Móvil

```text
┌─────────────────────────────────┐
│ Inventario                       │
│ [ Buscar nombre, talla o código ]│
│ [Filtros] [Stock bajo] [Ordenar⌄]│
├─────────────────────────────────┤
│ Camisa Manhattan lisa            │
│ Blanca · Talla 15                │
│ Disponible: 2  ·  Stock bajo      │
│ Precio: Q185.00             [›]  │
├─────────────────────────────────┤
│ Pantalón Wrangler                │
│ Azul · Talla 36                  │
│ Disponible: 1                    │
│ Precio: Q200.00             [›]  │
├─────────────────────────────────┤
│ Cinturón cuero                   │
│ Negro · Talla única              │
│ Agotado                     [›]  │
└─────────────────────────────────┘
```

### Detalle de variante

```text
┌─────────────────────────────────┐
│ ‹ Camisa Manhattan lisa           │
│ ALM-000184-003                   │
│ Blanca · Talla 15                │
├─────────────────────────────────┤
│ Disponible                 2     │
│ Apartado por defecto        0     │
│ Entregado a distribuidor    0     │
│ Precio sugerido      Q185.00     │
│ Precio mínimo        Q160.00     │
│                                  │
│ [ Vender esta variante ]          │
│ [ Ver movimientos ]               │
└─────────────────────────────────┘
```

### Comportamiento

- Los filtros son combinables y muestran cuántos están activos; se pueden
  limpiar en una sola acción.
- Las existencias son solo de lectura en esta pantalla. Un ajuste se inicia
  desde su flujo autorizado, nunca editando una cifra en línea.
- Costos y márgenes no se cargan ni se representan para un empleado sin el
  permiso correspondiente.
- En escritorio, filtros quedan como panel lateral y la lista como tabla o
  tarjetas, sin perder los atributos relevantes de una variante.

## 4. Nueva compra

### Móvil: líneas de compra

```text
┌─────────────────────────────────┐
│ ‹ Nueva compra                   │
│ Distribuidor [ Seleccionar    › ]│
│ Factura (opcional) [           ] │
├─────────────────────────────────┤
│ Líneas                           │
│ Camisa Manhattan · Blanca · 15   │
│ Cantidad [  6 ]  Costo [Q 92.50] │
│ Último costo: Q88.00  ⚠ Mayor    │
│                                  │
│ [ + Agregar producto o variante ]│
│ [ + Crear producto ]              │
├─────────────────────────────────┤
│ 6 unidades · Total         Q555.00│
│ [ Continuar ]                    │
└─────────────────────────────────┘
```

### Móvil: pago y confirmación

```text
┌─────────────────────────────────┐
│ ‹ Pago y confirmación             │
│ Tipo de compra                    │
│ [ Contado ] [ Crédito ✓ ] [ Parcial ]│
│                                  │
│ Pago inicial                 Q0.00│
│ Saldo pendiente             Q555.00│
│ Vencimiento (opcional) [      ]  │
│ Adjuntar factura (opcional)      │
│ [ Seleccionar archivo ]           │
├─────────────────────────────────┤
│ Revisión requerida                │
│ ⚠ El costo aumentó; los precios no│
│   cambiarán automáticamente.      │
│                                  │
│ [ Confirmar compra ]              │
└─────────────────────────────────┘
```

### Validaciones y estados

- Cantidad debe ser un entero positivo y costo debe ser un importe monetario
  válido. La pantalla calcula total y saldo sin flotantes.
- Contado exige pago inicial igual al total; crédito exige cero; parcial exige
  un importe mayor a cero y menor al total.
- Crear producto conserva el contexto de la compra y requiere solo los campos
  indispensables; atributos no aplicables no se fuerzan.
- El aviso de costo mayor informa y crea una revisión pendiente cuando proceda,
  pero no actualiza precios sugeridos ni mínimos.
- La confirmación muestra claramente si se confirmó en servidor o si quedó
  pendiente de sincronización. No afirma que el inventario o la deuda cambió
  hasta obtener confirmación.
- En escritorio, líneas y resumen de pago se ven simultáneamente en dos
  columnas, manteniendo una confirmación final única.

## Límites de este diseño

- No se define aún el mecanismo del PIN de autorización ni su vigencia.
- No se resuelve en estos wireframes el valor de un cambio sin venta original,
  la asignación de abonos generales, ni la política de cancelación. Son
  decisiones pendientes de la planificación y requieren definición antes de
  diseñar sus flujos.
- Los wireframes describen comportamiento y jerarquía de información; colores,
  tipografía, iconografía e identidad visual se decidirán al crear el sistema
  de interfaz.
