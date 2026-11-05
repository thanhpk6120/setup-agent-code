import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../core/engine.mjs', import.meta.url), 'utf8');
const start = source.indexOf('  P10: async (c) => {');
const end = source.indexOf('\n  P11:', start);
assert.ok(start >= 0 && end > start, 'P10 extraction markers missing');

function harness({ skipInstall = false, explicit = true, interactive = false, agent = 'dsh' } = {}) {
  const calls = [];
  const ctx = {
    opts: { memorix: explicit, 'skip-install': skipInstall }, interactive,
    selectedMcp: new Set(['memorix']), blockedMcp: new Set()
  };
  const U = {
    which: (command) => { calls.push({ kind: 'which', command }); return '/fake/memorix'; },
    run: (command, args, options) => { calls.push({ kind: 'run', command, args, options }); return { ok: true }; },
    log: { ok: () => {}, warn: () => {} }
  };
  const sandbox = { ctx, U, ensurePlugin: async () => { calls.push({ kind: 'plugin' }); } };
  const phases = vm.runInNewContext(`({\n${source.slice(start, end)}\n})`, sandbox);
  return { phases, calls, c: { agent: { id: agent, plugins: [{}] } } };
}

for (const scenario of [
  { name: 'explicit selection', explicit: true, interactive: false },
  { name: 'interactive selection', explicit: false, interactive: true }
]) {
  test(`P10 skips global Memorix hooks with --skip-install for ${scenario.name}`, async () => {
    const h = harness({ ...scenario, skipInstall: true });
    await h.phases.P10(h.c);
    assert.deepEqual(h.calls, [{ kind: 'plugin' }]);
  });
}

for (const [agent, flag] of [['dsh', 'dsh'], ['claude-code', 'claude'], ['codex-cli', 'codex']]) {
  test(`P10 retains global Memorix hooks without --skip-install for ${agent}`, async () => {
    const h = harness({ agent });
    await h.phases.P10(h.c);
    const runs = h.calls.filter(({ kind }) => kind === 'run');
    assert.equal(runs.length, 1);
    assert.equal(runs[0].command, 'memorix');
    assert.deepEqual(Array.from(runs[0].args), ['hooks', 'install', '--agent', flag, '--global']);
    assert.equal(runs[0].options.allowFail, true);
    assert.equal(runs[0].options.timeout, 120000);
  });
}
