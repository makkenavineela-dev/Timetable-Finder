// Checks the database named in backend/.env and says what is wrong, in plain words:
//   npm run check-db
// It only reads. It prints the host (never the password), whether the login works, the Neo4j version, whether
// the schema is there, how much data there is, and a list of integrity checks. Exit code 1 = a real problem.
import '../src/env.js';
import { read, close, explain, settings, hostOf, waitForDatabase } from '../src/db.js';

let errors = 0;
let warnings = 0;
const ok = (text) => console.log(`  ok     ${text}`);
const warn = (text) => { warnings++; console.log(`  WARN   ${text}`); };
const bad = (text) => { errors++; console.log(`  PROBLEM ${text}`); };

// integrity checks: each query returns the rows that are wrong
const CHECKS = [
  ['error', 'every section follows a bell schedule', `MATCH (s:Section) WHERE NOT (s)-[:FOLLOWS]->(:TimeGrid) RETURN s.id AS what`],
  ['error', 'every section belongs to a semester', `MATCH (s:Section) WHERE NOT (:Semester)-[:HAS_SECTION]->(s) RETURN s.id AS what`],
  ['error', 'every class belongs to a section', `MATCH (c:Class) WHERE NOT (c)-[:FOR_SECTION]->(:Section) RETURN c.id AS what`],
  ['error', 'every class has at least one period', `MATCH (c:Class) WHERE NOT (c)-[:AT_TIME]->(:TimeSlot) RETURN c.id AS what`],
  ['error', 'every class period belongs to the schedule its section follows', `
    MATCH (sec:Section)-[:FOLLOWS]->(g:TimeGrid), (sec)<-[:FOR_SECTION]-(c:Class)-[:AT_TIME]->(t:TimeSlot)
    WHERE t.grid <> g.id RETURN DISTINCT c.id AS what`],
  ['error', 'every allotment is of a course', `MATCH (a:Allotment) WHERE NOT (a)-[:OF_COURSE]->(:Course) RETURN a.id AS what`],
  ['error', 'every faculty member has a department', `MATCH (f:Faculty) WHERE NOT (f)-[:WORKS_IN]->(:Department) RETURN f.id AS what`],
  ['error', 'every room is on a floor', `MATCH (r:Room) WHERE NOT (:Floor)-[:HAS_ROOM]->(r) RETURN r.id AS what`],
  ['error', 'no room number is used twice in one block', `
    MATCH (b:Building)-[:HAS_FLOOR]->(:Floor)-[:HAS_ROOM]->(r:Room)
    WITH b, r.number AS number, count(*) AS k WHERE k > 1 RETURN b.id + ' ' + number AS what`],
  ['error', 'every period overlaps itself (needed for room and teacher busy checks)', `MATCH (t:TimeSlot) WHERE NOT (t)-[:OVERLAPS]-(t) RETURN t.id AS what`],
  ['error', 'no section, teacher or room has two classes at the same time (also across schedules)', `
    MATCH (sec:Section)<-[:FOR_SECTION]-(cl:Class)-[:AT_TIME]->(t:TimeSlot)
    WITH 'section' AS kind, sec.id AS who, t, collect(cl.id) AS classes WHERE size(classes) > 1
    RETURN kind + ' ' + who + ' at ' + t.id AS what
    UNION
    MATCH (x)<-[:TAUGHT_BY|IN_ROOM]-(c1:Class)-[:AT_TIME]->(t1:TimeSlot)-[:OVERLAPS]-(t2:TimeSlot)<-[:AT_TIME]-(c2:Class)-[:TAUGHT_BY|IN_ROOM]->(x)
    WHERE c1.id < c2.id RETURN x.id + ' at ' + t1.id + ' / ' + t2.id AS what`],
  ['warn', 'every class of a regular course has a room', `
    MATCH (a:Allotment)-[:HAS_CLASS]->(c:Class), (a)-[:OF_COURSE]->(:Course {scheduling: 'REGULAR'})
    WHERE NOT (c)-[:IN_ROOM]->(:Room) RETURN c.id AS what`],
  ['warn', 'every class of a regular course has a teacher', `
    MATCH (a:Allotment)-[:HAS_CLASS]->(c:Class), (a)-[:OF_COURSE]->(:Course {scheduling: 'REGULAR'})
    WHERE NOT (c)-[:TAUGHT_BY]->(:Faculty) RETURN c.id AS what`],
  ['warn', 'every regular course has its classes (classes allotted = classes needed)', `
    MATCH (sec:Section)-[:HAS_ALLOTMENT]->(a:Allotment)-[:OF_COURSE]->(c:Course {scheduling: 'REGULAR'})
    WITH sec, c, COUNT { (a)-[:HAS_CLASS]->() } AS have, reduce(n = 0, x IN [(c)-[q:HAS_LTP]->() | q.classesPerWeek] | n + x) AS need
    WHERE have <> need RETURN sec.name + ' ' + c.short + ' (' + toString(have) + ' of ' + toString(need) + ')' AS what`],
  ['warn', 'no test data is left behind (ids starting with ZZT)', `MATCH (n) WHERE n.id STARTS WITH 'ZZT' OR n.code STARTS WITH 'ZZT' RETURN coalesce(n.id, n.code) AS what`]
];

async function main() {
  const { uri, user, database, remote } = settings();
  console.log('Database check');
  console.log(`  host      ${hostOf(uri)}${remote ? ' (online)' : ' (this computer)'}`);
  console.log(`  address   ${uri.replace(/^([a-z0-9+]+):\/\/.*$/i, '$1://...')}   encrypted: ${/\+s/i.test(uri) ? 'yes' : 'no'}`);
  console.log(`  user      ${user}      database  ${database}      password  ${process.env.NEO4J_PASSWORD ? 'set' : 'EMPTY'}`);
  console.log('');

  if (!process.env.NEO4J_PASSWORD) {
    bad('NEO4J_PASSWORD in backend/.env is empty. Open the file and type the password after NEO4J_PASSWORD=');
    return;
  }

  console.log('Connection');
  const reached = await waitForDatabase({ totalMs: remote ? 90000 : 15000 });
  if (!reached.ok) {
    bad(explain(reached.error) || reached.error.message);
    return;
  }
  ok(`connected and logged in (${reached.ms} ms for one question)`);
  const [version] = await read('CALL dbms.components() YIELD name, versions, edition RETURN name, versions[0] AS version, edition');
  ok(`${version.name} ${version.version} ${version.edition}`);

  console.log('\nSchema');
  const [{ n: constraints }] = await read('SHOW CONSTRAINTS YIELD name RETURN count(*) AS n');
  const [{ n: indexes }] = await read("SHOW INDEXES YIELD name, state WHERE state = 'ONLINE' AND name <> 'lookup' RETURN count(*) AS n").catch(() => [{ n: -1 }]);
  if (constraints >= 20) ok(`${constraints} unique keys, ${indexes >= 0 ? indexes + ' indexes online' : 'indexes not listed'}`);
  else bad(`only ${constraints} unique keys (20 expected): the schema is not loaded. Run: npm run load-data${remote ? ' -- --yes' : ''}`);

  console.log('\nData');
  const [c] = await read(`RETURN COUNT { (:Section) } AS sections, COUNT { (:Class) } AS classes, COUNT { (:Room) } AS rooms,
    COUNT { (:Faculty) } AS faculty, COUNT { (:Course) } AS courses, COUNT { (:TimeSlot) } AS periods, COUNT { (:TimeGrid) } AS schedules,
    COUNT { () } AS nodes, COUNT { ()-->() } AS relationships`);
  console.log(`  ${c.nodes} nodes, ${c.relationships} relationships: ${c.sections} sections, ${c.classes} classes, ${c.rooms} rooms, ${c.faculty} faculty, ${c.courses} courses, ${c.periods} periods, ${c.schedules} schedules`);
  if (!c.sections || !c.classes) {
    bad(`the database holds no timetable. Run: npm run load-data${remote ? ' -- --yes' : ''}`);
    return;
  }

  console.log('\nChecks');
  for (const [level, title, query] of CHECKS) {
    const rows = await read(query);
    if (!rows.length) ok(title);
    else {
      const sample = rows.slice(0, 4).map((r) => r.what).join('; ') + (rows.length > 4 ? `; and ${rows.length - 4} more` : '');
      (level === 'error' ? bad : warn)(`${title}: ${rows.length} found (${sample})`);
    }
  }
}

main()
  .catch((err) => bad(explain(err) || err.message))
  .finally(async () => {
    await close();
    console.log(`\n${errors ? `${errors} problem(s)` : 'No problems'}${warnings ? `, ${warnings} warning(s)` : ''}.`);
    process.exitCode = errors ? 1 : 0;
  });
