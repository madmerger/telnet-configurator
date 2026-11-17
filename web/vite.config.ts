import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// `npm run dev` proxies /api to the Python backend (python -m cbt serve, port 8000).
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: { '/api': process.env.CBT_API ?? 'http://127.0.0.1:8000' },
  },
})
