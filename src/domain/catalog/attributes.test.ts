import { describe, expect, it } from 'vitest'
import { formatCatalogAttributes, parseCatalogAttributes } from './attributes'

describe('catalog attributes', () => {
  it('parses flexible attributes and normalizes duplicate keys', () => {
    expect(parseCatalogAttributes('Color: Blanca\nTalla: 15')).toEqual({
      color: 'Blanca',
      talla: '15',
    })
  })

  it('rejects malformed or duplicated attributes', () => {
    expect(() => parseCatalogAttributes('Color blanca')).toThrow('Nombre: valor')
    expect(() => parseCatalogAttributes('Color: Blanca\ncolor: Negra')).toThrow('repetido')
  })

  it('formats attributes for a compact catalog card', () => {
    expect(formatCatalogAttributes({ color: 'Blanca', talla: '15' })).toBe('color: Blanca · talla: 15')
  })
})
