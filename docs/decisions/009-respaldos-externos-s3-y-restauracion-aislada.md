# 009. Respaldos externos S3 y restauración aislada

## Contexto

Los respaldos internos y el manifiesto de Supabase no protegen los binarios de
adjuntos ante una pérdida del almacenamiento operativo. La fase 7 exige una
copia independiente, privada y verificable sin acoplar el sistema a un único
proveedor.

## Decisión

Cloudflare R2 Standard será el primer destino, mediante una interfaz S3
compatible implementada en la Edge Function `external-backup`. Las
credenciales son secretos exclusivamente de servidor y se limitan al bucket.
Cada conjunto contiene datos lógicos, exportación estructurada, adjuntos y
manifiesto. El servidor verifica cada objeto por existencia, tamaño y SHA-256
antes de marcar el conjunto como válido.

La retención solo procesa conjuntos externos completos y válidos: conserva 30
diarios y 12 mensuales por negocio. La restauración se ejecuta desde un script
administrativo que acepta únicamente destinos loopback aislados y exige una
confirmación explícita. Reconstruye datos y adjuntos, y valida totales de
ventas, pagos, compras y lotes.

## Consecuencias

- Cambiar de R2 a otro proveedor S3 compatible requiere configuración, no una
  modificación de las reglas de negocio.
- Un fallo de carga o eliminación se audita como conjunto fallido y jamás
  elimina otro respaldo.
- La fase no se considera operativamente cerrada hasta documentar un ensayo
  real con un bucket de prueba y una instancia local aislada.
