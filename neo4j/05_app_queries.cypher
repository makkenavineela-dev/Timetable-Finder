// =====================================================================
// Queries behind the timetable web app (backend API -> Neo4j)
//
// Every query is read-only and takes $parameters, so the backend passes
// user input as parameters and never builds Cypher from text.
// "@name" is how backend/src/queries.js finds the query, "@params" is an example.
// Day ids: MON TUE WED THU FRI SAT. Period ids: MON-P4 (schedule A), B-MON-P4 (schedule B).
//
// Sections follow one bell schedule (TimeGrid). A section is busy in a period when one of
// its classes is in it. A room or faculty member is busy when a class of theirs is in that
// period OR in a period of the other schedule that shares time with it:
//     (:TimeSlot)-[:OVERLAPS]-(t)        (a period also overlaps itself)
// =====================================================================


// @name: meta_rooms
// @params: {}
// Filter lists for the search screens: buildings > floors > rooms
MATCH (b:Building)-[:HAS_FLOOR]->(f:Floor)-[:HAS_ROOM]->(r:Room)
RETURN b.id AS building, b.name AS buildingName, f.id AS floorId, f.number AS floor, r.id AS roomId,
       r.number AS room, r.type AS type, r.capacity AS capacity
ORDER BY building, floor, room;


// @name: meta_sections
// @params: {}
MATCH (d:Department)-[:OFFERS]->(p:Program)-[:HAS_ACADEMIC_YEAR]->(ay:AcademicYear)
      -[:HAS_SEMESTER]->(sem:Semester)-[:HAS_SECTION]->(sec:Section)
OPTIONAL MATCH (fc:FacultyCluster)-[:HAS_SECTION]->(sec)
OPTIONAL MATCH (sec)-[:FOLLOWS]->(g:TimeGrid)
RETURN sec.id AS id, sec.name AS section, d.id AS department, d.name AS departmentName, p.name AS program,
       ay.year AS year, sem.number AS semester, sem.id AS semesterId, fc.name AS cluster, g.id AS grid
ORDER BY department, year, semester, cluster, section;


// @name: meta_faculty
// @params: {}
MATCH (f:Faculty)-[:WORKS_IN]->(d:Department)
RETURN f.id AS id, f.initials AS initials, f.name AS name, d.id AS department, d.name AS departmentName
ORDER BY initials, id;


// @name: meta_periods
// @params: {}
// Every period of every schedule
MATCH (g:TimeGrid)-[:HAS_SLOT]->(t:TimeSlot)<-[:HAS_SLOT]-(d:Day)
RETURN g.id AS grid, g.name AS gridName, g.default AS defaultGrid,
       d.id AS day, d.name AS dayName, d.order AS dayOrder, d.working AS working,
       t.id AS slot, t.period AS period,
       left(toString(t.start), 5) AS start, left(toString(t.end), 5) AS end
ORDER BY grid, dayOrder, period;


// @name: search
// @params: {"q": "40"}
// One search box for sections, rooms, faculty and blocks. Each result opens its own page.
CALL () {
  MATCH (s:Section) WHERE toLower(s.name) CONTAINS toLower($q)
  RETURN 'SECTION' AS kind, s.id AS id, s.name AS label
  UNION
  MATCH (r:Room) WHERE toLower(r.number) CONTAINS toLower($q) OR toLower(r.id) CONTAINS toLower($q)
  RETURN 'ROOM' AS kind, r.id AS id, r.number AS label
  UNION
  MATCH (f:Faculty) WHERE toLower(f.name) CONTAINS toLower($q) OR toLower(f.initials) CONTAINS toLower($q)
  RETURN 'FACULTY' AS kind, f.id AS id, f.name AS label
  UNION
  MATCH (b:Building) WHERE toLower(b.name) CONTAINS toLower($q) OR toLower(b.id) CONTAINS toLower($q)
  RETURN 'BUILDING' AS kind, b.id AS id, b.name AS label
}
RETURN kind, id, label
ORDER BY kind, label, id
LIMIT 25;


// @name: floor_occupancy
// @params: {"floor": "PJ-F4", "slot": "MON-P4"}
// Every room on a floor in one period: FREE, or OCCUPIED with section, class and faculty.
// A room used by two overlapping classes shows the first one (by class id).
MATCH (:Floor {id: $floor})-[:HAS_ROOM]->(r:Room), (t:TimeSlot {id: $slot})
OPTIONAL MATCH (r)<-[:IN_ROOM]-(cl:Class)-[:AT_TIME]->(:TimeSlot)-[:OVERLAPS]-(t)
OPTIONAL MATCH (cl)-[:FOR_SECTION]->(sec:Section)
OPTIONAL MATCH (cl)-[:TAUGHT_BY]->(f:Faculty)
WITH r, cl, sec, collect(DISTINCT f.initials) AS faculty
ORDER BY cl.id
WITH r, collect({cl: cl, sec: sec, faculty: faculty})[0] AS u
RETURN r.number AS room, r.id AS roomId, r.type AS type,
       CASE WHEN u.cl IS NULL THEN 'FREE' ELSE 'OCCUPIED' END AS status,
       u.sec.name AS section, u.sec.id AS sectionId, u.cl.name AS class, u.faculty AS faculty
ORDER BY room, roomId;


// @name: floor_day_grid
// @params: {"floor": "PJ-F4", "day": "MON", "grid": null}
// Rooms x periods of one schedule (grid null = the default one) for one day: the whole floor at a glance
MATCH (:Floor {id: $floor})-[:HAS_ROOM]->(r:Room),
      (g:TimeGrid)-[:HAS_SLOT]->(t:TimeSlot)<-[:HAS_SLOT]-(:Day {id: $day})
WHERE g.id = $grid OR ($grid IS NULL AND g.default)
OPTIONAL MATCH (r)<-[:IN_ROOM]-(cl:Class)-[:AT_TIME]->(:TimeSlot)-[:OVERLAPS]-(t)
OPTIONAL MATCH (cl)-[:FOR_SECTION]->(sec:Section)
WITH r, t, cl, sec ORDER BY cl.id
WITH r, t, collect({cl: cl, sec: sec})[0] AS u
RETURN r.number AS room, r.id AS roomId, r.type AS type, t.period AS period,
       CASE WHEN u.cl IS NULL THEN 'FREE' ELSE 'OCCUPIED' END AS status,
       u.sec.name AS section, u.sec.id AS sectionId, u.cl.name AS class
ORDER BY room, roomId, period;


// @name: free_rooms
// @params: {"building": "PJ", "floor": null, "type": "CLASSROOM", "slot": "MON-P2", "minCapacity": null}
// Find free rooms. Any filter can be null to skip it.
MATCH (b:Building)-[:HAS_FLOOR]->(fl:Floor)-[:HAS_ROOM]->(r:Room), (t:TimeSlot {id: $slot})
WHERE ($building IS NULL OR b.id = $building)
  AND ($floor IS NULL OR fl.id = $floor)
  AND ($type IS NULL OR r.type = $type)
  AND ($minCapacity IS NULL OR r.capacity >= $minCapacity)
  AND NOT EXISTS { MATCH (r)<-[:IN_ROOM]-(:Class)-[:AT_TIME]->(:TimeSlot)-[:OVERLAPS]-(t) }
RETURN b.id AS building, fl.number AS floor, r.number AS room, r.id AS roomId, r.type AS type, r.capacity AS capacity
ORDER BY building, floor, room, roomId;


// @name: section_week
// @params: {"section": "CSE-UG-2026-27-S5-5E4"}
// Week grid of a section, in the section's own schedule: each period holds a class, or nothing (free)
MATCH (sec:Section {id: $section})-[:FOLLOWS]->(:TimeGrid)-[:HAS_SLOT]->(t:TimeSlot)<-[:HAS_SLOT]-(d:Day {working: true})
OPTIONAL MATCH (sec)<-[:FOR_SECTION]-(cl:Class)-[:AT_TIME]->(t)
OPTIONAL MATCH (cl)-[:IN_ROOM]->(r:Room)
OPTIONAL MATCH (cl)-[:OF_TYPE]->(lt:LTP)
OPTIONAL MATCH (cl)-[:TAUGHT_BY]->(f:Faculty)
WITH d, t, cl, lt, collect(DISTINCT f.initials) AS faculty, collect(DISTINCT r {.id, .number}) AS rooms
RETURN d.id AS day, d.order AS dayOrder, t.period AS period,
       left(toString(t.start), 5) AS start, left(toString(t.end), 5) AS end,
       cl.id AS classId, cl.name AS class, lt.code AS type, rooms, faculty
ORDER BY dayOrder, period;


// @name: section_free_time
// @params: {"section": "CSE-UG-2026-27-S5-5E4", "day": null}
// Free periods of a section, one day or the whole week (day = null)
MATCH (sec:Section {id: $section})-[:FOLLOWS]->(:TimeGrid)-[:HAS_SLOT]->(t:TimeSlot)<-[:HAS_SLOT]-(d:Day {working: true})
WHERE ($day IS NULL OR d.id = $day)
  AND NOT EXISTS { MATCH (sec)<-[:FOR_SECTION]-(:Class)-[:AT_TIME]->(t) }
WITH d, t ORDER BY t.period
WITH d, collect({slot: t.id, period: t.period,
                 time: left(toString(t.start), 5) + '-' + left(toString(t.end), 5)}) AS free
RETURN d.id AS day, d.name AS dayName, free
ORDER BY d.order;


// @name: section_free_with_rooms
// @params: {"section": "CSE-UG-2026-27-S5-5E4", "day": "MON", "floor": "PJ-F4"}
// Where an extra class could go: periods when the section is free and which classrooms are free then
MATCH (sec:Section {id: $section})-[:FOLLOWS]->(:TimeGrid)-[:HAS_SLOT]->(t:TimeSlot)<-[:HAS_SLOT]-(:Day {id: $day})
WHERE NOT EXISTS { MATCH (sec)<-[:FOR_SECTION]-(:Class)-[:AT_TIME]->(t) }
OPTIONAL MATCH (:Floor {id: $floor})-[:HAS_ROOM]->(r:Room {type: 'CLASSROOM'})
WHERE NOT EXISTS { MATCH (r)<-[:IN_ROOM]-(:Class)-[:AT_TIME]->(:TimeSlot)-[:OVERLAPS]-(t) }
WITH t, r ORDER BY r.number
RETURN t.id AS slot, t.period AS period,
       left(toString(t.start), 5) + '-' + left(toString(t.end), 5) AS time,
       collect(r.number) AS freeRooms
ORDER BY period;


// @name: faculty_week
// @params: {"faculty": "CSE-CAV"}
// Everything a faculty member teaches in the week (labs show their own batches).
// grid says which schedule the class's periods belong to.
MATCH (f:Faculty {id: $faculty})<-[:TAUGHT_BY]-(cl:Class)-[:AT_TIME]->(t:TimeSlot)<-[:HAS_SLOT]-(d:Day)
OPTIONAL MATCH (cl)-[:FOR_SECTION]->(sec:Section)
OPTIONAL MATCH (cl)-[:FOR_BATCH]->(b:Batch)-[:ASSIGNED_TO]->(f)
WITH d, cl, sec, t, b ORDER BY b.name
WITH d, cl, sec, t.grid AS grid, min(t.period) AS firstPeriod, max(t.period) AS lastPeriod,
     min(t.start) AS start, max(t.end) AS end, collect(DISTINCT b.name) AS batches
OPTIONAL MATCH (cl)-[:IN_ROOM]->(r:Room)
WITH d, cl, sec, grid, firstPeriod, lastPeriod, start, end, batches, r ORDER BY r.number
WITH d, cl, sec, grid, firstPeriod, lastPeriod, start, end, batches, collect(r {.id, .number}) AS rooms
RETURN d.id AS day, d.order AS dayOrder, grid, firstPeriod, lastPeriod,
       left(toString(start), 5) + '-' + left(toString(end), 5) AS time,
       left(toString(start), 5) AS start, left(toString(end), 5) AS end,
       cl.name AS class, sec.name AS section, sec.id AS sectionId, rooms, batches
ORDER BY dayOrder, start, class;


// @name: faculty_free_time
// @params: {"faculty": "CSE-CAV", "day": "MON", "grid": null}
// Periods of one schedule (grid null = the default one) in which the faculty member has no class,
// also not in an overlapping period of the other schedule
MATCH (f:Faculty {id: $faculty}), (g:TimeGrid)-[:HAS_SLOT]->(t:TimeSlot)<-[:HAS_SLOT]-(d:Day {working: true})
WHERE (g.id = $grid OR ($grid IS NULL AND g.default))
  AND ($day IS NULL OR d.id = $day)
  AND NOT EXISTS { MATCH (f)<-[:TAUGHT_BY]-(:Class)-[:AT_TIME]->(:TimeSlot)-[:OVERLAPS]-(t) }
WITH d, t ORDER BY t.period
WITH d, collect({slot: t.id, period: t.period,
                 time: left(toString(t.start), 5) + '-' + left(toString(t.end), 5)}) AS free
RETURN d.id AS day, d.name AS dayName, free
ORDER BY d.order;


// @name: room_week
// @params: {"room": "PJ-406"}
// A room across the week: which section uses it and when (grid = the schedule of that class)
MATCH (r:Room {id: $room})<-[:IN_ROOM]-(cl:Class)-[:AT_TIME]->(t:TimeSlot)<-[:HAS_SLOT]-(d:Day)
OPTIONAL MATCH (cl)-[:FOR_SECTION]->(sec:Section)
OPTIONAL MATCH (cl)-[:TAUGHT_BY]->(f:Faculty)
WITH d, cl, sec, t, collect(DISTINCT f.initials) AS faculty
WITH d, cl, sec, faculty, t.grid AS grid, min(t.period) AS firstPeriod, max(t.period) AS lastPeriod,
     min(t.start) AS start, max(t.end) AS end
RETURN d.id AS day, d.order AS dayOrder, grid, firstPeriod, lastPeriod,
       left(toString(start), 5) + '-' + left(toString(end), 5) AS time,
       left(toString(start), 5) AS start, left(toString(end), 5) AS end,
       cl.name AS class, sec.name AS section, sec.id AS sectionId, faculty
ORDER BY dayOrder, start, class;


// @name: course_summary
// @params: {"section": "CSE-UG-2026-27-S5-5E4"}
// Courses of a section with L-T-P, teacher and how many classes are allotted
MATCH (sec:Section {id: $section})-[:HAS_ALLOTMENT]->(a:Allotment)-[:OF_COURSE]->(c:Course)
OPTIONAL MATCH (f:Faculty)-[:TEACHES {role: 'COURSE_TEACHER'}]->(a)
RETURN c.code AS code, c.short AS course, c.name AS name, c.LTP AS LTP, c.credits AS credits,
       c.scheduling AS scheduling, collect(DISTINCT f.initials) AS teacher,
       COUNT { (a)-[:HAS_CLASS]->() } AS classesAllotted,
       reduce(n = 0, x IN [(c)-[q:HAS_LTP]->() | q.classesPerWeek] | n + x) AS classesNeeded
ORDER BY course, code;
