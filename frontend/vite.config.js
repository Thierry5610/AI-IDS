import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    // Honour an injected PORT (preview/CI); default to 5173 for normal dev.
    port: Number(process.env.PORT) || 5173,
    proxy: {
      // /api/*  → inference service (strip /api prefix — service has no such prefix)
      '/api': {
        target:      'http://localhost:8000',
        changeOrigin: true,
        rewrite:     path => path.replace(/^\/api/, ''),
      },
      // /stream/* → bridge
      '/stream': {
        target:      'http://localhost:8001',
        changeOrigin: true,
      },
    },
  },
})
