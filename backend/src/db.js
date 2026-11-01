// Connection to Neo4j with the login from backend/.env. The driver is created on first use,
// so .env is already loaded by then. Works with the project's local database (bolt://127.0.0.1:17687)
// and with Neo4j Aura (neo4j+s://ID.databases.neo4j.io).
import neo4j from 'neo4j-driver';

let driver = null;

export const settings = () => {
  const uri = process.env.NEO4J_URI || 'bolt://127.0.0.1:17687';
  return {
    uri,
    user: process.env.NEO4J_USER || 'neo4j',
    database: process.env.NEO4J_DATABASE || 'neo4j',
    remote: !isLocalUri(uri)
  };
};

// True for a database on this computer (localhost / 127.0.0.1 / ::1), any scheme.
export function isLocalUri(uri) {
  return /^(bolt|neo4j)(\+s(sc)?)?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?\/?$/i.test(String(uri || '').trim());
}

// Only the host of the address, for messages (never the user name or password).
export function hostOf(uri) {
  const m = String(uri || '').match(/^[a-z0-9+]+:\/\/([^/:?#]+)/i);
  return m ? m[1] : 'unknown host';
}

function getDriver() {
  if (!driver) {
    const { uri, user, remote } = settings();
    // disableLosslessIntegers: whole numbers come back as normal JavaScript numbers.
    // Local database: short timeouts, so a stopped database fails in a few seconds (the default is about 30)
    // instead of leaving the page on "Loading..." for half a minute.
    // Remote database (Aura): the network needs more time, and Aura closes idle connections, so connections
    // are renewed every few minutes and checked before use when they have been idle.
    driver = neo4j.driver(uri, neo4j.auth.basic(user, process.env.NEO4J_PASSWORD || ''), {
      disableLosslessIntegers: true,
      connectionTimeout: remote ? 15000 : 4000,
      maxTransactionRetryTime: remote ? 15000 : 4000,
      connectionAcquisitionTimeout: remote ? 20000 : 6000,
      ...(remote ? { maxConnectionLifetime: 5 * 60 * 1000, connectionLivenessCheckTimeout: 30 * 1000 } : {})
    });
  }
  return driver;
}

// JavaScript has one kind of number, which the driver sends as a decimal (1 becomes 1.0).
// Whole numbers are sent as Neo4j integers instead, so a semester or floor number is stored as 1, not 1.0.
const typed = (v) => (Number.isInteger(v) ? neo4j.int(v) : Array.isArray(v) ? v.map(typed) : v);
const typedParams = (params) => Object.fromEntries(Object.entries(params).map(([k, v]) => [k, typed(v)]));

// Runs one read-only query. Values are always passed as parameters, never joined into the query text.
// The session is in READ mode, so Neo4j itself refuses any query that tries to change data.
export async function read(query, params = {}) {
  const session = getDriver().session({ database: settings().database, defaultAccessMode: neo4j.session.READ });
  try {
    const result = await session.executeRead((tx) => tx.run(query, typedParams(params)));
    return result.records.map((record) => record.toObject());
  } finally {
    await session.close();
  }
}

// A session that may change data: used by the data loader (scripts/load-data.js) and by change().
export function writeSession() {
  return getDriver().session({ database: settings().database, defaultAccessMode: neo4j.session.WRITE });
}

// Runs work(run) in ONE write transaction, where run(query, params) returns rows like read().
// If work throws (for example because a check found a clash), nothing of it is saved.
export async function change(work) {
  const session = writeSession();
  try {
    return await session.executeWrite((tx) => work(async (query, params = {}) =>
      (await tx.run(query, typedParams(params))).records.map((record) => record.toObject())));
  } finally {
    await session.close();
  }
}

// Asks the database a trivial question. Returns how long the answer took, in milliseconds.
export async function ping() {
  const started = Date.now();
  await read('RETURN 1 AS ok');
  return Date.now() - started;
}

// Waits for the database to answer, trying again with growing pauses (Aura Free can take about a minute to
// wake from a pause). Resolves with {ok, ms, error}; never throws, so the server can start meanwhile.
export async function waitForDatabase({ totalMs = 90000, firstPauseMs = 1000 } = {}) {
  const until = Date.now() + totalMs;
  let pause = firstPauseMs;
  let last = null;
  for (;;) {
    try {
      return { ok: true, ms: await ping(), error: null };
    } catch (err) {
      last = err;
      // a wrong login or a missing database does not get better by waiting
      if (['Neo.ClientError.Security.Unauthorized', 'Neo.ClientError.Security.CredentialsExpired',
        'Neo.ClientError.Database.DatabaseNotFound', 'Neo.ClientError.Security.AuthenticationRateLimit'].includes(err.code)) break;
      if (Date.now() + pause > until) break;
      await new Promise((resolve) => setTimeout(resolve, pause));
      pause = Math.min(pause * 2, 10000);
    }
  }
  return { ok: false, ms: null, error: last };
}

// A cheap query every few minutes keeps the connections warm (the first visitor after a quiet spell is not
// slow) and counts as activity, so a free Aura database is not paused for being unused.
let keepAliveTimer = null;
export function startKeepAlive(everyMs = 4 * 60 * 1000, log = console.warn) {
  if (keepAliveTimer) return;
  let failing = false;
  keepAliveTimer = setInterval(async () => {
    try {
      await ping();
      failing = false;
    } catch (err) {
      if (!failing) log(`Database keep-alive failed: ${explain(err) || err.message}`);
      failing = true;
    }
  }, everyMs);
  keepAliveTimer.unref();
}
export function stopKeepAlive() {
  if (keepAliveTimer) clearInterval(keepAliveTimer);
  keepAliveTimer = null;
}

// Turns a Neo4j connection problem into a message a person can act on. Returns null for other errors.
export function explain(err) {
  const remote = settings().remote;
  switch (err && err.code) {
    case 'ServiceUnavailable':
    case 'SessionExpired':
      return remote
        ? 'Cannot reach the Neo4j database. If it is a free Aura database it may be paused: open console.neo4j.io, resume it and wait a minute. Also check NEO4J_URI (it must start with neo4j+s://).'
        : 'Cannot reach the Neo4j database. Check that it is running and that NEO4J_URI in backend/.env is right.';
    case 'Neo.ClientError.Security.Unauthorized':
      return 'The database refused the login. Check NEO4J_USER and NEO4J_PASSWORD' + (remote ? ' (the password of the Aura instance, shown once when it was created).' : ' in backend/.env.');
    case 'Neo.ClientError.Security.AuthenticationRateLimit':
      return 'The database refused the login after too many wrong passwords. Fix NEO4J_PASSWORD and try again in a minute.';
    case 'Neo.ClientError.Security.CredentialsExpired':
      return 'The database password is still the first-time default and must be changed. Set a new one in Neo4j Browser, then put it in backend/.env.';
    case 'Neo.ClientError.Database.DatabaseNotFound':
      return 'The database name in NEO4J_DATABASE does not exist' + (remote ? ' (on Aura it is normally "neo4j").' : '.');
    default:
      return null;
  }
}

// Settings that are fine on a developer's computer but wrong for a public website.
// Returns a list of problems (empty = ok). Used at start-up when NODE_ENV=production.
export function productionProblems(env = process.env) {
  const out = [];
  const uri = env.NEO4J_URI || '';
  if (!uri) out.push('NEO4J_URI is not set.');
  else if (isLocalUri(uri)) out.push('NEO4J_URI points at this computer; a public website needs the Aura address (neo4j+s://...).');
  else if (!/^neo4j\+s(sc)?:\/\//i.test(uri) && !/^bolt\+s(sc)?:\/\//i.test(uri)) out.push('NEO4J_URI should start with neo4j+s:// so the connection is encrypted.');
  if (!env.NEO4J_PASSWORD) out.push('NEO4J_PASSWORD is not set.');
  return out;
}

export async function close() {
  stopKeepAlive();
  if (driver) {
    await driver.close();
    driver = null;
  }
}
