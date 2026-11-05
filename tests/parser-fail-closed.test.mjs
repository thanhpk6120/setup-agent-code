import test from 'node:test';
import assert from 'node:assert/strict';
import { mergeToml, mergeYamlLayer } from '../core/lib/render.mjs';

test('unsafe TOML structures fail before merging', () => {
  const template = '[owned]\na = 2\n';
  for (const input of [
    '[owned]\n"user.key" = "keep"\n',
    '[owned]\na = 1\n[[user]]\nname = "keep"\n',
    '[owned]\na = 1\n[user] # comment\nx = 1\n',
    '[owned]\nvalue = """first\nsecond\nthird"""\n',
    '[owned]\na = 1\n[owned]\na = 2\n'
  ]) assert.throws(() => mergeToml(input, template), /Cannot safely merge/);
});

test('quoted TOML table headers merge as the same table as bare ones', () => {
  // Codex writes [mcp_servers."9remote"], so a quoted id segment is supported.
  const bare = '[a.b]\nvalue = 1\n';
  for (const header of ['[a."b"]', "[a.'b']", '["a".b]']) {
    const quoted = `${header}\nvalue = 2\n`;
    // The owned table is rewritten in the template's spelling, not duplicated.
    assert.equal(mergeToml(bare, quoted), quoted);
    assert.equal(mergeToml(quoted, bare), bare);
  }
});

test('ambiguous quoted TOML table headers still fail closed', () => {
  const bare = '[a.b]\nvalue = 1\n';
  // A dot or an escape inside the quotes cannot be resolved by a line splitter.
  for (const header of ['[a."b.c"]', '[a."b\\"c"]', '[a.""]', '["a"."b"]\n[a.b]']) {
    const quoted = `${header}\nvalue = 2\n`;
    assert.throws(() => mergeToml(quoted, bare), /Cannot safely merge unsupported TOML table/);
    assert.throws(() => mergeToml(bare, quoted), /Cannot safely merge unsupported TOML table/);
    assert.throws(() => mergeToml(`${bare}${quoted}`, ''), /Cannot safely merge unsupported TOML table/);
  }
});

test('bare dotted TOML table headers remain mergeable', () => {
  const existing = '[a.b]\nvalue = 1\n';
  assert.equal(mergeToml(existing, '[a.c]\nother = 2\n'), '[a.b]\nvalue = 1\n\n[a.c]\nother = 2\n');
});

test('nested content inside a YAML insert item is preserved verbatim', () => {
  const input = '- insert:\n  - id: user\n    config:\n      - id: nested\n        value: keep\n';
  const out = mergeYamlLayer(input, '');
  assert.ok(out.includes('- id: nested'), 'deeper sequence line survives');
  assert.ok(out.includes('value: keep'), 'deeper scalar survives');
  assert.equal(out.split('- id: user').length - 1, 1, 'sibling item is emitted once');
});

test('unsafe YAML structures fail before merging', () => {
  assert.throws(() => mergeYamlLayer('- insert:\n  # comment\n  - id: user\n', ''), /Cannot safely merge/);
  assert.throws(() => mergeYamlLayer('- id: user\n  value: |\n    a\n\n\n    b\n', ''), /Cannot safely merge/);
});

test('unsupported YAML insert items fail closed on both layers', () => {
  for (const item of ['  - name: user', '  - user', '  - {id: user}', '  -', '  -\tid: user']) {
    for (const prefix of ['', '  - id: prior\n']) {
      const input = `- insert:\n${prefix}${item}\n`;
      assert.throws(() => mergeYamlLayer(input, ''), /Cannot safely merge/);
      assert.throws(() => mergeYamlLayer('', input), /Cannot safely merge/);
    }
  }
});

test('supported YAML insert items remain mergeable', () => {
  const existing = '- insert:\n  - id: user\n    name: keep\n';
  const template = '- insert:\n  - id: managed\n    name: default\n';
  assert.equal(mergeYamlLayer(existing, template), `${existing}${template.slice('- insert:\n'.length)}`);
});
