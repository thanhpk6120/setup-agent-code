import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../core/engine.mjs', import.meta.url), 'utf8');

function section(start, end) {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from + start.length);
  assert.ok(from >= 0 && to > from, `Cannot locate engine section: ${start}`);
  return source.slice(from, to);
}

function sandbox({ consent = true, states = {}, cloakOk = true } = {}) {
  const writes = [];
  const installs = [];
  const servers = ['target', 'healthy'].map((id) => ({
    id, verify: { id }, install: { test: [{ cmd: `install-${id}` }] }, installGuidance: [`fix-${id}`]
  }));
  const ctx = {
    opts: {}, mode: 'install', interactive: false, home: '/virtual-home', vars: {},
    selectedMcp: new Set(servers.map(({ id }) => id)), blockedMcp: new Set(),
    manifests: { mcp: { servers } }, guidance: []
  };
  const c = {
    agent: { mcp: { file: '/virtual/mcp.json', adapter: 'generic' }, configs: [
      { dest: '/virtual/mcp.json', kind: 'json', template: 'base', mcpMerge: true },
      { dest: '/virtual/target.json', kind: 'json', template: 'optional', whenMcp: 'target' }
    ] },
    paths: { dir: '/virtual', extra: {} }, tokens: {}, rows: []
  };
  const noOp = () => {};
  const U = { osKey: 'test', log: { skip: noOp, warn: noOp, info: noOp, ok: noOp, error: noOp },
    resolveNpmPath: (value) => value, which: (value) => value };
  const D = { assessVerify: ({ id }) => ({ state: states[id] || 'ok', detail: `state-${id}` }),
    askConsent: async () => consent, refreshPath: noOp };
  const M = { ROOT: '/virtual', resolveToken: (value) => value,
    buildServerSpec: (server) => ({ command: server.id, args: [], env: {} }) };
  const R = { renderTemplate: () => '{}', readJsonIfExists: () => null,
    jsonMcpObject: (_adapter, specs) => Object.fromEntries(specs.map(({ id, spec }) => [id, spec])) };
  const V = { result: (id, status, detail) => ({ id, status, detail }) };
  const context = vm.createContext({ ctx, U, D, M, R, V, ROOT: '/virtual', path, process,
    chooseWritePolicy: async () => 'overwrite', writeConfig: async (_c, write) => writes.push(write),
    executeInstallAction: (action) => { installs.push(action.cmd); return false; },
    installCloakbrowser: async () => cloakOk, evalWhen: () => true, isWindows: () => false });
  const phaseSource = section('  P6: async (c) => {', '\n  P8: async (c) => {');
  const helpers = section('function buildVars(c) {', '\nfunction applyHookRegistrations(obj, c) {');
  const phases = vm.runInContext(`({\n${phaseSource}\n})`, context);
  vm.runInContext(helpers, context);
  return { ctx, c, writes, installs, phases };
}

for (const scenario of [
  { name: 'declined install', consent: false, status: 'WARN', installs: 0 },
  { name: 'failed install', consent: true, status: 'FAIL', installs: 1 }
]) {
  test(`P6 ${scenario.name} blocks P7 MCP configuration`, async () => {
    const env = sandbox({ consent: scenario.consent, states: { target: 'missing' } });
    await env.phases.P6(env.c);
    assert.equal(env.ctx.blockedMcp.has('target'), true);
    assert.equal(env.ctx.blockedMcp.has('healthy'), false);
    assert.equal(env.c.rows.find((row) => row.id === 'install:target').status, scenario.status);
    assert.equal(env.installs.length, scenario.installs);
    await env.phases.P7(env.c);
    assert.equal(env.writes.some((write) => write.dest === '/virtual/target.json'), false);
    const config = JSON.parse(env.writes.find((write) => write.dest === '/virtual/mcp.json').content);
    assert.equal(Object.hasOwn(config.mcpServers, 'target'), false);
    assert.equal(Object.hasOwn(config.mcpServers, 'healthy'), true);
  });
}

test('P6 failed CloakBrowser install blocks P7 configuration', async () => {
  const env = sandbox({ cloakOk: false });
  env.ctx.manifests.mcp.servers[0].id = 'cloakbrowser';
  env.ctx.selectedMcp.delete('target');
  env.ctx.selectedMcp.add('cloakbrowser');
  env.c.agent.configs[1].whenMcp = 'cloakbrowser';
  await env.phases.P6(env.c);
  assert.equal(env.ctx.blockedMcp.has('cloakbrowser'), true);
  assert.equal(env.c.rows.find((row) => row.id === 'install:cloakbrowser').status, 'FAIL');
  await env.phases.P7(env.c);
  assert.equal(env.writes.some((write) => write.dest === '/virtual/target.json'), false);
  const config = JSON.parse(env.writes.find((write) => write.dest === '/virtual/mcp.json').content);
  assert.equal(Object.hasOwn(config.mcpServers, 'cloakbrowser'), false);
  assert.equal(Object.hasOwn(config.mcpServers, 'healthy'), true);
});
