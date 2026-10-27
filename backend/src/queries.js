// Reads the query files once at start-up. Each query is tagged "// @name: something".
//   neo4j/05_app_queries.cypher    read-only queries of the screens  -> Q
//   neo4j/06_edit_queries.cypher   changes made from the Add data tab -> E
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

function load(fileName, required) {
  const file = path.resolve(here, '../../neo4j', fileName);
  const out = {};
  for (const block of fs.readFileSync(file, 'utf8').split(/\n(?=\/\/ @name:)/)) {
    const m = block.match(/^\/\/ @name: (\w+)/);
    if (!m) continue;
    out[m[1]] = block.split('\n').filter((line) => !line.trim().startsWith('//')).join('\n').trim().replace(/;$/, '');
  }
  const missing = required.filter((name) => !out[name]);
  if (missing.length) throw new Error(`Query file ${file} is missing: ${missing.join(', ')}`);
  return out;
}

export const Q = load('05_app_queries.cypher', [
  'meta_rooms', 'meta_sections', 'meta_faculty', 'meta_periods', 'search',
  'floor_occupancy', 'floor_day_grid', 'free_rooms', 'room_week',
  'section_week', 'section_free_time', 'section_free_with_rooms', 'course_summary',
  'faculty_week', 'faculty_free_time'
]);

export const E = load('06_edit_queries.cypher', [
  'courses', 'save_room', 'save_faculty', 'save_course', 'save_section', 'set_teacher',
  'class_lookup', 'class_clashes', 'class_create',
  'remove_class', 'remove_room', 'remove_faculty', 'remove_course', 'remove_section', 'remove_empty_places'
]);
