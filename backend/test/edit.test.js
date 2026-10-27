// Integration test of the Add data endpoints (src/edit.js) against the real database.
// Everything it creates has an id (or course code) starting with ZZT and is removed again at the end.
import '../src/env.js';
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

const { createApp } = await import('../src/app.js');
const { change, close } = await import('../src/db.js');

const SEMESTER = 'ZZT-UG-2099-00-S1';
const Z1 = `${SEMESTER}-Z1`;
const Z2 = `${SEMESTER}-Z2`;
const Z3 = `${SEMESTER}-Z3`;   // follows schedule B
const COURSE = 'ZZT1COURSE';
const cleanUp = () => change((run) => run("MATCH (n) WHERE n.id STARTS WITH 'ZZT' OR n.code STARTS WITH 'ZZT' DETACH DELETE n"));

let server;
let port;
before(async () => {
  await cleanUp();
  await new Promise((resolve) => {
    server = createApp().listen(0, '127.0.0.1', () => {
      port = server.address().port;
      resolve();
    });
  });
});
after(async () => {
  server.close();
  await cleanUp();
  await close();
});

// node:http (not fetch) so the tests can also send the Host and Origin a browser on another site would send
function call(method, path, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? null : typeof body === 'string' ? body : JSON.stringify(body);
    const req = http.request({
      host: '127.0.0.1', port, method, path,
      headers: { ...(data ? { 'content-type': 'application/json', 'content-length': Buffer.byteLength(data) } : {}), ...headers }
    }, (res) => {
      let text = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => { text += chunk; });
      res.on('end', () => {
        let json = null;
        try { json = JSON.parse(text); } catch { /* not JSON */ }
        resolve({ status: res.statusCode, body: json });
      });
    });
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}
const post = (what, body) => call('POST', `/api/edit/${what}`, body);
const ok = (r) => assert.equal(r.status, 200, JSON.stringify(r.body));
const lecture = (extra) => ({ section: Z1, kind: 'L', course: COURSE, day: 'MON', period: 1, rooms: [], faculty: [], ...extra });

// ---------------------------------------------------------------- who may change data
test('changes are allowed from this computer', async () => {
  const r = await call('GET', '/api/edit/status');
  ok(r);
  assert.equal(r.body.allowed, true);
});

test('a request sent by another website is refused', async () => {
  const r = await call('POST', '/api/edit/rooms', { block: 'ZZT', floor: 1, number: '1', type: 'LAB' }, { origin: 'http://evil.example' });
  assert.equal(r.status, 403);
});

test('a request for another host name (DNS rebinding) is refused', async () => {
  const r = await call('GET', '/api/edit/status', undefined, { host: 'evil.example' });
  assert.equal(r.status, 403);
});

test('data that is not JSON is refused', async () => {
  const r = await call('POST', '/api/edit/rooms', 'block=ZZT', { 'content-type': 'text/plain' });
  assert.equal(r.status, 415);
});

test('broken JSON gets a clear answer', async () => {
  const r = await call('POST', '/api/edit/rooms', '{"block":', {});
  assert.equal(r.status, 400);
  assert.match(r.body.error, /JSON/);
});

test('a wrong value is refused with a hint', async () => {
  const r = await post('rooms', { block: 'ZZT', floor: 'x', number: '101', type: 'CLASSROOM' });
  assert.equal(r.status, 400);
  assert.match(r.body.error, /^Floor/);
  const r2 = await post('sections', { department: 'ZZT', program: 'UG', year: '2099-01', semester: 1, name: 'Z1' });
  assert.equal(r2.status, 400);
  assert.match(r2.body.error, /Academic year/);
});

// ---------------------------------------------------------------- adding
test('add a section: department, program, year and semester are created too', async () => {
  const r = await post('sections', { department: 'zzt', departmentName: 'Test department', program: 'UG', year: '2099-00', semester: 1, cluster: 'z', name: 'z1' });
  ok(r);
  assert.deepEqual(r.body, { id: Z1, name: 'Z1', created: true, grid: 'A' });
  ok(await post('sections', { department: 'ZZT', program: 'UG', year: '2099-00', semester: 1, cluster: 'Z', name: 'Z2' }));
  const again = await post('sections', { department: 'ZZT', program: 'UG', year: '2099-00', semester: 1, name: 'Z1' });
  assert.equal(again.body.created, false);
  assert.equal(again.body.grid, 'A', 'the default schedule');
  const b = await post('sections', { department: 'ZZT', program: 'UG', year: '2099-00', semester: 1, cluster: 'Z', name: 'Z3', grid: 'B' });
  ok(b);
  assert.equal(b.body.grid, 'B');
  const list = (await call('GET', '/api/meta/sections')).body.filter((s) => s.department === 'ZZT');
  assert.deepEqual(list.map((s) => [s.id, s.cluster, s.semesterId, s.grid]),
    [[Z1, 'Z', SEMESTER, 'A'], [Z2, 'Z', SEMESTER, 'A'], [Z3, 'Z', SEMESTER, 'B']]);
});

test('an unknown schedule is refused and the section is not created', async () => {
  const r = await post('sections', { department: 'ZZT', program: 'UG', year: '2099-00', semester: 1, name: 'ZNOPE', grid: 'Q' });
  assert.equal(r.status, 404);
  assert.match(r.body.error, /schedule Q/);
  const list = (await call('GET', '/api/meta/sections')).body.filter((s) => s.section === 'ZNOPE');
  assert.deepEqual(list, []);
});

test('add a room, then change it: a new block and floor are made, and the room is not doubled', async () => {
  const r = await post('rooms', { block: 'ZZT', blockName: 'Test block', floor: 1, number: '101', type: 'CLASSROOM' });
  ok(r);
  assert.deepEqual(r.body, { id: 'ZZT-101', number: '101', floor: 'ZZT-F1', created: true });
  const r2 = await post('rooms', { block: 'ZZT', floor: '1', number: '101', type: 'CLASSROOM', capacity: '60' });
  assert.equal(r2.body.created, false);
  ok(await post('rooms', { block: 'ZZT', floor: 1, number: 'lab 102', type: 'LAB' }));
  const rooms = (await call('GET', '/api/meta/rooms')).body.filter((x) => x.building === 'ZZT');
  assert.deepEqual(rooms.map((x) => [x.roomId, x.room, x.capacity, x.buildingName]),
    [['ZZT-101', '101', 60, 'Test block'], ['ZZT-LAB102', 'LAB 102', null, 'Test block']]);
});

test('add faculty members', async () => {
  const r = await post('faculty', { department: 'ZZT', initials: 'abc', name: 'Prof. A B C', cluster: 'Z' });
  ok(r);
  assert.deepEqual(r.body, { id: 'ZZT-ABC', name: 'Prof. A B C', created: true });
  ok(await post('faculty', { department: 'ZZT', initials: 'XYZ', name: 'Prof. X Y Z' }));
  const missing = await post('faculty', { department: 'NODEPT', initials: 'Q', name: 'Q' });
  assert.equal(missing.status, 404);
});

test('add a course: every section of the semester gets it, with classes needed from its L-T-P', async () => {
  const r = await post('courses', { semester: SEMESTER, code: COURSE, name: 'Test course', short: 'ZT1', category: 'PC', ltp: '3-0-1', scheduling: 'REGULAR' });
  ok(r);
  assert.equal(r.body.created, true);
  for (const sec of [Z1, Z2, Z3]) {
    const courses = (await call('GET', `/api/sections/${sec}/courses`)).body;
    assert.deepEqual(courses.map((c) => [c.code, c.LTP, c.classesNeeded, c.classesAllotted]), [[COURSE, '3-0-1', 4, 0]]);
  }
});

test('set the course teacher', async () => {
  ok(await post('teacher', { section: Z1, course: COURSE, faculty: 'ZZT-ABC' }));
  const courses = (await call('GET', `/api/sections/${Z1}/courses`)).body;
  assert.deepEqual(courses[0].teacher, ['ABC']);
});

test('add a lecture: it shows in the section week, the room and the faculty timetable', async () => {
  const r = await post('classes', lecture({ rooms: ['ZZT-101'], faculty: ['ZZT-ABC'] }));
  ok(r);
  assert.equal(r.body.name, 'ZT1');
  assert.deepEqual(r.body.slots, ['MON-P1']);
  const week = (await call('GET', `/api/sections/${Z1}/week`)).body;
  const p1 = week.find((x) => x.day === 'MON' && x.period === 1);
  assert.equal(p1.class, 'ZT1');
  assert.deepEqual(p1.rooms.map((x) => x.id), ['ZZT-101']);
  assert.equal((await call('GET', '/api/rooms/ZZT-101/week')).body.length, 1);
  assert.equal((await call('GET', '/api/faculty/ZZT-ABC/week')).body.length, 1);
});

test('clashes are refused and every clash is listed', async () => {
  const sameSection = await post('classes', lecture({ period: '1' }));
  assert.equal(sameSection.status, 409);
  assert.match(sameSection.body.details.join(' '), /Z1 already has ZT1/);
  const room = await post('classes', lecture({ section: Z2, rooms: ['ZZT-101'], faculty: ['ZZT-ABC'] }));
  assert.equal(room.status, 409);
  assert.equal(room.body.details.length, 2);
  assert.match(room.body.details.join(' '), /room 101 is used by Z1/);
  assert.match(room.body.details.join(' '), /ABC already teaches Z1/);
  assert.equal((await post('classes', lecture({ section: Z2, faculty: ['ZZT-XYZ'] }))).status, 200, 'another section, room and teacher is fine');
});

test('a section on schedule B uses its own periods, and clashes with schedule A are found', async () => {
  // Z1 (schedule A) has room ZZT-101 on MON-P1 (08:00-08:55). Z3 follows schedule B: its P1 is the same time.
  const clash = await post('classes', lecture({ section: Z3, rooms: ['ZZT-101'] }));
  assert.equal(clash.status, 409);
  assert.match(clash.body.details.join(' '), /B MON P1: room 101 is used by Z1/);
  // Z3's P3 is 10:20-11:15: it overlaps A's P3 (09:50-10:45) but not A's P4. Put Z1 in the room at A-P3 first.
  ok(await post('classes', lecture({ period: 3, rooms: ['ZZT-101'] })));
  const overlap = await post('classes', lecture({ section: Z3, period: 3, rooms: ['ZZT-101'] }));
  assert.equal(overlap.status, 409, 'B-P3 shares time with A-P3');
  assert.match(overlap.body.details.join(' '), /B MON P3: room 101 is used by Z1/);
  // B-P6 (14:00-14:55) shares time with no period of schedule A, so the same room is free then
  const lunch = await post('classes', lecture({ section: Z3, period: 6, rooms: ['ZZT-101'] }));
  ok(lunch);
  assert.deepEqual(lunch.body.slots, ['B-MON-P6']);
  const week = (await call('GET', `/api/sections/${Z3}/week`)).body;
  assert.equal(week.length, 6 * 8, 'eight periods a day');
  assert.equal(week.find((x) => x.day === 'MON' && x.period === 6).class, 'ZT1');
  // faculty are checked across schedules too: ABC teaches Z1 on MON-P1
  const teacher = await post('classes', lecture({ section: Z3, day: 'MON', period: 1, faculty: ['ZZT-ABC'] }));
  assert.equal(teacher.status, 409);
  assert.match(teacher.body.details.join(' '), /ABC already teaches Z1/);
  // a two-period class cannot start in B-P2 (the tea break follows it)
  assert.equal((await post('classes', lecture({ section: Z3, kind: 'P', day: 'TUE', period: 2 }))).status, 400);
  assert.equal((await post('classes', lecture({ section: Z3, kind: 'P', day: 'TUE', period: 3 }))).status, 200);
});

test('a lab takes two periods in a row, and cannot start right before a break', async () => {
  const lab = await post('classes', lecture({ kind: 'P', day: 'TUE', rooms: ['ZZT-LAB102'] }));
  ok(lab);
  assert.equal(lab.body.name, 'ZT1 Lab');
  assert.deepEqual(lab.body.slots, ['TUE-P1', 'TUE-P2']);
  const beforeBreak = await post('classes', lecture({ kind: 'P', day: 'WED', period: 3 }));
  assert.equal(beforeBreak.status, 400);
  assert.match(beforeBreak.body.error, /break/);
});

test('a kind the course does not have is refused', async () => {
  const r = await post('classes', lecture({ kind: 'T', day: 'THU' }));
  assert.equal(r.status, 400);
  assert.match(r.body.error, /no tutorial part/);
});

test('an activity needs a name but no course', async () => {
  const r = await post('classes', { section: Z1, kind: 'A', name: 'Proctor meet', day: 'WED', period: 9 });
  ok(r);
  assert.equal(r.body.name, 'Proctor meet');
});

// ---------------------------------------------------------------- removing
test('what is still used is not removed', async () => {
  for (const [what, id] of [['rooms', 'ZZT-101'], ['faculty', 'ZZT-ABC'], ['courses', COURSE], ['sections', Z1]]) {
    const r = await call('DELETE', `/api/edit/${what}/${id}`);
    assert.equal(r.status, 409, `${what} ${id}: ${JSON.stringify(r.body)}`);
  }
});

test('remove classes, then the room, course, faculty and sections', async () => {
  for (const sec of [Z1, Z2, Z3]) {
    const ids = new Set((await call('GET', `/api/sections/${sec}/week`)).body.map((x) => x.classId).filter(Boolean));
    for (const id of ids) ok(await call('DELETE', `/api/edit/classes/${id}`));
  }
  assert.equal((await call('GET', `/api/sections/${Z1}/week`)).body.filter((x) => x.classId).length, 0);
  ok(await call('DELETE', '/api/edit/rooms/ZZT-101'));
  ok(await call('DELETE', '/api/edit/rooms/ZZT-LAB102'));
  assert.equal((await call('GET', '/api/meta/rooms')).body.filter((x) => x.building === 'ZZT').length, 0, 'the empty block is gone');
  ok(await call('DELETE', `/api/edit/courses/${COURSE}`));
  assert.deepEqual((await call('GET', `/api/sections/${Z1}/courses`)).body, []);
  ok(await call('DELETE', '/api/edit/faculty/ZZT-ABC'));
  ok(await call('DELETE', '/api/edit/faculty/ZZT-XYZ'));
  ok(await call('DELETE', `/api/edit/sections/${Z1}`));
  ok(await call('DELETE', `/api/edit/sections/${Z2}`));
  ok(await call('DELETE', `/api/edit/sections/${Z3}`));
  assert.equal((await call('DELETE', `/api/edit/sections/${Z2}`)).status, 404);
});
