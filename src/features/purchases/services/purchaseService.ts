import { parseGTQ, serializeGTQ, type Money } from '../../../domain/money/money'
import { getSupabaseClient } from '../../../services/api/supabaseClient'

export type Supplier = { id: string; name: string }
export type PendingPurchase = { id: string; purchaseNumber: string; totalAmount: Money }
export type PurchasePaymentType = 'cash' | 'credit' | 'partial'
export type PurchaseLineInput = { variantId: string; quantity: number; unitCost: Money }
export type InventoryVariant = {
  availableQuantity: number
  productName: string
  variantCode: string
}

type InventoryVariantRow = {
  available_quantity: number | string
  product_name: string
  variant_code: string
}

export async function getSuppliers(businessId: string): Promise<Supplier[]> {
  const { data, error } = await getSupabaseClient()
    .from('suppliers')
    .select('id, name')
    .eq('business_id', businessId)
    .eq('is_active', true)
    .order('name')
  if (error) throw new Error('No fue posible cargar los distribuidores.')
  return (data ?? []) as Supplier[]
}

export async function createSupplier(businessId: string, name: string): Promise<void> {
  const { error } = await getSupabaseClient().rpc('create_supplier', {
    p_business_id: businessId, p_name: name,
  })
  if (error) throw new Error('No fue posible crear el distribuidor.')
}

export async function recordPurchase(
  businessId: string,
  supplierId: string,
  paymentType: PurchasePaymentType,
  initialPayment: Money,
  lines: readonly PurchaseLineInput[],
  requestId: string,
  invoiceNumber: string,
  purchasedAt: string,
): Promise<string> {
  const { data, error } = await getSupabaseClient().rpc('record_purchase', {
    p_business_id: businessId,
    p_initial_payment_amount: serializeGTQ(initialPayment),
    p_invoice_number: invoiceNumber.trim() || null,
    p_lines: lines.map((line) => ({
      quantity: line.quantity,
      unit_cost: serializeGTQ(line.unitCost),
      variant_id: line.variantId,
    })),
    p_payment_type: paymentType,
    p_purchased_at: purchasedAt,
    p_request_id: requestId,
    p_supplier_id: supplierId,
  })
  if (error || typeof data !== 'string') throw new Error('No fue posible registrar la compra.')
  return data
}

export async function getPendingPurchases(businessId: string): Promise<PendingPurchase[]> {
  const { data, error } = await getSupabaseClient().from('purchases')
    .select('id, purchase_number, total_amount')
    .eq('business_id', businessId)
    .eq('status', 'pending_confirmation')
    .order('created_at')
  if (error) throw new Error('No fue posible cargar las compras pendientes.')
  return (data ?? []).map((row) => ({
    id: row.id as string, purchaseNumber: row.purchase_number as string,
    totalAmount: parseGTQ(String(row.total_amount)),
  }))
}

export async function confirmPurchase(businessId: string, purchaseId: string): Promise<void> {
  const { error } = await getSupabaseClient().rpc('confirm_purchase', {
    p_business_id: businessId, p_purchase_id: purchaseId, p_request_id: crypto.randomUUID(),
  })
  if (error) throw new Error('No fue posible confirmar la compra.')
}

export async function getInventoryVariants(businessId: string): Promise<InventoryVariant[]> {
  const { data, error } = await getSupabaseClient().rpc('get_inventory_variants', {
    p_business_id: businessId,
    p_query: null,
  })

  if (error) throw new Error('No fue posible cargar las existencias.')

  return ((data ?? []) as InventoryVariantRow[]).map((row) => ({
    availableQuantity: Number(row.available_quantity),
    productName: row.product_name,
    variantCode: row.variant_code,
  }))
}
