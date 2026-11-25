import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const AGY_HUD = path.join(ROOT, 'templates', 'hooks', 'antigravity', 'hud.mjs');
const CLAUDE_HUD = path.join(ROOT, 'templates', 'hooks', 'claude', 'hud.mjs');

function stripAnsi(str) {
  return String(str).replace(/\x1b\[[0-9;]*m/g, '');
}

function runHud(scriptPath, payload, homeDir) {
  const res = spawnSync(process.execPath, [scriptPath], {
    input: JSON.stringify(payload),
    encoding: 'utf8',
    env: {
      ...process.env,
      HOME: homeDir,
      USERPROFILE: homeDir,
    },
    timeout: 10000,
  });
  assert.equal(res.status, 0, `HUD ${scriptPath} failed: ${res.stderr}`);
  return stripAnsi(res.stdout);
}

test('antigravity hud: tracks parallel subagents FIFO and clears on completion or server restart', () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'agy-hud-test-'));
  const agyDir = path.join(tmpHome, '.gemini', 'antigravity-cli');
  const logDir = path.join(agyDir, 'brain', 'sess-1', '.system_generated', 'logs');
  fs.mkdirSync(logDir, { recursive: true });
  const transcriptPath = path.join(logDir, 'transcript.jsonl');

  const nowIso = new Date().toISOString();
  const baseEntries = [
    { type: 'USER_INPUT', source: 'USER_EXPLICIT', created_at: nowIso, content: 'run parallel' },
    {
      type: 'PLANNER_RESPONSE',
      created_at: nowIso,
      tool_calls: [
        { name: 'invoke_subagent', args: { TypeName: 'research', Role: 'Reviewer 1' } },
        { name: 'invoke_subagent', args: { TypeName: 'research', Role: 'Reviewer 2' } },
        { name: 'read_file', args: { Path: '/repo/skills/tdd/SKILL.md' } },
      ],
    },
    { type: 'GENERIC', created_at: nowIso, content: '{"conversationId":"11111111-1111-1111-1111-111111111111"}' },
    { type: 'GENERIC', created_at: nowIso, content: '{"conversationId":"22222222-2222-2222-2222-222222222222"}' },
  ];

  fs.writeFileSync(transcriptPath, baseEntries.map((e) => JSON.stringify(e)).join('\n') + '\n', 'utf8');

  const payload = {
    session_id: 'sess-1',
    transcript_path: transcriptPath,
    model: { display_name: 'Gemini 4 Argon (Medium)' },
    workspace: { current_dir: ROOT },
    context_window: { used_percentage: 25, context_window_size: 1000000, current_usage: { input_tokens: 250000 } },
  };

  // Both subagents running
  const outRunning = runHud(AGY_HUD, payload, tmpHome);
  assert.match(outRunning, /Gemini 4 Argon \(Medium\)/);
  assert.match(outRunning, /25% \(250k\/1M\)/);
  assert.match(outRunning, /skill:tdd/);
  assert.match(outRunning, /agents:2/);
  assert.match(outRunning, /🔧 3 🤖 2 ⚡ 1/);

  // Complete first subagent -> 1 remaining
  fs.appendFileSync(
    transcriptPath,
    JSON.stringify({
      type: 'SYSTEM_MESSAGE',
      created_at: nowIso,
      content: '<SYSTEM_MESSAGE>sender=11111111-1111-1111-1111-111111111111</SYSTEM_MESSAGE>',
    }) + '\n',
    'utf8',
  );
  const outOneLeft = runHud(AGY_HUD, payload, tmpHome);
  assert.match(outOneLeft, /agents:1/);

  // Server restart notice -> clears remaining running subagents
  fs.appendFileSync(
    transcriptPath,
    JSON.stringify({
      type: 'SYSTEM_MESSAGE',
      created_at: nowIso,
      content: '<SYSTEM_MESSAGE>[Notice] All your subagents and background tasks have been stopped due to server restart.</SYSTEM_MESSAGE>',
    }) + '\n',
    'utf8',
  );
  const outRestart = runHud(AGY_HUD, payload, tmpHome);
  assert.match(outRestart, /agents:0/);
});

test('claude hud: avoids false 100% when context_window missing and renders git + transcript counts', () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'claude-hud-test-'));
  const projDir = path.join(tmpHome, '.claude', 'projects', 'proj-1');
  fs.mkdirSync(projDir, { recursive: true });
  const transcriptPath = path.join(projDir, 'sess-c1.jsonl');

  const nowIso = new Date().toISOString();
  const entries = [
    {
      timestamp: nowIso,
      message: {
        content: [
          { type: 'tool_use', id: 't1', name: 'Read', input: { file_path: '/repo/skills/code-review/SKILL.md' } },
          { type: 'tool_use', id: 't2', name: 'Agent', input: { subagent_type: 'explore', model: 'sonnet', description: 'Check' } },
          { type: 'tool_result', tool_use_id: 't2', content: 'done' },
        ],
      },
    },
  ];
  fs.writeFileSync(transcriptPath, entries.map((e) => JSON.stringify(e)).join('\n') + '\n', 'utf8');

  // Missing context_window must NOT show 100%
  const outNoCtx = runHud(
    CLAUDE_HUD,
    {
      session_id: 'sess-c1',
      transcript_path: transcriptPath,
      model: { display_name: 'Claude Sonnet 4.5' },
      workspace: { current_dir: ROOT },
    },
    tmpHome,
  );
  assert.match(outNoCtx, /Claude Sonnet 4\.5/);
  assert.match(outNoCtx, /\([^)]+\)/); // git branch badge
  assert.doesNotMatch(outNoCtx, /100%/);
  assert.match(outNoCtx, /skill:code-review/);
  assert.match(outNoCtx, /agents:0/);
  assert.match(outNoCtx, /🔧 2 🤖 1 ⚡ 1/);

  // With remaining_percentage -> renders context bar accurately
  const outWithCtx = runHud(
    CLAUDE_HUD,
    {
      session_id: 'sess-c1',
      transcript_path: transcriptPath,
      model: { display_name: 'Claude Sonnet 4.5' },
      workspace: { current_dir: ROOT },
      context_window: { remaining_percentage: 70 },
    },
    tmpHome,
  );
  assert.match(outWithCtx, /36%/);
});
