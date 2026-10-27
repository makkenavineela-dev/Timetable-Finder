// =====================================================================
// Useful queries. Run them one at a time and change the ids as needed.
// Ids used below: section CSE-UG-2026-27-S5-5E4, day MON, period MON-P4,
//      floor PJ-F4 (building PJ, floor 4), faculty CSE-CAV.
// Sections follow a bell schedule (TimeGrid A or B). A room or faculty member is busy in a period when a class
// of theirs is in it or in an overlapping period of the other schedule:  (:TimeSlot)-[:OVERLAPS]-(t)
// =====================================================================


// 0. Draw the schema graph (labels and relationship types)
CALL db.schema.visualization();


// ---------------------------------------------------------------------
// LTP allotment
// ---------------------------------------------------------------------

// 1. Required vs allotted classes per course, from L-T-P
MATCH (sec:Section {id:'CSE-UG-2026-27-S5-5E4'})-[:HAS_ALLOTMENT]->(a:Allotment)-[:OF_COURSE]->(c:Course)
WHERE c.scheduling <> 'NONE'
MATCH (c)-[req:HAS_LTP]->(ct:LTP)
OPTIONAL MATCH (a)-[:HAS_CLASS]->(cl:Class)-[:OF_TYPE]->(ct)
WITH c, ct, req, count(cl) AS allotted
RETURN c.short AS course, c.LTP AS LTP, ct.name AS type, req.credits AS credits,
       req.classesPerWeek AS needed, allotted, req.classesPerWeek - allotted AS pending
ORDER BY course, type;


// ---------------------------------------------------------------------
// Free time of a section
// ---------------------------------------------------------------------

// 2. Day view of a section: every period with its class, or FREE
MATCH (sec:Section {id:'CSE-UG-2026-27-S5-5E4'})-[:FOLLOWS]->(:TimeGrid)-[:HAS_SLOT]->(t:TimeSlot)<-[:HAS_SLOT]-(:Day {id:'MON'})
OPTIONAL MATCH (sec)<-[:FOR_SECTION]-(cl:Class)-[:AT_TIME]->(t)
OPTIONAL MATCH (cl)-[:IN_ROOM]->(r:Room)
WITH t, cl, collect(r.number) AS rooms
RETURN t.period AS period,
       left(toString(t.start), 5) + '-' + left(toString(t.end), 5) AS time,
       coalesce(cl.name, 'FREE') AS class, rooms
ORDER BY period;


// 3. Only the free periods of a section on one day
MATCH (sec:Section {id:'CSE-UG-2026-27-S5-5E4'})-[:FOLLOWS]->(:TimeGrid)-[:HAS_SLOT]->(t:TimeSlot)<-[:HAS_SLOT]-(:Day {id:'MON'})
WHERE NOT EXISTS { MATCH (sec)<-[:FOR_SECTION]-(:Class)-[:AT_TIME]->(t) }
RETURN t.id AS slot, left(toString(t.start), 5) + '-' + left(toString(t.end), 5) AS time
ORDER BY t.period;


// 4. Free periods of a section for every working day of the week
MATCH (sec:Section {id:'CSE-UG-2026-27-S5-5E4'})-[:FOLLOWS]->(:TimeGrid)-[:HAS_SLOT]->(t:TimeSlot)<-[:HAS_SLOT]-(d:Day {working: true})
WHERE NOT EXISTS { MATCH (sec)<-[:FOR_SECTION]-(:Class)-[:AT_TIME]->(t) }
WITH d, t ORDER BY t.period
WITH d, collect(left(toString(t.start), 5) + '-' + left(toString(t.end), 5)) AS freePeriods
RETURN d.name AS day, freePeriods
ORDER BY d.order;


// ---------------------------------------------------------------------
// Free rooms on a floor
// ---------------------------------------------------------------------

// 5. Free rooms on a floor in one period (the type column shows CLASSROOM or LAB)
MATCH (:Floor {id:'PJ-F4'})-[:HAS_ROOM]->(r:Room), (t:TimeSlot {id:'MON-P4'})
WHERE NOT EXISTS { MATCH (r)<-[:IN_ROOM]-(:Class)-[:AT_TIME]->(:TimeSlot)-[:OVERLAPS]-(t) }
RETURN r.number AS room, r.type AS type, r.capacity AS capacity
ORDER BY room;


// 6. Free periods of every room on a floor for one day (in schedule A; use TimeGrid {id:'B'} for the other)
MATCH (:Floor {id:'PJ-F4'})-[:HAS_ROOM]->(r:Room), (:TimeGrid {id:'A'})-[:HAS_SLOT]->(t:TimeSlot)<-[:HAS_SLOT]-(:Day {id:'MON'})
WHERE NOT EXISTS { MATCH (r)<-[:IN_ROOM]-(:Class)-[:AT_TIME]->(:TimeSlot)-[:OVERLAPS]-(t) }
WITH r, t ORDER BY t.period
WITH r, collect(left(toString(t.start), 5) + '-' + left(toString(t.end), 5)) AS freePeriods
RETURN r.number AS room, r.type AS type, freePeriods
ORDER BY room;


// 7. Classrooms on a floor that are free while the section is free
//    (where an extra class could go)
MATCH (sec:Section {id:'CSE-UG-2026-27-S5-5E4'})-[:FOLLOWS]->(:TimeGrid)-[:HAS_SLOT]->(t:TimeSlot)<-[:HAS_SLOT]-(:Day {id:'MON'})
WHERE NOT EXISTS { MATCH (sec)<-[:FOR_SECTION]-(:Class)-[:AT_TIME]->(t) }
MATCH (:Floor {id:'PJ-F4'})-[:HAS_ROOM]->(r:Room {type:'CLASSROOM'})
WHERE NOT EXISTS { MATCH (r)<-[:IN_ROOM]-(:Class)-[:AT_TIME]->(:TimeSlot)-[:OVERLAPS]-(t) }
WITH t, collect(r.number) AS freeRooms
RETURN t.id AS slot, left(toString(t.start), 5) + '-' + left(toString(t.end), 5) AS time, freeRooms
ORDER BY t.period;


// 8. Free periods of a faculty member on one day (schedule A; also not busy in an overlapping period of schedule B)
MATCH (f:Faculty {id:'CSE-CAV'}), (:TimeGrid {id:'A'})-[:HAS_SLOT]->(t:TimeSlot)<-[:HAS_SLOT]-(:Day {id:'MON'})
WHERE NOT EXISTS { MATCH (f)<-[:TAUGHT_BY]-(:Class)-[:AT_TIME]->(:TimeSlot)-[:OVERLAPS]-(t) }
RETURN t.id AS slot, left(toString(t.start), 5) + '-' + left(toString(t.end), 5) AS time
ORDER BY t.period;


// ---------------------------------------------------------------------
// Timetables
// ---------------------------------------------------------------------

// 9. Timetable of a section (rebuilds the printed sheet)
MATCH (sec:Section {id:'CSE-UG-2026-27-S5-5E4'})<-[:FOR_SECTION]-(cl:Class)
      -[:AT_TIME]->(t:TimeSlot)<-[:HAS_SLOT]-(d:Day)
OPTIONAL MATCH (cl)<-[:HAS_CLASS]-(:Allotment)-[:OF_COURSE]->(c:Course)
OPTIONAL MATCH (cl)-[:OF_TYPE]->(ct:LTP)
OPTIONAL MATCH (cl)-[:IN_ROOM]->(r:Room)
OPTIONAL MATCH (cl)-[:TAUGHT_BY]->(f:Faculty)
OPTIONAL MATCH (cl)-[:FOR_BATCH]->(b:Batch)-[:ASSIGNED_TO]->(bf:Faculty)
WITH d, cl, c, ct, r, t, f, b, bf ORDER BY b.name
WITH d, cl, c, ct, min(t.start) AS start, max(t.end) AS end,
     collect(DISTINCT r.number) AS rooms,
     collect(DISTINCT f.initials) AS teachers,
     collect(DISTINCT b.name + '-' + bf.initials) AS batches
RETURN d.name AS day, left(toString(start), 5) + '-' + left(toString(end), 5) AS time,
       cl.name AS class, c.code AS code, ct.name AS type, rooms,
       CASE WHEN size(batches) > 0 THEN batches ELSE teachers END AS faculty
ORDER BY d.order, start;


// 10. Timetable of a faculty member
MATCH (f:Faculty {id:'CSE-CAV'})<-[:TAUGHT_BY]-(cl:Class)-[:AT_TIME]->(t:TimeSlot)<-[:HAS_SLOT]-(d:Day)
OPTIONAL MATCH (cl)-[:FOR_SECTION]->(sec:Section)
OPTIONAL MATCH (cl)-[:IN_ROOM]->(r:Room)
OPTIONAL MATCH (cl)-[:FOR_BATCH]->(b:Batch)-[:ASSIGNED_TO]->(f)
WITH d, cl, sec, r, t, b ORDER BY b.name
WITH d, cl, sec, min(t.start) AS start, max(t.end) AS end,
     collect(DISTINCT r.number) AS rooms, collect(DISTINCT b.name) AS batches
RETURN d.name AS day, left(toString(start), 5) + '-' + left(toString(end), 5) AS time,
       cl.name AS class, sec.name AS section, rooms, batches
ORDER BY d.order, start;


// 11. Timetable of a student (only their own lab batch)
MATCH (st:Student {usn:'1BM23CS001'})-[:IN_SECTION]->(sec:Section)<-[:FOR_SECTION]-(cl:Class)
WHERE NOT EXISTS { (cl)-[:FOR_BATCH]->() }
   OR EXISTS { (cl)-[:FOR_BATCH]->(:Batch)<-[:IN_BATCH]-(st) }
MATCH (cl)-[:AT_TIME]->(t:TimeSlot)<-[:HAS_SLOT]-(d:Day)
OPTIONAL MATCH (cl)-[:IN_ROOM]->(r:Room)
WITH d, cl, min(t.start) AS start, max(t.end) AS end, collect(DISTINCT r.number) AS rooms
RETURN d.name AS day, left(toString(start), 5) + '-' + left(toString(end), 5) AS time,
       cl.name AS class, rooms
ORDER BY d.order, start;


// ---------------------------------------------------------------------
// Checks and reports
// ---------------------------------------------------------------------

// 12. Clashes: a section, faculty member or room with two classes at the same time.
//     Faculty and rooms are also checked against the other schedule's overlapping periods. No rows = no clashes.
MATCH (sec:Section)<-[:FOR_SECTION]-(cl:Class)-[:AT_TIME]->(t:TimeSlot)
WITH 'SECTION' AS kind, sec.id AS who, t, collect(cl.id) AS classes
WHERE size(classes) > 1
RETURN kind, who, t.id AS slot, classes
UNION
MATCH (x)<-[:TAUGHT_BY|IN_ROOM]-(c1:Class)-[:AT_TIME]->(t1:TimeSlot)-[:OVERLAPS]-(t2:TimeSlot)<-[:AT_TIME]-(c2:Class)-[:TAUGHT_BY|IN_ROOM]->(x)
WHERE c1.id < c2.id
RETURN CASE WHEN x:Faculty THEN 'FACULTY' ELSE 'ROOM' END AS kind, x.id AS who, t1.id + ' / ' + t2.id AS slot, [c1.id, c2.id] AS classes;


// 13. Sections and students per department for a year
MATCH (d:Department)-[:OFFERS]->(:Program)-[:HAS_ACADEMIC_YEAR]->(:AcademicYear {year:'2026-27'})
      -[:HAS_SEMESTER]->(:Semester)-[:HAS_SECTION]->(sec:Section)
OPTIONAL MATCH (sec)<-[:IN_SECTION]-(s:Student)
RETURN d.id AS department, count(DISTINCT sec) AS sections, count(DISTINCT s) AS students
ORDER BY department;
