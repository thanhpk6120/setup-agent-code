import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const verifySource = fs.readFileSync(new URL('../core/lib/verify.mjs', import.meta.url), 'utf8');
const engineSource = fs.readFileSync(new URL('../core/engine.mjs', import.meta.url), 'utf8');

function section(source, start, end) {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from + start.length);
  assert.ok(from >= 0 && to > from, `Cannot locate section: ${start}`);
  return source.slice(from, to);
}

function sandbox(text, adapter = 'generic') {
  const exists = () => text !== undefined;
  const readText = () => text;
  const verifyContext = vm.createContext({ path, exists, readText });
  const verify = vm.runInContext(
    `${section(verifySource, 'export function result(', '\n/** JSON-RPC')
      .replaceAll('export function ', 'function ')}\n({ result, verifyConfigEntries })`,
    verifyContext
  );
  const agent = {
    mcp: { file: '/virtual/mcp.json', adapter },
    configs: [{ dest: '/virtual/mcp.json', kind: 'json', mcpMerge: true }]
  };
  const c = { agent, tokens: { servers: [] }, rows: [] };
  const noOp = () => {};
  const V = {
    ...verify,
    verifyFiles: () => [], verifyBinary: () => [],
    formatTable: () => '', summarize: () => ({ PASS: 0, WARN: 0, FAIL: 0, SKIP: 0 })
  };
  const context = vm.createContext({
    ctx: { mode: 'doctor', selectedMcp: new Set(), blockedMcp: new Set(), opts: {} },
    M: { resolveToken: (value) => value },
    U: { exists, readText, log: { info: noOp }, resolveNpmPath: (value) => value },
    V, D: {}, buildSelectedSpecs: () => [], verifyPlugin: noOp
  });
  vm.runInContext(section(engineSource, 'function inferConfiguredMcp(c) {', '\nfunction evalWhen('), context);
  const phases = vm.runInContext(`({\n${section(engineSource, '  P11: async (c) => {', '\n  P12: async (c) => {')}\n})`, context);
  return { agent, verify, c, phases };
}

for (const adapter of ['omp-json', 'json-mcpServers']) {
  for (const fixture of [
    { name: 'missing', text: undefined },
    { name: 'malformed', text: '{"mcpServers":' }
  ]) {
    test(`doctor ${adapter}: ${fixture.name} JSON fails without claiming no MCP`, async () => {
      const env = sandbox(fixture.text, adapter);
      await env.phases.P11(env.c);
      assert.ok(env.c.rows.some((row) => row.status === 'FAIL'), 'expected a failure');
      assert.ok(!env.c.rows.some((row) => row.check === 'mcp' && row.status === 'SKIP'), 'invalid input is not an empty configuration');
    });
  }
}

for (const key of ['mcpServers', 'mcp']) {
  test(`verify reads server IDs from ${key}, not unrelated JSON properties`, () => {
    const adapter = key === 'mcp' ? 'opencode-json' : 'omp-json';
    const valid = sandbox(JSON.stringify({ [key]: { target: { command: 'node' } } }), adapter);
    const missing = sandbox(JSON.stringify({ [key]: {}, unrelated: { target: {} } }), adapter);
    assert.equal(valid.verify.verifyConfigEntries(valid.agent, {}, ['target']).find((row) => row.check === 'mcp:target')?.status, 'PASS');
    assert.equal(missing.verify.verifyConfigEntries(missing.agent, {}, ['target']).find((row) => row.check === 'mcp:target')?.status, 'FAIL');
  });

  test(`verify rejects invalid ${key} containers`, () => {
    const adapter = key === 'mcp' ? 'opencode-json' : 'omp-json';
    for (const value of [null, [], 'target', 42]) {
      const env = sandbox(JSON.stringify({ [key]: value }), adapter);
      assert.ok(env.verify.verifyConfigEntries(env.agent, {}, []).some((row) => row.status === 'FAIL'));
    }
  });

  test(`doctor distinguishes invalid ${key} from a valid empty configuration`, async () => {
    const adapter = key === 'mcp' ? 'opencode-json' : 'omp-json';
    for (const value of [null, [], 'target', 42]) {
      const env = sandbox(JSON.stringify({ [key]: value }), adapter);
      await env.phases.P11(env.c);
      assert.ok(env.c.rows.some((row) => row.status === 'FAIL'));
      assert.ok(!env.c.rows.some((row) => row.check === 'mcp' && row.status === 'SKIP'));
    }
    const empty = sandbox(JSON.stringify({ [key]: {} }), adapter);
    await empty.phases.P11(empty.c);
    assert.ok(empty.c.rows.some((row) => row.check === 'mcp' && row.status === 'SKIP'));
    assert.ok(!empty.c.rows.some((row) => row.status === 'FAIL'));
  });

  test(`doctor identifies a configured server in ${key}`, async () => {
    const env = sandbox(JSON.stringify({ [key]: { target: { command: 'node' } } }), key === 'mcp' ? 'opencode-json' : 'omp-json');
    await env.phases.P11(env.c);
    assert.equal(env.c.rows.find((row) => row.check === 'mcp:target')?.status, 'PASS');
    assert.ok(!env.c.rows.some((row) => row.check === 'mcp' && row.status === 'SKIP'));
  });
}

test('malformed JSON diagnostics do not disclose configuration content', () => {
  const marker = 'synthetic-private-value';
  const env = sandbox(`{"password":"${marker}", BROKEN`);
  const rows = env.verify.verifyConfigEntries(env.agent, {}, ['target']);
  assert.ok(rows.some((row) => row.status === 'FAIL'));
  assert.equal(JSON.stringify(rows).includes(marker), false);
});
