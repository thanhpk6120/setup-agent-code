// Run with: node --test tests/skills-safety.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

test('P9 preserves user skills and adds missing canonical skills without memorix', () => {
  // Isolated home inside the workspace; kept for inspection on failure, never deleted.
  const root = path.join(ROOT, 'tests', '.tmp-engine');
  fs.mkdirSync(root, { recursive: true });
  const home = fs.mkdtempSync(path.join(root, 'skills-safety-home-'));
  const skills = path.join(home, '.omp', 'agent', 'skills');
  fs.writeFileSync(path.join(home, 'empty.env'), '');
  const fixtures = {
    'custom-user-skill': 'custom skill owned by user\n',
    'create-plan': 'user content in canonical name\n',
    'memorix-memory': 'user memorix content\n'
  };
  for (const [name, content] of Object.entries(fixtures)) {
    const dir = path.join(skills, name);
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'SKILL.md'), content);
    fs.writeFileSync(path.join(dir, 'user-extra.txt'), `extra: ${name}\n`);
  }

  const env = {
    ...process.env,
    HOME: home,
    USERPROFILE: home,
    HOMEDRIVE: path.parse(home).root.slice(0, 2),
    HOMEPATH: home.slice(path.parse(home).root.length - 1),
    APPDATA: path.join(home, 'AppData', 'Roaming'),
    LOCALAPPDATA: path.join(home, 'AppData', 'Local'),
    XDG_CONFIG_HOME: path.join(home, '.config'),
    TEMP: home,
    TMP: home,
    TMPDIR: home,
    PATH: home,
    SETUP_RESUME_ENV_PATH: path.join(home, 'resume.env')
  };
  const result = spawnSync(process.execPath, [
    path.join(ROOT, 'core', 'engine.mjs'), '--target', 'omp', '--yes', '--skip-install',
    '--mcp', 'none', '--no-memorix', '--env-file', path.join(home, 'empty.env'), '--quiet'
  ], { cwd: home, env, encoding: 'utf8', timeout: 180000 });
  assert.equal(result.status, 0, `${result.error || ''}\n${result.stdout}\n${result.stderr}`);

  for (const [name, content] of Object.entries(fixtures)) {
    assert.equal(fs.readFileSync(path.join(skills, name, 'SKILL.md'), 'utf8'), content);
    assert.equal(fs.readFileSync(path.join(skills, name, 'user-extra.txt'), 'utf8'), `extra: ${name}\n`);
  }
  const missing = 'poka-yoke';
  assert.equal(
    fs.readFileSync(path.join(skills, missing, 'SKILL.md'), 'utf8'),
    fs.readFileSync(path.join(ROOT, 'skills', missing, 'SKILL.md'), 'utf8')
  );
  assert.equal(fs.existsSync(path.join(skills, 'memorix-sessions')), false);
});
