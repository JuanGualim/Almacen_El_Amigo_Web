import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react'
import { formatCatalogAttributes } from '../../../domain/catalog/attributes'
import { addMoney, formatGTQ, multiplyMoney, parseGTQ, serializeGTQ, type Money } from '../../../domain/money/money'
import { getOpenCashRegisterSummary, type CashRegisterSummary } from '../../cash-register/services/cashRegisterService'
import { confirmSale, confirmSaleWithPriceAuthorization, getSellableVariants, requestSalePriceAuthorization, type SaleLineInput, type SalePaymentMethod, type SellableVariant } from '../services/salesService'

type SalesPanelProps = {
  businessId: string
  onSaleConfirmed: () => void
  refreshToken: number
}

type CartLine = SaleLineInput & { description: string; minimumPrice: Money }

export function SalesPanel({ businessId, onSaleConfirmed, refreshToken }: SalesPanelProps) {
  const [cashSummary, setCashSummary] = useState<CashRegisterSummary | null>(null)
  const [variants, setVariants] = useState<SellableVariant[]>([])
  const [variantId, setVariantId] = useState('')
  const [quantity, setQuantity] = useState('1')
  const [unitPrice, setUnitPrice] = useState('')
  const [paymentMethod, setPaymentMethod] = useState<SalePaymentMethod>('cash')
  const [lines, setLines] = useState<CartLine[]>([])
  const [requestId, setRequestId] = useState(() => crypto.randomUUID())
  const [authorizationId, setAuthorizationId] = useState<string | null>(null)
  const [authorizationReason, setAuthorizationReason] = useState('')
  const [message, setMessage] = useState<string | null>(null)

  const load = useCallback(async () => {
    try {
      const [nextSummary, nextVariants] = await Promise.all([
        getOpenCashRegisterSummary(businessId),
        getSellableVariants(businessId),
      ])
      setCashSummary(nextSummary)
      setVariants(nextVariants)
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No fue posible cargar la venta.')
    }
  }, [businessId])

  useEffect(() => {
    const timeoutId = window.setTimeout(() => void load(), 0)
    return () => window.clearTimeout(timeoutId)
  }, [load, refreshToken])

  const total = useMemo(
    () => addMoney(...lines.map((line) => multiplyMoney(line.unitPrice, line.quantity))),
    [lines],
  )

  function handleVariantChange(nextVariantId: string) {
    setVariantId(nextVariantId)
    const variant = variants.find((item) => item.variantId === nextVariantId)
    setUnitPrice(variant ? serializeGTQ(variant.suggestedPrice) : '')
  }

  function handleAddLine() {
    setMessage(null)
    try {
      const variant = variants.find((item) => item.variantId === variantId)
      const units = Number(quantity)
      const price = parseGTQ(unitPrice)
      if (!variant) throw new Error('Selecciona una variante disponible.')
      if (!Number.isSafeInteger(units) || units <= 0) throw new Error('La cantidad debe ser un entero positivo.')
      if (units > variant.availableQuantity) throw new Error(`Solo hay ${variant.availableQuantity} unidades disponibles.`)
      if (lines.some((line) => line.variantId === variant.variantId)) throw new Error('La variante ya está en el carrito.')

      const attributes = formatCatalogAttributes(variant.attributes)
      setLines((currentLines) => [...currentLines, {
        description: `${variant.productName} · ${variant.variantCode}${attributes ? ` · ${attributes}` : ''}`,
        minimumPrice: variant.minimumPrice,
        quantity: units,
        unitPrice: price,
        variantId: variant.variantId,
      }])
      setVariantId('')
      setQuantity('1')
      setUnitPrice('')
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No fue posible agregar la línea.')
    }
  }

  async function handleConfirm(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setMessage(null)
    try {
      if (!cashSummary) throw new Error('No hay caja abierta para confirmar la venta.')
      if (lines.length === 0) throw new Error('Agrega al menos una línea al carrito.')
      const requiresAuthorization = lines.some((line) => line.unitPrice < line.minimumPrice)
      if (requiresAuthorization && !authorizationId) {
        const id = await requestSalePriceAuthorization(businessId, lines, authorizationReason, requestId)
        setAuthorizationId(id)
        setMessage('Solicitud enviada. El dueño debe aprobarla presencialmente con su PIN antes de confirmar.')
        return
      }
      if (!window.confirm(`Confirmar venta por ${formatGTQ(total)}?`)) return
      const saleId = authorizationId
        ? await confirmSaleWithPriceAuthorization(businessId, cashSummary.cashSessionId, paymentMethod, lines, requestId, authorizationId)
        : await confirmSale(businessId, cashSummary.cashSessionId, paymentMethod, lines, requestId)
      setLines([])
      setRequestId(crypto.randomUUID())
      setAuthorizationId(null)
      setAuthorizationReason('')
      setMessage(`Venta ${saleId.slice(0, 8)} confirmada. Inventario y caja actualizados.`)
      await load()
      onSaleConfirmed()
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No fue posible confirmar la venta.')
    }
  }

  return <section className="catalog-panel" aria-labelledby="sales-title">
    <h2 id="sales-title">Nueva venta</h2>
    {!cashSummary ? <p className="notice">La venta permanece bloqueada hasta que exista una caja abierta.</p> : <form className="catalog-form" onSubmit={handleConfirm}>
      <label className="field">Producto disponible<select value={variantId} onChange={(event) => handleVariantChange(event.target.value)}><option value="">Selecciona</option>{variants.map((variant) => <option key={variant.variantId} value={variant.variantId}>{variant.productName} · {variant.variantCode} · {variant.availableQuantity} disponibles</option>)}</select></label>
      <div className="catalog-price-fields"><label className="field">Cantidad<input inputMode="numeric" value={quantity} onChange={(event) => setQuantity(event.target.value)} /></label><label className="field">Precio negociado<input inputMode="decimal" value={unitPrice} onChange={(event) => setUnitPrice(event.target.value)} /></label></div>
      <button className="button button--compact" type="button" onClick={handleAddLine}>Agregar al carrito</button>
      {lines.length > 0 ? <ul className="price-history-list">{lines.map((line) => <li key={line.variantId}><strong>{line.description}</strong><span>{line.quantity} × {formatGTQ(line.unitPrice)} = {formatGTQ(multiplyMoney(line.unitPrice, line.quantity))}</span><span>Mínimo histórico al confirmar: {formatGTQ(line.minimumPrice)}</span><button className="button button--compact" type="button" onClick={() => setLines((currentLines) => currentLines.filter((currentLine) => currentLine.variantId !== line.variantId))}>Quitar</button></li>)}</ul> : <p className="muted">Busca una variante disponible y agrégala al carrito.</p>}
      <p><strong>Total: {formatGTQ(total)}</strong></p>
      {lines.some((line) => line.unitPrice < line.minimumPrice) ? <label className="field">Motivo para precio bajo mínimo<textarea value={authorizationReason} onChange={(event) => setAuthorizationReason(event.target.value)} required maxLength={300} /></label> : null}
      <label className="field">Forma de pago<select value={paymentMethod} onChange={(event) => setPaymentMethod(event.target.value as SalePaymentMethod)}><option value="cash">Efectivo</option><option value="qr">QR bancario</option><option value="transfer">Transferencia</option><option value="card">Tarjeta</option></select></label>
      <button className="button">Confirmar venta</button>
    </form>}
    {message ? <p className="notice" role="status">{message}</p> : null}
  </section>
}
