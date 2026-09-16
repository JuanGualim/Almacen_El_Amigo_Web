import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Origin': '*',
}

type InviteRequest = {
  businessId?: unknown
  displayName?: unknown
  email?: unknown
  requestId?: unknown
}

type AuthUser = {
  id: string
  email?: string
}

type NormalizedInviteRequest = {
  businessId: string
  displayName: string
  email: string
  requestId: string
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function readInviteRequest(payload: InviteRequest): NormalizedInviteRequest {
  const businessId = typeof payload.businessId === 'string' ? payload.businessId : ''
  const email = typeof payload.email === 'string' ? payload.email.trim().toLowerCase() : ''
  const requestId = typeof payload.requestId === 'string' ? payload.requestId : ''
  const displayName = typeof payload.displayName === 'string' ? payload.displayName.trim() : ''

  if (!UUID_PATTERN.test(businessId) || !UUID_PATTERN.test(requestId)) {
    throw new Error('La solicitud de invitación no es válida.')
  }

  if (!EMAIL_PATTERN.test(email) || email.length > 254) {
    throw new Error('Ingresa un correo electrónico válido.')
  }

  if (displayName.length > 120) {
    throw new Error('El nombre no puede exceder 120 caracteres.')
  }

  return { businessId, displayName, email, requestId }
}

async function findUserByEmail(
  adminClient: ReturnType<typeof createClient>,
  email: string,
): Promise<AuthUser | null> {
  const pageSize = 1_000

  for (let page = 1; page <= 100; page += 1) {
    const { data, error } = await adminClient.auth.admin.listUsers({ page, perPage: pageSize })

    if (error) {
      throw new Error('No fue posible verificar la cuenta invitada.')
    }

    const user = data.users.find((candidate) => candidate.email?.toLowerCase() === email)
    if (user) {
      return { id: user.id, email: user.email }
    }

    if (data.users.length < pageSize) {
      return null
    }
  }

  throw new Error('No fue posible verificar la cuenta invitada.')
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (request.method !== 'POST') {
    return jsonResponse({ error: 'Método no permitido.' }, 405)
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const authorization = request.headers.get('Authorization')

  if (!supabaseUrl || !anonKey || !serviceRoleKey || !authorization) {
    return jsonResponse({ error: 'No fue posible autenticar la invitación.' }, 401)
  }

  try {
    const input = readInviteRequest(await request.json() as InviteRequest)
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
    })
    const { data: userData, error: userError } = await userClient.auth.getUser()

    if (userError || !userData.user) {
      return jsonResponse({ error: 'Tu sesión no es válida. Ingresa de nuevo.' }, 401)
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })
    const existingUser = await findUserByEmail(adminClient, input.email)
    let invitedUser: AuthUser
    let invitationDelivery: 'email_sent' | 'existing_account'

    if (existingUser) {
      invitedUser = existingUser
      invitationDelivery = 'existing_account'
    } else {
      const appUrl = Deno.env.get('APP_URL') ?? 'http://127.0.0.1:3000'
      const { data, error } = await adminClient.auth.admin.inviteUserByEmail(input.email, {
        data: input.displayName ? { display_name: input.displayName } : {},
        redirectTo: new URL('/auth/accept-invitation', appUrl).toString(),
      })

      if (error || !data.user) {
        return jsonResponse({ error: 'No fue posible enviar la invitación. Inténtalo de nuevo.' }, 422)
      }

      invitedUser = { id: data.user.id, email: data.user.email }
      invitationDelivery = 'email_sent'
    }

    const { error: invitationError } = await adminClient.rpc('create_business_invitation', {
      p_actor_user_id: userData.user.id,
      p_business_id: input.businessId,
      p_invited_user_id: invitedUser.id,
      p_email: input.email,
      p_request_id: input.requestId,
    })

    if (invitationError) {
      if (invitationDelivery === 'email_sent') {
        await adminClient.auth.admin.deleteUser(invitedUser.id)
      }

      return jsonResponse({ error: 'No fue posible registrar la invitación para este negocio.' }, 422)
    }

    return jsonResponse({ delivery: invitationDelivery })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'No fue posible procesar la invitación.'
    return jsonResponse({ error: message }, 400)
  }
})
