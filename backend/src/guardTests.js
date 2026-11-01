// Imported first by the tests that write to the database. They create temporary data (ids starting with ZZT)
// and remove it again, which is fine on this computer's own database but not on an online one by accident.
// To run them against an online database on purpose:  set TEST_ON_REMOTE=1  (PowerShell: $env:TEST_ON_REMOTE=1)
import './env.js';
import { settings, hostOf } from './db.js';

const { uri, remote } = settings();
if (remote && process.env.TEST_ON_REMOTE !== '1') {
  throw new Error(
    `The tests write temporary data, and NEO4J_URI points at an online database (${hostOf(uri)}). ` +
    'Run them against the local database, or set TEST_ON_REMOTE=1 if you really mean to test the online one.');
}
