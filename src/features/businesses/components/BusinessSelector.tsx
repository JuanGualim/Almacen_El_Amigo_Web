import { useState, type FormEvent } from 'react'
import {
  createBusiness,
  type BusinessMembership,
} from '../services/businessService'

type BusinessSelectorProps = {
  memberships: readonly BusinessMembership[]
  onBusinessSelected: (business: BusinessMembership) => void
  onBusinessCreated: () => Promise<void>
}

export function BusinessSelector({
  memberships,
  onBusinessSelected,
  onBusinessCreated,
}: BusinessSelectorProps) {
  const [name, setName] = useState('')
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [isCreating, setIsCreating] = useState(false)

  async function handleCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setErrorMessage(null)
    setIsCreating(true)

    try {
      await createBusiness(name)
      setName('')
      await onBusinessCreated()
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'No fue posible crear el negocio.')
    } finally {
      setIsCreating(false)
    }
  }

  return (
    <section className="auth-card" aria-labelledby="business-title">
      <div className="brand">
        <div className="brand__icon" aria-hidden="true">↑</div>
        <div>
          <strong>Almacén El Amigo</strong>
          <div className="muted">Negocios autorizados</div>
        </div>
      </div>
      <h1 id="business-title">Selecciona un negocio</h1>
      {memberships.length > 0 ? (
        <ul className="business-list">
          {memberships.map((membership) => (
            <li key={membership.businessId}>
              <button onClick={() => onBusinessSelected(membership)} type="button">
                <strong>{membership.businessName}</strong>
                <br />
                <span className="muted">{membership.roleName} · {membership.timezone}</span>
              </button>
            </li>
          ))}
        </ul>
      ) : (
        <p className="muted">Aún no tienes un negocio asignado.</p>
      )}
      <form onSubmit={handleCreate}>
        <label className="field" htmlFor="business-name">
          Crear mi primer negocio
          <input
            id="business-name"
            maxLength={120}
            onChange={(event) => setName(event.target.value)}
            placeholder="Ej. Almacén El Amigo"
            required
            value={name}
          />
        </label>
        {errorMessage ? <p className="notice" role="alert">{errorMessage}</p> : null}
        <button className="button" disabled={isCreating} type="submit">
          {isCreating ? 'Creando…' : 'Crear negocio'}
        </button>
      </form>
    </section>
  )
}
