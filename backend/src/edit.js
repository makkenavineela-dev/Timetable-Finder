// Endpoints of the "Add data" tab: add, change and remove rooms, faculty, courses, sections and classes.
// Each runs queries from neo4j/06_edit_queries.cypher in one transaction, so a refused change saves nothing.
//
// The page has no login, so changes are only accepted
//   - from the computer that runs the server (also when HOST=0.0.0.0 shares the page on a network), and
//   - from the Timetable Finder page itself: another website open in the same browser cannot send them.
import express, { Router } from 'express';
import { read, change } from './db.js';
import { E } from './queries.js';
import {
  HttpError, id, day, text, optionalText, code, optionalCode, int, optionalInt, oneOf, idList, optionalGrid
} from './validate.js';

const router = Router();

const LOCAL_ADDRESSES = new Set(['127.0.0.1', '::1', '::ffff:127.0.0.1']);
const LOCAL_HOST = /^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/i;

function guard(req, res, next) {
  if (!LOCAL_ADDRESSES.has(req.socket.remoteAddress)) {
    return next(new HttpError(403, 'Data can only be changed on the computer that runs the server.'));
  }
  // A browser always says which site sent a request (Origin). Host is checked too, because a website
  // can make its own name point at this computer.
  const host = req.headers.host || '';
  const origin = req.headers.origin;
  const allowed = [`http://${host}`, process.env.FRONTEND_URL].filter(Boolean);
  if (!LOCAL_HOST.test(host) || (origin && !allowed.includes(origin))) {
    return next(new HttpError(403, 'Changes are only accepted from the Timetable Finder page itself.'));
  }
  if (req.method === 'POST' && !req.is('application/json')) {
    return next(new HttpError(415, 'Send the data as JSON.'));
  }
  next();
}
router.use(guard, express.json({ limit: '20kb' }));

const send = (handler) => (req, res, next) => {
  Promise.resolve()
    .then(() => handler(req.body || {}, req))
    .then((body) => res.json(body))
    .catch(next);
};

// ---- formats of what people type (the hint is shown when it does not fit)
const F = {
  block: [/^[A-Z][A-Z0-9-]{0,9}$/, 'letters and digits starting with a letter, for example PJ'],
  room: [/^[A-Z0-9][A-Z0-9 -]{0,19}$/, 'letters, digits, spaces or -, for example 409 or LAB 402'],
  department: [/^[A-Z]{2,8}$/, '2 to 8 letters, for example CSE'],
  initials: [/^[A-Z]{1,6}$/, '1 to 6 letters, for example CAV'],
  cluster: [/^[A-Z0-9]{1,4}$/, '1 to 4 letters or digits, for example E'],
  course: [/^[A-Z0-9]{3,15}$/, '3 to 15 letters and digits, for example 23CS5PCAIN'],
  category: [/^[A-Z]{2,4}$/, '2 to 4 letters, for example PC, PE or HS'],
  ltp: [/^\d-\d-\d$/, 'three numbers with dashes, for example 3-0-1'],
  program: [/^[A-Z]{2,6}$/, 'letters, for example UG or PG'],
  year: [/^\d{4}-\d{2}$/, 'like 2026-27'],
  section: [/^[A-Z0-9][A-Z0-9-]{0,11}$/, 'letters and digits, for example 5E5'],
  sectionCode: [/^[A-Z0-9-]{1,12}$/, 'letters and digits, for example 5U']
};
const must = (value, name, [pattern, hint]) => code(value, name, pattern, hint);
const may = (value, name, [pattern, hint]) => optionalCode(value, name, pattern, hint);

function academicYear(value) {
  const y = must(value, 'Academic year', F.year);
  if (Number(y.slice(5)) !== (Number(y.slice(2, 4)) + 1) % 100) {
    throw new HttpError(400, 'Academic year: the second part is the next year, like 2026-27');
  }
  return y;
}

// ---- lists for the forms
router.get('/status', send(() => ({ allowed: true })));
router.get('/courses', send(() => read(E.courses)));

// ---- add or change
router.post('/rooms', send(async (b) => {
  const [row] = await change((run) => run(E.save_room, {
    block: must(b.block, 'Block', F.block),
    blockName: optionalText(b.blockName, 'Block name', 40),
    floor: int(b.floor, 'Floor', 0, 30),
    number: must(b.number, 'Room number', F.room),
    type: oneOf(b.type, 'Room type', ['CLASSROOM', 'LAB']),
    capacity: optionalInt(b.capacity, 'Seats', 1, 1000)
  }));
  return row;
}));

router.post('/faculty', send(async (b) => {
  const params = {
    department: must(b.department, 'Department', F.department),
    initials: must(b.initials, 'Initials', F.initials),
    name: text(b.name, 'Full name', 80),
    cluster: may(b.cluster, 'Cluster', F.cluster)
  };
  const [row] = await change((run) => run(E.save_faculty, params));
  if (!row) throw new HttpError(404, `There is no department ${params.department} yet. Add a section of it first.`);
  return row;
}));

router.post('/courses', send(async (b) => {
  const [row] = await change((run) => run(E.save_course, {
    semester: id(b.semester, 'semester'),
    code: must(b.code, 'Course code', F.course),
    name: text(b.name, 'Course name', 100),
    short: text(b.short, 'Short name', 12),
    category: may(b.category, 'Category', F.category),
    ltp: code(b.ltp, 'L-T-P', ...F.ltp, false),
    scheduling: oneOf(b.scheduling, 'Scheduling', ['REGULAR', 'ELECTIVE_SLOT', 'NONE'])
  }));
  if (!row) throw new HttpError(404, 'There is no such semester. Add a section of it first.');
  return row;
}));

router.post('/sections', send((b) => {
  const p = {
    department: must(b.department, 'Department', F.department),
    departmentName: optionalText(b.departmentName, 'Department name', 80),
    program: must(b.program, 'Program', F.program),
    year: academicYear(b.year),
    semester: int(b.semester, 'Semester', 1, 10),
    cluster: may(b.cluster, 'Cluster', F.cluster),
    name: must(b.name, 'Section', F.section),
    code: may(b.code, 'Section code', F.sectionCode),
    grid: optionalGrid(b.grid)
  };
  return change(async (run) => {
    const [row] = await run(E.save_section, p);
    // checked inside the transaction, so an unknown schedule saves nothing
    if (p.grid && row.grid !== p.grid) throw new HttpError(404, `There is no schedule ${p.grid}.`);
    return row;
  });
}));

router.post('/teacher', send(async (b) => {
  const params = {
    section: id(b.section, 'section'),
    course: must(b.course, 'Course', F.course),
    faculty: b.faculty ? id(b.faculty, 'faculty') : null
  };
  return change(async (run) => {
    const [row] = await run(E.set_teacher, params);
    if (!row) throw new HttpError(404, 'That section does not have this course.');
    if (params.faculty && !row.teacher) throw new HttpError(404, 'There is no such faculty member.');
    return row;
  });
}));

// ---- a class on the timetable, saved only when nothing clashes
const SUFFIX = { L: '', T: ' Tutorial', P: ' Lab' };
const slotText = (slot) => slot.replace(/-/g, ' ');

function describeClash(c) {
  const lines = [];
  const at = `${slotText(c.slot)}: `;
  if (c.sameSection) lines.push(`${at}${c.section} already has ${c.class}`);
  if (c.rooms.length) lines.push(`${at}room ${c.rooms.join(', ')} is used by ${c.section || 'another class'} (${c.class})`);
  if (c.faculty.length) lines.push(`${at}${c.faculty.join(', ')} already teaches ${c.section || 'another class'} (${c.class})`);
  return lines;
}

router.post('/classes', send((b) => {
  const kind = oneOf(b.kind, 'Kind', ['L', 'T', 'P', 'A']);
  const p = {
    section: id(b.section, 'section'),
    kind,
    course: kind === 'A' ? null : must(b.course, 'Course', F.course),
    activity: kind === 'A' ? text(b.name, 'Name', 60) : null,
    day: day(b.day),
    period: int(b.period, 'Period', 1, 9),
    rooms: idList(b.rooms, 'rooms'),
    faculty: idList(b.faculty, 'faculty')
  };
  return change(async (run) => {
    const [x] = await run(E.class_lookup, p);
    if (!x) throw new HttpError(404, 'There is no such section.');
    if (!x.first) throw new HttpError(400, 'There is no such period.');
    if (!x.working) throw new HttpError(400, 'That day is not a working day.');
    if (x.length === 2 && !x.second) {
      throw new HttpError(400, `A two-period class cannot start in P${p.period}: a break or the end of the day comes after it.`);
    }
    if (kind !== 'A') {
      if (!x.allotment) throw new HttpError(400, `${p.course} is not a course of ${x.section}'s semester.`);
      if (!x.inLtp) throw new HttpError(400, `${x.short} (L-T-P ${x.LTP}) has no ${x.kindName.toLowerCase()} part.`);
    }
    if (x.rooms.length !== p.rooms.length) throw new HttpError(404, 'One of the chosen rooms does not exist.');
    if (x.faculty.length !== p.faculty.length) throw new HttpError(404, 'One of the chosen faculty members does not exist.');

    const slots = x.second && x.length === 2 ? [x.first, x.second] : [x.first];
    const clashes = await run(E.class_clashes, { section: p.section, slots, rooms: p.rooms, faculty: p.faculty });
    if (clashes.length) throw new HttpError(409, 'Not saved: it clashes with the timetable.', clashes.flatMap(describeClash));

    const [row] = await run(E.class_create, {
      id: kind === 'A' ? `${p.section}-A-${x.first}` : `${x.allotment}-${kind}-${x.first}`,
      name: kind === 'A' ? p.activity : x.short + SUFFIX[kind],
      section: p.section, kind, allotment: x.allotment, slots, rooms: p.rooms, faculty: p.faculty
    });
    return { ...row, section: x.section, slots };
  });
}));

// ---- remove (only what nothing else depends on)
const REMOVE = {
  classes: [E.remove_class, ''],
  rooms: [E.remove_room, 'classes use it'],
  faculty: [E.remove_faculty, 'classes, lab batches or course-teacher links still name this person'],
  courses: [E.remove_course, 'classes of this course are on the timetable'],
  sections: [E.remove_section, 'the section still has classes or students']
};
router.delete('/:kind/:id', send((b, req) => {
  const entry = REMOVE[req.params.kind];
  if (!entry) throw new HttpError(404, 'No such endpoint');
  const [query, usedBy] = entry;
  const key = id(req.params.id, 'id');
  return change(async (run) => {
    const [row] = await run(query, { id: key });
    if (!row) throw new HttpError(404, 'It does not exist (any more).');
    if (row.uses > 0) throw new HttpError(409, `${row.label} was not removed: ${row.uses} ${usedBy}. Remove those first.`);
    if (req.params.kind === 'rooms') await run(E.remove_empty_places);
    return { removed: row.label };
  });
}));

export default router;
