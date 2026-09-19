import { parseGTQ, type Money } from '../../../domain/money/money'
import { getSupabaseClient } from '../../../services/api/supabaseClient'

export type OperationalDashboard = {
  businessDate: string
  openCashSession: { businessDate: string; id: string; openingFund: Money } | null
  pendingDefectiveProducts: number | null
  pendingDefectiveResolutions: number | null
  pendingInventoryAdjustments: number | null
  pendingPriceReviews: number | null
  pendingSaleAuthorizations: number | null
  pendingSupplierPayments: number | null
  sensitiveSummary: {
    openSupplierBalance: Money
    todaySalesAmount: Money
    todaySalesCount: number
  } | null
}

type DashboardRecord = Record<string, unknown>

function objectValue(value: unknown, label: string): DashboardRecord {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`El panel operativo recibió ${label} inválido.`)
  }
  return value as DashboardRecord
}

function stringValue(value: unknown, label: string): string {
  if (typeof value !== 'string' || !value) throw new Error(`El panel operativo recibió ${label} inválido.`)
  return value
}

function countValue(value: unknown, label: string): number | null {
  if (value === null) return null
  const parsed = Number(value)
  if (!Number.isSafeInteger(parsed) || parsed < 0) throw new Error(`El panel operativo recibió ${label} inválido.`)
  return parsed
}

function moneyValue(value: unknown, label: string): Money {
  if ((typeof value !== 'string' && typeof value !== 'number') || !Number.isFinite(Number(value))) {
    throw new Error(`El panel operativo recibió ${label} inválido.`)
  }
  return parseGTQ(String(value))
}

function parseDashboard(value: unknown): OperationalDashboard {
  const payload = objectValue(value, 'datos')
  const openCashSessionValue = payload.open_cash_session
  const sensitiveSummaryValue = payload.sensitive_summary
  const openCashSession = openCashSessionValue === null
    ? null
    : (() => {
        const session = objectValue(openCashSessionValue, 'caja abierta')
        return {
          businessDate: stringValue(session.business_date, 'fecha de caja'),
          id: stringValue(session.id, 'identificador de caja'),
          openingFund: moneyValue(session.opening_fund, 'fondo inicial'),
        }
      })()
  const sensitiveSummary = sensitiveSummaryValue === null
    ? null
    : (() => {
        const summary = objectValue(sensitiveSummaryValue, 'resumen sensible')
        return {
          openSupplierBalance: moneyValue(summary.open_supplier_balance, 'saldo de distribuidores'),
          todaySalesAmount: moneyValue(summary.today_sales_amount, 'ventas del día'),
          todaySalesCount: countValue(summary.today_sales_count, 'cantidad de ventas') ?? 0,
        }
      })()

  return {
    businessDate: stringValue(payload.business_date, 'fecha comercial'),
    openCashSession,
    pendingDefectiveProducts: countValue(payload.pending_defective_products, 'defectuosos pendientes'),
    pendingDefectiveResolutions: countValue(payload.pending_defective_resolutions, 'resoluciones pendientes'),
    pendingInventoryAdjustments: countValue(payload.pending_inventory_adjustments, 'ajustes pendientes'),
    pendingPriceReviews: countValue(payload.pending_price_reviews, 'revisiones de precio pendientes'),
    pendingSaleAuthorizations: countValue(payload.pending_sale_authorizations, 'autorizaciones pendientes'),
    pendingSupplierPayments: countValue(payload.pending_supplier_payments, 'abonos pendientes'),
    sensitiveSummary,
  }
}

export async function getOperationalDashboard(businessId: string): Promise<OperationalDashboard> {
  const { data, error } = await getSupabaseClient().rpc('get_operational_dashboard', {
    p_business_id: businessId,
  })

  if (error) throw new Error('No fue posible cargar el inicio operativo.')
  return parseDashboard(data)
}
