import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    // 5194 so we don't fight flip (5190) when both dev servers run at once.
    port: 5194,
    // Bind to 0.0.0.0 so the dev server is reachable from other devices on the LAN.
    host: true,
  },
});
