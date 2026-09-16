import { useCallback, useEffect, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { BusinessSelector } from '../features/businesses/components/BusinessSelector'
import {
  getActiveBusinessMemberships,
  type BusinessMembership,
} from '../features/businesses/services/businessService'
import { LoginForm } from '../features/auth/components/LoginForm'
import { CatalogPanel } from '../features/catalog/components/CatalogPanel'
import { MemberManagement } from '../features/users/components/MemberManagement'
import {
  getPendingBusinessInvitations,
  type PendingBusinessInvitation,
} from '../features/users/services/memberService'
import { getCurrentSession, signOut } from '../services/auth/authService'
import { isSupabaseConfigured } from '../services/api/supabaseClient'

type AppState = 'loading' | 'ready' | 'error'

export function App() {
  const [appState, setAppState] = useState<AppState>('loading')
  const [session, setSession] = useState<Session | null>(null)
  const [memberships, setMemberships] = useState<BusinessMembership[]>([])
  const [pendingInvitations, setPendingInvitations] = useState<PendingBusinessInvitation[]>([])
  const [selectedBusiness, setSelectedBusiness] = useState<BusinessMembership | null>(null)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  const loadMemberships = useCallback(async () => {
    try {
      const [nextMemberships, nextInvitations] = await Promise.all([
        getActiveBusinessMemberships(),
        getPendingBusinessInvitations(),
      ])
      setMemberships(nextMemberships)
      setPendingInvitations(nextInvitations)
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'No fue posible cargar los negocios.')
      setAppState('error')
    }
  }, [])

  const loadSession = useCallback(async () => {
    if (!isSupabaseConfigured) {
      setAppState('ready')
      return
    }

    try {
      const nextSession = await getCurrentSession()
      setSession(nextSession)
      if (nextSession) {
        await loadMemberships()
      }
      setAppState('ready')
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'No fue posible iniciar la aplicación.')
      setAppState('error')
    }
  }, [loadMemberships])

  useEffect(() => {
    const taskId = window.setTimeout(() => {
      void loadSession()
    }, 0)

    return () => window.clearTimeout(taskId)
  }, [loadSession])

  async function handleAuthenticated() {
    const nextSession = await getCurrentSession()
    setSession(nextSession)
    await loadMemberships()
  }

  async function handleSignOut() {
    await signOut()
    setSession(null)
    setMemberships([])
    setPendingInvitations([])
    setSelectedBusiness(null)
  }

  if (appState === 'loading') {
    return <main className="app-shell"><p>Preparando aplicación…</p></main>
  }

  if (!isSupabaseConfigured) {
    return (
      <main className="app-shell">
        <section className="auth-card" aria-labelledby="configuration-title">
          <h1 id="configuration-title">Configura el entorno local</h1>
          <p className="muted">
            Copia <code>.env.example</code> a <code>.env.local</code> y usa las credenciales
            generadas por Supabase local. Esta pantalla no contiene claves ni datos del negocio.
          </p>
        </section>
      </main>
    )
  }

  if (appState === 'error') {
    return <main className="app-shell"><p className="notice" role="alert">{errorMessage}</p></main>
  }

  if (!session) {
    return (
      <main className="app-shell">
        <section className="auth-card" aria-labelledby="login-title">
          <div className="brand">
            <div className="brand__icon" aria-hidden="true">↑</div>
            <div>
              <strong>Almacén El Amigo</strong>
              <div className="muted">Control operativo</div>
            </div>
          </div>
          <h1 id="login-title">Ingresa a tu cuenta</h1>
          <p className="muted">Usa tu cuenta personal autorizada para el negocio.</p>
          <LoginForm onAuthenticated={() => void handleAuthenticated()} />
        </section>
      </main>
    )
  }

  if (!selectedBusiness) {
    return (
      <main className="app-shell">
        <BusinessSelector
          memberships={memberships}
          pendingInvitations={pendingInvitations}
          onBusinessCreated={loadMemberships}
          onInvitationAccepted={loadMemberships}
          onBusinessSelected={setSelectedBusiness}
        />
      </main>
    )
  }

  return (
    <main className="app-shell">
      <section className="auth-card" aria-labelledby="welcome-title">
        <h1 id="welcome-title">{selectedBusiness.businessName}</h1>
        <p className="muted">
          Negocio activo · {selectedBusiness.roleName} · {selectedBusiness.timezone}
        </p>
        <p>La base técnica está lista. Los módulos operativos se incorporarán de forma incremental.</p>
        {selectedBusiness.roleCode === 'owner' ? (
          <MemberManagement businessId={selectedBusiness.businessId} />
        ) : null}
        <CatalogPanel
          businessId={selectedBusiness.businessId}
          canManage={selectedBusiness.roleCode === 'owner'}
        />
        <button className="button" onClick={() => void handleSignOut()} type="button">
          Cerrar sesión
        </button>
      </section>
    </main>
  )
}
