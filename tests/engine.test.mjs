// tests/engine.test.mjs - unit + integration tests for the setup engine.
// Run with: node --test tests/
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

import * as M from '../core/lib/manifest.mjs';
import * as R from '../core/lib/render.mjs';
import * as U from '../core/lib/util.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ENGINE = path.join(ROOT, 'core', 'engine.mjs');

function tempHome() {
  const root = path.join(ROOT, 'tests', '.tmp-engine');
  fs.mkdirSync(root, { recursive: true });
  return fs.mkdtempSync(path.join(root, 'sac-test-'));
}

function runEngine(args, home) {
  const temp = path.join(home, 'temp');
  fs.mkdirSync(temp, { recursive: true });
  const envFile = path.join(home, 'empty.env');
  if (!fs.existsSync(envFile)) fs.writeFileSync(envFile, '');
  const env = {
    ...(process.env.SystemRoot ? { SystemRoot: process.env.SystemRoot } : {}),
    USERPROFILE: home,
    HOME: home,
    APPDATA: path.join(home, 'AppData', 'Roaming'),
    LOCALAPPDATA: path.join(home, 'AppData', 'Local'),
    TEMP: temp,
    TMP: temp,
    TMPDIR: temp,
    PATH: path.join(home, 'bin'),
    SETUP_RESUME_ENV_PATH: path.join(home, 'resume.env')
  };
  const result = spawnSync(process.execPath, ['--require', path.join(ROOT, 'tests', 'engine-process-guard.cjs'), ENGINE, ...args, ...(args.includes('--env-file') ? [] : ['--env-file', envFile])], { env, encoding: 'utf8', timeout: 180000 });
  return { status: result.status, stdout: result.stdout || '', stderr: result.stderr || '' };
}

// ---------------------------------------------------------------- manifests
test('manifests validate and cover every required agent', () => {
  const manifests = M.loadManifests(ROOT);
  const errors = M.validateManifests(manifests);
  assert.deepEqual(errors, []);
  const ids = manifests.agents.agents.map((a) => a.id);
  for (const required of ['omp', 'claude-code', 'opencode', 'codex-cli', 'dsh', 'antigravity-cli', 'goose', 'roo-code']) {
    assert.ok(ids.includes(required), `missing agent ${required}`);
  }
});

test('every agent declares instruction files with existing templates', () => {
  const manifests = M.loadManifests(ROOT);
  for (const agent of manifests.agents.agents) {
    assert.ok(agent.instructionFiles.length > 0, `${agent.id} has no instruction files`);
    for (const file of agent.instructionFiles) {
      assert.ok(file.dest.includes('/'), `${agent.id} dest must be a path`);
      for (const part of file.content) {
        assert.ok(fs.existsSync(path.join(ROOT, 'templates', part)), `missing templates/${part}`);
      }
    }
  }
});

test('omp must not install SYSTEM.md (it replaces the built-in prompt)', () => {
  const manifests = M.loadManifests(ROOT);
  const omp = M.agentById(manifests, 'omp');
  assert.ok(omp.forbiddenFiles.some((f) => f.dest.endsWith('SYSTEM.md')));
  assert.ok(!omp.instructionFiles.some((f) => f.dest.endsWith('SYSTEM.md')));
});

test('antigravity instruction file lives in ~/.gemini, not in the CLI dir', () => {
  const manifests = M.loadManifests(ROOT);
  const agy = M.agentById(manifests, 'antigravity-cli');
  const dests = agy.instructionFiles.map((f) => f.dest);
  assert.ok(dests.includes('<geminiDir>/AGENTS.md'));
  assert.ok(!dests.some((d) => d.includes('antigravity-cli/AGENTS.md')));
});

// ---------------------------------------------------------------- rendering
test('JSON placeholders are escaped (Windows paths must not break JSON)', () => {
  const out = R.substitutePlaceholders('{"p":"__GITNEXUS_PATH__"}', { GITNEXUS_PATH: 'C:\\nvm4w\\x.cmd' }, { json: true });
  assert.equal(JSON.parse(out).p, 'C:\\nvm4w\\x.cmd');
});

test('non-JSON placeholders stay verbatim (markdown backslashes preserved)', () => {
  const out = R.substitutePlaceholders('path=__P__', { P: 'C:\\a\\b' });
  assert.equal(out, 'path=C:\\a\\b');
});

test('TOML MCP blocks contain command/args/env for every server', () => {
  const blocks = R.tomlMcpBlocks([
    { id: 'a', spec: { command: 'node', args: ['x.js'], env: { K: 'v' } } },
    { id: 'b', spec: { command: 'cmd', args: [], env: {} } }
  ]);
  assert.match(blocks, /\[mcp_servers\.a\]/);
  assert.match(blocks, /\[mcp_servers\.a\.env\]/);
  assert.match(blocks, /args = \["x\.js"\]/);
  assert.match(blocks, /\[mcp_servers\.b\]/);
});

test('YAML MCP blocks are valid list items with stdio transport', () => {
  const blocks = R.yamlMcpBlocks([{ id: 'memorix', spec: { command: 'memorix', args: ['serve'], env: {} } }]);
  assert.match(blocks, /^- id: mcp-memorix/m);
  assert.match(blocks, /serverName: memorix/);
  assert.match(blocks, /transport: stdio/);
  assert.match(blocks, /command: "memorix"/);
});
test('yamlGooseExtensions and mergeGooseConfig manage Goose extensions correctly', () => {
  const servers = [{ id: 'gitnexus', spec: { command: 'gitnexus', args: ['mcp'], env: { FOO: 'bar' } } }];
  const rendered = R.yamlGooseExtensions(servers);
  assert.match(rendered, /gitnexus:/);
  assert.match(rendered, /type: stdio/);
  assert.match(rendered, /cmd: "gitnexus"/);
  assert.match(rendered, /FOO: "bar"/);

  const template = 'active_provider: anthropic\n# <<GOOSE_EXTENSIONS>>\n';
  const merged = R.mergeGooseConfig(template, servers);
  assert.match(merged, /extensions:\n  gitnexus:/);

  const existingWithCustom = 'active_provider: anthropic\nextensions:\n  builtin-dev:\n    type: builtin\n  gitnexus:\n    type: stdio\n';
  const updated = R.mergeGooseConfig(existingWithCustom, [], new Set(['gitnexus']));
  assert.match(updated, /builtin-dev:/);
  assert.ok(!updated.includes('gitnexus:'));
});

test('composeInstruction keeps global rules before instructions', () => {
  const text = R.composeInstruction(['A', 'B'], ['C']);
  assert.ok(text.indexOf('A') < text.indexOf('B'));
  assert.ok(text.indexOf('B') < text.indexOf('C'));
});

test('deepMerge keeps user keys and lets the overlay win', () => {
  const merged = R.deepMerge({ keep: 1, same: 'old' }, { same: 'new' });
  assert.equal(merged.keep, 1);
  assert.equal(merged.same, 'new');
});

test('.env loader strips inline comments but keeps quoted values', () => {
  const dir = tempHome();
  const file = path.join(dir, '.env');
  fs.writeFileSync(file, 'A=value # comment\nB="x # y"\nC=\n');
  const vars = U.parseEnvFile(file);
  assert.equal(vars.A, 'value');
  assert.equal(vars.B, 'x # y');
  assert.equal(vars.C, '');
});

test('versionGte compares semantic versions', () => {
  assert.equal(U.versionGte('1.2.3', '1.2.2'), true);
  assert.equal(U.versionGte('1.2.3', '1.10.0'), false);
  assert.equal(U.versionGte('v22.18.0', '22.18.0'), true);
});

// ---------------------------------------------------------------- integration
test('isolated install (mcp none) writes instruction files only and no memorix skills', () => {
  const home = tempHome();
  const res = runEngine(['--target', 'omp', '--yes', '--skip-install', '--force', '--mcp', 'none', '--no-memorix', '--quiet'], home);
  assert.equal(res.status, 0, res.stderr);
  assert.ok(fs.existsSync(path.join(home, '.omp', 'agent', 'AGENTS.md')));
  assert.ok(fs.existsSync(path.join(home, '.omp', 'agent', 'RULES.md')));
  assert.ok(!fs.existsSync(path.join(home, '.omp', 'agent', 'SYSTEM.md')), 'SYSTEM.md must never be installed');
  const mcp = JSON.parse(fs.readFileSync(path.join(home, '.omp', 'agent', 'mcp.json'), 'utf8'));
  assert.deepEqual(Object.keys(mcp.mcpServers), []);
  const skills = fs.readdirSync(path.join(home, '.omp', 'agent', 'skills'));
  assert.equal(skills.filter((s) => s.startsWith('memorix-')).length, 0);
  assert.ok(skills.length > 0);
});

test('isolated install (mcp all, memorix) writes every manifest MCP on every adapter', () => {
  const home = tempHome();
  const expectedMcp = JSON.parse(fs.readFileSync(path.join(ROOT, 'manifest', 'mcp.json'), 'utf8')).servers.length;
  const res = runEngine(['--target', 'all', '--yes', '--skip-install', '--force', '--mcp', 'all', '--memorix', '--quiet'], home);
  assert.equal(res.status, 0, res.stderr);

  const ompMcp = JSON.parse(fs.readFileSync(path.join(home, '.omp', 'agent', 'mcp.json'), 'utf8'));
  assert.equal(Object.keys(ompMcp.mcpServers).length, expectedMcp);

  const claudeJson = JSON.parse(fs.readFileSync(path.join(home, '.claude.json'), 'utf8'));
  assert.equal(Object.keys(claudeJson.mcpServers).length, expectedMcp);

  const codex = fs.readFileSync(path.join(home, '.codex', 'config.toml'), 'utf8');
  assert.equal((codex.match(/^\[mcp_servers\.[a-z0-9-]+\]$/gm) || []).length, expectedMcp);
  assert.ok(!codex.includes('CODEX.md'));

  const cordis = fs.readFileSync(path.join(home, '.dsh', 'profiles', 'web', 'cordis.patch.yml'), 'utf8');
  assert.equal((cordis.match(/^- id: mcp-/gm) || []).length, expectedMcp);
  assert.ok(cordis.includes('serverName: memorix'));
  assert.ok(!cordis.includes('maxActiveSubagents: 32\n    command:'), 'memorix must not leak into subagent config');

  const agySettings = JSON.parse(fs.readFileSync(path.join(home, '.gemini', 'antigravity-cli', 'settings.json'), 'utf8'));
  assert.equal(Object.keys(agySettings.mcpServers).length, expectedMcp);
  assert.ok(agySettings.hooks.PreToolUse.length >= 1);

  assert.ok(fs.existsSync(path.join(home, '.gemini', 'AGENTS.md')));
  assert.ok(!fs.existsSync(path.join(home, '.gemini', 'antigravity-cli', 'AGENTS.md')));
  const gooseDir = U.isWin ? path.join(home, 'AppData', 'Roaming', 'Block', 'goose', 'config') : path.join(home, '.config', 'goose');
  assert.ok(fs.existsSync(path.join(gooseDir, '.goosehints')));
  const gooseConfig = fs.readFileSync(path.join(gooseDir, 'config.yaml'), 'utf8');
  assert.equal((gooseConfig.match(/^  [a-z0-9-]+:\s*$/gm) || []).length, expectedMcp);

  assert.ok(fs.existsSync(path.join(home, '.roo', 'rules', 'AGENTS.md')));
  const rooSettingsDir = U.isWin
    ? path.join(home, 'AppData', 'Roaming', 'Code', 'User', 'globalStorage', 'rooveterinaryinc.roo-cline', 'settings')
    : path.join(home, '.config', 'Code', 'User', 'globalStorage', 'rooveterinaryinc.roo-cline', 'settings');
  const rooMcp = JSON.parse(fs.readFileSync(path.join(rooSettingsDir, 'mcp_settings.json'), 'utf8'));
  assert.equal(Object.keys(rooMcp.mcpServers).length, expectedMcp);
});

test('re-running with mcp none removes only installer-managed servers', () => {
  const home = tempHome();
  runEngine(['--target', 'omp', '--yes', '--skip-install', '--force', '--mcp', 'all', '--quiet'], home);
  const mcpPath = path.join(home, '.omp', 'agent', 'mcp.json');
  const withAll = JSON.parse(fs.readFileSync(mcpPath, 'utf8'));
  withAll.mcpServers['user-added'] = { command: 'my-server', args: [] };
  fs.writeFileSync(mcpPath, JSON.stringify(withAll, null, 2));

  const res = runEngine(['--target', 'omp', '--yes', '--skip-install', '--force', '--mcp', 'none', '--quiet'], home);
  assert.equal(res.status, 0, res.stderr);
  const after = JSON.parse(fs.readFileSync(mcpPath, 'utf8'));
  assert.deepEqual(Object.keys(after.mcpServers), ['user-added']);
});

test('dry-run emits identical phase plan and prompt order for every target', () => {
  const plan = (target) => {
    const home = tempHome();
    const res = runEngine(['--target', target, '--dry-run', '--json'], home);
    assert.equal(res.status, 0, res.stderr);
    return JSON.parse(res.stdout);
  };
  const omp = plan('omp');
  const dsh = plan('dsh');
  assert.deepEqual(omp.phases, dsh.phases);
  assert.deepEqual(omp.prompts, dsh.prompts);
  assert.equal(omp.phases[0], 'P0');
  assert.equal(omp.phases[omp.phases.length - 1], 'P12');
});

test('doctor verifies an installed home without writing', () => {
  const home = tempHome();
  runEngine(['--target', 'omp', '--yes', '--skip-install', '--force', '--mcp', 'none', '--quiet'], home);
  const before = fs.readFileSync(path.join(home, '.omp', 'agent', 'AGENTS.md'), 'utf8');
  const res = runEngine(['--target', 'omp', '--doctor', '--json'], home);
  assert.equal(res.status, 0, res.stderr);
  const after = fs.readFileSync(path.join(home, '.omp', 'agent', 'AGENTS.md'), 'utf8');
  assert.equal(before, after);
  const payload = JSON.parse(res.stdout);
  assert.equal(payload.mode, 'doctor');
  assert.ok(payload.counts.PASS > 0);
});
test('goose re-run with mcp none and mcp all preserves non-managed extensions and avoids duplicate keys', () => {
  const home = tempHome();
  const gooseDir = U.isWin ? path.join(home, 'AppData', 'Roaming', 'Block', 'goose', 'config') : path.join(home, '.config', 'goose');
  const cfgPath = path.join(gooseDir, 'config.yaml');

  runEngine(['--target', 'goose', '--yes', '--skip-install', '--force', '--mcp', 'all', '--quiet'], home);
  const withAll = fs.readFileSync(cfgPath, 'utf8');
  assert.ok(withAll.includes('extensions:'));
  assert.ok(withAll.includes('  gitnexus:'));

  const withCustom = withAll.replace('extensions:\n', 'extensions:\n  custom-dev:\n    type: builtin\n');
  fs.writeFileSync(cfgPath, withCustom, 'utf8');

  runEngine(['--target', 'goose', '--yes', '--skip-install', '--force', '--mcp', 'none', '--quiet'], home);
  const afterNone = fs.readFileSync(cfgPath, 'utf8');
  assert.ok(afterNone.includes('custom-dev:'));
  assert.ok(!afterNone.includes('gitnexus:'));

  runEngine(['--target', 'goose', '--yes', '--skip-install', '--force', '--mcp', 'all', '--quiet'], home);
  const afterReAll = fs.readFileSync(cfgPath, 'utf8');
  const extMatches = afterReAll.match(/^extensions:/gm) || [];
  assert.equal(extMatches.length, 1, 'must have exactly one extensions: key');
  assert.ok(afterReAll.includes('custom-dev:'));
  assert.ok(afterReAll.includes('gitnexus:'));
});

test('roo-code re-run with mcp none and mcp all removes only installer-managed servers', () => {
  const home = tempHome();
  const rooSettingsDir = U.isWin
    ? path.join(home, 'AppData', 'Roaming', 'Code', 'User', 'globalStorage', 'rooveterinaryinc.roo-cline', 'settings')
    : path.join(home, '.config', 'Code', 'User', 'globalStorage', 'rooveterinaryinc.roo-cline', 'settings');
  const mcpPath = path.join(rooSettingsDir, 'mcp_settings.json');

  runEngine(['--target', 'roo-code', '--yes', '--skip-install', '--force', '--mcp', 'all', '--quiet'], home);
  const withAll = JSON.parse(fs.readFileSync(mcpPath, 'utf8'));
  withAll.mcpServers['user-server'] = { command: 'user-tool', args: [] };
  fs.writeFileSync(mcpPath, JSON.stringify(withAll, null, 2));

  runEngine(['--target', 'roo-code', '--yes', '--skip-install', '--force', '--mcp', 'none', '--quiet'], home);
  const afterNone = JSON.parse(fs.readFileSync(mcpPath, 'utf8'));
  assert.deepEqual(Object.keys(afterNone.mcpServers), ['user-server']);

  runEngine(['--target', 'roo-code', '--yes', '--skip-install', '--force', '--mcp', 'all', '--quiet'], home);
  const afterReAll = JSON.parse(fs.readFileSync(mcpPath, 'utf8'));
  assert.ok(afterReAll.mcpServers['user-server']);
  assert.ok(afterReAll.mcpServers['gitnexus']);
});

test('doctor verifies goose and roo-code without writing', () => {
  const home = tempHome();
  runEngine(['--target', 'goose', '--yes', '--skip-install', '--force', '--mcp', 'all', '--quiet'], home);
  runEngine(['--target', 'roo-code', '--yes', '--skip-install', '--force', '--mcp', 'all', '--quiet'], home);

  const gooseDir = U.isWin ? path.join(home, 'AppData', 'Roaming', 'Block', 'goose', 'config') : path.join(home, '.config', 'goose');
  const cfgPath = path.join(gooseDir, 'config.yaml');
  const currentGoose = fs.readFileSync(cfgPath, 'utf8');
  fs.writeFileSync(cfgPath, currentGoose.replace('extensions:\n', 'extensions:\n  developer:\n    type: builtin\n'), 'utf8');

  const gooseDoc = runEngine(['--target', 'goose', '--doctor', '--json'], home);
  assert.equal(gooseDoc.status, 0, gooseDoc.stderr);
  const goosePayload = JSON.parse(gooseDoc.stdout);
  assert.equal(goosePayload.mode, 'doctor');
  assert.equal(goosePayload.counts.FAIL, 0);
  assert.ok(goosePayload.counts.PASS >= 5);

  const rooDoc = runEngine(['--target', 'roo-code', '--doctor', '--json'], home);
  assert.equal(rooDoc.status, 0, rooDoc.stderr);
  const rooPayload = JSON.parse(rooDoc.stdout);
  assert.equal(rooPayload.mode, 'doctor');
  assert.equal(rooPayload.counts.FAIL, 0);
  assert.ok(rooPayload.counts.PASS >= 5);
});

test('unknown option exits with code 2', () => {
  const home = tempHome();
  const res = runEngine(['--target', 'omp', '--not-a-flag'], home);
  assert.equal(res.status, 2);
});

test('conflicting memorix flags exit with code 2', () => {
  const home = tempHome();
  const res = runEngine(['--target', 'omp', '--memorix', '--no-memorix'], home);
  assert.equal(res.status, 2);
});

test('every instruction file ends up with Global Rules except OMP AGENTS.md', () => {
  const home = tempHome();
  runEngine(['--target', 'all', '--yes', '--skip-install', '--force', '--mcp', 'none', '--quiet'], home);
  const files = {
    claude: path.join(home, '.claude', 'CLAUDE.md'),
    opencode: path.join(home, '.config', 'opencode', 'AGENTS.md'),
    codex: path.join(home, '.codex', 'AGENTS.md'),
    dsh: path.join(home, '.dsh', 'AGENTS.md'),
    antigravity: path.join(home, '.gemini', 'AGENTS.md')
  };
  for (const [name, file] of Object.entries(files)) {
    const text = fs.readFileSync(file, 'utf8');
    assert.ok(text.includes('# Global Rules'), `${name} missing Global Rules`);
    assert.ok(text.includes('[Pre-flight] Tier:'), `${name} missing pre-flight prefix rule`);
    assert.ok(text.includes('Always respond in Vietnamese'), `${name} missing language rule`);
  }
  const ompAgents = fs.readFileSync(path.join(home, '.omp', 'agent', 'AGENTS.md'), 'utf8');
  const ompRules = fs.readFileSync(path.join(home, '.omp', 'agent', 'RULES.md'), 'utf8');
  assert.ok(ompRules.includes('# Global Rules'));
  assert.ok(ompAgents.includes('# Agent Instructions'));
  assert.ok(!ompAgents.includes('# Global Rules'), 'OMP AGENTS.md must stay context-only');
});

function resolveShell(name, winCandidates = []) {
  if (spawnSync(name, ['-c', 'exit 0']).status === 0) return name;
  for (const candidate of winCandidates) {
    if (fs.existsSync(candidate) && spawnSync(candidate, ['-c', 'exit 0']).status === 0) return candidate;
  }
  return null;
}

test('launcher contract: PowerShell and Bash produce the same dry-run plan', (t) => {
  // Runs the real install.ps1 / install.sh launchers: opt-in only, never in the default run.
  if (process.env.SAC_TEST_LAUNCHERS !== '1') { t.skip('dat SAC_TEST_LAUNCHERS=1 de chay launcher that'); return; }
  const pwshBin = resolveShell('pwsh', ['C:\\Program Files\\PowerShell\\7\\pwsh.exe']);
  const bashBin = resolveShell('bash', ['C:\\Program Files\\Git\\bin\\bash.exe', 'C:\\Program Files\\Git\\usr\\bin\\bash.exe']);
  if (!pwshBin || !bashBin) { t.skip('pwsh hoac bash khong co trong PATH'); return; }
  const home = tempHome();
  const env = {
    ...process.env,
    USERPROFILE: home,
    HOME: home,
    APPDATA: path.join(home, 'AppData', 'Roaming'),
    SETUP_RESUME_ENV_PATH: path.join(home, 'resume.env')
  };
  const ps = spawnSync(pwshBin, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(ROOT, 'install.ps1'), '-Target', 'omp', '-DryRun', '-Json'], { env, encoding: 'utf8', timeout: 120000 });
  const sh = spawnSync(bashBin, [path.join(ROOT, 'install.sh'), '--target', 'omp', '--dry-run', '--json'], { env, encoding: 'utf8', timeout: 120000 });
  assert.equal(ps.status, 0, ps.stderr);
  assert.equal(sh.status, 0, sh.stderr);
  const a = JSON.parse(ps.stdout);
  const b = JSON.parse(sh.stdout);
  assert.deepEqual(a.phases, b.phases);
  assert.deepEqual(a.prompts, b.prompts);
});

// ---------------------------------------------------------------- dependencies
import * as D from '../core/lib/deps.mjs';

test('every MCP requires entry is declared in prerequisites.json', () => {
  const manifests = M.loadManifests(ROOT);
  const ids = new Set(manifests.prereqs.deps.map((d) => d.id));
  for (const server of manifests.mcp.servers) {
    for (const depId of server.requires || []) {
      assert.ok(ids.has(depId), `${server.id} requires undeclared dep: ${depId}`);
    }
  }
});

test('every prerequisite carries guidance for the failure path', () => {
  const manifests = M.loadManifests(ROOT);
  for (const dep of manifests.prereqs.deps) {
    assert.ok(Array.isArray(dep.guidance) && dep.guidance.length > 0, `${dep.id} missing guidance`);
  }
});

test('declined dependency returns guidance and does not install', async () => {
  const dep = { id: 'fakedep', label: 'Fake', why: 'test', verify: { cmd: 'definitely-missing-xyz' }, install: { win: [], unix: [] }, guidance: ['manual step'] };
  const ctx = { mode: 'install', opts: {}, interactive: false, prompt: { ask: async () => '' } };
  const res = await D.ensureDependency(dep, ctx, { requiredBy: ['memorix'] });
  assert.equal(res.status, 'declined');
  assert.deepEqual(res.guidance, ['manual step']);
});

test('already-present dependency is reported as present', async () => {
  const dep = { id: 'node', verify: { cmd: 'node', args: ['--version'] }, install: { win: [], unix: [] }, guidance: ['x'] };
  const ctx = { mode: 'install', opts: {}, interactive: false, prompt: { ask: async () => '' } };
  const res = await D.ensureDependency(dep, ctx, {});
  assert.equal(res.status, 'present');
});

test('path requirement asks before touching PATH', async () => {
  const home = tempHome();
  const bin = path.join(home, '.local', 'bin');
  fs.mkdirSync(bin, { recursive: true });
  const originalPath = process.env.PATH;
  const originalHome = process.env.HOME;
  const originalProfile = process.env.USERPROFILE;
  process.env.HOME = home;
  process.env.USERPROFILE = home;
  try {
    const ctx = { mode: 'install', opts: { yes: true }, interactive: false, prompt: { ask: async () => '' } };
    const results = await D.ensurePathRequirements(ctx, [{ id: 'local-bin', label: 'local bin', resolve: 'local-bin', why: 'test' }]);
    assert.equal(results[0].status, 'added');
    assert.ok((process.env.PATH || '').split(path.delimiter).includes(bin));
  } finally {
    process.env.PATH = originalPath;
    process.env.HOME = originalHome;
    process.env.USERPROFILE = originalProfile;
  }
});

test('missing dependency blocks only the MCP servers that require it', () => {
  const home = tempHome();
  const report = path.join(home, 'blocked.json');
  const preload = path.join(home, 'block-processes.cjs');
  fs.writeFileSync(preload, `
    const childProcess = require('node:child_process');
    const { syncBuiltinESMExports } = require('node:module');
    childProcess.spawnSync = (command, args = []) => {
      if ((command === 'which' || command === 'where') && args[0] === 'omp') {
        return { status: 0, stdout: 'fake-omp\\n', stderr: '' };
      }
      if (command === 'fake-omp') return { status: 0, stdout: '1.0.0\\n', stderr: '' };
      if (command === 'which' || command === 'where' || (command === 'npm' && args.join(' ') === 'prefix -g')) {
        return { status: 1, stdout: '', stderr: 'blocked by test' };
      }
      throw new Error('Unexpected child process: ' + command);
    };
    childProcess.spawn = () => { throw new Error('Unexpected child process'); };
    childProcess.exec = childProcess.execFile = childProcess.execSync = childProcess.execFileSync = childProcess.spawn;
    syncBuiltinESMExports();
  `);
  const env = {
    ...process.env,
    USERPROFILE: home,
    HOME: home,
    APPDATA: path.join(home, 'AppData', 'Roaming'),
    LOCALAPPDATA: path.join(home, 'AppData', 'Local'),
    NODE_OPTIONS: '',
    SETUP_RESUME_ENV_PATH: path.join(home, 'resume.env'),
    SETUP_TEST_MISSING_DEPS: 'node',
    SETUP_TEST_DECLINE_DEPS: '1'
  };
  const result = spawnSync(process.execPath, ['--require', preload, ENGINE, '--target', 'omp', '--mcp', 'memorix', '--yes', '--report', report, '--json'], { env, encoding: 'utf8', timeout: 120000 });
  assert.equal(result.status, 0, result.stderr);
  const payload = JSON.parse(fs.readFileSync(report, 'utf8'));
  assert.ok(payload.blockedMcp.includes('memorix'), 'memorix must be blocked');
  assert.ok(payload.guidance.some((g) => g.scope === 'dep:node'), 'guidance for node must be present');
  const mcp = JSON.parse(fs.readFileSync(path.join(home, '.omp', 'agent', 'mcp.json'), 'utf8'));
  assert.deepEqual(Object.keys(mcp.mcpServers), [], 'blocked MCP must not be written');
});


test('dependency install runs the consent-gated action and verifies before continuing', async () => {
  const home = tempHome();
  const binDir = path.join(home, 'bin');
  fs.mkdirSync(binDir, { recursive: true });
  const toolName = process.platform === 'win32' ? 'fakedep-tool.cmd' : 'fakedep-tool';
  const target = path.join(binDir, toolName);
  const body = process.platform === 'win32' ? '@echo off\r\necho 1.2.3\r\n' : '#!/bin/sh\necho 1.2.3\n';
  const originalPath = process.env.PATH;
  process.env.PATH = `${binDir}${path.delimiter}${originalPath}`;
  process.env.FAKE_TARGET = target;
  process.env.FAKE_BODY = body;
  try {
    const dep = {
      id: 'fakedep',
      verify: { cmd: 'fakedep-tool', args: ['--version'], minVersion: '1.0.0' },
      install: {
        win: [{ cmd: 'node', args: ['-e', "require('fs').writeFileSync(process.env.FAKE_TARGET, process.env.FAKE_BODY)"] }],
        unix: [{ cmd: 'node', args: ['-e', "require('fs').writeFileSync(process.env.FAKE_TARGET, process.env.FAKE_BODY, { mode: 0o755 })"] }]
      },
      guidance: ['x']
    };
    const ctx = { mode: 'install', opts: { yes: true }, interactive: false, prompt: { ask: async () => '' } };
    const res = await D.ensureDependency(dep, ctx, { requiredBy: ['memorix'] });
    assert.equal(res.status, 'installed', JSON.stringify(res));
    assert.ok(res.detail.includes('1.2.3'));
  } finally {
    process.env.PATH = originalPath;
    delete process.env.FAKE_TARGET;
    delete process.env.FAKE_BODY;
  }
});

test('every MCP server and agent binary ships installGuidance for the failure path', () => {
  const manifests = M.loadManifests(ROOT);
  for (const server of manifests.mcp.servers) {
    assert.ok(Array.isArray(server.installGuidance) && server.installGuidance.length > 0, `${server.id} missing installGuidance`);
  }
  for (const agent of manifests.agents.agents) {
    assert.ok(Array.isArray(agent.binary.installGuidance) && agent.binary.installGuidance.length > 0, `${agent.id} missing installGuidance`);
  }
});

// ---------------------------------------------------------------- check-first
function fakeBin(dir, name, output) {
  const file = process.platform === 'win32' ? path.join(dir, `${name}.cmd`) : path.join(dir, name);
  const body = process.platform === 'win32' ? `@echo off\r\necho ${output}\r\n` : `#!/bin/sh\necho ${output}\n`;
  fs.writeFileSync(file, body, { mode: 0o755 });
  return file;
}

test('check-first: assessCommand distinguishes ok / outdated / mismatch / broken / missing', () => {
  const dir = tempHome();
  const original = process.env.PATH;
  process.env.PATH = `${dir}${path.delimiter}${original}`;
  try {
    fakeBin(dir, 'toolexact', '2.0.0');
    fakeBin(dir, 'toolold', '1.0.0');
    fakeBin(dir, 'toolbroken', 'not-a-version');
    assert.equal(D.assessCommand('toolexact', ['--version'], { version: '2.0.0' }).state, 'ok');
    assert.equal(D.assessCommand('toolexact', ['--version'], { version: '3.0.0' }).state, 'mismatch');
    assert.equal(D.assessCommand('toolold', ['--version'], { minVersion: '2.0.0' }).state, 'outdated');
    assert.equal(D.assessCommand('toolbroken', ['--version'], { minVersion: '1.0.0' }).state, 'broken');
    assert.equal(D.assessCommand('toolmissing-xyz', ['--version']).state, 'missing');
  } finally {
    process.env.PATH = original;
  }
});

test('check-first: doctor reports a version pin mismatch without asking questions', () => {
  const home = tempHome();
  const binDir = path.join(home, 'bin');
  fs.mkdirSync(binDir, { recursive: true });
  fakeBin(binDir, 'mcp-atlassian', '0.22.0');
  const ompDir = path.join(home, '.omp', 'agent');
  fs.mkdirSync(ompDir, { recursive: true });
  fs.writeFileSync(path.join(ompDir, 'mcp.json'), JSON.stringify({ mcpServers: { 'company-atlassian': { command: 'mcp-atlassian', args: [] } } }, null, 2));
  const minimalPath = process.platform === 'win32'
    ? [binDir, path.join(process.env.SystemRoot || 'C:\\Windows', 'System32'), process.env.SystemRoot || 'C:\\Windows'].join(path.delimiter)
    : [binDir, '/usr/bin', '/bin'].join(path.delimiter);
  const env = {
    ...process.env,
    PATH: minimalPath,
    USERPROFILE: home,
    HOME: home,
    APPDATA: path.join(home, 'AppData', 'Roaming'),
    SETUP_RESUME_ENV_PATH: path.join(home, 'resume.env')
  };
  const result = spawnSync(process.execPath, [ENGINE, '--target', 'omp', '--mcp', 'company-atlassian', '--doctor', '--json'], { env, encoding: 'utf8', timeout: 120000 });
  const payload = JSON.parse(result.stdout);
  const versionRow = payload.results.find((r) => r.check === 'version:company-atlassian');
  assert.ok(versionRow, 'doctor must emit a version check for mcp-atlassian');
  assert.equal(versionRow.status, 'FAIL');
  assert.match(versionRow.detail, /0\.22\.0/);
});



test('mergeYamlLayer keeps user entries, replaces managed ones and drops de-selected MCP', () => {
  const existing = [
    '# user header',
    '- id: llm-pi-ai',
    '  config:',
    '    providers:',
    '      deepseek:',
    '        baseURL: http://user.local/v1',
    '- id: plugin-market',
    '  config:',
    '    indexes:',
    '      - https://user.example/index.json',
    '- id: mcp-memorix',
    '  name: "@deepseek-ai/dsh-mcp-client"',
    '- id: mcp-agency',
    '  name: "@deepseek-ai/dsh-mcp-client"',
    ''
  ].join('\n');
  const template = ['- id: llm-pi-ai', '  config:', '    x: 1', '- id: mcp-context7', '  name: tpl', ''].join('\n');
  const merged = R.mergeYamlLayer(existing, template, { managedMcpIds: ['memorix', 'context7'], ownIds: ['llm-pi-ai'] });
  assert.ok(merged.startsWith('# user header'), 'user preamble is kept');
  assert.ok(!merged.includes('user.local'), 'template-owned entry is replaced');
  assert.ok(merged.includes('user.example'), 'unknown user entry survives');
  assert.ok(!merged.includes('mcp-memorix'), 'de-selected MCP entry is removed');
  assert.ok(merged.includes('- id: mcp-context7'), 'selected MCP entry is kept once');
  assert.equal(merged.match(/^- id: mcp-context7$/gm).length, 1, 'no duplicate MCP entry');
});

test('mergeYamlLayer diffs insert items by id and keeps the rest', () => {
  const existing = [
    '- insert:',
    '    - id: memory-memorix',
    '      config:',
    '        command: memorix',
    '    - id: user-own-plugin',
    '      name: whatever',
    ''
  ].join('\n');
  const template = ['- insert:', '    - id: memory-memorix', '      config:', '        command: memorix-new', ''].join('\n');
  const merged = R.mergeYamlLayer(existing, template, { managedInsertIds: ['memory-memorix'] });
  assert.ok(merged.includes('user-own-plugin'), 'unmanaged insert item survives');
  assert.ok(merged.includes('memorix-new'), 'managed insert item is replaced');
  assert.equal(merged.match(/id: memory-memorix/g).length, 1, 'managed insert item is not duplicated');
});

test('dsh re-run keeps user profile entries and existing skills', () => {
  const home = tempHome();
  const profile = path.join(home, '.dsh', 'profiles', 'web');
  fs.mkdirSync(profile, { recursive: true });
  const patch = path.join(profile, 'cordis.patch.yml');
  fs.writeFileSync(patch, [
    '- id: llm-pi-ai',
    '  name: "@deepseek-ai/dsh-llm-pi-ai"',
    '  config:',
    '    providers:',
    '      deepseek:',
    '        baseURL: http://keep.me/v1',
    '- id: plugin-market',
    '  config:',
    '    indexes:',
    '      - https://keep.example/index.json',
    '- id: ui-theme',
    '  config:',
    '    fontSize: 13',
    '',
    '# keep-tail-comment',
    ''
  ].join('\n'));
  const skills = path.join(home, '.dsh', 'skills');
  fs.mkdirSync(path.join(skills, 'delivery'), { recursive: true });
  fs.mkdirSync(path.join(skills, 'skills'), { recursive: true });

  const created = runEngine(['--target', 'dsh', '--yes', '--skip-install', '--mcp', 'context7', '--overwrite-all'], home);
  assert.equal(created.status, 0, created.stderr);
  const after = fs.readFileSync(patch, 'utf8');
  assert.ok(after.includes('keep.example'), 'user entry survives an install run');
  assert.ok(after.includes('keep-tail-comment'), 'user comment survives an install run');
  assert.ok(after.includes('- id: mcp-context7'), 'selected MCP is written');
  assert.ok(fs.existsSync(path.join(skills, 'delivery')), 'existing skill is preserved');
  assert.ok(fs.existsSync(path.join(skills, 'skills')), 'unowned skill directory is preserved');
  assert.ok(fs.existsSync(path.join(skills, 'create-plan', 'SKILL.md')), 'canonical skills are installed');
});

test('dsh installs the local safe-fs-replace plugin once (idempotent)', () => {
  const home = tempHome();
  const args = ['--target', 'dsh', '--yes', '--skip-install', '--mcp', 'none'];
  const first = runEngine(args, home);
  assert.equal(first.status, 0, first.stderr);
  const second = runEngine(args, home);
  assert.equal(second.status, 0, second.stderr);

  const plugin = path.join(home, '.dsh', 'local-plugins', 'safe-fs-replace.js');
  assert.ok(fs.existsSync(plugin), 'plugin file is copied');
  const source = fs.readFileSync(plugin, 'utf8');
  assert.ok(source.includes("export const name = 'safe-fs-replace'"), 'plugin exports its name');

  const patch = fs.readFileSync(path.join(home, '.dsh', 'profiles', 'web', 'cordis.patch.yml'), 'utf8');
  const occurrences = patch.split('- id: safe-fs-replace').length - 1;
  assert.equal(occurrences, 1, 'plugin entry must be registered exactly once after two runs');
  const retryOccurrences = patch.split('- id: llm-retry').length - 1;
  assert.equal(retryOccurrences, 1, 'llm-retry must be registered exactly once after two runs');
  assert.ok(patch.includes('retryPolicy:'), 'retryPolicy is registered in cordis.patch.yml');
  assert.ok(patch.includes('maxRetries: 5'), 'maxRetries is configured');
  assert.ok(patch.includes('name: "file:///'), 'plugin name is an absolute file URL');
  assert.ok(!patch.includes('\\\\'), 'file URL uses forward slashes');
});

test('dsh install never overwrites existing credentials', () => {
  const home = tempHome();
  const credDir = path.join(home, 'AppData', 'Roaming', 'dsh-desktop', 'harness');
  fs.mkdirSync(credDir, { recursive: true });
  const cred = path.join(credDir, '.credentials.yaml');
  const original = 'version: 1\nrefs:\n  DEEPSEEK_API_KEY: real-secret\nrecords:\n  keep: me\n';
  fs.writeFileSync(cred, original);
  const result = runEngine(['--target', 'dsh', '--yes', '--skip-install', '--overwrite-all'], home);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.readFileSync(cred, 'utf8'), original, 'credentials file is preserved');
});

test('dsh install writes the home-level memorix patch only when memorix is selected', () => {
  const withMemorix = tempHome();
  runEngine(['--target', 'dsh', '--yes', '--skip-install', '--memorix'], withMemorix);
  const homePatch = path.join(withMemorix, '.dsh', 'cordis.patch.yml');
  assert.ok(fs.existsSync(homePatch), 'home patch is written when memorix is on');
  assert.ok(fs.readFileSync(homePatch, 'utf8').includes('memory-memorix'));

  const without = tempHome();
  runEngine(['--target', 'dsh', '--yes', '--skip-install', '--no-memorix'], without);
  assert.ok(!fs.existsSync(path.join(without, '.dsh', 'cordis.patch.yml')), 'home patch is not written without memorix');
});

test('mergeYamlLayer lets an existing entry win unless the template owns it', () => {
  const existing = ['- id: ui-theme', '  config:', '    fontSize: 13', '- id: agent-default-model', '  config:', '    model: stale', ''].join('\n');
  const template = ['- id: ui-theme', '  config:', '    fontSize: 12', '- id: agent-default-model', '  config:', '    model: pinned', ''].join('\n');
  const merged = R.mergeYamlLayer(existing, template, { ownIds: ['agent-default-model'] });
  assert.ok(merged.includes('fontSize: 13'), 'non-owned user value wins');
  assert.ok(!merged.includes('fontSize: 12'), 'template default does not override a user value');
  assert.ok(merged.includes('model: pinned'), 'owned entry is replaced by the template');
});

test('dsh install preserves the live baseURL unless AI_BASE_URL is supplied', () => {
  const scenario = (envFileValue) => {
    const home = tempHome();
    const profile = path.join(home, '.dsh', 'profiles', 'web');
    fs.mkdirSync(profile, { recursive: true });
    const patch = path.join(profile, 'cordis.patch.yml');
    fs.writeFileSync(patch, [
      '- id: llm-pi-ai',
      '  config:',
      '    providers:',
      '      deepseek:',
      '        baseURL: http://keep.me:1234/v1',
      ''
    ].join('\n'));
    const args = ['--target', 'dsh', '--yes', '--skip-install', '--mcp', 'none'];
    if (envFileValue) {
      const envFile = path.join(home, 'vars.env');
      fs.writeFileSync(envFile, `AI_BASE_URL=${envFileValue}\n`);
      args.push('--env-file', envFile);
    }
    const result = runEngine(args, home);
    assert.equal(result.status, 0, result.stderr);
    return fs.readFileSync(patch, 'utf8');
  };
  assert.ok(scenario(null).includes('http://keep.me:1234/v1'), 'existing endpoint survives a re-run');
  assert.ok(scenario('http://new.me:9999/v1').includes('http://new.me:9999/v1'), 'explicit AI_BASE_URL wins');
});
test('dsh syncs cordis.patch.yml to desktop profile when present, preserving legacy presets with block scalars', () => {
  const home = tempHome();
  const cliProfile = path.join(home, '.dsh', 'profiles', 'web');
  const desktopProfile = path.join(home, 'AppData', 'Roaming', 'dsh-desktop', 'harness', 'profiles', 'web');
  fs.mkdirSync(cliProfile, { recursive: true });
  fs.mkdirSync(desktopProfile, { recursive: true });

  const legacyBlock = [
    '# dsh-desktop legacy presets begin',
    '- insert:',
    '    - id: preset-architect',
    '      config:',
    '        prefix: >-',
    '          Multiline architectural guidance with special block scalars.',
    '        section: |',
    '          Another literal block scalar with code and newlines.',
    '# dsh-desktop legacy presets end',
    ''
  ].join('\n');

  const initialDesktop = [
    '- id: ui-theme',
    '  config:',
    '    fontSize: 14',
    legacyBlock
  ].join('\n');

  fs.writeFileSync(path.join(desktopProfile, 'cordis.patch.yml'), initialDesktop);

  const result = runEngine(['--target', 'dsh', '--yes', '--skip-install', '--mcp', 'context7'], home);
  assert.equal(result.status, 0, result.stderr);

  const desktopContent = fs.readFileSync(path.join(desktopProfile, 'cordis.patch.yml'), 'utf8');
  assert.ok(desktopContent.includes('- id: mcp-context7'), 'MCP server is synced to desktop profile');
  assert.ok(desktopContent.includes('- id: safe-fs-replace'), 'safe-fs-replace plugin is synced to desktop profile');
  assert.ok(desktopContent.includes('# DSH fix: ReplaceFileW'), 'comment banner has # prefix');
  assert.ok(desktopContent.includes('# dsh-desktop legacy presets begin'), 'legacy presets begin marker is preserved');
  assert.ok(desktopContent.includes('prefix: >-'), 'block scalar prefix is preserved');
  assert.ok(desktopContent.includes('section: |'), 'literal block scalar is preserved');
  assert.ok(desktopContent.includes('# dsh-desktop legacy presets end'), 'legacy presets end marker is preserved');
});

test('dsh syncs safe-fs-replace to desktop profile even when CLI profile already has it registered', () => {
  const home = tempHome();
  const cliProfile = path.join(home, '.dsh', 'profiles', 'web');
  const desktopProfile = path.join(home, 'AppData', 'Roaming', 'dsh-desktop', 'harness', 'profiles', 'web');
  fs.mkdirSync(cliProfile, { recursive: true });
  fs.mkdirSync(desktopProfile, { recursive: true });

  fs.writeFileSync(path.join(cliProfile, 'cordis.patch.yml'), [
    '- id: ui-theme',
    '- insert:',
    '  - id: safe-fs-replace',
    '    name: "file:///already/registered.js"',
    ''
  ].join('\n'));

  fs.writeFileSync(path.join(desktopProfile, 'cordis.patch.yml'), [
    '- id: ui-theme',
    ''
  ].join('\n'));

  const result = runEngine(['--target', 'dsh', '--yes', '--skip-install', '--mcp', 'none'], home);
  assert.equal(result.status, 0, result.stderr);

  const desktopContent = fs.readFileSync(path.join(desktopProfile, 'cordis.patch.yml'), 'utf8');
  assert.ok(desktopContent.includes('- id: safe-fs-replace'), 'safe-fs-replace is synced to desktop profile even if CLI was already registered');
});


// ------------------------------------------------------- regressions (v1.0.5)
test('run resolves a bare command name through PATH', () => {
  // Bare `npm`/`npx` are .cmd shims on Windows; spawnSync returns ENOENT unless resolved.
  const r = U.run(process.execPath, ['-e', 'process.stdout.write("ok")'], { allowFail: true, timeout: 60000 });
  assert.equal(r.ok, true, r.stderr);
  assert.equal(r.stdout.trim(), 'ok');
});

test('run resolves a Windows .cmd shim without shell:true', (t) => {
  if (process.platform !== 'win32') return; // shim behaviour is Windows-only
  // Real npm is a host CLI: opt-in only, never in the default run.
  if (process.env.SAC_TEST_REAL_CLI !== '1') { t.skip('dat SAC_TEST_REAL_CLI=1 de chay npm that'); return; }
  const r = U.run('npm', ['--version'], { allowFail: true, timeout: 120000 });
  assert.equal(r.ok, true, `npm must resolve through PATH, got: ${r.stderr}`);
  assert.match(r.stdout.trim(), /^\d+\.\d+\.\d+/, 'npm reports a version');
});

test('dsh detects a guard plugin already installed in the profile', () => {
  const home = tempHome();
  const profile = path.join(home, '.dsh', 'profiles', 'web');
  fs.mkdirSync(profile, { recursive: true });
  fs.writeFileSync(
    path.join(profile, 'package.json'),
    JSON.stringify({
      name: 'dsh-profile-web',
      dependencies: { 'cc-safety-net': '2.7.2' },
      dsh: { profile: { bundles: ['cc-safety-net'] } }
    })
  );
  const binDir = path.join(profile, 'node_modules', '.bin');
  fs.mkdirSync(binDir, { recursive: true });
  const isWin = process.platform === 'win32';
  fs.writeFileSync(
    path.join(binDir, isWin ? 'cc-safety-net.cmd' : 'cc-safety-net'),
    isWin ? '@echo off\r\nif "%1"=="status" exit /b 0\r\nexit /b 1\r\n' : '#!/bin/sh\n[ "$1" = status ]\n',
    { mode: 0o755 }
  );
  const result = runEngine(['--target', 'dsh', '--yes', '--skip-install', '--mcp', 'none'], home);
  assert.equal(result.status, 0, result.stderr);
  assert.ok(
    result.stdout.includes('cc-safety-net: kiem tra thanh cong (exit 0)'),
    `existing profile plugin must be detected, got:\n${result.stdout}`
  );
  assert.ok(
    !result.stdout.includes('chua cai'),
    'installer must not report an installed plugin as missing'
  );
});

// ------------------------------------------------------- regressions (v1.0.6)
test('json config merge never deletes user keys, even with --overwrite-all', () => {
  // Regression: a non-interactive run (policy=overwrite) replaced settings.json
  // and destroyed the user's own PreToolUse hooks.
  const home = tempHome();
  const claude = path.join(home, '.claude');
  fs.mkdirSync(claude, { recursive: true });
  const userHook = { matcher: '*', hooks: [{ type: 'command', command: 'C:/user/orca-hook.exe', timeout: 10 }] };
  fs.writeFileSync(
    path.join(claude, 'settings.json'),
    JSON.stringify({ env: { USER_KEEP: '1' }, hooks: { PreToolUse: [userHook] }, userSetting: true }, null, 2)
  );
  const result = runEngine(['--target', 'claude-code', '--yes', '--skip-install', '--mcp', 'none', '--overwrite-all'], home);
  assert.equal(result.status, 0, result.stderr);
  const after = JSON.parse(fs.readFileSync(path.join(claude, 'settings.json'), 'utf8'));
  assert.equal(after.userSetting, true, 'unknown user key must survive');
  assert.equal(after.env.USER_KEEP, '1', 'user env key must survive');
  const commands = after.hooks.PreToolUse.flatMap((g) => (g.hooks || []).map((h) => h.command));
  assert.ok(commands.includes('C:/user/orca-hook.exe'), `user hook must survive, got ${JSON.stringify(commands)}`);
  assert.ok(commands.some((c) => c.includes('pre-tool.mjs')), 'installer hook must be present');
});

test('claude hook is registered in the nested shape Claude Code expects', () => {
  const home = tempHome();
  const result = runEngine(['--target', 'claude-code', '--yes', '--skip-install', '--mcp', 'none'], home);
  assert.equal(result.status, 0, result.stderr);
  const settings = JSON.parse(fs.readFileSync(path.join(home, '.claude', 'settings.json'), 'utf8'));
  const entry = settings.hooks.PreToolUse.find((g) => (g.hooks || []).some((h) => String(h.command).includes('pre-tool.mjs')));
  assert.ok(entry, 'a PreToolUse group must register the trash guard');
  assert.equal(typeof entry.matcher, 'string');
  const handler = entry.hooks[0];
  assert.equal(handler.type, 'command', 'handlers must carry type: command');
  assert.equal(typeof handler.timeout, 'number');
});

test('toml config merge keeps a user-added MCP server block', () => {
  // Regression: codex config.toml was rewritten and dropped [mcp_servers."9remote"].
  const home = tempHome();
  const codex = path.join(home, '.codex');
  fs.mkdirSync(codex, { recursive: true });
  const userBlock = [
    '# 9Remote MCP (9remote)',
    '[mcp_servers."9remote"]',
    'url = "http://127.0.0.1:2208/mcp"',
    '[mcp_servers."9remote".http_headers]',
    'Authorization = "Bearer user-token"',
    '# /9Remote MCP',
    ''
  ].join('\n');
  fs.writeFileSync(path.join(codex, 'config.toml'), `model = "codex-5"\n\n${userBlock}`);
  const result = runEngine(['--target', 'codex-cli', '--yes', '--skip-install', '--mcp', 'memorix'], home);
  assert.equal(result.status, 0, result.stderr);
  const text = fs.readFileSync(path.join(codex, 'config.toml'), 'utf8');
  assert.ok(text.includes('[mcp_servers."9remote"]'), 'user MCP server must survive');
  assert.ok(text.includes('Bearer user-token'), 'user credentials must survive');
  assert.ok(text.includes('# 9Remote MCP (9remote)'), 'user comment must survive');
  assert.ok(text.includes('[mcp_servers.memorix]'), 'managed MCP server must be written');
});

test('toml merge keeps live scalars, user tables and drops de-selected MCP', () => {
  // Regression: re-running the installer rewrote model_provider and dropped the
  // user's own MCP servers, providers and hook bookkeeping.
  const home = tempHome();
  const codex = path.join(home, '.codex');
  fs.mkdirSync(codex, { recursive: true });
  fs.writeFileSync(path.join(codex, 'config.toml'), [
    'model = "claude-sonnet"',
    'model_provider = "9router"',
    '',
    '[model_providers.9router]',
    'base_url = "http://127.0.0.1:20128/v1"',
    'wire_api = "responses"',
    '',
    '[mcp_servers."9remote"]',
    'url = "http://127.0.0.1:2208/mcp"',
    '',
    '[mcp_servers.memorix]',
    'command = "memorix"',
    'args = ["serve"]',
    '',
    '[hooks.state]',
    'trusted = true',
    ''
  ].join('\n'));
  const result = runEngine(['--target', 'codex-cli', '--yes', '--skip-install', '--mcp', 'none'], home);
  assert.equal(result.status, 0, result.stderr);
  const text = fs.readFileSync(path.join(codex, 'config.toml'), 'utf8');
  assert.ok(text.includes('model_provider = "9router"'), 'live model_provider must survive');
  assert.ok(text.includes('model = "claude-sonnet"'), 'live model must survive');
  assert.ok(text.includes('[model_providers.9router]'), 'user provider table must survive');
  assert.ok(text.includes('[mcp_servers."9remote"]'), 'user MCP server must survive');
  assert.ok(text.includes('[hooks.state]'), 'user hook table must survive');
  assert.ok(!text.includes('[mcp_servers.memorix]'), 'de-selected MCP must be removed');
  assert.equal((text.match(/^model = /gm) || []).length, 1, 'no duplicated scalar');
  assert.equal((text.match(/^model_provider = /gm) || []).length, 1, 'no duplicated scalar');
});

test('empty placeholder never erases a live config value', () => {
  // Regression: a missing .env blanked api_key in codex config.toml.
  const home = tempHome();
  const codex = path.join(home, '.codex');
  fs.mkdirSync(codex, { recursive: true });
  fs.writeFileSync(path.join(codex, 'config.toml'), 'model = "codex-5"\napi_key = "live-secret"\n');
  const result = runEngine(['--target', 'codex-cli', '--yes', '--skip-install', '--mcp', 'none'], home);
  assert.equal(result.status, 0, result.stderr);
  const text = fs.readFileSync(path.join(codex, 'config.toml'), 'utf8');
  assert.ok(text.includes('api_key = "live-secret"'), `live api_key must survive, got:\n${text}`);
});

