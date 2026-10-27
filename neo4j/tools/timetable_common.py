"""Shared parts of the timetable generators (build_cluster_E_sem5_cypher.py, build_cluster_E_sem3_cypher.py).

Each generator reads its own spreadsheet layout into the structures documented in write_cypher(),
and this module turns them into a .cypher file that loads after 01_schema.cypher.
Every decision that goes beyond what a sheet literally says is collected with note() and written
into the header of the .cypher file.
"""
import os
import re
import sys
from collections import OrderedDict

DAYS = {"Monday": "MON", "Tuesday": "TUE", "Wednesday": "WED", "Thursday": "THU", "Friday": "FRI", "Saturday": "SAT"}

# Bell schedules. 01_schema.cypher creates the same periods: keep both the same.
GRIDS = {
    # tea 10:45-11:15, lunch 14:00-14:55
    "A": [(1, "08:00", "08:55"), (2, "08:55", "09:50"), (3, "09:50", "10:45"), (4, "11:15", "12:10"), (5, "12:10", "13:05"),
          (6, "13:05", "14:00"), (7, "14:55", "15:50"), (8, "15:50", "16:45"), (9, "16:45", "17:40")],
    # tea 09:50-10:20, lunch 13:05-14:00
    "B": [(1, "08:00", "08:55"), (2, "08:55", "09:50"), (3, "10:20", "11:15"), (4, "11:15", "12:10"), (5, "12:10", "13:05"),
          (6, "14:00", "14:55"), (7, "14:55", "15:50"), (8, "15:50", "16:45")],
}


def lit(v):
    """A Python value as a Cypher literal."""
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, (list, tuple)):
        return "[" + ", ".join(lit(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ", ".join(f"{k}: {lit(x)}" for k, x in v.items()) + "}"
    return "'" + str(v).replace("\\", "\\\\").replace("'", "\\'") + "'"


def to24(t):
    """'1:05' -> '13:05', '8:00' -> '08:00'. Classes run from 08:00, so an hour below 8 is in the afternoon."""
    h, m = str(t).strip().split(":")
    h = int(h)
    return f"{h + 12 if h < 8 else h:02d}:{m}"


class Builder:
    def __init__(self):
        self.notes = []
        self.rooms = OrderedDict()   # room id -> dict(number, floor, type, building)

    def note(self, text):
        if text not in self.notes:
            self.notes.append(text)

    # ------------------------------------------------------------- periods
    def slots(self, grid, day, start, end, what):
        """Ids of the periods of grid that a session from start to end (HH:MM) on day covers."""
        periods = GRIDS[grid]
        covered = [p for p in periods if start <= p[1] and p[2] <= end]
        if not covered or covered[0][1] != start:
            sys.exit(f"{what} on {day} {start}-{end} does not start on a period of grid {grid}")
        for a, b in zip(covered, covered[1:]):
            if a[2] != b[1]:
                sys.exit(f"{what} on {day} {start}-{end} runs across a break")
        if covered[-1][2] != end:
            if any(covered[-1][2] < p[1] < end for p in periods):
                sys.exit(f"{what} on {day} {start}-{end} does not end on a period of grid {grid}")
            self.note(f"{what} on {day} is written as {start}-{end}, which runs into the break after "
                      f"{covered[-1][2]}; it is stored as {covered[0][1]}-{covered[-1][2]}.")
        # grid A keeps the plain ids MON-P1; other grids add their letter (B-MON-P1)
        return [("" if grid == "A" else grid + "-") + f"{day}-P{p[0]}" for p in covered]

    # ------------------------------------------------------------- rooms
    def room_ids(self, raw):
        """Room ids for a room cell such as '406', 'LAB 503,504' or '4F LAB 1-2'. Same rules for every file."""
        names = [x.strip() for x in str(raw).split(",")]
        if len(names) > 1:
            prefix = re.sub(r"\d+$", "", names[0])
            names = [names[0]] + [(prefix + n) if re.fullmatch(r"\d+", n) else n for n in names[1:]]
            self.note(f"'{raw}' is read as {len(names)} separate rooms ({', '.join(names)}); the class is linked to each of them.")
        out = []
        for n in names:
            if re.fullmatch(r"\d{3}", n):
                rid, info = f"PJ-{n}", dict(number=n, floor=int(n[0]), type="CLASSROOM", building="PJ")
            elif re.fullmatch(r"LAB \d{3}", n):
                rid, info = "PJ-" + n.replace(" ", ""), dict(number=n, floor=int(n[4]), type="LAB", building="PJ")
            elif re.fullmatch(r"4F LAB [\d-]+", n):
                rid, info = "PJ-" + n.replace(" ", "-").replace("4F-LAB-", "4F-LAB"), dict(number=n, floor=4, type="LAB", building="PJ")
                if "-" in n.split("LAB ")[1]:
                    self.note(f"'{n}' is kept as ONE room exactly as written. If it means 4F LAB 1 and 4F LAB 2 together, "
                              "it overlaps the use of 4F LAB 1 by other sections.")
            else:
                rid = "OTHER-" + re.sub(r"[^A-Za-z0-9]+", "-", n).strip("-")
                info = dict(number=n, floor=0, type="LAB", building="OTHER")
                self.note(f"Room '{n}': block, floor and type are not given. Placed in a block called OTHER (floor 0) as a LAB, "
                          "because a lab session is held there. Correct this if you know where it is.")
            self.rooms.setdefault(rid, info)
            out.append(rid)
        return out


def write_cypher(out_path, b, *, header, dept, program, year, sem, term, cluster, grid, sections, wef,
                 courses, faculty, allots, batches, classes, departments=(), remove_courses=(), remove_sections=()):
    """Writes the .cypher file.

    b            the Builder (notes and rooms)
    header       lines describing the source, written at the top
    sections     OrderedDict name -> section code
    wef          'YYYY-MM-DD'
    courses      OrderedDict code -> dict(code, name, short, category, ltp, scheduling)
    faculty      OrderedDict faculty id -> dict(initials, name or None, dept, cluster: bool)
    allots       list of dict(id, section, course, teacher faculty id or None)
    batches      list of dict(id, allot, name, faculty, type)
    classes      OrderedDict section name -> list of dict(id, name, section, allot, type, slots, rooms, faculty, batches)
    departments  extra departments as (id, name), for faculty of other departments
    """
    sem_id = f"{dept}-{program}-{year}-S{sem}"
    cluster_id = f"{dept}-{cluster}"
    sec_id = lambda s: f"{sem_id}-{s}"
    ids = [sec_id(s) for s in sections] + [sec_id(s) for s in remove_sections]
    out = []
    w = out.append

    w("// =====================================================================")
    for line in header:
        w("// " + line if line else "//")
    w("//")
    w("// Run after 01_schema.cypher. All data files are loaded by:  cd backend  then  npm run load-data")
    w("//")
    w("// Block 0 is a clean-up. It deletes the classes, lab batches and allotments of the")
    w("// sections below, so that data loaded by an earlier version of this file cannot mix")
    w("// with this one. On an empty database it does nothing. Everything else uses MERGE")
    w("// and is safe to re-run.")
    w("//")
    w("// Decisions beyond what the sheets say:")
    for n in b.notes:
        w("//   - " + n)
    w("// =====================================================================\n")

    w(f"""
// ---------- 0. Clean-up of what this file replaces ----------

MATCH (cl:Class)-[:FOR_SECTION]->(s:Section)
WHERE s.id IN {lit(ids)}
DETACH DELETE cl;

MATCH (s:Section)-[:HAS_ALLOTMENT]->(a:Allotment)
WHERE s.id IN {lit(ids)}
OPTIONAL MATCH (a)-[:HAS_BATCH]->(b:Batch)
DETACH DELETE b, a;
""")
    if remove_courses:
        w(f"MATCH (c:Course)\nWHERE c.code IN {lit(list(remove_courses))}\nDETACH DELETE c;\n")
    for s in remove_sections:
        w(f"MATCH (s:Section {{id: {lit(sec_id(s))}}})\nDETACH DELETE s;\n")

    w(f"""
// ---------- 1. College > Department > Program > Year > Semester > Cluster ----------

MERGE (col:College {{id:'BMSCE'}})
  SET col.name = 'B.M.S. College of Engineering', col.city = 'Bengaluru'
MERGE (d:Department {{id:{lit(dept)}}})
  SET d.name = 'Computer Science and Engineering'
MERGE (col)-[:HAS_DEPARTMENT]->(d)
MERGE (p:Program {{id:{lit(dept + '-' + program)}}})
  SET p.name = {lit(program)}, p.degree = 'B.E.'
MERGE (d)-[:OFFERS]->(p)
MERGE (ay:AcademicYear {{id:{lit(dept + '-' + program + '-' + year)}}})
  SET ay.year = {lit(year)}
MERGE (p)-[:HAS_ACADEMIC_YEAR]->(ay)
MERGE (sem:Semester {{id:{lit(sem_id)}}})
  SET sem.number = {sem}, sem.term = {lit(term)}
MERGE (ay)-[:HAS_SEMESTER]->(sem)
MERGE (fc:FacultyCluster {{id:{lit(cluster_id)}}})
  SET fc.name = {lit(cluster)}
MERGE (d)-[:HAS_FACULTY_CLUSTER]->(fc);
""")
    if departments:
        w("MATCH (col:College {id:'BMSCE'})\nUNWIND " + lit([list(d) for d in departments]) + " AS x\n"
          "MERGE (d:Department {id: x[0]})\n  SET d.name = x[1]\nMERGE (col)-[:HAS_DEPARTMENT]->(d);\n")

    w(f"""
// ---------- 2. Sections, and the bell schedule (time grid) they follow ----------

MATCH (sem:Semester {{id:{lit(sem_id)}}}), (fc:FacultyCluster {{id:{lit(cluster_id)}}}), (g:TimeGrid {{id:{lit(grid)}}})
UNWIND {lit([[sec_id(n), n, c] for n, c in sections.items()])} AS s
MERGE (sec:Section {{id: s[0]}})
  SET sec.name = s[1], sec.code = s[2], sec.wef = date({lit(wef)})
MERGE (sem)-[:HAS_SECTION]->(sec)
MERGE (fc)-[:HAS_SECTION]->(sec)
WITH sec, g
OPTIONAL MATCH (sec)-[old:FOLLOWS]->(other:TimeGrid) WHERE other <> g
DELETE old
WITH DISTINCT sec, g
MERGE (sec)-[:FOLLOWS]->(g);
""")

    w("\n// ---------- 3. Blocks, floors and rooms ----------\n"
      "// Rooms that already exist keep their ids, so every file links to the same rooms.\n")
    blocks = sorted({r["building"] for r in b.rooms.values()})
    w("MATCH (col:College {id:'BMSCE'})\nUNWIND " + lit([[x, "PJ" if x == "PJ" else "Location not given"] for x in blocks]) + " AS b\n"
      "MERGE (bl:Building {id: b[0]})\n  SET bl.name = b[1]\nMERGE (col)-[:HAS_BUILDING]->(bl);\n")
    w("UNWIND " + lit([[r["building"], f"{r['building']}-F{r['floor']}", r["floor"], rid, r["number"], r["type"]] for rid, r in b.rooms.items()]) + " AS r\n"
      "MATCH (bl:Building {id: r[0]})\n"
      "MERGE (fl:Floor {id: r[1]})\n  SET fl.number = r[2]\nMERGE (bl)-[:HAS_FLOOR]->(fl)\n"
      "MERGE (room:Room {id: r[3]})\n  SET room.number = r[4], room.type = r[5]\nMERGE (fl)-[:HAS_ROOM]->(room);\n")

    w("\n// ---------- 4. Courses with their L-T-P ----------\n")
    w(f"MATCH (sem:Semester {{id:{lit(sem_id)}}})\nUNWIND "
      + lit([[c["code"], c["name"], c["short"], c["category"], c["ltp"], c["scheduling"]] for c in courses.values()]) + " AS c\n"
      "WITH sem, c, [x IN split(c[4], '-') | toInteger(x)] AS ltp\n"
      "MERGE (course:Course {code: c[0]})\n"
      "  SET course.name = c[1], course.short = c[2], course.category = c[3], course.LTP = c[4],\n"
      "      course.credits = ltp[0] + ltp[1] + ltp[2], course.scheduling = c[5]\n"
      "MERGE (sem)-[:HAS_COURSE]->(course);\n")
    w("UNWIND " + lit([[c["code"], c["ltp"]] for c in courses.values()]) + " AS c\n"
      "MATCH (course:Course {code: c[0]})\n"
      "WITH course, [x IN split(c[1], '-') | toInteger(x)] AS ltp\n"
      "UNWIND [['L', ltp[0]], ['T', ltp[1]], ['P', ltp[2]]] AS part\n"
      "WITH course, part WHERE part[1] > 0\n"
      "MATCH (l:LTP {code: part[0]})\n"
      "MERGE (course)-[r:HAS_LTP]->(l)\n"
      "  SET r.credits = part[1], r.periodsPerWeek = part[1] * l.periodsPerCredit,\n"
      "      r.classesPerWeek = part[1] * l.periodsPerCredit / l.periodsPerClass;\n")

    w("\n// ---------- 5. Faculty (initials only where the file gives no name) ----------\n")
    w("UNWIND " + lit([[fid, f["initials"], f["name"], f["dept"], f["cluster"]] for fid, f in faculty.items()]) + " AS f\n"
      "MATCH (d:Department {id: f[3]})\n"
      "MERGE (fac:Faculty {id: f[0]})\n"
      "  SET fac.initials = f[1], fac.name = coalesce(f[2], fac.name, f[1])\n"
      "MERGE (fac)-[:WORKS_IN]->(d)\n"
      f"WITH fac, f WHERE f[4]\nMATCH (fc:FacultyCluster {{id:{lit(cluster_id)}}})\n"
      "MERGE (fc)-[:HAS_FACULTY]->(fac);\n")

    w("\n// ---------- 6. Allotments: every course of the semester given to every section, with its teacher ----------\n")
    w("UNWIND " + lit([dict(id=a["id"], section=a["section"], course=a["course"], teacher=a["teacher"]) for a in allots]) + " AS x\n"
      "MATCH (sec:Section {id: x.section}), (c:Course {code: x.course})\n"
      "MERGE (a:Allotment {id: x.id})\nMERGE (sec)-[:HAS_ALLOTMENT]->(a)\nMERGE (a)-[:OF_COURSE]->(c)\n"
      "WITH a, x\nOPTIONAL MATCH (f:Faculty {id: x.teacher})\n"
      "FOREACH (_ IN CASE WHEN f IS NULL THEN [] ELSE [1] END |\n"
      "  MERGE (f)-[r:TEACHES]->(a)\n    SET r.role = 'COURSE_TEACHER');\n")

    w("\n// ---------- 7. Lab batches and the faculty of each batch ----------\n")
    w("UNWIND " + lit([dict(id=x["id"], allot=x["allot"], name=x["name"], faculty=x["faculty"], type=x["type"]) for x in batches]) + " AS x\n"
      "MATCH (a:Allotment {id: x.allot}), (f:Faculty {id: x.faculty})\n"
      "MERGE (b:Batch {id: x.id})\n  SET b.name = x.name, b.type = x.type\n"
      "MERGE (a)-[:HAS_BATCH]->(b)\nMERGE (b)-[:ASSIGNED_TO]->(f);\n")

    w("\n// ---------- 8. Classes: lectures, tutorials, labs, elective slots and activities ----------\n"
      f"// type: L lecture, T tutorial, P lab, A activity. Periods are of time grid {grid}.\n"
      "// A lab is taken by every batch with its own faculty.\n")
    for sec, items in classes.items():
        w(f"\n// {sec} [{sections[sec]}] - {len(items)} sessions\n")
        w("UNWIND [\n" + ",\n".join("  " + lit(i) for i in items) + "\n] AS x\n"
          "MATCH (sec:Section {id: x.section}), (lt:LTP {code: x.type})\n"
          "MERGE (cl:Class {id: x.id})\n  SET cl.name = x.name\n"
          "MERGE (cl)-[:OF_TYPE]->(lt)\nMERGE (cl)-[:FOR_SECTION]->(sec)\n"
          "WITH x, cl\nOPTIONAL MATCH (a:Allotment {id: x.allot})\n"
          "FOREACH (_ IN CASE WHEN a IS NULL THEN [] ELSE [1] END | MERGE (a)-[:HAS_CLASS]->(cl))\n"
          "WITH x, cl\n"
          "CALL (x, cl) { UNWIND x.slots AS s MATCH (t:TimeSlot {id: s}) MERGE (cl)-[:AT_TIME]->(t) }\n"
          "CALL (x, cl) { UNWIND x.rooms AS r MATCH (rm:Room {id: r}) MERGE (cl)-[:IN_ROOM]->(rm) }\n"
          "CALL (x, cl) { UNWIND x.faculty AS f MATCH (fa:Faculty {id: f}) MERGE (cl)-[:TAUGHT_BY]->(fa) }\n"
          "CALL (x, cl) { UNWIND x.batches AS b MATCH (bt:Batch {id: b}) MERGE (cl)-[:FOR_BATCH]->(bt) };\n")

    text = "\n".join(out)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(text)

    n_classes = sum(len(v) for v in classes.values())
    print(f"wrote {os.path.normpath(out_path)}  ({len(text):,} characters)")
    print(f"sections {len(sections)}, courses {len(courses)}, faculty {len(faculty)}, rooms {len(b.rooms)}, "
          f"allotments {len(allots)}, batches {len(batches)}, classes {n_classes}")
    print("\nrooms:")
    for rid, r in b.rooms.items():
        print(f"  {rid:18} {r['number']:12} {r['type']:9} block {r['building']} floor {r['floor']}")
    print("\nassumptions:")
    for n in b.notes:
        print("  -", n)
