# BMSCE Timetable Finder

Search the college timetable: which rooms are free, which section is where, and when a section or faculty member is free.

```
start_timetable_finder.bat   double-click to start everything
frontend/                    the web page (HTML, CSS, JavaScript - no build step)
backend/                     the API (Node.js + Express) that reads Neo4j; it also serves the page
neo4j/                       the database scripts: schema, cluster E data (3rd and 5th semester), queries
local-neo4j/                 the project's own Neo4j database (Neo4j Community 5.26, data already loaded)
```

## Start it

Double-click **`start_timetable_finder.bat`** (or the **Timetable Finder** shortcut on the Desktop).

It starts the database, then the backend, then opens **http://localhost:3100**. The first start takes about a minute. Two windows stay open while you use the page: **Timetable Finder database** and **Timetable Finder** (the server). To stop, close both windows or press `Ctrl + C` in them.

You need **Node.js 20 or newer** (`node --version`) and **Java 21**, which comes with Neo4j Desktop.

## Add or change data on the page

The **Add data** tab has forms for:

- **Timetable class**: put a lecture, tutorial, lab or activity in a section's week, or remove one. Room and faculty are drop-down lists; use **+ Add another** when a lab has several rooms or teachers.
- **Room**, **Faculty**, **Course**, **Section**: add these, or change one that already exists.
- **Course teacher**: set who teaches a section's course.
- **Remove**: delete a room, faculty member, course or section that nothing uses any more.

Each form also creates the links the other screens need. For example, a new course is given to every section of its semester, with the classes it needs worked out from its L-T-P. A class is only saved when the section, every chosen room and every chosen faculty member are free in all its periods; otherwise the page lists each clash. Changes are saved in Neo4j at once and show on every tab.

- The page has no login, so changes are only accepted on the computer that runs the server, and only from this page. Other devices (with `HOST=0.0.0.0`) can look but not change anything.
- `npm run load-data` puts sections 3E1-3E4 and 5E1-5E4 back exactly as the spreadsheets have them. Classes you added to those sections are then lost; everything else you added stays.
- After changing data, `npm run export-snapshot` updates the offline copy (`frontend/data.js`).

## Two bell schedules

The 5th semester sections (5E1-5E4) follow **schedule A** (tea 10:45-11:15, lunch 14:00-14:55, nine periods). The 3rd semester sections (3E1-3E4) follow **schedule B** (tea 09:50-10:20, lunch 13:05-14:00, eight periods), as in their timetables.

- A section's own screens always use its schedule.
- **Floors, Free rooms, Rooms and Faculty** have a **Schedule** drop-down, because rooms and teachers are shared between the semesters. A class from the other schedule is placed in the periods it shares time with, so a room used at 10:20 by a 3rd semester class is busy in schedule A's 09:50-10:45 period too. A class that falls in a break of the schedule you look at (for example in schedule B's lunch) is only in the list below the grid, and a note says so.
- Clash checks (Add data, `04_queries.cypher` number 12) look across both schedules.

## The database and its login

The backend reads the database named in **`backend/.env`**, and logs in with the user and password there. That file is the only place the password is kept: do not share it, and do not put it in Git (`.gitignore` already keeps it out).

The project's own database (`local-neo4j/`) requires a login and only accepts connections from this computer. Its password was generated at random and stored in `backend/.env`.

**To see the graph in Neo4j Browser:** while the database is running, open http://localhost:17474, choose *Username / Password* and enter the `NEO4J_USER` and `NEO4J_PASSWORD` from `backend/.env`. Try `CALL db.schema.visualization()` or the queries in `neo4j/04_queries.cypher`.

### Use Neo4j Desktop or Neo4j Aura instead

1. Start your database (Desktop: press *Start* on the instance; Aura: it is always on).
2. In `backend/.env` change `NEO4J_URI`, `NEO4J_USER` and `NEO4J_PASSWORD` (the comments in `backend/.env.example` show the address formats). Your earlier Desktop settings are kept in `backend/.env.neo4j-desktop`.
3. Load the timetable into it once:

   ```powershell
   cd "C:\Users\dell\Desktop\project k\backend"
   npm run load-data
   ```

4. Double-click `start_timetable_finder.bat`. It only starts the project's own database when `NEO4J_URI` points at it (port 17687).

## If something is wrong

| You see | Cause and fix |
|---|---|
| "Cannot reach the Neo4j database" | The database is not running. Close the windows and start `start_timetable_finder.bat` again, or start your Desktop instance |
| "The database refused the login" | `NEO4J_USER` / `NEO4J_PASSWORD` in `backend/.env` do not match the database |
| "holds no timetable yet" | The database is empty. Run `npm run load-data` in the `backend` folder |
| "Cannot reach the Timetable Finder server" | The server window was closed. Start `start_timetable_finder.bat` again |
| "Port 3100 is already used by another program" | Set `PORT=3101` in `backend/.env` and open http://localhost:3101 |
| The database window says Java is missing or the wrong version | Install Neo4j Desktop (it brings Java 21), or install Java 21 and set `JAVA_HOME` |
| Badge says **Snapshot data** | You opened `frontend/index.html` directly. Use http://localhost:3100 for live data |

## Commands (in the `backend` folder)

| Command | What it does |
|---|---|
| `npm start` | Starts the server only (the database must already be running) |
| `npm test` | Checks every endpoint against the data, bad input, the read-only connection, the page's security headers and the Add data forms (with test data it removes again). Needs the database running |
| `npm run load-data` | Loads `neo4j/01_schema.cypher` and the two timetables `02_cluster_E_sem5.cypher`, `02_cluster_E_sem3.cypher` into the database in `.env`. Safe to repeat |
| `npm run export-snapshot` | Rewrites `frontend/data.js`, the copy the page shows when opened without the server |

To show the page on other devices in your network, add `HOST=0.0.0.0` to `backend/.env`. The page itself has no login, so only do this on a network you trust.

## What is where

| File | What it is |
|---|---|
| `neo4j/01_schema.cypher` | Schema, L-T-P rules, weekly periods, class allotment |
| `neo4j/02_cluster_E_sem5.cypher` | Cluster E, semester 5: 4 sections, courses, faculty, rooms, 80 classes (from `cluster_E_timetable_dataset.xlsx`) |
| `neo4j/02_cluster_E_sem3.cypher` | Cluster E, semester 3: 4 sections, courses, faculty, rooms, 96 classes (from `Cluster_E_3rd_Sem_Timetable_Extracted.xlsx`) |
| `neo4j/03_load_students.cypher` | How to link 10,000+ students after importing a CSV (not needed for the page) |
| `neo4j/04_queries.cypher` | Queries to run by hand in Neo4j Browser: free time, free rooms, clashes, L-T-P check |
| `neo4j/05_app_queries.cypher` | The 15 read-only queries behind the screens |
| `neo4j/06_edit_queries.cypher` | The queries behind the Add data tab (add, change, remove, clash check) |
| `neo4j/07_auto_allot.cypher` | Optional: places classes that are still missing, from each course's L-T-P (run by hand in Neo4j Browser) |
| `neo4j/tools/build_cluster_E_sem5_cypher.py`, `build_cluster_E_sem3_cypher.py` | Turn the spreadsheets into the two `02_*` files (`pip install openpyxl` first). `timetable_common.py` holds what they share. Every assumption they make is written at the top of the `.cypher` file |
| `neo4j/01_schema_graph.pdf`, `neo4j/class_diagram.*` | Pictures of the schema |
| `backend/src/` | `server.js` (start), `app.js` (page and security headers), `routes.js` (the 15 read endpoints), `edit.js` (the Add data endpoints and who may use them), `db.js` (login, read-only queries, write transactions), `validate.js`, `queries.js` |
| `backend/scripts/` | `load-data.js`, `export-snapshot.js` |
