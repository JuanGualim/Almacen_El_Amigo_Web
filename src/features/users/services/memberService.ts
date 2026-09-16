import { getSupabaseClient } from '../../../services/api/supabaseClient'

export type PendingBusinessInvitation = {
  businessId: string
  businessName: string
  invitedAt: string
  membershipId: string
  roleName: string
}

export type BusinessMember = {
  createdAt: string
  displayName: string | null
  email: string | null
  id: string
  invitationStatus: 'pending' | 'accepted' | 'cancelled' | null
  roleName: string
  status: 'active' | 'invited' | 'suspended'
}

type PendingInvitationRow = {
  business_id: string
  business_name: string
  invited_at: string
  membership_id: string
  role_name: string
}

type RelatedRow<T> = T | readonly T[] | null

type MemberRow = {
  created_at: string
  id: string
  status: BusinessMember['status']
  business_invitations: RelatedRow<{
    email: string
    status: NonNullable<BusinessMember['invitationStatus']>
  }>
  business_roles: RelatedRow<{
    name: string
  }>
  profiles: RelatedRow<{
    display_name: string | null
  }>
}

function isRelatedRows<T>(relation: RelatedRow<T>): relation is readonly T[] {
  return Array.isArray(relation)
}

function firstRelatedRow<T>(relation: RelatedRow<T>): T | null {
  if (isRelatedRows(relation)) {
    return relation[0] ?? null
  }

  return relation
}

export async function getPendingBusinessInvitations(): Promise<PendingBusinessInvitation[]> {
  const { data, error } = await getSupabaseClient().rpc('get_my_pending_business_invitations')

  if (error) {
    throw new Error('No fue posible obtener tus invitaciones pendientes.')
  }

  const invitations = (data ?? []) as PendingInvitationRow[]

  return invitations.map((row) => ({
    businessId: row.business_id,
    businessName: row.business_name,
    invitedAt: row.invited_at,
    membershipId: row.membership_id,
    roleName: row.role_name,
  }))
}

export async function acceptBusinessInvitation(membershipId: string): Promise<void> {
  const { error } = await getSupabaseClient().rpc('accept_business_invitation', {
    p_membership_id: membershipId,
  })

  if (error) {
    throw new Error('No fue posible aceptar la invitación. Inténtalo de nuevo.')
  }
}

export async function getBusinessMembers(businessId: string): Promise<BusinessMember[]> {
  const { data, error } = await getSupabaseClient()
    .from('business_memberships')
    .select(`
      id,
      status,
      created_at,
      profiles(display_name),
      business_roles(name),
      business_invitations(email, status)
    `)
    .eq('business_id', businessId)
    .order('created_at', { ascending: true })

  if (error) {
    throw new Error('No fue posible cargar el equipo del negocio.')
  }

  return ((data ?? []) as unknown as MemberRow[]).flatMap((member) => {
    const profile = firstRelatedRow(member.profiles)
    const role = firstRelatedRow(member.business_roles)
    const invitation = firstRelatedRow(member.business_invitations)

    if (!role) {
      return []
    }

    return [{
      createdAt: member.created_at,
      displayName: profile?.display_name ?? null,
      email: invitation?.email ?? null,
      id: member.id,
      invitationStatus: invitation?.status ?? null,
      roleName: role.name,
      status: member.status,
    }]
  })
}

export type InviteBusinessMemberResult = {
  delivery: 'email_sent' | 'existing_account'
}

export async function inviteBusinessMember(
  businessId: string,
  email: string,
  displayName: string,
): Promise<InviteBusinessMemberResult> {
  const { data, error } = await getSupabaseClient().functions.invoke<InviteBusinessMemberResult>(
    'invite-business-member',
    {
      body: {
        businessId,
        displayName,
        email,
        requestId: crypto.randomUUID(),
      },
    },
  )

  if (error || !data) {
    throw new Error('No fue posible enviar la invitación. Inténtalo de nuevo.')
  }

  return data
}
