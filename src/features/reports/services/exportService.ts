import { getSupabaseClient } from '../../../services/api/supabaseClient'
import type { OperationalReport } from './reportService'

function downloadText(filename: string, content: string, contentType: string): void {
  const url = URL.createObjectURL(new Blob([content], { type: contentType }))
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = filename
  anchor.click()
  URL.revokeObjectURL(url)
}

export function downloadReportCsv(report: OperationalReport, startDate: string, endDate: string): void {
  const rows = [
    ['seccion', 'descripcion', 'cantidad', 'importe_gtq'],
    ['resumen', 'ventas confirmadas', String(report.summary.salesCount), String(report.summary.salesAmount / 100)],
    ['resumen', 'compras confirmadas', String(report.summary.purchasesCount), String(report.summary.purchasesAmount / 100)],
    ['resumen', 'diferencia de caja', '', String(report.summary.cashDifferenceAmount / 100)],
    ...report.salesByDay.map((item) => ['ventas_por_dia', item.businessDate, String(item.salesCount), String(item.salesAmount / 100)]),
    ...report.salesByPaymentMethod.map((item) => ['ventas_por_pago', item.paymentMethod, String(item.salesCount), String(item.salesAmount / 100)]),
    ...report.topSoldVariants.map((item) => ['variantes', `${item.productName} · ${item.variantCode}`, String(item.quantity), String(item.salesAmount / 100)]),
  ]
  const csv = rows.map((row) => row.map((value) => `"${value.replaceAll('"', '""')}"`).join(',')).join('\n')
  downloadText(`reporte-${startDate}-${endDate}.csv`, csv, 'text/csv;charset=utf-8')
}

export async function downloadStructuredExport(businessId: string): Promise<void> {
  const { data, error } = await getSupabaseClient().rpc('get_business_structured_export', { p_business_id: businessId })
  if (error) throw new Error('No fue posible generar la exportación estructurada.')
  downloadText(`exportacion-estructurada-${businessId}.json`, `${JSON.stringify(data, null, 2)}\n`, 'application/json')
}

export async function createAndDownloadManualBackup(businessId: string): Promise<void> {
  const { data, error } = await getSupabaseClient().rpc('create_manual_business_backup', { p_business_id: businessId })
  const row = Array.isArray(data) ? data[0] : null
  if (error || !row || typeof row.snapshot !== 'object') throw new Error('No fue posible generar el respaldo manual.')
  downloadText(`respaldo-manual-${businessId}-${String(row.backup_id).slice(0, 8)}.json`, `${JSON.stringify({ checksum_sha256: row.checksum_sha256, snapshot: row.snapshot }, null, 2)}\n`, 'application/json')
}

export type ExternalBackupJob = {
  id: string
  status: 'pending' | 'exporting' | 'copying_attachments' | 'verifying' | 'finalizing' | 'completed' | 'failed'
  progress_percent: number
  total_files: number
  verified_files: number
  total_attachments: number
  verified_attachments: number
  error_message: string | null
  timing_ms: Record<string, number>
}

function readExternalBackupJob(data: unknown): ExternalBackupJob {
  const job = data && typeof data === 'object' && 'job' in data ? (data as { job?: unknown }).job : null
  if (!job || typeof job !== 'object' || typeof (job as { id?: unknown }).id !== 'string') {
    throw new Error('El trabajo de respaldo no devolvió un estado válido.')
  }
  return job as ExternalBackupJob
}

export async function startExternalBackup(businessId: string): Promise<ExternalBackupJob> {
  const { data, error } = await getSupabaseClient().functions.invoke('external-backup', {
    body: { action: 'start', businessId },
  })
  const jobId = data && typeof data === 'object' && typeof (data as { jobId?: unknown }).jobId === 'string' ? (data as { jobId: string }).jobId : null
  if (error || !jobId) throw new Error('No fue posible iniciar el respaldo externo.')
  return getExternalBackupJob(jobId)
}

export async function getExternalBackupJob(jobId: string): Promise<ExternalBackupJob> {
  const { data, error } = await getSupabaseClient().functions.invoke('external-backup', { body: { action: 'status', jobId } })
  if (error) throw new Error('No fue posible consultar el respaldo externo.')
  return readExternalBackupJob(data)
}

export async function getLatestExternalBackupJob(businessId: string): Promise<ExternalBackupJob | null> {
  const { data, error } = await getSupabaseClient().from('external_backup_jobs').select('id, status, progress_percent, total_files, verified_files, total_attachments, verified_attachments, error_message, timing_ms').eq('business_id', businessId).order('created_at', { ascending: false }).limit(1).maybeSingle()
  if (error) throw new Error('No fue posible consultar el último respaldo externo.')
  return data ? data as ExternalBackupJob : null
}

export async function processExternalBackupJob(jobId: string): Promise<ExternalBackupJob> {
  const { data, error } = await getSupabaseClient().functions.invoke('external-backup', { body: { action: 'process', jobId } })
  if (error) throw new Error('No fue posible procesar el siguiente lote del respaldo externo.')
  return readExternalBackupJob(data)
}

export async function retryExternalBackupJob(jobId: string): Promise<ExternalBackupJob> {
  const { data, error } = await getSupabaseClient().functions.invoke('external-backup', { body: { action: 'retry', jobId } })
  if (error) throw new Error('No fue posible reanudar el respaldo externo.')
  return readExternalBackupJob(data)
}
