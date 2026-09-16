import { parseGTQ, serializeGTQ, type Money } from '../../../domain/money/money'
import { getSupabaseClient } from '../../../services/api/supabaseClient'

export type CashRegisterSummary = {
  businessDate: string
  cardSales: Money
  cashSales: Money
  cashSessionId: string
  expectedCash: Money
  openingFund: Money
  qrSales: Money
  saleCount: number
  transferSales: Money
}

type CashRegisterSummaryRow = {
  business_date: string
  card_sales: number | string
  cash_sales: number | string
  cash_session_id: string
  expected_cash: number | string
  opening_fund: number | string
  qr_sales: number | string
  sale_count: number | string
  transfer_sales: number | string
}

function toMoney(value: number | string): Money {
  return parseGTQ(String(value))
}

export async function getOpenCashRegisterSummary(businessId: string): Promise<CashRegisterSummary | null> {
  const { data, error } = await getSupabaseClient().rpc('get_open_cash_register_summary', {
    p_business_id: businessId,
  })

  if (error) throw new Error('No fue posible cargar el estado de caja.')
  const row = (data as CashRegisterSummaryRow[] | null)?.[0]
  if (!row) return null

  return {
    businessDate: row.business_date,
    cardSales: toMoney(row.card_sales),
    cashSales: toMoney(row.cash_sales),
    cashSessionId: row.cash_session_id,
    expectedCash: toMoney(row.expected_cash),
    openingFund: toMoney(row.opening_fund),
    qrSales: toMoney(row.qr_sales),
    saleCount: Number(row.sale_count),
    transferSales: toMoney(row.transfer_sales),
  }
}

export async function openCashRegister(
  businessId: string,
  openingFund: Money,
  notes: string,
  requestId: string,
): Promise<void> {
  const { error } = await getSupabaseClient().rpc('open_cash_register', {
    p_business_id: businessId,
    p_opening_fund: serializeGTQ(openingFund),
    p_opening_notes: notes.trim() || null,
    p_request_id: requestId,
  })

  if (error) throw new Error('No fue posible abrir la caja.')
}

export async function closeCashRegister(
  businessId: string,
  cashSessionId: string,
  countedCash: Money,
  notes: string,
  requestId: string,
): Promise<void> {
  const { error } = await getSupabaseClient().rpc('close_cash_register', {
    p_business_id: businessId,
    p_cash_session_id: cashSessionId,
    p_closing_notes: notes.trim() || null,
    p_counted_cash: serializeGTQ(countedCash),
    p_request_id: requestId,
  })

  if (error) throw new Error('No fue posible cerrar la caja.')
}
