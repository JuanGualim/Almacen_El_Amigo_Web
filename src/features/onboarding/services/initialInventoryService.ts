import { serializeGTQ, type Money } from '../../../domain/money/money'
import { getSupabaseClient } from '../../../services/api/supabaseClient'

export type InitialInventoryImportLine = {
  quantity: number
  unitCost: Money | null
  variantId: string
}

export type InitialInventoryImportSummary = {
  id: string
  importedAt: string
  lineCount: number
  reason: string
}

type InitialInventoryImportRow = {
  id: string
  imported_at: string
  line_count: number
  reason: string
}

export async function getInitialInventoryImport(
  businessId: string,
): Promise<InitialInventoryImportSummary | null> {
  const { data, error } = await getSupabaseClient()
    .from('initial_inventory_imports')
    .select('id, imported_at, line_count, reason')
    .eq('business_id', businessId)
    .maybeSingle()

  if (error) {
    throw new Error('No fue posible consultar el estado de la carga inicial.')
  }

  if (!data) return null

  const row = data as InitialInventoryImportRow
  return {
    id: row.id,
    importedAt: row.imported_at,
    lineCount: row.line_count,
    reason: row.reason,
  }
}

export async function importInitialInventory(
  businessId: string,
  lines: InitialInventoryImportLine[],
  reason: string,
  requestId: string,
): Promise<string> {
  const { data, error } = await getSupabaseClient().rpc('import_initial_inventory', {
    p_business_id: businessId,
    p_lines: lines.map((line) => ({
      quantity: line.quantity,
      unit_cost: line.unitCost === null ? null : serializeGTQ(line.unitCost),
      variant_id: line.variantId,
    })),
    p_reason: reason.trim(),
    p_request_id: requestId,
  })

  if (error || typeof data !== 'string') {
    throw new Error(error?.message || 'No fue posible confirmar la carga inicial.')
  }

  return data
}
