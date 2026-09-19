import { useEffect, useState, type FormEvent, type ReactNode } from 'react'
import { formatGTQ } from '../../../domain/money/money'
import { getOperationalReport, type OperationalReport } from '../services/reportService'
import { createAndDownloadManualBackup, downloadReportCsv, downloadStructuredExport, getLatestExternalBackupJob, processExternalBackupJob, retryExternalBackupJob, startExternalBackup, type ExternalBackupJob } from '../services/exportService'

type ReportsPanelProps = { businessId: string; timezone: string }

function businessDateInTimezone(timezone: string): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    day: '2-digit', month: '2-digit', timeZone: timezone, year: 'numeric',
  }).formatToParts(new Date())
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]))
  return `${values.year}-${values.month}-${values.day}`
}

function firstDayOfMonth(date: string): string {
  return `${date.slice(0, 7)}-01`
}

function paymentMethodLabel(method: string): string {
  return { card: 'Tarjeta', cash: 'Efectivo', qr: 'QR', transfer: 'Transferencia' }[method] ?? method
}

export function ReportsPanel({ businessId, timezone }: ReportsPanelProps) {
  const today = businessDateInTimezone(timezone)
  const [startDate, setStartDate] = useState(firstDayOfMonth(today))
  const [endDate, setEndDate] = useState(today)
  const [report, setReport] = useState<OperationalReport | null>(null)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(false)
  const [isExporting, setIsExporting] = useState(false)
  const [backupMessage, setBackupMessage] = useState<string | null>(null)
  const [backupJob, setBackupJob] = useState<ExternalBackupJob | null>(null)

  useEffect(() => {
    void getLatestExternalBackupJob(businessId).then(setBackupJob).catch(() => undefined)
  }, [businessId])

  useEffect(() => {
    if (!backupJob || ['completed', 'failed'].includes(backupJob.status)) return
    const timer = window.setTimeout(() => {
      void processExternalBackupJob(backupJob.id).then(setBackupJob).catch((error: unknown) => {
        setErrorMessage(error instanceof Error ? error.message : 'No fue posible continuar el respaldo externo.')
      })
    }, 800)
    return () => window.clearTimeout(timer)
  }, [backupJob])

  async function loadReport(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (startDate > endDate) {
      setErrorMessage('La fecha inicial no puede ser posterior a la fecha final.')
      return
    }
    setErrorMessage(null)
    setIsLoading(true)
    try {
      setReport(await getOperationalReport(businessId, startDate, endDate))
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'No fue posible cargar el reporte.')
    } finally {
      setIsLoading(false)
    }
  }

  async function generateExport(action: () => Promise<void>) {
    setIsExporting(true); setErrorMessage(null); setBackupMessage(null)
    try { await action() } catch (error) { setErrorMessage(error instanceof Error ? error.message : 'No fue posible generar la descarga.') }
    finally { setIsExporting(false) }
  }

  return <section className="catalog-panel reports-panel" aria-labelledby="reports-title">
    <h2 id="reports-title">Reportes operativos</h2>
    <p className="muted">Los importes se calculan en el servidor con la zona horaria del negocio. Solo usuarios autorizados pueden ver este resumen.</p>
    <form className="catalog-form report-period-form" onSubmit={(event) => void loadReport(event)}>
      <label className="field">Desde<input type="date" value={startDate} onChange={(event) => setStartDate(event.target.value)} required /></label>
      <label className="field">Hasta<input type="date" value={endDate} onChange={(event) => setEndDate(event.target.value)} required /></label>
      <button className="button" disabled={isLoading}>{isLoading ? 'Cargando…' : 'Consultar reporte'}</button>
    </form>
    {errorMessage ? <p className="notice" role="alert">{errorMessage}</p> : null}
    {!report ? <p className="muted">Selecciona un periodo para consultar ventas, compras, caja y distribuidores.</p> : <>
      <div className="dashboard-grid report-summary">
        <article className="dashboard-card"><h3>Ventas</h3><strong>{formatGTQ(report.summary.salesAmount)}</strong><span>{report.summary.salesCount} confirmada(s)</span></article>
        <article className="dashboard-card"><h3>Compras</h3><strong>{formatGTQ(report.summary.purchasesAmount)}</strong><span>{report.summary.purchasesCount} confirmada(s)</span></article>
        <article className="dashboard-card"><h3>Diferencia de caja</h3><strong>{formatGTQ(report.summary.cashDifferenceAmount)}</strong><span>Cierres del periodo</span></article>
        <article className="dashboard-card"><h3>Saldo con distribuidores</h3><strong>{formatGTQ(report.summary.openSupplierBalance)}</strong><span>Saldo actual derivado</span></article>
      </div>
      <ReportList title="Ventas por día" emptyMessage="No hay ventas confirmadas en el periodo.">
        {report.salesByDay.map((item) => <li key={item.businessDate}><span>{item.businessDate} · {item.salesCount} venta(s)</span><strong>{formatGTQ(item.salesAmount)}</strong></li>)}
      </ReportList>
      <ReportList title="Ventas por forma de pago" emptyMessage="No hay pagos confirmados en el periodo.">
        {report.salesByPaymentMethod.map((item) => <li key={item.paymentMethod}><span>{paymentMethodLabel(item.paymentMethod)} · {item.salesCount} venta(s)</span><strong>{formatGTQ(item.salesAmount)}</strong></li>)}
      </ReportList>
      <ReportList title="Variantes más vendidas" emptyMessage="No hay líneas de venta en el periodo.">
        {report.topSoldVariants.map((item) => <li key={`${item.productName}-${item.variantCode}`}><span>{item.productName} · {item.variantCode} · {item.quantity} unidad(es)</span><strong>{formatGTQ(item.salesAmount)}</strong></li>)}
      </ReportList>
      <ReportList title="Compras por distribuidor" emptyMessage="No hay compras confirmadas en el periodo.">
        {report.purchasesBySupplier.map((item) => <li key={item.supplierName}><span>{item.supplierName} · {item.purchasesCount} compra(s)</span><strong>{formatGTQ(item.purchasesAmount)}</strong></li>)}
      </ReportList>
      <div className="dashboard-actions"><button className="button button--compact" type="button" onClick={() => downloadReportCsv(report, startDate, endDate)}>Descargar CSV</button></div>
    </>}
    <section className="report-list" aria-label="Exportación y respaldo">
      <h3>Exportación y respaldo</h3>
      <p className="muted">El CSV y el JSON facilitan consulta o traslado; el respaldo externo se marca como válido solo después de verificar datos, manifiesto y adjuntos.</p>
      <div className="dashboard-actions"><button className="button button--compact" disabled={isExporting} type="button" onClick={() => void generateExport(() => downloadStructuredExport(businessId))}>Descargar JSON estructurado</button><button className="button button--compact" disabled={isExporting} type="button" onClick={() => void generateExport(() => createAndDownloadManualBackup(businessId))}>Descargar respaldo local</button><button className="button button--compact" disabled={isExporting || (backupJob !== null && !['completed', 'failed'].includes(backupJob.status))} type="button" onClick={() => void generateExport(async () => { const job = await startExternalBackup(businessId); setBackupJob(job); setBackupMessage(`Respaldo externo iniciado: ${job.id.slice(0, 8)}.`) })}>Respaldar externamente</button></div>
      {backupMessage ? <p className="notice" role="status">{backupMessage}</p> : null}
      {backupJob ? <p className="notice" role={backupJob.status === 'failed' ? 'alert' : 'status'}>Respaldo {backupJob.status}: {backupJob.progress_percent}% ({backupJob.verified_files}/{backupJob.total_files} archivos verificados).{backupJob.status === 'completed' ? ' El conjunto y manifiesto quedaron verificados.' : ''}{backupJob.status === 'failed' ? ` ${backupJob.error_message ?? 'Puedes reanudarlo desde el último archivo verificado.'}` : ''}</p> : null}
      {backupJob?.status === 'failed' ? <div className="dashboard-actions"><button className="button button--compact" type="button" onClick={() => void generateExport(async () => { setBackupJob(await retryExternalBackupJob(backupJob.id)); setBackupMessage('Respaldo reanudado desde el último archivo verificado.') })}>Reanudar respaldo</button></div> : null}
    </section>
  </section>
}

type ReportListProps = { children: ReactNode; emptyMessage: string; title: string }

function ReportList({ children, emptyMessage, title }: ReportListProps) {
  const hasEntries = Array.isArray(children) ? children.length > 0 : Boolean(children)
  return <section className="report-list" aria-label={title}>
    <h3>{title}</h3>
    {hasEntries ? <ul className="dashboard-list">{children}</ul> : <p className="muted">{emptyMessage}</p>}
  </section>
}
