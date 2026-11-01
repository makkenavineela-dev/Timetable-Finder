// The web application: the API under /api and the frontend page at /.
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import routes from './routes.js';
import editRoutes from './edit.js';
import { ping, explain } from './db.js';
import { HttpError } from './validate.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const FRONTEND = path.resolve(here, '../../frontend');
// only these files of the frontend folder are served (not the README or anything else)
const PAGE_FILES = ['index.html', 'style.css', 'theme.js', 'app.js', 'edit.js', 'api.js', 'data.js'];

export function createApp() {
  const app = express();
  app.disable('x-powered-by');

  // The page only loads its own files, and no other site may show it inside a frame.
  app.use((req, res, next) => {
    res.set({
      'Content-Security-Policy': "default-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'no-referrer'
    });
    next();
  });

  // ---- API
  if (process.env.FRONTEND_URL) app.use('/api', cors({ origin: process.env.FRONTEND_URL }));
  app.use('/api', rateLimit({ windowMs: 60_000, limit: 300, standardHeaders: true, legacyHeaders: false }));
  app.use('/api', (req, res, next) => { res.set('Cache-Control', 'no-store'); next(); });

  app.get('/api/health', async (req, res) => {
    try {
      await ping();
      res.json({ ok: true, database: 'up' });
    } catch (err) {
      res.status(503).json({ ok: false, database: 'down', error: explain(err) || err.message });
    }
  });
  app.use('/api/edit', editRoutes);
  app.use('/api', routes);
  app.use('/api', (req, res) => res.status(404).json({ error: 'No such endpoint' }));

  // ---- frontend page. config.js tells the page to use this server's API.
  app.get('/config.js', (req, res) => {
    res.type('application/javascript').set('Cache-Control', 'no-store')
      .send('window.TT_CONFIG = { API_URL: location.origin };\n');
  });
  for (const file of PAGE_FILES) {
    app.get('/' + file, (req, res) => res.set('Cache-Control', 'no-cache').sendFile(path.join(FRONTEND, file)));
  }
  app.get('/', (req, res) => res.set('Cache-Control', 'no-cache').sendFile(path.join(FRONTEND, 'index.html')));

  // ---- errors
  app.use((err, req, res, next) => {
    if (err instanceof HttpError) return res.status(err.status).json({ error: err.message, details: err.details });
    if (err.type === 'entity.parse.failed') return res.status(400).json({ error: 'The data sent is not valid JSON' });
    if (err.type === 'entity.too.large') return res.status(413).json({ error: 'Too much data sent at once' });
    const message = explain(err);
    if (message) return res.status(503).json({ error: message });
    console.error('Unexpected error:', err);
    return res.status(500).json({ error: 'Server error' });
  });

  return app;
}
