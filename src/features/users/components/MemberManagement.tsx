import { useCallback, useEffect, useState, type FormEvent } from 'react'
import {
  getBusinessMembers,
  inviteBusinessMember,
  type BusinessMember,
} from '../services/memberService'

type MemberManagementProps = {
  businessId: string
}

const MEMBER_STATUS_LABEL: Record<BusinessMember['status'], string> = {
  active: 'Activo',
  invited: 'Pendiente de aceptación',
  suspended: 'Suspendido',
}

export function MemberManagement({ businessId }: MemberManagementProps) {
  const [members, setMembers] = useState<BusinessMember[]>([])
  const [displayName, setDisplayName] = useState('')
  const [email, setEmail] = useState('')
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [successMessage, setSuccessMessage] = useState<string | null>(null)
  const [isInviting, setIsInviting] = useState(false)
  const [isLoading, setIsLoading] = useState(true)

  const loadMembers = useCallback(async () => {
    try {
      setMembers(await getBusinessMembers(businessId))
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'No fue posible cargar el equipo.')
    } finally {
      setIsLoading(false)
    }
  }, [businessId])

  useEffect(() => {
    const taskId = window.setTimeout(() => {
      void loadMembers()
    }, 0)

    return () => window.clearTimeout(taskId)
  }, [loadMembers])

  async function handleInvite(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setErrorMessage(null)
    setSuccessMessage(null)
    setIsInviting(true)

    try {
      const result = await inviteBusinessMember(businessId, email, displayName)
      setDisplayName('')
      setEmail('')
      setSuccessMessage(
        result.delivery === 'email_sent'
          ? 'La invitación fue enviada. La persona deberá activar su cuenta y aceptar el acceso.'
          : 'La persona ya tiene una cuenta. Al iniciar sesión podrá aceptar el acceso al negocio.',
      )
      await loadMembers()
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'No fue posible enviar la invitación.')
    } finally {
      setIsInviting(false)
    }
  }

  return (
    <section className="member-panel" aria-labelledby="members-title">
      <h2 id="members-title">Equipo</h2>
      <p className="muted">Invita empleados con una cuenta personal. El acceso queda pendiente hasta que acepten.</p>

      <form className="member-form" onSubmit={handleInvite}>
        <label className="field" htmlFor="member-name">
          Nombre (opcional)
          <input
            id="member-name"
            maxLength={120}
            onChange={(event) => setDisplayName(event.target.value)}
            placeholder="Ej. Carlos López"
            value={displayName}
          />
        </label>
        <label className="field" htmlFor="member-email">
          Correo electrónico
          <input
            autoComplete="email"
            id="member-email"
            maxLength={254}
            onChange={(event) => setEmail(event.target.value)}
            placeholder="empleado@ejemplo.com"
            required
            type="email"
            value={email}
          />
        </label>
        <button className="button" disabled={isInviting} type="submit">
          {isInviting ? 'Enviando…' : 'Enviar invitación'}
        </button>
      </form>

      {successMessage ? <p className="notice notice--success" role="status">{successMessage}</p> : null}
      {errorMessage ? <p className="notice" role="alert">{errorMessage}</p> : null}

      <h3>Personas del negocio</h3>
      {isLoading ? <p className="muted">Cargando equipo…</p> : null}
      {!isLoading && members.length === 0 ? <p className="muted">Aún no hay personas registradas.</p> : null}
      {!isLoading && members.length > 0 ? (
        <ul className="member-list">
          {members.map((member) => (
            <li key={member.id}>
              <strong>{member.displayName ?? member.email ?? 'Cuenta sin nombre'}</strong>
              {member.email && member.displayName ? <span className="muted">{member.email}</span> : null}
              <span className="muted">{member.roleName} · {MEMBER_STATUS_LABEL[member.status]}</span>
            </li>
          ))}
        </ul>
      ) : null}
    </section>
  )
}
