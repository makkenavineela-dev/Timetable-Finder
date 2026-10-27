// =====================================================================
// Automatic class allotment from L-T-P. OPTIONAL: the timetable files (02_*) already hold the
// printed timetables; run this by hand to place classes that are still missing, for example
// the EVS lecture or a new section. It is NOT part of npm run load-data, because it would
// re-add classes you removed on the page. Safe to re-run: it only creates what is missing.
// Run it in Neo4j Browser (http://localhost:17474).
// =====================================================================
//
// The number of weekly classes for each course comes from its HAS_LTP
// relationships to the L, T and P nodes (Part B):
//   L credits x 1 period  -> one-period lectures
//   T credits x 2 periods -> two-period tutorials
//   P credits x 2 periods -> two-period labs (all batches together, one lab room)
// Only missing classes are created, so it is safe to re-run. After loading the 02_* files the
// gaps are the EVS lecture (1-0-0) of each 5th semester section and courses without a teacher.
//
// A class goes into the first block of periods where:
//   - the section is free in every period of the block
//   - every faculty member taking it is free (batch faculty for labs)
//   - a room of the right type is free (home room, then same floor, then any)
//   - the course has no other class of the same type that day
//   - the day is a working day and the periods are back-to-back, in the section's own schedule
//     (TimeGrid); room and faculty must also be free in every OVERLAPPING period of other schedules
// Among those, the lightest day of the section and the earliest period win.
// Labs go first, then tutorials, then lectures (hardest to fit first).
// A REGULAR course with no teacher yet is skipped. Anything that cannot be
// placed stays pending in query 1 of 04_queries.cypher.
// =====================================================================

// Step 1 - make sure every section has an Allotment for every course of its semester
MATCH (sem:Semester)-[:HAS_SECTION]->(sec:Section), (sem)-[:HAS_COURSE]->(c:Course)
MERGE (a:Allotment {id: sec.id + '-' + c.code})
MERGE (sec)-[:HAS_ALLOTMENT]->(a)
MERGE (a)-[:OF_COURSE]->(c);


// Step 2 - allot the missing classes of every section in the college.
// To allot only one section, change the first line to:
//   MATCH (sec:Section {id:'CSE-UG-2026-27-S5-5E4'})-[:HAS_ALLOTMENT]->(a:Allotment)-[:OF_COURSE]->(c:Course)
MATCH (sec:Section)-[:HAS_ALLOTMENT]->(a:Allotment)-[:OF_COURSE]->(c:Course)
WHERE c.scheduling IN ['REGULAR', 'ELECTIVE_SLOT']
MATCH (c)-[req:HAS_LTP]->(ct:LTP)
OPTIONAL MATCH (a)-[:HAS_CLASS]->(done:Class)-[:OF_TYPE]->(ct)
WITH sec, a, c, ct, req.classesPerWeek AS needed, count(done) AS allotted
WHERE allotted < needed
UNWIND range(1, needed - allotted) AS n
WITH sec, a, c, ct, n
ORDER BY ct.priority, a.id, n
CALL (sec, a, c, ct) {
  // 1. who must be free: the faculty of every batch for a lab, the course teacher otherwise
  OPTIONAL MATCH (a)-[:HAS_BATCH]->(:Batch {type:'LAB'})-[:ASSIGNED_TO]->(bf:Faculty)
  OPTIONAL MATCH (tf:Faculty)-[tr:TEACHES]->(a)
  WHERE tr.role = 'COURSE_TEACHER'
  WITH sec, a, c, ct, collect(DISTINCT bf) AS labStaff, collect(DISTINCT tf) AS teachers
  WITH sec, a, c, ct, CASE WHEN ct.byBatch THEN labStaff ELSE teachers END AS staff
  WHERE c.scheduling = 'ELECTIVE_SLOT' OR size(staff) > 0

  // 2. candidate blocks: periodsPerClass back-to-back periods of the section's schedule on a working day
  MATCH (sec)-[:FOLLOWS]->(:TimeGrid)-[:HAS_SLOT]->(t1:TimeSlot)<-[:HAS_SLOT]-(d:Day {working: true})
  MATCH p = (t1)-[:NEXT*0..2]->(:TimeSlot)
  WHERE length(p) = ct.periodsPerClass - 1
  WITH sec, a, c, ct, staff, d, t1, nodes(p) AS block

  // 3. keep blocks where the section, the faculty and a suitable room are all free
  WHERE NOT EXISTS { MATCH (sec)<-[:FOR_SECTION]-(:Class)-[:AT_TIME]->(t) WHERE t IN block }
    AND NOT EXISTS { MATCH (f:Faculty)<-[:TAUGHT_BY]-(:Class)-[:AT_TIME]->(:TimeSlot)-[:OVERLAPS]-(t)
                     WHERE f IN staff AND t IN block }
    AND NOT EXISTS { MATCH (a)-[:HAS_CLASS]->(prev:Class)-[:OF_TYPE]->(ct),
                           (prev)-[:AT_TIME]->(:TimeSlot)<-[:HAS_SLOT]-(d) }
    AND (c.scheduling = 'ELECTIVE_SLOT'
         OR EXISTS { MATCH (r:Room {type: ct.roomType})
                     WHERE NOT EXISTS { MATCH (r)<-[:IN_ROOM]-(:Class)-[:AT_TIME]->(:TimeSlot)-[:OVERLAPS]-(t) WHERE t IN block }
                       AND (r.capacity IS NULL OR sec.strength IS NULL OR r.capacity >= sec.strength) })

  // 4. lightest day of the section first, then the earliest period
  WITH sec, a, c, ct, staff, d, t1, block,
       size([(sec)<-[:FOR_SECTION]-(:Class)-[:AT_TIME]->(s:TimeSlot)<-[:HAS_SLOT]-(d) | s]) AS dayLoad
  ORDER BY dayLoad, d.order, t1.period
  LIMIT 1

  // 5. room: home room first, then a room on the same floor as the home room, then any free room
  OPTIONAL MATCH (sec)-[:HOME_ROOM]->(home:Room)<-[:HAS_ROOM]-(homeFloor:Floor)
  OPTIONAL MATCH (fl:Floor)-[:HAS_ROOM]->(r:Room {type: ct.roomType})
  WHERE c.scheduling = 'REGULAR'
    AND NOT EXISTS { MATCH (r)<-[:IN_ROOM]-(:Class)-[:AT_TIME]->(:TimeSlot)-[:OVERLAPS]-(t) WHERE t IN block }
    AND (r.capacity IS NULL OR sec.strength IS NULL OR r.capacity >= sec.strength)
  WITH sec, a, c, ct, staff, t1, block, r,
       CASE WHEN r = home THEN 0 WHEN fl = homeFloor THEN 1 ELSE 2 END AS roomRank
  ORDER BY roomRank, r.id
  LIMIT 1

  // 6. create the class and link it to its periods, faculty, room and batches
  MERGE (cl:Class {id: a.id + '-' + ct.code + '-' + t1.id})
    SET cl.name = CASE ct.code WHEN 'L' THEN c.short
                               WHEN 'T' THEN c.short + ' Tutorial'
                               ELSE c.short + ' Lab' END
  MERGE (a)-[:HAS_CLASS]->(cl)
  MERGE (cl)-[:OF_TYPE]->(ct)
  MERGE (cl)-[:FOR_SECTION]->(sec)
  FOREACH (t IN block | MERGE (cl)-[:AT_TIME]->(t))
  FOREACH (f IN staff | MERGE (cl)-[:TAUGHT_BY]->(f))
  FOREACH (rm IN CASE WHEN r IS NULL THEN [] ELSE [r] END | MERGE (cl)-[:IN_ROOM]->(rm))
  WITH a, ct, cl, block, r
  OPTIONAL MATCH (a)-[:HAS_BATCH]->(b:Batch {type:'LAB'})
  WHERE ct.byBatch
  WITH cl, block, r, collect(b) AS batches
  FOREACH (b IN batches | MERGE (cl)-[:FOR_BATCH]->(b))
  RETURN cl.name AS class, [t IN block | t.id] AS slots, r.id AS room
}
RETURN sec.name AS section, class, slots, room;
