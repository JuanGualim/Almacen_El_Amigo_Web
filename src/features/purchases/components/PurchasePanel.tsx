import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react'
import { addMoney, formatGTQ, multiplyMoney, parseGTQ } from '../../../domain/money/money'
import { getCatalogVariants, getVariantDescription, type CatalogVariant } from '../../catalog/services/catalogService'
import {
  confirmPurchase,
  createSupplier,
  getInventoryVariants,
  getPendingPurchases,
  getPendingPurchasePriceReviews,
  getSupplierDirectory,
  getSuppliers,
  recordPurchase,
  resolvePurchasePriceReview,
  setSupplierActiveStatus,
  type InventoryVariant,
  type PendingPurchase,
  type PurchaseLineInput,
  type PurchasePaymentType,
  type PurchasePriceReview,
  type SupplierDirectoryEntry,
  type Supplier,
} from '../services/purchaseService'

type PurchasePanelProps = { businessId: string; canConfirm: boolean }

type PurchaseLine = PurchaseLineInput & { description: string }

const EMPTY_MONEY = parseGTQ('0')

function getToday(): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Guatemala' }).format(new Date())
}

function getPurchasedAt(date: string): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new Error('Selecciona una fecha de compra válida.')
  }

  return new Date(`${date}T12:00:00-06:00`).toISOString()
}

export function PurchasePanel({ businessId, canConfirm }: PurchasePanelProps) {
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [variants, setVariants] = useState<CatalogVariant[]>([])
  const [inventory, setInventory] = useState<InventoryVariant[]>([])
  const [pending, setPending] = useState<PendingPurchase[]>([])
  const [pendingPriceReviews, setPendingPriceReviews] = useState<PurchasePriceReview[]>([])
  const [supplierDirectory, setSupplierDirectory] = useState<SupplierDirectoryEntry[]>([])
  const [supplierName, setSupplierName] = useState('')
  const [supplierContact, setSupplierContact] = useState('')
  const [supplierPhone, setSupplierPhone] = useState('')
  const [supplierId, setSupplierId] = useState('')
  const [variantId, setVariantId] = useState('')
  const [quantity, setQuantity] = useState('1')
  const [unitCost, setUnitCost] = useState('')
  const [lines, setLines] = useState<PurchaseLine[]>([])
  const [paymentType, setPaymentType] = useState<PurchasePaymentType>('cash')
  const [initialPayment, setInitialPayment] = useState('')
  const [invoiceNumber, setInvoiceNumber] = useState('')
  const [purchasedDate, setPurchasedDate] = useState(getToday)
  const [requestId, setRequestId] = useState(() => crypto.randomUUID())
  const [message, setMessage] = useState<string | null>(null)

  const load = useCallback(async () => {
    try {
      const [nextSuppliers, nextVariants, nextInventory, nextPending, nextPriceReviews, nextSupplierDirectory] = await Promise.all([
        getSuppliers(businessId),
        getCatalogVariants(businessId, ''),
        getInventoryVariants(businessId),
        canConfirm ? getPendingPurchases(businessId) : Promise.resolve([]),
        canConfirm ? getPendingPurchasePriceReviews(businessId) : Promise.resolve([]),
        canConfirm ? getSupplierDirectory(businessId) : Promise.resolve([]),
      ])
      setSuppliers(nextSuppliers)
      setVariants(nextVariants)
      setInventory(nextInventory)
      setPending(nextPending)
      setPendingPriceReviews(nextPriceReviews)
      setSupplierDirectory(nextSupplierDirectory)
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No fue posible cargar compras.')
    }
  }, [businessId, canConfirm])

  useEffect(() => {
    const id = window.setTimeout(() => void load(), 0)
    return () => window.clearTimeout(id)
  }, [load])

  const total = useMemo(
    () => addMoney(...lines.map((line) => multiplyMoney(line.unitCost, line.quantity))),
    [lines],
  )

  async function handleSupplier(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setMessage(null)
    try {
      await createSupplier(businessId, supplierName, supplierContact, supplierPhone)
      setSupplierName('')
      setSupplierContact('')
      setSupplierPhone('')
      setMessage('Distribuidor creado.')
      await load()
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No fue posible crear el distribuidor.')
    }
  }

  function handleAddLine() {
    setMessage(null)
    try {
      const selectedVariant = variants.find((variant) => variant.variantId === variantId)
      const units = Number(quantity)
      const cost = parseGTQ(unitCost)
      if (!selectedVariant) throw new Error('Selecciona una variante.')
      if (!Number.isSafeInteger(units) || units <= 0) {
        throw new Error('La cantidad debe ser un entero positivo.')
      }
      if (cost < 0) throw new Error('El costo no puede ser negativo.')
      if (lines.some((line) => line.variantId === variantId)) {
        throw new Error('Esta variante ya está en la compra. Modifica la línea existente o usa una compra separada.')
      }

      const attributes = getVariantDescription(selectedVariant)
      setLines((currentLines) => [...currentLines, {
        description: `${selectedVariant.productName} · ${selectedVariant.variantCode}${attributes === 'Sin atributos adicionales' ? '' : ` · ${attributes}`}`,
        quantity: units,
        unitCost: cost,
        variantId,
      }])
      setVariantId('')
      setQuantity('1')
      setUnitCost('')
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No fue posible agregar la línea.')
    }
  }

  async function handlePurchase(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setMessage(null)
    try {
      if (!supplierId) throw new Error('Selecciona un distribuidor.')
      if (lines.length === 0) throw new Error('Agrega al menos una línea a la compra.')
      const initial = paymentType === 'credit'
        ? EMPTY_MONEY
        : paymentType === 'cash'
          ? total
          : parseGTQ(initialPayment)
      if (paymentType === 'partial' && (initial <= EMPTY_MONEY || initial >= total)) {
        throw new Error('El pago inicial debe ser mayor que cero y menor al total.')
      }
      if (canConfirm && !window.confirm(`Confirmar compra por ${formatGTQ(total)} y aumentar inventario?`)) {
        return
      }

      const purchaseId = await recordPurchase(
        businessId,
        supplierId,
        paymentType,
        initial,
        lines,
        requestId,
        invoiceNumber,
        getPurchasedAt(purchasedDate),
      )
      if (canConfirm) {
        await confirmPurchase(businessId, purchaseId)
        setMessage('Compra confirmada e inventario actualizado.')
      } else {
        setMessage('Compra registrada y pendiente de confirmación del dueño.')
      }
      setLines([])
      setInitialPayment('')
      setInvoiceNumber('')
      setRequestId(crypto.randomUUID())
      await load()
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No fue posible registrar la compra.')
    }
  }

  async function handleConfirm(purchase: PendingPurchase) {
    if (!window.confirm(`Confirmar ${purchase.purchaseNumber} por ${formatGTQ(purchase.totalAmount)} y aumentar inventario?`)) {
      return
    }
    try {
      await confirmPurchase(businessId, purchase.id)
      setMessage('Compra confirmada e inventario actualizado.')
      await load()
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No fue posible confirmar la compra.')
    }
  }

  async function handleSupplierStatus(supplier: SupplierDirectoryEntry) {
    const nextStatus = !supplier.isActive
    const action = nextStatus ? 'reactivar' : 'desactivar'
    if (!window.confirm(`¿Deseas ${action} a ${supplier.name}? Su historial no se eliminará.`)) {
      return
    }
    try {
      await setSupplierActiveStatus(businessId, supplier.id, nextStatus)
      setMessage(`Distribuidor ${nextStatus ? 'activo' : 'inactivo'}.`)
      await load()
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No fue posible cambiar el estado del distribuidor.')
    }
  }

  async function handleResolvePriceReview(review: PurchasePriceReview) {
    const reason = window.prompt('Indica la decisión o motivo para esta revisión de costo:')
    if (reason === null) return
    try {
      await resolvePurchasePriceReview(businessId, review.id, reason)
      setMessage('Revisión de precio resuelta sin cambiar el precio vigente.')
      await load()
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No fue posible resolver la revisión de precio.')
    }
  }

  function getVariantName(variantId: string): string {
    const variant = variants.find((catalogVariant) => catalogVariant.variantId === variantId)
    return variant ? `${variant.productName} · ${variant.variantCode}` : 'Variante de catálogo'
  }

  return <section className="catalog-panel purchase-panel" aria-labelledby="purchase-title">
    <h2 id="purchase-title">Compras e inventario</h2>
    <p className="muted">Una compra solo modifica existencias cuando queda confirmada.</p>

    <form className="catalog-form" onSubmit={handleSupplier}>
      <h3>Nuevo distribuidor</h3>
      <label className="field">Nombre<input value={supplierName} onChange={(event) => setSupplierName(event.target.value)} required maxLength={160} /></label>
      <label className="field">Persona de contacto (opcional)<input value={supplierContact} onChange={(event) => setSupplierContact(event.target.value)} maxLength={160} /></label>
      <label className="field">Teléfono (opcional)<input value={supplierPhone} onChange={(event) => setSupplierPhone(event.target.value)} maxLength={60} /></label>
      <button className="button button--compact">Guardar distribuidor</button>
    </form>

    <form className="catalog-form" onSubmit={handlePurchase}>
      <h3>Registrar compra</h3>
      <label className="field">Distribuidor<select value={supplierId} onChange={(event) => setSupplierId(event.target.value)} required><option value="">Selecciona</option>{suppliers.map((supplier) => <option key={supplier.id} value={supplier.id}>{supplier.name}</option>)}</select></label>
      <label className="field">Factura o comprobante (opcional)<input value={invoiceNumber} onChange={(event) => setInvoiceNumber(event.target.value)} maxLength={120} /></label>
      <label className="field">Fecha de compra<input type="date" value={purchasedDate} onChange={(event) => setPurchasedDate(event.target.value)} required /></label>
      <h4>Agregar línea</h4>
      <label className="field">Variante<select value={variantId} onChange={(event) => setVariantId(event.target.value)}><option value="">Selecciona</option>{variants.map((variant) => <option key={variant.variantId} value={variant.variantId}>{variant.productName} · {variant.variantCode}</option>)}</select></label>
      <div className="catalog-price-fields"><label className="field">Cantidad<input inputMode="numeric" value={quantity} onChange={(event) => setQuantity(event.target.value)} /></label><label className="field">Costo unitario<input inputMode="decimal" value={unitCost} onChange={(event) => setUnitCost(event.target.value)} /></label></div>
      <button className="button button--compact" type="button" onClick={handleAddLine}>Agregar línea</button>
      {lines.length > 0 ? <ul className="price-history-list">{lines.map((line) => <li key={line.variantId}><strong>{line.description}</strong><span>{line.quantity} × {formatGTQ(line.unitCost)} = {formatGTQ(multiplyMoney(line.unitCost, line.quantity))}</span><button className="button button--compact" type="button" onClick={() => setLines((currentLines) => currentLines.filter((currentLine) => currentLine.variantId !== line.variantId))}>Quitar</button></li>)}</ul> : <p className="muted">Agrega las variantes recibidas antes de registrar la compra.</p>}
      <p><strong>Total: {formatGTQ(total)}</strong></p>
      <label className="field">Tipo de compra<select value={paymentType} onChange={(event) => setPaymentType(event.target.value as PurchasePaymentType)}><option value="cash">Contado</option><option value="credit">Crédito</option><option value="partial">Parcial</option></select></label>
      {paymentType === 'partial' ? <label className="field">Pago inicial<input inputMode="decimal" value={initialPayment} onChange={(event) => setInitialPayment(event.target.value)} required /></label> : null}
      <button className="button">{canConfirm ? 'Confirmar compra' : 'Registrar compra'}</button>
    </form>

    <section className="catalog-form" aria-labelledby="inventory-title">
      <h3 id="inventory-title">Existencias disponibles</h3>
      {inventory.length === 0 ? <p className="muted">Todavía no hay existencias confirmadas.</p> : <ul className="price-history-list">{inventory.map((variant) => <li key={variant.variantCode}><strong>{variant.productName} · {variant.variantCode}</strong><span>{variant.availableQuantity} unidades disponibles</span></li>)}</ul>}
    </section>

    {canConfirm && pending.length > 0 ? <><h3>Compras pendientes</h3><ul className="price-history-list">{pending.map((purchase) => <li key={purchase.id}><strong>{purchase.purchaseNumber} · {formatGTQ(purchase.totalAmount)}</strong><button className="button button--compact" type="button" onClick={() => void handleConfirm(purchase)}>Confirmar</button></li>)}</ul></> : null}
    {canConfirm && pendingPriceReviews.length > 0 ? <><h3>Costos por revisar</h3><p className="muted">Resolver una revisión no modifica el precio de venta. Actualízalo desde el catálogo si corresponde.</p><ul className="price-history-list">{pendingPriceReviews.map((review) => <li key={review.id}><strong>{getVariantName(review.variantId)}</strong><span>Costo anterior: {formatGTQ(review.previousUnitCost)} · costo nuevo: {formatGTQ(review.currentUnitCost)}</span><button className="button button--compact" type="button" onClick={() => void handleResolvePriceReview(review)}>Resolver revisión</button></li>)}</ul></> : null}
    {canConfirm && supplierDirectory.length > 0 ? <><h3>Estado de distribuidores</h3><ul className="price-history-list">{supplierDirectory.map((supplier) => <li key={supplier.id}><strong>{supplier.name}</strong><span>{supplier.isActive ? 'Activo' : 'Inactivo'}</span><button className="button button--compact" type="button" onClick={() => void handleSupplierStatus(supplier)}>{supplier.isActive ? 'Desactivar' : 'Reactivar'}</button></li>)}</ul></> : null}
    {message ? <p className="notice" role="status">{message}</p> : null}
  </section>
}
