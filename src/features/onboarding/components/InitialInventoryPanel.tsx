import { useCallback, useEffect, useMemo, useState, type ChangeEvent, type FormEvent } from 'react'
import { formatGTQ } from '../../../domain/money/money'
import { getCatalogVariants, type CatalogVariant } from '../../catalog/services/catalogService'
import {
  getInitialInventoryImport,
  importInitialInventory,
  type InitialInventoryImportSummary,
} from '../services/initialInventoryService'
import {
  INITIAL_INVENTORY_TEMPLATE,
  parseInitialInventoryCsv,
  type InitialInventoryCsvRow,
} from '../services/initialInventoryCsv'

type InitialInventoryPanelProps = { businessId: string }

type ResolvedCsvRow = InitialInventoryCsvRow & { variant: CatalogVariant | null }

function downloadTemplate() {
  const anchor = document.createElement('a')
  anchor.href = URL.createObjectURL(new Blob([INITIAL_INVENTORY_TEMPLATE], { type: 'text/csv;charset=utf-8' }))
  anchor.download = 'plantilla-inventario-inicial.csv'
  anchor.click()
  URL.revokeObjectURL(anchor.href)
}

export function InitialInventoryPanel({ businessId }: InitialInventoryPanelProps) {
  const [catalog, setCatalog] = useState<CatalogVariant[]>([])
  const [csvRows, setCsvRows] = useState<InitialInventoryCsvRow[]>([])
  const [existingImport, setExistingImport] = useState<InitialInventoryImportSummary | null>(null)
  const [reason, setReason] = useState('Conteo físico inicial verificado antes del piloto')
  const [isAcknowledged, setIsAcknowledged] = useState(false)
  const [requestId, setRequestId] = useState(() => crypto.randomUUID())
  const [message, setMessage] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [isSubmitting, setIsSubmitting] = useState(false)

  const load = useCallback(async () => {
    setIsLoading(true)
    try {
      const [nextCatalog, nextImport] = await Promise.all([
        getCatalogVariants(businessId, ''),
        getInitialInventoryImport(businessId),
      ])
      setCatalog(nextCatalog)
      setExistingImport(nextImport)
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No fue posible preparar la carga inicial.')
    } finally {
      setIsLoading(false)
    }
  }, [businessId])

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0)
    return () => window.clearTimeout(timer)
  }, [load])

  const resolvedRows = useMemo<ResolvedCsvRow[]>(() => {
    const variantsByCode = new Map(catalog.map((variant) => [variant.variantCode.toUpperCase(), variant]))
    return csvRows.map((row) => ({ ...row, variant: variantsByCode.get(row.variantCode) ?? null }))
  }, [catalog, csvRows])

  const unknownRows = resolvedRows.filter((row) => !row.variant)
  const totalUnits = resolvedRows.reduce((total, row) => total + row.quantity, 0)

  async function handleCsvChange(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0]
    if (!file) return
    setMessage(null)
    try {
      if (file.size > 512_000) throw new Error('La plantilla no puede superar 500 KB.')
      const rows = parseInitialInventoryCsv(await file.text())
      if (rows.length > 1000) throw new Error('La carga inicial admite como máximo 1000 líneas.')
      setCsvRows(rows)
      setIsAcknowledged(false)
      setRequestId(crypto.randomUUID())
      setMessage(`Plantilla validada localmente: ${rows.length} línea(s). Revisa la vista previa antes de confirmar.`)
    } catch (error) {
      setCsvRows([])
      setMessage(error instanceof Error ? error.message : 'No fue posible leer la plantilla.')
    }
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setMessage(null)
    try {
      if (existingImport) throw new Error('Este negocio ya tiene una carga inicial confirmada.')
      if (resolvedRows.length === 0) throw new Error('Carga una plantilla con al menos una variante.')
      if (unknownRows.length > 0) throw new Error('Corrige los códigos que no existen en el catálogo antes de confirmar.')
      if (reason.trim().length < 3) throw new Error('Indica el origen o motivo del conteo inicial.')
      if (!isAcknowledged) throw new Error('Confirma que comparaste el archivo con el conteo físico.')
      if (!window.confirm(`Confirmar ${resolvedRows.length} variantes y ${totalUnits} unidades como inventario inicial? Esta acción no se puede repetir.`)) return

      setIsSubmitting(true)
      const importId = await importInitialInventory(
        businessId,
        resolvedRows.map((row) => ({ quantity: row.quantity, unitCost: row.unitCost, variantId: row.variant!.variantId })),
        reason,
        requestId,
      )
      setMessage(`Carga inicial ${importId.slice(0, 8)} confirmada. Las existencias ya están disponibles y cada línea conserva un lote auditable.`)
      setCsvRows([])
      setIsAcknowledged(false)
      setRequestId(crypto.randomUUID())
      await load()
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No fue posible confirmar la carga inicial.')
    } finally {
      setIsSubmitting(false)
    }
  }

  return <section className="catalog-panel phase8-panel" aria-labelledby="initial-inventory-title">
    <div className="section-heading">
      <div>
        <span className="eyebrow">Fase 8 · Preparación del piloto</span>
        <h2 id="initial-inventory-title">Carga inicial de inventario</h2>
      </div>
      {!existingImport ? <button className="button button--compact button--secondary" type="button" onClick={downloadTemplate}>Descargar plantilla</button> : null}
    </div>
    <p className="muted">Esta carga crea lotes iniciales auditables; no crea una compra, una deuda ni cambia precios. Debe hacerse una sola vez, antes de ventas, compras o ajustes.</p>

    {isLoading ? <p className="muted">Preparando catálogo y estado de la carga…</p> : null}
    {existingImport ? <section className="phase8-complete" aria-label="Carga inicial confirmada">
      <strong>Carga inicial confirmada</strong>
      <span>{existingImport.lineCount} variantes · {new Intl.DateTimeFormat('es-GT', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(existingImport.importedAt))}</span>
      <span className="muted">{existingImport.reason}</span>
      <p className="muted">Las diferencias posteriores se registran con conteo o ajuste; no se vuelve a importar una base inicial.</p>
    </section> : <form className="catalog-form" onSubmit={(event) => void handleSubmit(event)}>
      <label className="field" htmlFor="initial-inventory-file">
        Archivo CSV verificado
        <input id="initial-inventory-file" accept=".csv,text/csv" type="file" onChange={(event) => void handleCsvChange(event)} />
      </label>
      <p className="field-help">Columnas requeridas: <code>variant_code</code>, <code>quantity</code> y <code>unit_cost</code>. El costo puede quedar vacío si todavía no se conoce; no se calculan valores con punto flotante.</p>

      {resolvedRows.length > 0 ? <section className="initial-import-preview" aria-labelledby="initial-preview-title">
        <div className="section-heading">
          <h3 id="initial-preview-title">Vista previa</h3>
          <strong>{resolvedRows.length} variantes · {totalUnits} unidades</strong>
        </div>
        {unknownRows.length > 0 ? <p className="notice" role="alert">Hay {unknownRows.length} código(s) que no existen en el catálogo. Crea o corrige sus variantes antes de importar.</p> : null}
        <ul className="price-history-list">
          {resolvedRows.map((row) => <li key={row.variantCode} className={row.variant ? '' : 'import-row--error'}>
            <strong>{row.variant ? `${row.variant.productName} · ${row.variantCode}` : `${row.variantCode} · No encontrada`}</strong>
            <span>{row.quantity} unidad(es) · {row.unitCost === null ? 'Costo pendiente de conocer' : `Costo: ${formatGTQ(row.unitCost)}`}</span>
          </li>)}
        </ul>
      </section> : null}

      <label className="field" htmlFor="initial-inventory-reason">Origen del conteo<input id="initial-inventory-reason" minLength={3} maxLength={300} required value={reason} onChange={(event) => setReason(event.target.value)} /></label>
      <label className="check-field" htmlFor="initial-inventory-acknowledged"><input id="initial-inventory-acknowledged" type="checkbox" checked={isAcknowledged} onChange={(event) => setIsAcknowledged(event.target.checked)} /><span>Comparé cada cantidad con el conteo físico y entiendo que las diferencias posteriores se ajustan con trazabilidad.</span></label>
      <button className="button" disabled={isSubmitting || resolvedRows.length === 0 || unknownRows.length > 0} type="submit">{isSubmitting ? 'Confirmando carga…' : 'Confirmar inventario inicial'}</button>
    </form>}

    <section className="phase8-checklist" aria-labelledby="pilot-checklist-title">
      <h3 id="pilot-checklist-title">Antes del piloto</h3>
      <ol>
        <li>Crear y revisar catálogo, precios mínimos y variantes antes de subir la plantilla.</li>
        <li>Probar una venta, una compra, apertura y cierre de caja con datos ficticios.</li>
        <li>Comparar diariamente ventas, efectivo e inventario con el registro paralelo.</li>
        <li>Resolver diferencias mediante los flujos de conteo, ajuste o cancelación; nunca editando existencias.</li>
      </ol>
      <p className="notice">El respaldo externo debe pasar de la programación local de prueba a un ejecutor privado permanente antes de operar continuamente con datos reales.</p>
    </section>
    {message ? <p className="notice" role="status">{message}</p> : null}
  </section>
}
