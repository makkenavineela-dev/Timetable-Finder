// =====================================================================
// Students (10,000+) on Neo4j Aura
//
// Aura cannot read files from your computer with LOAD CSV, so the CSV goes
// in through the Import tool first, then this file links the students.
//
// students.csv columns:
//   usn,name,email,admissionYear,sectionId,labBatch,projectBatch,electiveCode
//   sectionId    = section id, for example CSE-UG-2026-27-S5-5E4
//   labBatch     = B1..B4, linked to that batch in every lab course of the section
//   projectBatch = B1..B8 mini-project batch
//   electiveCode = code of the PE course the student chose (leave empty if none)
//
// Step 1 - Aura console > Import: upload students.csv, map it to the node
//          label Student, set usn as the ID, keep every column as a
//          property, then run the import.
// Step 2 - run the statement below in Query. It links every imported student
//          and then removes the helper columns. Safe to re-run.
//
// Students that still have a sectionId afterwards did not match any section.
// Find them with:  MATCH (s:Student) WHERE s.sectionId IS NOT NULL RETURN s
// For a very large file, add a STARTS WITH filter on s.sectionId to the
// WHERE line and run it one department at a time.
// =====================================================================

MATCH (s:Student)
WHERE s.sectionId IS NOT NULL
MATCH (sec:Section {id: s.sectionId})
MERGE (s)-[:IN_SECTION]->(sec)
WITH s, sec
OPTIONAL MATCH (sec)-[:HAS_ALLOTMENT]->(:Allotment)-[:HAS_BATCH]->(lb:Batch {type:'LAB', name: s.labBatch})
FOREACH (_ IN CASE WHEN lb IS NULL THEN [] ELSE [1] END | MERGE (s)-[:IN_BATCH]->(lb))
WITH DISTINCT s, sec
OPTIONAL MATCH (sec)-[:HAS_ALLOTMENT]->(:Allotment)-[:HAS_BATCH]->(pb:Batch {type:'PROJECT', name: s.projectBatch})
FOREACH (_ IN CASE WHEN pb IS NULL THEN [] ELSE [1] END | MERGE (s)-[:IN_BATCH]->(pb))
WITH DISTINCT s
OPTIONAL MATCH (e:Course {code: s.electiveCode})
FOREACH (_ IN CASE WHEN e IS NULL THEN [] ELSE [1] END | MERGE (s)-[:ENROLLED_IN]->(e))
WITH DISTINCT s
SET s.admissionYear = toInteger(s.admissionYear)
REMOVE s.sectionId, s.labBatch, s.projectBatch, s.electiveCode;
