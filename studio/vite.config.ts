import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

declare const process: { env: Record<string, string | undefined> } // avoids a @types/node dependency

const target = process.env.MEDSIM_BACKEND ?? 'http://localhost:8000'

// API calls use root-absolute paths (/studio/...); assets stay relative so the build works under /app/.
export default defineConfig({
  base: './',
  plugins: [react()],
  server: {
    proxy: {
      '/studio': target,
      '/scenarios': target,
      '/sessions': target,
      '/health': target,
      '/ws': { target, ws: true },
    },
  },
})
