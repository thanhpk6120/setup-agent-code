import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../core/engine.mjs', import.meta.url), 'utf8');
const helpersStart = source.indexOf('function pnpmPath()');
const helpersEnd = source.indexOf('\nfunction finish(', helpersStart);
const doctorStart = source.indexOf('  P11: async (c) => {');
const doctorEnd = source.indexOf('\n  P12:', doctorStart);
assert.ok(helpersStart >= 0 && helpersEnd > helpersStart && doctorStart >= 0 && doctorEnd > doctorStart, 'engine extraction markers missing');

const plugin = {
  id: 'cc-safety-net', package: 'cc-safety-net', label: 'Safety Net',
  profile: 'web', verifyCmd: 'cc-safety-net', verifyArgs: ['status'],
  installGuidance: ['repair plugin']
};

function harness({ installed = true, cli = true, verify = { ok: true, status: 0 }, install = { ok: true, status: 0 }, metadataAfterInstall = true } = {}) {
  let metadata = installed;
  const calls = [];
  const logs = [];
  const ctx = { home: '/fake-home', mode: 'doctor', opts: {}, guidance: [], selectedMcp: new Set(), blockedMcp: new Set() };
  const c = { agent: { plugins: [plugin] }, paths: { extra: { profile: '/fake-home/.dsh/profiles/web' } }, tokens: { servers: [] }, rows: [] };
  const U = {
    isWin: false,
    which: (name) => name === 'pnpm' ? '/fake-bin/pnpm' : name === 'dsh' ? '/fake-bin/dsh' : null,
    exists: () => cli,
    ensureDir: (dir) => calls.push({ kind: 'ensureDir', dir }),
    run: (cmd, args, opts) => {
      calls.push({ kind: 'run', cmd, args, opts });
      if (cmd === '/fake-bin/dsh') {
        metadata = metadataAfterInstall;
        return install;
      }
      return verify;
    },
    log: Object.fromEntries(['info', 'ok', 'skip', 'warn', 'error'].map((key) => [key, (message) => logs.push({ key, message })]))
  };
  const R = { readJsonIfExists: () => metadata ? { dependencies: { [plugin.package]: '1' }, dsh: { profile: { bundles: [plugin.package] } } } : null };
  const D = { askConsent: async () => true, assessVerify: () => { throw new Error('unexpected version verification'); } };
  const V = {
    result: (check, status, detail) => ({ check, status, detail }),
    verifyFiles: () => [], verifyBinary: () => [], verifyConfigEntries: () => [],
    formatTable: () => '', summarize: () => ({ PASS: 0, WARN: 0, FAIL: 0, SKIP: 0 })
  };
  const sandbox = { U, R, D, V, ctx, path: path.posix, process: { env: { PATH: '/fake-bin', LOCALAPPDATA: '/fake-appdata' } }, inferConfiguredMcp: () => [], buildSelectedSpecs: () => [] };
  const script = `${source.slice(helpersStart, helpersEnd)}\nconst phases = {\n${source.slice(doctorStart, doctorEnd)}\n};\nglobalThis.api = { pluginStatus, verifyPlugin, ensurePlugin, doctor: phases.P11 };`;
  vm.runInNewContext(script, sandbox, { filename: 'isolated-engine.mjs', timeout: 1000 });
  return { api: sandbox.api, c, ctx, calls, logs };
}

test('installation and verification succeed inside the fake profile', async () => {
  const h = harness({ installed: false });
  await h.api.ensurePlugin(h.c, plugin);
  assert.equal(h.c.rows.length, 1);
  assert.equal(h.c.rows[0].status, 'PASS');
  const runs = h.calls.filter((call) => call.kind === 'run');
  assert.equal(runs.length, 2);
  assert.equal(runs[0].cmd, '/fake-bin/dsh');
  assert.deepEqual(Array.from(runs[0].args), ['plugin', '--profile', 'web', 'add', 'cc-safety-net']);
  assert.equal(runs[0].opts.cwd, '/fake-home/.dsh/profiles/web');
  assert.equal(runs[1].cmd, '/fake-home/.dsh/profiles/web/node_modules/.bin/cc-safety-net');
  assert.deepEqual(Array.from(runs[1].args), ['status']);
});

test('missing profile CLI is a failure and never runs a command', async () => {
  const h = harness({ cli: false });
  const status = h.api.pluginStatus('/fake-home/.dsh/profiles/web', plugin);
  assert.equal(status.ok, false);
  assert.match(status.detail, /CLI/);
  await h.api.ensurePlugin(h.c, plugin);
  assert.equal(h.c.rows[0].status, 'FAIL');
  assert.equal(h.calls.filter((call) => call.kind === 'run').length, 0);
});

test('verification fails on nonzero exit even with stdout', async () => {
  const h = harness({ verify: { ok: false, status: 7, stdout: 'looks successful' } });
  await h.api.ensurePlugin(h.c, plugin);
  assert.equal(h.c.rows[0].status, 'FAIL');
  assert.match(h.c.rows[0].detail, /exit 7/);
  assert.equal(h.ctx.guidance.length, 1);
});

test('failed installer stays failed even if metadata appears', async () => {
  const h = harness({ installed: false, install: { ok: false, status: 1 }, metadataAfterInstall: true });
  await h.api.ensurePlugin(h.c, plugin);
  assert.equal(h.c.rows[0].status, 'FAIL');
  assert.match(h.c.rows[0].detail, /exit 1/);
  assert.equal(h.calls.filter((call) => call.kind === 'run').length, 1);
  assert.equal(h.ctx.guidance.length, 1);
});

test('a false ok flag fails verification or installation even with status zero', async () => {
  const verify = harness({ verify: { ok: false, status: 0, stdout: 'output' } });
  await verify.api.ensurePlugin(verify.c, plugin);
  assert.equal(verify.c.rows[0].status, 'FAIL');

  const install = harness({ installed: false, install: { ok: false, status: 0 }, metadataAfterInstall: true });
  await install.api.ensurePlugin(install.c, plugin);
  assert.equal(install.c.rows[0].status, 'FAIL');
  assert.equal(install.calls.filter((call) => call.kind === 'run').length, 1);
});

test('doctor checks each plugin and reports PASS, FAIL, or missing metadata WARN', async () => {
  for (const [options, expected] of [
    [{}, 'PASS'],
    [{ verify: { ok: false, status: 2, stdout: 'output' } }, 'FAIL'],
    [{ installed: false }, 'WARN']
  ]) {
    const h = harness(options);
    await h.api.doctor(h.c);
    const row = h.c.rows.find((item) => item.check === 'plugin:cc-safety-net');
    assert.ok(row);
    assert.equal(row.status, expected);
    assert.equal(h.calls.some((call) => call.cmd === '/fake-bin/dsh'), false);
  }
});
