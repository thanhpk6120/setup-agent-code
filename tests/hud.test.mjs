import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
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

function runHudOpenStdin(scriptPath, payload) {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    const child = spawn(process.execPath, [scriptPath], { stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });

    const killer = setTimeout(() => {
      child.kill();
      reject(new Error(`HUD ${scriptPath} hung with open stdin (>1500ms)`));
    }, 1500);

    child.on('exit', (code) => {
      clearTimeout(killer);
      resolve({ code, elapsedMs: Date.now() - start, stdout: stripAnsi(stdout), stderr });
    });

    child.stdin.write(JSON.stringify(payload));
  });
}

test('antigravity hud: tracks parallel subagents FIFO and clears on completion or server restart', () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'agy-hud-test-'));
  try {
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
    assert.doesNotMatch(outRestart, /agents:/);
  } finally {
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
});

test('claude hud: avoids false 100% when context_window missing and renders git + transcript counts', () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'claude-hud-test-'));
  try {
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
    assert.doesNotMatch(outNoCtx, /agents:/);
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
  } finally {
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
});

test('hud scripts exit immediately when stdin stays open after JSON payload', async () => {
  const agyRes = await runHudOpenStdin(AGY_HUD, {
    model: { display_name: 'Gemini 4 Argon (Medium)' },
    workspace: { current_dir: ROOT },
    vcs: { branch: 'main', dirty: false },
  });
  assert.equal(agyRes.code, 0, agyRes.stderr);
  assert.ok(agyRes.elapsedMs < 1000, `AGY HUD took too long: ${agyRes.elapsedMs}ms`);
  assert.match(agyRes.stdout, /\(main\)/);

  const claudeRes = await runHudOpenStdin(CLAUDE_HUD, {
    model: { display_name: 'Claude Sonnet 4.5' },
    workspace: { current_dir: ROOT },
    vcs: { branch: 'main', dirty: true },
  });
  assert.equal(claudeRes.code, 0, claudeRes.stderr);
  assert.ok(claudeRes.elapsedMs < 1000, `Claude HUD took too long: ${claudeRes.elapsedMs}ms`);
  assert.match(claudeRes.stdout, /\(main\*\)/);
});

test('antigravity hud: renders Tier 1-3 fields, /goal lifecycle + >512KB persistence, checklist, phase, and layout', () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'agy-hud-t3-'));
  const sessionId = 'sess-goal-1';
  const goalCacheFile = path.join(os.tmpdir(), `agy-hud-goal-${sessionId}.json`);
  try {
    const agyDir = path.join(tmpHome, '.gemini', 'antigravity-cli');
    const logDir = path.join(agyDir, 'brain', sessionId, '.system_generated', 'logs');
    fs.mkdirSync(logDir, { recursive: true });
    fs.writeFileSync(path.join(agyDir, 'review-gate.json'), JSON.stringify({ enabled: true, model: 'gemini-4-neon-high' }));

    const transcriptPath = path.join(logDir, 'transcript.jsonl');
    const nowIso = new Date().toISOString();
    const entries = [
      {
        type: 'USER_INPUT',
        source: 'USER_EXPLICIT',
        created_at: nowIso,
        content: '<USER_REQUEST>/goal</USER_REQUEST>\n/goal is a [Slash Command]: run overnight',
      },
      {
        type: 'SYSTEM_MESSAGE',
        source: 'SYSTEM',
        created_at: nowIso,
        content: 'Plan mode is off: execute now',
      },
      {
        type: 'PLANNER_RESPONSE',
        model: 'gemini-4-hydrogen-medium',
        created_at: nowIso,
        tool_calls: [
          {
            name: 'update_steps',
            args: {
              steps: [
                { title: 'Read files', status: 'done' },
                { title: 'Edit HUD script', status: 'in_progress' },
                { title: 'Run tests', status: 'pending' },
              ],
            },
          },
        ],
      },
      {
        type: 'USER_INPUT',
        source: 'SYSTEM',
        created_at: nowIso,
        content: 'Goal stop hook reminder: include <!-- GOAL_COMPLETE --> when done.',
      },
    ];
    fs.writeFileSync(transcriptPath, entries.map((e) => JSON.stringify(e)).join('\n') + '\n', 'utf8');

    const payload = {
      session_id: sessionId,
      transcript_path: transcriptPath,
      agent_state: 'working',
      cycle_mode: 'auto',
      sandbox: { enabled: true },
      vim: { mode: 'NORMAL' },
      model: { display_name: 'Orchestrator (Neon)', effort: 'high' },
      workspace: { current_dir: path.join(tmpHome, 'deep', 'nested', 'workspace', 'my-cool-repo') },
      terminal_width: 90,
      exceeds_200k_tokens: true,
      task_count: 2,
      artifact_count: 3,
      pending_input_count: 1,
      cost: { total_usd: 0.42, subagent_usd: 0.05, estimated: true },
      quota: {
        'gemini-5h': { remaining_fraction: 0.98, reset_in_seconds: 7200 },
        'gemini-weekly': { remaining_fraction: 0.45, reset_in_seconds: 172800 },
        '3p-5h': { remaining_fraction: 0.8, reset_in_seconds: 3600 },
        '3p-weekly': { remaining_fraction: 0.9, reset_in_seconds: 345600 },
      },
      context_window: {
        used_percentage: 32,
        context_window_size: 1000000,
        current_usage: { input_tokens: 100000, cache_read_input_tokens: 300000 },
      },
      subagents: [{ name: 'research', role: 'Codebase Explorer', status: 'running' }],
    };

    const out = runHud(AGY_HUD, payload, tmpHome);
    assert.doesNotMatch(out, /undefined/);
    const lines = out.split('\n');
    assert.ok(lines.length >= 3, `Expected 2 header lines + subagent line, got:\n${out}`);
    assert.match(lines[0], /● WORK/);
    assert.match(lines[0], /Orchestrator \(Neon\) \[Exec:4-hydrogen-medium\]|Orchestrator \(Neon\) \[Exec:hydrogen-medium\]/);
    assert.match(lines[0], /auto/);
    assert.match(lines[0], /🔒SBX/);
    assert.match(lines[0], /VIM:NORMAL/);
    assert.match(lines[0], /…\/workspace\/my-cool-repo/);
    assert.match(lines[0], /🎯 GOAL .* #1/);
    assert.match(lines[0], /RG:4-neon-high|RG:neon-high/);
    assert.match(lines[1], /32% \(400k\/1M\) 💾 75%/);
    assert.doesNotMatch(lines[1], />200k/);
    assert.match(lines[1], /~\$0\.42 \(sub:\$0\.05\)/);
    assert.match(lines[1], /5h:98%\/2h 7d:45%\/2d/);
    assert.match(lines[1], /☑ 1\/3: Edit HUD script/);
    assert.match(lines[1], /tasks:2/);
    assert.match(lines[1], /📄3/);
    assert.match(lines[1], /📥1/);
    assert.match(lines[1], /agents:1/);
    assert.match(lines[2], /Codebase Explorer/);

    // Claude model selects 3p-* 5h + 7d quota buckets
    const out3p = runHud(AGY_HUD, { ...payload, model: { display_name: 'Claude Sonnet 5.5' }, subagents: [] }, tmpHome);
    assert.match(out3p, /5h:80%\/1h 7d:90%\/4d/);

    // Scroll transcript past 512 KB without any goal markers -> cached active /goal must persist!
    // Also verify null remaining_fraction does NOT render false Q:0%/5h:0%/7d:0%, new reminder increments to #2 without double-counting,
    // and inline `<!-- GOAL_COMPLETE -->` inside text does NOT close the goal prematurely.
    const filler = JSON.stringify({ type: 'PLANNER_RESPONSE', model: 'gemini-4-hydrogen-medium', content: 'x'.repeat(1024) });
    fs.appendFileSync(transcriptPath, `${Array(600).fill(filler).join('\n')}\n`, 'utf8');
    fs.appendFileSync(
      transcriptPath,
      [
        JSON.stringify({ type: 'USER_INPUT', source: 'SYSTEM', step_index: 900, created_at: nowIso, content: 'Reminder: <!-- GOAL_COMPLETE -->' }),
        JSON.stringify({ type: 'PLANNER_RESPONSE', created_at: nowIso, content: 'Discussing `<!-- GOAL_COMPLETE -->` in docs' }),
      ].join('\n') + '\n',
      'utf8',
    );
    const outScrolled1 = runHud(AGY_HUD, { ...payload, quota: { 'gemini-weekly': { remaining_fraction: null } } }, tmpHome);
    const outScrolled2 = runHud(AGY_HUD, { ...payload, quota: { 'gemini-weekly': { remaining_fraction: null } } }, tmpHome);
    assert.match(outScrolled1, /🎯 GOAL .* #2/);
    assert.match(outScrolled2, /🎯 GOAL .* #2/);
    assert.doesNotMatch(outScrolled1, /Q:0%|5h:0%|7d:0%/);

    // tool_confirmation_pending overrides state badge + compact layout works
    fs.writeFileSync(path.join(agyDir, 'hud-config.json'), JSON.stringify({ layout: 'compact' }));
    const outWait = runHud(AGY_HUD, { ...payload, tool_confirmation_pending: true, subagents: [] }, tmpHome);
    assert.equal(outWait.split('\n').length, 1);
    assert.match(outWait, /⚠ WAIT y\/n/);

    // Goal completion marker switches badge to ✓ GOAL and persists across subsequent renders within 60s
    fs.appendFileSync(
      transcriptPath,
      `${JSON.stringify({ type: 'PLANNER_RESPONSE', created_at: new Date().toISOString(), content: 'Done <!-- GOAL_COMPLETE -->' })}\n`,
      'utf8',
    );
    const outDone1 = runHud(AGY_HUD, { ...payload, cycle_mode: 'default', permission_mode: 'plan', subagents: [] }, tmpHome);
    const outDone2 = runHud(AGY_HUD, { ...payload, cycle_mode: 'default', permission_mode: 'plan', subagents: [] }, tmpHome);
    assert.match(outDone1, /✓ GOAL/);
    assert.match(outDone2, /✓ GOAL/);
    assert.match(outDone1, /plan/);
  } finally {
    fs.rmSync(tmpHome, { recursive: true, force: true });
    fs.rmSync(goalCacheFile, { force: true });
  }
});

test('claude hud: renders Tier 1-3 fields (cost, lines, rate_limits, cache%, TodoWrite, OMC mode, review-gate)', () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'claude-hud-t3-'));
  try {
    const claudeDir = path.join(tmpHome, '.claude');
    const projDir = path.join(claudeDir, 'projects', 'proj-t3');
    const wsDir = path.join(tmpHome, 'work', 'very-long-folder-name', 'claude-demo-app');
    const omcStateDir = path.join(wsDir, '.omc', 'state');
    fs.mkdirSync(projDir, { recursive: true });
    fs.mkdirSync(omcStateDir, { recursive: true });

    fs.writeFileSync(path.join(claudeDir, 'review-gate.json'), JSON.stringify({ enabled: true, model: 'opus' }));
    fs.writeFileSync(path.join(omcStateDir, 'ralph-state.json'), JSON.stringify({ active: true, iteration: 2, max_iterations: 5 }));

    const transcriptPath = path.join(projDir, 'sess-c3.jsonl');
    const nowIso = new Date().toISOString();
    const entries = [
      {
        timestamp: nowIso,
        message: {
          content: [
            {
              type: 'tool_use',
              id: 'todo1',
              name: 'TodoWrite',
              input: {
                todos: [
                  { content: 'Setup', status: 'completed' },
                  { content: 'Implement HUD', activeForm: 'Implementing HUD', status: 'in_progress' },
                  { content: 'Verify', status: 'pending' },
                ],
              },
            },
          ],
        },
      },
    ];
    fs.writeFileSync(transcriptPath, entries.map((e) => JSON.stringify(e)).join('\n') + '\n', 'utf8');

    const payload = {
      session_id: 'sess-c3',
      transcript_path: transcriptPath,
      model: { display_name: 'Claude Sonnet 4.5' },
      agent: { name: 'reviewer' },
      permission_mode: 'acceptEdits',
      output_style: { name: 'concise' },
      vim: { mode: 'INSERT' },
      workspace: { current_dir: wsDir },
      terminal_width: 100,
      exceeds_200k_tokens: true,
      cost: { total_cost_usd: 1.25, total_lines_added: 42, total_lines_removed: 7 },
      rate_limits: {
        five_hour: { used_percentage: 20 },
        seven_day: { used_percentage: 85 },
      },
      context_window: {
        remaining_percentage: 70,
        context_window_size: 200000,
        current_usage: { input_tokens: 20000, cache_read_input_tokens: 40000 },
      },
    };

    const out = runHud(CLAUDE_HUD, payload, tmpHome);
    const lines = out.split('\n');
    assert.equal(lines.length, 2);
    assert.match(lines[0], /Claude Sonnet 4\.5/);
    assert.match(lines[0], /@reviewer/);
    assert.match(lines[0], /acceptEdits/);
    assert.match(lines[0], /style:concise/);
    assert.match(lines[0], /VIM:INSERT/);
    assert.match(lines[0], /…\/very-long-folder-name\/claude-demo-app/);
    assert.match(lines[0], /🎯 RALPH #2\/5/);
    assert.match(lines[0], /RG:opus/);
    assert.match(lines[1], /36% \(60k\/200k\) 💾 67%/);
    assert.doesNotMatch(lines[1], />200k/);
    assert.match(lines[1], /\$1\.25 \+42\/-7/);
    assert.match(lines[1], /5h:80% 7d:15%/);
    assert.match(lines[1], /☑ 1\/3: Implementing HUD/);
  } finally {
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
});

test('hud display fixes: suppresses thinking when idle, uses consistent │, renders low-usage bar, hides agents:0, resets Orchestrator phase', () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'hud-fixes-'));
  try {
    const agyDir = path.join(tmpHome, '.gemini', 'antigravity-cli');
    const logDir = path.join(agyDir, 'brain', 'sess-fix', '.system_generated', 'logs');
    fs.mkdirSync(logDir, { recursive: true });
    const transcriptPath = path.join(logDir, 'transcript.jsonl');
    const nowIso = new Date().toISOString();

    // Prior exec turn followed by a new USER_EXPLICIT turn with recent thinking
    const entries = [
      { type: 'SYSTEM_MESSAGE', source: 'SYSTEM', created_at: nowIso, content: 'Plan mode is off: execute' },
      { type: 'PLANNER_RESPONSE', model: 'gemini-4-hydrogen-high', thinking: 'exec thought', created_at: nowIso },
      { type: 'USER_INPUT', source: 'USER_EXPLICIT', created_at: nowIso, content: 'new question' },
    ];
    fs.writeFileSync(transcriptPath, entries.map((e) => JSON.stringify(e)).join('\n') + '\n', 'utf8');

    const basePayload = {
      session_id: 'sess-fix',
      transcript_path: transcriptPath,
      model: { display_name: 'Orchestrator (Neon)' },
      workspace: { current_dir: ROOT },
      context_window: { used_percentage: 9, context_window_size: 1000000, current_usage: { input_tokens: 90000 } },
    };

    // New USER_EXPLICIT turn resets stale [Exec:hydrogen-high] to [Plan] even in accept-edits mode
    const outResetPlan = runHud(AGY_HUD, { ...basePayload, cycle_mode: 'accept-edits', agent_state: 'working' }, tmpHome);
    const resetLines = outResetPlan.split('\n');
    assert.match(resetLines[0], /Orchestrator \(Neon\) \[Plan\]/);
    assert.doesNotMatch(resetLines[0], /hydrogen-high|Exec:/);
    assert.match(resetLines[1], /█░░░░░░░░░ 9%/);
    assert.match(resetLines[1], /thinking/);
    assert.doesNotMatch(resetLines[1], /agents:0/);
    assert.doesNotMatch(resetLines[1], / \| /);
    assert.match(resetLines[1], / │ /);

    // Once planning model responds in accept-edits mode, shows [Plan:neon-high] (NOT [Exec:neon-high])
    fs.appendFileSync(
      transcriptPath,
      JSON.stringify({ type: 'PLANNER_RESPONSE', model: 'gemini-4-neon-high', thinking: 'planning', created_at: nowIso }) + '\n',
      'utf8',
    );
    const outPlanModel = runHud(AGY_HUD, { ...basePayload, cycle_mode: 'accept-edits', agent_state: 'idle' }, tmpHome);
    assert.match(outPlanModel, /Orchestrator \(Neon\) \[Plan:neon-high\]/);
    assert.doesNotMatch(outPlanModel, /Exec:neon-high/);
    // Idle suppresses stale thinking even within 30s
    assert.doesNotMatch(outPlanModel, /thinking/);

    // tool_confirmation_pending also suppresses thinking
    const outWait = runHud(AGY_HUD, { ...basePayload, cycle_mode: 'accept-edits', agent_state: 'working', tool_confirmation_pending: true }, tmpHome);
    assert.doesNotMatch(outWait, /thinking/);

    // Zero usage renders empty bar
    const outZero = runHud(
      AGY_HUD,
      { ...basePayload, context_window: { used_percentage: 0, context_window_size: 1000000 } },
      tmpHome,
    );
    assert.match(outZero, /░░░░░░░░░░ 0%/);

    // Plan review hand-back resets phase to [Plan] without stale Exec model
    fs.appendFileSync(
      transcriptPath,
      [
        JSON.stringify({ type: 'SYSTEM_MESSAGE', source: 'SYSTEM', created_at: nowIso, content: 'Plan mode is off: run' }),
        JSON.stringify({ type: 'PLANNER_RESPONSE', model: 'gemini-4-hydrogen-high', created_at: nowIso }),
        JSON.stringify({ type: 'SYSTEM_MESSAGE', source: 'SYSTEM', created_at: nowIso, content: '[plan review due]' }),
      ].join('\n') + '\n',
      'utf8',
    );
    const outReview = runHud(AGY_HUD, { ...basePayload, agent_state: 'working' }, tmpHome);
    assert.match(outReview, /Orchestrator \(Neon\) \[Plan\]/);
    assert.doesNotMatch(outReview, /hydrogen-high/);

    // Claude HUD: low usage bar, consistent │, hides agents:0, 0% bar
    const outClaudeLow = runHud(
      CLAUDE_HUD,
      {
        model: { display_name: 'Claude Sonnet 4.5' },
        workspace: { current_dir: ROOT },
        context_window: { remaining_percentage: 93 },
      },
      tmpHome,
    );
    const claudeLines = outClaudeLow.split('\n');
    assert.match(claudeLines[1], /█░░░░░░░░░ 8%/);
    assert.doesNotMatch(claudeLines[1], /agents:0/);
    assert.doesNotMatch(claudeLines[1], / \| /);
    assert.match(claudeLines[1], / │ /);

    const outClaudeZero = runHud(
      CLAUDE_HUD,
      {
        model: { display_name: 'Claude Sonnet 4.5' },
        workspace: { current_dir: ROOT },
        context_window: { remaining_percentage: 100 },
      },
      tmpHome,
    );
    assert.match(outClaudeZero, /░░░░░░░░░░ 0%/);
  } finally {
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
});
