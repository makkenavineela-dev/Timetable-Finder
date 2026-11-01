// Data layer. The screens in app.js only call window.TT_API, so they do not care where the data comes from.
//   Remote - asks the backend API (used when config.js has an API_URL)
//   Local  - answers the same questions from the snapshot in data.js
// Both return rows shaped like the Cypher queries in neo4j/05_app_queries.cypher.
(function () {
  'use strict';
  var API = ((window.TT_CONFIG || {}).API_URL || '').replace(/\/$/, '');
  var enc = encodeURIComponent;

  /* ------------------------------------------------------------------ Remote */
  function request(path, options) {
    return fetch(API + path, options).catch(function () {
      // fetch only fails like this when the server cannot be reached at all
      throw new Error('Cannot reach the Timetable Finder server at ' + API + '. Start it again (start_timetable_finder.bat), then try again.');
    }).then(function (res) {
      if (res.ok) return res.json();
      // the backend explains problems in {"error": "...", "details": ["..."]}
      return res.json().catch(function () { return {}; }).then(function (body) {
        var err = new Error(body.error || 'The server answered ' + res.status + ' for ' + path);
        err.details = body.details || [];
        throw err;
      });
    });
  }
  function get(path, params) {
    var qs = new URLSearchParams(Object.entries(params || {}).filter(function (e) { return e[1] != null && e[1] !== ''; }));
    return request(path + (qs.toString() ? '?' + qs : ''));
  }
  // changes (Add data tab): JSON in, JSON out
  function send(method, path, body) {
    return request(path, body === undefined ? { method: method }
      : { method: method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  }

  var Remote = {
    mode: 'api',
    label: API,
    meta: function () {
      return Promise.all([get('/api/meta/rooms'), get('/api/meta/sections'), get('/api/meta/faculty'), get('/api/meta/periods')])
        .then(function (r) {
          var rooms = r[0], sections = r[1], faculty = r[2], periods = r[3];
          var buildings = new Map(), floors = new Map(), days = new Map(), grids = new Map(), depts = new Map();
          // department id -> full name, from the sections and from the faculty (a department can have only faculty)
          sections.concat(faculty).forEach(function (x) {
            if (x.department && (!depts.has(x.department) || !depts.get(x.department).name)) {
              depts.set(x.department, { id: x.department, name: x.departmentName || x.department });
            }
          });
          rooms.forEach(function (x) {
            buildings.set(x.building, { id: x.building, name: x.buildingName || x.building });
            floors.set(x.floorId, { id: x.floorId, building: x.building, number: x.floor });
          });
          periods.forEach(function (x) {
            days.set(x.day, { id: x.day, name: x.dayName, order: x.dayOrder, working: x.working });
            grids.set(x.grid, { id: x.grid, name: x.gridName, default: !!x.defaultGrid });
          });
          return {
            departments: Array.from(depts.values()).sort(function (a, b) { return a.id < b.id ? -1 : 1; }),
            buildings: Array.from(buildings.values()),
            floors: Array.from(floors.values()),
            rooms: rooms.map(function (x) { return { id: x.roomId, number: x.room, floor: x.floorId, type: x.type, capacity: x.capacity }; }),
            days: Array.from(days.values()).sort(function (a, b) { return a.order - b.order; }),
            grids: Array.from(grids.values()).sort(function (a, b) { return a.id < b.id ? -1 : 1; }),
            slots: periods.map(function (x) { return { id: x.slot, grid: x.grid, day: x.day, period: x.period, start: x.start, end: x.end }; }),
            sections: sections.map(function (x) {
              return { id: x.id, name: x.section, department: x.department, program: x.program, year: x.year, semester: x.semester, semesterId: x.semesterId, cluster: x.cluster, grid: x.grid };
            }),
            faculty: faculty
          };
        });
    },
    floorOccupancy: function (floor, slot) { return get('/api/floors/' + enc(floor) + '/occupancy', { slot: slot }); },
    floorGrid: function (floor, day, grid) { return get('/api/floors/' + enc(floor) + '/grid', { day: day, grid: grid }); },
    freeRooms: function (f) { return get('/api/rooms/free', f); },
    roomWeek: function (id) { return get('/api/rooms/' + enc(id) + '/week'); },
    sectionWeek: function (id) { return get('/api/sections/' + enc(id) + '/week'); },
    sectionFree: function (id, day) { return get('/api/sections/' + enc(id) + '/free', { day: day }); },
    sectionFreeWithRooms: function (id, day, floor) { return get('/api/sections/' + enc(id) + '/free-with-rooms', { day: day, floor: floor }); },
    courses: function (id) { return get('/api/sections/' + enc(id) + '/courses'); },
    facultyWeek: function (id) { return get('/api/faculty/' + enc(id) + '/week'); },
    facultyFree: function (id, day, grid) { return get('/api/faculty/' + enc(id) + '/free', { day: day, grid: grid }); },
    search: function (q) { return get('/api/search', { q: q }); },
    // Add data tab. what: rooms, faculty, courses, sections, classes or teacher
    editStatus: function () { return get('/api/edit/status'); },
    courseList: function () { return get('/api/edit/courses'); },
    save: function (what, data) { return send('POST', '/api/edit/' + what, data); },
    remove: function (what, id) { return send('DELETE', '/api/edit/' + what + '/' + enc(id)); }
  };

  /* ------------------------------------------------------------------- Local */
  function makeLocal(D) {
    var roomById = new Map(D.rooms.map(function (r) { return [r.id, r]; }));
    var floorById = new Map(D.floors.map(function (f) { return [f.id, f]; }));
    var slotById = new Map(D.slots.map(function (s) { return [s.id, s]; }));
    var dayById = new Map(D.days.map(function (d) { return [d.id, d]; }));
    var facById = new Map(D.faculty.map(function (f) { return [f.id, f]; }));
    var secById = new Map(D.sections.map(function (s) { return [s.id, s]; }));
    var courseByCode = new Map(D.courses.map(function (c) { return [c.code, c]; }));

    var defaultGrid = (D.grids.find(function (g) { return g.default; }) || D.grids[0]).id;
    function gridOfSection(id) { var s = secById.get(id); return (s && s.grid) || defaultGrid; }

    // slot id -> every period that shares time with it on the same day (itself included), in any schedule
    var overlapping = new Map();
    D.slots.forEach(function (a) {
      overlapping.set(a.id, D.slots.filter(function (b) { return b.day === a.day && a.start < b.end && b.start < a.end; }));
    });
    // slot id -> classes held in that period or in an overlapping one, ordered by class id
    var at = new Map();
    D.classes.forEach(function (c) {
      c.slots.forEach(function (s) {
        overlapping.get(s).forEach(function (o) {
          if (!at.has(o.id)) at.set(o.id, []);
          if (at.get(o.id).indexOf(c) < 0) at.get(o.id).push(c);
        });
      });
    });
    at.forEach(function (list) { list.sort(function (a, b) { return cmp(a.id, b.id); }); });
    function here(slot) { return at.get(slot) || []; }
    // plain character order, like Cypher's ORDER BY
    function cmp(x, y) { return x < y ? -1 : x > y ? 1 : 0; }
    function secName(id) { var s = secById.get(id); return s ? s.name + (s.sample ? ' (sample)' : '') : null; }
    function initials(ids) { return ids.map(function (i) { return (facById.get(i) || {}).initials; }).filter(Boolean); }
    // a class can use several rooms at once: its rooms are a list of {id, number}
    function roomObjs(c) { return c.rooms.map(function (id) { return { id: id, number: roomById.get(id).number }; }); }
    function usesRoom(c, id) { return c.rooms.indexOf(id) >= 0; }
    function byOrder(a, b) { return a.dayOrder - b.dayOrder || cmp(a.start, b.start) || cmp(a.class, b.class); }
    function range(c) {
      var first = slotById.get(c.slots[0]), last = slotById.get(c.slots[c.slots.length - 1]);
      return { first: first, last: last };
    }
    function classRow(c, extra) {
      var r = range(c);
      return Object.assign({
        day: r.first.day, dayOrder: dayById.get(r.first.day).order, grid: r.first.grid, firstPeriod: r.first.period, lastPeriod: r.last.period,
        time: r.first.start + '-' + r.last.end, start: r.first.start, end: r.last.end,
        class: c.name, section: secName(c.section), sectionId: c.section, rooms: roomObjs(c)
      }, extra);
    }
    function workingDays(day) { return D.days.filter(function (d) { return d.working && (!day || d.id === day); }); }
    function freeTime(isBusy, day, grid) {
      var out = [];
      workingDays(day).forEach(function (d) {
        var free = D.slots.filter(function (s) { return s.day === d.id && s.grid === grid && !isBusy(s.id); })
          .map(function (s) { return { slot: s.id, period: s.period, time: s.start + '-' + s.end }; });
        if (free.length) out.push({ day: d.id, dayName: d.name, free: free });
      });
      return out;
    }
    function sectionBusy(id) { return function (slot) { return here(slot).some(function (c) { return c.section === id; }); }; }
    function facultyBusy(id) { return function (slot) { return here(slot).some(function (c) { return c.faculty.indexOf(id) >= 0; }); }; }
    function roomIsFree(room, slot) { return !here(slot).some(function (c) { return usesRoom(c, room.id); }); }
    function roomOrder(a, b) {
      var fa = floorById.get(a.floor), fb = floorById.get(b.floor);
      return cmp(fa.building, fb.building) || fa.number - fb.number || cmp(a.number, b.number) || cmp(a.id, b.id);
    }

    var L = {
      mode: 'demo',
      label: 'data snapshot',
      meta: function () {
        return { departments: D.departments || [], buildings: D.buildings, floors: D.floors, rooms: D.rooms, days: D.days, grids: D.grids, slots: D.slots, sections: D.sections, faculty: D.faculty };
      },
      floorOccupancy: function (floor, slot) {
        return D.rooms.filter(function (r) { return r.floor === floor; }).sort(roomOrder).map(function (r) {
          var c = here(slot).find(function (x) { return usesRoom(x, r.id); });   // the first class by id
          return {
            room: r.number, roomId: r.id, type: r.type, status: c ? 'OCCUPIED' : 'FREE',
            section: c ? secName(c.section) : null, sectionId: c ? c.section : null,
            class: c ? c.name : null, faculty: c ? initials(c.faculty) : []
          };
        });
      },
      floorGrid: function (floor, day, grid) {
        var out = [];
        D.rooms.filter(function (r) { return r.floor === floor; }).sort(roomOrder).forEach(function (r) {
          D.slots.filter(function (s) { return s.day === day && s.grid === (grid || defaultGrid); }).forEach(function (s) {
            var c = here(s.id).find(function (x) { return usesRoom(x, r.id); });
            out.push({
              room: r.number, roomId: r.id, type: r.type, period: s.period, status: c ? 'OCCUPIED' : 'FREE',
              section: c ? secName(c.section) : null, sectionId: c ? c.section : null, class: c ? c.name : null
            });
          });
        });
        return out;
      },
      freeRooms: function (f) {
        return D.rooms.filter(function (r) {
          var fl = floorById.get(r.floor);
          return (!f.building || fl.building === f.building) && (!f.floor || r.floor === f.floor) &&
            (!f.type || r.type === f.type) && (!f.minCapacity || (r.capacity != null && r.capacity >= Number(f.minCapacity))) &&
            roomIsFree(r, f.slot);
        }).sort(roomOrder).map(function (r) {
          var fl = floorById.get(r.floor);
          return { building: fl.building, floor: fl.number, room: r.number, roomId: r.id, type: r.type, capacity: r.capacity };
        });
      },
      roomWeek: function (id) {
        return D.classes.filter(function (c) { return usesRoom(c, id); })
          .map(function (c) { var row = classRow(c, { faculty: initials(c.faculty) }); delete row.rooms; return row; }).sort(byOrder);
      },
      sectionWeek: function (id) {
        var out = [];
        workingDays().forEach(function (d) {
          D.slots.filter(function (s) { return s.day === d.id && s.grid === gridOfSection(id); }).forEach(function (s) {
            var c = here(s.id).find(function (x) { return x.section === id; });
            out.push({
              day: d.id, dayOrder: d.order, period: s.period, start: s.start, end: s.end,
              classId: c ? c.id : null, class: c ? c.name : null, type: c ? c.type : null,
              rooms: c ? roomObjs(c) : [], faculty: c ? initials(c.faculty) : []
            });
          });
        });
        return out;
      },
      sectionFree: function (id, day) { return freeTime(sectionBusy(id), day, gridOfSection(id)); },
      sectionFreeWithRooms: function (id, day, floor) {
        var busy = sectionBusy(id);
        return D.slots.filter(function (s) { return s.day === day && s.grid === gridOfSection(id) && !busy(s.id); }).map(function (s) {
          var rooms = D.rooms.filter(function (r) { return r.floor === floor && r.type === 'CLASSROOM' && roomIsFree(r, s.id); })
            .map(function (r) { return r.number; }).sort();
          return { slot: s.id, period: s.period, time: s.start + '-' + s.end, freeRooms: rooms };
        });
      },
      courses: function (id) {
        return D.allotments.filter(function (a) { return a.section === id; }).map(function (a) {
          var c = courseByCode.get(a.course);
          return {
            code: c.code, course: c.short, name: c.name, LTP: c.LTP, credits: c.credits, scheduling: c.scheduling,
            teacher: initials(a.teachers),
            classesAllotted: D.classes.filter(function (x) { return x.section === id && x.course === c.code; }).length,
            classesNeeded: c.needed
          };
        }).sort(function (a, b) { return a.course.localeCompare(b.course); });
      },
      facultyWeek: function (id) {
        return D.classes.filter(function (c) { return c.faculty.indexOf(id) >= 0; }).map(function (c) {
          return classRow(c, { batches: c.batches.filter(function (b) { return b.faculty === id; }).map(function (b) { return b.name; }) });
        }).sort(byOrder);
      },
      facultyFree: function (id, day, grid) { return freeTime(facultyBusy(id), day, grid || defaultGrid); },
      search: function (q) {
        var s = q.toLowerCase(), has = function (v) { return v != null && String(v).toLowerCase().indexOf(s) >= 0; };
        var out = [];
        D.sections.forEach(function (x) { if (has(x.name)) out.push({ kind: 'SECTION', id: x.id, label: x.name }); });
        D.rooms.forEach(function (x) { if (has(x.number) || has(x.id)) out.push({ kind: 'ROOM', id: x.id, label: x.number }); });
        D.faculty.forEach(function (x) { if (has(x.name) || has(x.initials)) out.push({ kind: 'FACULTY', id: x.id, label: x.name }); });
        D.buildings.forEach(function (x) { if (has(x.name) || has(x.id)) out.push({ kind: 'BUILDING', id: x.id, label: x.name }); });
        // same order as Cypher's ORDER BY, so the 25 kept are the same ones
        out.sort(function (a, b) { return cmp(a.kind, b.kind) || cmp(a.label, b.label) || cmp(a.id, b.id); });
        return out.slice(0, 25);
      }
    };

    // every call returns a Promise, like the remote version
    var api = { mode: L.mode, label: L.label };
    Object.keys(L).forEach(function (k) {
      if (typeof L[k] === 'function') api[k] = function () { return Promise.resolve(L[k].apply(null, arguments)); };
    });
    return api;
  }

  if (API) window.TT_API = Remote;
  else if (window.TT_DATA) window.TT_API = makeLocal(window.TT_DATA);
  else window.TT_API = null;
})();
