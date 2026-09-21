import { lazy, Suspense, useCallback, useEffect, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { BusinessSelector } from '../features/businesses/components/BusinessSelector'
import {
  getActiveBusinessMemberships,
  type BusinessMembership,
} from '../features/businesses/services/businessService'
import { LoginForm } from '../features/auth/components/LoginForm'
import { ApplicationStatus } from '../features/dashboard/components/ApplicationStatus'
import { OperationalDashboard } from '../features/dashboard/components/OperationalDashboard'
import {
  getPendingBusinessInvitations,
  type PendingBusinessInvitation,
} from '../features/users/services/memberService'
import { getCurrentSession, signOut } from '../services/auth/authService'
import { clearOfflineDataForUser } from '../features/sales/services/offlineSalesService'
import { isSupabaseConfigured } from '../services/api/supabaseClient'
import { type ActiveView, viewFromLocation } from './navigation'

type AppState = 'loading' | 'ready' | 'error'

const CatalogPanel = lazy(async () => ({ default: (await import('../features/catalog/components/CatalogPanel')).CatalogPanel }))
const CashRegisterPanel = lazy(async () => ({ default: (await import('../features/cash-register/components/CashRegisterPanel')).CashRegisterPanel }))
const PurchasePanel = lazy(async () => ({ default: (await import('../features/purchases/components/PurchasePanel')).PurchasePanel }))
const SalesPanel = lazy(async () => ({ default: (await import('../features/sales/components/SalesPanel')).SalesPanel }))
const SaleAuthorizationPanel = lazy(async () => ({ default: (await import('../features/sales/components/SaleAuthorizationPanel')).SaleAuthorizationPanel }))
const OperationsPanel = lazy(async () => ({ default: (await import('../features/operations/components/OperationsPanel')).OperationsPanel }))
const ReportsPanel = lazy(async () => ({ default: (await import('../features/reports/components/ReportsPanel')).ReportsPanel }))
const MemberManagement = lazy(async () => ({ default: (await import('../features/users/components/MemberManagement')).MemberManagement }))
const InitialInventoryPanel = lazy(async () => ({ default: (await import('../features/onboarding/components/InitialInventoryPanel')).InitialInventoryPanel }))

function LazyPanel({ children }: { children: ReactNode }) {
  return <Suspense fallback={<p className="muted" role="status">Cargando módulo…</p>}>{children}</Suspense>
}

export function App() {
  const [appState, setAppState] = useState<AppState>('loading')
  const [session, setSession] = useState<Session | null>(null)
  const [memberships, setMemberships] = useState<BusinessMembership[]>([])
  const [pendingInvitations, setPendingInvitations] = useState<PendingBusinessInvitation[]>([])
  const [selectedBusiness, setSelectedBusiness] = useState<BusinessMembership | null>(null)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [cashRefreshToken, setCashRefreshToken] = useState(0)
  const [activeView, setActiveView] = useState<ActiveView>(viewFromLocation)

  const navigate = useCallback((view: ActiveView) => {
    window.location.hash = view === 'home' ? '' : view
    setActiveView(view)
  }, [])

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

  useEffect(() => {
    const handleHashChange = () => setActiveView(viewFromLocation())
    window.addEventListener('hashchange', handleHashChange)
    return () => window.removeEventListener('hashchange', handleHashChange)
  }, [])

  async function handleAuthenticated() {
    const nextSession = await getCurrentSession()
    setSession(nextSession)
    await loadMemberships()
  }

  async function handleSignOut() {
    if (session) await clearOfflineDataForUser(session.user.id)
    await signOut()
    setSession(null)
    setMemberships([])
    setPendingInvitations([])
    setSelectedBusiness(null)
    navigate('home')
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
          onBusinessSelected={(membership) => {
            setSelectedBusiness(membership)
            navigate('home')
          }}
        />
      </main>
    )
  }

  return <main className="app-shell app-shell--workspace">
    <header className="app-topbar">
      <div className="app-topbar__identity">
        <div className="brand__icon" aria-hidden="true">↑</div>
        <div>
          <strong>{selectedBusiness.businessName}</strong>
          <span>{selectedBusiness.roleName} · {selectedBusiness.timezone}</span>
        </div>
      </div>
      <ApplicationStatus />
    </header>
    <section className="app-workspace" aria-labelledby="workspace-title">
      <div className="workspace-heading">
        <div>
          <span className="eyebrow">Negocio activo</span>
          <h1 id="workspace-title">{activeView === 'home' ? 'Inicio operativo' : activeView === 'sell' ? 'Punto de venta' : activeView === 'inventory' ? 'Inventario y catálogo' : activeView === 'operations' ? 'Operaciones' : 'Administración'}</h1>
        </div>
      </div>
      <div className="app-content">
        {activeView === 'home' ? <OperationalDashboard businessId={selectedBusiness.businessId} isOwner={selectedBusiness.roleCode === 'owner'} onNavigate={navigate} /> : null}
        {activeView === 'inventory' ? <LazyPanel><CatalogPanel businessId={selectedBusiness.businessId} canManage={selectedBusiness.roleCode === 'owner'} /></LazyPanel> : null}
        {activeView === 'sell' ? <LazyPanel><SalesPanel businessId={selectedBusiness.businessId} onSaleConfirmed={() => setCashRefreshToken((currentToken) => currentToken + 1)} refreshToken={cashRefreshToken} userId={session.user.id} /></LazyPanel> : null}
        {activeView === 'operations' ? <LazyPanel><>
          <PurchasePanel businessId={selectedBusiness.businessId} canConfirm={selectedBusiness.roleCode === 'owner'} />
          <CashRegisterPanel businessId={selectedBusiness.businessId} canOpen={selectedBusiness.roleCode === 'owner'} onChanged={() => setCashRefreshToken((currentToken) => currentToken + 1)} refreshToken={cashRefreshToken} />
          <OperationsPanel businessId={selectedBusiness.businessId} isOwner={selectedBusiness.roleCode === 'owner'} />
        </></LazyPanel> : null}
        {activeView === 'more' ? <LazyPanel><>
          {selectedBusiness.roleCode === 'owner' ? <InitialInventoryPanel businessId={selectedBusiness.businessId} /> : null}
          {selectedBusiness.roleCode === 'owner' ? <ReportsPanel businessId={selectedBusiness.businessId} timezone={selectedBusiness.timezone} /> : null}
          {selectedBusiness.roleCode === 'owner' ? <MemberManagement businessId={selectedBusiness.businessId} /> : null}
          {selectedBusiness.roleCode === 'owner' ? <SaleAuthorizationPanel businessId={selectedBusiness.businessId} /> : null}
          <button className="button button--secondary" onClick={() => void handleSignOut()} type="button">Cerrar sesión</button>
        </></LazyPanel> : null}
      </div>
    </section>
    <nav aria-label="Navegación principal" className="app-navigation">
      <button aria-current={activeView === 'home' ? 'page' : undefined} className="button button--compact" onClick={() => navigate('home')} type="button"><span aria-hidden="true">⌂</span>Inicio</button>
      <button aria-current={activeView === 'sell' ? 'page' : undefined} className="button button--compact" onClick={() => navigate('sell')} type="button"><span aria-hidden="true">▣</span>Vender</button>
      <button aria-current={activeView === 'inventory' ? 'page' : undefined} className="button button--compact" onClick={() => navigate('inventory')} type="button"><span aria-hidden="true">▤</span>Inventario</button>
      <button aria-current={activeView === 'operations' ? 'page' : undefined} className="button button--compact" onClick={() => navigate('operations')} type="button"><span aria-hidden="true">▧</span>Operaciones</button>
      <button aria-current={activeView === 'more' ? 'page' : undefined} className="button button--compact" onClick={() => navigate('more')} type="button"><span aria-hidden="true">•••</span>Más</button>
    </nav>
  </main>
}
