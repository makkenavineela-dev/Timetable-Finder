// Every value that comes from the address is checked here before it reaches a query.
export class HttpError extends Error {
  // details: optional list of lines shown under the message (for example every clash found)
  constructor(status, message, details) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

const bad = (message) => new HttpError(400, message);

const DAY = /^(MON|TUE|WED|THU|FRI|SAT)$/;
const SLOT = /^([A-Z]-)?(MON|TUE|WED|THU|FRI|SAT)-P[1-9]$/;   // MON-P4 (schedule A), B-MON-P4 (schedule B)
const GRID = /^[A-Z]$/;
const ID = /^[A-Za-z0-9._-]{1,80}$/;
const ROOM_TYPES = ['CLASSROOM', 'LAB'];

const one = (value) => (Array.isArray(value) ? value[0] : value);  // ?a=1&a=2 gives an array
const empty = (value) => value === undefined || value === null || value === '';

export function id(value, name = 'id') {
  const v = one(value);
  if (typeof v !== 'string' || !ID.test(v)) throw bad(`Invalid ${name}`);
  return v;
}
export function optionalId(value, name) {
  return empty(value) ? null : id(value, name);
}
export function slot(value) {
  const v = one(value);
  if (typeof v !== 'string' || !SLOT.test(v)) throw bad('Invalid slot. Use a day and period such as MON-P4 or B-MON-P4');
  return v;
}
export function day(value) {
  const v = one(value);
  if (typeof v !== 'string' || !DAY.test(v)) throw bad('Invalid day. Use MON, TUE, WED, THU, FRI or SAT');
  return v;
}
export function optionalDay(value) {
  return empty(value) ? null : day(value);
}
export function optionalGrid(value) {
  if (empty(value)) return null;
  const v = one(value);
  if (typeof v !== 'string' || !GRID.test(v)) throw bad('Invalid schedule. Use a letter such as A or B');
  return v;
}
export function optionalType(value) {
  if (empty(value)) return null;
  const v = one(value);
  if (!ROOM_TYPES.includes(v)) throw bad('Invalid type. Use CLASSROOM or LAB');
  return v;
}
export function optionalSeats(value) {
  if (empty(value)) return null;
  const n = Number(one(value));
  if (!Number.isInteger(n) || n < 1 || n > 5000) throw bad('Invalid minCapacity');
  return n;
}
export function searchText(value) {
  const v = one(value);
  if (typeof v !== 'string') throw bad('Missing search text');
  const t = v.trim();
  if (t.length < 1 || t.length > 40) throw bad('Search text must be 1 to 40 characters');
  return t;
}

// ---- fields of the Add data forms (JSON body). Each returns the clean value or throws a 400.
const trimmed = (value) => (typeof value === 'string' ? value.trim() : value);

// text the form shows back to people: names, titles
export function text(value, name, max = 80) {
  const v = trimmed(value);
  if (typeof v !== 'string' || v.length < 1 || v.length > max || /[\u0000-\u001f<>]/.test(v)) {
    throw bad(`${name}: type 1 to ${max} characters (no < or >)`);
  }
  return v;
}
export function optionalText(value, name, max) {
  return empty(trimmed(value)) ? null : text(value, name, max);
}
// a value that must match a pattern, for example a course code; upper: also turned into capitals
export function code(value, name, pattern, hint, upper = true) {
  let v = trimmed(value);
  if (typeof v === 'string' && upper) v = v.toUpperCase();
  if (typeof v !== 'string' || !pattern.test(v)) throw bad(`${name}: ${hint}`);
  return v;
}
export function optionalCode(value, name, pattern, hint, upper) {
  return empty(trimmed(value)) ? null : code(value, name, pattern, hint, upper);
}
export function int(value, name, min, max) {
  const n = typeof value === 'string' && value.trim() !== '' ? Number(value) : value;
  if (!Number.isInteger(n) || n < min || n > max) throw bad(`${name}: a whole number from ${min} to ${max}`);
  return n;
}
export function optionalInt(value, name, min, max) {
  return empty(trimmed(value)) ? null : int(value, name, min, max);
}
export function oneOf(value, name, allowed) {
  const v = trimmed(value);
  if (!allowed.includes(v)) throw bad(`${name}: one of ${allowed.join(', ')}`);
  return v;
}
export function idList(value, name, max = 10) {
  const list = value == null ? [] : value;
  if (!Array.isArray(list) || list.length > max) throw bad(`${name}: a list of at most ${max}`);
  return [...new Set(list.map((v) => id(v, name)))];
}
