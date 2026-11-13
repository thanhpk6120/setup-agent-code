import test from 'node:test';
import assert from 'node:assert/strict';

import { mergeToml, tomlHeaderKey } from '../core/lib/render.mjs';

test('mergeToml accepts quoted keys and values Codex writes', () => {
  const live = [
    'model = "codex-5"',
    '',
    '[mcp_servers.memorix]',
    'command = "memorix"',
    'args = ["serve"]',
    '',
    '[mcp_servers."9remote".http_headers]',
    '"x-9remote-session" = "abc"',
    '',
  ].join('\n');
  const tpl = ['[mcp_servers.memorix]', 'command = "cmd"', 'args = ["/c", "memorix.cmd"]', ''].join('\n');
  const out = mergeToml(live, tpl, { ownedHeaders: ['[mcp_servers.memorix]'] });
  assert.ok(out.includes('command = "cmd"'), 'owned table is updated');
  assert.ok(out.includes('"x-9remote-session" = "abc"'), 'quoted user key survives');
});

test('mergeToml keeps tables whose quoted ids contain dots', () => {
  const live = ['[hooks.state.\'C:\\Users\\me\\hooks.json:stop:0:0\']', 'trusted = true', ''].join('\n');
  const tpl = ['model = "x"', ''].join('\n');
  const out = mergeToml(live, tpl);
  assert.ok(out.includes('trusted = true'), 'dotted quoted table survives');
});

test('tomlHeaderKey canonicalises quoted segments with escapes', () => {
  assert.equal(tomlHeaderKey('[mcp_servers."9remote"]'), 'mcp_servers.9remote');
  assert.equal(
    tomlHeaderKey(String.raw`[projects."i:\\cyberlotus\\project"]`),
    String.raw`projects.i:\cyberlotus\project`
  );
  assert.equal(
    tomlHeaderKey(String.raw`[hooks.state.'C:\Users\me\.codex\hooks.json:stop:0:0']`),
    String.raw`hooks.state.C:\Users\me\.codex\hooks.json:stop:0:0`
  );
});

test('tomlHeaderKey refuses what the line parser cannot compare', () => {
  assert.equal(tomlHeaderKey('[a."bad\\q"]'), null, 'unknown escape is refused, not guessed');
  assert.equal(tomlHeaderKey('[a.b'), null);
  assert.equal(tomlHeaderKey('[]'), null);
});
