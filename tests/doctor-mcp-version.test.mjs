import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../core/engine.mjs', import.meta.url), 'utf8');
const start = source.indexOf('  P11: async (c) => {');
const end = source.indexOf('\n  P12: async (c) => {', start);
assert.ok(start >= 0 && end > start);

function setup({ mode = 'doctor', configured = [], selected = [], servers = [], tokenServers } = {}) {
  const checked = [];
  const ctx = { mode, selectedMcp: new Set(selected), blockedMcp: new Set(), opts: { 'skip-install': true }, manifests: { mcp: { servers } } };
  const V = {
    result: (check, status, detail) => ({ check, status, detail }),
    verifyFiles: () => [], verifyBinary: () => [], verifyConfigEntries: () => [],
    formatTable: () => '', summarize: () => ({ PASS: 0, WARN: 0, FAIL: 0, SKIP: 0 })
  };
  const context = vm.createContext({
    ctx, V, inferConfiguredMcp: () => configured,
    U: { resolveNpmPath: (value) => value, log: { info: () => {} } },
    D: { assessVerify: (verify) => { checked.push(verify.version); return { state: 'ok', detail: 'mocked' }; } },
    buildSelectedSpecs: () => servers.filter((server) => ctx.selectedMcp.has(server.id)).map((server) => ({ id: server.id, server })),
    verifyPlugin: () => {}
  });
  const phases = vm.runInContext(`({\n${source.slice(start, end)}\n})`, context);
  return { phases, checked, c: { agent: {}, tokens: { servers: tokenServers }, rows: [] } };
}

const servers = [
  { id: 'configured', verify: { version: '1.2.3' } },
  { id: 'selected', verify: { version: '4.5.6' } },
  { id: 'no-pin' }
];

test('doctor verifies configured manifest servers even when not selected', async () => {
  const env = setup({ configured: ['configured', 'no-pin', 'unknown'], selected: ['selected'], servers });
  await env.phases.P11(env.c);
  assert.deepEqual(env.checked, ['1.2.3']);
  assert.deepEqual(env.c.rows.filter((row) => row.check.startsWith('version:')).map((row) => row.check), ['version:configured']);
});

test('doctor does not check versions when configuration is empty or unreadable', async () => {
  for (const configured of [[], null]) {
    const env = setup({ configured, selected: ['selected'], servers });
    await env.phases.P11(env.c);
    assert.deepEqual(env.checked, []);
  }
});

test('install still verifies rendered selected server specs', async () => {
  const tokenServers = [{ id: 'selected', server: servers[1] }];
  const env = setup({ mode: 'install', configured: ['configured'], selected: ['configured'], servers, tokenServers });
  await env.phases.P11(env.c);
  assert.deepEqual(env.checked, ['4.5.6']);
});
