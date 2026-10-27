// =====================================================================
// BMSCE college timetable graph - schema for Neo4j 5.x
// Every statement is safe to re-run.
//   Part A: unique keys and indexes
//   Part B: college-wide rules - LTP nodes, days and the weekly period grids (bell schedules)
//
// RUN ORDER  (cd backend, then npm run load-data does steps 1 and 2)
//   1. this file                      creates the schema
//   2. 02_cluster_E_sem5.cypher and
//      02_cluster_E_sem3.cypher       load sections, courses, faculty, rooms and classes
//   3. 07_auto_allot.cypher           optional: places the classes that are still missing
// =====================================================================
//
// GRAPH MODEL
//
//   Organisation
//   (College)-[:HAS_DEPARTMENT]->(Department)-[:OFFERS]->(Program)
//   (Program)-[:HAS_ACADEMIC_YEAR]->(AcademicYear)-[:HAS_SEMESTER]->(Semester)
//   (Semester)-[:HAS_SECTION]->(Section)
//   (Semester)-[:HAS_COURSE]->(Course)                curriculum of that semester
//
//   L-T-P (part of the main graph)
//   (Course)-[:HAS_LTP {credits, periodsPerWeek, classesPerWeek}]->(LTP)
//   LTP nodes: L Lecture, T Tutorial, P Practical (plus A Activity for
//   non-credit periods like the Friday seminar)
//   (Department)-[:HAS_FACULTY_CLUSTER]->(FacultyCluster)
//   (FacultyCluster)-[:HAS_SECTION]->(Section)
//   (FacultyCluster)-[:HAS_FACULTY]->(Faculty)-[:WORKS_IN]->(Department)
//
//   Buildings
//   (College)-[:HAS_BUILDING]->(Building)-[:HAS_FLOOR]->(Floor)-[:HAS_ROOM]->(Room)
//   (Section)-[:HOME_ROOM]->(Room)                    first choice when allotting
//
//   Allotment = one course given to one section
//   (Section)-[:HAS_ALLOTMENT]->(Allotment)-[:OF_COURSE]->(Course)
//   (Faculty)-[:TEACHES {role}]->(Allotment)          COURSE_TEACHER | COORDINATOR
//   (Allotment)-[:HAS_BATCH]->(Batch)-[:ASSIGNED_TO]->(Faculty)   lab / project batches
//
//   Class = one weekly class on the timetable
//   (Allotment)-[:HAS_CLASS]->(Class)
//   (Class)-[:OF_TYPE]->(LTP)                         L / T / P / A
//   (Class)-[:FOR_SECTION]->(Section)
//   (Class)-[:FOR_BATCH]->(Batch)                     labs only
//   (Class)-[:TAUGHT_BY]->(Faculty)                   lab: the faculty of every batch
//   (Class)-[:AT_TIME]->(TimeSlot)                    one link per period it uses
//   (Class)-[:IN_ROOM]->(Room)
//
//   Week grid. Semesters can follow different bell schedules (tea and lunch at other
//   times), so there is one TimeGrid per schedule and every section follows one.
//   (Section)-[:FOLLOWS]->(TimeGrid)
//   (TimeGrid)-[:HAS_SLOT]->(TimeSlot)                the periods of that schedule
//   (Day)-[:HAS_SLOT]->(TimeSlot)                     one TimeSlot per grid + day + period
//   (TimeSlot)-[:NEXT]->(TimeSlot)                    only back-to-back periods of one grid
//   (TimeSlot)-[:OVERLAPS]-(TimeSlot)                 periods of any grid that share time on the
//                                                     same day (also to itself). A room or faculty
//                                                     member is busy in a period when a class is
//                                                     in ANY overlapping one.
//
//   Students
//   (Student)-[:IN_SECTION]->(Section)                one per semester = history
//   (Student)-[:IN_BATCH]->(Batch)
//   (Student)-[:ENROLLED_IN]->(Course)                chosen electives
//
// LTP -> CLASSES
//   Every course links to its L, T and P nodes. The HAS_LTP relationship
//   stores the credits and how many classes they need each week:
//     classesPerWeek = credits x periodsPerCredit / periodsPerClass
//   AI 3-0-1:  (AI)-[:HAS_LTP {credits:3, classesPerWeek:3}]->(L)   3 one-period lectures
//              (AI)-[:HAS_LTP {credits:1, classesPerWeek:1}]->(P)   1 two-period lab
//   DEV 2-1-0: (DEV)-[:HAS_LTP {credits:1, classesPerWeek:1}]->(T)  1 two-period tutorial
//   The rule numbers live on the LTP nodes (Part B), so changing a policy
//   means editing one node and re-running the HAS_LTP statement in the 02_* file of that semester.
//   Course.scheduling: REGULAR       needs a teacher and a room
//                      ELECTIVE_SLOT reserves the period only (the <PE> slots)
//                      NONE          not on the timetable (Mini Project, NCMC)
//   07_auto_allot.cypher creates the missing classes and
//   04_queries.cypher shows required vs allotted.
//
// FREE TIME
//   A class links to every period it occupies. A section is free in a TimeSlot when
//   none of its classes links to it; a faculty member or room is free when no class of
//   theirs links to it or to a period that OVERLAPS it (the other schedule's periods).
//   Tea and lunch are not periods, so they never show up as free time.
//
// IDS - built from the id of the parent, so 5A, Sem 5 or B1 can repeat
// in every department and year without clashing:
//   Department     CSE
//   Program        CSE-UG
//   AcademicYear   CSE-UG-2026-27
//   Semester       CSE-UG-2026-27-S5
//   Section        CSE-UG-2026-27-S5-5E4
//   Allotment      CSE-UG-2026-27-S5-5E4-23CS5PCAIN           section + course
//   Batch          CSE-UG-2026-27-S5-5E4-23CS5PCCON-B1        allotment + batch
//   Class          CSE-UG-2026-27-S5-5E4-23CS5PCAIN-L-MON-P5  allotment + type + first period
//   FacultyCluster CSE-E
//   Faculty        CSE-CAV          (use the employee id if you have one)
//   Building       PJ
//   Floor          PJ-F4
//   Room           PJ-406
//   Day            MON
//   TimeGrid       A (standard), B
//   TimeSlot       MON-P4 (grid A), B-MON-P4 (grid B)
//   LTP            code = L | T | P | A
//   Course         code = 23CS5PCAIN
//   Student        usn  = 1BM23CS001
// =====================================================================


// =====================================================================
// PART A - unique keys (each one also creates an index)
// =====================================================================

CREATE CONSTRAINT college_id         IF NOT EXISTS FOR (n:College)        REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT department_id      IF NOT EXISTS FOR (n:Department)     REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT program_id         IF NOT EXISTS FOR (n:Program)        REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT academic_year_id   IF NOT EXISTS FOR (n:AcademicYear)   REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT semester_id        IF NOT EXISTS FOR (n:Semester)       REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT section_id         IF NOT EXISTS FOR (n:Section)        REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT faculty_cluster_id IF NOT EXISTS FOR (n:FacultyCluster) REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT faculty_id         IF NOT EXISTS FOR (n:Faculty)        REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT course_code        IF NOT EXISTS FOR (n:Course)         REQUIRE n.code IS UNIQUE;
CREATE CONSTRAINT allotment_id       IF NOT EXISTS FOR (n:Allotment)      REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT batch_id           IF NOT EXISTS FOR (n:Batch)          REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT class_id           IF NOT EXISTS FOR (n:Class)          REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT ltp_code           IF NOT EXISTS FOR (n:LTP)            REQUIRE n.code IS UNIQUE;
CREATE CONSTRAINT student_usn        IF NOT EXISTS FOR (n:Student)        REQUIRE n.usn  IS UNIQUE;
CREATE CONSTRAINT building_id        IF NOT EXISTS FOR (n:Building)       REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT floor_id           IF NOT EXISTS FOR (n:Floor)          REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT room_id            IF NOT EXISTS FOR (n:Room)           REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT day_id             IF NOT EXISTS FOR (n:Day)            REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT timeslot_id        IF NOT EXISTS FOR (n:TimeSlot)       REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT timegrid_id        IF NOT EXISTS FOR (n:TimeGrid)       REQUIRE n.id   IS UNIQUE;


// ---------- lookup indexes for the fields you search by ----------

CREATE INDEX faculty_initials   IF NOT EXISTS FOR (n:Faculty)      ON (n.initials);
CREATE INDEX section_name       IF NOT EXISTS FOR (n:Section)      ON (n.name);
CREATE INDEX semester_number    IF NOT EXISTS FOR (n:Semester)     ON (n.number);
CREATE INDEX academic_year_year IF NOT EXISTS FOR (n:AcademicYear) ON (n.year);
CREATE INDEX course_name        IF NOT EXISTS FOR (n:Course)       ON (n.name);
CREATE INDEX course_category    IF NOT EXISTS FOR (n:Course)       ON (n.category);
CREATE INDEX course_scheduling  IF NOT EXISTS FOR (n:Course)       ON (n.scheduling);
CREATE INDEX batch_type         IF NOT EXISTS FOR (n:Batch)        ON (n.type);
CREATE INDEX room_type          IF NOT EXISTS FOR (n:Room)         ON (n.type);
CREATE INDEX room_number        IF NOT EXISTS FOR (n:Room)         ON (n.number);
CREATE INDEX floor_number       IF NOT EXISTS FOR (n:Floor)        ON (n.number);
CREATE INDEX timeslot_period    IF NOT EXISTS FOR (n:TimeSlot)     ON (n.period);
CREATE INDEX timeslot_grid      IF NOT EXISTS FOR (n:TimeSlot)     ON (n.grid);
CREATE INDEX student_admission  IF NOT EXISTS FOR (n:Student)      ON (n.admissionYear);

// Search students and faculty by part of their name
CREATE FULLTEXT INDEX person_name IF NOT EXISTS FOR (n:Student|Faculty) ON EACH [n.name];


// =====================================================================
// PART B - college-wide rules (shared by every department)
// =====================================================================

// ---------- LTP nodes: how many classes each credit needs ----------
// Change these numbers if the college changes its credit-hour policy.
//   periodsPerCredit  periods per week for 1 credit
//   periodsPerClass   length of one class (2 = back-to-back periods)
//   roomType          room the class needs
//   byBatch           class is taken batch-wise (all batches at once, one lab)
//   priority          allotment order: hardest to fit first

UNWIND [
  {code:'L', name:'Lecture',   periodsPerCredit:1, periodsPerClass:1, roomType:'CLASSROOM', byBatch:false, priority:3},
  {code:'T', name:'Tutorial',  periodsPerCredit:2, periodsPerClass:2, roomType:'CLASSROOM', byBatch:false, priority:2},
  {code:'P', name:'Practical', periodsPerCredit:2, periodsPerClass:2, roomType:'LAB',       byBatch:true,  priority:1},
  {code:'A', name:'Activity'}
] AS rule
MERGE (ct:LTP {code: rule.code})
  SET ct += rule;


// ---------- Days ----------
// working = false keeps the allotment off that day. The cluster E timetables
// have Saturday classes, so SAT is a working day.

UNWIND [['MON','Monday',1,true],   ['TUE','Tuesday',2,true],  ['WED','Wednesday',3,true],
        ['THU','Thursday',4,true], ['FRI','Friday',5,true],   ['SAT','Saturday',6,true]] AS d
MERGE (day:Day {id: d[0]})
  SET day.name = d[1], day.order = d[2], day.working = d[3];


// ---------- Bell schedules (time grids) ----------
//   A  tea 10:45-11:15, lunch 14:00-14:55, nine periods (the 5th semester sections)
//   B  tea 09:50-10:20, lunch 13:05-14:00, eight periods (the 3rd semester sections)
// default = the schedule the room screens show first.

UNWIND [
  {id:'A', name:'Schedule A (tea 10:45-11:15, lunch 14:00-14:55)', default:true},
  {id:'B', name:'Schedule B (tea 09:50-10:20, lunch 13:05-14:00)', default:false}
] AS g
MERGE (tg:TimeGrid {id: g.id})
  SET tg.name = g.name, tg.default = g.default;


// ---------- Periods: one TimeSlot per grid, day and period ----------
// Grid A keeps the ids MON-P1 ... SAT-P9, other grids add their letter: B-MON-P1 ... B-SAT-P8.

UNWIND [
  {grid:'A', periods:[[1,'08:00','08:55'], [2,'08:55','09:50'], [3,'09:50','10:45'], [4,'11:15','12:10'], [5,'12:10','13:05'],
                      [6,'13:05','14:00'], [7,'14:55','15:50'], [8,'15:50','16:45'], [9,'16:45','17:40']]},
  {grid:'B', periods:[[1,'08:00','08:55'], [2,'08:55','09:50'], [3,'10:20','11:15'], [4,'11:15','12:10'], [5,'12:10','13:05'],
                      [6,'14:00','14:55'], [7,'14:55','15:50'], [8,'15:50','16:45']]}
] AS gr
MATCH (tg:TimeGrid {id: gr.grid}), (day:Day)
UNWIND gr.periods AS p
MERGE (t:TimeSlot {id: CASE gr.grid WHEN 'A' THEN '' ELSE gr.grid + '-' END + day.id + '-P' + toString(p[0])})
  SET t.period = p[0], t.start = localtime(p[1]), t.end = localtime(p[2]), t.grid = gr.grid
MERGE (day)-[:HAS_SLOT]->(t)
MERGE (tg)-[:HAS_SLOT]->(t);

// NEXT joins back-to-back periods of one grid, never across the tea break or lunch,
// so a two-period lab or tutorial is always placed in continuous periods.
MATCH (tg:TimeGrid)-[:HAS_SLOT]->(a:TimeSlot)<-[:HAS_SLOT]-(day:Day)-[:HAS_SLOT]->(b:TimeSlot)<-[:HAS_SLOT]-(tg)
WHERE a.end = b.start
MERGE (a)-[:NEXT]->(b);

// OVERLAPS joins periods that share time on the same day, across grids (and each period to itself),
// so a room or faculty member busy in one schedule shows as busy in the other.
MATCH (day:Day)-[:HAS_SLOT]->(a:TimeSlot), (day)-[:HAS_SLOT]->(b:TimeSlot)
WHERE a.id < b.id AND a.start < b.end AND b.start < a.end
MERGE (a)-[:OVERLAPS]->(b);

// ... and each period to itself (the pattern above never matches the same period twice).
MATCH (t:TimeSlot)
MERGE (t)-[:OVERLAPS]->(t);
