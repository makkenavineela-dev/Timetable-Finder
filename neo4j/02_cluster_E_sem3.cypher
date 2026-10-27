// =====================================================================
// Cluster E, semester 3: 3E1 [3A], 3E2 [3J], 3E3 [3K], 3E4 [3T]
// Generated from Cluster_E_3rd_Sem_Timetable_Extracted.xlsx by tools/build_cluster_E_sem3_cypher.py
// Source: Uploaded PDF: 2 Cluster E 3rd SEM CLASS TIMETABLE
// B.M.S. College of Engineering, Bengaluru - Computer Science and Engineering
// September–December 2026, effective from 28/09/2026
//
// Run after 01_schema.cypher. All data files are loaded by:  cd backend  then  npm run load-data
//
// Block 0 is a clean-up. It deletes the classes, lab batches and allotments of the
// sections below, so that data loaded by an earlier version of this file cannot mix
// with this one. On an empty database it does nothing. Everything else uses MERGE
// and is safe to re-run.
//
// Decisions beyond what the sheets say:
//   - Skill Lab-1 has a teacher but no session in the file, so it is stored as not timetabled.
//   - NCMC (26CS3NCXXX) has no L-T-P in the file: stored as 0-0-0 and not timetabled (a non-credit course).
//   - Dr. Chaitra V (teaches DMS) has no initials in the file: initials CV are made from the name, and the person is placed in the Mathematics department (DMS is a mathematics course), without a cluster.
//   - Dr. Shivraj D L (teaches DMS) has no initials in the file: initials SDL are made from the name, and the person is placed in the Mathematics department (DMS is a mathematics course), without a cluster.
//   - Dr. Rajashi Chatterjee (teaches DMS) has no initials in the file: initials RC are made from the name, and the person is placed in the Mathematics department (DMS is a mathematics course), without a cluster.
//   - Ms. Likhita H A (teaches DMS) has no initials in the file: initials LHA are made from the name, and the person is placed in the Mathematics department (DMS is a mathematics course), without a cluster.
//   - '4F LAB 1-2' is kept as ONE room exactly as written. If it means 4F LAB 1 and 4F LAB 2 together, it overlaps the use of 4F LAB 1 by other sections.
//   - Room 'BSN-PG LAB': block, floor and type are not given. Placed in a block called OTHER (floor 0) as a LAB, because a lab session is held there. Correct this if you know where it is.
//   - Seminar / Workshop / Proctor Meet on WED is written as 12:10-14:00, which runs into the break after 13:05; it is stored as 12:10-13:05.
//   - These sections follow time grid B: tea 09:50-10:20, lunch 13:05-14:00, eight periods (08:00 to 16:45). The file's times were written without am/pm; hours below 8 are read as afternoon.
//   - DMS_T sessions are the DMS tutorial (type T, two periods): DMS is 3-1-0.
//   - DIP-MATH (A) and DIP-MATH (B) are not in the subject list. They are stored as one-period activities without course, room or faculty (type A), like the seminar slot; (A) and (B) are kept in the name.
//   - The classes that run in several rooms or '4F LAB 1-2' follow the same room rules as the 5th semester file.
//   - Faculty names come from 'Faculty by Class'; people who only appear in lab batches have initials only. Everyone with initials is put in the CSE department and cluster E, as in the 5th semester file.
//   - Effective from 28/09/2026.
// =====================================================================


// ---------- 0. Clean-up of what this file replaces ----------

MATCH (cl:Class)-[:FOR_SECTION]->(s:Section)
WHERE s.id IN ['CSE-UG-2026-27-S3-3E1', 'CSE-UG-2026-27-S3-3E2', 'CSE-UG-2026-27-S3-3E3', 'CSE-UG-2026-27-S3-3E4']
DETACH DELETE cl;

MATCH (s:Section)-[:HAS_ALLOTMENT]->(a:Allotment)
WHERE s.id IN ['CSE-UG-2026-27-S3-3E1', 'CSE-UG-2026-27-S3-3E2', 'CSE-UG-2026-27-S3-3E3', 'CSE-UG-2026-27-S3-3E4']
OPTIONAL MATCH (a)-[:HAS_BATCH]->(b:Batch)
DETACH DELETE b, a;


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
MERGE (sem:Semester {id:'CSE-UG-2026-27-S3'})
  SET sem.number = 3, sem.term = 'ODD'
MERGE (ay)-[:HAS_SEMESTER]->(sem)
MERGE (fc:FacultyCluster {id:'CSE-E'})
  SET fc.name = 'E'
MERGE (d)-[:HAS_FACULTY_CLUSTER]->(fc);

MATCH (col:College {id:'BMSCE'})
UNWIND [['MA', 'Mathematics']] AS x
MERGE (d:Department {id: x[0]})
  SET d.name = x[1]
MERGE (col)-[:HAS_DEPARTMENT]->(d);


// ---------- 2. Sections, and the bell schedule (time grid) they follow ----------

MATCH (sem:Semester {id:'CSE-UG-2026-27-S3'}), (fc:FacultyCluster {id:'CSE-E'}), (g:TimeGrid {id:'B'})
UNWIND [['CSE-UG-2026-27-S3-3E1', '3E1', '3A'], ['CSE-UG-2026-27-S3-3E2', '3E2', '3J'], ['CSE-UG-2026-27-S3-3E3', '3E3', '3K'], ['CSE-UG-2026-27-S3-3E4', '3E4', '3T']] AS s
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

UNWIND [['PJ', 'PJ-F2', 2, 'PJ-220', '220', 'CLASSROOM'], ['PJ', 'PJ-F4', 4, 'PJ-406', '406', 'CLASSROOM'], ['PJ', 'PJ-F4', 4, 'PJ-LAB401', 'LAB 401', 'LAB'], ['PJ', 'PJ-F4', 4, 'PJ-408', '408', 'CLASSROOM'], ['PJ', 'PJ-F4', 4, 'PJ-4F-LAB1-2', '4F LAB 1-2', 'LAB'], ['PJ', 'PJ-F1', 1, 'PJ-105', '105', 'CLASSROOM'], ['OTHER', 'OTHER-F0', 0, 'OTHER-BSN-PG-LAB', 'BSN-PG LAB', 'LAB'], ['PJ', 'PJ-F4', 4, 'PJ-4F-LAB1', '4F LAB 1', 'LAB'], ['PJ', 'PJ-F4', 4, 'PJ-407', '407', 'CLASSROOM'], ['PJ', 'PJ-F2', 2, 'PJ-204', '204', 'CLASSROOM'], ['PJ', 'PJ-F2', 2, 'PJ-208', '208', 'CLASSROOM'], ['PJ', 'PJ-F2', 2, 'PJ-213', '213', 'CLASSROOM']] AS r
MATCH (bl:Building {id: r[0]})
MERGE (fl:Floor {id: r[1]})
  SET fl.number = r[2]
MERGE (bl)-[:HAS_FLOOR]->(fl)
MERGE (room:Room {id: r[3]})
  SET room.number = r[4], room.type = r[5]
MERGE (fl)-[:HAS_ROOM]->(room);


// ---------- 4. Courses with their L-T-P ----------

MATCH (sem:Semester {id:'CSE-UG-2026-27-S3'})
UNWIND [['26CS3IPDST', 'Data Structures', 'DS', 'IP', '3-0-1', 'REGULAR'], ['26CS3IPDBM', 'Database Management Systems', 'DBMS', 'IP', '3-0-1', 'REGULAR'], ['26CS3PCDLC', 'Digital Logic and Computer Organization', 'DLC', 'PC', '3-0-0', 'REGULAR'], ['26CS3PCOOP', 'Object Oriented Programming', 'OOP', 'PC', '3-0-1', 'REGULAR'], ['26MA3BSDMS', 'Discrete Mathematics and Statistics', 'DMS', 'BS', '3-1-0', 'REGULAR'], ['26CS3AEFSD', 'Full Stack Development', 'FSD', 'AE', '0-0-1', 'REGULAR'], ['26CS3SDXX', 'Skill Lab-1', 'Skill Lab-1', 'SD', '0-0-1', 'NONE'], ['26CS3NCXXX', 'NCMC', 'NCMC', 'NC', '0-0-0', 'NONE']] AS c
WITH sem, c, [x IN split(c[4], '-') | toInteger(x)] AS ltp
MERGE (course:Course {code: c[0]})
  SET course.name = c[1], course.short = c[2], course.category = c[3], course.LTP = c[4],
      course.credits = ltp[0] + ltp[1] + ltp[2], course.scheduling = c[5]
MERGE (sem)-[:HAS_COURSE]->(course);

UNWIND [['26CS3IPDST', '3-0-1'], ['26CS3IPDBM', '3-0-1'], ['26CS3PCDLC', '3-0-0'], ['26CS3PCOOP', '3-0-1'], ['26MA3BSDMS', '3-1-0'], ['26CS3AEFSD', '0-0-1'], ['26CS3SDXX', '0-0-1'], ['26CS3NCXXX', '0-0-0']] AS c
MATCH (course:Course {code: c[0]})
WITH course, [x IN split(c[1], '-') | toInteger(x)] AS ltp
UNWIND [['L', ltp[0]], ['T', ltp[1]], ['P', ltp[2]]] AS part
WITH course, part WHERE part[1] > 0
MATCH (l:LTP {code: part[0]})
MERGE (course)-[r:HAS_LTP]->(l)
  SET r.credits = part[1], r.periodsPerWeek = part[1] * l.periodsPerCredit,
      r.classesPerWeek = part[1] * l.periodsPerCredit / l.periodsPerClass;


// ---------- 5. Faculty (initials only where the file gives no name) ----------

UNWIND [['CSE-BSR', 'BSR', 'Dr. Rajeshwari B S', 'CSE', true], ['CSE-AB', 'AB', 'Prof. Amruta B', 'CSE', true], ['CSE-SLR', 'SLR', 'Dr. Sreelatha R', 'CSE', true], ['CSE-MHM', 'MHM', 'Prof. Monisha H M', 'CSE', true], ['MA-CV', 'CV', 'Dr. Chaitra V', 'MA', false], ['CSE-SAH', 'SAH', 'Prof. Sahana A', 'CSE', true], ['CSE-MGB', 'MGB', 'Prof. Monisha G B', 'CSE', true], ['CSE-SMR', 'SMR', 'Prof. Smrithi S', 'CSE', true], ['CSE-AK', 'AK', 'Prof. Ambuja K', 'CSE', true], ['MA-SDL', 'SDL', 'Dr. Shivraj D L', 'MA', false], ['CSE-AAS', 'AAS', 'Prof. Amrutha Varshini A S', 'CSE', true], ['CSE-LS', 'LS', 'Dr. Laxman Singh', 'CSE', true], ['CSE-SS', 'SS', 'Prof. Sunayana S', 'CSE', true], ['CSE-BVK', 'BVK', 'Dr. Bhavani K', 'CSE', true], ['MA-RC', 'RC', 'Dr. Rajashi Chatterjee', 'MA', false], ['CSE-NNM', 'NNM', 'Prof. Nagesh N M', 'CSE', true], ['CSE-NAS', 'NAS', 'Prof. Navyashree S', 'CSE', true], ['MA-LHA', 'LHA', 'Ms. Likhita H A', 'MA', false], ['CSE-SRN', 'SRN', 'Prof. Sindhoor N', 'CSE', true], ['CSE-NTJ', 'NTJ', null, 'CSE', true], ['CSE-AHV', 'AHV', null, 'CSE', true], ['CSE-SHR', 'SHR', null, 'CSE', true], ['CSE-NSJ', 'NSJ', null, 'CSE', true], ['CSE-VG', 'VG', null, 'CSE', true], ['CSE-PA', 'PA', null, 'CSE', true], ['CSE-SAR', 'SAR', null, 'CSE', true], ['CSE-CAV', 'CAV', null, 'CSE', true], ['CSE-MS', 'MS', null, 'CSE', true], ['CSE-SUR', 'SUR', null, 'CSE', true], ['CSE-DK', 'DK', null, 'CSE', true], ['CSE-SAN', 'SAN', null, 'CSE', true], ['CSE-SPS', 'SPS', null, 'CSE', true], ['CSE-TFS', 'TFS', null, 'CSE', true], ['CSE-ASG', 'ASG', null, 'CSE', true], ['CSE-RKB', 'RKB', null, 'CSE', true], ['CSE-ADI', 'ADI', null, 'CSE', true]] AS f
MATCH (d:Department {id: f[3]})
MERGE (fac:Faculty {id: f[0]})
  SET fac.initials = f[1], fac.name = coalesce(f[2], fac.name, f[1])
MERGE (fac)-[:WORKS_IN]->(d)
WITH fac, f WHERE f[4]
MATCH (fc:FacultyCluster {id:'CSE-E'})
MERGE (fc)-[:HAS_FACULTY]->(fac);


// ---------- 6. Allotments: every course of the semester given to every section, with its teacher ----------

UNWIND [{id: 'CSE-UG-2026-27-S3-3E1-26CS3IPDST', section: 'CSE-UG-2026-27-S3-3E1', course: '26CS3IPDST', teacher: 'CSE-BSR'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM', section: 'CSE-UG-2026-27-S3-3E1', course: '26CS3IPDBM', teacher: 'CSE-AB'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3PCDLC', section: 'CSE-UG-2026-27-S3-3E1', course: '26CS3PCDLC', teacher: 'CSE-SLR'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP', section: 'CSE-UG-2026-27-S3-3E1', course: '26CS3PCOOP', teacher: 'CSE-MHM'}, {id: 'CSE-UG-2026-27-S3-3E1-26MA3BSDMS', section: 'CSE-UG-2026-27-S3-3E1', course: '26MA3BSDMS', teacher: 'MA-CV'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3AEFSD', section: 'CSE-UG-2026-27-S3-3E1', course: '26CS3AEFSD', teacher: 'CSE-SAH'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3SDXX', section: 'CSE-UG-2026-27-S3-3E1', course: '26CS3SDXX', teacher: 'CSE-MGB'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3NCXXX', section: 'CSE-UG-2026-27-S3-3E1', course: '26CS3NCXXX', teacher: null}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3IPDST', section: 'CSE-UG-2026-27-S3-3E2', course: '26CS3IPDST', teacher: 'CSE-SMR'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM', section: 'CSE-UG-2026-27-S3-3E2', course: '26CS3IPDBM', teacher: 'CSE-AB'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3PCDLC', section: 'CSE-UG-2026-27-S3-3E2', course: '26CS3PCDLC', teacher: 'CSE-AK'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP', section: 'CSE-UG-2026-27-S3-3E2', course: '26CS3PCOOP', teacher: 'CSE-MHM'}, {id: 'CSE-UG-2026-27-S3-3E2-26MA3BSDMS', section: 'CSE-UG-2026-27-S3-3E2', course: '26MA3BSDMS', teacher: 'MA-SDL'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3AEFSD', section: 'CSE-UG-2026-27-S3-3E2', course: '26CS3AEFSD', teacher: 'CSE-AK'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3SDXX', section: 'CSE-UG-2026-27-S3-3E2', course: '26CS3SDXX', teacher: 'CSE-AB'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3NCXXX', section: 'CSE-UG-2026-27-S3-3E2', course: '26CS3NCXXX', teacher: null}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3IPDST', section: 'CSE-UG-2026-27-S3-3E3', course: '26CS3IPDST', teacher: 'CSE-AAS'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM', section: 'CSE-UG-2026-27-S3-3E3', course: '26CS3IPDBM', teacher: 'CSE-LS'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3PCDLC', section: 'CSE-UG-2026-27-S3-3E3', course: '26CS3PCDLC', teacher: 'CSE-SS'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP', section: 'CSE-UG-2026-27-S3-3E3', course: '26CS3PCOOP', teacher: 'CSE-BVK'}, {id: 'CSE-UG-2026-27-S3-3E3-26MA3BSDMS', section: 'CSE-UG-2026-27-S3-3E3', course: '26MA3BSDMS', teacher: 'MA-RC'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3AEFSD', section: 'CSE-UG-2026-27-S3-3E3', course: '26CS3AEFSD', teacher: 'CSE-SS'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3SDXX', section: 'CSE-UG-2026-27-S3-3E3', course: '26CS3SDXX', teacher: 'CSE-BVK'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3NCXXX', section: 'CSE-UG-2026-27-S3-3E3', course: '26CS3NCXXX', teacher: null}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3IPDST', section: 'CSE-UG-2026-27-S3-3E4', course: '26CS3IPDST', teacher: 'CSE-NNM'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM', section: 'CSE-UG-2026-27-S3-3E4', course: '26CS3IPDBM', teacher: 'CSE-NAS'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3PCDLC', section: 'CSE-UG-2026-27-S3-3E4', course: '26CS3PCDLC', teacher: 'CSE-SLR'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP', section: 'CSE-UG-2026-27-S3-3E4', course: '26CS3PCOOP', teacher: 'CSE-BVK'}, {id: 'CSE-UG-2026-27-S3-3E4-26MA3BSDMS', section: 'CSE-UG-2026-27-S3-3E4', course: '26MA3BSDMS', teacher: 'MA-LHA'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3AEFSD', section: 'CSE-UG-2026-27-S3-3E4', course: '26CS3AEFSD', teacher: 'CSE-BVK'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3SDXX', section: 'CSE-UG-2026-27-S3-3E4', course: '26CS3SDXX', teacher: 'CSE-SRN'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3NCXXX', section: 'CSE-UG-2026-27-S3-3E4', course: '26CS3NCXXX', teacher: null}] AS x
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

UNWIND [{id: 'CSE-UG-2026-27-S3-3E1-26CS3IPDST-B1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3IPDST', name: 'B1', faculty: 'CSE-AAS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3IPDST-B2', allot: 'CSE-UG-2026-27-S3-3E1-26CS3IPDST', name: 'B2', faculty: 'CSE-AHV', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3IPDST-B3', allot: 'CSE-UG-2026-27-S3-3E1-26CS3IPDST', name: 'B3', faculty: 'CSE-AHV', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3IPDST-B4', allot: 'CSE-UG-2026-27-S3-3E1-26CS3IPDST', name: 'B4', faculty: 'CSE-SHR', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM-B1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM', name: 'B1', faculty: 'CSE-AB', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM-B2', allot: 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM', name: 'B2', faculty: 'CSE-VG', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM-B3', allot: 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM', name: 'B3', faculty: 'CSE-SMR', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM-B4', allot: 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM', name: 'B4', faculty: 'CSE-PA', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP-B1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP', name: 'B1', faculty: 'CSE-MHM', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP-B2', allot: 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP', name: 'B2', faculty: 'CSE-NSJ', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP-B3', allot: 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP', name: 'B3', faculty: 'CSE-NAS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP-B4', allot: 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP', name: 'B4', faculty: 'CSE-NAS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3AEFSD-B1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3AEFSD', name: 'B1', faculty: 'CSE-SAH', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3AEFSD-B2', allot: 'CSE-UG-2026-27-S3-3E1-26CS3AEFSD', name: 'B2', faculty: 'CSE-AK', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3AEFSD-B3', allot: 'CSE-UG-2026-27-S3-3E1-26CS3AEFSD', name: 'B3', faculty: 'CSE-SS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E1-26CS3AEFSD-B4', allot: 'CSE-UG-2026-27-S3-3E1-26CS3AEFSD', name: 'B4', faculty: 'CSE-NTJ', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3IPDST-B1', allot: 'CSE-UG-2026-27-S3-3E2-26CS3IPDST', name: 'B1', faculty: 'CSE-SMR', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3IPDST-B2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3IPDST', name: 'B2', faculty: 'CSE-SMR', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3IPDST-B3', allot: 'CSE-UG-2026-27-S3-3E2-26CS3IPDST', name: 'B3', faculty: 'CSE-SAR', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3IPDST-B4', allot: 'CSE-UG-2026-27-S3-3E2-26CS3IPDST', name: 'B4', faculty: 'CSE-CAV', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM-B1', allot: 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM', name: 'B1', faculty: 'CSE-AB', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM-B2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM', name: 'B2', faculty: 'CSE-LS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM-B3', allot: 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM', name: 'B3', faculty: 'CSE-VG', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM-B4', allot: 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM', name: 'B4', faculty: 'CSE-MGB', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP-B1', allot: 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP', name: 'B1', faculty: 'CSE-MHM', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP-B2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP', name: 'B2', faculty: 'CSE-BVK', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP-B3', allot: 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP', name: 'B3', faculty: 'CSE-SS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP-B4', allot: 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP', name: 'B4', faculty: 'CSE-NSJ', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3AEFSD-B1', allot: 'CSE-UG-2026-27-S3-3E2-26CS3AEFSD', name: 'B1', faculty: 'CSE-AK', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3AEFSD-B2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3AEFSD', name: 'B2', faculty: 'CSE-SAH', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3AEFSD-B3', allot: 'CSE-UG-2026-27-S3-3E2-26CS3AEFSD', name: 'B3', faculty: 'CSE-MS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E2-26CS3AEFSD-B4', allot: 'CSE-UG-2026-27-S3-3E2-26CS3AEFSD', name: 'B4', faculty: 'CSE-NTJ', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3IPDST-B1', allot: 'CSE-UG-2026-27-S3-3E3-26CS3IPDST', name: 'B1', faculty: 'CSE-AAS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3IPDST-B2', allot: 'CSE-UG-2026-27-S3-3E3-26CS3IPDST', name: 'B2', faculty: 'CSE-SS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3IPDST-B3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3IPDST', name: 'B3', faculty: 'CSE-SMR', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3IPDST-B4', allot: 'CSE-UG-2026-27-S3-3E3-26CS3IPDST', name: 'B4', faculty: 'CSE-SAR', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM-B1', allot: 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM', name: 'B1', faculty: 'CSE-LS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM-B2', allot: 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM', name: 'B2', faculty: 'CSE-SUR', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM-B3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM', name: 'B3', faculty: 'CSE-SUR', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM-B4', allot: 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM', name: 'B4', faculty: 'CSE-DK', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP-B1', allot: 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP', name: 'B1', faculty: 'CSE-BVK', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP-B2', allot: 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP', name: 'B2', faculty: 'CSE-MHM', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP-B3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP', name: 'B3', faculty: 'CSE-NSJ', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP-B4', allot: 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP', name: 'B4', faculty: 'CSE-NNM', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3AEFSD-B1', allot: 'CSE-UG-2026-27-S3-3E3-26CS3AEFSD', name: 'B1', faculty: 'CSE-SS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3AEFSD-B2', allot: 'CSE-UG-2026-27-S3-3E3-26CS3AEFSD', name: 'B2', faculty: 'CSE-BVK', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3AEFSD-B3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3AEFSD', name: 'B3', faculty: 'CSE-SAN', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E3-26CS3AEFSD-B4', allot: 'CSE-UG-2026-27-S3-3E3-26CS3AEFSD', name: 'B4', faculty: 'CSE-SPS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3IPDST-B1', allot: 'CSE-UG-2026-27-S3-3E4-26CS3IPDST', name: 'B1', faculty: 'CSE-NNM', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3IPDST-B2', allot: 'CSE-UG-2026-27-S3-3E4-26CS3IPDST', name: 'B2', faculty: 'CSE-SS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3IPDST-B3', allot: 'CSE-UG-2026-27-S3-3E4-26CS3IPDST', name: 'B3', faculty: 'CSE-AHV', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3IPDST-B4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3IPDST', name: 'B4', faculty: 'CSE-TFS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM-B1', allot: 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM', name: 'B1', faculty: 'CSE-NAS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM-B2', allot: 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM', name: 'B2', faculty: 'CSE-MHM', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM-B3', allot: 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM', name: 'B3', faculty: 'CSE-AB', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM-B4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM', name: 'B4', faculty: 'CSE-LS', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP-B1', allot: 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP', name: 'B1', faculty: 'CSE-BVK', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP-B2', allot: 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP', name: 'B2', faculty: 'CSE-SMR', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP-B3', allot: 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP', name: 'B3', faculty: 'CSE-SAH', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP-B4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP', name: 'B4', faculty: 'CSE-NNM', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3AEFSD-B1', allot: 'CSE-UG-2026-27-S3-3E4-26CS3AEFSD', name: 'B1', faculty: 'CSE-BVK', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3AEFSD-B2', allot: 'CSE-UG-2026-27-S3-3E4-26CS3AEFSD', name: 'B2', faculty: 'CSE-ASG', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3AEFSD-B3', allot: 'CSE-UG-2026-27-S3-3E4-26CS3AEFSD', name: 'B3', faculty: 'CSE-RKB', type: 'LAB'}, {id: 'CSE-UG-2026-27-S3-3E4-26CS3AEFSD-B4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3AEFSD', name: 'B4', faculty: 'CSE-ADI', type: 'LAB'}] AS x
MATCH (a:Allotment {id: x.allot}), (f:Faculty {id: x.faculty})
MERGE (b:Batch {id: x.id})
  SET b.name = x.name, b.type = x.type
MERGE (a)-[:HAS_BATCH]->(b)
MERGE (b)-[:ASSIGNED_TO]->(f);


// ---------- 8. Classes: lectures, tutorials, labs, elective slots and activities ----------
// type: L lecture, T tutorial, P lab, A activity. Periods are of time grid B.
// A lab is taken by every batch with its own faculty.


// 3E1 [3A] - 24 sessions

UNWIND [
  {id: 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM-L-B-MON-P2', name: 'DBMS', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM', type: 'L', slots: ['B-MON-P2'], rooms: ['PJ-220'], faculty: ['CSE-AB'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E1-26CS3IPDST-L-B-MON-P3', name: 'DS', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3IPDST', type: 'L', slots: ['B-MON-P3'], rooms: ['PJ-406'], faculty: ['CSE-BSR'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E1-26CS3AEFSD-P-B-MON-P4', name: 'FSD Lab', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3AEFSD', type: 'P', slots: ['B-MON-P4', 'B-MON-P5'], rooms: ['PJ-LAB401'], faculty: ['CSE-SAH', 'CSE-AK', 'CSE-SS', 'CSE-NTJ'], batches: ['CSE-UG-2026-27-S3-3E1-26CS3AEFSD-B1', 'CSE-UG-2026-27-S3-3E1-26CS3AEFSD-B2', 'CSE-UG-2026-27-S3-3E1-26CS3AEFSD-B3', 'CSE-UG-2026-27-S3-3E1-26CS3AEFSD-B4']},
  {id: 'CSE-UG-2026-27-S3-3E1-26MA3BSDMS-L-B-MON-P6', name: 'DMS', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26MA3BSDMS', type: 'L', slots: ['B-MON-P6'], rooms: ['PJ-220'], faculty: ['MA-CV'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E1-26CS3PCDLC-L-B-MON-P7', name: 'DLC', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3PCDLC', type: 'L', slots: ['B-MON-P7'], rooms: ['PJ-220'], faculty: ['CSE-SLR'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E1-A-B-MON-P8', name: 'DIP-MATH (A)', section: 'CSE-UG-2026-27-S3-3E1', allot: null, type: 'A', slots: ['B-MON-P8'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E1-26MA3BSDMS-L-B-TUE-P2', name: 'DMS', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26MA3BSDMS', type: 'L', slots: ['B-TUE-P2'], rooms: ['PJ-408'], faculty: ['MA-CV'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP-L-B-TUE-P3', name: 'OOP', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP', type: 'L', slots: ['B-TUE-P3'], rooms: ['PJ-220'], faculty: ['CSE-MHM'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E1-26CS3IPDST-P-B-TUE-P4', name: 'DS Lab', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3IPDST', type: 'P', slots: ['B-TUE-P4', 'B-TUE-P5'], rooms: ['PJ-4F-LAB1-2'], faculty: ['CSE-AAS', 'CSE-AHV', 'CSE-SHR'], batches: ['CSE-UG-2026-27-S3-3E1-26CS3IPDST-B1', 'CSE-UG-2026-27-S3-3E1-26CS3IPDST-B2', 'CSE-UG-2026-27-S3-3E1-26CS3IPDST-B3', 'CSE-UG-2026-27-S3-3E1-26CS3IPDST-B4']},
  {id: 'CSE-UG-2026-27-S3-3E1-A-B-TUE-P6', name: 'Seminar / Workshop / Proctor Meet', section: 'CSE-UG-2026-27-S3-3E1', allot: null, type: 'A', slots: ['B-TUE-P6', 'B-TUE-P7'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E1-A-B-TUE-P8', name: 'DIP-MATH (A)', section: 'CSE-UG-2026-27-S3-3E1', allot: null, type: 'A', slots: ['B-TUE-P8'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP-L-B-WED-P2', name: 'OOP', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP', type: 'L', slots: ['B-WED-P2'], rooms: ['PJ-220'], faculty: ['CSE-MHM'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM-L-B-WED-P3', name: 'DBMS', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM', type: 'L', slots: ['B-WED-P3'], rooms: ['PJ-105'], faculty: ['CSE-AB'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E1-26MA3BSDMS-T-B-WED-P4', name: 'DMS Tutorial', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26MA3BSDMS', type: 'T', slots: ['B-WED-P4'], rooms: ['PJ-105'], faculty: ['MA-CV'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E1-A-B-WED-P8', name: 'DIP-MATH (A)', section: 'CSE-UG-2026-27-S3-3E1', allot: null, type: 'A', slots: ['B-WED-P8'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E1-26CS3IPDST-L-B-THU-P2', name: 'DS', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3IPDST', type: 'L', slots: ['B-THU-P2'], rooms: ['PJ-220'], faculty: ['CSE-BSR'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E1-26CS3PCDLC-L-B-THU-P3', name: 'DLC', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3PCDLC', type: 'L', slots: ['B-THU-P3'], rooms: ['PJ-406'], faculty: ['CSE-SLR'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP-P-B-THU-P4', name: 'OOP Lab', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP', type: 'P', slots: ['B-THU-P4', 'B-THU-P5'], rooms: ['OTHER-BSN-PG-LAB'], faculty: ['CSE-MHM', 'CSE-NSJ', 'CSE-NAS'], batches: ['CSE-UG-2026-27-S3-3E1-26CS3PCOOP-B1', 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP-B2', 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP-B3', 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP-B4']},
  {id: 'CSE-UG-2026-27-S3-3E1-26MA3BSDMS-L-B-THU-P6', name: 'DMS', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26MA3BSDMS', type: 'L', slots: ['B-THU-P6'], rooms: ['PJ-220'], faculty: ['MA-CV'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM-L-B-FRI-P2', name: 'DBMS', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM', type: 'L', slots: ['B-FRI-P2'], rooms: ['PJ-408'], faculty: ['CSE-AB'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E1-26CS3IPDST-L-B-FRI-P3', name: 'DS', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3IPDST', type: 'L', slots: ['B-FRI-P3'], rooms: ['PJ-408'], faculty: ['CSE-BSR'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM-P-B-FRI-P4', name: 'DBMS Lab', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM', type: 'P', slots: ['B-FRI-P4', 'B-FRI-P5'], rooms: ['OTHER-BSN-PG-LAB'], faculty: ['CSE-AB', 'CSE-VG', 'CSE-SMR', 'CSE-PA'], batches: ['CSE-UG-2026-27-S3-3E1-26CS3IPDBM-B1', 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM-B2', 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM-B3', 'CSE-UG-2026-27-S3-3E1-26CS3IPDBM-B4']},
  {id: 'CSE-UG-2026-27-S3-3E1-26CS3PCDLC-L-B-FRI-P6', name: 'DLC', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3PCDLC', type: 'L', slots: ['B-FRI-P6'], rooms: ['PJ-408'], faculty: ['CSE-SLR'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP-L-B-FRI-P7', name: 'OOP', section: 'CSE-UG-2026-27-S3-3E1', allot: 'CSE-UG-2026-27-S3-3E1-26CS3PCOOP', type: 'L', slots: ['B-FRI-P7'], rooms: ['PJ-408'], faculty: ['CSE-MHM'], batches: []}
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


// 3E2 [3J] - 24 sessions

UNWIND [
  {id: 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP-L-B-MON-P2', name: 'OOP', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP', type: 'L', slots: ['B-MON-P2'], rooms: ['PJ-408'], faculty: ['CSE-MHM'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E2-26MA3BSDMS-L-B-MON-P3', name: 'DMS', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26MA3BSDMS', type: 'L', slots: ['B-MON-P3'], rooms: ['PJ-408'], faculty: ['MA-SDL'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM-L-B-MON-P4', name: 'DBMS', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM', type: 'L', slots: ['B-MON-P4'], rooms: ['PJ-408'], faculty: ['CSE-AB'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E2-26CS3IPDST-L-B-MON-P5', name: 'DS', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3IPDST', type: 'L', slots: ['B-MON-P5'], rooms: ['PJ-408'], faculty: ['CSE-SMR'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E2-A-B-MON-P8', name: 'DIP-MATH (A)', section: 'CSE-UG-2026-27-S3-3E2', allot: null, type: 'A', slots: ['B-MON-P8'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E2-26MA3BSDMS-L-B-TUE-P2', name: 'DMS', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26MA3BSDMS', type: 'L', slots: ['B-TUE-P2'], rooms: ['PJ-220'], faculty: ['MA-SDL'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E2-26CS3IPDST-L-B-TUE-P3', name: 'DS', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3IPDST', type: 'L', slots: ['B-TUE-P3'], rooms: ['PJ-406'], faculty: ['CSE-SMR'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E2-26CS3IPDST-P-B-TUE-P4', name: 'DS Lab', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3IPDST', type: 'P', slots: ['B-TUE-P4', 'B-TUE-P5'], rooms: ['PJ-LAB401'], faculty: ['CSE-SMR', 'CSE-SAR', 'CSE-CAV'], batches: ['CSE-UG-2026-27-S3-3E2-26CS3IPDST-B1', 'CSE-UG-2026-27-S3-3E2-26CS3IPDST-B2', 'CSE-UG-2026-27-S3-3E2-26CS3IPDST-B3', 'CSE-UG-2026-27-S3-3E2-26CS3IPDST-B4']},
  {id: 'CSE-UG-2026-27-S3-3E2-A-B-TUE-P8', name: 'DIP-MATH (A)', section: 'CSE-UG-2026-27-S3-3E2', allot: null, type: 'A', slots: ['B-TUE-P8'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E2-26MA3BSDMS-T-B-WED-P1', name: 'DMS Tutorial', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26MA3BSDMS', type: 'T', slots: ['B-WED-P1', 'B-WED-P2'], rooms: ['PJ-406'], faculty: ['MA-SDL'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP-P-B-WED-P3', name: 'OOP Lab', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP', type: 'P', slots: ['B-WED-P3', 'B-WED-P4'], rooms: ['PJ-4F-LAB1'], faculty: ['CSE-MHM', 'CSE-BVK', 'CSE-SS', 'CSE-NSJ'], batches: ['CSE-UG-2026-27-S3-3E2-26CS3PCOOP-B1', 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP-B2', 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP-B3', 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP-B4']},
  {id: 'CSE-UG-2026-27-S3-3E2-A-B-WED-P5', name: 'Seminar / Workshop / Proctor Meet', section: 'CSE-UG-2026-27-S3-3E2', allot: null, type: 'A', slots: ['B-WED-P5'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E2-A-B-WED-P8', name: 'DIP-MATH (A)', section: 'CSE-UG-2026-27-S3-3E2', allot: null, type: 'A', slots: ['B-WED-P8'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP-L-B-THU-P2', name: 'OOP', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP', type: 'L', slots: ['B-THU-P2'], rooms: ['PJ-407'], faculty: ['CSE-MHM'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM-P-B-THU-P3', name: 'DBMS Lab', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM', type: 'P', slots: ['B-THU-P3', 'B-THU-P4'], rooms: ['PJ-4F-LAB1'], faculty: ['CSE-AB', 'CSE-LS', 'CSE-VG', 'CSE-MGB'], batches: ['CSE-UG-2026-27-S3-3E2-26CS3IPDBM-B1', 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM-B2', 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM-B3', 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM-B4']},
  {id: 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM-L-B-THU-P5', name: 'DBMS', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM', type: 'L', slots: ['B-THU-P5'], rooms: ['PJ-407'], faculty: ['CSE-AB'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E2-26CS3PCDLC-L-B-THU-P6', name: 'DLC', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3PCDLC', type: 'L', slots: ['B-THU-P6'], rooms: ['PJ-407'], faculty: ['CSE-AK'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E2-26CS3PCDLC-L-B-FRI-P2', name: 'DLC', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3PCDLC', type: 'L', slots: ['B-FRI-P2'], rooms: ['PJ-407'], faculty: ['CSE-AK'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E2-26MA3BSDMS-L-B-FRI-P3', name: 'DMS', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26MA3BSDMS', type: 'L', slots: ['B-FRI-P3'], rooms: ['PJ-407'], faculty: ['MA-SDL'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E2-26CS3AEFSD-P-B-FRI-P4', name: 'FSD Lab', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3AEFSD', type: 'P', slots: ['B-FRI-P4', 'B-FRI-P5'], rooms: ['PJ-4F-LAB1'], faculty: ['CSE-AK', 'CSE-SAH', 'CSE-MS', 'CSE-NTJ'], batches: ['CSE-UG-2026-27-S3-3E2-26CS3AEFSD-B1', 'CSE-UG-2026-27-S3-3E2-26CS3AEFSD-B2', 'CSE-UG-2026-27-S3-3E2-26CS3AEFSD-B3', 'CSE-UG-2026-27-S3-3E2-26CS3AEFSD-B4']},
  {id: 'CSE-UG-2026-27-S3-3E2-26CS3IPDST-L-B-SAT-P2', name: 'DS', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3IPDST', type: 'L', slots: ['B-SAT-P2'], rooms: ['PJ-406'], faculty: ['CSE-SMR'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM-L-B-SAT-P3', name: 'DBMS', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3IPDBM', type: 'L', slots: ['B-SAT-P3'], rooms: ['PJ-204'], faculty: ['CSE-AB'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E2-26CS3PCDLC-L-B-SAT-P4', name: 'DLC', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3PCDLC', type: 'L', slots: ['B-SAT-P4'], rooms: ['PJ-204'], faculty: ['CSE-AK'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP-L-B-SAT-P5', name: 'OOP', section: 'CSE-UG-2026-27-S3-3E2', allot: 'CSE-UG-2026-27-S3-3E2-26CS3PCOOP', type: 'L', slots: ['B-SAT-P5'], rooms: ['PJ-204'], faculty: ['CSE-MHM'], batches: []}
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


// 3E3 [3K] - 24 sessions

UNWIND [
  {id: 'CSE-UG-2026-27-S3-3E3-A-B-MON-P2', name: 'Seminar / Workshop / Proctor Meet', section: 'CSE-UG-2026-27-S3-3E3', allot: null, type: 'A', slots: ['B-MON-P2'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP-L-B-MON-P3', name: 'OOP', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP', type: 'L', slots: ['B-MON-P3'], rooms: ['PJ-407'], faculty: ['CSE-BVK'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM-P-B-MON-P4', name: 'DBMS Lab', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM', type: 'P', slots: ['B-MON-P4', 'B-MON-P5'], rooms: ['PJ-4F-LAB1'], faculty: ['CSE-LS', 'CSE-SUR', 'CSE-DK'], batches: ['CSE-UG-2026-27-S3-3E3-26CS3IPDBM-B1', 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM-B2', 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM-B3', 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM-B4']},
  {id: 'CSE-UG-2026-27-S3-3E3-26MA3BSDMS-L-B-MON-P6', name: 'DMS', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26MA3BSDMS', type: 'L', slots: ['B-MON-P6'], rooms: ['PJ-407'], faculty: ['MA-RC'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E3-A-B-MON-P8', name: 'DIP-MATH (A)', section: 'CSE-UG-2026-27-S3-3E3', allot: null, type: 'A', slots: ['B-MON-P8'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E3-26CS3PCDLC-L-B-TUE-P2', name: 'DLC', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3PCDLC', type: 'L', slots: ['B-TUE-P2'], rooms: ['PJ-407'], faculty: ['CSE-SS'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP-L-B-TUE-P3', name: 'OOP', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP', type: 'L', slots: ['B-TUE-P3'], rooms: ['PJ-407'], faculty: ['CSE-BVK'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E3-26CS3AEFSD-P-B-TUE-P4', name: 'FSD Lab', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3AEFSD', type: 'P', slots: ['B-TUE-P4', 'B-TUE-P5'], rooms: ['PJ-4F-LAB1'], faculty: ['CSE-SS', 'CSE-BVK', 'CSE-SAN', 'CSE-SPS'], batches: ['CSE-UG-2026-27-S3-3E3-26CS3AEFSD-B1', 'CSE-UG-2026-27-S3-3E3-26CS3AEFSD-B2', 'CSE-UG-2026-27-S3-3E3-26CS3AEFSD-B3', 'CSE-UG-2026-27-S3-3E3-26CS3AEFSD-B4']},
  {id: 'CSE-UG-2026-27-S3-3E3-A-B-TUE-P8', name: 'DIP-MATH (A)', section: 'CSE-UG-2026-27-S3-3E3', allot: null, type: 'A', slots: ['B-TUE-P8'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E3-26MA3BSDMS-L-B-WED-P2', name: 'DMS', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26MA3BSDMS', type: 'L', slots: ['B-WED-P2'], rooms: ['PJ-408'], faculty: ['MA-RC'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E3-26CS3IPDST-L-B-WED-P3', name: 'DS', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3IPDST', type: 'L', slots: ['B-WED-P3'], rooms: ['PJ-220'], faculty: ['CSE-AAS'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM-L-B-WED-P4', name: 'DBMS', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM', type: 'L', slots: ['B-WED-P4'], rooms: ['PJ-220'], faculty: ['CSE-LS'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP-L-B-WED-P5', name: 'OOP', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP', type: 'L', slots: ['B-WED-P5'], rooms: ['PJ-220'], faculty: ['CSE-BVK'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E3-A-B-WED-P8', name: 'DIP-MATH (A)', section: 'CSE-UG-2026-27-S3-3E3', allot: null, type: 'A', slots: ['B-WED-P8'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E3-26CS3PCDLC-L-B-THU-P1', name: 'DLC', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3PCDLC', type: 'L', slots: ['B-THU-P1'], rooms: ['PJ-406'], faculty: ['CSE-SS'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E3-26MA3BSDMS-L-B-THU-P2', name: 'DMS', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26MA3BSDMS', type: 'L', slots: ['B-THU-P2'], rooms: ['PJ-406'], faculty: ['MA-RC'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E3-26CS3IPDST-P-B-THU-P3', name: 'DS Lab', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3IPDST', type: 'P', slots: ['B-THU-P3', 'B-THU-P4'], rooms: ['PJ-4F-LAB1-2'], faculty: ['CSE-AAS', 'CSE-SS', 'CSE-SMR', 'CSE-SAR'], batches: ['CSE-UG-2026-27-S3-3E3-26CS3IPDST-B1', 'CSE-UG-2026-27-S3-3E3-26CS3IPDST-B2', 'CSE-UG-2026-27-S3-3E3-26CS3IPDST-B3', 'CSE-UG-2026-27-S3-3E3-26CS3IPDST-B4']},
  {id: 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM-L-B-FRI-P2', name: 'DBMS', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM', type: 'L', slots: ['B-FRI-P2'], rooms: ['PJ-406'], faculty: ['CSE-LS'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E3-26CS3IPDST-L-B-FRI-P3', name: 'DS', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3IPDST', type: 'L', slots: ['B-FRI-P3'], rooms: ['PJ-220'], faculty: ['CSE-AAS'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP-P-B-FRI-P4', name: 'OOP Lab', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP', type: 'P', slots: ['B-FRI-P4', 'B-FRI-P5'], rooms: ['PJ-4F-LAB1-2'], faculty: ['CSE-BVK', 'CSE-MHM', 'CSE-NSJ', 'CSE-NNM'], batches: ['CSE-UG-2026-27-S3-3E3-26CS3PCOOP-B1', 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP-B2', 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP-B3', 'CSE-UG-2026-27-S3-3E3-26CS3PCOOP-B4']},
  {id: 'CSE-UG-2026-27-S3-3E3-26MA3BSDMS-T-B-FRI-P6', name: 'DMS Tutorial', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26MA3BSDMS', type: 'T', slots: ['B-FRI-P6', 'B-FRI-P7'], rooms: ['PJ-407'], faculty: ['MA-RC'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E3-26CS3PCDLC-L-B-SAT-P3', name: 'DLC', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3PCDLC', type: 'L', slots: ['B-SAT-P3'], rooms: ['PJ-208'], faculty: ['CSE-SS'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E3-26CS3IPDST-L-B-SAT-P4', name: 'DS', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3IPDST', type: 'L', slots: ['B-SAT-P4'], rooms: ['PJ-208'], faculty: ['CSE-AAS'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM-L-B-SAT-P5', name: 'DBMS', section: 'CSE-UG-2026-27-S3-3E3', allot: 'CSE-UG-2026-27-S3-3E3-26CS3IPDBM', type: 'L', slots: ['B-SAT-P5'], rooms: ['PJ-208'], faculty: ['CSE-LS'], batches: []}
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


// 3E4 [3T] - 24 sessions

UNWIND [
  {id: 'CSE-UG-2026-27-S3-3E4-26CS3IPDST-P-B-MON-P1', name: 'DS Lab', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3IPDST', type: 'P', slots: ['B-MON-P1', 'B-MON-P2'], rooms: ['PJ-LAB401'], faculty: ['CSE-NNM', 'CSE-SS', 'CSE-AHV', 'CSE-TFS'], batches: ['CSE-UG-2026-27-S3-3E4-26CS3IPDST-B1', 'CSE-UG-2026-27-S3-3E4-26CS3IPDST-B2', 'CSE-UG-2026-27-S3-3E4-26CS3IPDST-B3', 'CSE-UG-2026-27-S3-3E4-26CS3IPDST-B4']},
  {id: 'CSE-UG-2026-27-S3-3E4-26CS3IPDST-L-B-MON-P3', name: 'DS', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3IPDST', type: 'L', slots: ['B-MON-P3'], rooms: ['PJ-220'], faculty: ['CSE-NNM'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM-L-B-MON-P4', name: 'DBMS', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM', type: 'L', slots: ['B-MON-P4'], rooms: ['PJ-220'], faculty: ['CSE-NAS'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP-L-B-MON-P5', name: 'OOP', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP', type: 'L', slots: ['B-MON-P5'], rooms: ['PJ-220'], faculty: ['CSE-BVK'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-26MA3BSDMS-L-B-MON-P6', name: 'DMS', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26MA3BSDMS', type: 'L', slots: ['B-MON-P6'], rooms: ['PJ-408'], faculty: ['MA-LHA'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-26MA3BSDMS-T-B-TUE-P1', name: 'DMS Tutorial', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26MA3BSDMS', type: 'T', slots: ['B-TUE-P1', 'B-TUE-P2'], rooms: ['PJ-406'], faculty: ['MA-LHA'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-26CS3PCDLC-L-B-TUE-P3', name: 'DLC', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3PCDLC', type: 'L', slots: ['B-TUE-P3'], rooms: ['PJ-408'], faculty: ['CSE-SLR'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM-P-B-TUE-P4', name: 'DBMS Lab', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM', type: 'P', slots: ['B-TUE-P4', 'B-TUE-P5'], rooms: ['OTHER-BSN-PG-LAB'], faculty: ['CSE-NAS', 'CSE-MHM', 'CSE-AB', 'CSE-LS'], batches: ['CSE-UG-2026-27-S3-3E4-26CS3IPDBM-B1', 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM-B2', 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM-B3', 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM-B4']},
  {id: 'CSE-UG-2026-27-S3-3E4-A-B-WED-P2', name: 'Seminar / Workshop / Proctor Meet', section: 'CSE-UG-2026-27-S3-3E4', allot: null, type: 'A', slots: ['B-WED-P2'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-26CS3IPDST-L-B-WED-P3', name: 'DS', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3IPDST', type: 'L', slots: ['B-WED-P3'], rooms: ['PJ-408'], faculty: ['CSE-NNM'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-26CS3PCDLC-L-B-WED-P4', name: 'DLC', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3PCDLC', type: 'L', slots: ['B-WED-P4'], rooms: ['PJ-408'], faculty: ['CSE-SLR'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM-L-B-WED-P5', name: 'DBMS', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM', type: 'L', slots: ['B-WED-P5'], rooms: ['PJ-408'], faculty: ['CSE-NAS'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-A-B-WED-P8', name: 'DIP-MATH (B)', section: 'CSE-UG-2026-27-S3-3E4', allot: null, type: 'A', slots: ['B-WED-P8'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-26MA3BSDMS-L-B-THU-P2', name: 'DMS', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26MA3BSDMS', type: 'L', slots: ['B-THU-P2'], rooms: ['PJ-213'], faculty: ['MA-LHA'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP-L-B-THU-P3', name: 'OOP', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP', type: 'L', slots: ['B-THU-P3'], rooms: ['PJ-407'], faculty: ['CSE-BVK'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-26CS3AEFSD-P-B-THU-P4', name: 'FSD Lab', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3AEFSD', type: 'P', slots: ['B-THU-P4', 'B-THU-P5'], rooms: ['PJ-LAB401'], faculty: ['CSE-BVK', 'CSE-ASG', 'CSE-RKB', 'CSE-ADI'], batches: ['CSE-UG-2026-27-S3-3E4-26CS3AEFSD-B1', 'CSE-UG-2026-27-S3-3E4-26CS3AEFSD-B2', 'CSE-UG-2026-27-S3-3E4-26CS3AEFSD-B3', 'CSE-UG-2026-27-S3-3E4-26CS3AEFSD-B4']},
  {id: 'CSE-UG-2026-27-S3-3E4-A-B-THU-P8', name: 'DIP-MATH (B)', section: 'CSE-UG-2026-27-S3-3E4', allot: null, type: 'A', slots: ['B-THU-P8'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM-L-B-FRI-P2', name: 'DBMS', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3IPDBM', type: 'L', slots: ['B-FRI-P2'], rooms: ['PJ-220'], faculty: ['CSE-NAS'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-26CS3IPDST-L-B-FRI-P3', name: 'DS', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3IPDST', type: 'L', slots: ['B-FRI-P3'], rooms: ['PJ-406'], faculty: ['CSE-NNM'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-26MA3BSDMS-L-B-FRI-P4', name: 'DMS', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26MA3BSDMS', type: 'L', slots: ['B-FRI-P4'], rooms: ['PJ-406'], faculty: ['MA-LHA'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-26CS3PCDLC-L-B-FRI-P5', name: 'DLC', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3PCDLC', type: 'L', slots: ['B-FRI-P5'], rooms: ['PJ-406'], faculty: ['CSE-SLR'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-A-B-FRI-P8', name: 'DIP-MATH (B)', section: 'CSE-UG-2026-27-S3-3E4', allot: null, type: 'A', slots: ['B-FRI-P8'], rooms: [], faculty: [], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP-L-B-SAT-P3', name: 'OOP', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP', type: 'L', slots: ['B-SAT-P3'], rooms: ['PJ-406'], faculty: ['CSE-BVK'], batches: []},
  {id: 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP-P-B-SAT-P4', name: 'OOP Lab', section: 'CSE-UG-2026-27-S3-3E4', allot: 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP', type: 'P', slots: ['B-SAT-P4', 'B-SAT-P5'], rooms: ['PJ-4F-LAB1'], faculty: ['CSE-BVK', 'CSE-SMR', 'CSE-SAH', 'CSE-NNM'], batches: ['CSE-UG-2026-27-S3-3E4-26CS3PCOOP-B1', 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP-B2', 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP-B3', 'CSE-UG-2026-27-S3-3E4-26CS3PCOOP-B4']}
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
