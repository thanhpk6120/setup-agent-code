import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { STANDARD_AGENTS, parseArgs, resolveDefaultStorageDir, setupAgentTeamIde } from './setup.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function makeTempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'agent-team-ide-setup-'));
}

test('resolveDefaultStorageDir returns OS-specific globalStorage path', () => {
  const win = resolveDefaultStorageDir('win32', { APPDATA: 'C:\\Users\\Test\\AppData\\Roaming' }, 'C:\\Users\\Test');
  assert.equal(win, path.join('C:\\Users\\Test\\AppData\\Roaming', 'Agent Team', 'User', 'globalStorage', 'agent-team.agent-team'));

  const mac = resolveDefaultStorageDir('darwin', {}, '/Users/test');
  assert.equal(mac, path.join('/Users/test', 'Library', 'Application Support', 'Agent Team', 'User', 'globalStorage', 'agent-team.agent-team'));

  const linux = resolveDefaultStorageDir('linux', { XDG_CONFIG_HOME: '/home/test/.xdg' }, '/home/test');
  assert.equal(linux, path.join('/home/test/.xdg', 'Agent Team', 'User', 'globalStorage', 'agent-team.agent-team'));
});

test('fresh install creates all 19 role agents and installs grilling skill', () => {
  const dir = makeTempDir();
  const res = setupAgentTeamIde({ storageDir: dir });

  assert.equal(res.totalAgents, STANDARD_AGENTS.length);
  assert.equal(res.addedAgents.length, STANDARD_AGENTS.length);
  assert.equal(res.agentsChanged, true);
  assert.equal(res.backupFile, null);
  assert.ok(res.copiedSkillFiles >= 2);

  const saved = JSON.parse(fs.readFileSync(path.join(dir, 'agents.json'), 'utf8'));
  assert.equal(saved.version, 1);
  assert.equal(saved.agents.length, 19);

  const orch = saved.agents.find((a) => a.id === 'orchestrator');
  assert.deepEqual(orch.skills, ['grilling']);

  const planner = saved.agents.find((a) => a.id === 'planner');
  assert.deepEqual(planner.skills, ['grilling']);

  const coder = saved.agents.find((a) => a.id === 'coder');
  assert.equal(coder.skills, undefined);

  assert.ok(fs.existsSync(path.join(dir, 'skills', 'grilling', 'SKILL.md')));
  assert.ok(fs.existsSync(path.join(dir, 'skills', 'grilling', 'agents', 'openai.yaml')));
});

test('cleans bloated skills, preserves custom agents and profileId, and creates backup', () => {
  const dir = makeTempDir();
  const existing = {
    version: 1,
    agents: [
      {
        id: 'orchestrator',
        name: 'Orchestrator',
        cliId: 'antigravity',
        profileId: 'custom-profile',
        roleId: 'orchestrator',
        model: 'gemini-4-hydrogen-medium',
        permissionMode: 'agent',
        mcpServers: [],
        createdAt: 1000,
        skills: ['se-code-review', 'orca-computer-use', 'grilling', 'grilling-2'],
      },
      {
        id: 'coder',
        name: 'Coder',
        cliId: 'antigravity',
        profileId: 'custom-profile',
        roleId: 'coder',
        model: 'gemini-4-hydrogen-low',
        permissionMode: 'agent',
        mcpServers: [],
        createdAt: 1001,
        skills: ['se-spec', 'orca-computer-use', 'grilling'],
      },
      {
        id: 'planer',
        name: 'Planer',
        cliId: 'antigravity',
        profileId: 'custom-profile',
        model: 'gemini-4-argon-medium',
        permissionMode: 'agent',
        mcpServers: [],
        createdAt: 1002,
        skills: ['se-spec', 'grilling'],
      },
    ],
  };
  fs.writeFileSync(path.join(dir, 'agents.json'), JSON.stringify(existing, null, 2), 'utf8');

  const res = setupAgentTeamIde({ storageDir: dir });
  assert.equal(res.totalAgents, 20);
  assert.equal(res.addedAgents.length, 17);
  assert.deepEqual(res.cleanedAgents.sort(), ['coder', 'orchestrator']);
  assert.ok(res.backupFile && fs.existsSync(res.backupFile));

  const saved = JSON.parse(fs.readFileSync(path.join(dir, 'agents.json'), 'utf8'));
  const orch = saved.agents.find((a) => a.id === 'orchestrator');
  assert.deepEqual(orch.skills, ['grilling']);

  const coder = saved.agents.find((a) => a.id === 'coder');
  assert.equal(coder.skills, undefined);

  const customPlaner = saved.agents.find((a) => a.id === 'planer');
  assert.deepEqual(customPlaner.skills, ['se-spec', 'grilling']);

  const architect = saved.agents.find((a) => a.id === 'architect');
  assert.equal(architect.profileId, 'custom-profile');
});

test('is idempotent on repeated runs', () => {
  const dir = makeTempDir();
  setupAgentTeamIde({ storageDir: dir });
  const second = setupAgentTeamIde({ storageDir: dir });

  assert.equal(second.totalAgents, 19);
  assert.deepEqual(second.addedAgents, []);
  assert.deepEqual(second.cleanedAgents, []);
  assert.equal(second.agentsChanged, false);
  assert.equal(second.copiedSkillFiles, 0);
});

test('dry-run makes no disk changes', () => {
  const dir = makeTempDir();
  const res = setupAgentTeamIde({ storageDir: dir, dryRun: true });

  assert.equal(res.dryRun, true);
  assert.equal(res.totalAgents, 19);
  assert.equal(fs.existsSync(path.join(dir, 'agents.json')), false);
  assert.equal(fs.existsSync(path.join(dir, 'skills', 'grilling')), false);
});

test('CLI execution via setup.mjs --json works end-to-end', () => {
  const dir = makeTempDir();
  const out = execFileSync(
    process.execPath,
    [path.join(__dirname, 'setup.mjs'), '--storage-dir', dir, '--json'],
    { encoding: 'utf8' }
  );
  const parsed = JSON.parse(out);
  assert.equal(parsed.totalAgents, 19);
  assert.ok(fs.existsSync(path.join(dir, 'agents.json')));
});

test('malformed or empty agents.json throws clear error with file path', () => {
  const dir = makeTempDir();
  const file = path.join(dir, 'agents.json');
  fs.writeFileSync(file, '', 'utf8');
  assert.throws(() => setupAgentTeamIde({ storageDir: dir }), /Empty agents\.json/);

  fs.writeFileSync(file, '{bad json', 'utf8');
  assert.throws(() => setupAgentTeamIde({ storageDir: dir }), /Malformed JSON/);
});

test('switching --cli does not inherit antigravity profileId from orchestrator', () => {
  const dir = makeTempDir();
  setupAgentTeamIde({ storageDir: dir });
  const updated = setupAgentTeamIde({ storageDir: dir, cliId: 'codex' });
  assert.equal(updated.cliId, 'codex');
  assert.equal(updated.profileId, null);
});

test('supports --no-clean-skills, --force, and dry-run preview on existing dir', () => {
  const dir = makeTempDir();
  fs.writeFileSync(path.join(dir, 'agents.json'), JSON.stringify({
    version: 1,
    customMeta: 'keep-me',
    agents: [
      { id: 'orchestrator', name: 'Orchestrator', cliId: 'antigravity', roleId: 'orchestrator', skills: ['se-code-review'] },
    ],
  }), 'utf8');

  const dry = setupAgentTeamIde({ storageDir: dir, dryRun: true });
  assert.ok(dry.copiedSkillFiles >= 2);
  assert.deepEqual(dry.cleanedAgents, ['orchestrator']);

  const noClean = setupAgentTeamIde({ storageDir: dir, cleanSkills: false });
  assert.deepEqual(noClean.cleanedAgents, []);
  const saved = JSON.parse(fs.readFileSync(path.join(dir, 'agents.json'), 'utf8'));
  assert.equal(saved.customMeta, 'keep-me');
  assert.deepEqual(saved.agents.find((a) => a.id === 'orchestrator').skills, ['se-code-review']);

  const skillFile = path.join(dir, 'skills', 'grilling', 'SKILL.md');
  fs.writeFileSync(skillFile, 'modified', 'utf8');
  const forced = setupAgentTeamIde({ storageDir: dir, force: true });
  assert.ok(forced.copiedSkillFiles >= 2);
  assert.notEqual(fs.readFileSync(skillFile, 'utf8'), 'modified');
});

test('parseArgs handles inline values and rejects missing flag values', () => {
  const ok = parseArgs(['--storage-dir=/tmp/x', '--cli=codex', '--dry-run']);
  assert.equal(ok.storageDir, '/tmp/x');
  assert.equal(ok.cliId, 'codex');
  assert.equal(ok.dryRun, true);

  assert.throws(() => parseArgs(['--storage-dir', '--dry-run']), /Missing value/);
  assert.throws(() => parseArgs(['--storage-dir=']), /Missing value/);
  assert.throws(() => parseArgs(['--dry-run=false']), /does not take a value/);
  assert.throws(() => parseArgs(['--unknown-flag']), /Unknown or incomplete option/);
});
