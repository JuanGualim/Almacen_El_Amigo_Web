import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { formatGTQ, parseGTQ } from '../../../domain/money/money'
import {
  applySupplierPayment,
  cancelPurchase,
  cancelSale,
  confirmDefectiveResolution,
  confirmSupplierPayment,
  deliverDefectiveProduct,
  getOperationData,
  recordAuthorizedExit,
  recordDefectiveResolution,
  recordInventoryCount,
  recordProductExchange,
  recordSupplierPayment,
  reportDefectiveProduct,
  type DefectiveProduct,
  type DefectiveResolution,
  type DefectiveResolutionType,
  type OpenCashSession,
  type OperationPurchase,
  type OperationSale,
  type OperationSupplier,
  type SupplierPayment,
  type InventoryOperationVariant,
} from '../services/operationsService'

type OperationsPanelProps = { businessId: string; isOwner: boolean }
type PaymentMethod = 'cash' | 'qr' | 'transfer' | 'card'

function positiveInteger(value: string, label: string): number {
  const parsed = Number(value)
  if (!Number.isSafeInteger(parsed) || parsed <= 0) throw new Error(`${label} debe ser un entero positivo.`)
  return parsed
}

export function OperationsPanel({ businessId, isOwner }: OperationsPanelProps) {
  const [variants, setVariants] = useState<InventoryOperationVariant[]>([])
  const [suppliers, setSuppliers] = useState<OperationSupplier[]>([])
  const [sessions, setSessions] = useState<OpenCashSession[]>([])
  const [sales, setSales] = useState<OperationSale[]>([])
  const [purchases, setPurchases] = useState<OperationPurchase[]>([])
  const [payments, setPayments] = useState<SupplierPayment[]>([])
  const [defectiveProducts, setDefectiveProducts] = useState<DefectiveProduct[]>([])
  const [defectiveResolutions, setDefectiveResolutions] = useState<DefectiveResolution[]>([])
  const [message, setMessage] = useState<string | null>(null)
  const [paymentSupplierId, setPaymentSupplierId] = useState('')
  const [paymentAmount, setPaymentAmount] = useState('')
  const [paymentMethod, setPaymentMethod] = useState<PaymentMethod>('transfer')
  const [paymentReference, setPaymentReference] = useState('')
  const [countVariantId, setCountVariantId] = useState('')
  const [countedQuantity, setCountedQuantity] = useState('')
  const [countReason, setCountReason] = useState('')
  const [defectiveVariantId, setDefectiveVariantId] = useState('')
  const [defectiveSupplierId, setDefectiveSupplierId] = useState('')
  const [defectiveQuantity, setDefectiveQuantity] = useState('1')
  const [defectiveDescription, setDefectiveDescription] = useState('')
  const [resolutionDefectiveId, setResolutionDefectiveId] = useState('')
  const [resolutionSupplierId, setResolutionSupplierId] = useState('')
  const [resolutionType, setResolutionType] = useState<DefectiveResolutionType>('replacement')
  const [resolutionReason, setResolutionReason] = useState('')
  const [resolutionAmount, setResolutionAmount] = useState('')
  const [resolutionEvidencePath, setResolutionEvidencePath] = useState('')
  const [exitVariantId, setExitVariantId] = useState('')
  const [exitQuantity, setExitQuantity] = useState('1')
  const [exitReason, setExitReason] = useState('')
  const [saleId, setSaleId] = useState('')
  const [saleCancellationReason, setSaleCancellationReason] = useState('')
  const [purchaseId, setPurchaseId] = useState('')
  const [purchaseCancellationReason, setPurchaseCancellationReason] = useState('')
  const [applicationPaymentId, setApplicationPaymentId] = useState('')
  const [applicationPurchaseId, setApplicationPurchaseId] = useState('')
  const [applicationAmount, setApplicationAmount] = useState('')
  const [exchangeOriginalSaleId, setExchangeOriginalSaleId] = useState('')
  const [exchangeReceivedVariantId, setExchangeReceivedVariantId] = useState('')
  const [exchangeReceivedQuantity, setExchangeReceivedQuantity] = useState('1')
  const [exchangeDeliveredVariantId, setExchangeDeliveredVariantId] = useState('')
  const [exchangeDeliveredQuantity, setExchangeDeliveredQuantity] = useState('1')
  const [exchangeRecognizedValue, setExchangeRecognizedValue] = useState('')
  const [exchangePaymentMethod, setExchangePaymentMethod] = useState<PaymentMethod | ''>('')
  const [exchangeReason, setExchangeReason] = useState('')

  const load = useCallback(async () => {
    try {
      const data = await getOperationData(businessId, isOwner)
      setVariants(data.variants)
      setSuppliers(data.suppliers)
      setSessions(data.cashSessions)
      setDefectiveProducts(data.defectiveProducts)
      setDefectiveResolutions(data.defectiveResolutions)
      setSales(data.sales)
      setPurchases(data.purchases)
      setPayments(data.supplierPayments)
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No fue posible cargar operaciones.')
    }
  }, [businessId, isOwner])

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0)
    return () => window.clearTimeout(timer)
  }, [load])

  async function submit(action: () => Promise<void>, success: string) {
    setMessage(null)
    try {
      await action()
      setMessage(success)
      await load()
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No fue posible completar la operación.')
    }
  }

  function handlePayment(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    void submit(async () => {
      if (!paymentSupplierId) throw new Error('Selecciona un distribuidor.')
      await recordSupplierPayment(businessId, paymentSupplierId, parseGTQ(paymentAmount), paymentMethod, paymentReference, '', crypto.randomUUID())
      setPaymentAmount('')
      setPaymentReference('')
    }, 'Abono registrado. El saldo solo cambiará cuando el dueño lo confirme.')
  }

  function handleCount(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    void submit(async () => {
      if (!countVariantId) throw new Error('Selecciona una variante.')
      await recordInventoryCount(businessId, countVariantId, Number(countedQuantity), countReason)
      setCountedQuantity('')
      setCountReason('')
    }, 'Conteo registrado. La diferencia queda pendiente de confirmación cuando corresponde.')
  }

  function handleDefective(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    void submit(async () => {
      if (!defectiveVariantId) throw new Error('Selecciona una variante.')
      await reportDefectiveProduct(businessId, defectiveVariantId, defectiveSupplierId, positiveInteger(defectiveQuantity, 'La cantidad'), defectiveDescription)
      setDefectiveDescription('')
      setDefectiveQuantity('1')
    }, 'Producto reclasificado como defectuoso y apartado de la existencia disponible.')
  }

  function handleExit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    void submit(async () => {
      if (!exitVariantId) throw new Error('Selecciona una variante.')
      await recordAuthorizedExit(businessId, exitVariantId, positiveInteger(exitQuantity, 'La cantidad'), exitReason)
      setExitReason('')
      setExitQuantity('1')
    }, 'Salida autorizada registrada con consumo FIFO.')
  }

  function handleDefectiveResolution(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    void submit(async () => {
      if (!resolutionDefectiveId) throw new Error('Selecciona un producto defectuoso.')
      const needsAmount = resolutionType === 'supplier_credit' || resolutionType === 'supplier_refund'
      await recordDefectiveResolution(
        businessId, resolutionDefectiveId, resolutionSupplierId, resolutionType,
        resolutionReason, needsAmount ? parseGTQ(resolutionAmount) : null, resolutionEvidencePath,
      )
      setResolutionReason('')
      setResolutionAmount('')
      setResolutionEvidencePath('')
    }, 'Resolución registrada. Las resoluciones sin reemplazo requieren confirmación del dueño.')
  }

  function handleExchange(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    void submit(async () => {
      if (!exchangeReceivedVariantId || !exchangeDeliveredVariantId) throw new Error('Selecciona los productos recibido y entregado.')
      const recognizedValue = exchangeRecognizedValue.trim() ? parseGTQ(exchangeRecognizedValue) : null
      await recordProductExchange(
        businessId, sessions[0]?.id ?? '', exchangeOriginalSaleId, exchangeReceivedVariantId,
        positiveInteger(exchangeReceivedQuantity, 'La cantidad recibida'), exchangeDeliveredVariantId,
        positiveInteger(exchangeDeliveredQuantity, 'La cantidad entregada'), recognizedValue,
        exchangePaymentMethod, exchangeReason,
      )
      setExchangeReason('')
      setExchangeRecognizedValue('')
    }, 'Cambio registrado. Nunca se genera efectivo ni saldo a favor.')
  }

  return <section className="catalog-panel" aria-labelledby="operations-title">
    <h2 id="operations-title">Controles y operaciones especiales</h2>
    <p className="muted">Las existencias y saldos se actualizan solo mediante operaciones auditables.</p>

    <form className="catalog-form" onSubmit={handlePayment}>
      <h3>Registrar abono a distribuidor</h3>
      <label className="field">Distribuidor<select value={paymentSupplierId} onChange={(event) => setPaymentSupplierId(event.target.value)} required><option value="">Selecciona</option>{suppliers.map((supplier) => <option key={supplier.id} value={supplier.id}>{supplier.name}</option>)}</select></label>
      <label className="field">Importe<input inputMode="decimal" value={paymentAmount} onChange={(event) => setPaymentAmount(event.target.value)} required /></label>
      <label className="field">Forma de pago<select value={paymentMethod} onChange={(event) => setPaymentMethod(event.target.value as PaymentMethod)}><option value="transfer">Transferencia</option><option value="qr">QR</option><option value="cash">Efectivo</option><option value="card">Tarjeta</option></select></label>
      <label className="field">Referencia (opcional)<input value={paymentReference} onChange={(event) => setPaymentReference(event.target.value)} maxLength={160} /></label>
      <button className="button">Registrar abono pendiente</button>
    </form>

    <form className="catalog-form" onSubmit={handleCount}>
      <h3>Conteo físico</h3>
      <label className="field">Variante<select value={countVariantId} onChange={(event) => setCountVariantId(event.target.value)} required><option value="">Selecciona</option>{variants.map((variant) => <option key={variant.variantId} value={variant.variantId}>{variant.label} · disponible: {variant.availableQuantity}</option>)}</select></label>
      <label className="field">Cantidad contada<input inputMode="numeric" min="0" value={countedQuantity} onChange={(event) => setCountedQuantity(event.target.value)} required /></label>
      <label className="field">Motivo de la diferencia<input value={countReason} onChange={(event) => setCountReason(event.target.value)} minLength={3} maxLength={300} required /></label>
      <button className="button">Registrar conteo</button>
    </form>

    <form className="catalog-form" onSubmit={handleDefective}>
      <h3>Reportar producto defectuoso</h3>
      <label className="field">Variante<select value={defectiveVariantId} onChange={(event) => setDefectiveVariantId(event.target.value)} required><option value="">Selecciona</option>{variants.filter((variant) => variant.availableQuantity > 0).map((variant) => <option key={variant.variantId} value={variant.variantId}>{variant.label} · disponible: {variant.availableQuantity}</option>)}</select></label>
      <label className="field">Distribuidor (opcional)<select value={defectiveSupplierId} onChange={(event) => setDefectiveSupplierId(event.target.value)}><option value="">Sin asignar</option>{suppliers.map((supplier) => <option key={supplier.id} value={supplier.id}>{supplier.name}</option>)}</select></label>
      <label className="field">Cantidad<input inputMode="numeric" value={defectiveQuantity} onChange={(event) => setDefectiveQuantity(event.target.value)} required /></label>
      <label className="field">Descripción<input value={defectiveDescription} onChange={(event) => setDefectiveDescription(event.target.value)} minLength={3} maxLength={500} required /></label>
      <button className="button">Apartar defectuoso</button>
    </form>

    {isOwner && defectiveProducts.length > 0 ? <section className="catalog-form" aria-labelledby="defective-follow-up-title">
      <h3 id="defective-follow-up-title">Seguimiento de defectuosos</h3>
      <ul className="price-history-list">{defectiveProducts.map((defective) => <li key={defective.id}>
        <span>{defective.status === 'pending_supplier' ? 'Pendiente de entrega al distribuidor' : 'Entregado al distribuidor; pendiente de acuerdo final'}</span>
        {defective.status === 'pending_supplier'
          ? <button className="button button--compact" type="button" onClick={() => void submit(() => deliverDefectiveProduct(businessId, defective.id), 'Defectuoso entregado al distribuidor con sus lotes trazados.')}>Entregar</button>
          : null}
      </li>)}</ul>
    </section> : null}

    {defectiveProducts.length > 0 ? <form className="catalog-form" onSubmit={handleDefectiveResolution}>
      <h3>Registrar resolución de defectuoso</h3>
      <label className="field">Producto defectuoso<select value={resolutionDefectiveId} onChange={(event) => setResolutionDefectiveId(event.target.value)} required><option value="">Selecciona</option>{defectiveProducts.map((defective) => <option key={defective.id} value={defective.id}>{defective.status === 'pending_supplier' ? 'Pendiente de entrega' : 'Entregado al distribuidor'}</option>)}</select></label>
      <label className="field">Tipo<select value={resolutionType} onChange={(event) => setResolutionType(event.target.value as DefectiveResolutionType)}><option value="replacement">Reemplazo</option><option value="returned_to_stock">Regresa a disponible</option><option value="supplier_credit">Crédito del distribuidor</option><option value="supplier_refund">Reembolso del distribuidor</option><option value="accepted_loss">Pérdida o desecho aceptado</option></select></label>
      <label className="field">Distribuidor{resolutionType === 'supplier_credit' || resolutionType === 'supplier_refund' ? ' (obligatorio)' : ' (opcional)'}<select value={resolutionSupplierId} onChange={(event) => setResolutionSupplierId(event.target.value)} required={resolutionType === 'supplier_credit' || resolutionType === 'supplier_refund'}><option value="">Selecciona</option>{suppliers.map((supplier) => <option key={supplier.id} value={supplier.id}>{supplier.name}</option>)}</select></label>
      {resolutionType === 'supplier_credit' || resolutionType === 'supplier_refund' ? <label className="field">Importe<input inputMode="decimal" value={resolutionAmount} onChange={(event) => setResolutionAmount(event.target.value)} required /></label> : null}
      <label className="field">Motivo<input value={resolutionReason} onChange={(event) => setResolutionReason(event.target.value)} minLength={3} maxLength={500} required /></label>
      <label className="field">Ruta de evidencia (opcional)<input value={resolutionEvidencePath} onChange={(event) => setResolutionEvidencePath(event.target.value)} maxLength={500} /></label>
      <button className="button">Registrar resolución</button>
    </form> : null}

    {defectiveResolutions.length > 0 ? <section className="catalog-form" aria-labelledby="resolution-confirmation-title">
      <h3 id="resolution-confirmation-title">Resoluciones pendientes</h3>
      <ul className="price-history-list">{defectiveResolutions.map((resolution) => <li key={resolution.id}>
        <span>{resolution.resolutionType.replaceAll('_', ' ')}</span>
        {isOwner || resolution.resolutionType === 'replacement' ? <button className="button button--compact" type="button" onClick={() => void submit(() => confirmDefectiveResolution(businessId, resolution.id), 'Resolución confirmada con movimientos por lote y auditoría completa.')}>Confirmar resolución</button> : <span className="muted">Pendiente de confirmación del dueño</span>}
      </li>)}</ul>
    </section> : null}

    {isOwner ? <form className="catalog-form" onSubmit={handleExit}>
      <h3>Salida autorizada</h3>
      <label className="field">Variante<select value={exitVariantId} onChange={(event) => setExitVariantId(event.target.value)} required><option value="">Selecciona</option>{variants.filter((variant) => variant.availableQuantity > 0).map((variant) => <option key={variant.variantId} value={variant.variantId}>{variant.label}</option>)}</select></label>
      <label className="field">Cantidad<input inputMode="numeric" value={exitQuantity} onChange={(event) => setExitQuantity(event.target.value)} required /></label>
      <label className="field">Motivo<input value={exitReason} onChange={(event) => setExitReason(event.target.value)} minLength={3} maxLength={300} required /></label>
      <button className="button">Confirmar salida</button>
    </form> : null}

    {isOwner ? <form className="catalog-form" onSubmit={handleExchange}>
      <h3>Cambio sin reembolso</h3>
      <label className="field">Venta original (opcional)<select value={exchangeOriginalSaleId} onChange={(event) => setExchangeOriginalSaleId(event.target.value)}><option value="">No localizada</option>{sales.map((sale) => <option key={sale.id} value={sale.id}>{sale.saleNumber} · {formatGTQ(sale.totalAmount)}</option>)}</select></label>
      <label className="field">Producto recibido<select value={exchangeReceivedVariantId} onChange={(event) => setExchangeReceivedVariantId(event.target.value)} required><option value="">Selecciona</option>{variants.map((variant) => <option key={variant.variantId} value={variant.variantId}>{variant.label}</option>)}</select></label>
      <label className="field">Cantidad recibida<input inputMode="numeric" value={exchangeReceivedQuantity} onChange={(event) => setExchangeReceivedQuantity(event.target.value)} required /></label>
      <label className="field">Producto entregado<select value={exchangeDeliveredVariantId} onChange={(event) => setExchangeDeliveredVariantId(event.target.value)} required><option value="">Selecciona</option>{variants.filter((variant) => variant.availableQuantity > 0).map((variant) => <option key={variant.variantId} value={variant.variantId}>{variant.label}</option>)}</select></label>
      <label className="field">Cantidad entregada<input inputMode="numeric" value={exchangeDeliveredQuantity} onChange={(event) => setExchangeDeliveredQuantity(event.target.value)} required /></label>
      <label className="field">Valor reconocido por unidad (solo si no hay venta original)<input inputMode="decimal" value={exchangeRecognizedValue} onChange={(event) => setExchangeRecognizedValue(event.target.value)} /></label>
      <label className="field">Forma de pago si hay diferencia<select value={exchangePaymentMethod} onChange={(event) => setExchangePaymentMethod(event.target.value as PaymentMethod | '')}><option value="">Se determinará si no hay diferencia</option><option value="cash">Efectivo</option><option value="qr">QR</option><option value="transfer">Transferencia</option><option value="card">Tarjeta</option></select></label>
      <label className="field">Motivo<input value={exchangeReason} onChange={(event) => setExchangeReason(event.target.value)} minLength={3} maxLength={300} required /></label>
      <button className="button">Registrar cambio</button>
    </form> : null}

    {isOwner ? <section className="catalog-form" aria-labelledby="owner-controls-title">
      <h3 id="owner-controls-title">Confirmaciones y cancelaciones del dueño</h3>
      {payments.filter((payment) => payment.status === 'pending').length > 0 ? <ul className="price-history-list">{payments.filter((payment) => payment.status === 'pending').map((payment) => <li key={payment.id}><span>Abono pendiente · {formatGTQ(payment.amount)}</span><button className="button button--compact" type="button" onClick={() => void submit(() => confirmSupplierPayment(businessId, payment.id), 'Abono confirmado. Ya impacta el saldo del distribuidor.')}>Confirmar</button></li>)}</ul> : <p className="muted">No hay abonos pendientes.</p>}
      <label className="field">Abono confirmado<select value={applicationPaymentId} onChange={(event) => setApplicationPaymentId(event.target.value)}><option value="">Selecciona</option>{payments.filter((payment) => payment.status === 'confirmed').map((payment) => <option key={payment.id} value={payment.id}>{formatGTQ(payment.amount)}</option>)}</select></label>
      <label className="field">Compra a cubrir<select value={applicationPurchaseId} onChange={(event) => setApplicationPurchaseId(event.target.value)}><option value="">Selecciona</option>{purchases.map((purchase) => <option key={purchase.id} value={purchase.id}>{purchase.purchaseNumber} · {formatGTQ(purchase.totalAmount)}</option>)}</select></label>
      <label className="field">Importe aplicado<input inputMode="decimal" value={applicationAmount} onChange={(event) => setApplicationAmount(event.target.value)} /></label>
      <button className="button button--compact" type="button" onClick={() => void submit(async () => { if (!applicationPaymentId || !applicationPurchaseId) throw new Error('Selecciona abono y compra.'); await applySupplierPayment(businessId, applicationPaymentId, applicationPurchaseId, parseGTQ(applicationAmount)) }, 'Abono aplicado a la compra sin alterar el historial.')}>Aplicar abono</button>
      <label className="field">Venta a cancelar<select value={saleId} onChange={(event) => setSaleId(event.target.value)}><option value="">Selecciona</option>{sales.map((sale) => <option key={sale.id} value={sale.id}>{sale.saleNumber} · {formatGTQ(sale.totalAmount)}</option>)}</select></label>
      <label className="field">Motivo de cancelación de venta<input value={saleCancellationReason} onChange={(event) => setSaleCancellationReason(event.target.value)} minLength={3} maxLength={300} /></label>
      <button className="button button--compact" type="button" onClick={() => void submit(async () => { if (!saleId || !sessions[0]) throw new Error('Selecciona venta y asegúrate de tener una caja abierta.'); await cancelSale(businessId, saleId, sessions[0].id, saleCancellationReason) }, 'Venta cancelada con reversiones FIFO y compensación de caja cuando aplica.')}>Cancelar venta</button>
      <label className="field">Compra a cancelar<select value={purchaseId} onChange={(event) => setPurchaseId(event.target.value)}><option value="">Selecciona</option>{purchases.map((purchase) => <option key={purchase.id} value={purchase.id}>{purchase.purchaseNumber} · {formatGTQ(purchase.totalAmount)}</option>)}</select></label>
      <label className="field">Motivo de cancelación de compra<input value={purchaseCancellationReason} onChange={(event) => setPurchaseCancellationReason(event.target.value)} minLength={3} maxLength={300} /></label>
      <button className="button button--compact" type="button" onClick={() => void submit(async () => { if (!purchaseId) throw new Error('Selecciona una compra.'); await cancelPurchase(businessId, purchaseId, purchaseCancellationReason) }, 'Compra cancelada mediante compensaciones, si no tenía dependencias.')}>Cancelar compra</button>
    </section> : null}
    {message ? <p className="notice" role="status">{message}</p> : null}
  </section>
}
