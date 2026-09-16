import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { formatGTQ, parseGTQ } from '../../../domain/money/money'
import {
  closeCashRegister,
  getOpenCashRegisterSummary,
  openCashRegister,
  type CashRegisterSummary,
} from '../services/cashRegisterService'

type CashRegisterPanelProps = {
  businessId: string
  canOpen: boolean
  onChanged: () => void
  refreshToken: number
}

export function CashRegisterPanel({ businessId, canOpen, onChanged, refreshToken }: CashRegisterPanelProps) {
  const [summary, setSummary] = useState<CashRegisterSummary | null>(null)
  const [openingFund, setOpeningFund] = useState('')
  const [openingNotes, setOpeningNotes] = useState('')
  const [countedCash, setCountedCash] = useState('')
  const [closingNotes, setClosingNotes] = useState('')
  const [openRequestId, setOpenRequestId] = useState(() => crypto.randomUUID())
  const [closeRequestId, setCloseRequestId] = useState(() => crypto.randomUUID())
  const [message, setMessage] = useState<string | null>(null)

  const load = useCallback(async () => {
    try {
      setSummary(await getOpenCashRegisterSummary(businessId))
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No fue posible cargar la caja.')
    }
  }, [businessId])

  useEffect(() => {
    const timeoutId = window.setTimeout(() => void load(), 0)
    return () => window.clearTimeout(timeoutId)
  }, [load, refreshToken])

  async function handleOpen(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setMessage(null)
    try {
      const fund = parseGTQ(openingFund)
      if (fund < 0) throw new Error('El fondo inicial no puede ser negativo.')
      if (!window.confirm(`Abrir caja con fondo inicial de ${formatGTQ(fund)}?`)) return
      await openCashRegister(businessId, fund, openingNotes, openRequestId)
      setOpeningFund('')
      setOpeningNotes('')
      setOpenRequestId(crypto.randomUUID())
      setMessage('Caja abierta.')
      await load()
      onChanged()
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No fue posible abrir la caja.')
    }
  }

  async function handleClose(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!summary) return
    setMessage(null)
    try {
      const counted = parseGTQ(countedCash)
      const difference = counted - summary.expectedCash
      if (difference !== 0 && closingNotes.trim().length < 3) {
        throw new Error('Explica la diferencia de caja antes de cerrar.')
      }
      if (!window.confirm(`Cerrar caja con ${formatGTQ(counted)} contados?`)) return
      await closeCashRegister(businessId, summary.cashSessionId, counted, closingNotes, closeRequestId)
      setCountedCash('')
      setClosingNotes('')
      setCloseRequestId(crypto.randomUUID())
      setMessage('Caja cerrada. La diferencia quedó registrada.')
      await load()
      onChanged()
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No fue posible cerrar la caja.')
    }
  }

  return <section className="catalog-panel" aria-labelledby="cash-register-title">
    <h2 id="cash-register-title">Caja de ventas</h2>
    {!summary ? <>
      <p className="muted">No hay una caja abierta para el día comercial actual.</p>
      {canOpen ? <form className="catalog-form" onSubmit={handleOpen}>
        <label className="field">Fondo inicial<input inputMode="decimal" value={openingFund} onChange={(event) => setOpeningFund(event.target.value)} required /></label>
        <label className="field">Observaciones (opcional)<textarea value={openingNotes} onChange={(event) => setOpeningNotes(event.target.value)} maxLength={600} /></label>
        <button className="button">Abrir caja</button>
      </form> : <p className="notice">Solicita al dueño que abra la caja antes de confirmar ventas.</p>}
    </> : <>
      <p><strong>Caja abierta · {summary.businessDate}</strong></p>
      <ul className="price-history-list">
        <li><span>Fondo inicial</span><strong>{formatGTQ(summary.openingFund)}</strong></li>
        <li><span>Ventas en efectivo</span><strong>{formatGTQ(summary.cashSales)}</strong></li>
        <li><span>QR</span><strong>{formatGTQ(summary.qrSales)}</strong></li>
        <li><span>Transferencia</span><strong>{formatGTQ(summary.transferSales)}</strong></li>
        <li><span>Tarjeta</span><strong>{formatGTQ(summary.cardSales)}</strong></li>
        <li><span>Ventas confirmadas</span><strong>{summary.saleCount}</strong></li>
        <li><span>Efectivo esperado</span><strong>{formatGTQ(summary.expectedCash)}</strong></li>
      </ul>
      <form className="catalog-form" onSubmit={handleClose}>
        <h3>Cerrar caja</h3>
        <label className="field">Efectivo contado<input inputMode="decimal" value={countedCash} onChange={(event) => setCountedCash(event.target.value)} required /></label>
        <label className="field">Explicación si hay diferencia<textarea value={closingNotes} onChange={(event) => setClosingNotes(event.target.value)} maxLength={600} /></label>
        <button className="button">Cerrar caja</button>
      </form>
    </>}
    {message ? <p className="notice" role="status">{message}</p> : null}
  </section>
}
