import { parseGTQ, serializeGTQ, type Money } from '../../../domain/money/money'
import { getSupabaseClient } from '../../../services/api/supabaseClient'

export type InventoryOperationVariant = {
  availableQuantity: number
  label: string
  variantId: string
}

export type OperationSupplier = { id: string; name: string }
export type OpenCashSession = { id: string; businessDate: string }
export type OperationSale = { id: string; saleNumber: string; totalAmount: Money }
export type OperationPurchase = { id: string; purchaseNumber: string; totalAmount: Money }
export type SupplierPayment = {
  amount: Money
  id: string
  supplierId: string
  status: 'pending' | 'confirmed'
}
export type DefectiveProduct = { id: string; status: 'pending_supplier' | 'delivered' | 'replaced' | 'resolved' }

type InventoryVariantRow = {
  available_quantity: number | string
  product_name: string
  variant_code: string
  variant_id: string
}

type SupplierRow = { id: string; name: string }
type CashSessionRow = { business_date: string; id: string }
type SaleRow = { id: string; sale_number: string; total_amount: number | string }
type PurchaseRow = { id: string; purchase_number: string; total_amount: number | string }
type SupplierPaymentRow = {
  amount: number | string
  id: string
  status: 'pending' | 'confirmed'
  supplier_id: string
}
type DefectiveProductRow = { id: string; status: DefectiveProduct['status'] }

function asError(error: unknown, fallback: string): Error {
  return new Error(error instanceof Error ? error.message : fallback)
}

export async function getOperationData(businessId: string, includeOwnerData: boolean): Promise<{
  cashSessions: OpenCashSession[]
  defectiveProducts: DefectiveProduct[]
  purchases: OperationPurchase[]
  sales: OperationSale[]
  suppliers: OperationSupplier[]
  supplierPayments: SupplierPayment[]
  variants: InventoryOperationVariant[]
}> {
  const client = getSupabaseClient()
  const [variantsResult, suppliersResult, sessionsResult, salesResult, purchasesResult, paymentsResult, defectivesResult] = await Promise.all([
    client.rpc('get_inventory_variants', { p_business_id: businessId, p_query: null }),
    client.from('suppliers').select('id, name').eq('business_id', businessId).eq('is_active', true).order('name'),
    client.from('cash_register_sessions').select('id, business_date').eq('business_id', businessId).eq('status', 'open'),
    includeOwnerData
      ? client.from('sales').select('id, sale_number, total_amount').eq('business_id', businessId).eq('status', 'confirmed').order('confirmed_at', { ascending: false }).limit(30)
      : Promise.resolve({ data: [], error: null }),
    includeOwnerData
      ? client.from('purchases').select('id, purchase_number, total_amount').eq('business_id', businessId).eq('status', 'confirmed').order('confirmed_at', { ascending: false }).limit(30)
      : Promise.resolve({ data: [], error: null }),
    client.from('supplier_payments').select('id, supplier_id, amount, status').eq('business_id', businessId).order('registered_at', { ascending: false }).limit(30),
    client.from('defective_products').select('id, status').eq('business_id', businessId).in('status', ['pending_supplier', 'delivered']).order('reported_at', { ascending: false }).limit(30),
  ])

  for (const result of [variantsResult, suppliersResult, sessionsResult, salesResult, purchasesResult, paymentsResult, defectivesResult]) {
    if (result.error) throw asError(result.error, 'No fue posible cargar las operaciones.')
  }

  return {
    cashSessions: ((sessionsResult.data ?? []) as CashSessionRow[]).map((row) => ({ id: row.id, businessDate: row.business_date })),
    defectiveProducts: (defectivesResult.data ?? []) as DefectiveProductRow[],
    purchases: ((purchasesResult.data ?? []) as PurchaseRow[]).map((row) => ({
      id: row.id, purchaseNumber: row.purchase_number, totalAmount: parseGTQ(String(row.total_amount)),
    })),
    sales: ((salesResult.data ?? []) as SaleRow[]).map((row) => ({
      id: row.id, saleNumber: row.sale_number, totalAmount: parseGTQ(String(row.total_amount)),
    })),
    suppliers: ((suppliersResult.data ?? []) as SupplierRow[]).map((row) => ({ id: row.id, name: row.name })),
    supplierPayments: ((paymentsResult.data ?? []) as SupplierPaymentRow[]).map((row) => ({
      amount: parseGTQ(String(row.amount)), id: row.id, status: row.status, supplierId: row.supplier_id,
    })),
    variants: ((variantsResult.data ?? []) as InventoryVariantRow[]).map((row) => ({
      availableQuantity: Number(row.available_quantity),
      label: `${row.product_name} · ${row.variant_code}`,
      variantId: row.variant_id,
    })),
  }
}

export async function recordSupplierPayment(
  businessId: string,
  supplierId: string,
  amount: Money,
  method: 'cash' | 'qr' | 'transfer' | 'card',
  reference: string,
  notes: string,
  requestId: string,
): Promise<void> {
  const { error } = await getSupabaseClient().rpc('record_general_supplier_payment', {
    p_amount: serializeGTQ(amount), p_business_id: businessId, p_method: method,
    p_notes: notes.trim() || null, p_reference: reference.trim() || null,
    p_request_id: requestId, p_supplier_id: supplierId,
  })
  if (error) throw asError(error, 'No fue posible registrar el abono.')
}

export async function confirmSupplierPayment(businessId: string, paymentId: string): Promise<void> {
  const { error } = await getSupabaseClient().rpc('confirm_general_supplier_payment', {
    p_business_id: businessId, p_payment_id: paymentId, p_request_id: crypto.randomUUID(),
  })
  if (error) throw asError(error, 'No fue posible confirmar el abono.')
}

export async function applySupplierPayment(
  businessId: string, paymentId: string, purchaseId: string, amount: Money,
): Promise<void> {
  const { error } = await getSupabaseClient().rpc('apply_supplier_payment_to_purchase', {
    p_amount: serializeGTQ(amount), p_business_id: businessId, p_purchase_id: purchaseId,
    p_request_id: crypto.randomUUID(), p_supplier_payment_id: paymentId,
  })
  if (error) throw asError(error, 'No fue posible aplicar el abono.')
}

export async function recordInventoryCount(
  businessId: string, variantId: string, countedQuantity: number, reason: string,
): Promise<void> {
  const { error } = await getSupabaseClient().rpc('record_inventory_count_difference', {
    p_business_id: businessId, p_counted_quantity: countedQuantity, p_reason: reason,
    p_request_id: crypto.randomUUID(), p_variant_id: variantId,
  })
  if (error) throw asError(error, 'No fue posible registrar el conteo.')
}

export async function recordAuthorizedExit(
  businessId: string, variantId: string, quantity: number, reason: string,
): Promise<void> {
  const { error } = await getSupabaseClient().rpc('record_authorized_exit', {
    p_business_id: businessId, p_quantity: quantity, p_reason: reason,
    p_request_id: crypto.randomUUID(), p_variant_id: variantId,
  })
  if (error) throw asError(error, 'No fue posible registrar la salida.')
}

export async function reportDefectiveProduct(
  businessId: string, variantId: string, supplierId: string, quantity: number, description: string,
): Promise<void> {
  const { error } = await getSupabaseClient().rpc('report_defective_product', {
    p_business_id: businessId, p_description: description, p_quantity: quantity,
    p_request_id: crypto.randomUUID(), p_supplier_id: supplierId || null, p_variant_id: variantId,
  })
  if (error) throw asError(error, 'No fue posible reportar el producto defectuoso.')
}

export async function deliverDefectiveProduct(businessId: string, defectiveProductId: string): Promise<void> {
  const { error } = await getSupabaseClient().rpc('deliver_defective_product', {
    p_business_id: businessId, p_defective_product_id: defectiveProductId, p_request_id: crypto.randomUUID(),
  })
  if (error) throw asError(error, 'No fue posible registrar la entrega al distribuidor.')
}

export async function replaceDefectiveProduct(businessId: string, defectiveProductId: string): Promise<void> {
  const { error } = await getSupabaseClient().rpc('replace_defective_product', {
    p_business_id: businessId, p_defective_product_id: defectiveProductId, p_request_id: crypto.randomUUID(),
  })
  if (error) throw asError(error, 'No fue posible registrar el reemplazo.')
}

export async function cancelSale(businessId: string, saleId: string, cashSessionId: string, reason: string): Promise<void> {
  const { error } = await getSupabaseClient().rpc('cancel_sale', {
    p_business_id: businessId, p_cash_session_id: cashSessionId, p_reason: reason,
    p_request_id: crypto.randomUUID(), p_sale_id: saleId,
  })
  if (error) throw asError(error, 'No fue posible cancelar la venta.')
}

export async function cancelPurchase(businessId: string, purchaseId: string, reason: string): Promise<void> {
  const { error } = await getSupabaseClient().rpc('cancel_purchase', {
    p_business_id: businessId, p_purchase_id: purchaseId, p_reason: reason, p_request_id: crypto.randomUUID(),
  })
  if (error) throw asError(error, 'No fue posible cancelar la compra.')
}

export async function recordProductExchange(
  businessId: string,
  cashSessionId: string,
  originalSaleId: string,
  receivedVariantId: string,
  receivedQuantity: number,
  deliveredVariantId: string,
  deliveredQuantity: number,
  recognizedUnitValue: Money | null,
  paymentMethod: 'cash' | 'qr' | 'transfer' | 'card' | '',
  reason: string,
): Promise<void> {
  const { error } = await getSupabaseClient().rpc('record_product_exchange', {
    p_business_id: businessId, p_cash_session_id: cashSessionId || null,
    p_delivered_quantity: deliveredQuantity, p_delivered_variant_id: deliveredVariantId,
    p_original_sale_id: originalSaleId || null, p_payment_method: paymentMethod || null,
    p_reason: reason, p_received_quantity: receivedQuantity, p_received_variant_id: receivedVariantId,
    p_recognized_unit_value: recognizedUnitValue === null ? null : serializeGTQ(recognizedUnitValue),
    p_request_id: crypto.randomUUID(),
  })
  if (error) throw asError(error, 'No fue posible registrar el cambio.')
}
