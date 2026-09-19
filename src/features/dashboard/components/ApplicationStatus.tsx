import { useEffect, useState } from 'react'
import { applyServiceWorkerUpdate } from '../../../services/pwa/serviceWorker'

export function ApplicationStatus() {
  const [isOnline, setIsOnline] = useState(() => navigator.onLine)
  const [isUpdateReady, setIsUpdateReady] = useState(false)
  const [message, setMessage] = useState<string | null>(null)

  useEffect(() => {
    const handleOnline = () => setIsOnline(true)
    const handleOffline = () => setIsOnline(false)
    const handleUpdate = () => setIsUpdateReady(true)
    window.addEventListener('online', handleOnline)
    window.addEventListener('offline', handleOffline)
    window.addEventListener('app-update-ready', handleUpdate)
    return () => {
      window.removeEventListener('online', handleOnline)
      window.removeEventListener('offline', handleOffline)
      window.removeEventListener('app-update-ready', handleUpdate)
    }
  }, [])

  async function updateApplication() {
    setMessage(null)
    try {
      await applyServiceWorkerUpdate()
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No fue posible actualizar la aplicación.')
    }
  }

  return <>
    <p className={`connection-status${isOnline ? ' connection-status--online' : ' connection-status--offline'}`} role="status">
      {isOnline
        ? 'Con conexión. Las confirmaciones se registran directamente en el servidor.'
        : 'Sin conexión. No se confirmarán operaciones hasta recuperar Internet.'}
    </p>
    {isUpdateReady ? <p className="update-status" role="status">Hay una actualización disponible. <button className="text-button" type="button" onClick={() => void updateApplication()}>Actualizar ahora</button></p> : null}
    {message ? <p className="notice" role="alert">{message}</p> : null}
  </>
}
