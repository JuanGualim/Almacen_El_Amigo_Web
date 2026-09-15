# ADR 001: Base técnica y entorno local

- Estado: aceptada
- Fecha: 2026-09-15

## Contexto

El MVP necesita una PWA React con autenticación, PostgreSQL, archivos y una
separación estricta por negocio. Las políticas RLS, las migraciones y las
operaciones atómicas deben poder probarse sin depender de infraestructura
remota ni datos reales.

## Decisión

- El frontend será React con TypeScript y Vite.
- La PWA precacheará únicamente sus recursos públicos de aplicación; no se
  configurará caché en tiempo de ejecución para respuestas autenticadas.
- Supabase será el proveedor inicial de PostgreSQL, Auth y Storage.
- La ejecución local de Supabase se hará con Supabase CLI y un runtime Docker
  compatible. No se mantendrá un `docker-compose.yml` propio para duplicar el
  stack que administra la CLI.
- El frontend seguirá ejecutándose nativamente con Vite para mantener una
  recarga de desarrollo sencilla.
- En producción se contempla alojamiento estático para el frontend y Supabase
  administrado. Docker local no implica autoalojar Supabase ni exponer el stack
  local a la red.

## Alternativas consideradas

- **Sin Docker, usando solo un proyecto remoto:** reduce consumo local, pero
  dificulta probar migraciones, RLS e integración sin afectar un entorno
  compartido.
- **Docker Compose propio para frontend y backend:** añade duplicación y
  mantenimiento sobre el stack oficial de Supabase sin aportar una necesidad
  actual.
- **Backend personalizado desde el inicio:** aumenta costo y superficie de
  seguridad antes de validar el MVP.

## Consecuencias

- Cada persona que desarrolle el proyecto necesitará Node.js, Docker y el
  comando de Supabase disponible mediante `npm run supabase`.
- Las migraciones, configuración segura y datos ficticios del entorno local se
  versionarán; secretos, archivos temporales y credenciales no.
- Las pruebas de RLS y acceso cruzado se ejecutarán contra la instancia local
  cuando el stack Docker esté disponible.
- El uso de RAM del stack local debe verificarse antes de ejecutarlo en equipos
  con recursos limitados.
