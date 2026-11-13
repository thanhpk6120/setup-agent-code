import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';

const source = fs.readFileSync(new URL('../core/lib/util.mjs', import.meta.url), 'utf8');
const start = source.indexOf('/** Windows cannot execute .cmd/.bat');
const end = source.indexOf('\nexport function run(', start);
assert.ok(start >= 0 && end > start, 'spawnAdapter markers missing');
const code = source.slice(start, end).replace(/^export /gm, '');

function adapterFor(cmd, args, cwd) {
  const context = vm.createContext({ isWin: true, process: { env: { ComSpec: 'cmd.exe' }, cwd: () => 'C:\\work' }, path });
  return vm.runInContext(code + '; spawnAdapter(' + JSON.stringify(cmd) + ', ' + JSON.stringify(args) + ', ' + JSON.stringify(cwd) + ')', context);
}

test('spawnAdapter runs .cmd through cmd.exe with verbatim argv', () => {
  const result = adapterFor('C:/Program Files/nodejs/npm.cmd', ['--version']);
  assert.equal(result.file, 'cmd.exe');
  assert.equal(result.windowsVerbatimArguments, true, 'node must not re-escape the quotes cmd.exe receives');
  assert.equal(result.argv.slice(0, 3).join(' '), '/d /s /c');
  assert.match(result.argv[3], /npm\.cmd\" --version\"$/, result.argv[3]);
  assert.ok(!result.argv[3].includes('\\\"'), 'no backslash-escaped quotes reach cmd.exe');
  assert.ok(result.argv[3].startsWith('\"'), 'cmd.exe /s strips the outer quote pair');
});

test('spawnAdapter gives cmd.exe an absolute backslash path', () => {
  const result = adapterFor('tools/run.cmd', [], 'C:/work');
  assert.match(result.argv[3], /^\"C:\\work\\tools\\run\.cmd\"$/, result.argv[3]);
});

test('spawnAdapter quotes arguments that contain spaces', () => {
  const result = adapterFor('C:/tools/run.cmd', ['--cwd', 'C:/Program Files/app']);
  assert.ok(result.argv[3].includes('\"C:/Program Files/app\"'), result.argv[3]);
});

test('spawnAdapter leaves native executables unchanged', () => {
  const result = adapterFor('C:/Program Files/nodejs/node.exe', ['--version']);
  assert.equal(result.file, 'C:/Program Files/nodejs/node.exe');
  assert.deepEqual(Array.from(result.argv), ['--version']);
  assert.equal(result.windowsVerbatimArguments, undefined);
});
