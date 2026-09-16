import { describe, expect, it } from 'vitest'
import { moneyFromMinorUnits } from '../money/money'
import { assertValidPriceRange } from './pricing'

describe('price ranges', () => {
  it('accepts a minimum price at or below the suggested price', () => {
    expect(() => assertValidPriceRange(
      moneyFromMinorUnits(18_500),
      moneyFromMinorUnits(16_000),
    )).not.toThrow()
  })

  it('rejects a minimum price above the suggested price', () => {
    expect(() => assertValidPriceRange(
      moneyFromMinorUnits(16_000),
      moneyFromMinorUnits(18_500),
    )).toThrow('mínimo')
  })
})
