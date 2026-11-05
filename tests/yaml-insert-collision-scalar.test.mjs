import test from 'node:test';
import assert from 'node:assert/strict';
import { mergeYamlLayer } from '../core/lib/render.mjs';

// Pure-function tests: no HOME access, no file writes, no deletion.

const countId = (text, id) => (text.match(new RegExp(`id: ${id}\\b`, 'g')) || []).length;

test('unmanaged insert colliding with a template id keeps the live item', () => {
  const existing = '- id: keep\n  value: live\n- insert:\n  - id: user-plugin\n    value: live-insert\n';
  const template = '- insert:\n  - id: user-plugin\n    value: template-insert\n';
  const merged = mergeYamlLayer(existing, template);
  assert.equal(countId(merged, 'user-plugin'), 1, 'colliding id is emitted once');
  assert.match(merged, /value: live-insert/, 'existing value wins');
  assert.doesNotMatch(merged, /template-insert/, 'template default does not overwrite');
});

test('unmanaged collision with different config does not drop either entry', () => {
  const existing = '- insert:\n  - id: dup\n    command: memorix\n    name: live-name\n';
  const template = '- insert:\n  - id: dup\n    command: other\n  - id: fresh\n    command: added\n';
  const merged = mergeYamlLayer(existing, template, { managedInsertIds: [] });
  assert.equal(countId(merged, 'dup'), 1);
  assert.match(merged, /command: memorix/);
  assert.doesNotMatch(merged, /command: other/);
  assert.equal(countId(merged, 'fresh'), 1, 'new template insert is still added');
});

test('managed insert is replaced once while unmanaged siblings survive', () => {
  const existing = '- insert:\n  - id: memory-memorix\n    value: old-managed\n  - id: user-plugin\n    value: live\n';
  const template = '- insert:\n  - id: memory-memorix\n    value: new-managed\n';
  const merged = mergeYamlLayer(existing, template, { managedInsertIds: ['memory-memorix'] });
  assert.equal(countId(merged, 'memory-memorix'), 1);
  assert.match(merged, /new-managed/);
  assert.doesNotMatch(merged, /old-managed/);
  assert.equal(countId(merged, 'user-plugin'), 1);
});

test('repeated merges converge without duplicating or losing insert items', () => {
  const existing = '- insert:\n  - id: user-plugin\n    value: live\n  - id: memory-memorix\n    value: old-managed\n';
  const template = '- insert:\n  - id: user-plugin\n    value: template-insert\n  - id: memory-memorix\n    value: new-managed\n  - id: brand-new\n    value: added\n';
  const options = { managedInsertIds: ['memory-memorix'] };
  const first = mergeYamlLayer(existing, template, options);
  const second = mergeYamlLayer(first, template, options);
  const third = mergeYamlLayer(second, template, options);
  assert.equal(third, second, 'merge is idempotent once template inserts are present');
  for (const id of ['user-plugin', 'memory-memorix', 'brand-new']) {
    assert.equal(countId(second, id), 1, `${id} appears exactly once`);
  }
  assert.match(second, /value: live/, 'existing unmanaged value survives');
  assert.match(second, /new-managed/, 'managed value is refreshed');
});

test('sequence and mapping block scalars fail closed on both layers', () => {
  const plain = '- id: keep\n  value: live\n';
  const scalars = [
    '- |\n  first\n\n\n  second\n',
    '- >\n  folded\n',
    '- |-\n  stripped\n',
    '- |+\n  kept\n',
    '- id: x\n  value: |\n    a\n\n    b\n',
    '- id: x\n  value: >-\n    folded\n'
  ];
  for (const scalar of scalars) {
    assert.throws(() => mergeYamlLayer(`${plain}${scalar}`, ''), /Cannot safely merge/);
    assert.throws(() => mergeYamlLayer('', `${plain}${scalar}`), /Cannot safely merge/);
    assert.throws(() => mergeYamlLayer(scalar, plain), /Cannot safely merge/);
  }
});

test('pipes that are not block scalars do not fail closed', () => {
  const cases = [
    '- id: keep\n  note: "a | b"\n',
    '- id: keep\n  value: "|"\n',
    '# contains a | marker\n- id: keep\n  value: live\n',
    '- id: keep\n  url: http://example.test/a?b=c\n',
    '- id: keep\n  value: live # trailing | comment\n'
  ];
  for (const existing of cases) {
    let merged;
    try {
      merged = mergeYamlLayer(existing, '- id: keep\n  value: from-template\n');
    } catch (error) {
      assert.fail(`false positive for ${JSON.stringify(existing)}: ${error.message}`);
    }
    assert.ok(merged.includes(existing.trimEnd()), `live entry survives for ${JSON.stringify(existing)}`);
    assert.doesNotMatch(merged, /from-template/, 'existing entry wins over the template default');
  }
});
