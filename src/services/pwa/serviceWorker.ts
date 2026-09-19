import { registerSW } from 'virtual:pwa-register'

let applyUpdate: ((reloadPage?: boolean) => Promise<void>) | null = null

export function registerServiceWorker(): void {
  applyUpdate = registerSW({
    onNeedRefresh() {
      window.dispatchEvent(new Event('app-update-ready'))
    },
  })
}

export async function applyServiceWorkerUpdate(): Promise<void> {
  if (!applyUpdate) throw new Error('La actualización no está disponible todavía.')
  await applyUpdate(true)
}
