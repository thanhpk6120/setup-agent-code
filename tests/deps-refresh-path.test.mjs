import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

function createDeps(registryPath) {
  const source = fs.readFileSync(new URL('../core/lib/deps.mjs', import.meta.url), 'utf8')
    .replace(/import path from 'node:path';\r?\n/, '')
    .replace(/import fs from 'node:fs';\r?\n/, '')
    .replace(/import os from 'node:os';\r?\n/, '')
    .replace(/import \{[\s\S]*?\} from '\.\/util\.mjs';\r?\n/, '')
    .replace(/export /g, '');
  let registryReads = 0;
  const sandbox = {
    path: path.win32,
    fs: {}, os: {},
    process: { env: { PATH: 'C:\\original' } },
    exists: () => true,
    isWin: true,
    log: { warn() {}, info() {}, ok() {} },
    run: () => { registryReads += 1; return { ok: true, stdout: registryPath }; },
    osKey: 'win', readJson() {}, versionGte() {}, versionOf() {}, which() {}
  };
  vm.runInNewContext(`${source}\nthis.api = { refreshPath, ensurePathRequirements };`, sandbox);
  return { ...sandbox.api, env: sandbox.process.env, registryReads: () => registryReads };
}

const ctx = (answer) => ({ mode: 'install', opts: {}, interactive: true, prompt: { ask: async () => answer } });

test('Windows refresh preserves the whole PATH after a refusal, but explicit consent still adds a directory', async () => {
  const deps = createDeps('C:\\DENIED\\;C:\\other');
  const result = await deps.ensurePathRequirements(ctx('n'), [{ id: 'denied', path: 'C:\\denied' }]);
  assert.equal(result[0].status, 'declined');
  const before = deps.env.PATH;
  deps.refreshPath();
  deps.refreshPath();
  assert.equal(deps.env.PATH, before);
  assert.equal(deps.registryReads(), 0);
  const accepted = await deps.ensurePathRequirements(ctx('y'), [{ id: 'accepted', path: 'C:\\accepted' }]);
  assert.equal(accepted[0].status, 'added');
  assert.equal(deps.env.PATH, 'C:\\original;C:\\accepted');
  deps.refreshPath();
  assert.equal(deps.env.PATH, 'C:\\original;C:\\accepted');
});

test('Windows refresh does not import registry entries before explicit consent', async () => {
  const deps = createDeps('C:\\original;C:\\other');
  deps.refreshPath();
  assert.equal(deps.registryReads(), 0);
  assert.equal(deps.env.PATH, 'C:\\original');
  const accepted = await deps.ensurePathRequirements(ctx('y'), [{ id: 'other', path: 'C:\\other' }]);
  assert.equal(accepted[0].status, 'added');
  assert.equal(deps.env.PATH, 'C:\\original;C:\\other');
  deps.refreshPath();
  assert.equal(deps.registryReads(), 0);
  assert.equal(deps.env.PATH, 'C:\\original;C:\\other');
});
