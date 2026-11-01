# Timetable Finder - frontend

A plain HTML + CSS + JavaScript page (no install, no build step). For starting the whole app see the README in the project folder.

## Screens

| Tab | What you can do |
|---|---|
| Floors | Pick block, floor, schedule, day and period: every room is **free** or **occupied by a named section**, plus a rooms x periods grid for the day |
| Free rooms | Find free rooms by block, floor, room type, schedule, day and period |
| Sections | Pick **Branch, Semester, Cluster, Section** (a Year dropdown appears once more than one academic year exists), then see the week timetable with free periods in green, free-time summary, free classrooms for each free period, course list with L-T-P |
| Faculty | Week timetable and free time of one faculty member, in the schedule you pick |
| Rooms | Pick **Block, Floor, Room** (and schedule), then see which section uses the room and when |
| Add data | Forms to add or change classes, rooms, faculty, courses, sections and course teachers, and to remove them. Needs the backend; only works on the computer that runs it |

The **Day / Night mode** button (top right) switches the colours. Until you press it the page follows your system setting; after that it remembers your choice in this browser.

The search box (top) finds sections, rooms, faculty and blocks. Every filter is kept in the web address, so a result can be shared as a link.

## Where the data comes from

The screens only talk to `window.TT_API` (`api.js`). It has two versions that return the same rows:

- **Live** - asks the backend. This is used when the page is opened from the backend at http://localhost:3100 (the backend then hands the page a `config.js` that points at itself).
- **Snapshot** - answers from `data.js`, a copy of the database. This is used when `index.html` is opened directly from the folder, so the page also works without a server. The badge at the top says which one you are looking at.

`npm test` in the backend checks that both versions give the same answers.

`data.js` is generated. After the data in Neo4j changes, refresh it with `npm run export-snapshot` in the `backend` folder.

A section whose code is `SAMPLE` in the database is shown as "(sample)" on screen; there is none in the current data.

## Files

| File | Purpose |
|---|---|
| `index.html` | The page |
| `style.css` | Look, light and dark colours (chosen by `data-theme`), phone layout |
| `theme.js` | Day / Night button: loads first, sets the colours before the page is drawn, remembers the choice |
| `app.js` | The five screens, search and filters |
| `edit.js` | The Add data tab (loaded before `app.js`, which draws it) |
| `api.js` | Data layer (backend or snapshot) |
| `config.js` | `API_URL`, used only when the page is opened without the backend |
| `data.js` | Data snapshot (generated) |
