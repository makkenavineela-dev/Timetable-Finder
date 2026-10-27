// =====================================================================
// Changes made from the "Add data" tab of the web app (backend/src/edit.js)
//
// Every query takes $parameters (checked by the backend first) and builds ids
// the same way as 01_schema.cypher: from the id of the parent.
// "Add" also means "update": saving something that exists changes it.
// Optional values that are null keep what is already stored.
// =====================================================================


// @name: courses
// @params: {}
// Every course with its semesters and L-T-P parts (for the course, class and remove forms)
MATCH (c:Course)
OPTIONAL MATCH (sem:Semester)-[:HAS_COURSE]->(c)
WITH c, collect(sem.id) AS semesters
RETURN c.code AS code, c.short AS short, c.name AS name, c.category AS category, c.LTP AS LTP,
       c.scheduling AS scheduling, semesters, [(c)-[:HAS_LTP]->(l:LTP) | l.code] AS parts
ORDER BY short, code;


// @name: save_room
// @params: {"block": "PJ", "blockName": null, "floor": 4, "number": "409", "type": "CLASSROOM", "capacity": 60}
// A room is found by block + room number; a new block or floor is created when needed.
MERGE (col:College {id: 'BMSCE'})
  ON CREATE SET col.name = 'B.M.S. College of Engineering', col.city = 'Bengaluru'
MERGE (b:Building {id: $block})
  ON CREATE SET b.name = coalesce($blockName, $block)
SET b.name = coalesce($blockName, b.name)
MERGE (col)-[:HAS_BUILDING]->(b)
MERGE (fl:Floor {id: $block + '-F' + toString($floor)})
  ON CREATE SET fl.number = $floor
MERGE (b)-[:HAS_FLOOR]->(fl)
WITH b, fl
OPTIONAL MATCH (b)-[:HAS_FLOOR]->(:Floor)-[:HAS_ROOM]->(same:Room {number: $number})
WITH fl, coalesce(head(collect(same.id)), $block + '-' + replace($number, ' ', '')) AS roomId
WITH fl, roomId, NOT EXISTS { MATCH (:Room {id: roomId}) } AS created
MERGE (r:Room {id: roomId})
SET r.number = $number, r.type = $type, r.capacity = coalesce($capacity, r.capacity)
WITH fl, r, created
// a room is on one floor: moving it removes the old link
OPTIONAL MATCH (other:Floor)-[h:HAS_ROOM]->(r) WHERE other <> fl
DELETE h
WITH DISTINCT fl, r, created
MERGE (fl)-[:HAS_ROOM]->(r)
RETURN r.id AS id, r.number AS number, fl.id AS floor, created;


// @name: save_faculty
// @params: {"department": "CSE", "initials": "ABC", "name": "Prof. A B C", "cluster": "E"}
MATCH (d:Department {id: $department})
WITH d, d.id + '-' + $initials AS facultyId
WITH d, facultyId, NOT EXISTS { MATCH (:Faculty {id: facultyId}) } AS created
MERGE (f:Faculty {id: facultyId})
SET f.initials = $initials, f.name = $name
MERGE (f)-[:WORKS_IN]->(d)
WITH d, f, created
// a cluster given moves the faculty member to it; no cluster keeps the current one
OPTIONAL MATCH (oc:FacultyCluster)-[h:HAS_FACULTY]->(f)
WHERE $cluster IS NOT NULL AND oc.id <> d.id + '-' + $cluster
DELETE h
WITH DISTINCT d, f, created
FOREACH (_ IN CASE WHEN $cluster IS NULL THEN [] ELSE [1] END |
  MERGE (fc:FacultyCluster {id: d.id + '-' + $cluster})
    ON CREATE SET fc.name = $cluster
  MERGE (d)-[:HAS_FACULTY_CLUSTER]->(fc)
  MERGE (fc)-[:HAS_FACULTY]->(f))
RETURN f.id AS id, f.name AS name, created;


// @name: save_course
// @params: {"semester": "CSE-UG-2026-27-S5", "code": "23CS5PEABC", "name": "Cloud Computing", "short": "CLC", "category": "PE", "ltp": "3-0-0", "scheduling": "REGULAR"}
// The L-T-P becomes HAS_LTP links (same rule as the 02_* files), and every
// section of the semester gets an allotment of the course.
MATCH (sem:Semester {id: $semester})
WITH sem, NOT EXISTS { MATCH (:Course {code: $code}) } AS created, [x IN split($ltp, '-') | toInteger(x)] AS ltp
MERGE (c:Course {code: $code})
SET c.name = $name, c.short = $short, c.category = coalesce($category, c.category), c.LTP = $ltp,
    c.credits = ltp[0] + ltp[1] + ltp[2], c.scheduling = $scheduling
MERGE (sem)-[:HAS_COURSE]->(c)
WITH sem, c, ltp, created
OPTIONAL MATCH (c)-[old:HAS_LTP]->()
DELETE old
WITH DISTINCT sem, c, ltp, created
CALL (c, ltp) {
  UNWIND [['L', ltp[0]], ['T', ltp[1]], ['P', ltp[2]]] AS part
  WITH c, part WHERE part[1] > 0
  MATCH (l:LTP {code: part[0]})
  MERGE (c)-[r:HAS_LTP]->(l)
  SET r.credits = part[1], r.periodsPerWeek = part[1] * l.periodsPerCredit,
      r.classesPerWeek = part[1] * l.periodsPerCredit / l.periodsPerClass
}
CALL (sem, c) {
  MATCH (sem)-[:HAS_SECTION]->(sec:Section)
  MERGE (a:Allotment {id: sec.id + '-' + c.code})
  MERGE (sec)-[:HAS_ALLOTMENT]->(a)
  MERGE (a)-[:OF_COURSE]->(c)
}
RETURN c.code AS id, c.short AS short, c.name AS name, created;


// @name: save_section
// @params: {"department": "CSE", "departmentName": null, "program": "UG", "year": "2026-27", "semester": 5, "cluster": "E", "name": "5E5", "code": null, "grid": null}
// Creates whatever is missing of College > Department > Program > Year > Semester > Section,
// puts the section on a bell schedule (grid null = the default one, or the one it has already),
// and gives the section an allotment of every course of its semester.
MERGE (col:College {id: 'BMSCE'})
  ON CREATE SET col.name = 'B.M.S. College of Engineering', col.city = 'Bengaluru'
MERGE (d:Department {id: $department})
  ON CREATE SET d.name = coalesce($departmentName, $department)
SET d.name = coalesce($departmentName, d.name)
MERGE (col)-[:HAS_DEPARTMENT]->(d)
MERGE (p:Program {id: $department + '-' + $program})
  ON CREATE SET p.name = $program
MERGE (d)-[:OFFERS]->(p)
MERGE (ay:AcademicYear {id: p.id + '-' + $year})
  ON CREATE SET ay.year = $year
MERGE (p)-[:HAS_ACADEMIC_YEAR]->(ay)
MERGE (sem:Semester {id: ay.id + '-S' + toString($semester)})
  ON CREATE SET sem.number = $semester, sem.term = CASE WHEN $semester % 2 = 1 THEN 'ODD' ELSE 'EVEN' END
MERGE (ay)-[:HAS_SEMESTER]->(sem)
WITH d, sem, sem.id + '-' + $name AS sectionId
WITH d, sem, sectionId, NOT EXISTS { MATCH (:Section {id: sectionId}) } AS created
MERGE (sec:Section {id: sectionId})
SET sec.name = $name, sec.code = coalesce($code, sec.code)
MERGE (sem)-[:HAS_SECTION]->(sec)
WITH d, sem, sec, created
OPTIONAL MATCH (oc:FacultyCluster)-[h:HAS_SECTION]->(sec)
WHERE $cluster IS NOT NULL AND oc.id <> d.id + '-' + $cluster
DELETE h
WITH DISTINCT d, sem, sec, created
FOREACH (_ IN CASE WHEN $cluster IS NULL THEN [] ELSE [1] END |
  MERGE (fc:FacultyCluster {id: d.id + '-' + $cluster})
    ON CREATE SET fc.name = $cluster
  MERGE (d)-[:HAS_FACULTY_CLUSTER]->(fc)
  MERGE (fc)-[:HAS_SECTION]->(sec))
WITH sem, sec, created
CALL (sec) {
  MATCH (g:TimeGrid) WHERE g.id = $grid OR ($grid IS NULL AND NOT EXISTS { (sec)-[:FOLLOWS]->() } AND g.default)
  OPTIONAL MATCH (sec)-[old:FOLLOWS]->(other:TimeGrid) WHERE other <> g
  DELETE old
  MERGE (sec)-[:FOLLOWS]->(g)
}
CALL (sem, sec) {
  MATCH (sem)-[:HAS_COURSE]->(c:Course)
  MERGE (a:Allotment {id: sec.id + '-' + c.code})
  MERGE (sec)-[:HAS_ALLOTMENT]->(a)
  MERGE (a)-[:OF_COURSE]->(c)
}
RETURN sec.id AS id, sec.name AS name, created, [(sec)-[:FOLLOWS]->(g:TimeGrid) | g.id][0] AS grid;


// @name: set_teacher
// @params: {"section": "CSE-UG-2026-27-S5-5E4", "course": "23CS5PCAIN", "faculty": "CSE-CAV"}
// The course teacher of one section's course (faculty null = no teacher). Classes keep their faculty.
MATCH (sec:Section {id: $section})-[:HAS_ALLOTMENT]->(a:Allotment)-[:OF_COURSE]->(c:Course {code: $course})
OPTIONAL MATCH (:Faculty)-[old:TEACHES {role: 'COURSE_TEACHER'}]->(a)
DELETE old
WITH DISTINCT sec, a, c
OPTIONAL MATCH (f:Faculty {id: $faculty})
FOREACH (_ IN CASE WHEN f IS NULL THEN [] ELSE [1] END | MERGE (f)-[:TEACHES {role: 'COURSE_TEACHER'}]->(a))
RETURN sec.name AS section, c.short AS course, f.initials AS teacher;


// @name: class_lookup
// @params: {"section": "CSE-UG-2026-27-S5-5E4", "kind": "L", "course": "23CS5PCAIN", "day": "MON", "period": 1, "rooms": ["PJ-406"], "faculty": ["CSE-CAV"]}
// Everything the backend checks before adding a class (no rows = no such section)
MATCH (sec:Section {id: $section}), (lt:LTP {code: $kind})
OPTIONAL MATCH (sec)-[:FOLLOWS]->(:TimeGrid)-[:HAS_SLOT]->(t1:TimeSlot {period: $period})<-[:HAS_SLOT]-(d:Day {id: $day})
OPTIONAL MATCH (t1)-[:NEXT]->(t2:TimeSlot)
OPTIONAL MATCH (sec)-[:HAS_ALLOTMENT]->(a:Allotment)-[:OF_COURSE]->(c:Course {code: $course})
RETURN sec.name AS section, d.working AS working, t1.id AS first, t2.id AS second,
       coalesce(lt.periodsPerClass, 1) AS length, lt.name AS kindName,
       a.id AS allotment, c.short AS short, c.LTP AS LTP,
       c IS NOT NULL AND EXISTS { MATCH (c)-[:HAS_LTP]->(lt) } AS inLtp,
       COLLECT { MATCH (r:Room) WHERE r.id IN $rooms RETURN r.id } AS rooms,
       COLLECT { MATCH (f:Faculty) WHERE f.id IN $faculty RETURN f.id } AS faculty;


// @name: class_clashes
// @params: {"section": "CSE-UG-2026-27-S5-5E4", "slots": ["MON-P1"], "rooms": ["PJ-406"], "faculty": ["CSE-CAV"]}
// Classes already in those periods that use the same section, a chosen room or a chosen faculty member.
// Rooms and faculty also clash with classes in overlapping periods of the other schedule.
UNWIND $slots AS s
MATCH (t:TimeSlot {id: s})
CALL (t) {
  MATCH (t)<-[:AT_TIME]-(cl:Class) RETURN cl, true AS ownGrid
  UNION
  MATCH (t)-[:OVERLAPS]-(:TimeSlot)<-[:AT_TIME]-(cl:Class) RETURN cl, false AS ownGrid
}
WITH DISTINCT t, cl
OPTIONAL MATCH (cl)-[:FOR_SECTION]->(sec:Section)
WITH t, cl, sec,
     COLLECT { MATCH (cl)-[:IN_ROOM]->(r:Room) WHERE r.id IN $rooms RETURN r.number } AS rooms,
     COLLECT { MATCH (cl)-[:TAUGHT_BY]->(f:Faculty) WHERE f.id IN $faculty RETURN f.initials } AS faculty
WHERE (sec.id = $section AND EXISTS { (cl)-[:AT_TIME]->(t) }) OR size(rooms) > 0 OR size(faculty) > 0
RETURN t.id AS slot, cl.name AS class, sec.name AS section, sec.id = $section AS sameSection, rooms, faculty
ORDER BY slot, class;


// @name: class_create
// @params: {"id": "...-23CS5PCAIN-L-MON-P1", "name": "AI", "section": "CSE-UG-2026-27-S5-5E4", "kind": "L", "allotment": "CSE-UG-2026-27-S5-5E4-23CS5PCAIN", "slots": ["MON-P1"], "rooms": ["PJ-406"], "faculty": ["CSE-CAV"]}
MATCH (sec:Section {id: $section}), (lt:LTP {code: $kind})
MERGE (cl:Class {id: $id})
SET cl.name = $name
MERGE (cl)-[:OF_TYPE]->(lt)
MERGE (cl)-[:FOR_SECTION]->(sec)
WITH cl
OPTIONAL MATCH (a:Allotment {id: $allotment})
FOREACH (_ IN CASE WHEN a IS NULL THEN [] ELSE [1] END | MERGE (a)-[:HAS_CLASS]->(cl))
WITH cl
CALL (cl) { UNWIND $slots AS s MATCH (t:TimeSlot {id: s}) MERGE (cl)-[:AT_TIME]->(t) }
CALL (cl) { UNWIND $rooms AS r MATCH (rm:Room {id: r}) MERGE (cl)-[:IN_ROOM]->(rm) }
CALL (cl) { UNWIND $faculty AS f MATCH (fa:Faculty {id: f}) MERGE (cl)-[:TAUGHT_BY]->(fa) }
RETURN cl.id AS id, cl.name AS name;


// ---------------------------------------------------------------------
// Removing. Each returns label and uses; something still in use (uses > 0)
// is not deleted and the backend says what depends on it.
// ---------------------------------------------------------------------

// @name: remove_class
// @params: {"id": "CSE-UG-2026-27-S5-5E4-23CS5PCAIN-L-MON-P5"}
MATCH (cl:Class {id: $id})
OPTIONAL MATCH (cl)-[:FOR_SECTION]->(sec:Section)
WITH cl, cl.name + coalesce(' of ' + sec.name, '') AS label
DETACH DELETE cl
RETURN label, 0 AS uses;


// @name: remove_room
// @params: {"id": "PJ-409"}
MATCH (r:Room {id: $id})
WITH r, 'Room ' + r.number AS label, COUNT { (r)<-[:IN_ROOM]-(:Class) } AS uses
FOREACH (_ IN CASE WHEN uses = 0 THEN [1] ELSE [] END | DETACH DELETE r)
RETURN label, uses;


// @name: remove_faculty
// @params: {"id": "CSE-ABC"}
MATCH (f:Faculty {id: $id})
WITH f, f.name AS label,
     COUNT { (f)<-[:TAUGHT_BY]-(:Class) } + COUNT { (f)<-[:ASSIGNED_TO]-(:Batch) } + COUNT { (f)-[:TEACHES]->() } AS uses
FOREACH (_ IN CASE WHEN uses = 0 THEN [1] ELSE [] END | DETACH DELETE f)
RETURN label, uses;


// @name: remove_course
// @params: {"id": "23CS5PEABC"}
// Also removes the course's allotments (and their batches) in every section.
MATCH (c:Course {code: $id})
WITH c, c.short + ' (' + c.name + ')' AS label, COUNT { (c)<-[:OF_COURSE]-(:Allotment)-[:HAS_CLASS]->(:Class) } AS uses
CALL (c, uses) {
  MATCH (a:Allotment)-[:OF_COURSE]->(c) WHERE uses = 0
  OPTIONAL MATCH (a)-[:HAS_BATCH]->(b:Batch)
  DETACH DELETE b, a
}
FOREACH (_ IN CASE WHEN uses = 0 THEN [1] ELSE [] END | DETACH DELETE c)
RETURN label, uses;


// @name: remove_section
// @params: {"id": "CSE-UG-2026-27-S5-5E5"}
// Also removes the section's allotments and batches.
MATCH (sec:Section {id: $id})
WITH sec, 'Section ' + sec.name AS label,
     COUNT { (sec)<-[:FOR_SECTION]-(:Class) } + COUNT { (sec)<-[:IN_SECTION]-(:Student) } AS uses
CALL (sec, uses) {
  MATCH (sec)-[:HAS_ALLOTMENT]->(a:Allotment) WHERE uses = 0
  OPTIONAL MATCH (a)-[:HAS_BATCH]->(b:Batch)
  DETACH DELETE b, a
}
FOREACH (_ IN CASE WHEN uses = 0 THEN [1] ELSE [] END | DETACH DELETE sec)
RETURN label, uses;


// @name: remove_empty_places
// @params: {}
// After a room is removed: floors without rooms and blocks without floors go too
CALL () { MATCH (fl:Floor) WHERE NOT EXISTS { (fl)-[:HAS_ROOM]->() } DETACH DELETE fl }
CALL () { MATCH (b:Building) WHERE NOT EXISTS { (b)-[:HAS_FLOOR]->() } DETACH DELETE b }
RETURN true AS done;
