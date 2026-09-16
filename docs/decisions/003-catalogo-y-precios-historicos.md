# ADR 003: Catálogo flexible y precios históricos

- Estado: aceptada
- Fecha: 2026-09-15

## Contexto

El negocio comercializa artículos con combinaciones variables de talla, color,
diseño, marca y otras características. Un producto comercial y una variante
vendible no son lo mismo: una misma camisa puede tener varias tallas o colores,
y compras posteriores a otro costo no deben crear una variante nueva.

## Decisión

- Las categorías, marcas, productos y variantes pertenecen a un negocio y se
  protegen con RLS.
- Los atributos de variante se guardan como pares flexibles de texto en JSON,
  con validación de nombres, valores y combinaciones duplicadas por producto.
- Cada producto recibe un código interno `ALM-######`; sus variantes reciben
  una secuencia derivada, por ejemplo `ALM-000184-003`.
- El precio vigente se separa del historial. Los cambios solo se realizan por
  una función autorizada que registra precio anterior, nuevo valor, usuario,
  fecha y motivo.
- Esta fase no crea existencias ni movimientos. Lotes, costos y cantidades se
  incorporarán con compras e inventario trazable en la fase siguiente.

## Consecuencias

- Los precios se almacenan como `numeric(14,2)` en PostgreSQL y se envían desde
  TypeScript como texto decimal derivado de unidades menores exactas.
- Un empleado puede consultar los precios permitidos, pero no modificarlos sin
  el permiso correspondiente.
- El modelo permite extender atributos sin alterar el esquema, conservando una
  restricción que impide variantes idénticas dentro del mismo producto.
