import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import fs from 'node:fs/promises';
import path from 'node:path';

/**
 * Dev-only JSON persistence. `GET <route>` reads the file, `POST <route>`
 * writes it (atomic temp-file + rename so concurrent tab writes can't
 * interleave). Only active under `vite dev`.
 */
function saveJsonPlugin(route: string, relTarget: string): Plugin {
  const target = path.resolve(__dirname, relTarget);
  return {
    name: `save-json:${route}`,
    configureServer(server) {
      server.middlewares.use(route, async (req, res) => {
        if (req.method === 'GET') {
          try {
            const buf = await fs.readFile(target, 'utf8');
            res.statusCode = 200;
            res.setHeader('content-type', 'application/json');
            res.setHeader('cache-control', 'no-store');
            res.end(buf);
          } catch {
            res.statusCode = 200;
            res.setHeader('content-type', 'application/json');
            res.end('{}');
          }
          return;
        }
        if (req.method !== 'POST') {
          res.statusCode = 405;
          res.end('method not allowed');
          return;
        }
        let body = '';
        req.on('data', (chunk: string) => (body += chunk));
        req.on('end', async () => {
          try {
            const parsed = JSON.parse(body);
            await fs.mkdir(path.dirname(target), { recursive: true });
            const tmp = `${target}.tmp.${process.pid}.${Date.now()}.${Math.random()
              .toString(36)
              .slice(2)}`;
            await fs.writeFile(tmp, JSON.stringify(parsed, null, 2) + '\n', 'utf8');
            await fs.rename(tmp, target);
            res.statusCode = 200;
            res.setHeader('content-type', 'application/json');
            res.end('{"ok":true}');
          } catch (err) {
            res.statusCode = 500;
            res.end(String(err));
          }
        });
      });
    },
  };
}

export default defineConfig({
  plugins: [
    react(),
    saveJsonPlugin('/api/sessions', 'src/data/sessions.json'),
    saveJsonPlugin('/api/working', 'src/data/sessions.local.json'),
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 5194,
    host: true,
  },
});
