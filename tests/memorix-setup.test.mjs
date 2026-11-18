import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

test('memorix templates contain no real OpenRouter secrets', () => {
  const example = fs.readFileSync(path.join(ROOT, 'templates/memorix/config.toml.example'), 'utf8');
  assert.doesNotMatch(example, /sk-or-v1-[a-zA-Z0-9]{20,}/);
  assert.match(example, /<OPENROUTER_API_KEY>/);
  assert.match(example, /baidu\/ernie-5\.5-flash-preview:free/);
});

test('setup-memorix.mjs populates isolated home without overwriting existing config.toml', () => {
  const fakeHome = fs.mkdtempSync(path.join(os.tmpdir(), 'memorix-setup-test-'));
  try {
    const res = spawnSync(
      process.execPath,
      [
        path.join(ROOT, 'scripts/setup-memorix.mjs'),
        '--home', fakeHome,
        '--api-key', 'sk-test-placeholder',
        '--skip-fastembed',
        '--no-autostart'
      ],
      { encoding: 'utf8', timeout: 15000 }
    );
    assert.equal(res.status, 0, res.stderr || res.stdout);

    assert.ok(fs.existsSync(path.join(fakeHome, 'mcp-servers/memorix/memorix-mcp-wrapper.mjs')));
    assert.ok(fs.existsSync(path.join(fakeHome, '.memorix/ensure-serve-http.mjs')));
    assert.ok(fs.existsSync(path.join(fakeHome, '.memorix/prune-snapshots.mjs')));

    const cfgPath = path.join(fakeHome, '.memorix/config.toml');
    assert.ok(fs.existsSync(cfgPath));
    const cfg1 = fs.readFileSync(cfgPath, 'utf8');
    assert.match(cfg1, /api_key = "sk-test-placeholder"/);

    fs.writeFileSync(cfgPath, 'custom = true\n', 'utf8');
    const res2 = spawnSync(
      process.execPath,
      [path.join(ROOT, 'scripts/setup-memorix.mjs'), '--home', fakeHome, '--skip-fastembed', '--no-autostart'],
      { encoding: 'utf8', timeout: 15000 }
    );
    assert.equal(res2.status, 0, res2.stderr || res2.stdout);
    assert.equal(fs.readFileSync(cfgPath, 'utf8'), 'custom = true\n');
  } finally {
    fs.rmSync(fakeHome, { recursive: true, force: true });
  }
});

test('setup-memorix.mjs --dry-run exits 0 without creating files', () => {
  const fakeHome = fs.mkdtempSync(path.join(os.tmpdir(), 'memorix-setup-dry-'));
  try {
    const res = spawnSync(
      process.execPath,
      [path.join(ROOT, 'scripts/setup-memorix.mjs'), '--home', fakeHome, '--dry-run'],
      { encoding: 'utf8', timeout: 15000 }
    );
    assert.equal(res.status, 0, res.stderr || res.stdout);
    assert.equal(fs.existsSync(path.join(fakeHome, '.memorix/config.toml')), false);
  } finally {
    fs.rmSync(fakeHome, { recursive: true, force: true });
  }
});
