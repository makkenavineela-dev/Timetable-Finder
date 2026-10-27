// Integration test: starts the real server against the real database.
//   Needs Neo4j running with the timetable loaded (npm run load-data) and backend/.env filled in.
//   It checks every endpoint against frontend/data.js (the snapshot of that same data).
import '../src/env.js';
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const { createApp } = await import('../src/app.js');
const { read, close, explain } = await import('../src/db.js');

const here = path.dirname(fileURLToPath(import.meta.url));
const FRONTEND = path.resolve(here, '../../frontend');

// the page's own data layer, loaded exactly as a browser would, answers from data.js
const ctx = { window: {}, console };
vm.createContext(ctx);
for (const f of ['config.js', 'data.js', 'api.js']) vm.runInContext(fs.readFileSync(path.join(FRONTEND, f), 'utf8'), ctx, { filename: f });
const snapshot = ctx.window.TT_API;
const SEC = 'CSE-UG-2026-27-S5-5E4';       // 5th semester, schedule A
const SEC3 = 'CSE-UG-2026-27-S3-3E1';      // 3rd semester, schedule B

// The snapshot's objects come from another scripting context, so copy them as plain JSON first.
// Arrays are compared without caring about order (the database may list faculty in any order).
const plain = (v) => JSON.parse(JSON.stringify(v));
const norm = (v) => {
  v = plain(v);
  const walk = (x) => Array.isArray(x) ? x.map(walk).sort((a, b) => (JSON.stringify(a) < JSON.stringify(b) ? -1 : 1))
    : x && typeof x === 'object' ? Object.fromEntries(Object.keys(x).sort().map((k) => [k, walk(x[k])])) : x;
  return walk(v);
};

let server;
let base;
before(() => new Promise((resolve) => {
  server = createApp().listen(0, '127.0.0.1', () => {
    base = `http://127.0.0.1:${server.address().port}`;
    resolve();
  });
}));
after(async () => {
  server.close();
  await close();
});

const get = async (url) => {
  const res = await fetch(base + url);
  const type = res.headers.get('content-type') || '';
  return { status: res.status, body: type.includes('json') ? await res.json() : await res.text(), type, headers: res.headers };
};

test('health: the database answers', async () => {
  const r = await get('/api/health');
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.database, 'up');
});

test('the backend connection is read-only: the database refuses a write', async () => {
  await assert.rejects(read("CREATE (:ShouldNotExist {by: 'test'})"), (err) => err.code === 'Neo.ClientError.Statement.AccessMode');
});

// ---------------------------------------------------------------- answers equal the snapshot
const sameAs = {
  'floor occupancy': ['/api/floors/PJ-F4/occupancy?slot=MON-P4', () => snapshot.floorOccupancy('PJ-F4', 'MON-P4')],
  'floor grid': ['/api/floors/PJ-F4/grid?day=MON', () => snapshot.floorGrid('PJ-F4', 'MON')],
  'free rooms': ['/api/rooms/free?building=PJ&type=CLASSROOM&slot=MON-P2',
    () => snapshot.freeRooms({ building: 'PJ', floor: null, type: 'CLASSROOM', slot: 'MON-P2', minCapacity: null })],
  'free rooms on Saturday, any block': ['/api/rooms/free?slot=SAT-P2',
    () => snapshot.freeRooms({ building: null, floor: null, type: null, slot: 'SAT-P2', minCapacity: null })],
  'room week': ['/api/rooms/PJ-406/week', () => snapshot.roomWeek('PJ-406')],
  'room week (two-room lab)': ['/api/rooms/PJ-LAB503/week', () => snapshot.roomWeek('PJ-LAB503')],
  'section week': [`/api/sections/${SEC}/week`, () => snapshot.sectionWeek(SEC)],
  'section week with a two-room class': ['/api/sections/CSE-UG-2026-27-S5-5E1/week', () => snapshot.sectionWeek('CSE-UG-2026-27-S5-5E1')],
  'section free (week)': [`/api/sections/${SEC}/free`, () => snapshot.sectionFree(SEC, null)],
  'section free (one day)': [`/api/sections/${SEC}/free?day=SAT`, () => snapshot.sectionFree(SEC, 'SAT')],
  'section free with rooms': [`/api/sections/${SEC}/free-with-rooms?day=MON&floor=PJ-F4`,
    () => snapshot.sectionFreeWithRooms(SEC, 'MON', 'PJ-F4')],
  'section courses': [`/api/sections/${SEC}/courses`, () => snapshot.courses(SEC)],
  'faculty week': ['/api/faculty/CSE-CAV/week', () => snapshot.facultyWeek('CSE-CAV')],
  'faculty free': ['/api/faculty/CSE-CAV/free?day=MON', () => snapshot.facultyFree('CSE-CAV', 'MON')],
  'floor grid in schedule B': ['/api/floors/PJ-F4/grid?day=TUE&grid=B', () => snapshot.floorGrid('PJ-F4', 'TUE', 'B')],
  'floor occupancy at a schedule B period': ['/api/floors/PJ-F4/occupancy?slot=B-MON-P3', () => snapshot.floorOccupancy('PJ-F4', 'B-MON-P3')],
  'floor occupancy at a schedule A period that overlaps it': ['/api/floors/PJ-F4/occupancy?slot=MON-P3', () => snapshot.floorOccupancy('PJ-F4', 'MON-P3')],
  'free rooms at a schedule B period': ['/api/rooms/free?slot=B-THU-P6', () => snapshot.freeRooms({ building: null, floor: null, type: null, slot: 'B-THU-P6', minCapacity: null })],
  'room week with classes of both schedules': ['/api/rooms/PJ-406/week', () => snapshot.roomWeek('PJ-406')],
  'section week of a 3rd semester section': [`/api/sections/${SEC3}/week`, () => snapshot.sectionWeek(SEC3)],
  'section free of a 3rd semester section': [`/api/sections/${SEC3}/free`, () => snapshot.sectionFree(SEC3, null)],
  'section free with rooms (schedule B)': [`/api/sections/${SEC3}/free-with-rooms?day=TUE&floor=PJ-F4`, () => snapshot.sectionFreeWithRooms(SEC3, 'TUE', 'PJ-F4')],
  'section courses of a 3rd semester section': [`/api/sections/${SEC3}/courses`, () => snapshot.courses(SEC3)],
  'faculty with classes in both schedules': ['/api/faculty/CSE-BVK/week', () => snapshot.facultyWeek('CSE-BVK')],
  'faculty free in schedule A': ['/api/faculty/CSE-BVK/free?day=TUE&grid=A', () => snapshot.facultyFree('CSE-BVK', 'TUE', 'A')],
  'faculty free in schedule B': ['/api/faculty/CSE-BVK/free?day=TUE&grid=B', () => snapshot.facultyFree('CSE-BVK', 'TUE', 'B')],
  'search': ['/api/search?q=40', () => snapshot.search('40')],
  'search for a block by its id': ['/api/search?q=other', () => snapshot.search('other')],
  'search for faculty initials': ['/api/search?q=cav', () => snapshot.search('cav')]
};
for (const [name, [url, expected]] of Object.entries(sameAs)) {
  test(`answer matches the data snapshot: ${name}`, async () => {
    const r = await get(url);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.deepEqual(norm(r.body), norm(await expected()));
  });
}

test('lists: blocks, rooms, sections, faculty and periods match the snapshot', async () => {
  const meta = await snapshot.meta();
  const rooms = await get('/api/meta/rooms');
  const sections = await get('/api/meta/sections');
  const faculty = await get('/api/meta/faculty');
  const periods = await get('/api/meta/periods');
  assert.equal(rooms.body.length, meta.rooms.length);
  const blocks = [...new Map(rooms.body.map((r) => [r.building, r.buildingName])).entries()];
  assert.deepEqual(norm(blocks), norm(meta.buildings.map((b) => [b.id, b.name])));
  assert.deepEqual(norm(sections.body.map((s) => [s.id, s.section, s.department, s.semester, s.cluster])),
    norm(meta.sections.map((s) => [s.id, s.name, s.department, s.semester, s.cluster])));
  assert.equal(faculty.body.length, meta.faculty.length);
  assert.equal(periods.body.length, meta.slots.length);
  assert.ok(periods.body.some((p) => p.day === 'SAT' && p.working === true), 'Saturday is a working day');
});

test('search finds sections, rooms, faculty and blocks only (no courses)', async () => {
  const r = await get('/api/search?q=a');
  assert.equal(r.status, 200);
  assert.ok(r.body.length > 0);
  for (const row of r.body) {
    assert.ok(['SECTION', 'ROOM', 'FACULTY', 'BUILDING'].includes(row.kind), row.kind);
    assert.deepEqual(Object.keys(row).sort(), ['id', 'kind', 'label']);
  }
});

test('a class with two rooms is one entry with two rooms', async () => {
  const r = await get('/api/sections/CSE-UG-2026-27-S5-5E1/week');
  const lab = r.body.filter((x) => x.class === 'AI Lab' && x.period === 7);
  assert.equal(lab.length, 1);
  assert.deepEqual(lab[0].rooms.map((x) => x.number).sort(), ['LAB 503', 'LAB 504']);
});

test('the schedules: A has 9 periods a day, B has 8, and sections follow their own', async () => {
  const periods = (await get('/api/meta/periods')).body;
  const perDay = (grid) => periods.filter((p) => p.grid === grid && p.day === 'MON');
  assert.equal(perDay('A').length, 9);
  assert.equal(perDay('B').length, 8);
  assert.equal(perDay('B')[2].start, '10:20');
  const week3 = (await get(`/api/sections/${SEC3}/week`)).body;
  assert.equal(week3.length, 6 * 8, 'six working days of eight periods');
  assert.equal((await get(`/api/sections/${SEC}/week`)).body.length, 6 * 9);
  const sections = (await get('/api/meta/sections')).body;
  assert.deepEqual(sections.map((s) => s.section + s.grid), ['3E1B', '3E2B', '3E3B', '3E4B', '5E1A', '5E2A', '5E3A', '5E4A']);
});

test('a room used in one schedule is busy in the overlapping period of the other', async () => {
  // 3E1 has DS in room 406 on Monday 10:20-11:15 (B-P3). Schedule A has no such period but MON-P3 (09:50-10:45) overlaps it.
  const a = (await get('/api/floors/PJ-F4/occupancy?slot=MON-P3')).body.find((r) => r.room === '406');
  assert.equal(a.status, 'OCCUPIED');
  assert.equal(a.section, '3E1');
  const b = (await get('/api/floors/PJ-F4/occupancy?slot=B-MON-P3')).body.find((r) => r.room === '406');
  assert.equal(b.status, 'OCCUPIED');
  const free = (await get('/api/rooms/free?slot=MON-P3&building=PJ&type=CLASSROOM')).body.map((r) => r.room);
  assert.ok(!free.includes('406'));
  // 14:00-14:55 (B-P6) is lunch in schedule A: no A period shares time with it
  const lunch = (await get('/api/meta/periods')).body.filter((p) => p.grid === 'A' && p.start === '14:00');
  assert.equal(lunch.length, 0);
});

test('no room or faculty member has classes in overlapping periods of the two schedules', async () => {
  const clashes = await read(`
    MATCH (x)<-[:TAUGHT_BY|IN_ROOM]-(c1:Class)-[:AT_TIME]->(t1:TimeSlot)-[:OVERLAPS]-(t2:TimeSlot)<-[:AT_TIME]-(c2:Class)-[:TAUGHT_BY|IN_ROOM]->(x)
    WHERE c1.id < c2.id
    RETURN labels(x)[0] AS kind, x.id AS who, c1.id AS first, c2.id AS second`);
  assert.deepEqual(clashes, []);
});

test('every course of a 3rd semester section has the classes its L-T-P needs', async () => {
  for (const sec of ['3E1', '3E2', '3E3', '3E4']) {
    const courses = (await get(`/api/sections/CSE-UG-2026-27-S3-${sec}/courses`)).body;
    for (const c of courses.filter((x) => x.scheduling === 'REGULAR')) {
      assert.equal(c.classesAllotted, c.classesNeeded, `${sec} ${c.course}`);
    }
  }
});

test('the Monday free periods of 5E4 are right', async () => {
  const r = await get(`/api/sections/${SEC}/free?day=MON`);
  assert.deepEqual(r.body[0].free.map((f) => f.slot), ['MON-P1', 'MON-P2', 'MON-P3', 'MON-P9']);
});

test('no section, faculty member or room has two classes at the same time', async () => {
  const clashes = await read(`
    MATCH (x)<-[:FOR_SECTION|TAUGHT_BY|IN_ROOM]-(cl:Class)-[:AT_TIME]->(t:TimeSlot)
    WITH x, t, count(DISTINCT cl) AS n WHERE n > 1
    RETURN labels(x)[0] AS kind, coalesce(x.id, x.name) AS who, t.id AS slot, n`);
  assert.deepEqual(clashes, []);
});

// ---------------------------------------------------------------- bad input is refused
const refused = {
  'a slot that is not a period': '/api/floors/PJ-F4/occupancy?slot=MON-P10',
  'a missing slot': '/api/floors/PJ-F4/occupancy',
  'a day that does not exist': '/api/floors/PJ-F4/grid?day=SUN',
  'a room type that does not exist': '/api/rooms/free?slot=MON-P2&type=HALL',
  'seats that are not a number': '/api/rooms/free?slot=MON-P2&minCapacity=abc',
  'seats below one': '/api/rooms/free?slot=MON-P2&minCapacity=0',
  'an id with odd characters': '/api/sections/x%27%20OR%201=1%20--/week',
  'an id with a semicolon': '/api/faculty/CSE-CAV;DROP/week',
  'empty search text': '/api/search?q=',
  'search text that is too long': '/api/search?q=' + 'a'.repeat(41),
  'a missing day for free-with-rooms': `/api/sections/${SEC}/free-with-rooms?floor=PJ-F4`,
  'a schedule letter that is two letters': '/api/rooms/free?slot=BB-MON-P1',
  'a schedule that is not a letter': '/api/faculty/CSE-CAV/free?grid=b1',
  'a schedule in the floor grid that is not a letter': '/api/floors/PJ-F4/grid?day=MON&grid=1'
};
for (const [name, url] of Object.entries(refused)) {
  test(`refused with 400: ${name}`, async () => {
    const r = await get(url);
    assert.equal(r.status, 400, `${url} -> ${r.status} ${JSON.stringify(r.body)}`);
    assert.ok(r.body.error);
  });
}

test('search text with quotes is treated as plain text', async () => {
  const r = await get('/api/search?q=' + encodeURIComponent(`' OR 1=1 //`));
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, []);
});

test('an unknown id is an empty answer, not an error', async () => {
  const r = await get('/api/sections/NOT-A-SECTION/week');
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, []);
});

// ---------------------------------------------------------------- the page and its files
test('the page is served at /', async () => {
  const r = await get('/');
  assert.equal(r.status, 200);
  assert.match(r.body, /Timetable Finder/);
});

test('the page only loads its own files and cannot be framed', async () => {
  const r = await get('/');
  assert.match(r.headers.get('content-security-policy'), /default-src 'self'/);
  assert.match(r.headers.get('content-security-policy'), /frame-ancestors 'none'/);
  assert.equal(r.headers.get('x-content-type-options'), 'nosniff');
  // the page must not need inline styles or scripts, which that policy blocks
  assert.doesNotMatch(r.body, /<script>|style=/);
  for (const file of ['app.js', 'edit.js']) assert.doesNotMatch(fs.readFileSync(path.join(FRONTEND, file), 'utf8'), /style:/);
});

test('config.js points the page at this server', async () => {
  const r = await get('/config.js');
  assert.equal(r.status, 200);
  assert.match(r.body, /API_URL: location\.origin/);
});

for (const file of ['style.css', 'app.js', 'edit.js', 'api.js', 'data.js']) {
  test(`page file is served: ${file}`, async () => assert.equal((await get('/' + file)).status, 200));
}

for (const url of ['/README.md', '/.env', '/..%2f..%2fbackend%2f.env', '/backend/.env', '/package.json', '/scripts/load-data.js']) {
  test(`not served: ${url}`, async () => assert.equal((await get(url)).status, 404));
}

test('an unknown API address gives a JSON 404', async () => {
  const r = await get('/api/nothing');
  assert.equal(r.status, 404);
  assert.ok(r.body.error);
});

// ---------------------------------------------------------------- friendly database messages
test('database problems are explained in plain words', () => {
  assert.match(explain({ code: 'ServiceUnavailable' }), /running/);
  assert.match(explain({ code: 'Neo.ClientError.Security.Unauthorized' }), /NEO4J_PASSWORD/);
  assert.match(explain({ code: 'Neo.ClientError.Security.AuthenticationRateLimit' }), /too many/);
  assert.match(explain({ code: 'Neo.ClientError.Security.CredentialsExpired' }), /changed/);
  assert.match(explain({ code: 'Neo.ClientError.Database.DatabaseNotFound' }), /NEO4J_DATABASE/);
  assert.equal(explain(new Error('something else')), null);
});
