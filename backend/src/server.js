// Start the app:  npm start   then open http://localhost:3100
//   node src/server.js --open   also opens the page in the browser (the start file in the project folder uses this)
import './env.js';
import { spawn } from 'node:child_process';
import { createApp } from './app.js';
import { ping, close, settings } from './db.js';

const port = Number(process.env.PORT) || 3100;
// Only this computer can reach the server by default. Set HOST=0.0.0.0 in .env to share it on your network.
const host = process.env.HOST || '127.0.0.1';
const url = `http://localhost:${port}`;
const openPage = process.argv.includes('--open');

function openBrowser() {
  const [command, args] = process.platform === 'win32' ? ['cmd', ['/c', 'start', '', url]]
    : process.platform === 'darwin' ? ['open', [url]] : ['xdg-open', [url]];
  spawn(command, args, { stdio: 'ignore', detached: true, windowsHide: true }).on('error', () => {}).unref();
}

// True when the program on our port is already this app (for example started from another window).
async function alreadyRunning() {
  try {
    const res = await fetch(`http://127.0.0.1:${port}/api/health`, { signal: AbortSignal.timeout(10000) });
    return 'database' in (await res.json());
  } catch {
    return false;
  }
}

const server = createApp().listen(port, host, async () => {
  console.log(`Timetable Finder is running:  ${url}`);
  try {
    await ping();
    console.log(`Database connected:           ${settings().uri}`);
  } catch (err) {
    console.warn('\nWARNING: the database is not reachable yet.');
    console.warn(`  ${err.message}`);
    console.warn('  Check that Neo4j is running and that backend/.env has the right NEO4J_URI, NEO4J_USER and NEO4J_PASSWORD.');
    console.warn('  The page opens, but shows an error until the database answers.\n');
  }
  if (openPage) openBrowser();
  console.log('Keep this window open while you use the page. Press Ctrl+C to stop.');
});

server.on('error', async (err) => {
  if (err.code === 'EADDRINUSE') {
    if (await alreadyRunning()) {
      console.log(`Timetable Finder is already running at ${url}`);
      if (openPage) openBrowser();
      process.exit(0);
    }
    console.error(`Port ${port} is already used by another program. Stop it, or set another PORT (for example PORT=3101) in backend/.env.`);
  } else {
    console.error(err);
  }
  process.exit(1);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, async () => {
    server.close();
    await close();
    process.exit(0);
  });
}
