import { useCallback, useEffect, useState } from 'react'
import { getInventoryAlerts, type InventoryAlertProduct } from '../services/inventoryAlertsService'

export function InventoryAlertsPanel({ businessId }: { businessId: string }) {
  const [alerts, setAlerts] = useState<InventoryAlertProduct[]>([])
  const [message, setMessage] = useState<string | null>(null)
  const load = useCallback(async () => {
    try { setAlerts(await getInventoryAlerts(businessId)); setMessage(null) }
    catch (error) { setMessage(error instanceof Error ? error.message : 'No fue posible cargar alertas.') }
  }, [businessId])
  useEffect(() => { const timer = window.setTimeout(() => void load(), 0); return () => window.clearTimeout(timer) }, [load])
  return <section className="dashboard-pending" aria-labelledby="inventory-alerts-title">
    <div className="section-heading"><h3 id="inventory-alerts-title">Alertas de existencias</h3><button className="button button--compact" type="button" onClick={() => void load()}>Actualizar</button></div>
    {message ? <p className="notice" role="alert">{message}</p> : null}
    {alerts.length === 0 ? <p className="muted">No hay variantes agotadas ni con stock bajo.</p> : <ul className="dashboard-list">{alerts.map((product) => <li key={product.productId}><span><strong>{product.productName}</strong><br />{product.variants.map((variant) => `${variant.variantCode}: ${variant.status === 'out_of_stock' ? 'agotada' : `${variant.availableQuantity}/${variant.lowStockThreshold} unidades`}`).join(' · ')}</span><strong>{product.outOfStockCount + product.lowStockCount}</strong></li>)}</ul>}
  </section>
}
