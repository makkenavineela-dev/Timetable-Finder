// Unit test of the .cypher file splitter used by npm run load-data (no database needed).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { statements } from '../scripts/load-data.js';

test('comments are dropped and statements split on ;', () => {
  assert.deepEqual(statements('// title\nMATCH (n) RETURN n; /* block\ncomment */ RETURN 1;\n// end'),
    ['MATCH (n) RETURN n', 'RETURN 1']);
});

test('; and // inside quotes stay part of the text', () => {
  assert.deepEqual(statements(`RETURN 'a;b' AS x; RETURN "http://x" AS y; RETURN \`we;ird\` AS z`),
    [`RETURN 'a;b' AS x`, 'RETURN "http://x" AS y', 'RETURN `we;ird` AS z']);
});

test('an escaped quote does not end the text', () => {
  assert.deepEqual(statements(`RETURN 'it\\'s; fine' AS x; RETURN 2`), [`RETURN 'it\\'s; fine' AS x`, 'RETURN 2']);
});

for (const [file, count] of [['01_schema.cypher', 42], ['02_cluster_E_sem5.cypher', 17], ['02_cluster_E_sem3.cypher', 16]]) {
  test(`${file} splits into ${count} statements that each start with a Cypher keyword`, () => {
    const text = fs.readFileSync(fileURLToPath(new URL(`../../neo4j/${file}`, import.meta.url)), 'utf8');
    const list = statements(text);
    assert.equal(list.length, count);
    for (const s of list) assert.match(s, /^(MATCH|MERGE|CREATE|UNWIND|CALL|OPTIONAL)\b/, s.slice(0, 60));
  });
}
