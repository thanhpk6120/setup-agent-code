import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../core/lib/deps.mjs', import.meta.url), 'utf8');

async function fixture({ answers = [], actionOk = true, binary = true, opts = {}, mode = 'install', interactive = true, initiallyPresent = false } = {}) {
  const env = { HOME: '/fake-home', PATH: initiallyPresent ? '/usr/bin:/fake-home/.local/bin' : '/usr/bin' };
  const calls = [];
  const questions = [];
  const fakeProcess = { env };
  const log = { ok() {}, warn() {}, info() {}, error() {} };
  const util = {
    exists: (value) => value === '/fake-home/.local/bin', isWin: false, log, osKey: 'unix',
    readJson() {},
    run: (...args) => { calls.push(args); return { ok: actionOk, stdout: '' }; },
    versionGte: () => true,
    versionOf: () => 'uv 1.2.3',
    which: (cmd) => cmd === 'uv' && env.PATH.split(':').includes('/fake-home/.local/bin') && binary ? '/fake-home/.local/bin/uv' : null
  };
  const context = vm.createContext({ process: fakeProcess, console });
  const module = new vm.SourceTextModule(source, { context });
  await module.link(async (specifier) => {
    const values = specifier === 'node:path' ? { default: path.posix }
      : specifier === 'node:fs' ? { default: { statSync: () => ({ isFile: () => binary }) } }
      : specifier === 'node:os' ? { default: {} } : util;
    return new vm.SyntheticModule(Object.keys(values), function () {
      for (const [key, value] of Object.entries(values)) this.setExport(key, value);
    }, { context });
  });
  await module.evaluate();
  const ctx = { mode, opts, interactive, prompt: { ask: async (question) => { questions.push(question); return answers.shift() ?? 'n'; } } };
  const dep = { id: 'uv', verify: { cmd: 'uv' }, install: { unix: [{ cmd: 'installer' }] }, guidance: [] };
  return { deps: module.namespace, env, calls, questions, ctx, dep };
}

test('consent installation and PATH separately before verifying uv', async () => {
  const f = await fixture({ answers: ['y', 'y'] });
  assert.equal((await f.deps.ensureDependency(f.dep, f.ctx)).status, 'installed');
  assert.equal(f.questions.length, 2);
  assert.match(f.questions[1], /PATH/);
  assert.equal(f.env.PATH, '/usr/bin:/fake-home/.local/bin');
  assert.equal(f.calls.length, 1);
});

test('declining PATH never changes PATH after installation', async () => {
  const f = await fixture({ answers: ['y', 'n', 's'] });
  assert.equal((await f.deps.ensureDependency(f.dep, f.ctx)).status, 'failed');
  assert.equal(f.env.PATH, '/usr/bin');
  assert.equal(f.calls.length, 1);
});

test('declining installation does not execute installer or alter PATH', async () => {
  const f = await fixture({ answers: ['n'] });
  assert.equal((await f.deps.ensureDependency(f.dep, f.ctx)).status, 'declined');
  assert.equal(f.env.PATH, '/usr/bin');
  assert.equal(f.calls.length, 0);
});

test('explicit yes authorizes installation and session PATH without prompts', async () => {
  const f = await fixture({ opts: { yes: true }, interactive: false });
  assert.equal((await f.deps.ensureDependency(f.dep, f.ctx)).status, 'installed');
  assert.equal(f.env.PATH, '/usr/bin:/fake-home/.local/bin');
  assert.equal(f.questions.length, 0);
});

test('failed installer or missing uv binary never offers or alters PATH', async () => {
  for (const options of [{ actionOk: false }, { binary: false }]) {
    const f = await fixture({ ...options, answers: ['y', 's'] });
    assert.equal((await f.deps.ensureDependency(f.dep, f.ctx)).status, 'failed');
    assert.equal(f.env.PATH, '/usr/bin');
    assert.equal(f.questions.filter((q) => q.includes('PATH')).length, 0);
  }
});

test('configuration-only and already-present paths cause no installation', async () => {
  for (const options of [{ mode: 'configure' }, { opts: { 'skip-install': true } }, { initiallyPresent: true }]) {
    const f = await fixture(options);
    const before = f.env.PATH;
    const result = await f.deps.ensureDependency(f.dep, f.ctx);
    assert.equal(result.status, options.initiallyPresent ? 'present' : 'skipped');
    assert.equal(f.env.PATH, before);
    assert.equal(f.calls.length, 0);
    assert.equal(f.questions.length, 0);
  }
});
