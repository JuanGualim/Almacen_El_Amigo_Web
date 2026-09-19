const url = process.env.BACKUP_FUNCTION_URL
const token = process.env.BACKUP_JOB_TOKEN
const kind = process.env.BACKUP_JOB_KIND ?? 'automatic_daily'
const action = process.env.BACKUP_JOB_ACTION ?? 'start_automatic'

if (!url || !token || !['start_automatic', 'process_pending', 'cleanup'].includes(action) || (action === 'start_automatic' && !['automatic_daily', 'automatic_monthly'].includes(kind))) {
  throw new Error('Configura BACKUP_FUNCTION_URL, BACKUP_JOB_TOKEN, BACKUP_JOB_ACTION y, para iniciar, BACKUP_JOB_KIND válido.')
}

const payload = action === 'start_automatic' ? { action, kind } : { action }
const response = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/json', 'x-backup-job-token': token }, body: JSON.stringify(payload) })
if (!response.ok) throw new Error(`La ejecución programada falló (${response.status}).`)
process.stdout.write('Tarea de respaldo externo procesada correctamente.\n')
