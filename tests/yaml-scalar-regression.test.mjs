import test from 'node:test';
import assert from 'node:assert/strict';
import { mergeYamlLayer } from '../core/lib/render.mjs';

const scalar = '- |\n  first\n\n\n  second\n';
const other = '- id: other\n  value: keep\n';

for (const [layer, existing, template] of [
  ['existing', scalar, other],
  ['template', other, scalar]
]) {
  test(`sequence block scalar in ${layer} preserves its bytes or fails closed`, () => {
    let merged;
    try {
      merged = mergeYamlLayer(existing, template);
    } catch (error) {
      assert.match(error.message, /Cannot safely merge/);
      return;
    }
    assert.ok(merged.includes(scalar), 'sequence block scalar bytes must remain unchanged');
  });
}
