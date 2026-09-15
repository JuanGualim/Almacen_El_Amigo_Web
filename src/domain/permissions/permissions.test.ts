import { describe, expect, it } from 'vitest'
import { canAccess, EMPLOYEE_DEFAULT_PERMISSIONS } from './permissions'

describe('employee default permissions', () => {
  it('allows the documented sales flow but not sensitive supplier balances', () => {
    expect(canAccess('sales.create', EMPLOYEE_DEFAULT_PERMISSIONS)).toBe(true)
    expect(canAccess('payables.read', EMPLOYEE_DEFAULT_PERMISSIONS)).toBe(false)
    expect(canAccess('pricing.manage', EMPLOYEE_DEFAULT_PERMISSIONS)).toBe(false)
  })
})
