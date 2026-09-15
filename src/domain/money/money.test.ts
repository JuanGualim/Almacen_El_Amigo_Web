import { describe, expect, it } from 'vitest'
import { addMoney, formatGTQ, moneyFromMinorUnits, parseGTQ } from './money'

describe('money', () => {
  it('parses GTQ without floating point arithmetic', () => {
    expect(parseGTQ('Q 185.25')).toBe(18_525)
    expect(parseGTQ('0.5')).toBe(50)
  })

  it('rejects more than two decimal places', () => {
    expect(() => parseGTQ('10.999')).toThrow('hasta dos decimales')
  })

  it('adds and formats exact minor units', () => {
    expect(addMoney(moneyFromMinorUnits(10), moneyFromMinorUnits(20))).toBe(30)
    expect(formatGTQ(moneyFromMinorUnits(18_525))).toContain('185.25')
  })
})
