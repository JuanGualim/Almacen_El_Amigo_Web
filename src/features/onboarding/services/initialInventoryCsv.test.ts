import { describe, expect, it } from 'vitest'
import { parseInitialInventoryCsv } from './initialInventoryCsv'

describe('initial inventory CSV', () => {
  it('parses verified quantities and optional known costs without floating point values', () => {
    expect(parseInitialInventoryCsv('variant_code,quantity,unit_cost\nALM-000001-001,4,70.25\nALM-000001-002,2,\n')).toEqual([
      { variantCode: 'ALM-000001-001', quantity: 4, unitCost: 7025, sourceLine: 2 },
      { variantCode: 'ALM-000001-002', quantity: 2, unitCost: null, sourceLine: 3 },
    ])
  })

  it('rejects duplicate variants and non-integer quantities before calling the server', () => {
    expect(() => parseInitialInventoryCsv('variant_code,quantity,unit_cost\nALM-1,2,10\nALM-1,1,10\n')).toThrow('repetida')
    expect(() => parseInitialInventoryCsv('variant_code,quantity,unit_cost\nALM-1,1.5,10\n')).toThrow('entero positivo')
  })
})
