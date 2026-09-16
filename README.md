# Almacén El Amigo

PWA para la operación de una tienda guatemalteca de ropa y accesorios para
hombre. El proyecto busca centralizar catálogo, inventario, ventas, caja,
compras, distribuidores y cuentas, manteniendo trazabilidad y separación
estricta entre negocios.



## Estado actual

Está disponible la base técnica de la aplicación:

- Frontend React con TypeScript y Vite.
- Manifest y service worker PWA que solo precachea recursos públicos de la
  aplicación; no almacena respuestas privadas en caché.
- Inicio de sesión mediante Supabase Auth.
- Creación y selección de negocios autorizados.
- Invitación de empleados por correo, con aceptación explícita del acceso.
- Catálogo de categorías, marcas, productos, variantes y atributos flexibles.
- Precios sugeridos y mínimos con historial inmutable y permisos de consulta.
- Distribuidores activos, compras de contado, crédito o pago parcial, y sus
  lotes con costo histórico.
- Movimientos de inventario derivados exclusivamente de compras confirmadas,
  con existencias disponibles calculadas a partir de esos movimientos.
- Cargos iniciales de cuentas por pagar y revisiones auditables cuando un costo
  aumenta, sin cambiar precios de venta automáticamente.
- Apertura y cierre de la única caja de ventas, con fondo inicial, efectivo
  esperado, efectivo contado y diferencia trazable.
- Ventas confirmadas atómicamente con líneas y precios históricos, pagos por
  efectivo, QR, transferencia o tarjeta, y reducción de inventario una sola
  vez.
- Modelo inicial de perfiles, roles, permisos, membresías y auditoría.
- Políticas RLS que aíslan la información por negocio.
- Pruebas unitarias de dinero y permisos, más una prueba de integración para
  acceso cruzado entre negocios.

Los módulos de abonos, ajustes, cambios, salidas y mercadería defectuosa se
desarrollarán en las fases siguientes. Las existencias no se editan
directamente: compras y ventas confirmadas son las únicas operaciones de esta
etapa que las modifican; los prototipos visuales no implican funcionalidades
implementadas.

## Tecnologías

- React, TypeScript y Vite.
- PWA con `vite-plugin-pwa`.
- Supabase local: PostgreSQL, Auth, Storage y políticas RLS.
- Docker para ejecutar el stack local de Supabase.
- Vitest para pruebas unitarias y pgTAP mediante Supabase para pruebas de base
  de datos.

## Requisitos

- Node.js 22 o superior.
- npm.
- Docker y Docker Compose instalados, con el daemon iniciado.

Comprueba los dos últimos requisitos con:

```bash
node --version
npm --version
docker info
```

## Ejecutar el proyecto localmente

### 1. Instalar dependencias

```bash
npm ci
```

`node_modules` no se sube al repositorio. Se reconstruye siempre desde
`package-lock.json` con este comando.

### 2. Iniciar Supabase con Docker

```bash
npm run supabase -- start
```

La primera ejecución descarga imágenes de Docker y puede tardar varios
minutos. El comando imprime las URLs y las credenciales locales necesarias para
el siguiente paso. No copies esas credenciales a documentación, chats,
capturas ni archivos versionados.

### 3. Configurar el frontend local

Copia el archivo de ejemplo:

```bash
cp .env.example .env.local
```

En `.env.local`, conserva la URL local y reemplaza
`VITE_SUPABASE_ANON_KEY` con la `ANON_KEY` que mostró el comando de Supabase.
El archivo `.env.local` está ignorado por Git.

### 4. Crear una cuenta local de prueba

Abre Supabase Studio en `http://127.0.0.1:54323`, ve a **Authentication →
Users** y crea una cuenta con correo y contraseña ficticios. No uses datos
reales del negocio.

Al iniciar sesión con esa cuenta en la PWA podrás crear el primer negocio. La
operación crea atómicamente el negocio, los roles iniciales y la membresía de
dueño.

### 5. Ejecutar la PWA

En otra terminal:

```bash
npm run dev
```

Abre `http://127.0.0.1:3000` en el navegador.

### 6. Probar invitaciones de empleados

Con Supabase local y la PWA ejecutándose, inicia la Edge Function en una
tercera terminal:

```bash
npm run supabase -- functions serve invite-business-member
```

Inicia sesión como dueño, selecciona el negocio y usa la sección **Equipo**
para invitar un correo ficticio. En local, Supabase no envía correos reales:
el mensaje se puede revisar en Mailpit, en `http://127.0.0.1:54324`.

La persona invitada activa su cuenta desde el enlace y, al entrar a la PWA,
acepta explícitamente la invitación antes de ver el negocio. Si ese correo ya
corresponde a una cuenta, no se intenta crear una segunda: la persona verá la
invitación pendiente al iniciar sesión.

Para un despliegue real se debe configurar un proveedor SMTP, registrar la URL
exacta de producción para `/auth/accept-invitation` en Supabase Auth y definir
`APP_URL` como secreto de la Edge Function. Nunca se debe configurar ni exponer
la clave `SUPABASE_SERVICE_ROLE_KEY` en el frontend.

Para detener únicamente el stack local al terminar:

```bash
npm run supabase -- stop
```

## Verificaciones

Ejecuta estas comprobaciones antes de preparar cambios para revisión:

```bash
npm run typecheck
npm run lint
npm test
npm run build
npm run supabase -- test db
```

La prueba de base de datos crea usuarios y negocios ficticios dentro de una
transacción y verifica que un usuario no puede consultar el negocio,
membresías ni permisos de otro.

Para comprobar que las migraciones funcionan desde una base limpia:

```bash
npm run supabase -- db reset --local
```

Este último comando **borra y recrea solo la base local**. Nunca debe usarse
contra un proyecto remoto con datos reales.

## Estructura relevante

```text
src/
  app/                 Arranque de la aplicación
  domain/              Reglas puras: dinero y permisos
  features/            Funcionalidades de autenticación y negocios
  services/            Integración con Supabase y autenticación
  styles/              Tokens y estilos globales
supabase/
  migrations/          Esquema PostgreSQL versionado
  tests/               Pruebas de políticas y base de datos
docs/
  decisions/           Decisiones arquitectónicas
  flows/               Casos de uso
  wireframes/          Wireframes funcionales
Diseños/               Prototipos visuales de referencia
```

## Seguridad y datos

- Cada tabla operativa futura debe pertenecer a un negocio y protegerse con
  RLS o un mecanismo equivalente en el backend.
- No se debe confiar solo en filtros del frontend para separar información.
- El dinero se representa como unidades menores enteras en TypeScript y como
  `numeric/decimal` en PostgreSQL cuando corresponda.
- No se suben secretos, archivos `.env`, datos reales, comprobantes ni
  dependencias instaladas.
- Las operaciones financieras y de inventario deberán implementarse como
  transacciones atómicas e idempotentes en el servidor.

## Archivos que no se suben

`.gitignore` excluye, entre otros:

- `node_modules/`
- `dist/`
- `.env` y variantes locales
- cobertura y reportes de pruebas
- logs y archivos temporales del sistema

Sí deben versionarse el código fuente, `package.json`, `package-lock.json`,
migraciones, pruebas, documentación y prototipos que el equipo decida
conservar como referencia.
