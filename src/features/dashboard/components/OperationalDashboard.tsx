import { useCallback, useEffect, useState } from 'react'
import { formatGTQ } from '../../../domain/money/money'
import {
  getOperationalDashboard,
  type OperationalDashboard as OperationalDashboardData,
} from '../services/dashboardService'

type OperationalDashboardProps = {
  businessId: string
  onNavigate: (view: 'operations' | 'sell') => void
}

type PendingItem = { label: string; value: number | null }

export function OperationalDashboard({ businessId, onNavigate }: OperationalDashboardProps) {
  const [dashboard, setDashboard] = useState<OperationalDashboardData | null>(null)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(true)

  const load = useCallback(async () => {
    setIsLoading(true)
    setErrorMessage(null)
    try {
      setDashboard(await getOperationalDashboard(businessId))
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'No fue posible cargar el inicio operativo.')
    } finally {
      setIsLoading(false)
    }
  }, [businessId])

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0)
    return () => window.clearTimeout(timer)
  }, [load])

  if (isLoading && !dashboard) return <section className="catalog-panel"><p className="muted">Cargando inicio operativo…</p></section>

  if (errorMessage && !dashboard) {
    return <section className="catalog-panel"><p className="notice" role="alert">{errorMessage}</p><button className="button button--compact" type="button" onClick={() => void load()}>Reintentar</button></section>
  }

  if (!dashboard) return null

  const pendingItems: PendingItem[] = [
    { label: 'Revisiones de precio', value: dashboard.pendingPriceReviews },
    { label: 'Abonos por confirmar', value: dashboard.pendingSupplierPayments },
    { label: 'Autorizaciones de precio', value: dashboard.pendingSaleAuthorizations },
    { label: 'Conteos o ajustes', value: dashboard.pendingInventoryAdjustments },
    { label: 'Defectuosos en seguimiento', value: dashboard.pendingDefectiveProducts },
    { label: 'Resoluciones de defectuosos', value: dashboard.pendingDefectiveResolutions },
  ].filter((item): item is { label: string; value: number } => item.value !== null)

  return <section className="catalog-panel operational-dashboard" aria-labelledby="operational-dashboard-title">
    <div className="section-heading">
      <div>
        <h2 id="operational-dashboard-title">Inicio operativo</h2>
        <p className="muted">Día comercial: {dashboard.businessDate}</p>
      </div>
      <button className="button button--compact" type="button" onClick={() => void load()}>Actualizar</button>
    </div>
    {errorMessage ? <p className="notice" role="alert">{errorMessage}</p> : null}

    <div className="dashboard-grid">
      <article className="dashboard-card">
        <h3>Caja de ventas</h3>
        {dashboard.openCashSession
          ? <><strong>Abierta</strong><span>Fondo: {formatGTQ(dashboard.openCashSession.openingFund)}</span></>
          : <><strong>Sin caja abierta</strong><span>Abre caja antes de confirmar ventas.</span></>}
      </article>
      {dashboard.sensitiveSummary ? <>
        <article className="dashboard-card">
          <h3>Ventas de hoy</h3>
          <strong>{formatGTQ(dashboard.sensitiveSummary.todaySalesAmount)}</strong>
          <span>{dashboard.sensitiveSummary.todaySalesCount} confirmada(s)</span>
        </article>
        <article className="dashboard-card">
          <h3>Saldo con distribuidores</h3>
          <strong>{formatGTQ(dashboard.sensitiveSummary.openSupplierBalance)}</strong>
          <span>Importe derivado al momento de la consulta.</span>
        </article>
      </> : null}
    </div>

    <section className="dashboard-pending" aria-labelledby="pending-title">
      <h3 id="pending-title">Pendientes visibles para tu rol</h3>
      {pendingItems.length === 0 ? <p className="muted">No tienes pendientes operativos visibles.</p> : <ul className="dashboard-list">
        {pendingItems.map((item) => <li key={item.label}><span>{item.label}</span><strong>{item.value}</strong></li>)}
      </ul>}
    </section>

    <div className="dashboard-actions">
      <button className="button button--compact" type="button" onClick={() => onNavigate('sell')}>Registrar venta</button>
      <button className="button button--compact" type="button" onClick={() => onNavigate('operations')}>Ver operaciones</button>
    </div>
  </section>
}
