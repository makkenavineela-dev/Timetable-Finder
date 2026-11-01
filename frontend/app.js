// Timetable Finder - screens. All data comes through window.TT_API (see api.js).
(function () {
  'use strict';

  var api = window.TT_API;
  var M = null;                 // meta: buildings, floors, rooms, days, slots, sections, faculty
  var grids = [];               // bell schedules: [{id, name, default}]. Sections follow one; room screens let you pick.
  var workDays = [];            // working days
  var DAY_IDS = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

  var TABS = [
    ['floors', 'Floors'],
    ['free', 'Free rooms'],
    ['sections', 'Sections'],
    ['faculty', 'Faculty'],
    ['rooms', 'Rooms']
  ];

  /* ------------------------------------------------------------ small helpers */
  function $(s) { return document.querySelector(s); }
  function enc(v) { return encodeURIComponent(v); }

  // Builds an element. Text always goes in as text (never as HTML), so data cannot inject markup.
  function h(tag, attrs) {
    var el = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) {
      var v = attrs[k];
      if (v == null || v === false) return;
      if (k === 'class') el.className = v;
      else if (k.indexOf('on') === 0) el.addEventListener(k.slice(2), v);
      else el.setAttribute(k, v === true ? '' : v);
    });
    Array.prototype.slice.call(arguments, 2).forEach(function add(kid) {
      if (kid == null || kid === false) return;
      if (Array.isArray(kid)) return kid.forEach(add);
      el.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
    });
    return el;
  }

  function parseHash() {
    var raw = location.hash.replace(/^#\/?/, '');
    var i = raw.indexOf('?');
    var path = i < 0 ? raw : raw.slice(0, i);
    var params = {};
    new URLSearchParams(i < 0 ? '' : raw.slice(i + 1)).forEach(function (v, k) { params[k] = v; });
    return { tab: path || 'floors', params: params };
  }
  // Filter changes rewrite the address (so a result can be shared as a link) without adding history entries.
  function go(tab, params) {
    var qs = new URLSearchParams(Object.keys(params).filter(function (k) { return params[k] != null && params[k] !== ''; })
      .map(function (k) { return [k, params[k]]; })).toString();
    history.replaceState(null, '', '#/' + tab + (qs ? '?' + qs : ''));
    render();
  }

  var hRoom = function (id) { return '#/rooms?r=' + enc(id); };
  var hSection = function (id) { return '#/sections?s=' + enc(id); };
  var hFaculty = function (id) { return '#/faculty?f=' + enc(id); };

  function facultyIdByInitials(ini) {
    var f = M.faculty.find(function (x) { return x.initials === ini; });
    return f ? f.id : null;
  }
  function sectionColor(id) {
    var i = M.sections.findIndex(function (s) { return s.id === id; });
    return 'c' + (Math.max(i, 0) % 6);
  }
  function sectionLabel(s) { return s.name + (s.sample ? ' (sample)' : ''); }
  // department id with its full name, for example "CSE · Computer Science and Engineering"
  function deptLabel(id) {
    var d = (M.departments || []).find(function (x) { return x.id === id; });
    return d && d.name && d.name !== id ? id + ' · ' + d.name : id;
  }
  // A class can use several rooms at once (for example LAB 503 and LAB 504), so rooms come as a list of {id, number}.
  function sortedRooms(rooms) {
    return (rooms || []).slice().sort(function (a, b) { return String(a.number).localeCompare(String(b.number), undefined, { numeric: true }); });
  }
  function roomText(rooms) { return sortedRooms(rooms).map(function (r) { return r.number; }).join(', '); }
  function firstRoomHref(rooms) { var s = sortedRooms(rooms); return s.length ? hRoom(s[0].id) : null; }
  function roomLinks(rooms) {
    var s = sortedRooms(rooms);
    if (!s.length) return '–';
    return s.map(function (r, i) { return [i ? ', ' : '', h('a', { href: hRoom(r.id) }, r.number)]; });
  }
  function blockName(id) { var b = M.buildings.find(function (x) { return x.id === id; }); return b ? b.name : id; }
  function periodText(p) { return 'P' + p.period + ' · ' + p.start + '–' + p.end; }
  function timeText(t) { return t.replace('-', '–'); }
  function lower(s) { return s ? s.toLowerCase() : ''; }

  function loading() { return h('p', { class: 'muted' }, 'Loading…'); }
  function errorBox(err, retry) {
    return h('div', { class: 'box err', role: 'alert' },
      h('p', {}, 'Could not load the data. ', (err && err.message) || String(err)),
      retry ? h('button', { type: 'button', class: 'btn', onclick: retry }, 'Try again') : null);
  }

  /* ----------------------------------------------------------------- widgets */
  function option(value, label, current) {
    return h('option', { value: value, selected: String(value) === String(current) }, label);
  }
  function select(id, options, current, onChange) {
    var s = h('select', { id: id, onchange: onChange ? function (e) { onChange(e.target.value); } : null });
    options.forEach(function (o) { s.append(option(o[0], o[1], current)); });
    return s;
  }
  function field(label, control) { return h('label', { class: 'field' }, h('span', {}, label), control); }
  function panel(title, note) {
    var kids = Array.prototype.slice.call(arguments, 2);
    return h('section', { class: 'panel' }, h('h2', {}, title), note ? h('p', { class: 'note' }, note) : null, kids);
  }
  function table(headers, rows) {
    return h('div', { class: 'scroll' }, h('table', { class: 'dt' },
      h('thead', {}, h('tr', {}, headers.map(function (x) { return h('th', { scope: 'col' }, x); }))),
      h('tbody', {}, rows.map(function (r) { return h('tr', {}, r.map(function (c) { return h('td', {}, c); })); }))));
  }
  function pill(kind, text) { return h('span', { class: 'pill ' + kind }, text); }
  function legend(items) {
    return h('div', { class: 'legend' }, items.map(function (i) { return h('span', {}, h('i', { class: i[0] }), i[1]); }));
  }

  // Rows x periods grid. cellFn(rowKey, period) returns null or {key, cls, lines, href, title}.
  // opts.periods are the periods of the schedule shown. Neighbouring cells with the same key
  // (a two-period lab) are merged into one wide cell.
  function grid(opts) {
    var cols = [], periods = opts.periods;
    periods.forEach(function (pd, i) {
      if (i > 0 && periods[i - 1].end !== pd.start) cols.push({ brk: true, from: periods[i - 1].end, to: pd.start });
      cols.push({ pd: pd });
    });
    var head = h('tr', {}, h('th', { class: 'rowh', scope: 'col' }, opts.corner || ''));
    cols.forEach(function (c) {
      if (c.brk) head.append(h('th', { class: 'brk', title: 'Break ' + c.from + '–' + c.to }));
      else head.append(h('th', { scope: 'col', class: c.pd.period === opts.selPeriod ? 'selcol' : null }, 'P' + c.pd.period, h('small', {}, c.pd.start)));
    });
    var body = h('tbody');
    opts.rows.forEach(function (r) {
      var tr = h('tr', {}, h('th', { scope: 'row', class: 'rowh' },
        r.href ? h('a', { href: r.href }, r.label) : r.label, r.sub ? h('small', {}, r.sub) : null));
      var i = 0;
      while (i < cols.length) {
        var c = cols[i];
        if (c.brk) { tr.append(h('td', { class: 'brk' })); i++; continue; }
        var cell = opts.cellFn(r.key, c.pd.period);
        var span = 1;
        if (cell && cell.key != null) {
          while (cols[i + span] && !cols[i + span].brk) {
            var nxt = opts.cellFn(r.key, cols[i + span].pd.period);
            if (nxt && nxt.key === cell.key) span++; else break;
          }
        }
        if (!cell) {
          tr.append(h('td', { class: 'cell none' }));
        } else {
          var lines = cell.lines.filter(Boolean);
          var inner = [h('b', {}, lines[0])].concat(lines.slice(1).map(function (l) { return h('small', {}, l); }));
          var selected = opts.selPeriod != null && opts.selPeriod >= c.pd.period && opts.selPeriod < c.pd.period + span;
          tr.append(h('td', { class: 'cell ' + cell.cls + (selected ? ' selcol' : ''), colspan: span > 1 ? span : null, title: cell.title },
            cell.href ? h('a', { href: cell.href }, inner) : inner));
        }
        i += span;
      }
      body.append(tr);
    });
    return h('div', { class: 'scroll' }, h('table', { class: 'wk' }, h('thead', {}, head), body));
  }

  var FREE = { key: null, cls: 'free', lines: ['free'] };
  function classKind(type, hasRoom) {
    if (type === 'P' || type === 'T') return 'lab';
    if (type === 'A') return 'act';
    return !hasRoom && type === 'L' ? 'pe' : 'lec';
  }
  var TYPE_LEGEND = [['free', 'free'], ['lec', 'lecture'], ['lab', 'lab or tutorial (two periods)'], ['pe', 'elective slot (no room)']];

  // Week rows from faculty/room queries -> {cells: map "DAY|period" -> {row, index}, hidden: rows not in any column}.
  // The rows can belong to either schedule, so a class goes into every period of the schedule SHOWN (per)
  // that shares time with it. A class that falls in a break of that schedule has no column: it is counted
  // in hidden and still appears in the list under the grid.
  function weekCells(rows, per) {
    var cells = new Map(), hidden = 0;
    rows.forEach(function (row, i) {
      var hit = per.filter(function (p) { return p.start < row.end && row.start < p.end; });
      if (!hit.length) hidden++;
      hit.forEach(function (p) { cells.set(row.day + '|' + p.period, { row: row, index: i }); });
    });
    return { cells: cells, hidden: hidden };
  }
  function hiddenNote(n) {
    return n ? n + (n === 1 ? ' class falls' : ' classes fall') + ' in a break of this schedule, so ' + (n === 1 ? 'it is' : 'they are') + ' only in the list below.' : '';
  }
  function dayRows() {
    return workDays.map(function (d) { return { key: d.id, label: d.name.slice(0, 3) }; });
  }

  // Free-time tables (section and faculty)
  function freeTable(rows) {
    if (!rows.length) return h('p', { class: 'empty' }, 'No free periods.');
    return table(['Day', 'Free', 'Free periods'], rows.map(function (r) {
      return [h('b', {}, r.dayName), String(r.free.length), r.free.map(function (f) { return timeText(f.time); }).join(', ')];
    }));
  }

  function nowSlot(g) {
    var d = new Date();
    var hhmm = ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2);
    var day = DAY_IDS[d.getDay()];
    if (!workDays.some(function (w) { return w.id === day; })) return null;
    return M.slots.find(function (s) { return s.grid === g && s.day === day && s.start <= hhmm && hhmm < s.end; }) || null;
  }
  function nowButton(tab, params) {
    var msg = h('span', { id: 'nowmsg' });
    var btn = h('button', {
      type: 'button', class: 'btn', onclick: function () {
        var s = nowSlot(params.g);
        if (!s) { msg.textContent = 'No class period is running right now.'; return; }
        go(tab, Object.assign({}, params, { d: s.day, p: String(s.period) }));
      }
    }, 'Use current time');
    return [btn, msg];
  }

  function uniq(list) { return list.filter(function (v, i) { return list.indexOf(v) === i; }); }
  function byText(a, b) { return String(a).localeCompare(String(b), undefined, { numeric: true }); }
  function clusterKey(s) { return s.cluster || '-'; }
  function clusterLabel(k) { return k === '-' ? 'No cluster' : 'Cluster ' + k; }

  // Branch > Year > Semester > Cluster > Section. Resolved from the top, so a choice that no longer
  // exists under the level above falls back to the first valid one. A section id in the address wins.
  function resolveSection(p) {
    var named = M.sections.find(function (x) { return x.id === p.s; });
    var pool = M.sections, sel = {};
    [['br', function (s) { return s.department; }], ['yr', function (s) { return s.year; }],
      ['sm', function (s) { return String(s.semester); }], ['cl', clusterKey]].forEach(function (lvl) {
      var get = lvl[1];
      var values = uniq(pool.map(get)).sort(byText);
      var want = named ? get(named) : p[lvl[0]];
      // with no valid choice, start from the first value - but the latest academic year
      sel[lvl[0]] = values.indexOf(want) >= 0 ? want : (lvl[0] === 'yr' ? values[values.length - 1] : values[0]);
      sel['all_' + lvl[0]] = values;
      pool = pool.filter(function (s) { return get(s) === sel[lvl[0]]; });
    });
    pool = pool.slice().sort(function (a, b) { return byText(a.name, b.name); });
    sel.sections = pool;
    sel.s = named && pool.indexOf(named) >= 0 ? named.id : pool[0].id;
    return sel;
  }
  // Address parameters after the user changes one level: levels above stay, levels below reset.
  function pickerParams(sel, level, value) {
    var out = {}, hit = false;
    ['br', 'yr', 'sm', 'cl', 's'].forEach(function (k) {
      if (k === level) { out[k] = value; hit = true; } else out[k] = hit ? '' : sel[k];
    });
    return out;
  }
  function roomsOf(floorId) {
    return M.rooms.filter(function (r) { return r.floor === floorId; }).sort(function (a, b) { return byText(a.number, b.number); });
  }
  // Block > Floor > Room
  function resolveRoom(p) {
    var named = M.rooms.find(function (r) { return r.id === p.r; });
    var firstClassroom = M.rooms.find(function (r) { return r.type === 'CLASSROOM'; }) || M.rooms[0];
    var floorOf = function (r) { return M.floors.find(function (f) { return f.id === r.floor; }); };
    var knownBlock = M.buildings.some(function (b) { return b.id === p.b; });
    var seed = named || (knownBlock ? null : firstClassroom);
    var b = seed ? floorOf(seed).building : p.b;
    var floors = M.floors.filter(function (f) { return f.building === b; }).sort(function (x, y) { return x.number - y.number; });
    var f;
    if (seed) f = seed.floor;
    else if (floors.some(function (x) { return x.id === p.f; })) f = p.f;
    else f = (floors.find(function (x) { return roomsOf(x.id).some(function (r) { return r.type === 'CLASSROOM'; }); }) || floors[0]).id;
    var rooms = roomsOf(f);
    var room = rooms.find(function (r) { return r.id === p.r; }) || rooms[0];
    return { b: b, f: f, r: room.id, floors: floors, rooms: rooms };
  }

  function pick(list, value, fallback) {
    return list.some(function (x) { return x.id === value; }) ? value : fallback;
  }
  function busiestFloor(type) {
    var count = {};
    M.rooms.forEach(function (r) { if (!type || r.type === type) count[r.floor] = (count[r.floor] || 0) + 1; });
    var best = M.floors.filter(function (f) { return count[f.id]; })
      .sort(function (a, b) { return count[b.id] - count[a.id] || a.number - b.number; })[0];
    return best ? best.id : M.floors[0].id;
  }
  function floorOptions(building, withAny) {
    var o = M.floors.filter(function (f) { return !building || f.building === building; })
      .map(function (f) { return [f.id, (building ? '' : blockName(f.building) + ' · ') + 'Floor ' + f.number]; });
    return withAny ? [['', 'Any floor']].concat(o) : o;
  }
  function dayOptions(withAll) {
    var o = workDays.map(function (d) { return [d.id, d.name]; });
    return withAll ? [['', 'Whole week']].concat(o) : o;
  }
  // ---- schedules (bell schedules). Sections follow one; the room screens and Faculty let you pick.
  function defaultGrid() { return (grids.find(function (g) { return g.default; }) || grids[0]).id; }
  function periodsOf(g) {
    return M.slots.filter(function (s) { return s.grid === g && s.day === workDays[0].id; })
      .sort(function (a, b) { return a.period - b.period; }).map(function (s) { return { period: s.period, start: s.start, end: s.end }; });
  }
  function pickGrid(v) { return grids.some(function (g) { return g.id === v; }) ? v : defaultGrid(); }
  // the Schedule drop-down, only when there is more than one schedule
  function gridField(id, current, onChange) {
    if (grids.length < 2) return null;
    return field('Schedule', select(id, grids.map(function (g) { return [g.id, g.name]; }), current, onChange));
  }
  function slotId(g, day, period) {
    var s = M.slots.find(function (x) { return x.grid === g && x.day === day && x.period === period; });
    return s ? s.id : day + '-P' + period;
  }
  function periodOptions(per) { return per.map(function (p) { return [String(p.period), periodText(p)]; }); }
  function validPeriod(v, per) {
    var n = Number(v);
    var ok = per.some(function (p) { return p.period === n; });
    return ok ? n : (per[3] || per[0]).period;
  }

  /* ------------------------------------------------------------------- views */
  // ---- Floors: which rooms are free / occupied by which section
  function viewFloors(p) {
    var roomsIn = function (b) { return M.rooms.filter(function (r) { return M.floors.some(function (f) { return f.id === r.floor && f.building === b.id; }); }).length; };
    var biggest = M.buildings.slice().sort(function (a, b) { return roomsIn(b) - roomsIn(a); })[0];
    var building = pick(M.buildings, p.b, biggest.id);
    var floors = M.floors.filter(function (f) { return f.building === building; });
    var floor = pick(floors, p.f, floors.slice().sort(function (a, b) {
      return M.rooms.filter(function (r) { return r.floor === b.id; }).length - M.rooms.filter(function (r) { return r.floor === a.id; }).length;
    })[0].id);
    var g = pickGrid(p.g);
    var periods = periodsOf(g);
    var day = pick(workDays, p.d, workDays[0].id);
    var per = validPeriod(p.p, periods);
    var slot = slotId(g, day, per);
    var base = { b: building, f: floor, d: day, p: String(per), g: g };
    var floorNo = M.floors.find(function (f) { return f.id === floor; }).number;
    var pd = periods.find(function (x) { return x.period === per; });

    return Promise.all([api.floorOccupancy(floor, slot), api.floorGrid(floor, day, g)]).then(function (res) {
      var occ = res[0], cells = res[1];
      var freeN = occ.filter(function (r) { return r.status === 'FREE'; }).length;
      var rowsMap = new Map(), order = [];
      cells.forEach(function (c) {
        if (!rowsMap.has(c.roomId)) { rowsMap.set(c.roomId, { room: c.room, type: c.type, p: {} }); order.push(c.roomId); }
        rowsMap.get(c.roomId).p[c.period] = c;
      });
      var dayName = workDays.find(function (d) { return d.id === day; }).name;
      var usedSections = [];
      cells.forEach(function (c) { if (c.sectionId && usedSections.indexOf(c.sectionId) < 0) usedSections.push(c.sectionId); });

      var filters = h('div', { class: 'filters' },
        field('Block', select('f-b', M.buildings.map(function (b) { return [b.id, b.name]; }), building,
          function (v) { go('floors', Object.assign({}, base, { b: v, f: '' })); })),
        field('Floor', select('f-f', floorOptions(building), floor, function (v) { go('floors', Object.assign({}, base, { f: v })); })),
        gridField('f-g', g, function (v) { go('floors', Object.assign({}, base, { g: v })); }),
        field('Day', select('f-d', dayOptions(), day, function (v) { go('floors', Object.assign({}, base, { d: v })); })),
        field('Period', select('f-p', periodOptions(periods), String(per), function (v) { go('floors', Object.assign({}, base, { p: v })); })),
        nowButton('floors', base));

      var summary = panel('Floor ' + floorNo + ' · ' + dayName + ' · ' + periodText(pd),
        freeN + ' free, ' + (occ.length - freeN) + ' occupied. Click a room or a section to open it.',
        table(['Room', 'Type', 'Status', 'Section', 'Class', 'Faculty'], occ.map(function (r) {
          var free = r.status === 'FREE';
          return [h('a', { href: hRoom(r.roomId) }, h('b', {}, r.room)), lower(r.type), pill(free ? 'ok' : 'busy', lower(r.status)),
            free ? '–' : h('a', { href: hSection(r.sectionId) }, r.section), free ? '–' : r.class,
            free ? '–' : (r.faculty || []).join(', ')];
        })));

      var legendItems = [['free', 'free']].concat(usedSections.map(function (id) {
        var s = M.sections.find(function (x) { return x.id === id; });
        return [sectionColor(id), 'occupied by ' + sectionLabel(s)];
      }));
      var gridPanel = panel('Floor ' + floorNo + ' on ' + dayName + ' – every period',
        'The outlined column is the period chosen above.',
        legend(legendItems),
        grid({
          periods: periods, corner: 'Room', selPeriod: per, rows: order.map(function (id) {
            var r = rowsMap.get(id);
            return { key: id, label: r.room, sub: lower(r.type), href: hRoom(id) };
          }),
          cellFn: function (roomId, period) {
            var c = rowsMap.get(roomId).p[period];
            if (!c || c.status === 'FREE') return FREE;
            return { key: null, cls: sectionColor(c.sectionId), lines: [c.section, c.class], href: hSection(c.sectionId), title: c.section + ' · ' + c.class };
          }
        }));
      return h('div', {}, filters, summary, gridPanel);
    });
  }

  // ---- Free rooms: search by building, floor, type, size and period
  function viewFree(p) {
    var building = M.buildings.some(function (b) { return b.id === p.b; }) ? p.b : '';
    var floors = M.floors.filter(function (f) { return !building || f.building === building; });
    var floor = floors.some(function (f) { return f.id === p.f; }) ? p.f : '';
    var type = p.t === 'CLASSROOM' || p.t === 'LAB' ? p.t : '';
    var g = pickGrid(p.g);
    var periods = periodsOf(g);
    var day = pick(workDays, p.d, workDays[0].id);
    var per = validPeriod(p.p, periods);
    var slot = slotId(g, day, per);
    var base = { b: building, f: floor, t: type, d: day, p: String(per), g: g };

    return api.freeRooms({ building: building || null, floor: floor || null, type: type || null, slot: slot, minCapacity: null })
      .then(function (rows) {
        var dayName = workDays.find(function (d) { return d.id === day; }).name;
        var pd = periods.find(function (x) { return x.period === per; });
        var filters = h('div', { class: 'filters' },
          field('Block', select('r-b', [['', 'Any block']].concat(M.buildings.map(function (b) { return [b.id, b.name]; })), building,
            function (v) { go('free', Object.assign({}, base, { b: v, f: '' })); })),
          field('Floor', select('r-f', floorOptions(building, true), floor, function (v) { go('free', Object.assign({}, base, { f: v })); })),
          field('Room type', select('r-t', [['', 'Any type'], ['CLASSROOM', 'Classroom'], ['LAB', 'Lab']], type, function (v) { go('free', Object.assign({}, base, { t: v })); })),
          gridField('r-g', g, function (v) { go('free', Object.assign({}, base, { g: v })); }),
          field('Day', select('r-d', dayOptions(), day, function (v) { go('free', Object.assign({}, base, { d: v })); })),
          field('Period', select('r-p', periodOptions(periods), String(per), function (v) { go('free', Object.assign({}, base, { p: v })); })),
          nowButton('free', base));
        var body = rows.length
          ? table(['Block', 'Floor', 'Room', 'Type'], rows.map(function (r) {
            return [blockName(r.building), String(r.floor), h('a', { href: hRoom(r.roomId) }, h('b', {}, r.room)), lower(r.type)];
          }))
          : h('p', { class: 'empty' }, 'No free room matches these filters.');
        return h('div', {}, filters, panel(rows.length + ' free ' + (rows.length === 1 ? 'room' : 'rooms') + ' · ' + dayName + ' · ' + periodText(pd),
          'Rooms with no class in this period' + (grids.length > 1 ? ', or in a period of the other schedule that shares time with it.' : '.'), body));
      });
  }

  // ---- Sections: week grid and free time
  function viewSections(p) {
    var sel = resolveSection(p);
    var sid = sel.s;
    var sec = M.sections.find(function (s) { return s.id === sid; });
    var day = workDays.some(function (d) { return d.id === p.d; }) ? p.d : '';
    var xDay = pick(workDays, p.x, workDays[0].id);
    var fl = M.floors.some(function (f) { return f.id === p.fl; }) ? p.fl : busiestFloor('CLASSROOM');
    var base = { s: sid, d: day, x: xDay, fl: fl };
    var periods = periodsOf(sec.grid || defaultGrid());

    return Promise.all([api.sectionWeek(sid), api.sectionFree(sid, day || null), api.sectionFreeWithRooms(sid, xDay, fl), api.courses(sid)])
      .then(function (res) {
        var week = new Map();
        res[0].forEach(function (r) { week.set(r.day + '|' + r.period, r); });
        var freeCount = res[0].filter(function (r) { return !r.classId; }).length;

        function change(level) {
          return function (v) { go('sections', Object.assign({}, base, pickerParams(sel, level, v))); };
        }
        var filters = h('div', { class: 'filters' },
          field('Branch', select('s-br', sel.all_br.map(function (v) { return [v, deptLabel(v)]; }), sel.br, change('br'))),
          sel.all_yr.length > 1 ? field('Year', select('s-yr', sel.all_yr.map(function (v) { return [v, v]; }), sel.yr, change('yr'))) : null,
          field('Semester', select('s-sm', sel.all_sm.map(function (v) { return [v, 'Semester ' + v]; }), sel.sm, change('sm'))),
          field('Cluster', select('s-cl', sel.all_cl.map(function (v) { return [v, clusterLabel(v)]; }), sel.cl, change('cl'))),
          field('Section', select('s-s', sel.sections.map(function (s) { return [s.id, sectionLabel(s)]; }), sid, change('s'))),
          field('Free time for', select('s-d', dayOptions(true), day, function (v) { go('sections', Object.assign({}, base, { d: v })); })));

        var head = h('div', { class: 'headline' }, h('h2', {}, sectionLabel(sec)),
          h('p', {}, [sec.department, sec.program, sec.year, 'semester ' + sec.semester, sec.cluster ? 'cluster ' + sec.cluster : null].filter(Boolean).join(' · ')),
          grids.length > 1 ? h('span', { class: 'tag' }, 'schedule ' + (sec.grid || defaultGrid())) : null,
          sec.sample ? h('span', { class: 'tag' }, 'sample data') : null);

        var weekPanel = panel('Week timetable', freeCount + ' of ' + res[0].length + ' periods are free. Click a class to open its room.',
          legend(TYPE_LEGEND),
          grid({
            periods: periods, corner: '', rows: dayRows(), cellFn: function (d, period) {
              var r = week.get(d + '|' + period);
              if (!r || !r.classId) return FREE;
              return {
                key: r.classId, cls: classKind(r.type, r.rooms.length > 0), lines: [r.class, roomText(r.rooms)], href: firstRoomHref(r.rooms),
                title: r.class + (r.faculty && r.faculty.length ? ' · ' + r.faculty.join(', ') : '')
              };
            }
          }));

        var freePanel = panel('Free time', day ? 'Free periods on ' + workDays.find(function (d) { return d.id === day; }).name + '.' : 'Free periods in the week.', freeTable(res[1]));

        var extra = h('div', {}, h('div', { class: 'filters' },
          field('Day', select('s-x', dayOptions(), xDay, function (v) { go('sections', Object.assign({}, base, { x: v })); })),
          field('Floor', select('s-fl', floorOptions(''), fl, function (v) { go('sections', Object.assign({}, base, { fl: v })); }))),
          res[2].length ? table(['Section is free', 'Free classrooms on that floor'], res[2].map(function (r) {
            return [h('b', {}, timeText(r.time)), r.freeRooms.length ? r.freeRooms.map(function (n, i) {
              var room = M.rooms.find(function (x) { return x.floor === fl && x.number === n; });
              return [i ? ', ' : '', room ? h('a', { href: hRoom(room.id) }, n) : n];
            }) : h('small', {}, 'none free')];
          })) : h('p', { class: 'empty' }, 'The section has no free period on this day.'));
        var extraPanel = panel('Where an extra class could go', 'Periods when the section is free, and which classrooms are free then.', extra);

        var coursePanel = panel('Courses', 'Classes needed come from each course’s L-T-P.', table(['Course', 'Name', 'L-T-P', 'Teacher', 'Classes'],
          res[3].map(function (c) {
            var status;
            if (c.scheduling === 'NONE') status = h('small', {}, 'not timetabled');
            else status = pill(c.classesAllotted >= c.classesNeeded ? 'ok' : 'warn', c.classesAllotted + ' of ' + c.classesNeeded);
            return [h('b', {}, c.course), c.name, c.LTP, (c.teacher || []).map(function (t, i) {
              var id = facultyIdByInitials(t);
              return [i ? ', ' : '', id ? h('a', { href: hFaculty(id) }, t) : t];
            }), status];
          })));

        return h('div', {}, filters, head, weekPanel, h('div', { class: 'cols gap-below' }, freePanel, extraPanel), coursePanel);
      });
  }

  // ---- Faculty
  function viewFaculty(p) {
    var preferred = M.faculty.find(function (f) { return f.initials === 'CAV'; });
    var fid = pick(M.faculty, p.f, (preferred || M.faculty[0]).id);
    var fac = M.faculty.find(function (f) { return f.id === fid; });
    var day = workDays.some(function (d) { return d.id === p.d; }) ? p.d : '';
    var g = pickGrid(p.g);
    var periods = periodsOf(g);
    var base = { f: fid, d: day, g: g };

    return Promise.all([api.facultyWeek(fid), api.facultyFree(fid, day || null, g)]).then(function (res) {
      var shown = weekCells(res[0], periods), cells = shown.cells;
      var filters = h('div', { class: 'filters' },
        field('Faculty', select('t-f', M.faculty.map(function (f) { return [f.id, f.initials + ' · ' + f.name]; }), fid, function (v) { go('faculty', Object.assign({}, base, { f: v })); })),
        gridField('t-g', g, function (v) { go('faculty', Object.assign({}, base, { g: v })); }),
        field('Free time for', select('t-d', dayOptions(true), day, function (v) { go('faculty', Object.assign({}, base, { d: v })); })));
      var head = h('div', { class: 'headline' }, h('h2', {}, fac.name), h('p', {}, fac.initials + ' · ' + fac.department));

      var weekPanel = panel('Week timetable', res[0].length + ' classes. Labs show only this person’s batches.' +
          (grids.length > 1 ? ' Shown in schedule ' + g + '; classes of the other schedule are placed in the periods they share time with.' : '') +
          (shown.hidden ? ' ' + hiddenNote(shown.hidden) : ''),
        legend([['free', 'free'], ['lec', 'class'], ['lab', 'lab (batches)']]),
        res[0].length ? grid({
          periods: periods, corner: '', rows: dayRows(), cellFn: function (d, period) {
            var c = cells.get(d + '|' + period);
            if (!c) return FREE;
            var r = c.row, batch = r.batches && r.batches.length ? 'batch ' + r.batches.join(', ') : null;
            return {
              key: c.index, cls: batch ? 'lab' : 'lec', lines: [r.class, r.section + (batch ? ' · ' + batch : ''), roomText(r.rooms)],
              href: firstRoomHref(r.rooms), title: r.class + ' · ' + r.section
            };
          }
        }) : h('p', { class: 'empty' }, 'No classes in the timetable yet.'));

      var list = panel('Classes', null, res[0].length ? table(['Day', 'Time', 'Class', 'Section', 'Room'], res[0].map(function (r) {
        return [r.day, timeText(r.time), r.class + (r.batches && r.batches.length ? ' (batch ' + r.batches.join(', ') + ')' : ''),
          r.sectionId ? h('a', { href: hSection(r.sectionId) }, r.section) : r.section,
          roomLinks(r.rooms)];
      })) : h('p', { class: 'empty' }, 'Nothing scheduled.'));

      return h('div', {}, filters, head, weekPanel,
        h('div', { class: 'cols' }, panel('Free time', day ? 'Free periods on one day.' : 'Free periods in the week.', freeTable(res[1])), list));
    });
  }

  // ---- Rooms
  function viewRooms(p) {
    var sel = resolveRoom(p);
    var rid = sel.r;
    var room = M.rooms.find(function (r) { return r.id === rid; });
    var fl = M.floors.find(function (f) { return f.id === room.floor; });
    var g = pickGrid(p.g);
    var periods = periodsOf(g);

    return api.roomWeek(rid).then(function (rows) {
      var shown = weekCells(rows, periods), cells = shown.cells;
      var total = workDays.length * periods.length;
      var used = cells.size;
      var filters = h('div', { class: 'filters' },
        field('Block', select('o-b', M.buildings.map(function (b) { return [b.id, b.name]; }), sel.b, function (v) { go('rooms', { b: v, g: g }); })),
        field('Floor', select('o-f', sel.floors.map(function (f) { return [f.id, 'Floor ' + f.number]; }), sel.f, function (v) { go('rooms', { b: sel.b, f: v, g: g }); })),
        field('Room', select('o-r', sel.rooms.map(function (r) { return [r.id, r.number + ' (' + lower(r.type) + ')']; }), rid, function (v) { go('rooms', { b: sel.b, f: sel.f, r: v, g: g }); })),
        gridField('o-g', g, function (v) { go('rooms', { b: sel.b, f: sel.f, r: rid, g: v }); }));
      var head = h('div', { class: 'headline' }, h('h2', {}, 'Room ' + room.number),
        h('p', {}, blockName(fl.building) + ' · floor ' + fl.number + ' · ' + lower(room.type) + (room.capacity != null ? ' · ' + room.capacity + ' seats' : '')));
      var usedSections = [];
      rows.forEach(function (r) { if (r.sectionId && usedSections.indexOf(r.sectionId) < 0) usedSections.push(r.sectionId); });
      var weekPanel = panel('Week usage', used + ' of ' + total + ' periods used, ' + (total - used) + ' free' +
          (grids.length > 1 ? ' (schedule ' + g + ', classes of the other schedule placed in the periods they share time with)' : '') + '. ' + hiddenNote(shown.hidden),
        legend([['free', 'free']].concat(usedSections.map(function (id) {
          return [sectionColor(id), sectionLabel(M.sections.find(function (s) { return s.id === id; }))];
        }))),
        grid({
          periods: periods, corner: '', rows: dayRows(), cellFn: function (d, period) {
            var c = cells.get(d + '|' + period);
            if (!c) return FREE;
            var r = c.row;
            return {
              key: c.index, cls: r.sectionId ? sectionColor(r.sectionId) : 'lec', lines: [r.section, r.class],
              href: r.sectionId ? hSection(r.sectionId) : null, title: r.section + ' · ' + r.class + ' · ' + (r.faculty || []).join(', ')
            };
          }
        }));
      var list = panel('Classes in this room', null, rows.length ? table(['Day', 'Time', 'Class', 'Section', 'Faculty'], rows.map(function (r) {
        return [r.day, timeText(r.time), r.class, r.sectionId ? h('a', { href: hSection(r.sectionId) }, r.section) : r.section, (r.faculty || []).join(', ') || '–'];
      })) : h('p', { class: 'empty' }, 'No class uses this room.'));
      return h('div', {}, filters, head, weekPanel, list);
    });
  }

  /* ------------------------------------------------------------------ router */
  var VIEWS = { floors: viewFloors, free: viewFree, sections: viewSections, faculty: viewFaculty, rooms: viewRooms };
  // tabs from other files (edit.js adds "Add data"); those load before this one
  (window.TT_EXTRA_VIEWS || []).forEach(function (v) { TABS.push([v.key, v.label]); VIEWS[v.key] = v.view; });
  var renderId = 0;

  function renderTabs(active) {
    var nav = $('#tabs');
    nav.replaceChildren.apply(nav, TABS.map(function (t) {
      return h('a', { href: '#/' + t[0], 'aria-current': t[0] === active ? 'page' : null }, t[1]);
    }));
  }

  function render() {
    var id = ++renderId;
    var route = parseHash();
    var tab = VIEWS[route.tab] ? route.tab : 'floors';
    var focusId = document.activeElement && document.activeElement.id;
    renderTabs(tab);
    var view = $('#view');
    Promise.resolve().then(function () { return VIEWS[tab](route.params); }).then(function (el) {
      if (id !== renderId) return;
      view.replaceChildren(el);
      if (focusId && /^[a-z]-[a-z]+$/.test(focusId)) { var f = document.getElementById(focusId); if (f) f.focus(); }
    }).catch(function (err) {
      if (id === renderId) view.replaceChildren(errorBox(err, render));
    });
    if (!view.firstChild) view.append(loading());
  }

  /* ------------------------------------------------------------------ search */
  function setupSearch() {
    var input = $('#q'), list = $('#results'), timer = 0, seq = 0;
    function close() { list.hidden = true; list.replaceChildren(); }
    function hrefFor(r) {
      if (r.kind === 'SECTION') return hSection(r.id);
      if (r.kind === 'ROOM') return hRoom(r.id);
      if (r.kind === 'FACULTY') return hFaculty(r.id);
      if (r.kind === 'BUILDING') return '#/floors?b=' + enc(r.id);
      return null;
    }
    function show(rows) {
      list.replaceChildren();
      if (!rows.length) list.append(h('li', { class: 'none muted' }, 'No match'));
      rows.forEach(function (r) {
        var href = hrefFor(r);
        var kind = r.kind === 'BUILDING' ? 'block' : r.kind.toLowerCase();
        var inner = [h('span', { class: 'pill kind' }, kind), h('span', {}, r.label), h('span', { class: 'id' }, r.id)];
        list.append(h('li', {}, href ? h('a', { href: href, onclick: function () { close(); input.value = ''; } }, inner) : h('span', { class: 'none' }, inner)));
      });
      list.hidden = false;
    }
    input.addEventListener('input', function () {
      clearTimeout(timer);
      var q = input.value.trim();
      if (!q) return close();
      timer = setTimeout(function () {
        var my = ++seq;
        Promise.resolve(api.search(q)).then(function (rows) { if (my === seq) show(rows); }).catch(close);
      }, 150);
    });
    input.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') close();
      if (e.key === 'Enter') {
        var a = list.querySelector('a');
        if (a) { location.hash = a.getAttribute('href'); close(); input.value = ''; input.blur(); }
      }
      if (e.key === 'ArrowDown') { var first = list.querySelector('a'); if (first) { e.preventDefault(); first.focus(); } }
    });
    list.addEventListener('keydown', function (e) {
      var items = Array.prototype.slice.call(list.querySelectorAll('a')), i = items.indexOf(document.activeElement);
      if (e.key === 'ArrowDown' && items[i + 1]) { e.preventDefault(); items[i + 1].focus(); }
      if (e.key === 'ArrowUp') { e.preventDefault(); (items[i - 1] || input).focus(); }
      if (e.key === 'Escape') { close(); input.focus(); }
    });
    document.addEventListener('click', function (e) { if (!e.target.closest('.search')) close(); });
  }

  /* -------------------------------------------------------------------- boot */
  // Loads the lists every screen uses (blocks, rooms, sections, faculty, periods). Run again after a change.
  function reloadMeta() {
    return Promise.resolve(api.meta()).then(function (meta) {
      M = meta;
      workDays = M.days.filter(function (d) { return d.working; });
      grids = M.grids || [];
      // every screen needs periods, rooms, sections and faculty, so an empty database stops here with a clear message
      if (!workDays.length || !grids.length || !periodsOf(defaultGrid()).length || !M.rooms.length || !M.sections.length || !M.faculty.length) {
        throw new Error('The database is connected but holds no timetable yet. Load it once: in the backend folder run "npm run load-data", then reload this page.');
      }
    });
  }

  // What edit.js (the Add data tab) uses from this file
  window.TT_UI = {
    h: h, field: field, panel: panel, table: table, select: select, go: go, render: render,
    uniq: uniq, byText: byText, roomText: roomText, timeText: timeText, blockName: blockName, sectionLabel: sectionLabel,
    meta: function () { return M; },
    workDays: function () { return workDays; },
    grids: function () { return grids; },
    defaultGrid: defaultGrid,
    periodsOf: periodsOf,
    reloadMeta: reloadMeta
  };

  function boot() {
    if (!api) {
      $('#view').append(errorBox(new Error('No data. Fill API_URL in config.js or keep data.js next to this page.')));
      return;
    }
    $('#view').append(loading());
    reloadMeta().then(function () {
      var mode = $('#mode');
      var hasSample = M.sections.some(function (s) { return s.sample; });
      mode.textContent = api.mode === 'api' ? 'Live data' : (hasSample ? 'Demo data' : 'Snapshot data');
      mode.className = 'mode' + (api.mode === 'api' ? ' live' : '');
      $('#foot').textContent = api.mode === 'api'
        ? 'Live data from ' + api.label + '.'
        : 'A snapshot of the Neo4j timetable graph (data.js), not live data.' +
          (hasSample ? ' Sections marked sample are made-up data that only show rooms shared by several sections.' : '') +
          ' For live data start start_timetable_finder.bat and use http://localhost:3100.';
      setupSearch();
      window.addEventListener('hashchange', render);
      render();
    }).catch(function (err) {
      $('#view').replaceChildren(errorBox(err, function () { location.reload(); }));
    });
  }
  boot();
})();
