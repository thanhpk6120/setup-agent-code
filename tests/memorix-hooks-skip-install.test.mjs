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
  const sandbox = { ctx, U, ensurePlugin: async () => { calls.push({ kind: 'plugin' }); }, ensureAgentNpmDeps: async () => {} };
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

for (const [agent] of [['dsh'], ['claude-code'], ['codex-cli'], ['antigravity-cli']]) {
  test(`P10 does not install global Memorix CLI hooks (MCP-only) for ${agent}`, async () => {
    const h = harness({ agent });
    await h.phases.P10(h.c);
    const memorixRuns = h.calls.filter(({ kind, command, args }) => kind === 'run' && command === 'memorix' && Array.isArray(args) && args[0] === 'hooks');
    assert.equal(memorixRuns.length, 0);
  });
}
