# ADR 002: Invitaciones de empleados por correo

- Estado: aceptada
- Fecha: 2026-09-15

## Contexto

Cada persona debe usar una cuenta individual y el dueño administra quién puede
acceder a cada negocio. El navegador no puede conservar una clave administrativa
de Supabase ni decidir por sí solo la pertenencia a un negocio.

## Decisión

- El dueño invita empleados desde la aplicación usando correo electrónico.
- La Edge Function `invite-business-member` valida la sesión del dueño y usa
  su clave de servicio solo en el servidor para crear la identidad de Auth y
  asociarla a una membresía de empleado pendiente.
- La base de datos vuelve a validar el permiso `memberships.manage` para el
  usuario que ejecutó la acción, registra una auditoría y no permite que el
  cliente cree membresías directamente.
- El empleado debe aceptar su propia invitación; solo entonces la membresía se
  vuelve activa y puede consultar el negocio.
- Si el correo ya corresponde a una cuenta, se reutiliza esa cuenta y queda una
  invitación pendiente para aceptar en su siguiente inicio de sesión.

## Consecuencias

- Las cuentas y permisos no dependen de credenciales compartidas.
- El correo de invitación se prueba localmente en Mailpit; la configuración de
  SMTP real se hará únicamente antes del despliegue autorizado.
- La operación depende de una función Edge y de una URL de redirección
  permitida. La función usa un identificador por solicitud para que reintentos
  posteriores no creen otra membresía.
- La personalización de roles y excepciones de permisos permanece respaldada
  por el modelo de datos existente y se expondrá mediante una pantalla dedicada
  cuando se acuerde ese flujo.
