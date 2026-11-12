import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// En desarrollo local, /api se reenvía al backend de compose; en Kubernetes el Ingress lo resuelve (mismo origen).
export default defineConfig({
  plugins: [react()],
  server: { proxy: { '/api': process.env.API_DEV || 'http://localhost:8000' } },
  build: { sourcemap: false },
});
