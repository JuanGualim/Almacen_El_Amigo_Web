# 008. Alertas, ventas offline y continuidad

## Decisión

- Stock bajo se configura por variante: por defecto dos unidades, activo. Una
  variante con cero disponible está agotada; entre una unidad y el límite está
  baja. Solo se calcula el estado `available`, por lo que defectuosos y
  entregados al distribuidor no cuentan.
- Fuera de línea se consultan instantáneas locales y se guardan borradores.
  Solo ventas ordinarias con precio igual o superior al mínimo conocido entran
  en cola. Nunca se presentan como confirmadas. El servidor vuelve a validar
  caja, permisos, existencia y precios al sincronizar; un rechazo queda como
  conflicto auditable para el dueño.
- Los reportes se descargan en CSV. La exportación estructurada y los
  respaldos manuales usan JSON versionado con checksum SHA-256 y manifiesto de
  adjuntos. El cron local crea instantáneas diarias privadas, conserva treinta
  y retiene además una instantánea mensual durante doce meses.

## Consecuencia pendiente

La instantánea registra el manifiesto de archivos, pero aún no duplica el
binario de cada adjunto a un almacenamiento de respaldo independiente. Una
restauración completa debe ensayarse en una base aislada antes de usar el
sistema como fuente oficial.
