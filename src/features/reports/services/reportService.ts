import { parseGTQ, type Money } from '../../../domain/money/money'
import { getSupabaseClient } from '../../../services/api/supabaseClient'

export type OperationalReport = {
  purchasesBySupplier: Array<{ purchasesAmount: Money; purchasesCount: number; supplierName: string }>
  salesByDay: Array<{ businessDate: string; salesAmount: Money; salesCount: number }>
  salesByPaymentMethod: Array<{ paymentMethod: string; salesAmount: Money; salesCount: number }>
  summary: {
    cashDifferenceAmount: Money
    openSupplierBalance: Money
    purchasesAmount: Money
    purchasesCount: number
    salesAmount: Money
    salesCount: number
  }
  topSoldVariants: Array<{ productName: string; quantity: number; salesAmount: Money; variantCode: string }>
}

type JsonRecord = Record<string, unknown>

function record(value: unknown, label: string): JsonRecord {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error(`El reporte recibió ${label} inválido.`)
  return value as JsonRecord
}

function list(value: unknown, label: string): unknown[] {
  if (!Array.isArray(value)) throw new Error(`El reporte recibió ${label} inválido.`)
  return value
}

function string(value: unknown, label: string): string {
  if (typeof value !== 'string' || !value) throw new Error(`El reporte recibió ${label} inválido.`)
  return value
}

function count(value: unknown, label: string): number {
  const parsed = Number(value)
  if (!Number.isSafeInteger(parsed) || parsed < 0) throw new Error(`El reporte recibió ${label} inválido.`)
  return parsed
}

function money(value: unknown, label: string): Money {
  if ((typeof value !== 'string' && typeof value !== 'number') || !Number.isFinite(Number(value))) {
    throw new Error(`El reporte recibió ${label} inválido.`)
  }
  return parseGTQ(String(value))
}

function parseReport(value: unknown): OperationalReport {
  const payload = record(value, 'datos')
  const summary = record(payload.summary, 'resumen')
  return {
    purchasesBySupplier: list(payload.purchases_by_supplier, 'compras por distribuidor').map((value) => {
      const item = record(value, 'compra por distribuidor')
      return {
        purchasesAmount: money(item.purchases_amount, 'importe de compra'),
        purchasesCount: count(item.purchases_count, 'cantidad de compras'),
        supplierName: string(item.supplier_name, 'distribuidor'),
      }
    }),
    salesByDay: list(payload.sales_by_day, 'ventas por día').map((value) => {
      const item = record(value, 'venta por día')
      return {
        businessDate: string(item.date, 'fecha'),
        salesAmount: money(item.sales_amount, 'importe de venta'),
        salesCount: count(item.sales_count, 'cantidad de ventas'),
      }
    }),
    salesByPaymentMethod: list(payload.sales_by_payment_method, 'ventas por forma de pago').map((value) => {
      const item = record(value, 'venta por forma de pago')
      return {
        paymentMethod: string(item.payment_method, 'forma de pago'),
        salesAmount: money(item.sales_amount, 'importe por forma de pago'),
        salesCount: count(item.sales_count, 'cantidad por forma de pago'),
      }
    }),
    summary: {
      cashDifferenceAmount: money(summary.cash_difference_amount, 'diferencia de caja'),
      openSupplierBalance: money(summary.open_supplier_balance, 'saldo de distribuidores'),
      purchasesAmount: money(summary.purchases_amount, 'importe de compras'),
      purchasesCount: count(summary.purchases_count, 'cantidad de compras'),
      salesAmount: money(summary.sales_amount, 'importe de ventas'),
      salesCount: count(summary.sales_count, 'cantidad de ventas'),
    },
    topSoldVariants: list(payload.top_sold_variants, 'variantes vendidas').map((value) => {
      const item = record(value, 'variante vendida')
      return {
        productName: string(item.product_name, 'producto'),
        quantity: count(item.quantity, 'cantidad vendida'),
        salesAmount: money(item.sales_amount, 'importe por variante'),
        variantCode: string(item.variant_code, 'variante'),
      }
    }),
  }
}

export async function getOperationalReport(
  businessId: string,
  startDate: string,
  endDate: string,
): Promise<OperationalReport> {
  const { data, error } = await getSupabaseClient().rpc('get_operational_report', {
    p_business_id: businessId,
    p_end_date: endDate,
    p_start_date: startDate,
  })
  if (error) throw new Error('No fue posible cargar el reporte operativo.')
  return parseReport(data)
}
