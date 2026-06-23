import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
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
