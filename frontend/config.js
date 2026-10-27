// Timetable Finder settings.
//
// API_URL empty  -> the page shows the snapshot in data.js (no backend needed). This file is used then.
// API_URL filled -> the page reads live data from a backend, for example "http://localhost:3100".
// When the backend serves the page (http://localhost:3100) it replaces this file with one that
// points at itself, so there is nothing to change here for normal use.
window.TT_CONFIG = {
  API_URL: ""
};
