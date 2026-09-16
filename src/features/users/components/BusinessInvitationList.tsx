import { useState } from 'react'
import {
  acceptBusinessInvitation,
  type PendingBusinessInvitation,
} from '../services/memberService'

type BusinessInvitationListProps = {
  invitations: readonly PendingBusinessInvitation[]
  onInvitationAccepted: () => Promise<void>
}

export function BusinessInvitationList({
  invitations,
  onInvitationAccepted,
}: BusinessInvitationListProps) {
  const [acceptingId, setAcceptingId] = useState<string | null>(null)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  async function handleAccept(membershipId: string) {
    setErrorMessage(null)
    setAcceptingId(membershipId)

    try {
      await acceptBusinessInvitation(membershipId)
      await onInvitationAccepted()
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'No fue posible aceptar la invitación.')
    } finally {
      setAcceptingId(null)
    }
  }

  if (invitations.length === 0) {
    return null
  }

  return (
    <section className="invitation-panel" aria-labelledby="invitation-title">
      <h2 id="invitation-title">Invitaciones pendientes</h2>
      <p className="muted">Acepta una invitación para poder entrar al negocio correspondiente.</p>
      <ul className="invitation-list">
        {invitations.map((invitation) => (
          <li key={invitation.membershipId}>
            <strong>{invitation.businessName}</strong>
            <span className="muted">Rol inicial: {invitation.roleName}</span>
            <button
              className="button button--compact"
              disabled={acceptingId === invitation.membershipId}
              onClick={() => void handleAccept(invitation.membershipId)}
              type="button"
            >
              {acceptingId === invitation.membershipId ? 'Aceptando…' : 'Aceptar invitación'}
            </button>
          </li>
        ))}
      </ul>
      {errorMessage ? <p className="notice" role="alert">{errorMessage}</p> : null}
    </section>
  )
}
