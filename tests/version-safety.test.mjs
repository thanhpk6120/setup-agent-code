import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../core/lib/util.mjs', import.meta.url), 'utf8');
const start = source.indexOf('export function versionOf(');
const end = source.indexOf('\nexport function run(', start);
assert.ok(start >= 0 && end > start);
// The slice also carries helper declarations; strip their module syntax for vm.
const code = source.slice(start, end).replace(/^export /gm, '');

function versionWith(result, { finderThrows = false } = {}) {
  const calls = [];
  const context = vm.createContext({
    which: () => { if (finderThrows) throw new Error('finder failed'); return '/mock/tool'; },
    spawnSync: (file, args, options) => {
      calls.push({ file, args, options });
      if (result instanceof Error) throw result;
      return result;
    },
    isWin: false
  });
  vm.runInContext(code, context);
  return { value: context.versionOf('tool'), calls };
}

test('versionOf accepts only successful execution', () => {
  const { value, calls } = versionWith({ status: 0, stdout: 'tool 1.2.3', stderr: '' });
  assert.equal(value, '1.2.3');
  assert.equal(calls[0].file, '/mock/tool');
  assert.deepEqual(Array.from(calls[0].args), ['--version']);
  assert.equal(calls[0].options.timeout, 15000);
  assert.equal(versionWith({ status: 0, stdout: '', stderr: 'tool build' }).value, 'tool build');
});

test('versionOf rejects nonzero exit, error and timeout even with version output', () => {
  for (const result of [
    { status: 1, stdout: 'tool 1.2.3', stderr: '' },
    { status: null, stdout: 'tool 1.2.3', stderr: '' },
    { status: 0, error: new Error('spawn failed'), stdout: 'tool 1.2.3' },
    { status: null, error: Object.assign(new Error('timed out'), { code: 'ETIMEDOUT' }), stdout: 'tool 1.2.3' },
    new Error('spawn threw')
  ]) assert.equal(versionWith(result).value, '');
  assert.equal(versionWith({}, { finderThrows: true }).value, '');
});
