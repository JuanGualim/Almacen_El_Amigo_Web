import {
  formatCatalogAttributes,
  type CatalogAttributes,
} from '../../../domain/catalog/attributes'
import {
  parseGTQ,
  serializeGTQ,
  type Money,
} from '../../../domain/money/money'
import { assertValidPriceRange } from '../../../domain/pricing/pricing'
import { getSupabaseClient } from '../../../services/api/supabaseClient'

export type CatalogVariant = {
  attributes: CatalogAttributes
  brandName: string | null
  categoryName: string
  minimumPrice: Money | null
  productCode: string
  productId: string
  productName: string
  suggestedPrice: Money | null
  variantCode: string
  variantId: string
}

export type NewCatalogProduct = {
  attributes: CatalogAttributes
  brandName: string
  categoryName: string
  minimumPrice: Money
  productName: string
  suggestedPrice: Money
}

export type VariantPriceHistoryEntry = {
  amount: Money
  changedAt: string
  kind: 'minimum' | 'suggested'
  reason: string | null
}

type CatalogVariantRow = {
  attributes: CatalogAttributes
  brand_name: string | null
  category_name: string
  minimum_price: string | number | null
  product_code: string
  product_id: string
  product_name: string
  suggested_price: string | number | null
  variant_code: string
  variant_id: string
}

function parseDatabaseMoney(value: string | number | null): Money | null {
  return value === null ? null : parseGTQ(String(value))
}

function mapCatalogVariant(row: CatalogVariantRow): CatalogVariant {
  return {
    attributes: row.attributes,
    brandName: row.brand_name,
    categoryName: row.category_name,
    minimumPrice: parseDatabaseMoney(row.minimum_price),
    productCode: row.product_code,
    productId: row.product_id,
    productName: row.product_name,
    suggestedPrice: parseDatabaseMoney(row.suggested_price),
    variantCode: row.variant_code,
    variantId: row.variant_id,
  }
}

export function getVariantDescription(variant: CatalogVariant): string {
  return formatCatalogAttributes(variant.attributes) || 'Sin atributos adicionales'
}

export async function getCatalogVariants(
  businessId: string,
  query: string,
): Promise<CatalogVariant[]> {
  const { data, error } = await getSupabaseClient().rpc('get_catalog_variants', {
    p_business_id: businessId,
    p_query: query.trim() || null,
  })

  if (error) {
    throw new Error('No fue posible cargar el catálogo de este negocio.')
  }

  return ((data ?? []) as CatalogVariantRow[]).map(mapCatalogVariant)
}

export async function createCatalogProduct(
  businessId: string,
  product: NewCatalogProduct,
): Promise<void> {
  assertValidPriceRange(product.suggestedPrice, product.minimumPrice)

  const { error } = await getSupabaseClient().rpc('create_catalog_product', {
    p_brand_name: product.brandName,
    p_business_id: businessId,
    p_category_name: product.categoryName,
    p_minimum_price: serializeGTQ(product.minimumPrice),
    p_product_details: {},
    p_product_name: product.productName,
    p_suggested_price: serializeGTQ(product.suggestedPrice),
    p_variant_attributes: product.attributes,
  })

  if (error) {
    throw new Error('No fue posible crear el producto. Revisa los datos e inténtalo de nuevo.')
  }
}

export async function createCatalogVariant(
  businessId: string,
  productId: string,
  attributes: CatalogAttributes,
  suggestedPrice: Money,
  minimumPrice: Money,
): Promise<void> {
  assertValidPriceRange(suggestedPrice, minimumPrice)

  const { error } = await getSupabaseClient().rpc('create_product_variant', {
    p_attributes: attributes,
    p_business_id: businessId,
    p_minimum_price: serializeGTQ(minimumPrice),
    p_product_id: productId,
    p_suggested_price: serializeGTQ(suggestedPrice),
  })

  if (error) {
    throw new Error('No fue posible crear la variante. Verifica que no esté repetida.')
  }
}

export async function updateCatalogVariantPrices(
  businessId: string,
  variantId: string,
  suggestedPrice: Money,
  minimumPrice: Money,
  reason: string,
): Promise<void> {
  assertValidPriceRange(suggestedPrice, minimumPrice)

  const { error } = await getSupabaseClient().rpc('update_variant_prices', {
    p_business_id: businessId,
    p_minimum_price: serializeGTQ(minimumPrice),
    p_reason: reason,
    p_suggested_price: serializeGTQ(suggestedPrice),
    p_variant_id: variantId,
  })

  if (error) {
    throw new Error('No fue posible actualizar los precios. Inténtalo de nuevo.')
  }
}

export async function getVariantPriceHistory(variantId: string): Promise<VariantPriceHistoryEntry[]> {
  const { data, error } = await getSupabaseClient()
    .from('variant_price_history')
    .select('amount, changed_at, price_kind, reason')
    .eq('variant_id', variantId)
    .order('changed_at', { ascending: false })

  if (error) {
    throw new Error('No fue posible cargar el historial de precios.')
  }

  return (data ?? []).map((entry) => {
    const row = entry as {
      amount: string | number
      changed_at: string
      price_kind: VariantPriceHistoryEntry['kind']
      reason: string | null
    }

    return {
      amount: parseGTQ(String(row.amount)),
      changedAt: row.changed_at,
      kind: row.price_kind,
      reason: row.reason,
    }
  })
}
