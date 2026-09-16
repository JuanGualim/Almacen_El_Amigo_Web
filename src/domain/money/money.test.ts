import { describe, expect, it } from 'vitest'
import { addMoney, formatGTQ, moneyFromMinorUnits, multiplyMoney, parseGTQ, serializeGTQ } from './money'

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

  it('serializes money for PostgreSQL without floating point conversion', () => {
    expect(serializeGTQ(moneyFromMinorUnits(18_575))).toBe('185.75')
  })

  it('multiplies money by an integer quantity without floating point arithmetic', () => {
    expect(multiplyMoney(moneyFromMinorUnits(8_075), 3)).toBe(24_225)
    expect(() => multiplyMoney(moneyFromMinorUnits(100), 1.5)).toThrow('entero')
  })
})
