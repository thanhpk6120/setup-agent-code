import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { preferFnmDefaultAlias } from '../core/lib/util.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const PRE_TOOL = path.join(ROOT, 'templates/hooks/antigravity/pre-tool.mjs');

function runPreTool(payloadOrRaw) {
  const input = typeof payloadOrRaw === 'string' ? payloadOrRaw : JSON.stringify(payloadOrRaw);
  const res = spawnSync(process.execPath, [PRE_TOOL], {
    input,
    encoding: 'utf8',
    timeout: 10000
  });
  assert.equal(res.status, 0, `pre-tool.mjs exited ${res.status}: ${res.stderr}`);
  const trimmed = res.stdout.trim();
  return trimmed ? JSON.parse(trimmed) : null;
}

test('antigravity pre-tool denies hard delete in toolCall.args using Antigravity PreToolUse schema', () => {
  const out = runPreTool({
    toolCall: { id: 't1', name: 'run_command', args: { CommandLine: 'rm -rf foo' } },
    lastUserInput: 'delete foo',
    hookEventName: 'PreToolUse'
  });
  assert.equal(out.decision, 'deny');
  assert.match(out.reason || '', /xoa cung bi chan/i);
});

test('antigravity pre-tool ignores rm -rf in lastUserInput when CommandLine is safe', () => {
  const out = runPreTool({
    toolCall: { id: 't2', name: 'run_command', args: { CommandLine: 'git status' } },
    lastUserInput: 'please do not run rm -rf anywhere',
    hookEventName: 'PreToolUse'
  });
  assert.equal(out, null);
});

test('antigravity pre-tool allows safe trash / Recycle commands', () => {
  const out = runPreTool({
    toolCall: { id: 't3', name: 'run_command', args: { CommandLine: 'trash temp-dir' } },
    hookEventName: 'PreToolUse'
  });
  assert.equal(out, null);
});

test('antigravity pre-tool denies chained, subshell, and trash-named bypass attempts', () => {
  for (const cmd of [
    'trash a && rm -rf b',
    'rm -rf trash',
    'Remove-Item Recycle',
    'rm -rf foo # trash',
    'trash a $(rm -rf b)',
    'trash a `rm -rf b`'
  ]) {
    const out = runPreTool({
      toolCall: { id: 't-bypass', name: 'run_command', args: { CommandLine: cmd } },
      hookEventName: 'PreToolUse'
    });
    assert.equal(out?.decision, 'deny', `Expected deny for: ${cmd}`);
  }

  const spoofedSummary = runPreTool({
    toolCall: {
      id: 't5',
      name: 'run_command',
      args: { CommandLine: 'rm -rf foo', toolSummary: 'Move to trash safely' }
    },
    hookEventName: 'PreToolUse'
  });
  assert.equal(spoofedSummary?.decision, 'deny');
});

test('antigravity pre-tool supports legacy tool_input fallback', () => {
  const out = runPreTool({
    tool_input: { command: 'Remove-Item -Recurse foo' }
  });
  assert.equal(out.decision, 'deny');
});

test('antigravity pre-tool passes through (empty stdout) for empty, invalid JSON, or payloads without tool args', () => {
  assert.equal(runPreTool(''), null);
  assert.equal(runPreTool('{broken'), null);
  assert.equal(runPreTool({ lastUserInput: 'rm -rf something', workspacePaths: ['/tmp'] }), null);
});

test('preferFnmDefaultAlias rewrites default versioned fnm paths to aliases/default', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'fnm-alias-test-'));
  try {
    const fnmRoot = path.join(tmp, 'fnm');
    const v24Inst = path.join(fnmRoot, 'node-versions', 'v24.21.0', 'installation');
    const v14Inst = path.join(fnmRoot, 'node-versions', 'v14.21.3', 'installation');
    const aliasDir = path.join(fnmRoot, 'aliases');
    const defaultAlias = path.join(aliasDir, 'default');
    fs.mkdirSync(v24Inst, { recursive: true });
    fs.mkdirSync(v14Inst, { recursive: true });
    fs.mkdirSync(aliasDir, { recursive: true });

    const bin24 = path.join(v24Inst, 'gitnexus.cmd');
    const bin14 = path.join(v14Inst, 'gitnexus.cmd');
    fs.writeFileSync(bin24, '@echo off\n', 'utf8');
    fs.writeFileSync(bin14, '@echo off\n', 'utf8');

    fs.symlinkSync(v24Inst, defaultAlias, process.platform === 'win32' ? 'junction' : 'dir');

    assert.equal(preferFnmDefaultAlias(bin24), path.join(defaultAlias, 'gitnexus.cmd'));
    assert.equal(preferFnmDefaultAlias(bin14), bin14);
    assert.equal(preferFnmDefaultAlias('C:\\Program Files\\nodejs\\node.exe'), 'C:\\Program Files\\nodejs\\node.exe');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});
