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
