import test from 'node:test';
import assert from 'node:assert/strict';

import { wrapWindowsShim } from '../core/lib/manifest.mjs';

test('wrapWindowsShim resolves a bare name to its .cmd shim', () => {
  const out = wrapWindowsShim('memorix', ['serve'], { windows: true, resolve: () => 'C:/npm/memorix.cmd' });
  assert.equal(out.command, 'cmd');
  assert.deepEqual(out.args, ['/c', 'C:/npm/memorix.cmd', 'serve']);
});

test('wrapWindowsShim wraps an explicit .cmd path once', () => {
  const out = wrapWindowsShim('C:/Program Files/nodejs/npm.cmd', ['--version'], { windows: true });
  assert.equal(out.command, 'cmd');
  assert.deepEqual(out.args, ['/c', 'C:/Program Files/nodejs/npm.cmd', '--version']);
});

test('wrapWindowsShim keeps native executables and unix commands untouched', () => {
  const exe = wrapWindowsShim('node', ['server.js'], { windows: true, resolve: () => 'C:/nodejs/node.exe' });
  assert.equal(exe.command, 'node');
  assert.deepEqual(exe.args, ['server.js']);
  const unix = wrapWindowsShim('memorix', ['serve'], { windows: false, resolve: () => '/usr/bin/memorix' });
  assert.equal(unix.command, 'memorix');
  assert.deepEqual(unix.args, ['serve']);
});
