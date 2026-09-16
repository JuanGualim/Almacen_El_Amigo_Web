import { parseGTQ, serializeGTQ, type Money } from '../../../domain/money/money'
import type { CatalogAttributes } from '../../../domain/catalog/attributes'
import { getSupabaseClient } from '../../../services/api/supabaseClient'

export type SalePaymentMethod = 'cash' | 'qr' | 'transfer' | 'card'

export type SellableVariant = {
  attributes: CatalogAttributes
  availableQuantity: number
  minimumPrice: Money
  productName: string
  suggestedPrice: Money
  variantCode: string
  variantId: string
}

export type SaleLineInput = {
  quantity: number
  unitPrice: Money
  variantId: string
}

type SellableVariantRow = {
  attributes: CatalogAttributes
  available_quantity: number | string
  minimum_price: number | string | null
  product_name: string
  suggested_price: number | string | null
  variant_code: string
  variant_id: string
}

export async function getSellableVariants(businessId: string): Promise<SellableVariant[]> {
  const { data, error } = await getSupabaseClient().rpc('get_inventory_variants', {
    p_business_id: businessId,
    p_query: null,
  })

  if (error) throw new Error('No fue posible cargar el inventario disponible para vender.')

  return ((data ?? []) as SellableVariantRow[]).flatMap((row) => {
    const availableQuantity = Number(row.available_quantity)
    if (!Number.isSafeInteger(availableQuantity) || availableQuantity <= 0 || row.suggested_price === null || row.minimum_price === null) {
      return []
    }

    return [{
      attributes: row.attributes,
      availableQuantity,
      minimumPrice: parseGTQ(String(row.minimum_price)),
      productName: row.product_name,
      suggestedPrice: parseGTQ(String(row.suggested_price)),
      variantCode: row.variant_code,
      variantId: row.variant_id,
    }]
  })
}

export async function confirmSale(
  businessId: string,
  cashSessionId: string,
  paymentMethod: SalePaymentMethod,
  lines: readonly SaleLineInput[],
  requestId: string,
): Promise<string> {
  const { data, error } = await getSupabaseClient().rpc('confirm_sale', {
    p_business_id: businessId,
    p_cash_session_id: cashSessionId,
    p_lines: lines.map((line) => ({
      quantity: line.quantity,
      unit_price: serializeGTQ(line.unitPrice),
      variant_id: line.variantId,
    })),
    p_payment_method: paymentMethod,
    p_request_id: requestId,
  })

  if (error || typeof data !== 'string') throw new Error('No fue posible confirmar la venta.')
  return data
}
