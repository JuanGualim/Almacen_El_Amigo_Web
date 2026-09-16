import { getSupabaseClient } from '../../../services/api/supabaseClient'

export type BusinessMembership = {
  businessId: string
  businessName: string
  currencyCode: string
  roleCode: 'owner' | 'employee'
  timezone: string
  roleName: string
}

type MembershipRow = {
  business_id: string
  businesses: RelatedRow<{
    currency_code: string
    name: string
    timezone: string
  }>
  business_roles: RelatedRow<{
    code: 'owner' | 'employee'
    name: string
  }>
}

type RelatedRow<T> = T | readonly T[] | null

function isRelatedRows<T>(relation: RelatedRow<T>): relation is readonly T[] {
  return Array.isArray(relation)
}

function firstRelatedRow<T>(relation: RelatedRow<T>): T | null {
  if (isRelatedRows(relation)) {
    return relation[0] ?? null
  }

  return relation
}

export async function getActiveBusinessMemberships(): Promise<BusinessMembership[]> {
  const { data, error } = await getSupabaseClient()
    .from('business_memberships')
    .select('business_id, businesses(name, timezone, currency_code), business_roles(code, name)')
    .eq('status', 'active')

  if (error) {
    throw new Error('No fue posible obtener los negocios autorizados.')
  }

  const memberships = (data ?? []) as unknown as MembershipRow[]

  return memberships.flatMap((membership) => {
    const business = firstRelatedRow(membership.businesses)
    const role = firstRelatedRow(membership.business_roles)

    if (!business || !role) {
      return []
    }

    return [{
      businessId: membership.business_id,
      businessName: business.name,
      currencyCode: business.currency_code,
      roleCode: role.code,
      timezone: business.timezone,
      roleName: role.name,
    }]
  })
}

export async function createBusiness(name: string): Promise<string> {
  const { data, error } = await getSupabaseClient().rpc('create_business', {
    p_name: name,
    p_timezone: 'America/Guatemala',
  })

  if (error || typeof data !== 'string') {
    throw new Error('No fue posible crear el negocio.')
  }

  return data
}
