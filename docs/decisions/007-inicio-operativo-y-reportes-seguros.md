# 007. Inicio operativo y reportes seguros

## Contexto

La fase 7 necesita mostrar pendientes y reportes sin convertir la interfaz en
la barrera de seguridad. Los saldos de distribuidores y los totales de ventas
son información sensible: el empleado no debe recibirlos solo porque la
pantalla intente ocultarlos.

## Decisión

Se agregan dos funciones `security definer` incrementales en Supabase:

- `get_operational_dashboard(business_id)` valida membresía activa y devuelve
  únicamente los pendientes autorizados. El resumen de ventas del día y el
  saldo con distribuidores solo se incluye para `reports.read_sensitive`.
- `get_operational_report(business_id, start_date, end_date)` exige ese mismo
  permiso, calcula fechas mediante la zona horaria del negocio y limita el
  periodo a 367 días para evitar consultas sin límite.

La interfaz muestra la conectividad y las actualizaciones de la PWA, pero no
encola operaciones todavía. No se habilitan exportaciones ni respaldos hasta
que se acuerden formato, frecuencia y un entorno de restauración verificable.

## Consecuencias

- El aislamiento y los permisos se aplican antes de que el navegador reciba
  datos sensibles.
- Los reportes del periodo incluyen ventas, medios de pago, variantes más
  vendidas, compras por distribuidor, diferencia de caja y saldo actual.
- Las alertas de stock bajo, la cola offline y los respaldos siguen pendientes
  de decisiones funcionales explícitas; no se simula su disponibilidad.
