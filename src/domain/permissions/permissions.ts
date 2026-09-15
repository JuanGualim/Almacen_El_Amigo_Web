export const PERMISSIONS = [
  'business.manage',
  'memberships.manage',
  'catalog.read',
  'catalog.manage',
  'pricing.read',
  'pricing.manage',
  'inventory.read',
  'inventory.adjust',
  'sales.create',
  'sales.authorize_below_minimum',
  'purchases.create',
  'purchases.confirm',
  'suppliers.read',
  'payables.read',
  'payables.manage',
  'cash_register.open',
  'cash_register.close',
  'reports.read_sensitive',
  'audit.read',
  'files.upload',
] as const

export type Permission = (typeof PERMISSIONS)[number]

export type BusinessRoleCode = 'owner' | 'employee'

export const EMPLOYEE_DEFAULT_PERMISSIONS: readonly Permission[] = [
  'catalog.read',
  'pricing.read',
  'inventory.read',
  'sales.create',
  'purchases.create',
  'suppliers.read',
  'cash_register.close',
  'files.upload',
]

export function canAccess(permission: Permission, grantedPermissions: readonly Permission[]): boolean {
  return grantedPermissions.includes(permission)
}
