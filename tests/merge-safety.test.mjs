import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { mergeKeepExisting, mergeToml, mergeYamlLayer, readJsonIfExists } from '../core/lib/render.mjs';

test('invalid existing JSON fails closed while missing JSON returns null', () => {
  assert.throws(() => readJsonIfExists(fileURLToPath(new URL('../core/lib/render.mjs', import.meta.url))), SyntaxError);
  assert.equal(readJsonIfExists(fileURLToPath(new URL('./nonexistent-merge-safety.json', import.meta.url))), null);
  assert.equal(readJsonIfExists(fileURLToPath(new URL('../package.json', import.meta.url))).name, 'setup-agent-code');
});

test('empty template arrays preserve existing permissions', () => {
  const base = { permissions: { allow: ['read'], deny: ['write'] }, args: ['old'] };
  assert.deepEqual(mergeKeepExisting(base, { permissions: { allow: [], deny: [] }, args: ['new'] }), {
    permissions: { allow: ['read'], deny: ['write'] }, args: ['new']
  });
  assert.deepEqual(mergeKeepExisting({}, { permissions: [] }), { permissions: [] });
});

test('TOML multiline arrays fail closed for live and template inputs', () => {
  const multiline = '[server]\nargs = [\n  "one",\n  "two",\n]\n';
  const simple = '[server]\nargs = ["new"]\n';
  assert.throws(() => mergeToml(multiline, simple), /Cannot safely merge/);
  assert.throws(() => mergeToml(simple, multiline), /Cannot safely merge/);
  assert.match(mergeToml('[server]\nargs = ["[one]", "two"]\n', simple), /args = \["new"\]/);
});

test('YAML quoted IDs participate in ownership and insert matching', () => {
  const existing = '- id: "mcp-old"\n  value: old\n- id: \'keep\'\n  value: live\n- insert:\n  - id: "managed"\n    value: old\n';
  const template = '- id: keep\n  value: template\n- insert:\n  - id: managed\n    value: new\n';
  const result = mergeYamlLayer(existing, template, { managedMcpIds: ['old'], managedInsertIds: ['managed'] });
  assert.doesNotMatch(result, /mcp-old|value: old|value: template/);
  assert.match(result, /value: live/);
  assert.match(result, /value: new/);
});

test('unmanaged insert item with a duplicate ID keeps the live value once', () => {
  const existing = '- id: keep\n  value: live\n- insert:\n  - id: user-plugin\n    value: live-insert\n';
  const template = '- insert:\n  - id: user-plugin\n    value: template-insert\n';
  const result = mergeYamlLayer(existing, template);
  assert.equal(result.match(/id: user-plugin/g).length, 1, 'duplicate insert id is emitted once');
  assert.match(result, /value: live-insert/);
  assert.doesNotMatch(result, /template-insert/);
});

test('managed insert item is replaced while unmanaged siblings survive', () => {
  const existing = '- insert:\n  - id: memory-memorix\n    value: old-managed\n  - id: user-plugin\n    value: live\n';
  const template = '- insert:\n  - id: memory-memorix\n    value: new-managed\n';
  const result = mergeYamlLayer(existing, template, { managedInsertIds: ['memory-memorix'] });
  assert.equal(result.match(/id: memory-memorix/g).length, 1, 'managed insert is not duplicated');
  assert.match(result, /new-managed/);
  assert.doesNotMatch(result, /old-managed/);
  assert.match(result, /id: user-plugin/);
});

test('block scalar keys and sequence block scalars fail closed', () => {
  const plain = '- id: keep\n  value: live\n';
  for (const scalar of ['- id: x\n  value: |\n    a\n\n    b\n', '- |\n  first\n\n  second\n', '- >-\n  folded\n']) {
    assert.throws(() => mergeYamlLayer(`${plain}${scalar}`, ''), /Cannot safely merge/);
    assert.throws(() => mergeYamlLayer('', `${plain}${scalar}`), /Cannot safely merge/);
  }
  assert.match(mergeYamlLayer(plain, '- id: keep\n  value: added\n'), /value: live/);
});
