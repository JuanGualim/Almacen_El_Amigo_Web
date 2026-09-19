import { getSupabaseClient } from '../../../services/api/supabaseClient'

export type InventoryAlertProduct = {
  lowStockCount: number
  outOfStockCount: number
  productId: string
  productName: string
  variants: Array<{ availableQuantity: number; lowStockThreshold: number; status: 'low_stock' | 'out_of_stock'; variantCode: string; variantId: string }>
}

type AlertRow = {
  low_stock_count: number | string
  out_of_stock_count: number | string
  product_id: string
  product_name: string
  variants: Array<{ available_quantity: number | string; low_stock_threshold: number | string; status: 'low_stock' | 'out_of_stock'; variant_code: string; variant_id: string }>
}

export async function getInventoryAlerts(businessId: string): Promise<InventoryAlertProduct[]> {
  const { data, error } = await getSupabaseClient().rpc('get_inventory_alerts', { p_business_id: businessId })
  if (error) throw new Error('No fue posible cargar las alertas de existencias.')
  return ((data ?? []) as AlertRow[]).map((row) => ({
    lowStockCount: Number(row.low_stock_count), outOfStockCount: Number(row.out_of_stock_count), productId: row.product_id,
    productName: row.product_name,
    variants: row.variants.map((variant) => ({
      availableQuantity: Number(variant.available_quantity), lowStockThreshold: Number(variant.low_stock_threshold),
      status: variant.status, variantCode: variant.variant_code, variantId: variant.variant_id,
    })),
  }))
}

export async function setVariantStockAlert(businessId: string, variantId: string, threshold: number, isEnabled: boolean): Promise<void> {
  const { error } = await getSupabaseClient().rpc('set_variant_stock_alert', {
    p_business_id: businessId, p_is_enabled: isEnabled, p_low_stock_threshold: threshold, p_variant_id: variantId,
  })
  if (error) throw new Error('No fue posible guardar la alerta de la variante.')
}

export async function getVariantStockAlert(businessId: string, variantId: string): Promise<{ isEnabled: boolean; threshold: number }> {
  const { data, error } = await getSupabaseClient().from('variant_stock_alert_settings')
    .select('is_enabled, low_stock_threshold')
    .eq('business_id', businessId).eq('variant_id', variantId).maybeSingle()
  if (error) throw new Error('No fue posible cargar la configuración de alerta.')
  return data
    ? { isEnabled: data.is_enabled as boolean, threshold: Number(data.low_stock_threshold) }
    : { isEnabled: true, threshold: 2 }
}
