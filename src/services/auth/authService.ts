import type { Session } from '@supabase/supabase-js'
import { getSupabaseClient } from '../api/supabaseClient'

export async function getCurrentSession(): Promise<Session | null> {
  const { data, error } = await getSupabaseClient().auth.getSession()

  if (error) {
    throw new Error('No se pudo recuperar la sesión actual.')
  }

  return data.session
}

export async function signInWithPassword(email: string, password: string): Promise<Session> {
  const { data, error } = await getSupabaseClient().auth.signInWithPassword({ email, password })

  if (error || !data.session) {
    throw new Error('No fue posible iniciar sesión. Verifica tus credenciales.')
  }

  return data.session
}

export async function signOut(): Promise<void> {
  const { error } = await getSupabaseClient().auth.signOut()

  if (error) {
    throw new Error('No fue posible cerrar sesión de forma segura.')
  }
}
