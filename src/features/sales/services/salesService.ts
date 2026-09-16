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

export type PendingSaleAuthorization = { id: string; reason: string; requestedAt: string }

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

export async function requestSalePriceAuthorization(businessId: string, lines: readonly SaleLineInput[], reason: string, requestId: string): Promise<string> {
  const { data, error } = await getSupabaseClient().rpc('request_sale_price_authorization', {
    p_business_id: businessId,
    p_lines: lines.map((line) => ({ quantity: line.quantity, unit_price: serializeGTQ(line.unitPrice), variant_id: line.variantId })),
    p_reason: reason,
    p_request_id: requestId,
  })
  if (error || typeof data !== 'string') throw new Error('No fue posible solicitar la autorización.')
  return data
}

export async function confirmSaleWithPriceAuthorization(businessId: string, cashSessionId: string, paymentMethod: SalePaymentMethod, lines: readonly SaleLineInput[], requestId: string, authorizationId: string): Promise<string> {
  const { data, error } = await getSupabaseClient().rpc('confirm_sale_with_price_authorization', {
    p_authorization_id: authorizationId,
    p_business_id: businessId,
    p_cash_session_id: cashSessionId,
    p_lines: lines.map((line) => ({ quantity: line.quantity, unit_price: serializeGTQ(line.unitPrice), variant_id: line.variantId })),
    p_payment_method: paymentMethod,
    p_request_id: requestId,
  })
  if (error || typeof data !== 'string') throw new Error('La autorización no pudo aplicarse a la venta.')
  return data
}

export async function getPendingSaleAuthorizations(businessId: string): Promise<PendingSaleAuthorization[]> {
  const { data, error } = await getSupabaseClient().from('sale_price_authorizations').select('id, reason, requested_at').eq('business_id', businessId).eq('status', 'pending').order('requested_at')
  if (error) throw new Error('No fue posible cargar solicitudes de autorización.')
  return (data ?? []).map((row) => ({ id: row.id as string, reason: row.reason as string, requestedAt: row.requested_at as string }))
}

export async function setOwnerAuthorizationPin(businessId: string, pin: string, confirmation: string): Promise<void> {
  const { error } = await getSupabaseClient().rpc('set_owner_authorization_pin', { p_business_id: businessId, p_confirmation: confirmation, p_pin: pin })
  if (error) throw new Error('No fue posible guardar el PIN.')
}

export async function approveSalePriceAuthorization(businessId: string, authorizationId: string, pin: string): Promise<boolean> {
  const { data, error } = await getSupabaseClient().rpc('approve_sale_price_authorization', { p_authorization_id: authorizationId, p_business_id: businessId, p_pin: pin })
  if (error || typeof data !== 'boolean') throw new Error('No fue posible aprobar la solicitud.')
  return data
}
