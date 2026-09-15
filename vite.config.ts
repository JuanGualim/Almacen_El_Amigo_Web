import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react-swc'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: 'prompt',
      injectRegister: false,
      manifest: {
        name: 'Almacén El Amigo',
        short_name: 'El Amigo',
        description: 'Control operativo para tienda de ropa y accesorios para hombre.',
        lang: 'es-GT',
        theme_color: '#0f2942',
        background_color: '#f7f9fb',
        display: 'standalone',
        icons: [
          {
            src: '/icons/app-icon.svg',
            sizes: 'any',
            type: 'image/svg+xml',
            purpose: 'any',
          },
        ],
      },
      workbox: {
        runtimeCaching: [],
      },
    }),
  ],
  server: {
    port: 3000,
  },
  test: {
    environment: 'jsdom',
    setupFiles: './src/test/setup.ts',
  },
})
