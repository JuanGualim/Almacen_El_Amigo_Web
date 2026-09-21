import { parseGTQ, type Money } from '../../../domain/money/money'

export type InitialInventoryCsvRow = {
  quantity: number
  sourceLine: number
  unitCost: Money | null
  variantCode: string
}

export const INITIAL_INVENTORY_TEMPLATE = 'variant_code,quantity,unit_cost\nALM-000001-001,4,70.00\n'

function parseCsv(value: string): string[][] {
  const rows: string[][] = []
  let currentField = ''
  let currentRow: string[] = []
  let inQuotes = false

  for (let index = 0; index < value.length; index += 1) {
    const character = value[index]
    const nextCharacter = value[index + 1]

    if (character === '"') {
      if (inQuotes && nextCharacter === '"') {
        currentField += '"'
        index += 1
      } else {
        inQuotes = !inQuotes
      }
      continue
    }

    if (character === ',' && !inQuotes) {
      currentRow.push(currentField)
      currentField = ''
      continue
    }

    if (character === '\n' && !inQuotes) {
      currentRow.push(currentField)
      rows.push(currentRow)
      currentField = ''
      currentRow = []
      continue
    }

    if (character !== '\r') currentField += character
  }

  if (inQuotes) throw new Error('El CSV contiene una comilla sin cerrar.')

  if (currentField || currentRow.length > 0) {
    currentRow.push(currentField)
    rows.push(currentRow)
  }

  return rows.filter((row) => row.some((cell) => cell.trim() !== ''))
}

function normalizedHeader(value: string): string {
  return value.trim().replace(/^\uFEFF/, '').toLowerCase()
}

function normalizedCode(value: string): string {
  return value.trim().toUpperCase()
}

export function parseInitialInventoryCsv(value: string): InitialInventoryCsvRow[] {
  const rows = parseCsv(value)
  if (rows.length < 2) throw new Error('El CSV debe incluir encabezados y al menos una línea de inventario.')

  const headers = rows[0].map(normalizedHeader)
  const codeIndex = headers.indexOf('variant_code')
  const quantityIndex = headers.indexOf('quantity')
  const unitCostIndex = headers.indexOf('unit_cost')

  if (codeIndex < 0 || quantityIndex < 0 || unitCostIndex < 0) {
    throw new Error('El CSV debe incluir las columnas variant_code, quantity y unit_cost.')
  }

  const requiredLastIndex = Math.max(codeIndex, quantityIndex, unitCostIndex)
  const rowsByCode = new Set<string>()

  return rows.slice(1).map((row, index) => {
    const sourceLine = index + 2
    if (row.length <= requiredLastIndex) throw new Error(`Faltan datos en la línea ${sourceLine}.`)

    const variantCode = normalizedCode(row[codeIndex])
    if (!variantCode) throw new Error(`Indica el código de variante en la línea ${sourceLine}.`)
    if (rowsByCode.has(variantCode)) throw new Error(`La variante ${variantCode} está repetida en el CSV.`)
    rowsByCode.add(variantCode)

    const quantityValue = row[quantityIndex].trim()
    if (!/^[1-9][0-9]*$/.test(quantityValue)) {
      throw new Error(`La cantidad de la línea ${sourceLine} debe ser un entero positivo.`)
    }
    const quantity = Number(quantityValue)
    if (!Number.isSafeInteger(quantity)) throw new Error(`La cantidad de la línea ${sourceLine} es demasiado grande.`)

    const rawUnitCost = row[unitCostIndex].trim()
    let unitCost: Money | null = null
    if (rawUnitCost) {
      unitCost = parseGTQ(rawUnitCost)
      if (unitCost < 0) throw new Error(`El costo de la línea ${sourceLine} no puede ser negativo.`)
    }

    return { quantity, sourceLine, unitCost, variantCode }
  })
}
