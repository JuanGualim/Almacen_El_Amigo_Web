import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { registerSW } from 'virtual:pwa-register'
import { App } from './app/App'
import './styles/tokens.css'
import './styles/global.css'

registerSW({
  onNeedRefresh() {
    window.dispatchEvent(new Event('app-update-ready'))
  },
})

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
