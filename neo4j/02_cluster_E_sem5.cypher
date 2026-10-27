// =====================================================================
// Cluster E, semester 5: 5E1 [5A], 5E2 [5J], 5E3 [5K], 5E4 [5T]
// Generated from cluster_E_timetable_dataset.xlsx by tools/build_cluster_E_sem5_cypher.py
// Source: 2 Cluster E 5th SEM CLASS TIMETABLE-wef 28-09-2026.pdf (4 pages)
// B.M.S. College of Engineering, Bangalore - 560019 - Department of Computer Science and Engineering
// September 2026 - December 2026, effective from 28/09/2026
//
// Run after 01_schema.cypher. All data files are loaded by:  cd backend  then  npm run load-data
//
// Block 0 is a clean-up. It deletes the classes, lab batches and allotments of the
// sections below, so that data loaded by an earlier version of this file cannot mix
// with this one. On an empty database it does nothing. Everything else uses MERGE
// and is safe to re-run.
//
// Decisions beyond what the sheets say:
//   - PE is an elective slot (reserves the period only) and Mini Project is not timetabled; both have no teacher in the file.
//   - The sessions called CC LAB are taken as the lab of the AE course (same assumption as in the 3rd semester file).
//   - Course codes follow this file: PE = 23CS5SPEXXX, AE = 23CS5SAEXXX (the earlier printed timetable showed 23CS5PEXXX / 23CS5AEXXX). The clean-up block removes the old two courses so they are not allotted twice.
//   - Room 'ISE-SH': block, floor and type are not given. Placed in a block called OTHER (floor 0) as a LAB, because a lab session is held there. Correct this if you know where it is.
//   - 'LAB 503,504' is read as 2 separate rooms (LAB 503, LAB 504); the class is linked to each of them.
//   - Room 'BSN-PG LAB': block, floor and type are not given. Placed in a block called OTHER (floor 0) as a LAB, because a lab session is held there. Correct this if you know where it is.
//   - '4F LAB 1-2' is kept as ONE room exactly as written. If it means 4F LAB 1 and 4F LAB 2 together, it overlaps the use of 4F LAB 1 by other sections.
//   - DEV_T sessions are the DEV tutorial (type T, two periods); the sheet lists them as 'Lecture'.
//   - EVS (1-0-0) has no session in the file, so it has no class yet. The allotment in Part C of 01_schema.cypher can place it.
//   - Effective from 28/09/2026; the earlier printed 5E4 timetable said 21/09/2026, so the file's date is used.
//   - Saturday is a working day (01_schema.cypher), because 5E1, 5E2 and 5E3 have Saturday classes.
//   - Room blocks: all numbered rooms and 'LAB nnn' are put in block PJ on the floor given by the first digit (4F LAB = floor 4). Only 406/407 were confirmed as PJ earlier; the rest are assumed.
//   - These sections follow time grid A: tea 10:45-11:15, lunch 14:00-14:55.
// =====================================================================


// ---------- 0. Clean-up of what this file replaces ----------

MATCH (cl:Class)-[:FOR_SECTION]->(s:Section)
WHERE s.id IN ['CSE-UG-2026-27-S5-5E1', 'CSE-UG-2026-27-S5-5E2', 'CSE-UG-2026-27-S5-5E3', 'CSE-UG-2026-27-S5-5E4', 'CSE-UG-2026-27-S5-5E5']
DETACH DELETE cl;

MATCH (s:Section)-[:HAS_ALLOTMENT]->(a:Allotment)
WHERE s.id IN ['CSE-UG-2026-27-S5-5E1', 'CSE-UG-2026-27-S5-5E2', 'CSE-UG-2026-27-S5-5E3', 'CSE-UG-2026-27-S5-5E4', 'CSE-UG-2026-27-S5-5E5']
OPTIONAL MATCH (a)-[:HAS_BATCH]->(b:Batch)
DETACH DELETE b, a;

MATCH (c:Course)
WHERE c.code IN ['23CS5PEXXX', '23CS5AEXXX']
DETACH DELETE c;

MATCH (s:Section {id: 'CSE-UG-2026-27-S5-5E5'})
DETACH DELETE s;


// ---------- 1. College > Department > Program > Year > Semester > Cluster ----------

MERGE (col:College {id:'BMSCE'})
  SET col.name = 'B.M.S. College of Engineering', col.city = 'Bengaluru'
MERGE (d:Department {id:'CSE'})
  SET d.name = 'Computer Science and Engineering'
MERGE (col)-[:HAS_DEPARTMENT]->(d)
MERGE (p:Program {id:'CSE-UG'})
  SET p.name = 'UG', p.degree = 'B.E.'
MERGE (d)-[:OFFERS]->(p)
MERGE (ay:AcademicYear {id:'CSE-UG-2026-27'})
  SET ay.year = '2026-27'
MERGE (p)-[:HAS_ACADEMIC_YEAR]->(ay)
MERGE (sem:Semester {id:'CSE-UG-2026-27-S5'})
  SET sem.number = 5, sem.term = 'ODD'
MERGE (ay)-[:HAS_SEMESTER]->(sem)
MERGE (fc:FacultyCluster {id:'CSE-E'})
  SET fc.name = 'E'
MERGE (d)-[:HAS_FACULTY_CLUSTER]->(fc);


// ---------- 2. Sections, and the bell schedule (time grid) they follow ----------

MATCH (sem:Semester {id:'CSE-UG-2026-27-S5'}), (fc:FacultyCluster {id:'CSE-E'}), (g:TimeGrid {id:'A'})
UNWIND [['CSE-UG-2026-27-S5-5E1', '5E1', '5A'], ['CSE-UG-2026-27-S5-5E2', '5E2', '5J'], ['CSE-UG-2026-27-S5-5E3', '5E3', '5K'], ['CSE-UG-2026-27-S5-5E4', '5E4', '5T']] AS s
MERGE (sec:Section {id: s[0]})
  SET sec.name = s[1], sec.code = s[2], sec.wef = date('2026-09-28')
MERGE (sem)-[:HAS_SECTION]->(sec)
MERGE (fc)-[:HAS_SECTION]->(sec)
WITH sec, g
OPTIONAL MATCH (sec)-[old:FOLLOWS]->(other:TimeGrid) WHERE other <> g
DELETE old
WITH DISTINCT sec, g
MERGE (sec)-[:FOLLOWS]->(g);


// ---------- 3. Blocks, floors and rooms ----------
// Rooms that already exist keep their ids, so every file links to the same rooms.

MATCH (col:College {id:'BMSCE'})
UNWIND [['OTHER', 'Location not given'], ['PJ', 'PJ']] AS b
MERGE (bl:Building {id: b[0]})
  SET bl.name = b[1]
MERGE (col)-[:HAS_BUILDING]->(bl);

UNWIND [['OTHER', 'OTHER-F0', 0, 'OTHER-ISE-SH', 'ISE-SH', 'LAB'], ['PJ', 'PJ-F4', 4, 'PJ-408', '408', 'CLASSROOM'], ['PJ', 'PJ-F4', 4, 'PJ-406', '406', 'CLASSROOM'], ['PJ', 'PJ-F4', 4, 'PJ-LAB401', 'LAB 401', 'LAB'], ['PJ', 'PJ-F4', 4, 'PJ-407', '407', 'CLASSROOM'], ['PJ', 'PJ-F5', 5, 'PJ-LAB503', 'LAB 503', 'LAB'], ['PJ', 'PJ-F5', 5, 'PJ-LAB504', 'LAB 504', 'LAB'], ['OTHER', 'OTHER-F0', 0, 'OTHER-BSN-PG-LAB', 'BSN-PG LAB', 'LAB'], ['PJ', 'PJ-F4', 4, 'PJ-4F-LAB1', '4F LAB 1', 'LAB'], ['PJ', 'PJ-F2', 2, 'PJ-220', '220', 'CLASSROOM'], ['PJ', 'PJ-F4', 4, 'PJ-4F-LAB1-2', '4F LAB 1-2', 'LAB'], ['PJ', 'PJ-F2', 2, 'PJ-206', '206', 'CLASSROOM']] AS r
MATCH (bl:Building {id: r[0]})
MERGE (fl:Floor {id: r[1]})
  SET fl.number = r[2]
MERGE (bl)-[:HAS_FLOOR]->(fl)
MERGE (room:Room {id: r[3]})
  SET room.number = r[4], room.type = r[5]
MERGE (fl)-[:HAS_ROOM]->(room);


// ---------- 4. Courses with their L-T-P ----------

MATCH (sem:Semester {id:'CSE-UG-2026-27-S5'})
UNWIND [['23CS5PCOOM', 'Object Oriented Modelling', 'OOM', 'PC', '2-0-1', 'REGULAR'], ['23CS5PCDEV', 'Data Exploration and Visualization', 'DEV', 'PC', '2-1-0', 'REGULAR'], ['23CS5PCAIN', 'Artificial Intelligence', 'AI', 'PC', '3-0-1', 'REGULAR'], ['23CS5PCCON', 'Computer Networks', 'CN', 'PC', '3-0-1', 'REGULAR'], ['23CV5HSEVS', 'Environmental Studies', 'EVS', 'HS', '1-0-0', 'REGULAR'], ['23CS5BSBIS', 'Bio Inspired Systems', 'BIS', 'BS', '0-0-1', 'REGULAR'], ['23CS5SPEXXX', 'Professional Elective', 'PE', 'PE', '3-0-0', 'ELECTIVE_SLOT'], ['23CS5SAEXXX', 'Ability Enhancement Course', 'CC', 'AE', '0-0-1', 'REGULAR'], ['23CS5PWMIP', 'Mini Project', 'MIP', 'PW', '0-0-1', 'NONE']] AS c
WITH sem, c, [x IN split(c[4], '-') | toInteger(x)] AS ltp
MERGE (course:Course {code: c[0]})
  SET course.name = c[1], course.short = c[2], course.category = c[3], course.LTP = c[4],
      course.credits = ltp[0] + ltp[1] + ltp[2], course.scheduling = c[5]
MERGE (sem)-[:HAS_COURSE]->(course);

UNWIND [['23CS5PCOOM', '2-0-1'], ['23CS5PCDEV', '2-1-0'], ['23CS5PCAIN', '3-0-1'], ['23CS5PCCON', '3-0-1'], ['23CV5HSEVS', '1-0-0'], ['23CS5BSBIS', '0-0-1'], ['23CS5SPEXXX', '3-0-0'], ['23CS5SAEXXX', '0-0-1'], ['23CS5PWMIP', '0-0-1']] AS c
MATCH (course:Course {code: c[0]})
WITH course, [x IN split(c[1], '-') | toInteger(x)] AS ltp
UNWIND [['L', ltp[0]], ['T', ltp[1]], ['P', ltp[2]]] AS part
WITH course, part WHERE part[1] > 0
MATCH (l:LTP {code: part[0]})
MERGE (course)-[r:HAS_LTP]->(l)
  SET r.credits = part[1], r.periodsPerWeek = part[1] * l.periodsPerCredit,
      r.classesPerWeek = part[1] * l.periodsPerCredit / l.periodsPerClass;


// ---------- 5. Faculty (initials only where the file gives no name) ----------

UNWIND [['CSE-AHV', 'AHV', 'Dr. Adarsha Sagar H V', 'CSE', true], ['CSE-SAN', 'SAN', 'Prof. Saritha A N', 'CSE', true], ['CSE-KRM', 'KRM', 'Dr. K R Mamatha', 'CSE', true], ['CSE-SPS', 'SPS', 'Prof. Supreeth S', 'CSE', true], ['CSE-NSJ', 'NSJ', 'Prof. Namitha S J', 'CSE', true], ['CSE-MGB', 'MGB', 'Prof. Monisha G B', 'CSE', true], ['CSE-VG', 'VG', 'Prof. Vishala G', 'CSE', true], ['CSE-CAV', 'CAV', 'Prof. Chinchu A V', 'CSE', true], ['CSE-LS', 'LS', 'Dr. Laxman Singh', 'CSE', true], ['CSE-SSB', 'SSB', 'Dr. Sneha S Bagalkot', 'CSE', true], ['CSE-KPM', 'KPM', 'Dr. K Panimozhi', 'CSE', true], ['CSE-SHR', 'SHR', 'Prof. Shwetha H R', 'CSE', true], ['CSE-RS', 'RS', 'Dr. Roopashree S', 'CSE', true], ['CSE-SUR', 'SUR', 'Prof. Surabhi S', 'CSE', true], ['CSE-MHM', 'MHM', null, 'CSE', true], ['CSE-SAH', 'SAH', null, 'CSE', true], ['CSE-NNM', 'NNM', null, 'CSE', true], ['CSE-AAS', 'AAS', null, 'CSE', true], ['CSE-AB', 'AB', null, 'CSE', true], ['CSE-SRN', 'SRN', null, 'CSE', true], ['CSE-BRH', 'BRH', null, 'CSE', true], ['CSE-BVK', 'BVK', null, 'CSE', true], ['CSE-STS', 'STS', null, 'CSE', true], ['CSE-AK', 'AK', null, 'CSE', true], ['CSE-SMR', 'SMR', null, 'CSE', true], ['CSE-SS', 'SS', null, 'CSE', true], ['CSE-CSP', 'CSP', null, 'CSE', true]] AS f
MATCH (d:Department {id: f[3]})
MERGE (fac:Faculty {id: f[0]})
  SET fac.initials = f[1], fac.name = coalesce(f[2], fac.name, f[1])
MERGE (fac)-[:WORKS_IN]->(d)
WITH fac, f WHERE f[4]
MATCH (fc:FacultyCluster {id:'CSE-E'})
MERGE (fc)-[:HAS_FACULTY]->(fac);


// ---------- 6. Allotments: every course of the semester given to every section, with its teacher ----------

UNWIND [{id: 'CSE-UG-2026-27-S5-5E1-23CS5PCOOM', section: 'CSE-UG-2026-27-S5-5E1', course: '23CS5PCOOM', teacher: 'CSE-AHV'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCDEV', section: 'CSE-UG-2026-27-S5-5E1', course: '23CS5PCDEV', teacher: 'CSE-SAN'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN', section: 'CSE-UG-2026-27-S5-5E1', course: '23CS5PCAIN', teacher: 'CSE-KRM'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCCON', section: 'CSE-UG-2026-27-S5-5E1', course: '23CS5PCCON', teacher: 'CSE-SPS'}, {id: 'CSE-UG-2026-27-S5-5E1-23CV5HSEVS', section: 'CSE-UG-2026-27-S5-5E1', course: '23CV5HSEVS', teacher: 'CSE-NSJ'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5BSBIS', section: 'CSE-UG-2026-27-S5-5E1', course: '23CS5BSBIS', teacher: 'CSE-NSJ'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5SPEXXX', section: 'CSE-UG-2026-27-S5-5E1', course: '23CS5SPEXXX', teacher: null}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5SAEXXX', section: 'CSE-UG-2026-27-S5-5E1', course: '23CS5SAEXXX', teacher: null}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5PWMIP', section: 'CSE-UG-2026-27-S5-5E1', course: '23CS5PWMIP', teacher: null}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCOOM', section: 'CSE-UG-2026-27-S5-5E2', course: '23CS5PCOOM', teacher: 'CSE-MGB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCDEV', section: 'CSE-UG-2026-27-S5-5E2', course: '23CS5PCDEV', teacher: 'CSE-VG'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN', section: 'CSE-UG-2026-27-S5-5E2', course: '23CS5PCAIN', teacher: 'CSE-KRM'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCCON', section: 'CSE-UG-2026-27-S5-5E2', course: '23CS5PCCON', teacher: 'CSE-CAV'}, {id: 'CSE-UG-2026-27-S5-5E2-23CV5HSEVS', section: 'CSE-UG-2026-27-S5-5E2', course: '23CV5HSEVS', teacher: 'CSE-LS'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5BSBIS', section: 'CSE-UG-2026-27-S5-5E2', course: '23CS5BSBIS', teacher: 'CSE-MGB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5SPEXXX', section: 'CSE-UG-2026-27-S5-5E2', course: '23CS5SPEXXX', teacher: null}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5SAEXXX', section: 'CSE-UG-2026-27-S5-5E2', course: '23CS5SAEXXX', teacher: null}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5PWMIP', section: 'CSE-UG-2026-27-S5-5E2', course: '23CS5PWMIP', teacher: null}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCOOM', section: 'CSE-UG-2026-27-S5-5E3', course: '23CS5PCOOM', teacher: 'CSE-MGB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCDEV', section: 'CSE-UG-2026-27-S5-5E3', course: '23CS5PCDEV', teacher: 'CSE-SSB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN', section: 'CSE-UG-2026-27-S5-5E3', course: '23CS5PCAIN', teacher: 'CSE-KPM'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCCON', section: 'CSE-UG-2026-27-S5-5E3', course: '23CS5PCCON', teacher: 'CSE-SPS'}, {id: 'CSE-UG-2026-27-S5-5E3-23CV5HSEVS', section: 'CSE-UG-2026-27-S5-5E3', course: '23CV5HSEVS', teacher: 'CSE-SPS'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5BSBIS', section: 'CSE-UG-2026-27-S5-5E3', course: '23CS5BSBIS', teacher: 'CSE-SPS'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5SPEXXX', section: 'CSE-UG-2026-27-S5-5E3', course: '23CS5SPEXXX', teacher: null}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5SAEXXX', section: 'CSE-UG-2026-27-S5-5E3', course: '23CS5SAEXXX', teacher: null}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5PWMIP', section: 'CSE-UG-2026-27-S5-5E3', course: '23CS5PWMIP', teacher: null}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCOOM', section: 'CSE-UG-2026-27-S5-5E4', course: '23CS5PCOOM', teacher: 'CSE-SHR'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCDEV', section: 'CSE-UG-2026-27-S5-5E4', course: '23CS5PCDEV', teacher: 'CSE-VG'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN', section: 'CSE-UG-2026-27-S5-5E4', course: '23CS5PCAIN', teacher: 'CSE-RS'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCCON', section: 'CSE-UG-2026-27-S5-5E4', course: '23CS5PCCON', teacher: 'CSE-CAV'}, {id: 'CSE-UG-2026-27-S5-5E4-23CV5HSEVS', section: 'CSE-UG-2026-27-S5-5E4', course: '23CV5HSEVS', teacher: 'CSE-SUR'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5BSBIS', section: 'CSE-UG-2026-27-S5-5E4', course: '23CS5BSBIS', teacher: 'CSE-VG'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5SPEXXX', section: 'CSE-UG-2026-27-S5-5E4', course: '23CS5SPEXXX', teacher: null}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5SAEXXX', section: 'CSE-UG-2026-27-S5-5E4', course: '23CS5SAEXXX', teacher: null}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5PWMIP', section: 'CSE-UG-2026-27-S5-5E4', course: '23CS5PWMIP', teacher: null}] AS x
MATCH (sec:Section {id: x.section}), (c:Course {code: x.course})
MERGE (a:Allotment {id: x.id})
MERGE (sec)-[:HAS_ALLOTMENT]->(a)
MERGE (a)-[:OF_COURSE]->(c)
WITH a, x
OPTIONAL MATCH (f:Faculty {id: x.teacher})
FOREACH (_ IN CASE WHEN f IS NULL THEN [] ELSE [1] END |
  MERGE (f)-[r:TEACHES]->(a)
    SET r.role = 'COURSE_TEACHER');


// ---------- 7. Lab batches and the faculty of each batch ----------

UNWIND [{id: 'CSE-UG-2026-27-S5-5E1-23CS5PCOOM-B1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCOOM', name: 'B1', faculty: 'CSE-AHV', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCOOM-B2', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCOOM', name: 'B2', faculty: 'CSE-SAH', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCOOM-B3', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCOOM', name: 'B3', faculty: 'CSE-MGB', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCOOM-B4', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCOOM', name: 'B4', faculty: 'CSE-LS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN-B1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN', name: 'B1', faculty: 'CSE-KRM', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN-B2', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN', name: 'B2', faculty: 'CSE-NNM', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN-B3', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN', name: 'B3', faculty: 'CSE-NNM', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN-B4', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN', name: 'B4', faculty: 'CSE-LS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCCON-B1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCCON', name: 'B1', faculty: 'CSE-SPS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCCON-B2', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCCON', name: 'B2', faculty: 'CSE-MHM', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCCON-B3', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCCON', name: 'B3', faculty: 'CSE-AHV', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCCON-B4', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCCON', name: 'B4', faculty: 'CSE-AHV', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5BSBIS-B1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5BSBIS', name: 'B1', faculty: 'CSE-NSJ', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5BSBIS-B2', allot: 'CSE-UG-2026-27-S5-5E1-23CS5BSBIS', name: 'B2', faculty: 'CSE-AB', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5BSBIS-B3', allot: 'CSE-UG-2026-27-S5-5E1-23CS5BSBIS', name: 'B3', faculty: 'CSE-VG', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5BSBIS-B4', allot: 'CSE-UG-2026-27-S5-5E1-23CS5BSBIS', name: 'B4', faculty: 'CSE-CAV', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5SAEXXX-B1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5SAEXXX', name: 'B1', faculty: 'CSE-AAS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E1-23CS5SAEXXX-B2', allot: 'CSE-UG-2026-27-S5-5E1-23CS5SAEXXX', name: 'B2', faculty: 'CSE-MGB', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCOOM-B1', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCOOM', name: 'B1', faculty: 'CSE-MGB', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCOOM-B2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCOOM', name: 'B2', faculty: 'CSE-LS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCOOM-B3', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCOOM', name: 'B3', faculty: 'CSE-SAH', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCOOM-B4', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCOOM', name: 'B4', faculty: 'CSE-AAS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN-B1', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN', name: 'B1', faculty: 'CSE-KRM', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN-B2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN', name: 'B2', faculty: 'CSE-SAN', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN-B3', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN', name: 'B3', faculty: 'CSE-SUR', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN-B4', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN', name: 'B4', faculty: 'CSE-BRH', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCCON-B1', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCCON', name: 'B1', faculty: 'CSE-CAV', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCCON-B2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCCON', name: 'B2', faculty: 'CSE-BRH', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCCON-B3', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCCON', name: 'B3', faculty: 'CSE-NNM', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCCON-B4', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCCON', name: 'B4', faculty: 'CSE-STS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5BSBIS-B1', allot: 'CSE-UG-2026-27-S5-5E2-23CS5BSBIS', name: 'B1', faculty: 'CSE-MGB', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5BSBIS-B2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5BSBIS', name: 'B2', faculty: 'CSE-SSB', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5BSBIS-B3', allot: 'CSE-UG-2026-27-S5-5E2-23CS5BSBIS', name: 'B3', faculty: 'CSE-SRN', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5BSBIS-B4', allot: 'CSE-UG-2026-27-S5-5E2-23CS5BSBIS', name: 'B4', faculty: 'CSE-CAV', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5SAEXXX-B1', allot: 'CSE-UG-2026-27-S5-5E2-23CS5SAEXXX', name: 'B1', faculty: 'CSE-CAV', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E2-23CS5SAEXXX-B2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5SAEXXX', name: 'B2', faculty: 'CSE-BVK', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCOOM-B1', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCOOM', name: 'B1', faculty: 'CSE-MGB', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCOOM-B2', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCOOM', name: 'B2', faculty: 'CSE-SAH', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCOOM-B3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCOOM', name: 'B3', faculty: 'CSE-LS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCOOM-B4', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCOOM', name: 'B4', faculty: 'CSE-AAS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN-B1', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN', name: 'B1', faculty: 'CSE-SAN', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN-B2', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN', name: 'B2', faculty: 'CSE-SAH', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN-B3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN', name: 'B3', faculty: 'CSE-SAH', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN-B4', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN', name: 'B4', faculty: 'CSE-NNM', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCCON-B1', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCCON', name: 'B1', faculty: 'CSE-SPS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCCON-B2', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCCON', name: 'B2', faculty: 'CSE-STS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCCON-B3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCCON', name: 'B3', faculty: 'CSE-BRH', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCCON-B4', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCCON', name: 'B4', faculty: 'CSE-AHV', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5BSBIS-B1', allot: 'CSE-UG-2026-27-S5-5E3-23CS5BSBIS', name: 'B1', faculty: 'CSE-SPS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5BSBIS-B2', allot: 'CSE-UG-2026-27-S5-5E3-23CS5BSBIS', name: 'B2', faculty: 'CSE-AK', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5BSBIS-B3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5BSBIS', name: 'B3', faculty: 'CSE-SSB', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5BSBIS-B4', allot: 'CSE-UG-2026-27-S5-5E3-23CS5BSBIS', name: 'B4', faculty: 'CSE-AB', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5SAEXXX-B1', allot: 'CSE-UG-2026-27-S5-5E3-23CS5SAEXXX', name: 'B1', faculty: 'CSE-SSB', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E3-23CS5SAEXXX-B2', allot: 'CSE-UG-2026-27-S5-5E3-23CS5SAEXXX', name: 'B2', faculty: 'CSE-AK', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCOOM-B1', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCOOM', name: 'B1', faculty: 'CSE-SHR', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCOOM-B2', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCOOM', name: 'B2', faculty: 'CSE-CSP', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCOOM-B3', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCOOM', name: 'B3', faculty: 'CSE-AAS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCOOM-B4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCOOM', name: 'B4', faculty: 'CSE-LS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN-B1', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN', name: 'B1', faculty: 'CSE-RS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN-B2', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN', name: 'B2', faculty: 'CSE-NNM', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN-B3', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN', name: 'B3', faculty: 'CSE-SMR', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN-B4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN', name: 'B4', faculty: 'CSE-VG', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCCON-B1', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCCON', name: 'B1', faculty: 'CSE-CAV', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCCON-B2', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCCON', name: 'B2', faculty: 'CSE-SMR', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCCON-B3', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCCON', name: 'B3', faculty: 'CSE-MGB', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCCON-B4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCCON', name: 'B4', faculty: 'CSE-STS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5BSBIS-B1', allot: 'CSE-UG-2026-27-S5-5E4-23CS5BSBIS', name: 'B1', faculty: 'CSE-VG', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5BSBIS-B2', allot: 'CSE-UG-2026-27-S5-5E4-23CS5BSBIS', name: 'B2', faculty: 'CSE-NSJ', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5BSBIS-B3', allot: 'CSE-UG-2026-27-S5-5E4-23CS5BSBIS', name: 'B3', faculty: 'CSE-CAV', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5BSBIS-B4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5BSBIS', name: 'B4', faculty: 'CSE-CAV', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5SAEXXX-B1', allot: 'CSE-UG-2026-27-S5-5E4-23CS5SAEXXX', name: 'B1', faculty: 'CSE-SS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S5-5E4-23CS5SAEXXX-B2', allot: 'CSE-UG-2026-27-S5-5E4-23CS5SAEXXX', name: 'B2', faculty: 'CSE-SSB', type: 'LAB'}] AS x
MATCH (a:Allotment {id: x.allot}), (f:Faculty {id: x.faculty})
MERGE (b:Batch {id: x.id})
  SET b.name = x.name, b.type = x.type
MERGE (a)-[:HAS_BATCH]->(b)
MERGE (b)-[:ASSIGNED_TO]->(f);


// ---------- 8. Classes: lectures, tutorials, labs, elective slots and activities ----------
// type: L lecture, T tutorial, P lab, A activity. Periods are of time grid A.
// A lab is taken by every batch with its own faculty.


// 5E1 [5A] - 20 sessions

UNWIND [
  {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCCON-P-MON-P4', name: 'CN Lab', section: 'CSE-UG-2026-27-S5-5E1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCCON', type: 'P', slots: ['MON-P4', 'MON-P5'], rooms: ['OTHER-ISE-SH'], faculty: ['CSE-SPS', 'CSE-MHM', 'CSE-AHV'], batches: ['CSE-UG-2026-27-S5-5E1-23CS5PCCON-B1', 'CSE-UG-2026-27-S5-5E1-23CS5PCCON-B2', 'CSE-UG-2026-27-S5-5E1-23CS5PCCON-B3', 'CSE-UG-2026-27-S5-5E1-23CS5PCCON-B4']},
  {id: 'CSE-UG-2026-27-S5-5E1-23CS5SPEXXX-L-MON-P6', name: 'PE', section: 'CSE-UG-2026-27-S5-5E1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5SPEXXX', type: 'L', slots: ['MON-P6'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCCON-L-MON-P7', name: 'CN', section: 'CSE-UG-2026-27-S5-5E1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCCON', type: 'L', slots: ['MON-P7'], rooms: ['PJ-408'], faculty: ['CSE-SPS'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E1-23CS5SPEXXX-L-TUE-P4', name: 'PE', section: 'CSE-UG-2026-27-S5-5E1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5SPEXXX', type: 'L', slots: ['TUE-P4'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN-L-TUE-P5', name: 'AI', section: 'CSE-UG-2026-27-S5-5E1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN', type: 'L', slots: ['TUE-P5'], rooms: ['PJ-406'], faculty: ['CSE-KRM'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCDEV-L-TUE-P6', name: 'DEV', section: 'CSE-UG-2026-27-S5-5E1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCDEV', type: 'L', slots: ['TUE-P6'], rooms: ['PJ-406'], faculty: ['CSE-SAN'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCOOM-P-TUE-P7', name: 'OOM Lab', section: 'CSE-UG-2026-27-S5-5E1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCOOM', type: 'P', slots: ['TUE-P7', 'TUE-P8'], rooms: ['PJ-LAB401'], faculty: ['CSE-AHV', 'CSE-SAH', 'CSE-MGB', 'CSE-LS'], batches: ['CSE-UG-2026-27-S5-5E1-23CS5PCOOM-B1', 'CSE-UG-2026-27-S5-5E1-23CS5PCOOM-B2', 'CSE-UG-2026-27-S5-5E1-23CS5PCOOM-B3', 'CSE-UG-2026-27-S5-5E1-23CS5PCOOM-B4']},
  {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCCON-L-WED-P4', name: 'CN', section: 'CSE-UG-2026-27-S5-5E1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCCON', type: 'L', slots: ['WED-P4'], rooms: ['PJ-406'], faculty: ['CSE-SPS'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E1-A-WED-P5', name: 'Seminar / Workshop / Proctor Meet', section: 'CSE-UG-2026-27-S5-5E1', allot: null, type: 'A', slots: ['WED-P5'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCOOM-L-WED-P6', name: 'OOM', section: 'CSE-UG-2026-27-S5-5E1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCOOM', type: 'L', slots: ['WED-P6'], rooms: ['PJ-406'], faculty: ['CSE-AHV'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCDEV-T-WED-P7', name: 'DEV Tutorial', section: 'CSE-UG-2026-27-S5-5E1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCDEV', type: 'T', slots: ['WED-P7', 'WED-P8'], rooms: ['PJ-407'], faculty: ['CSE-SAN'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E1-23CS5SPEXXX-L-THU-P4', name: 'PE', section: 'CSE-UG-2026-27-S5-5E1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5SPEXXX', type: 'L', slots: ['THU-P4'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCDEV-L-THU-P5', name: 'DEV', section: 'CSE-UG-2026-27-S5-5E1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCDEV', type: 'L', slots: ['THU-P5'], rooms: ['PJ-408'], faculty: ['CSE-SAN'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN-L-THU-P6', name: 'AI', section: 'CSE-UG-2026-27-S5-5E1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN', type: 'L', slots: ['THU-P6'], rooms: ['PJ-408'], faculty: ['CSE-KRM'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN-P-THU-P7', name: 'AI Lab', section: 'CSE-UG-2026-27-S5-5E1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN', type: 'P', slots: ['THU-P7', 'THU-P8'], rooms: ['PJ-LAB503', 'PJ-LAB504'], faculty: ['CSE-KRM', 'CSE-NNM', 'CSE-LS'], batches: ['CSE-UG-2026-27-S5-5E1-23CS5PCAIN-B1', 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN-B2', 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN-B3', 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN-B4']},
  {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCOOM-L-FRI-P5', name: 'OOM', section: 'CSE-UG-2026-27-S5-5E1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCOOM', type: 'L', slots: ['FRI-P5'], rooms: ['PJ-407'], faculty: ['CSE-AHV'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN-L-FRI-P6', name: 'AI', section: 'CSE-UG-2026-27-S5-5E1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCAIN', type: 'L', slots: ['FRI-P6'], rooms: ['PJ-407'], faculty: ['CSE-KRM'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E1-23CS5SAEXXX-P-FRI-P7', name: 'CC Lab', section: 'CSE-UG-2026-27-S5-5E1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5SAEXXX', type: 'P', slots: ['FRI-P7', 'FRI-P8'], rooms: ['PJ-LAB401'], faculty: ['CSE-AAS', 'CSE-MGB'], batches: ['CSE-UG-2026-27-S5-5E1-23CS5SAEXXX-B1', 'CSE-UG-2026-27-S5-5E1-23CS5SAEXXX-B2']},
  {id: 'CSE-UG-2026-27-S5-5E1-23CS5PCCON-L-SAT-P3', name: 'CN', section: 'CSE-UG-2026-27-S5-5E1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5PCCON', type: 'L', slots: ['SAT-P3'], rooms: ['PJ-407'], faculty: ['CSE-SPS'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E1-23CS5BSBIS-P-SAT-P4', name: 'BIS Lab', section: 'CSE-UG-2026-27-S5-5E1', allot: 'CSE-UG-2026-27-S5-5E1-23CS5BSBIS', type: 'P', slots: ['SAT-P4', 'SAT-P5'], rooms: ['PJ-LAB401'], faculty: ['CSE-NSJ', 'CSE-AB', 'CSE-VG', 'CSE-CAV'], batches: ['CSE-UG-2026-27-S5-5E1-23CS5BSBIS-B1', 'CSE-UG-2026-27-S5-5E1-23CS5BSBIS-B2', 'CSE-UG-2026-27-S5-5E1-23CS5BSBIS-B3', 'CSE-UG-2026-27-S5-5E1-23CS5BSBIS-B4']}
] AS x
MATCH (sec:Section {id: x.section}), (lt:LTP {code: x.type})
MERGE (cl:Class {id: x.id})
  SET cl.name = x.name
MERGE (cl)-[:OF_TYPE]->(lt)
MERGE (cl)-[:FOR_SECTION]->(sec)
WITH x, cl
OPTIONAL MATCH (a:Allotment {id: x.allot})
FOREACH (_ IN CASE WHEN a IS NULL THEN [] ELSE [1] END | MERGE (a)-[:HAS_CLASS]->(cl))
WITH x, cl
CALL (x, cl) { UNWIND x.slots AS s MATCH (t:TimeSlot {id: s}) MERGE (cl)-[:AT_TIME]->(t) }
CALL (x, cl) { UNWIND x.rooms AS r MATCH (rm:Room {id: r}) MERGE (cl)-[:IN_ROOM]->(rm) }
CALL (x, cl) { UNWIND x.faculty AS f MATCH (fa:Faculty {id: f}) MERGE (cl)-[:TAUGHT_BY]->(fa) }
CALL (x, cl) { UNWIND x.batches AS b MATCH (bt:Batch {id: b}) MERGE (cl)-[:FOR_BATCH]->(bt) };


// 5E2 [5J] - 20 sessions

UNWIND [
  {id: 'CSE-UG-2026-27-S5-5E2-23CS5BSBIS-P-MON-P4', name: 'BIS Lab', section: 'CSE-UG-2026-27-S5-5E2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5BSBIS', type: 'P', slots: ['MON-P4', 'MON-P5'], rooms: ['OTHER-BSN-PG-LAB'], faculty: ['CSE-MGB', 'CSE-SSB', 'CSE-SRN', 'CSE-CAV'], batches: ['CSE-UG-2026-27-S5-5E2-23CS5BSBIS-B1', 'CSE-UG-2026-27-S5-5E2-23CS5BSBIS-B2', 'CSE-UG-2026-27-S5-5E2-23CS5BSBIS-B3', 'CSE-UG-2026-27-S5-5E2-23CS5BSBIS-B4']},
  {id: 'CSE-UG-2026-27-S5-5E2-23CS5SPEXXX-L-MON-P6', name: 'PE', section: 'CSE-UG-2026-27-S5-5E2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5SPEXXX', type: 'L', slots: ['MON-P6'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCDEV-T-MON-P7', name: 'DEV Tutorial', section: 'CSE-UG-2026-27-S5-5E2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCDEV', type: 'T', slots: ['MON-P7', 'MON-P8'], rooms: ['PJ-406'], faculty: ['CSE-VG'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E2-23CS5SPEXXX-L-TUE-P4', name: 'PE', section: 'CSE-UG-2026-27-S5-5E2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5SPEXXX', type: 'L', slots: ['TUE-P4'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCDEV-L-TUE-P5', name: 'DEV', section: 'CSE-UG-2026-27-S5-5E2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCDEV', type: 'L', slots: ['TUE-P5'], rooms: ['PJ-408'], faculty: ['CSE-VG'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E2-A-TUE-P6', name: 'Seminar / Workshop / Proctor Meet', section: 'CSE-UG-2026-27-S5-5E2', allot: null, type: 'A', slots: ['TUE-P6'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN-L-TUE-P7', name: 'AI', section: 'CSE-UG-2026-27-S5-5E2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN', type: 'L', slots: ['TUE-P7'], rooms: ['PJ-406'], faculty: ['CSE-KRM'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCCON-L-TUE-P8', name: 'CN', section: 'CSE-UG-2026-27-S5-5E2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCCON', type: 'L', slots: ['TUE-P8'], rooms: ['PJ-406'], faculty: ['CSE-CAV'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN-P-WED-P5', name: 'AI Lab', section: 'CSE-UG-2026-27-S5-5E2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN', type: 'P', slots: ['WED-P5', 'WED-P6'], rooms: ['PJ-4F-LAB1'], faculty: ['CSE-KRM', 'CSE-SAN', 'CSE-SUR', 'CSE-BRH'], batches: ['CSE-UG-2026-27-S5-5E2-23CS5PCAIN-B1', 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN-B2', 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN-B3', 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN-B4']},
  {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCCON-L-WED-P7', name: 'CN', section: 'CSE-UG-2026-27-S5-5E2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCCON', type: 'L', slots: ['WED-P7'], rooms: ['PJ-406'], faculty: ['CSE-CAV'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E2-23CS5SPEXXX-L-THU-P4', name: 'PE', section: 'CSE-UG-2026-27-S5-5E2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5SPEXXX', type: 'L', slots: ['THU-P4'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCOOM-P-THU-P5', name: 'OOM Lab', section: 'CSE-UG-2026-27-S5-5E2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCOOM', type: 'P', slots: ['THU-P5', 'THU-P6'], rooms: ['PJ-4F-LAB1'], faculty: ['CSE-MGB', 'CSE-LS', 'CSE-SAH', 'CSE-AAS'], batches: ['CSE-UG-2026-27-S5-5E2-23CS5PCOOM-B1', 'CSE-UG-2026-27-S5-5E2-23CS5PCOOM-B2', 'CSE-UG-2026-27-S5-5E2-23CS5PCOOM-B3', 'CSE-UG-2026-27-S5-5E2-23CS5PCOOM-B4']},
  {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCOOM-L-THU-P7', name: 'OOM', section: 'CSE-UG-2026-27-S5-5E2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCOOM', type: 'L', slots: ['THU-P7'], rooms: ['PJ-407'], faculty: ['CSE-MGB'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN-L-FRI-P4', name: 'AI', section: 'CSE-UG-2026-27-S5-5E2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN', type: 'L', slots: ['FRI-P4'], rooms: ['PJ-220'], faculty: ['CSE-KRM'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCCON-L-FRI-P5', name: 'CN', section: 'CSE-UG-2026-27-S5-5E2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCCON', type: 'L', slots: ['FRI-P5'], rooms: ['PJ-220'], faculty: ['CSE-CAV'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCDEV-L-FRI-P6', name: 'DEV', section: 'CSE-UG-2026-27-S5-5E2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCDEV', type: 'L', slots: ['FRI-P6'], rooms: ['PJ-220'], faculty: ['CSE-VG'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E2-23CS5SAEXXX-P-FRI-P7', name: 'CC Lab', section: 'CSE-UG-2026-27-S5-5E2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5SAEXXX', type: 'P', slots: ['FRI-P7', 'FRI-P8'], rooms: ['PJ-4F-LAB1'], faculty: ['CSE-CAV', 'CSE-BVK'], batches: ['CSE-UG-2026-27-S5-5E2-23CS5SAEXXX-B1', 'CSE-UG-2026-27-S5-5E2-23CS5SAEXXX-B2']},
  {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCCON-P-SAT-P2', name: 'CN Lab', section: 'CSE-UG-2026-27-S5-5E2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCCON', type: 'P', slots: ['SAT-P2', 'SAT-P3'], rooms: ['OTHER-BSN-PG-LAB'], faculty: ['CSE-CAV', 'CSE-BRH', 'CSE-NNM', 'CSE-STS'], batches: ['CSE-UG-2026-27-S5-5E2-23CS5PCCON-B1', 'CSE-UG-2026-27-S5-5E2-23CS5PCCON-B2', 'CSE-UG-2026-27-S5-5E2-23CS5PCCON-B3', 'CSE-UG-2026-27-S5-5E2-23CS5PCCON-B4']},
  {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCOOM-L-SAT-P4', name: 'OOM', section: 'CSE-UG-2026-27-S5-5E2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCOOM', type: 'L', slots: ['SAT-P4'], rooms: ['PJ-220'], faculty: ['CSE-MGB'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN-L-SAT-P5', name: 'AI', section: 'CSE-UG-2026-27-S5-5E2', allot: 'CSE-UG-2026-27-S5-5E2-23CS5PCAIN', type: 'L', slots: ['SAT-P5'], rooms: ['PJ-220'], faculty: ['CSE-KRM'], batches: []}
] AS x
MATCH (sec:Section {id: x.section}), (lt:LTP {code: x.type})
MERGE (cl:Class {id: x.id})
  SET cl.name = x.name
MERGE (cl)-[:OF_TYPE]->(lt)
MERGE (cl)-[:FOR_SECTION]->(sec)
WITH x, cl
OPTIONAL MATCH (a:Allotment {id: x.allot})
FOREACH (_ IN CASE WHEN a IS NULL THEN [] ELSE [1] END | MERGE (a)-[:HAS_CLASS]->(cl))
WITH x, cl
CALL (x, cl) { UNWIND x.slots AS s MATCH (t:TimeSlot {id: s}) MERGE (cl)-[:AT_TIME]->(t) }
CALL (x, cl) { UNWIND x.rooms AS r MATCH (rm:Room {id: r}) MERGE (cl)-[:IN_ROOM]->(rm) }
CALL (x, cl) { UNWIND x.faculty AS f MATCH (fa:Faculty {id: f}) MERGE (cl)-[:TAUGHT_BY]->(fa) }
CALL (x, cl) { UNWIND x.batches AS b MATCH (bt:Batch {id: b}) MERGE (cl)-[:FOR_BATCH]->(bt) };


// 5E3 [5K] - 20 sessions

UNWIND [
  {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN-L-MON-P5', name: 'AI', section: 'CSE-UG-2026-27-S5-5E3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN', type: 'L', slots: ['MON-P5'], rooms: ['PJ-407'], faculty: ['CSE-KPM'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E3-23CS5SPEXXX-L-MON-P6', name: 'PE', section: 'CSE-UG-2026-27-S5-5E3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5SPEXXX', type: 'L', slots: ['MON-P6'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E3-23CS5SAEXXX-P-MON-P7', name: 'CC Lab', section: 'CSE-UG-2026-27-S5-5E3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5SAEXXX', type: 'P', slots: ['MON-P7', 'MON-P8'], rooms: ['PJ-LAB401'], faculty: ['CSE-SSB', 'CSE-AK'], batches: ['CSE-UG-2026-27-S5-5E3-23CS5SAEXXX-B1', 'CSE-UG-2026-27-S5-5E3-23CS5SAEXXX-B2']},
  {id: 'CSE-UG-2026-27-S5-5E3-23CS5SPEXXX-L-TUE-P4', name: 'PE', section: 'CSE-UG-2026-27-S5-5E3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5SPEXXX', type: 'L', slots: ['TUE-P4'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCOOM-L-TUE-P5', name: 'OOM', section: 'CSE-UG-2026-27-S5-5E3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCOOM', type: 'L', slots: ['TUE-P5'], rooms: ['PJ-220'], faculty: ['CSE-MGB'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN-L-TUE-P6', name: 'AI', section: 'CSE-UG-2026-27-S5-5E3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN', type: 'L', slots: ['TUE-P6'], rooms: ['PJ-220'], faculty: ['CSE-KPM'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCDEV-T-TUE-P7', name: 'DEV Tutorial', section: 'CSE-UG-2026-27-S5-5E3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCDEV', type: 'T', slots: ['TUE-P7', 'TUE-P8'], rooms: ['PJ-407'], faculty: ['CSE-SSB'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E3-A-WED-P4', name: 'Seminar / Workshop / Proctor Meet', section: 'CSE-UG-2026-27-S5-5E3', allot: null, type: 'A', slots: ['WED-P4'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E3-23CS5BSBIS-P-WED-P5', name: 'BIS Lab', section: 'CSE-UG-2026-27-S5-5E3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5BSBIS', type: 'P', slots: ['WED-P5', 'WED-P6'], rooms: ['PJ-LAB401'], faculty: ['CSE-SPS', 'CSE-AK', 'CSE-SSB', 'CSE-AB'], batches: ['CSE-UG-2026-27-S5-5E3-23CS5BSBIS-B1', 'CSE-UG-2026-27-S5-5E3-23CS5BSBIS-B2', 'CSE-UG-2026-27-S5-5E3-23CS5BSBIS-B3', 'CSE-UG-2026-27-S5-5E3-23CS5BSBIS-B4']},
  {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCCON-L-WED-P7', name: 'CN', section: 'CSE-UG-2026-27-S5-5E3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCCON', type: 'L', slots: ['WED-P7'], rooms: ['PJ-408'], faculty: ['CSE-SPS'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E3-23CS5SPEXXX-L-THU-P4', name: 'PE', section: 'CSE-UG-2026-27-S5-5E3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5SPEXXX', type: 'L', slots: ['THU-P4'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCCON-P-THU-P5', name: 'CN Lab', section: 'CSE-UG-2026-27-S5-5E3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCCON', type: 'P', slots: ['THU-P5', 'THU-P6'], rooms: ['PJ-4F-LAB1-2'], faculty: ['CSE-SPS', 'CSE-STS', 'CSE-BRH', 'CSE-AHV'], batches: ['CSE-UG-2026-27-S5-5E3-23CS5PCCON-B1', 'CSE-UG-2026-27-S5-5E3-23CS5PCCON-B2', 'CSE-UG-2026-27-S5-5E3-23CS5PCCON-B3', 'CSE-UG-2026-27-S5-5E3-23CS5PCCON-B4']},
  {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN-L-THU-P7', name: 'AI', section: 'CSE-UG-2026-27-S5-5E3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN', type: 'L', slots: ['THU-P7'], rooms: ['PJ-408'], faculty: ['CSE-KPM'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCOOM-L-FRI-P4', name: 'OOM', section: 'CSE-UG-2026-27-S5-5E3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCOOM', type: 'L', slots: ['FRI-P4'], rooms: ['PJ-408'], faculty: ['CSE-MGB'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCDEV-L-FRI-P5', name: 'DEV', section: 'CSE-UG-2026-27-S5-5E3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCDEV', type: 'L', slots: ['FRI-P5'], rooms: ['PJ-408'], faculty: ['CSE-SSB'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCCON-L-FRI-P6', name: 'CN', section: 'CSE-UG-2026-27-S5-5E3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCCON', type: 'L', slots: ['FRI-P6'], rooms: ['PJ-408'], faculty: ['CSE-SPS'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN-P-FRI-P7', name: 'AI Lab', section: 'CSE-UG-2026-27-S5-5E3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN', type: 'P', slots: ['FRI-P7', 'FRI-P8'], rooms: ['PJ-4F-LAB1-2'], faculty: ['CSE-SAN', 'CSE-SAH', 'CSE-NNM'], batches: ['CSE-UG-2026-27-S5-5E3-23CS5PCAIN-B1', 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN-B2', 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN-B3', 'CSE-UG-2026-27-S5-5E3-23CS5PCAIN-B4']},
  {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCOOM-P-SAT-P2', name: 'OOM Lab', section: 'CSE-UG-2026-27-S5-5E3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCOOM', type: 'P', slots: ['SAT-P2', 'SAT-P3'], rooms: ['PJ-4F-LAB1'], faculty: ['CSE-MGB', 'CSE-SAH', 'CSE-LS', 'CSE-AAS'], batches: ['CSE-UG-2026-27-S5-5E3-23CS5PCOOM-B1', 'CSE-UG-2026-27-S5-5E3-23CS5PCOOM-B2', 'CSE-UG-2026-27-S5-5E3-23CS5PCOOM-B3', 'CSE-UG-2026-27-S5-5E3-23CS5PCOOM-B4']},
  {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCCON-L-SAT-P4', name: 'CN', section: 'CSE-UG-2026-27-S5-5E3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCCON', type: 'L', slots: ['SAT-P4'], rooms: ['PJ-406'], faculty: ['CSE-SPS'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E3-23CS5PCDEV-L-SAT-P5', name: 'DEV', section: 'CSE-UG-2026-27-S5-5E3', allot: 'CSE-UG-2026-27-S5-5E3-23CS5PCDEV', type: 'L', slots: ['SAT-P5'], rooms: ['PJ-406'], faculty: ['CSE-SSB'], batches: []}
] AS x
MATCH (sec:Section {id: x.section}), (lt:LTP {code: x.type})
MERGE (cl:Class {id: x.id})
  SET cl.name = x.name
MERGE (cl)-[:OF_TYPE]->(lt)
MERGE (cl)-[:FOR_SECTION]->(sec)
WITH x, cl
OPTIONAL MATCH (a:Allotment {id: x.allot})
FOREACH (_ IN CASE WHEN a IS NULL THEN [] ELSE [1] END | MERGE (a)-[:HAS_CLASS]->(cl))
WITH x, cl
CALL (x, cl) { UNWIND x.slots AS s MATCH (t:TimeSlot {id: s}) MERGE (cl)-[:AT_TIME]->(t) }
CALL (x, cl) { UNWIND x.rooms AS r MATCH (rm:Room {id: r}) MERGE (cl)-[:IN_ROOM]->(rm) }
CALL (x, cl) { UNWIND x.faculty AS f MATCH (fa:Faculty {id: f}) MERGE (cl)-[:TAUGHT_BY]->(fa) }
CALL (x, cl) { UNWIND x.batches AS b MATCH (bt:Batch {id: b}) MERGE (cl)-[:FOR_BATCH]->(bt) };


// 5E4 [5T] - 20 sessions

UNWIND [
  {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCDEV-L-MON-P4', name: 'DEV', section: 'CSE-UG-2026-27-S5-5E4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCDEV', type: 'L', slots: ['MON-P4'], rooms: ['PJ-406'], faculty: ['CSE-VG'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN-L-MON-P5', name: 'AI', section: 'CSE-UG-2026-27-S5-5E4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN', type: 'L', slots: ['MON-P5'], rooms: ['PJ-406'], faculty: ['CSE-RS'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E4-23CS5SPEXXX-L-MON-P6', name: 'PE', section: 'CSE-UG-2026-27-S5-5E4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5SPEXXX', type: 'L', slots: ['MON-P6'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCCON-P-MON-P7', name: 'CN Lab', section: 'CSE-UG-2026-27-S5-5E4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCCON', type: 'P', slots: ['MON-P7', 'MON-P8'], rooms: ['PJ-4F-LAB1'], faculty: ['CSE-CAV', 'CSE-SMR', 'CSE-MGB', 'CSE-STS'], batches: ['CSE-UG-2026-27-S5-5E4-23CS5PCCON-B1', 'CSE-UG-2026-27-S5-5E4-23CS5PCCON-B2', 'CSE-UG-2026-27-S5-5E4-23CS5PCCON-B3', 'CSE-UG-2026-27-S5-5E4-23CS5PCCON-B4']},
  {id: 'CSE-UG-2026-27-S5-5E4-23CS5SPEXXX-L-TUE-P4', name: 'PE', section: 'CSE-UG-2026-27-S5-5E4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5SPEXXX', type: 'L', slots: ['TUE-P4'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN-L-TUE-P5', name: 'AI', section: 'CSE-UG-2026-27-S5-5E4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN', type: 'L', slots: ['TUE-P5'], rooms: ['PJ-407'], faculty: ['CSE-RS'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCCON-L-TUE-P6', name: 'CN', section: 'CSE-UG-2026-27-S5-5E4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCCON', type: 'L', slots: ['TUE-P6'], rooms: ['PJ-407'], faculty: ['CSE-CAV'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN-P-TUE-P7', name: 'AI Lab', section: 'CSE-UG-2026-27-S5-5E4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN', type: 'P', slots: ['TUE-P7', 'TUE-P8'], rooms: ['PJ-4F-LAB1'], faculty: ['CSE-RS', 'CSE-NNM', 'CSE-SMR', 'CSE-VG'], batches: ['CSE-UG-2026-27-S5-5E4-23CS5PCAIN-B1', 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN-B2', 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN-B3', 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN-B4']},
  {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN-L-WED-P4', name: 'AI', section: 'CSE-UG-2026-27-S5-5E4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCAIN', type: 'L', slots: ['WED-P4'], rooms: ['PJ-407'], faculty: ['CSE-RS'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCCON-L-WED-P5', name: 'CN', section: 'CSE-UG-2026-27-S5-5E4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCCON', type: 'L', slots: ['WED-P5'], rooms: ['PJ-407'], faculty: ['CSE-CAV'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCOOM-L-WED-P6', name: 'OOM', section: 'CSE-UG-2026-27-S5-5E4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCOOM', type: 'L', slots: ['WED-P6'], rooms: ['PJ-407'], faculty: ['CSE-SHR'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E4-23CS5SAEXXX-P-WED-P7', name: 'CC Lab', section: 'CSE-UG-2026-27-S5-5E4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5SAEXXX', type: 'P', slots: ['WED-P7', 'WED-P8'], rooms: ['PJ-LAB401'], faculty: ['CSE-SS', 'CSE-SSB'], batches: ['CSE-UG-2026-27-S5-5E4-23CS5SAEXXX-B1', 'CSE-UG-2026-27-S5-5E4-23CS5SAEXXX-B2']},
  {id: 'CSE-UG-2026-27-S5-5E4-23CS5SPEXXX-L-THU-P4', name: 'PE', section: 'CSE-UG-2026-27-S5-5E4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5SPEXXX', type: 'L', slots: ['THU-P4'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCCON-L-THU-P5', name: 'CN', section: 'CSE-UG-2026-27-S5-5E4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCCON', type: 'L', slots: ['THU-P5'], rooms: ['PJ-406'], faculty: ['CSE-CAV'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCDEV-L-THU-P6', name: 'DEV', section: 'CSE-UG-2026-27-S5-5E4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCDEV', type: 'L', slots: ['THU-P6'], rooms: ['PJ-406'], faculty: ['CSE-VG'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E4-23CS5BSBIS-P-THU-P7', name: 'BIS Lab', section: 'CSE-UG-2026-27-S5-5E4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5BSBIS', type: 'P', slots: ['THU-P7', 'THU-P8'], rooms: ['PJ-4F-LAB1'], faculty: ['CSE-VG', 'CSE-NSJ', 'CSE-CAV'], batches: ['CSE-UG-2026-27-S5-5E4-23CS5BSBIS-B1', 'CSE-UG-2026-27-S5-5E4-23CS5BSBIS-B2', 'CSE-UG-2026-27-S5-5E4-23CS5BSBIS-B3', 'CSE-UG-2026-27-S5-5E4-23CS5BSBIS-B4']},
  {id: 'CSE-UG-2026-27-S5-5E4-A-FRI-P3', name: 'Seminar / Workshop / Proctor Meet', section: 'CSE-UG-2026-27-S5-5E4', allot: null, type: 'A', slots: ['FRI-P3'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCOOM-L-FRI-P4', name: 'OOM', section: 'CSE-UG-2026-27-S5-5E4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCOOM', type: 'L', slots: ['FRI-P4'], rooms: ['PJ-206'], faculty: ['CSE-SHR'], batches: []},
  {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCOOM-P-FRI-P5', name: 'OOM Lab', section: 'CSE-UG-2026-27-S5-5E4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCOOM', type: 'P', slots: ['FRI-P5', 'FRI-P6'], rooms: ['PJ-LAB401'], faculty: ['CSE-SHR', 'CSE-CSP', 'CSE-AAS', 'CSE-LS'], batches: ['CSE-UG-2026-27-S5-5E4-23CS5PCOOM-B1', 'CSE-UG-2026-27-S5-5E4-23CS5PCOOM-B2', 'CSE-UG-2026-27-S5-5E4-23CS5PCOOM-B3', 'CSE-UG-2026-27-S5-5E4-23CS5PCOOM-B4']},
  {id: 'CSE-UG-2026-27-S5-5E4-23CS5PCDEV-T-FRI-P7', name: 'DEV Tutorial', section: 'CSE-UG-2026-27-S5-5E4', allot: 'CSE-UG-2026-27-S5-5E4-23CS5PCDEV', type: 'T', slots: ['FRI-P7', 'FRI-P8'], rooms: ['PJ-220'], faculty: ['CSE-VG'], batches: []}
] AS x
MATCH (sec:Section {id: x.section}), (lt:LTP {code: x.type})
MERGE (cl:Class {id: x.id})
  SET cl.name = x.name
MERGE (cl)-[:OF_TYPE]->(lt)
MERGE (cl)-[:FOR_SECTION]->(sec)
WITH x, cl
OPTIONAL MATCH (a:Allotment {id: x.allot})
FOREACH (_ IN CASE WHEN a IS NULL THEN [] ELSE [1] END | MERGE (a)-[:HAS_CLASS]->(cl))
WITH x, cl
CALL (x, cl) { UNWIND x.slots AS s MATCH (t:TimeSlot {id: s}) MERGE (cl)-[:AT_TIME]->(t) }
CALL (x, cl) { UNWIND x.rooms AS r MATCH (rm:Room {id: r}) MERGE (cl)-[:IN_ROOM]->(rm) }
CALL (x, cl) { UNWIND x.faculty AS f MATCH (fa:Faculty {id: f}) MERGE (cl)-[:TAUGHT_BY]->(fa) }
CALL (x, cl) { UNWIND x.batches AS b MATCH (bt:Batch {id: b}) MERGE (cl)-[:FOR_BATCH]->(bt) };
