// Connection to Neo4j with the login from backend/.env. The driver is created on first use,
// so .env is already loaded by then.
import neo4j from 'neo4j-driver';

let driver = null;

export const settings = () => ({
  uri: process.env.NEO4J_URI || 'bolt://127.0.0.1:17687',
  user: process.env.NEO4J_USER || 'neo4j',
  database: process.env.NEO4J_DATABASE || 'neo4j'
});

function getDriver() {
  if (!driver) {
    const { uri, user } = settings();
    // disableLosslessIntegers: whole numbers come back as normal JavaScript numbers
    // The short timeouts make a stopped database fail in a few seconds (the default is about 30)
    // instead of leaving the page on "Loading..." for half a minute.
    driver = neo4j.driver(uri, neo4j.auth.basic(user, process.env.NEO4J_PASSWORD || ''), {
      disableLosslessIntegers: true,
      connectionTimeout: 4000,
      maxTransactionRetryTime: 4000,
      connectionAcquisitionTimeout: 6000
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

export async function ping() {
  await read('RETURN 1 AS ok');
}

// Turns a Neo4j connection problem into a message a person can act on. Returns null for other errors.
export function explain(err) {
  switch (err && err.code) {
    case 'ServiceUnavailable':
    case 'SessionExpired':
      return 'Cannot reach the Neo4j database. Check that it is running and that NEO4J_URI in backend/.env is right.';
    case 'Neo.ClientError.Security.Unauthorized':
      return 'The database refused the login. Check NEO4J_USER and NEO4J_PASSWORD in backend/.env.';
    case 'Neo.ClientError.Security.AuthenticationRateLimit':
      return 'The database refused the login after too many wrong passwords. Fix NEO4J_PASSWORD in backend/.env and try again in a minute.';
    case 'Neo.ClientError.Security.CredentialsExpired':
      return 'The database password is still the first-time default and must be changed. Set a new one in Neo4j Browser, then put it in backend/.env.';
    case 'Neo.ClientError.Database.DatabaseNotFound':
      return 'The database name in NEO4J_DATABASE (backend/.env) does not exist.';
    default:
      return null;
  }
}

export async function close() {
  if (driver) {
    await driver.close();
    driver = null;
  }
}
