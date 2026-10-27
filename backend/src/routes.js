// The 15 read-only endpoints. Each one runs one query from neo4j/05_app_queries.cypher.
import { Router } from 'express';
import { read } from './db.js';
import { Q } from './queries.js';
import { id, optionalId, slot, day, optionalDay, optionalGrid, optionalType, optionalSeats, searchText } from './validate.js';

const router = Router();

// Express 4 does not catch errors thrown in async handlers, so every handler goes through this.
const route = (handler) => (req, res, next) => {
  Promise.resolve()
    .then(() => handler(req))
    .then((rows) => res.json(rows))
    .catch(next);
};

// ---- lists for the filters
router.get('/meta/rooms', route(() => read(Q.meta_rooms)));
router.get('/meta/sections', route(() => read(Q.meta_sections)));
router.get('/meta/faculty', route(() => read(Q.meta_faculty)));
router.get('/meta/periods', route(() => read(Q.meta_periods)));

// ---- search box
router.get('/search', route((req) => read(Q.search, { q: searchText(req.query.q) })));

// ---- floors: free or occupied rooms
router.get('/floors/:floorId/occupancy', route((req) =>
  read(Q.floor_occupancy, { floor: id(req.params.floorId, 'floor'), slot: slot(req.query.slot) })));
router.get('/floors/:floorId/grid', route((req) =>
  read(Q.floor_day_grid, { floor: id(req.params.floorId, 'floor'), day: day(req.query.day), grid: optionalGrid(req.query.grid) })));

// ---- rooms
router.get('/rooms/free', route((req) => read(Q.free_rooms, {
  building: optionalId(req.query.building, 'building'),
  floor: optionalId(req.query.floor, 'floor'),
  type: optionalType(req.query.type),
  slot: slot(req.query.slot),
  minCapacity: optionalSeats(req.query.minCapacity)
})));
router.get('/rooms/:roomId/week', route((req) => read(Q.room_week, { room: id(req.params.roomId, 'room') })));

// ---- sections
router.get('/sections/:id/week', route((req) => read(Q.section_week, { section: id(req.params.id, 'section') })));
router.get('/sections/:id/free', route((req) =>
  read(Q.section_free_time, { section: id(req.params.id, 'section'), day: optionalDay(req.query.day) })));
router.get('/sections/:id/free-with-rooms', route((req) => read(Q.section_free_with_rooms, {
  section: id(req.params.id, 'section'), day: day(req.query.day), floor: id(req.query.floor, 'floor')
})));
router.get('/sections/:id/courses', route((req) => read(Q.course_summary, { section: id(req.params.id, 'section') })));

// ---- faculty
router.get('/faculty/:id/week', route((req) => read(Q.faculty_week, { faculty: id(req.params.id, 'faculty') })));
router.get('/faculty/:id/free', route((req) =>
  read(Q.faculty_free_time, { faculty: id(req.params.id, 'faculty'), day: optionalDay(req.query.day), grid: optionalGrid(req.query.grid) })));

export default router;
