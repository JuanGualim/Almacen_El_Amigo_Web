import { spawn } from 'node:child_process'
import { mkdir, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { createS3CompatibleStorage, sha256Hex } from '../../supabase/functions/_shared/s3-compatible.mjs'

const required = ['BACKUP_S3_ENDPOINT', 'BACKUP_S3_BUCKET', 'BACKUP_S3_ACCESS_KEY_ID', 'BACKUP_S3_SECRET_ACCESS_KEY', 'BACKUP_MANIFEST_KEY', 'RESTORE_SUPABASE_DB_URL', 'RESTORE_SUPABASE_URL', 'RESTORE_SUPABASE_SERVICE_ROLE_KEY']

function requireEnvironment(name) {
  const value = process.env[name]
  if (!value) throw new Error(`Falta la variable requerida ${name}.`)
  return value
}

function assertLocalIsolatedDestination() {
  if (process.env.RESTORE_ISOLATED_CONFIRMATION !== 'LOCAL_ISOLATED_SUPABASE') {
    throw new Error('Confirma explícitamente RESTORE_ISOLATED_CONFIRMATION=LOCAL_ISOLATED_SUPABASE.')
  }
  for (const name of ['RESTORE_SUPABASE_DB_URL', 'RESTORE_SUPABASE_URL']) {
    const url = new URL(requireEnvironment(name))
    if (!['127.0.0.1', 'localhost', '::1'].includes(url.hostname)) {
      throw new Error('La restauración solo acepta una instancia local aislada de Supabase.')
    }
  }
}

async function readVerifiedObject(storage, key, expectedChecksum, expectedSize) {
  const head = await storage.headObject(key)
  if (!head || head.sha256 !== expectedChecksum || (expectedSize !== undefined && head.contentLength !== expectedSize)) {
    throw new Error('Un objeto del manifiesto no coincide con sus metadatos remotos.')
  }
  const body = new Uint8Array(await (await storage.getObject(key)).arrayBuffer())
  if (body.byteLength !== head.contentLength || await sha256Hex(body) !== expectedChecksum) {
    throw new Error('Un objeto del manifiesto no coincide con su checksum.')
  }
  return body
}

function runPsql(databaseUrl, script) {
  return new Promise((resolve, reject) => {
    const process = spawn('psql', ['--no-psqlrc', '--quiet', '--tuples-only', '--no-align', '--set', 'ON_ERROR_STOP=1', databaseUrl], { stdio: ['pipe', 'pipe', 'pipe'] })
    let stdout = ''
    process.stdout.on('data', (chunk) => { stdout += chunk })
    process.once('error', () => reject(new Error('No fue posible iniciar psql; instala el cliente PostgreSQL local.')))
    process.once('close', (code) => code === 0 ? resolve(stdout) : reject(new Error(`La restauración de datos fue rechazada por PostgreSQL (${code}).`)))
    process.stdin.end(script)
  })
}

async function ensureBucket(baseUrl, serviceRoleKey, bucketId) {
  const response = await fetch(`${baseUrl}/storage/v1/bucket`, {
    method: 'POST', headers: { authorization: `Bearer ${serviceRoleKey}`, apikey: serviceRoleKey, 'content-type': 'application/json' },
    body: JSON.stringify({ id: bucketId, name: bucketId, public: false }),
  })
  if (!response.ok && response.status !== 400 && response.status !== 409) throw new Error('No fue posible preparar un bucket privado en la instancia aislada.')
}

async function restoreAttachment(baseUrl, serviceRoleKey, file, body) {
  const bucket = file.source?.bucket_id
  const name = file.source?.name
  if (typeof bucket !== 'string' || typeof name !== 'string') throw new Error('El manifiesto no conserva la ruta original de un adjunto.')
  await ensureBucket(baseUrl, serviceRoleKey, bucket)
  const encodedPath = `${encodeURIComponent(bucket)}/${name.split('/').map(encodeURIComponent).join('/')}`
  const response = await fetch(`${baseUrl}/storage/v1/object/${encodedPath}`, {
    method: 'POST', headers: { authorization: `Bearer ${serviceRoleKey}`, apikey: serviceRoleKey, 'content-type': file.mime_type, 'x-upsert': 'true' }, body,
  })
  if (!response.ok) throw new Error('No fue posible restaurar un adjunto en la instancia aislada.')
  const verification = await fetch(`${baseUrl}/storage/v1/object/${encodedPath}`, {
    headers: { authorization: `Bearer ${serviceRoleKey}`, apikey: serviceRoleKey },
  })
  if (!verification.ok) throw new Error('No fue posible verificar un adjunto restaurado.')
  const restored = new Uint8Array(await verification.arrayBuffer())
  if (restored.byteLength !== body.byteLength || await sha256Hex(restored) !== file.sha256) {
    throw new Error('Un adjunto restaurado no coincide con el manifiesto.')
  }
}

async function main() {
  for (const name of required) requireEnvironment(name)
  assertLocalIsolatedDestination()
  const storage = createS3CompatibleStorage({
    endpoint: requireEnvironment('BACKUP_S3_ENDPOINT'), bucket: requireEnvironment('BACKUP_S3_BUCKET'),
    accessKeyId: requireEnvironment('BACKUP_S3_ACCESS_KEY_ID'), secretAccessKey: requireEnvironment('BACKUP_S3_SECRET_ACCESS_KEY'), region: process.env.BACKUP_S3_REGION ?? 'auto',
  })
  const manifestKey = requireEnvironment('BACKUP_MANIFEST_KEY')
  const manifestHead = await storage.headObject(manifestKey)
  if (!manifestHead?.sha256) throw new Error('El manifiesto remoto no tiene checksum verificable.')
  const manifestBytes = await readVerifiedObject(storage, manifestKey, manifestHead.sha256)
  const manifest = JSON.parse(new TextDecoder().decode(manifestBytes))
  if (manifest.format !== 'almacen-el-amigo-external-backup-v1' || !Array.isArray(manifest.files) || typeof manifest.business_id !== 'string') {
    throw new Error('El manifiesto no corresponde a un respaldo externo compatible.')
  }

  const downloaded = new Map()
  for (const file of manifest.files) downloaded.set(file.key, await readVerifiedObject(storage, file.key, file.sha256, file.size_bytes))
  const dataFile = manifest.files.find((file) => file.kind === 'data')
  if (!dataFile) throw new Error('El conjunto no incluye el respaldo de datos.')
  const dataPayload = JSON.parse(new TextDecoder().decode(downloaded.get(dataFile.key)))
  if (dataPayload.business_id !== manifest.business_id) throw new Error('El negocio del respaldo de datos no coincide con el manifiesto.')

  const json = JSON.stringify(dataPayload)
  const delimiter = '$backup_payload$'
  if (json.includes(delimiter)) throw new Error('El contenido del respaldo requiere una restauración asistida.')
  const sql = `begin; set local app.backup_restore_isolated = 'true'; select json_build_object('restore', public.restore_business_backup_data(${delimiter}${json}${delimiter}::jsonb), 'validation', public.validate_restored_business_backup('${manifest.business_id}')); commit;\n`
  const output = await runPsql(requireEnvironment('RESTORE_SUPABASE_DB_URL'), sql)
  const result = JSON.parse(output.trim())
  const expectedCounts = Object.fromEntries(Object.entries(dataPayload.tables).map(([table, rows]) => [table, Array.isArray(rows) ? rows.length : -1]))
  for (const [table, expected] of Object.entries(expectedCounts)) {
    if (result.restore?.table_counts?.[table] !== expected) throw new Error(`La cantidad restaurada de ${table} no coincide con el respaldo.`)
  }
  if (result.validation?.valid !== true) throw new Error('Las reglas críticas no validaron después de reconstruir los datos.')

  for (const file of manifest.files.filter((candidate) => candidate.kind === 'attachment')) {
    await restoreAttachment(requireEnvironment('RESTORE_SUPABASE_URL').replace(/\/$/, ''), requireEnvironment('RESTORE_SUPABASE_SERVICE_ROLE_KEY'), file, downloaded.get(file.key))
  }

  const report = { status: 'success', backup_set_id: manifest.backup_set_id, business_id: manifest.business_id, restored_at: new Date().toISOString(), restored_table_counts: result.restore.table_counts, attachment_count: manifest.files.filter((file) => file.kind === 'attachment').length, validation: result.validation }
  const reportDirectory = process.env.RESTORE_REPORT_DIRECTORY ?? 'tmp/restore-reports'
  await mkdir(reportDirectory, { recursive: true })
  const reportPath = join(reportDirectory, `restore-${manifest.backup_set_id}.json`)
  await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`, { encoding: 'utf8', mode: 0o600 })
  process.stdout.write(`Restauración aislada correcta. Informe: ${reportPath}\n`)
}

main().catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.message : 'La restauración aislada falló.'}\n`)
  process.exitCode = 1
})
