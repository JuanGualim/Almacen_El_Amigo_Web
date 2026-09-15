import { useState, type FormEvent } from 'react'
import { signInWithPassword } from '../../../services/auth/authService'

type LoginFormProps = {
  onAuthenticated: () => void
}

export function LoginForm({ onAuthenticated }: LoginFormProps) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [isSubmitting, setIsSubmitting] = useState(false)

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setErrorMessage(null)
    setIsSubmitting(true)

    try {
      await signInWithPassword(email, password)
      onAuthenticated()
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Ocurrió un error al iniciar sesión.')
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} noValidate>
      <label className="field" htmlFor="email">
        Correo electrónico
        <input
          autoComplete="email"
          id="email"
          onChange={(event) => setEmail(event.target.value)}
          required
          type="email"
          value={email}
        />
      </label>
      <label className="field" htmlFor="password">
        Contraseña
        <input
          autoComplete="current-password"
          id="password"
          onChange={(event) => setPassword(event.target.value)}
          required
          type="password"
          value={password}
        />
      </label>
      {errorMessage ? <p className="notice" role="alert">{errorMessage}</p> : null}
      <button className="button" disabled={isSubmitting} type="submit">
        {isSubmitting ? 'Ingresando…' : 'Iniciar sesión'}
      </button>
    </form>
  )
}
