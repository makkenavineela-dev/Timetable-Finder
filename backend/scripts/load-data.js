// Loads the timetable into the Neo4j database named in backend/.env (it logs in with the password there).
//   npm run load-data                       neo4j/01_schema.cypher, then the 5th and 3rd semester timetables (02_*)
//   npm run load-data -- some.cypher ...    other .cypher files, in the order given
//   npm run load-data -- --yes              needed when the database is not on this computer (for example Aura)
// Every statement in those files is safe to re-run.
import '../src/env.js';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { writeSession, close, explain, settings, hostOf } from '../src/db.js';

const NEO4J_FOLDER = fileURLToPath(new URL('../../neo4j/', import.meta.url));
const DEFAULT_FILES = ['01_schema.cypher', '02_cluster_E_sem5.cypher', '02_cluster_E_sem3.cypher'].map((f) => path.join(NEO4J_FOLDER, f));

// Splits a .cypher file into statements: drops comments and splits on ";" outside quotes.
export function statements(text) {
  const out = [];
  let cur = '';
  let quote = null;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quote) {
      cur += ch;
      if (ch === '\\' && quote !== '`' && i + 1 < text.length) cur += text[++i];
      else if (ch === quote) quote = null;
    } else if (ch === "'" || ch === '"' || ch === '`') {
      quote = ch;
      cur += ch;
    } else if (ch === '/' && text[i + 1] === '/') {
      while (i + 1 < text.length && text[i + 1] !== '\n') i++;
    } else if (ch === '/' && text[i + 1] === '*') {
      const end = text.indexOf('*/', i + 2);
      i = end < 0 ? text.length : end + 1;
      cur += ' ';
    } else if (ch === ';') {
      out.push(cur);
      cur = '';
    } else {
      cur += ch;
    }
  }
  out.push(cur);
  return out.map((s) => s.trim()).filter(Boolean);
}

async function main() {
  const args = process.argv.slice(2);
  const confirmed = args.includes('--yes');
  const given = args.filter((a) => a !== '--yes');
  const files = given.length ? given.map((f) => path.resolve(f)) : DEFAULT_FILES;
  const { uri, database, remote } = settings();
  console.log(`Loading into ${hostOf(uri)} (database "${database}")${remote ? ' - an ONLINE database' : ''}`);
  // The first block of each timetable file deletes the classes of its sections before loading them again, so
  // pointing this at the wrong database would replace real data. A database that is not on this computer
  // needs the word --yes to show it was meant.
  if (remote && !confirmed) {
    console.error('\nThis is an online database. To load into it on purpose, run:\n  npm run load-data -- --yes');
    process.exitCode = 1;
    return;
  }
  const session = writeSession();
  try {
    for (const file of files) {
      const list = statements(fs.readFileSync(file, 'utf8'));
      let nodes = 0;
      let relationships = 0;
      for (const [i, statement] of list.entries()) {
        try {
          const { summary } = await session.run(statement);
          const c = summary.counters.updates();
          nodes += c.nodesCreated;
          relationships += c.relationshipsCreated;
        } catch (err) {
          const first = statement.split('\n')[0].slice(0, 80);
          throw new Error(`${path.basename(file)}, statement ${i + 1} (${first}):\n  ${explain(err) || err.message}`);
        }
      }
      console.log(`  ${path.basename(file)}: ${list.length} statements, ${nodes} nodes and ${relationships} relationships created`);
    }
    const [check] = (await session.run(
      'RETURN COUNT { (:Section) } AS sections, COUNT { (:Class) } AS classes, COUNT { (:Room) } AS rooms, COUNT { (:Faculty) } AS faculty'
    )).records.map((r) => r.toObject());
    console.log(`Done. The database now has ${check.sections} sections, ${check.classes} classes, ${check.rooms} rooms and ${check.faculty} faculty.`);
  } finally {
    await session.close();
    await close();
  }
}

// run only when started as a script (the tests import statements() without loading anything)
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((err) => {
    console.error(`\nLoading failed. ${explain(err) || err.message}`);
    process.exitCode = 1;
  });
}
