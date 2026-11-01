// The "Add data" tab: forms that add, change or remove rooms, faculty, courses, sections and timetable
// classes in the Neo4j database. They need the backend (live data) and only work on the computer that runs it.
// This file loads before app.js and registers the tab; it uses app.js's helpers (window.TT_UI) only when
// the tab is drawn.
(function () {
  'use strict';

  var UI, api, h;   // set when the tab is drawn

  var FORMS = [
    ['class', 'Timetable class'], ['room', 'Room'], ['faculty', 'Faculty'], ['course', 'Course'],
    ['section', 'Section'], ['teacher', 'Course teacher'], ['remove', 'Remove']
  ];
  var KINDS = [['L', 'Lecture (1 period)'], ['T', 'Tutorial (2 periods)'], ['P', 'Lab (2 periods)'], ['A', 'Activity without a course (1 period)']];
  // course categories: short form and full name
  var CATEGORY_NAMES = {
    PC: 'Professional Core', IP: 'Integrated Professional Core', PE: 'Professional Elective', OE: 'Open Elective',
    BS: 'Basic Science', HS: 'Humanities and Social Sciences', AE: 'Ability Enhancement', SD: 'Skill Development',
    PW: 'Project Work', MC: 'Mandatory Course', NC: 'Non-credit Course'
  };
  var PROGRAM_NAMES = { UG: 'Undergraduate', PG: 'Postgraduate' };
  var done = null;   // result of the last change: shown once at the top when the tab is drawn again

  /* ------------------------------------------------------------ small helpers */
  function M() { return UI.meta(); }
  function enc(v) { return encodeURIComponent(v); }
  function input(id, attrs) { return h('input', Object.assign({ id: id, autocomplete: 'off' }, attrs)); }
  function put(form, id, v) { var el = form.elements[id]; if (el && v != null) el.value = v; }

  /* ------------------------------------- suggestions: the short form and the full name */
  // A suggestion is {value, name}: value is the short form (what is saved), name the full name shown beside it.
  function item(value, name, data) { return { value: String(value), name: String(name == null ? value : name), data: data }; }
  function findItem(list, text) {
    var t = String(text).trim().toLowerCase();
    if (!t) return null;
    function same(get) { return list.find(function (i) { return get(i).toLowerCase() === t; }) || null; }
    return same(function (i) { return i.value; }) || same(function (i) { return i.name; }) ||
      same(function (i) { return i.value + ' · ' + i.name; });
  }
  // A text box with a list of suggestions. Typing either the short form or the full name works: when you leave the
  // box, the full name is turned into the short form, and onPick(suggestion) lets the form fill its other boxes.
  // Returns [box, list] to put inside a field.
  function suggestBox(id, list, attrs, onPick) {
    var listId = id + '-list';
    var box = input(id, Object.assign({ list: listId }, attrs));
    box.addEventListener('change', function () {
      var hit = findItem(list, box.value);
      if (hit) { box.value = hit.value; if (onPick) onPick(hit); }
    });
    var options = list.map(function (i) { return h('option', { value: i.value, label: i.name }); });
    return [box, h('datalist', { id: listId }, options)];
  }
  function deptName(id) {
    var d = (M().departments || []).find(function (x) { return x.id === id; });
    return d && d.name ? d.name : id;
  }
  function deptLabel(id) { var n = deptName(id); return n !== id ? id + ' · ' + n : id; }
  function departmentItems() { return departments().map(function (d) { return item(d, deptName(d)); }); }
  function value(form, id) { var el = form.elements[id]; return el ? el.value.trim() : ''; }
  // the values chosen in every drop-down of a multiPick, without blanks or repeats
  function picked(form, name) {
    var out = [];
    Array.prototype.forEach.call(form.querySelectorAll('select[name="' + name + '"]'), function (x) {
      if (x.value && out.indexOf(x.value) < 0) out.push(x.value);
    });
    return out;
  }
  function sectionText(s) { return s.name + ' · ' + s.department + ' ' + s.program + ' ' + s.year + ' · sem ' + s.semester; }
  function sections() { return M().sections.slice().sort(function (a, b) { return UI.byText(sectionText(a), sectionText(b)); }); }
  function pickSection(id) { var list = sections(); return list.find(function (s) { return s.id === id; }) || list[0]; }
  function departments() {
    return UI.uniq(M().sections.map(function (s) { return s.department; })
      .concat(M().faculty.map(function (f) { return f.department; }))).sort();
  }
  function clusters() { return UI.uniq(M().sections.map(function (s) { return s.cluster; }).filter(Boolean)).sort(); }
  function clusterItems() { return clusters().map(function (c) { return item(c, 'Cluster ' + c); }); }
  function semesters() {
    var seen = {};
    return sections().filter(function (s) { return !seen[s.semesterId] && (seen[s.semesterId] = true); })
      .map(function (s) { return [s.semesterId, s.department + ' ' + s.program + ' ' + s.year + ' · semester ' + s.semester]; });
  }
  function facultyOptions() {
    return M().faculty.slice().sort(function (a, b) { return UI.byText(a.initials, b.initials); })
      .map(function (f) { return [f.id, f.initials + ' · ' + f.name]; });
  }
  function roomOptions() {
    var floorOf = {};
    M().floors.forEach(function (f) { floorOf[f.id] = f; });
    return M().rooms.slice().sort(function (a, b) {
      var fa = floorOf[a.floor], fb = floorOf[b.floor];
      return UI.byText(fa.building, fb.building) || fa.number - fb.number || UI.byText(a.number, b.number);
    }).map(function (r) {
      var fl = floorOf[r.floor];
      return [r.id, r.number + ' · ' + UI.blockName(fl.building) + ' floor ' + fl.number + ' · ' + r.type.toLowerCase()];
    });
  }
  // One drop-down to choose from options [[value, label]], and "+ Add another" for more (a lab can use
  // several rooms, and have several teachers). Each extra row has a button to take it away again.
  // box.set(values) fills it, for example with the course teacher.
  function multiPick(name, options, noneText, addText) {
    var box = h('div', { class: 'multi' }), rows = h('div', {});
    function row(value) {
      var sel = h('select', { name: name }, h('option', { value: '' }, noneText),
        options.map(function (o) { return h('option', { value: o[0], selected: o[0] === value }, o[1]); }));
      var line = h('div', { class: 'multirow' }, sel);
      line.append(h('button', {
        type: 'button', class: 'btn small', title: 'Take this one away', 'aria-label': 'Take this one away', onclick: function () {
          if (rows.children.length > 1) line.remove(); else sel.value = '';
        }
      }, '×'));
      return line;
    }
    box.set = function (values) {
      rows.replaceChildren(row(values[0] || ''));
      values.slice(1).forEach(function (v) { rows.append(row(v)); });
    };
    box.append(rows, h('button', { type: 'button', class: 'btn small', onclick: function () { rows.append(row('')); } }, '+ ' + addText));
    box.set([]);
    return box;
  }

  /* ------------------------------------------------------- forms and saving */
  function showResult(box, ok, text, details) {
    box.className = 'result box ' + (ok ? 'ok' : 'err');
    box.replaceChildren(h('p', {}, text));
    if (details && details.length) box.append(h('ul', {}, details.map(function (d) { return h('li', {}, d); })));
    box.hidden = false;
  }

  function form(title, note, fields, button, onSubmit) {
    var f = h('form', { class: 'panel editform', novalidate: true },
      h('h2', {}, title), note ? h('p', { class: 'note' }, note) : null,
      h('div', { class: 'fields' }, fields),
      h('div', { class: 'actions' }, h('button', { type: 'submit', class: 'btn' }, button)),
      h('div', { class: 'result', role: 'status', hidden: true }));
    f.addEventListener('submit', function (e) { e.preventDefault(); onSubmit(f); });
    return f;
  }

  // Sends one change. On success every list of the page is reloaded and the tab is drawn again,
  // showing describe(answer). On failure the server's explanation is shown under the form, which keeps what was typed.
  function save(form, send, describe) {
    var box = form.querySelector('.result'), button = form.querySelector('button[type=submit]');
    button.disabled = true;
    box.hidden = true;
    Promise.resolve().then(send).then(function (answer) {
      done = describe(answer);
      return UI.reloadMeta().then(UI.render);
    }).catch(function (err) {
      showResult(box, false, err.message, err.details);
      button.disabled = false;
    });
  }

  // A remove button that needs a second click within 4 seconds
  function removeButton(box, kind, id) {
    var armed = false, timer = 0;
    var b = h('button', { type: 'button', class: 'btn small' }, 'Remove');
    function disarm() { armed = false; b.textContent = 'Remove'; b.classList.remove('danger'); }
    b.addEventListener('click', function () {
      if (!armed) {
        armed = true;
        b.textContent = 'Click again';
        b.classList.add('danger');
        timer = setTimeout(disarm, 4000);
        return;
      }
      clearTimeout(timer);
      b.disabled = true;
      api.remove(kind, id).then(function (r) {
        done = { text: 'Removed ' + r.removed + '.' };
        return UI.reloadMeta().then(UI.render);
      }).catch(function (err) {
        showResult(box, false, err.message, err.details);
        b.disabled = false;
        disarm();
      });
    });
    return b;
  }

  /* ---------------------------------------------------------------- the forms */
  // A class on the timetable, and the section's classes with Remove buttons
  function classForm(p) {
    var sec = pickSection(p.s);
    return Promise.all([api.courseList(), api.courses(sec.id), api.sectionWeek(sec.id)]).then(function (res) {
      var teacherOf = {};
      res[1].forEach(function (c) { teacherOf[c.code] = c.teacher || []; });
      // courses of this section's semester that go on the timetable
      var courses = res[0].filter(function (c) { return c.semesters.indexOf(sec.semesterId) >= 0 && c.scheduling !== 'NONE'; });
      var courseSel = UI.select('e-course', [], '');
      var courseField = UI.field('Course', courseSel);
      var activityNames = UI.uniq(res[2].filter(function (r) { return r.classId && r.type === 'A'; }).map(function (r) { return r.class; }));
      var nameField = UI.field('Name', suggestBox('e-name', activityNames.map(function (n) { return item(n); }), { placeholder: 'Seminar', class: 'wide' }));
      var facBox = multiPick('fac', facultyOptions(), 'Choose a faculty member', 'Add another faculty member');
      var roomBox = multiPick('room', roomOptions(), 'No room', 'Add another room');
      var periods = UI.periodsOf(sec.grid || UI.defaultGrid());
      var f;

      function fillCourses() {
        var kind = value(f, 'e-kind');
        var fit = courses.filter(function (c) { return c.parts.indexOf(kind) >= 0; });
        courseSel.replaceChildren.apply(courseSel, fit.length
          ? fit.map(function (c) { return h('option', { value: c.code }, c.short + ' · ' + c.name + ' (' + c.LTP + ')'); })
          : [h('option', { value: '' }, 'No course of this semester has this kind')]);
        courseField.hidden = kind === 'A';
        nameField.hidden = kind !== 'A';
        tickTeacher();
      }
      // the course teacher is chosen as the faculty member; change it if someone else takes this class
      function tickTeacher() {
        var initials = value(f, 'e-kind') === 'A' ? [] : teacherOf[courseSel.value] || [];
        facBox.set(M().faculty.filter(function (x) { return initials.indexOf(x.initials) >= 0; }).map(function (x) { return x.id; }));
      }

      f = form('Add a class to the timetable',
        'It is saved only when the section, every room and every faculty member chosen are free in all its periods' +
        (UI.grids().length > 1 ? ' (also against the other schedule\'s periods)' : '') + '. Tutorials and labs take two periods in a row. ' +
        'This section follows ' + (UI.grids().length > 1 ? 'schedule ' + (sec.grid || UI.defaultGrid()) : 'its schedule') + '.', [
          UI.field('Section', UI.select('e-section', sections().map(function (s) { return [s.id, sectionText(s)]; }), sec.id,
            function (v) { UI.go('edit', { f: 'class', s: v }); })),
          UI.field('Kind', UI.select('e-kind', KINDS, 'L', fillCourses)),
          courseField, nameField,
          UI.field('Day', UI.select('e-day', UI.workDays().map(function (d) { return [d.id, d.name]; }), UI.workDays()[0].id)),
          UI.field('Starts in', UI.select('e-period', periods.map(function (pd) { return [String(pd.period), 'P' + pd.period + ' · ' + pd.start + '–' + pd.end]; }), '1')),
          h('div', { class: 'field' }, h('span', {}, 'Room (none for an elective slot)'), roomBox),
          h('div', { class: 'field' }, h('span', {}, 'Faculty'), facBox)
        ], 'Add class', function (form) {
          save(form, function () {
            var kind = value(form, 'e-kind');
            return api.save('classes', {
              section: sec.id, kind: kind,
              course: kind === 'A' ? null : value(form, 'e-course'),
              name: kind === 'A' ? value(form, 'e-name') : null,
              day: value(form, 'e-day'), period: value(form, 'e-period'),
              rooms: picked(form, 'room'), faculty: picked(form, 'fac')
            });
          }, function (r) {
            return { text: 'Added ' + r.name + ' for ' + r.section + ' (' + r.slots.map(function (s) { return s.replace(/-/g, ' '); }).join(', ') + ').', href: '#/sections?s=' + enc(sec.id), link: 'Open the section' };
          });
        });
      courseSel.addEventListener('change', tickTeacher);
      fillCourses();

      // the section's classes, one row per class
      var classes = [], byId = {}, dayName = {};
      UI.workDays().forEach(function (d) { dayName[d.id] = d.name.slice(0, 3); });
      res[2].forEach(function (r) {
        if (!r.classId) return;
        if (byId[r.classId]) { byId[r.classId].last = r.period; return; }
        byId[r.classId] = { id: r.classId, name: r.class, day: r.day, first: r.period, last: r.period, rooms: r.rooms };
        classes.push(byId[r.classId]);
      });
      var box = h('div', { class: 'result', role: 'status', hidden: true });
      var list = UI.panel('Classes of ' + sec.name, 'Remove a class to free its periods, rooms and faculty.',
        classes.length ? UI.table(['Day', 'Periods', 'Class', 'Rooms', ''], classes.map(function (c) {
          return [dayName[c.day] || c.day, 'P' + c.first + (c.last > c.first ? '–P' + c.last : ''), c.name,
            UI.roomText(c.rooms) || '–', removeButton(box, 'classes', c.id)];
        })) : h('p', { class: 'empty' }, 'No classes yet.'), box);
      return h('div', {}, f, list);
    });
  }

  function roomForm() {
    var floorOf = {};
    M().floors.forEach(function (f) { floorOf[f.id] = f; });
    var f;
    var blocks = M().buildings.map(function (b) { return item(b.id, b.name); });
    var blockNames = M().buildings.map(function (b) { return item(b.name, b.id); });
    var numbers = M().rooms.map(function (r) {
      var fl = floorOf[r.floor];
      return item(r.number, UI.blockName(fl.building) + ' floor ' + fl.number + ' · ' + r.type.toLowerCase(), r);
    });
    f = form('Add or change a room',
      'A room is known by its block and number: saving one that exists updates its floor, type and seats. A new block or floor is created when needed. Start typing: every box suggests the short form with its full name.', [
        UI.field('Block (short form)', suggestBox('e-block', blocks, { placeholder: 'PJ' }, function (hit) { put(f, 'e-blockname', hit.name); })),
        UI.field('Block name (new block only)', suggestBox('e-blockname', blockNames, { placeholder: 'optional' }, function (hit) { put(f, 'e-block', hit.name); })),
        UI.field('Floor', input('e-floor', { type: 'number', min: 0, max: 30, placeholder: '4' })),
        UI.field('Room number', suggestBox('e-number', numbers, { placeholder: '409 or LAB 402' }, function (hit) {
          var r = hit.data, fl = floorOf[r.floor];
          put(f, 'e-block', fl.building); put(f, 'e-blockname', UI.blockName(fl.building));
          put(f, 'e-floor', fl.number); put(f, 'e-type', r.type); put(f, 'e-seats', r.capacity == null ? '' : r.capacity);
        })),
        UI.field('Type', UI.select('e-type', [['CLASSROOM', 'Classroom'], ['LAB', 'Lab']], 'CLASSROOM')),
        UI.field('Seats', input('e-seats', { type: 'number', min: 1, max: 1000, placeholder: 'optional' }))
      ], 'Save room', function (form) {
        save(form, function () {
          return api.save('rooms', {
            block: value(form, 'e-block'), blockName: value(form, 'e-blockname'), floor: value(form, 'e-floor'),
            number: value(form, 'e-number'), type: value(form, 'e-type'), capacity: value(form, 'e-seats')
          });
        }, function (r) {
          return { text: (r.created ? 'Added room ' : 'Updated room ') + r.number + '.', href: '#/rooms?r=' + enc(r.id), link: 'Open the room' };
        });
      });
    return f;
  }

  function facultyForm() {
    var depts = departments();
    var f;
    function fill(hit) {
      var fac = hit.data;
      put(f, 'e-initials', fac.initials); put(f, 'e-name', fac.name); put(f, 'e-dept', fac.department);
    }
    var byInitials = M().faculty.map(function (x) { return item(x.initials, x.name, x); });
    var byName = M().faculty.map(function (x) { return item(x.name, x.initials, x); });
    f = form('Add or change a faculty member',
      'A faculty member is known by department and initials: saving initials that exist updates the name. An empty cluster keeps the current one. Choosing an existing person fills the other boxes.', [
        UI.field('Department', UI.select('e-dept', depts.map(function (d) { return [d, deptLabel(d)]; }), depts[0])),
        UI.field('Initials (short form)', suggestBox('e-initials', byInitials, { placeholder: 'ABC', maxlength: 6 }, fill)),
        UI.field('Full name', suggestBox('e-name', byName, { placeholder: 'Prof. A B Chandra', class: 'wide' }, fill)),
        UI.field('Cluster', suggestBox('e-cluster', clusterItems(), { placeholder: 'optional, for example E' }))
      ], 'Save faculty member', function (form) {
        save(form, function () {
          return api.save('faculty', { department: value(form, 'e-dept'), initials: value(form, 'e-initials'), name: value(form, 'e-name'), cluster: value(form, 'e-cluster') });
        }, function (r) {
          return { text: (r.created ? 'Added ' : 'Updated ') + r.name + '.', href: '#/faculty?f=' + enc(r.id), link: 'Open the timetable' };
        });
      });
    return f;
  }

  function courseForm() {
    return api.courseList().then(function (courses) {
      var sems = semesters();
      var f;
      function fill(hit) {
        var c = hit.data;
        put(f, 'e-code', c.code); put(f, 'e-cname', c.name); put(f, 'e-short', c.short);
        put(f, 'e-ltp', c.LTP); put(f, 'e-cat', c.category || ''); put(f, 'e-sched', c.scheduling);
      }
      var byCode = courses.map(function (c) { return item(c.code, c.short + ' · ' + c.name, c); });
      var byShort = courses.map(function (c) { return item(c.short, c.name, c); });
      var byName = courses.map(function (c) { return item(c.name, c.short + ' · ' + c.code, c); });
      var cats = Object.keys(CATEGORY_NAMES).map(function (k) { return item(k, CATEGORY_NAMES[k]); });
      courses.forEach(function (c) { if (c.category && !CATEGORY_NAMES[c.category]) cats.push(item(c.category, c.category)); });
      f = form('Add or change a course',
        'Every section of the chosen semester gets the course (it shows in their course list). Saving a code that exists updates the course. Choosing an existing course fills the other boxes.', [
          UI.field('Semester', UI.select('e-sem', sems, sems.length ? sems[sems.length - 1][0] : '')),
          UI.field('Course code', suggestBox('e-code', byCode, { placeholder: '23CS5PEABC' }, fill)),
          UI.field('Course name (full name)', suggestBox('e-cname', byName, { placeholder: 'Cloud Computing', class: 'wide' }, fill)),
          UI.field('Short name', suggestBox('e-short', byShort, { placeholder: 'CLC', maxlength: 12 }, fill)),
          UI.field('L-T-P', input('e-ltp', { placeholder: '3-0-1', maxlength: 5 })),
          UI.field('Category', suggestBox('e-cat', cats, { placeholder: 'optional, for example PE' })),
          UI.field('Scheduling', UI.select('e-sched', [['REGULAR', 'Regular (teacher and room)'],
            ['ELECTIVE_SLOT', 'Elective slot (period only)'], ['NONE', 'Not on the timetable']], 'REGULAR'))
        ], 'Save course', function (form) {
          save(form, function () {
            return api.save('courses', {
              semester: value(form, 'e-sem'), code: value(form, 'e-code'), name: value(form, 'e-cname'), short: value(form, 'e-short'),
              ltp: value(form, 'e-ltp'), category: value(form, 'e-cat'), scheduling: value(form, 'e-sched')
            });
          }, function (r) {
            return { text: (r.created ? 'Added course ' : 'Updated course ') + r.short + ' (' + r.name + ').' };
          });
        });
      return f;
    });
  }

  function sectionForm() {
    var list = sections(), last = list[list.length - 1] || {};
    var semesterNumbers = [1, 2, 3, 4, 5, 6, 7, 8].map(function (n) { return [String(n), 'Semester ' + n]; });
    var f;
    var depts = departmentItems();
    var deptNames = departments().map(function (d) { return item(deptName(d), d); });
    var programs = UI.uniq(['UG', 'PG'].concat(M().sections.map(function (s) { return s.program; }))).map(function (p) { return item(p, PROGRAM_NAMES[p] || p); });
    var years = UI.uniq(M().sections.map(function (s) { return s.year; })).sort().map(function (y) { return item(y, 'Academic year ' + y); });
    var names = UI.uniq(M().sections.map(function (s) { return s.name; })).map(function (n) {
      var s = M().sections.find(function (x) { return x.name === n; });
      return item(n, s.department + ' · semester ' + s.semester + (s.cluster ? ' · cluster ' + s.cluster : ''));
    });
    f = form('Add or change a section',
      'Department, program, year and semester are created when they are new. The section gets every course of its semester and follows the chosen bell schedule (the 5th semester sections follow A, the 3rd semester ones B). Every box suggests the short form with its full name.', [
        UI.field('Department (short form)', suggestBox('e-dept', depts, { placeholder: 'CSE', value: last.department || '' }, function (hit) { put(f, 'e-dname', hit.name); })),
        UI.field('Department name (full name; new department only)', suggestBox('e-dname', deptNames, { placeholder: 'optional', class: 'wide' }, function (hit) { put(f, 'e-dept', hit.name); })),
        UI.field('Program', suggestBox('e-prog', programs, { value: last.program || 'UG' })),
        UI.field('Academic year', suggestBox('e-year', years, { placeholder: '2026-27', value: last.year || '' })),
        UI.field('Semester', UI.select('e-semno', semesterNumbers, String(last.semester || 1))),
        UI.field('Cluster', suggestBox('e-cluster', clusterItems(), { placeholder: 'optional, for example E' })),
        UI.field('Section', suggestBox('e-sec', names, { placeholder: '5E5' })),
        UI.field('Section code', input('e-scode', { placeholder: 'optional, for example 5U' })),
        UI.grids().length > 1 ? UI.field('Bell schedule', UI.select('e-grid', [['', 'Keep / default']].concat(UI.grids().map(function (g) { return [g.id, g.name]; })), '')) : null
      ], 'Save section', function (form) {
        save(form, function () {
          return api.save('sections', {
            department: value(form, 'e-dept'), departmentName: value(form, 'e-dname'), program: value(form, 'e-prog'),
            year: value(form, 'e-year'), semester: value(form, 'e-semno'), cluster: value(form, 'e-cluster'),
            name: value(form, 'e-sec'), code: value(form, 'e-scode'), grid: value(form, 'e-grid')
          });
        }, function (r) {
          return { text: (r.created ? 'Added section ' : 'Updated section ') + r.name + '.', href: '#/sections?s=' + enc(r.id), link: 'Open the section' };
        });
      });
    return f;
  }

  function teacherForm(p) {
    var sec = pickSection(p.s);
    return api.courses(sec.id).then(function (courses) {
      var options = courses.map(function (c) {
        return [c.code, c.course + ' · ' + c.name + ' (now: ' + (c.teacher.length ? c.teacher.join(', ') : 'no teacher') + ')'];
      });
      return form('Set the course teacher',
        'The teacher of one section\'s course, shown in its course list. Classes already on the timetable keep their faculty.', [
          UI.field('Section', UI.select('e-section', sections().map(function (s) { return [s.id, sectionText(s)]; }), sec.id,
            function (v) { UI.go('edit', { f: 'teacher', s: v }); })),
          UI.field('Course', UI.select('e-course', options, options.length ? options[0][0] : '')),
          UI.field('Teacher', UI.select('e-teacher', [['', 'No teacher']].concat(facultyOptions()), ''))
        ], 'Save teacher', function (f) {
          save(f, function () {
            return api.save('teacher', { section: sec.id, course: value(f, 'e-course'), faculty: value(f, 'e-teacher') });
          }, function (r) {
            return { text: r.course + ' of ' + r.section + ': ' + (r.teacher ? 'the teacher is now ' + r.teacher : 'no teacher') + '.', href: '#/sections?s=' + enc(sec.id), link: 'Open the section' };
          });
        });
    });
  }

  function removeForm(p) {
    var kinds = [['rooms', 'Room'], ['faculty', 'Faculty member'], ['courses', 'Course'], ['sections', 'Section']];
    var kind = kinds.some(function (k) { return k[0] === p.k; }) ? p.k : 'rooms';
    var items = kind === 'courses'
      ? api.courseList().then(function (cs) { return cs.map(function (c) { return [c.code, c.short + ' · ' + c.name + ' (' + c.code + ')']; }); })
      : Promise.resolve(kind === 'rooms' ? roomOptions() : kind === 'faculty' ? facultyOptions()
        : sections().map(function (s) { return [s.id, sectionText(s)]; }));
    return items.then(function (options) {
      var armed = null;
      var f = form('Remove something',
        'Only what nothing depends on can be removed, so remove its classes first (Timetable class). Removing a course or a section also removes its course allotments.', [
          UI.field('What', UI.select('e-what', kinds, kind, function (v) { UI.go('edit', { f: 'remove', k: v }); })),
          UI.field('Which', UI.select('e-item', options, options.length ? options[0][0] : ''))
        ], 'Remove', function (form) {
          var item = value(form, 'e-item'), button = form.querySelector('button[type=submit]');
          if (armed !== item) {   // the first click only asks
            armed = item;
            button.textContent = 'Click again to remove';
            button.classList.add('danger');
            return;
          }
          disarm();
          save(form, function () { return api.remove(kind, item); }, function (r) { return { text: 'Removed ' + r.removed + '.' }; });
        });
      function disarm() {
        armed = null;
        var button = f.querySelector('button[type=submit]');
        button.textContent = 'Remove';
        button.classList.remove('danger');
      }
      f.elements['e-item'].addEventListener('change', disarm);
      return f;
    });
  }

  var BUILD = { class: classForm, room: roomForm, faculty: facultyForm, course: courseForm, section: sectionForm, teacher: teacherForm, remove: removeForm };

  /* --------------------------------------------------------------------- tab */
  function view(p) {
    UI = window.TT_UI;
    api = window.TT_API;
    h = UI.h;
    if (api.mode !== 'api') {
      return h('div', { class: 'box err', role: 'alert' }, h('p', {},
        'Adding data needs the server. Start start_timetable_finder.bat and open http://localhost:3100.'));
    }
    var which = Object.prototype.hasOwnProperty.call(BUILD, p.f) ? p.f : 'class';
    var nav = h('nav', { class: 'subtabs', 'aria-label': 'What to add' }, FORMS.map(function (x) {
      return h('a', { href: '#/edit?f=' + x[0], 'aria-current': x[0] === which ? 'page' : null }, x[1]);
    }));
    return api.editStatus().then(function () { return BUILD[which](p); }).then(function (body) {
      var top = null;
      if (done) {
        top = h('div', { class: 'box ok', role: 'status' }, h('p', {}, done.text, done.href ? [' ', h('a', { href: done.href }, done.link)] : null));
        done = null;
      }
      return h('div', {}, nav, top,
        h('p', { class: 'editnote' }, 'Changes are saved in the Neo4j database at once and show on every tab. ' +
          'Note: "npm run load-data" puts sections 5E1–5E4 back to the spreadsheet, so classes added to them here would then be lost.'),
        body);
    });
  }

  window.TT_EXTRA_VIEWS = (window.TT_EXTRA_VIEWS || []).concat([{ key: 'edit', label: 'Add data', view: view }]);
})();
