# Respaldo externo y restauración aislada

La copia externa usa una interfaz S3 compatible. La implementación inicial se
configura para Cloudflare R2 Standard, pero el código solo conoce
`BACKUP_S3_ENDPOINT`, bucket y credenciales S3; cambiar de proveedor no exige
cambiar la lógica de respaldo.

## Crear el bucket de prueba en Cloudflare R2

1. En Cloudflare R2 crea un bucket nuevo, por ejemplo
   `almacen-el-amigo-backups-test`. No lo hagas público ni configures una URL
   pública.
2. Crea un token de API de R2 con permisos **Object Read & Write**, limitado
   exclusivamente a ese bucket. No uses una clave global de la cuenta.
3. Conserva localmente el endpoint S3 de tu cuenta, el Access Key ID y el
   Secret Access Key. No los copies al repositorio, documentación, capturas o
   conversaciones.
4. Copia `supabase/backup.env.example` a un archivo local ignorado por Git,
   completa sus valores y genera un `BACKUP_JOB_TOKEN` aleatorio de al menos
   32 bytes. No uses el mismo token para otros servicios.

Para desarrollo local, carga esas variables como secretos de la Edge Function
con el mecanismo de Supabase que uses en tu entorno. Para producción, registra
las mismas variables como secretos del proyecto/función; nunca como variables
del frontend y nunca con el prefijo `VITE_`.

El endpoint típico de R2 es
`https://<ACCOUNT_ID>.r2.cloudflarestorage.com` y la región es `auto`.
El bucket no forma parte del endpoint: se configura en `BACKUP_S3_BUCKET`.

## Ejecución y retención

Despliega o sirve la Edge Function `external-backup`. Las solicitudes desde la
PWA llevan la sesión del dueño; las automáticas usan exclusivamente el header
`x-backup-job-token` con `BACKUP_JOB_TOKEN` y no aceptan una identidad del
navegador.

El botón de la aplicación crea un trabajo y responde de inmediato con `202` y
su identificador. La interfaz consulta el estado y procesa un lote por
invocación. El trabajo conserva `pending`, `exporting`, `copying_attachments`,
`verifying`, `finalizing`, `completed` o `failed`; muestra progreso numérico y
un error sanitizado. Un trabajo `failed` puede reanudarse y continúa desde el
último archivo verificado, sin crear otra ruta de objeto.

Programa un proceso de servidor confiable para crear la copia diaria:

```bash
BACKUP_FUNCTION_URL=https://TU_PROYECTO.supabase.co/functions/v1/external-backup \
BACKUP_JOB_TOKEN=valor_local_secreto \
BACKUP_JOB_ACTION=start_automatic \
BACKUP_JOB_KIND=automatic_daily \
node scripts/backup/trigger-external-backup.mjs
```

El día uno de cada mes programa una segunda ejecución con
`BACKUP_JOB_KIND=automatic_monthly`. Además, programa cada minuto (o con una
frecuencia que deje cada ejecución muy por debajo de 150 segundos) el avance
de un solo lote:

```bash
BACKUP_FUNCTION_URL=https://TU_PROYECTO.supabase.co/functions/v1/external-backup \
BACKUP_JOB_TOKEN=valor_local_secreto \
BACKUP_JOB_ACTION=process_pending \
node scripts/backup/trigger-external-backup.mjs
```

Una vez al día ejecuta la limpieza segura con `BACKUP_JOB_ACTION=cleanup`.
El script no recibe credenciales de R2; estas solo viven en la Edge Function.
El programador puede ser el scheduler privado de tu infraestructura. No pongas
el token en una URL, un repositorio o un navegador.

Cada conjunto usa un prefijo único y contiene `backup-data.json`,
`structured-export.json`, cada adjunto y `manifest.json`. El manifiesto guarda
ruta, tamaño, MIME, negocio, registro relacionado cuando existe y SHA-256.
Después de cada subida, el servidor hace `HEAD` para comprobar existencia y
descarga el objeto para comprobar su tamaño y recalcular su SHA-256 antes de
marcar el conjunto como `valid`. Los metadatos y longitudes de `HEAD` se
conservan solo para diagnóstico porque un proveedor compatible puede
transformarlos; la comprobación criptográfica sobre los bytes descargados es
obligatoria. La verificación final procesa un archivo por invocación.
La tabla del trabajo registra, sin contenido ni secretos, los milisegundos de
generación de datos y JSON, descarga de adjuntos, subida/verificación, revisión
final y manifiesto; también conserva el número de intentos. Esto permite
identificar el cuello de botella real.

La retención conserva las 30 copias diarias y 12 mensuales más recientes por
negocio. Solo se eliminan conjuntos completos con estado `valid`, después de
comprobar que hay otro conjunto válido más reciente. Si una subida o una
eliminación queda incompleta, se registra como fallida y no provoca la
eliminación de ningún otro conjunto.

Los conjuntos interrumpidos permanecen en estado incompleto siete días para
diagnóstico y quedan excluidos de restauración y retención. La limpieza elimina
sus objetos por lotes. La retención también elimina por lotes un único conjunto
vencido, lo pone temporalmente fuera de restauración y solo lo marca eliminado
cuando todos sus objetos y el manifiesto desaparecieron.

## Ensayo de restauración aislada

Nunca ejecutes el restaurador contra una URL de producción. El script rechaza
hosts distintos de `localhost`, `127.0.0.1` o `::1`, y exige la confirmación
literal `RESTORE_ISOLATED_CONFIRMATION=LOCAL_ISOLATED_SUPABASE`.

1. Crea una instancia local **nueva y aislada** de Supabase con las mismas
   migraciones del repositorio. Debe tener otro directorio/volúmenes que la
   instancia de desarrollo normal y no contener el negocio a restaurar.
2. Instala el cliente `psql` local. Obtén la URL PostgreSQL y la URL API de
   esa instancia aislada desde su propio `supabase status`; no uses valores de
   producción.
3. Identifica la clave `manifest.json` del conjunto válido que deseas ensayar.
   La tabla privada `external_backup_sets` conserva el prefijo y manifiesto
   para el dueño. Copia solamente la ruta, no las credenciales.
4. En una terminal administrativa local, exporta las variables S3 desde tu
   archivo secreto y define además `BACKUP_MANIFEST_KEY`,
   `BACKUP_MANIFEST_SHA256`,
   `RESTORE_SUPABASE_DB_URL`, `RESTORE_SUPABASE_URL`,
   `RESTORE_SUPABASE_SERVICE_ROLE_KEY` y
   `RESTORE_ISOLATED_CONFIRMATION=LOCAL_ISOLATED_SUPABASE`.
5. Ejecuta `node scripts/backup/restore-external-backup.mjs`.

El restaurador valida primero la estructura del manifiesto, sus rutas, negocio,
MIME y checksums; luego descarga y verifica todos los objetos antes de escribir
datos. Recrea los datos y adjuntos en la instancia aislada, compara las
cantidades de tablas y valida totales de ventas, pagos, compras y cantidades de
lote. Genera un informe JSON local tanto de éxito como de fallo. Usa únicamente
datos ficticios para el ensayo. Si falla, conserva el informe, destruye la
instancia aislada y corrige la causa antes de repetirlo; nunca reutilices esa
instancia como producción.
