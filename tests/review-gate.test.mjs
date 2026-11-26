import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import * as U from '../core/lib/util.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const HOOK = path.join(ROOT, 'templates', 'hooks', 'antigravity', 'review-gate.mjs');
const CLAUDE_HOOK = path.join(ROOT, 'templates', 'hooks', 'claude', 'review-gate.mjs');
const CODEX_HOOK = path.join(ROOT, 'templates', 'hooks', 'codex', 'review-gate.mjs');
const OPENCODE_PLUGIN = path.join(ROOT, 'templates', 'hooks', 'opencode', 'review-gate.js');
const TMP_ROOT = path.join(ROOT, 'tests', '.tmp-review-gate');

function makeTempDir() {
  fs.mkdirSync(TMP_ROOT, { recursive: true });
  return fs.mkdtempSync(path.join(TMP_ROOT, 'case-'));
}

after(() => {
  if (fs.existsSync(TMP_ROOT)) U.trash(TMP_ROOT);
});

function runHook(payload, configPath, hookPath = HOOK, extraEnv = null) {
  const env = { ...process.env };
  delete env.REVIEW_GATE_SKIP;
  if (extraEnv) Object.assign(env, extraEnv);
  if (configPath) env.REVIEW_GATE_CONFIG = configPath;
  else delete env.REVIEW_GATE_CONFIG;
  const res = spawnSync(process.execPath, [hookPath], {
    input: typeof payload === 'string' ? payload : JSON.stringify(payload),
    encoding: 'utf8',
    env
  });
  assert.equal(res.status, 0, res.stderr);
  return JSON.parse(res.stdout);
}

test('review-gate allows read-only turns and skips non-NO_TOOL_CALL or active continuations', () => {
  const dir = makeTempDir();
  const transcript = path.join(dir, 'read-only.jsonl');
  fs.writeFileSync(transcript, [
    JSON.stringify({ type: 'USER_INPUT', source: 'USER_EXPLICIT' }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'read_file' }] })
  ].join('\n'));
  assert.deepEqual(runHook({ terminationReason: 'NO_TOOL_CALL', continuationActive: false, transcriptPath: transcript }), {});

  const editTranscript = path.join(dir, 'edit.jsonl');
  fs.writeFileSync(editTranscript, [
    JSON.stringify({ type: 'USER_INPUT', source: 'USER_EXPLICIT' }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'edit_file' }] })
  ].join('\n'));
  assert.deepEqual(runHook({ terminationReason: 'NO_TOOL_CALL', continuationActive: true, transcriptPath: editTranscript }), {});
  assert.deepEqual(runHook({ terminationReason: 'USER_CANCELED', continuationActive: false, transcriptPath: editTranscript }), {});
  assert.deepEqual(runHook('not-json'), {});
});

test('review-gate blocks unreviewed edits and handles transcript_path, same-step order, and SYSTEM_MESSAGE', () => {
  const dir = makeTempDir();
  const transcript = path.join(dir, 'unreviewed.jsonl');
  fs.writeFileSync(transcript, [
    JSON.stringify({ type: 'USER_INPUT', source: 'USER_EXPLICIT' }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'invoke_subagent' }, { name: 'edit_file' }] }),
    JSON.stringify({ type: 'USER_INPUT', source: 'SYSTEM', content: '<SYSTEM_MESSAGE>\nnotice\n</SYSTEM_MESSAGE>' }),
    '{broken-json-line'
  ].join('\n'));
  const res = runHook({ terminationReason: 'NO_TOOL_CALL', continuationActive: false, transcript_path: transcript });
  assert.equal(res.decision, 'continue');
  assert.ok(res.reason.includes('invoke_subagent'));
});

test('review-gate allows stop once invoke_subagent runs after the last edit', () => {
  const dir = makeTempDir();
  const transcript = path.join(dir, 'reviewed.jsonl');
  fs.writeFileSync(transcript, [
    JSON.stringify({ type: 'USER_INPUT', source: 'USER_EXPLICIT' }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'write_file' }] }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'swarm', args: { action: 'status' } }] })
  ].join('\n'));
  assert.equal(runHook({ terminationReason: 'NO_TOOL_CALL', continuationActive: false, transcriptPath: transcript }).decision, 'continue');

  fs.appendFileSync(transcript, `\n${JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'invoke_subagent' }] })}`);
  assert.deepEqual(runHook({ terminationReason: 'NO_TOOL_CALL', continuationActive: false, transcriptPath: transcript }), {});
});

test('review-gate respects review-gate.json model/enabled settings and skips single doc edits', () => {
  const dir = makeTempDir();
  const codeTranscript = path.join(dir, 'code.jsonl');
  const docTranscript = path.join(dir, 'doc.jsonl');
  const proConfig = path.join(dir, 'pro.json');
  const offConfig = path.join(dir, 'off.json');
  const badConfig = path.join(dir, 'bad.json');

  fs.writeFileSync(codeTranscript, [
    JSON.stringify({ type: 'USER_INPUT', source: 'USER_EXPLICIT', content: 'fix bug' }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'edit_file', arguments: { Path: 'src/app.js' } }] })
  ].join('\n'));
  fs.writeFileSync(docTranscript, [
    JSON.stringify({ type: 'USER_INPUT', source: 'USER_EXPLICIT', content: 'update docs' }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'edit_file', arguments: { Path: 'README.md' } }] })
  ].join('\n'));
  fs.writeFileSync(proConfig, JSON.stringify({ enabled: true, model: 'pro' }));
  fs.writeFileSync(offConfig, JSON.stringify({ enabled: false, model: 'pro' }));
  fs.writeFileSync(badConfig, '{invalid');

  const missingCfg = path.join(dir, 'missing.json');
  const rDefault = runHook({ terminationReason: 'NO_TOOL_CALL', continuationActive: false, transcriptPath: codeTranscript }, missingCfg);
  assert.equal(rDefault.decision, 'continue');
  assert.ok(rDefault.reason.includes('Model: "inherit"'));

  const rPro = runHook({ terminationReason: 'NO_TOOL_CALL', continuationActive: false, transcriptPath: codeTranscript }, proConfig);
  assert.equal(rPro.decision, 'continue');
  assert.ok(rPro.reason.includes('Model: "pro"'));

  assert.deepEqual(runHook({ terminationReason: 'NO_TOOL_CALL', continuationActive: false, transcriptPath: codeTranscript }, offConfig), {});

  const rBad = runHook({ terminationReason: 'NO_TOOL_CALL', continuationActive: false, transcriptPath: codeTranscript }, badConfig);
  assert.equal(rBad.decision, 'continue');
  assert.ok(rBad.reason.includes('Model: "inherit"'));

  const flashDashConfig = path.join(dir, 'flash-dash.json');
  fs.writeFileSync(flashDashConfig, JSON.stringify({ enabled: true, model: 'flash-lite' }));
  const rFlashDash = runHook({ terminationReason: 'NO_TOOL_CALL', continuationActive: false, transcriptPath: codeTranscript }, flashDashConfig);
  assert.equal(rFlashDash.decision, 'continue');
  assert.ok(rFlashDash.reason.includes('Model: "flash_lite"'));

  assert.deepEqual(runHook({ terminationReason: 'NO_TOOL_CALL', continuationActive: false, transcriptPath: docTranscript }, missingCfg), {});
});

test('claude review-gate blocks unreviewed Edit, respects stop_hook_active, Agent review, and config', () => {
  const dir = makeTempDir();
  const transcript = path.join(dir, 'claude.jsonl');
  const docTranscript = path.join(dir, 'claude-doc.jsonl');
  const sonnetCfg = path.join(dir, 'sonnet.json');
  const offCfg = path.join(dir, 'off.json');
  const missingCfg = path.join(dir, 'missing.json');

  fs.writeFileSync(transcript, [
    JSON.stringify({ type: 'user', message: { role: 'user', content: 'fix bug' } }),
    JSON.stringify({ type: 'assistant', message: { role: 'assistant', content: [{ type: 'tool_use', name: 'Edit', input: { file_path: 'src/app.js' } }] } })
  ].join('\n'));
  fs.writeFileSync(docTranscript, [
    JSON.stringify({ type: 'user', message: { role: 'user', content: 'update readme' } }),
    JSON.stringify({ type: 'assistant', message: { role: 'assistant', content: [{ type: 'tool_use', name: 'Write', input: { file_path: 'README.md' } }] } })
  ].join('\n'));
  fs.writeFileSync(sonnetCfg, JSON.stringify({ enabled: true, model: 'sonnet' }));
  fs.writeFileSync(offCfg, JSON.stringify({ enabled: false, model: 'opus' }));

  const rDefault = runHook({ stop_hook_active: false, transcript_path: transcript }, missingCfg, CLAUDE_HOOK);
  assert.equal(rDefault.decision, 'block');
  assert.ok(rDefault.reason.includes('inherit'));

  const rSonnet = runHook({ stop_hook_active: false, transcript_path: transcript }, sonnetCfg, CLAUDE_HOOK);
  assert.equal(rSonnet.decision, 'block');
  assert.ok(rSonnet.reason.includes('model: "sonnet"'));

  assert.deepEqual(runHook({ stop_hook_active: true, transcript_path: transcript }, missingCfg, CLAUDE_HOOK), {});
  assert.deepEqual(runHook({ stop_hook_active: false, transcript_path: transcript }, offCfg, CLAUDE_HOOK), {});
  assert.deepEqual(runHook({ stop_hook_active: false, transcript_path: docTranscript }, missingCfg, CLAUDE_HOOK), {});

  fs.appendFileSync(transcript, `\n${JSON.stringify({ type: 'assistant', message: { role: 'assistant', content: [{ type: 'tool_use', name: 'Agent', input: { description: 'review' } }] } })}`);
  assert.deepEqual(runHook({ stop_hook_active: false, transcript_path: transcript }, missingCfg, CLAUDE_HOOK), {});
});

test('codex review-gate blocks unreviewed apply_patch, respects stop_hook_active, spawn_agent, and config', () => {
  const dir = makeTempDir();
  const transcript = path.join(dir, 'codex.jsonl');
  const docTranscript = path.join(dir, 'codex-doc.jsonl');
  const miniCfg = path.join(dir, 'mini.json');
  const offCfg = path.join(dir, 'off.json');
  const missingCfg = path.join(dir, 'missing.json');

  fs.writeFileSync(transcript, [
    JSON.stringify({ type: 'event_msg', payload: { type: 'user_message', message: 'fix bug' } }),
    JSON.stringify({ type: 'response_item', payload: { type: 'function_call', name: 'apply_patch', arguments: '*** Begin Patch\n*** Update File: src/app.js\n*** End Patch' } })
  ].join('\n'));
  fs.writeFileSync(docTranscript, [
    JSON.stringify({ type: 'event_msg', payload: { type: 'user_message', message: 'update docs' } }),
    JSON.stringify({ type: 'response_item', payload: { type: 'custom_tool_call', name: 'apply_patch', input: '*** Begin Patch\n*** Update File: README.md\n*** End Patch' } })
  ].join('\n'));
  fs.writeFileSync(miniCfg, JSON.stringify({ enabled: true, model: 'gpt-5.4-mini' }));
  fs.writeFileSync(offCfg, JSON.stringify({ enabled: false, model: 'gpt-5.4' }));

  const rDefault = runHook({ stop_hook_active: false, transcript_path: transcript }, missingCfg, CODEX_HOOK);
  assert.equal(rDefault.decision, 'block');
  assert.ok(rDefault.reason.includes('app.js'));
  assert.ok(rDefault.reason.includes('spawn_agent'));

  const rMini = runHook({ stop_hook_active: false, transcript_path: transcript }, miniCfg, CODEX_HOOK);
  assert.equal(rMini.decision, 'block');
  assert.ok(rMini.reason.includes('model: "gpt-5.4-mini"'));

  assert.deepEqual(runHook({ stop_hook_active: true, transcript_path: transcript }, missingCfg, CODEX_HOOK), {});
  assert.deepEqual(runHook({ stop_hook_active: false, transcript_path: transcript }, offCfg, CODEX_HOOK), {});
  assert.deepEqual(runHook({ stop_hook_active: false, transcript_path: docTranscript }, missingCfg, CODEX_HOOK), {});

  const multiPatchTranscript = path.join(dir, 'codex-multi.jsonl');
  fs.writeFileSync(multiPatchTranscript, [
    JSON.stringify({ type: 'event_msg', payload: { type: 'user_message', message: 'update docs and code' } }),
    JSON.stringify({ type: 'response_item', payload: { type: 'custom_tool_call', name: 'apply_patch', input: '*** Begin Patch\n*** Update File: README.md\n*** Update File: src/app.js\n*** End Patch' } })
  ].join('\n'));
  const rMulti = runHook({ stop_hook_active: false, transcript_path: multiPatchTranscript }, missingCfg, CODEX_HOOK);
  assert.equal(rMulti.decision, 'block');
  assert.ok(rMulti.reason.includes('app.js'));

  fs.appendFileSync(transcript, `\n${JSON.stringify({ type: 'response_item', payload: { type: 'function_call', name: 'spawn_agent', arguments: '{}' } })}`);
  assert.deepEqual(runHook({ stop_hook_active: false, transcript_path: transcript }, missingCfg, CODEX_HOOK), {});
});

test('opencode review-gate plugin triggers synthetic review on idle after unreviewed edits', async () => {
  const dir = makeTempDir();
  const pluginPkgDir = path.join(dir, 'node_modules', '@opencode', 'plugin');
  fs.mkdirSync(pluginPkgDir, { recursive: true });
  fs.writeFileSync(path.join(pluginPkgDir, 'package.json'), JSON.stringify({ name: '@opencode/plugin', type: 'module', main: 'index.js' }));
  fs.writeFileSync(path.join(pluginPkgDir, 'index.js'), 'export const Plugin = { define(p) { return p; } };');
  fs.writeFileSync(path.join(dir, 'package.json'), JSON.stringify({ type: 'module' }));
  const pluginCopy = path.join(dir, 'review-gate.js');
  fs.copyFileSync(OPENCODE_PLUGIN, pluginCopy);
  const cfgPath = path.join(dir, 'review-gate.json');
  fs.writeFileSync(cfgPath, JSON.stringify({ enabled: true, model: 'inherit' }));

  const prevCfg = process.env.OPENCODE_REVIEW_GATE_CONFIG;
  process.env.OPENCODE_REVIEW_GATE_CONFIG = cfgPath;
  try {
    const mod = await import(pathToFileURL(pluginCopy).href);
    const toolHooks = {};
    const sessionHooks = {};
    const syntheticCalls = [];
    await mod.default.setup({
      tool: { hook: (name, fn) => { toolHooks[name] = fn; } },
      session: {
        hook: (name, fn) => { sessionHooks[name] = fn; },
        synthetic: async (input) => { syntheticCalls.push(input); }
      }
    });

    await toolHooks['execute.after']({ status: 'completed', tool: 'edit', sessionID: 's1', input: { filePath: 'src/app.js' } });
    await sessionHooks['experimental.idle']({ sessionID: 's1', background: [] });
    assert.equal(syntheticCalls.length, 1);
    assert.ok(syntheticCalls[0].text.includes('Independent Reviewer'));

    // Repeating idle immediately does not loop infinitely
    await sessionHooks['experimental.idle']({ sessionID: 's1', background: [] });
    assert.equal(syntheticCalls.length, 1);

    // Subagent task clears pending edit
    await toolHooks['execute.after']({ status: 'completed', tool: 'edit', sessionID: 's2', input: { filePath: 'src/app.js' } });
    await toolHooks['execute.after']({ status: 'completed', tool: 'task', sessionID: 's2', input: {} });
    await sessionHooks['experimental.idle']({ sessionID: 's2', background: [] });
    assert.equal(syntheticCalls.length, 1);

    // Disabled config skips synthetic prompt
    fs.writeFileSync(cfgPath, JSON.stringify({ enabled: false, model: 'inherit' }));
    await toolHooks['execute.after']({ status: 'completed', tool: 'write', sessionID: 's3', input: { filePath: 'src/app.js' } });
    await sessionHooks['experimental.idle']({ sessionID: 's3', background: [] });
    assert.equal(syntheticCalls.length, 1);
  } finally {
    if (prevCfg === undefined) delete process.env.OPENCODE_REVIEW_GATE_CONFIG;
    else process.env.OPENCODE_REVIEW_GATE_CONFIG = prevCfg;
  }
});

test('antigravity review-gate supports exact model IDs via agy CLI, rejects unsafe IDs, and skips when REVIEW_GATE_SKIP=1', () => {
  const dir = makeTempDir();
  const transcript = path.join(dir, 'agy-exact.jsonl');
  const exactCfg = path.join(dir, 'exact.json');
  const unsafeCfg = path.join(dir, 'unsafe.json');

  fs.writeFileSync(transcript, [
    JSON.stringify({ type: 'USER_INPUT', source: 'USER_EXPLICIT', content: 'fix bug' }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'edit_file', arguments: { Path: 'src/app.js' } }] }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'run_command', args: { CommandLine: '"agy models"' } }] }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'run_command', args: { CommandLine: '"agy --print-timeout 10s"' } }] }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'run_command', args: { CommandLine: '"agy models && git diff -p"' } }] }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'run_command', args: { CommandLine: '"agy models -- -p"' } }] }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'run_command', args: { CommandLine: '"agy chat -p"' } }] }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'run_command', args: { CommandLine: '"agy models | grep -P foo"' } }] }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'run_command', args: { CommandLine: '"agy chat \\"git diff -p\\""' } }] }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'run_command', args: { CommandLine: '"node \\"C:/mock-home/.gemini/antigravity-cli/hooks/review-gate.mjs\\" --run --dry-run"' } }] }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'run_command', args: { CommandLine: '"node -e \\"review-gate.mjs --run\\""' } }] }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'run_command', args: { CommandLine: '"echo agy --print"' } }] })
  ].join('\n'));
  fs.writeFileSync(exactCfg, JSON.stringify({ enabled: true, model: 'gemini-4-neon-high' }));
  fs.writeFileSync(unsafeCfg, JSON.stringify({ enabled: true, model: 'gemini-4-neon-high; echo pwn' }));
  const reservedCfg = path.join(dir, 'reserved.json');
  fs.writeFileSync(reservedCfg, JSON.stringify({ enabled: true, model: 'off' }));

  const rExact = runHook({ terminationReason: 'NO_TOOL_CALL', continuationActive: false, transcriptPath: transcript }, exactCfg);
  assert.equal(rExact.decision, 'continue');
  assert.ok(rExact.reason.includes('gemini-4-neon-high'));
  assert.ok(rExact.reason.includes('review-gate.mjs'));
  assert.ok(rExact.reason.includes('--run --files "src/app.js"'));
  assert.ok(!rExact.reason.includes('invoke_subagent'));

  const rUnsafe = runHook({ terminationReason: 'NO_TOOL_CALL', continuationActive: false, transcriptPath: transcript }, unsafeCfg);
  assert.equal(rUnsafe.decision, 'continue');
  assert.ok(rUnsafe.reason.includes('Model: "inherit"'));

  const rReserved = runHook({ terminationReason: 'NO_TOOL_CALL', continuationActive: false, transcriptPath: transcript }, reservedCfg);
  assert.equal(rReserved.decision, 'continue');
  assert.ok(rReserved.reason.includes('Model: "inherit"'));

  assert.deepEqual(
    runHook({ terminationReason: 'NO_TOOL_CALL', continuationActive: false, transcriptPath: transcript }, exactCfg, HOOK, { REVIEW_GATE_SKIP: '1' }),
    {}
  );

  // Direct `agy --print "..."` (without prior flags) and POSIX `REVIEW_GATE_SKIP=1 agy ...` also clear review gate.
  const directPrintTranscript = path.join(dir, 'agy-direct.jsonl');
  fs.writeFileSync(directPrintTranscript, [
    JSON.stringify({ type: 'USER_INPUT', source: 'USER_EXPLICIT', content: 'fix bug' }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'edit_file', arguments: { Path: 'src/app.js' } }] }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'run_command', args: { CommandLine: 'agy --print "Review diff"' } }] })
  ].join('\n'));
  assert.deepEqual(runHook({ terminationReason: 'NO_TOOL_CALL', continuationActive: false, transcriptPath: directPrintTranscript }, exactCfg), {});

  const posixTranscript = path.join(dir, 'agy-posix.jsonl');
  fs.writeFileSync(posixTranscript, [
    JSON.stringify({ type: 'USER_INPUT', source: 'USER_EXPLICIT', content: 'fix bug' }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'edit_file', arguments: { Path: 'src/app.js' } }] }),
    JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'run_command', args: { CommandLine: "REVIEW_GATE_SKIP='1' C:/bin/agy.exe -p \"Review diff\"" } }] })
  ].join('\n'));
  assert.deepEqual(runHook({ terminationReason: 'NO_TOOL_CALL', continuationActive: false, transcriptPath: posixTranscript }, exactCfg), {});

  for (const validCmd of [
    'agy --print="Review diff"',
    '"C:\\bin\\agy.exe" --print "Review diff"',
    'agy.cmd -p="Review diff"',
    'agy.ps1 --print "Review diff"',
    'agy --cwd "x `"--print`"" --print "Review diff"',
    'agy --model chat --print "Review diff"',
    'agy --cwd chat --print "Review diff"',
    'agy --prompt "Review diff"',
    'node "C:/mock-home/.gemini/antigravity-cli/hooks/review-gate.mjs" --run --files "src/app.js"',
    'node --no-warnings "C:/mock-home/.gemini/antigravity-cli/hooks/review-gate.mjs" --run --files "src/app.js"'
  ]) {
    const t = path.join(dir, `agy-${Math.random().toString(36).slice(2, 8)}.jsonl`);
    fs.writeFileSync(t, [
      JSON.stringify({ type: 'USER_INPUT', source: 'USER_EXPLICIT', content: 'fix bug' }),
      JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'edit_file', arguments: { Path: 'src/app.js' } }] }),
      JSON.stringify({ type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'run_command', args: { CommandLine: validCmd } }] })
    ].join('\n'));
    assert.deepEqual(runHook({ terminationReason: 'NO_TOOL_CALL', continuationActive: false, transcriptPath: t }, exactCfg), {}, validCmd);
  }

  fs.appendFileSync(transcript, `\n${JSON.stringify({
    type: 'PLANNER_RESPONSE',
    tool_calls: [{
      name: 'run_command',
      args: {
        CommandLine: JSON.stringify('node "C:/mock-home/.gemini/antigravity-cli/hooks/review-gate.mjs" --run --files "src/app.js"')
      }
    }]
  })}`);
  assert.deepEqual(runHook({ terminationReason: 'NO_TOOL_CALL', continuationActive: false, transcriptPath: transcript }, exactCfg), {});
});

test('antigravity review-gate --run collects inline git diff, untracked files, non-git files, and caps size', () => {
  const dir = makeTempDir();
  const cfgPath = path.join(dir, 'exact.json');
  fs.writeFileSync(cfgPath, JSON.stringify({ enabled: true, model: 'gemini-4-neon-high' }));
  const env = { ...process.env, REVIEW_GATE_CONFIG: cfgPath };

  // 1. Git repo case (tracked modification + untracked new file + lockfile filtering)
  const repoDir = path.join(dir, 'repo');
  fs.mkdirSync(repoDir, { recursive: true });
  execFileSync('git', ['init'], { cwd: repoDir, stdio: 'ignore' });
  execFileSync('git', ['config', 'user.email', 'test@example.com'], { cwd: repoDir, stdio: 'ignore' });
  execFileSync('git', ['config', 'user.name', 'Test'], { cwd: repoDir, stdio: 'ignore' });
  fs.writeFileSync(path.join(repoDir, 'a.js'), 'export const x = 1;\n');
  fs.writeFileSync(path.join(repoDir, 'package-lock.json'), '{"lockfileVersion":3}\n');
  execFileSync('git', ['add', 'a.js', 'package-lock.json'], { cwd: repoDir, stdio: 'ignore' });
  execFileSync('git', ['commit', '-m', 'init'], { cwd: repoDir, stdio: 'ignore' });
  fs.writeFileSync(path.join(repoDir, 'a.js'), 'export const x = 2;\n');
  fs.writeFileSync(path.join(repoDir, 'package-lock.json'), '{"lockfileVersion":3,"packages":{"foo":{}}}\n');
  fs.writeFileSync(path.join(repoDir, 'new.js'), 'export const y = 42;\n');

  const gitRun = spawnSync(
    process.execPath,
    [HOOK, '--run', '--dry-run', '--cwd', repoDir, '--files', 'a.js', 'package-lock.json', 'new.js'],
    { encoding: 'utf8', env }
  );
  assert.equal(gitRun.status, 0, gitRun.stderr);
  const gitOut = JSON.parse(gitRun.stdout);
  assert.equal(gitOut.model, 'gemini-4-neon-high');
  assert.equal(gitOut.truncated, false);
  assert.equal(gitOut.patchPath, null);
  assert.ok(gitOut.prompt.includes('Do NOT call any tools'));
  assert.ok(gitOut.prompt.includes('=== GIT DIFF STAT ==='));
  assert.ok(gitOut.prompt.includes('package-lock.json'));
  assert.ok(gitOut.prompt.includes('=== GIT DIFF ==='));
  assert.ok(gitOut.prompt.includes('+export const x = 2;'));
  assert.ok(!gitOut.prompt.includes('"packages":{"foo":{}}'));
  assert.ok(gitOut.prompt.includes('[Skipped inline diff for generated/lockfile(s): package-lock.json]'));
  assert.ok(gitOut.prompt.includes('=== NEW FILE (untracked): new.js ==='));
  assert.ok(gitOut.prompt.includes('export const y = 42;'));

  // 1b. Deleted tracked file still yields git diff deletion instead of "deleted/missing"
  const deletedPath = path.join(repoDir, 'to-delete.js');
  fs.writeFileSync(deletedPath, 'export const gone = 99;\n');
  execFileSync('git', ['add', 'to-delete.js'], { cwd: repoDir, stdio: 'ignore' });
  execFileSync('git', ['commit', '-m', 'add to-delete'], { cwd: repoDir, stdio: 'ignore' });
  U.trash(deletedPath);
  const delRun = spawnSync(
    process.execPath,
    [HOOK, '--run', '--dry-run', '--cwd', repoDir, '--files', deletedPath],
    { encoding: 'utf8', env }
  );
  assert.equal(delRun.status, 0, delRun.stderr);
  const delOut = JSON.parse(delRun.stdout);
  assert.ok(delOut.prompt.includes('=== GIT DIFF ==='));
  assert.ok(delOut.prompt.includes('-export const gone = 99;'));
  assert.ok(!delOut.prompt.includes('FILE (deleted/missing)'));

  // 1c. Parent workspace without .git still resolves per-file git root for repo/a.js
  const parentWorkspaceRun = spawnSync(
    process.execPath,
    [HOOK, '--run', '--dry-run', '--cwd', dir, '--files', 'repo/a.js'],
    { encoding: 'utf8', env }
  );
  assert.equal(parentWorkspaceRun.status, 0, parentWorkspaceRun.stderr);
  const parentWorkspaceOut = JSON.parse(parentWorkspaceRun.stdout);
  assert.ok(parentWorkspaceOut.prompt.includes('=== GIT DIFF ==='));
  assert.ok(parentWorkspaceOut.prompt.includes('+export const x = 2;'));
  assert.ok(!parentWorkspaceOut.prompt.includes('FILE (no git diff)'));

  // 2. Non-git folder case (outside any git repo, uses parent without .git)
  const nonGitDir = fs.mkdtempSync(path.join(process.env.TEMP || process.env.TMPDIR || '/tmp', 'rg-nongit-'));
  let createdPatchPath = null;
  try {
    fs.writeFileSync(path.join(nonGitDir, 'settings.json'), '{"theme":"dark"}\n');
    const nonGitRun = spawnSync(
      process.execPath,
      [HOOK, '--run', '--dry-run', '--cwd', nonGitDir, '--files', 'settings.json'],
      { encoding: 'utf8', env }
    );
    assert.equal(nonGitRun.status, 0, nonGitRun.stderr);
    const nonGitOut = JSON.parse(nonGitRun.stdout);
    assert.equal(nonGitOut.gitRoot, null);
    assert.equal(nonGitOut.truncated, false);
    assert.ok(nonGitOut.prompt.includes('=== FILE (no git diff): settings.json ==='));
    assert.ok(nonGitOut.prompt.includes('{"theme":"dark"}'));

    // 3. Bounded file read (40 KB file truncated at MAX_FILE_CHARS without full truncation of inline budget)
    fs.writeFileSync(path.join(nonGitDir, 'big.txt'), 'A'.repeat(40_000));
    const boundedRun = spawnSync(
      process.execPath,
      [HOOK, '--run', '--dry-run', '--cwd', nonGitDir, '--files', 'big.txt'],
      { encoding: 'utf8', env }
    );
    assert.equal(boundedRun.status, 0, boundedRun.stderr);
    const boundedOut = JSON.parse(boundedRun.stdout);
    assert.ok(boundedOut.prompt.includes('truncated; file size 40000 bytes'));

    // 4. Hybrid overflow when inline budget is exceeded -> saves FULL patch file and enables read_file
    const overflowRun = spawnSync(
      process.execPath,
      [HOOK, '--run', '--dry-run', '--max-inline-chars', '400', '--cwd', nonGitDir, '--files', 'settings.json', 'big.txt'],
      { encoding: 'utf8', env }
    );
    assert.equal(overflowRun.status, 0, overflowRun.stderr);
    const overflowOut = JSON.parse(overflowRun.stdout);
    assert.equal(overflowOut.truncated, true);
    assert.ok(overflowOut.patchPath && fs.existsSync(overflowOut.patchPath));
    createdPatchPath = overflowOut.patchPath;
    assert.ok(overflowOut.prompt.includes('read_file'));
    assert.ok(!overflowOut.prompt.includes('Do NOT call any tools'));
    const patchBody = fs.readFileSync(overflowOut.patchPath, 'utf8');
    assert.ok(patchBody.includes('{"theme":"dark"}'));
    assert.ok(patchBody.includes('AAAA'));
  } finally {
    U.trash(nonGitDir);
    if (createdPatchPath && fs.existsSync(createdPatchPath)) U.trash(path.dirname(createdPatchPath));
  }

  // Reject flash-lite alias in --run exact-model mode (exit code 2)
  const tierRun = spawnSync(
    process.execPath,
    [HOOK, '--run', '--dry-run', '--model', 'flash-lite'],
    { encoding: 'utf8', env }
  );
  assert.equal(tierRun.status, 2);

  // Stop parseRunArgs at `--` so `-- --model flash-lite` is ignored and config model is kept
  const postDashRun = spawnSync(
    process.execPath,
    [HOOK, '--run', '--dry-run', '--cwd', repoDir, '--', '--model', 'flash-lite'],
    { encoding: 'utf8', env }
  );
  assert.equal(postDashRun.status, 0, postDashRun.stderr);
  assert.equal(JSON.parse(postDashRun.stdout).model, 'gemini-4-neon-high');

  // Repo-wide --run (no --files) picks up BOTH modified tracked files AND untracked new files
  const allRepoRun = spawnSync(
    process.execPath,
    [HOOK, '--run', '--dry-run', '--cwd', repoDir],
    { encoding: 'utf8', env }
  );
  assert.equal(allRepoRun.status, 0, allRepoRun.stderr);
  const allRepoOut = JSON.parse(allRepoRun.stdout);
  assert.ok(allRepoOut.prompt.includes('+export const x = 2;'));
  assert.ok(allRepoOut.prompt.includes('=== NEW FILE (untracked): new.js ==='));

  // Mocked live `stream-json` execution via REVIEW_GATE_AGY_BIN inside a directory with spaces
  // (covers .cmd/.sh shim launch, space/empty-arg preservation, stdin payload, result parsing, and status ERROR)
  const shimDir = path.join(dir, 'shim dir (v1)');
  fs.mkdirSync(shimDir, { recursive: true });
  const mockScript = path.join(shimDir, 'mock-agy.mjs');
  fs.writeFileSync(mockScript, [
    'import fs from "node:fs";',
    'const stdin = fs.readFileSync(0, "utf8").trim();',
    'const msg = JSON.parse(stdin);',
    'if (!process.argv.includes("--print=")) {',
    '  console.error("missing --print= arg:", JSON.stringify(process.argv));',
    '  process.exit(3);',
    '}',
    'if (process.argv.includes("fail-model")) {',
    '  console.log(JSON.stringify({ event: "result", result: { status: "ERROR", response: "" } }));',
    '  process.exit(0);',
    '}',
    'if (process.argv.includes("empty-model")) {',
    '  console.log(JSON.stringify({ event: "result", result: { status: "SUCCESS", response: "" } }));',
    '  process.exit(0);',
    '}',
    'if (process.argv.includes("event-error-model")) {',
    '  console.log(JSON.stringify({ event: "error", error: "auth expired" }));',
    '  process.exit(0);',
    '}',
    'if (process.argv.includes("linger-model")) {',
    '  console.log(JSON.stringify({ event: "result", result: { status: "SUCCESS", response: "OK — fast" } }));',
    '  setTimeout(() => {}, 10000);',
    '  await new Promise(() => {});',
    '}',
    'if (process.argv.includes("hang-model")) {',
    '  setTimeout(() => {}, 10000);',
    '  await new Promise(() => {});',
    '}',
    'const addDirIdx = process.argv.indexOf("--add-dir");',
    'if (addDirIdx !== -1 && (!process.argv[addDirIdx + 1] || !fs.existsSync(process.argv[addDirIdx + 1]))) {',
    '  console.error("invalid --add-dir:", process.argv[addDirIdx + 1]);',
    '  process.exit(4);',
    '}',
    'console.log(JSON.stringify({ event: "init" }));',
    'console.log(JSON.stringify({ event: "step_update", step_update: { text_delta: "OK " } }));',
    'console.log(JSON.stringify({ event: "result", result: { status: "SUCCESS", response: `OK — reviewed (${msg.message.content.includes("+export const x = 2;")}) addDir=${addDirIdx !== -1}` } }));'
  ].join('\n'));
  const mockShim = path.join(shimDir, process.platform === 'win32' ? 'mock-agy.cmd' : 'mock-agy.sh');
  if (process.platform === 'win32') {
    fs.writeFileSync(mockShim, `@echo off\r\n"${process.execPath}" "${mockScript}" %*\r\n`);
  } else {
    fs.writeFileSync(mockShim, `#!/usr/bin/env sh\nexec "${process.execPath}" "${mockScript}" "$@"\n`);
    fs.chmodSync(mockShim, 0o755);
  }

  // Fallback to step_update deltas when result.response is empty string ""
  fs.writeFileSync(path.join(shimDir, 'mock-agy-delta.mjs'), [
    'const args = process.argv;',
    'if (args.includes("delta-model")) {',
    '  console.log(JSON.stringify({ event: "step_update", step_update: { text_delta: "OK — from delta" } }));',
    '  console.log(JSON.stringify({ event: "result", result: { status: "SUCCESS", response: "   \\n" } }));',
    '  process.exit(0);',
    '}'
  ].join('\n'));
  const deltaShim = path.join(shimDir, process.platform === 'win32' ? 'mock-delta.cmd' : 'mock-delta.sh');
  if (process.platform === 'win32') {
    fs.writeFileSync(deltaShim, `@echo off\r\n"${process.execPath}" "${path.join(shimDir, 'mock-agy-delta.mjs')}" %*\r\n`);
  } else {
    fs.writeFileSync(deltaShim, `#!/usr/bin/env sh\nexec "${process.execPath}" "${path.join(shimDir, 'mock-agy-delta.mjs')}" "$@"\n`);
    fs.chmodSync(deltaShim, 0o755);
  }

  const liveDelta = spawnSync(
    process.execPath,
    [HOOK, '--run', '--model', 'delta-model', '--cwd', repoDir, '--files', 'a.js'],
    { encoding: 'utf8', env: { ...env, REVIEW_GATE_AGY_BIN: deltaShim } }
  );
  assert.equal(liveDelta.status, 0, liveDelta.stderr);
  assert.equal(liveDelta.stdout.trim(), 'OK — from delta');

  const liveOk = spawnSync(
    process.execPath,
    [HOOK, '--run', '--cwd', repoDir, '--files', 'a.js'],
    { encoding: 'utf8', env: { ...env, REVIEW_GATE_AGY_BIN: mockShim } }
  );
  assert.equal(liveOk.status, 0, liveOk.stderr);
  assert.equal(liveOk.stdout.trim(), 'OK — reviewed (true) addDir=false');

  const liveEmpty = spawnSync(
    process.execPath,
    [HOOK, '--run', '--model', 'empty-model', '--cwd', repoDir, '--files', 'a.js'],
    { encoding: 'utf8', env: { ...env, REVIEW_GATE_AGY_BIN: mockShim } }
  );
  assert.equal(liveEmpty.status, 1);
  assert.ok(liveEmpty.stderr.includes('empty output'));

  const liveErr = spawnSync(
    process.execPath,
    [HOOK, '--run', '--model', 'fail-model', '--cwd', repoDir, '--files', 'a.js'],
    { encoding: 'utf8', env: { ...env, REVIEW_GATE_AGY_BIN: mockShim } }
  );
  assert.equal(liveErr.status, 1);
  assert.ok(liveErr.stderr.includes('ERROR'));

  // Empty committed diff does not get labeled "100% complete"
  const cleanDir = path.join(dir, 'clean-repo');
  fs.mkdirSync(cleanDir, { recursive: true });
  execFileSync('git', ['init'], { cwd: cleanDir, stdio: 'ignore' });
  execFileSync('git', ['config', 'user.email', 'test@example.com'], { cwd: cleanDir, stdio: 'ignore' });
  execFileSync('git', ['config', 'user.name', 'Test'], { cwd: cleanDir, stdio: 'ignore' });
  fs.writeFileSync(path.join(cleanDir, 'ok.js'), 'export const ok = 1;\n');
  execFileSync('git', ['add', 'ok.js'], { cwd: cleanDir, stdio: 'ignore' });
  execFileSync('git', ['commit', '-m', 'init'], { cwd: cleanDir, stdio: 'ignore' });
  const emptyDiffRun = spawnSync(
    process.execPath,
    [HOOK, '--run', '--dry-run', '--cwd', cleanDir, '--files', 'ok.js'],
    { encoding: 'utf8', env }
  );
  assert.equal(emptyDiffRun.status, 0, emptyDiffRun.stderr);
  assert.ok(!JSON.parse(emptyDiffRun.stdout).prompt.includes('100% complete'));

  // Non-result error event returns exit 1
  const eventErrRun = spawnSync(
    process.execPath,
    [HOOK, '--run', '--model', 'event-error-model', '--cwd', repoDir, '--files', 'a.js'],
    { encoding: 'utf8', env: { ...env, REVIEW_GATE_AGY_BIN: mockShim } }
  );
  assert.equal(eventErrRun.status, 1);
  assert.ok(eventErrRun.stderr.includes('auth expired'));

  // Windows path without extension resolves cleanly to .cmd even if an extensionless POSIX shim sits beside it
  if (process.platform === 'win32') {
    fs.writeFileSync(path.join(shimDir, 'mock-agy'), '#!/bin/sh\nexit 1\n');
    const extlessRun = spawnSync(
      process.execPath,
      [HOOK, '--run', '--cwd', repoDir, '--files', 'a.js'],
      { encoding: 'utf8', env: { ...env, REVIEW_GATE_AGY_BIN: path.join(shimDir, 'mock-agy') } }
    );
    assert.equal(extlessRun.status, 0, extlessRun.stderr);
  }

  // Instant exit when result arrives even if child keeps timers/pipes open
  const tLingerStart = Date.now();
  const lingerRun = spawnSync(
    process.execPath,
    [HOOK, '--run', '--model', 'linger-model', '--cwd', repoDir, '--files', 'a.js'],
    { encoding: 'utf8', env: { ...env, REVIEW_GATE_AGY_BIN: mockShim } }
  );
  assert.equal(lingerRun.status, 0, lingerRun.stderr);
  assert.equal(lingerRun.stdout.trim(), 'OK — fast');
  assert.ok(Date.now() - tLingerStart < 5000, 'lingerRun took too long');

  // Hard timeout kills hung child process quickly
  const tHangStart = Date.now();
  const hangRun = spawnSync(
    process.execPath,
    [HOOK, '--run', '--model', 'hang-model', '--cwd', repoDir, '--files', 'a.js'],
    { encoding: 'utf8', env: { ...env, REVIEW_GATE_AGY_BIN: mockShim, REVIEW_GATE_TIMEOUT_MS: '600' } }
  );
  assert.equal(hangRun.status, 1);
  assert.ok(hangRun.stderr.includes('Timed out'));
  assert.ok(Date.now() - tHangStart < 5000, 'hangRun took too long');

  // Non-dry-run overflow passes --add-dir <patchDir> and cleans up its temporary patch directory after spawn finishes
  const tmpMarker = `agy-review-gate-`;
  const patchRoot = process.platform === 'win32'
    ? os.tmpdir()
    : path.join(os.homedir(), '.cache', 'agy-review-gate');
  const bigRepoFile = path.join(repoDir, 'big-patch.txt');
  fs.writeFileSync(bigRepoFile, 'Z'.repeat(5000));
  const beforeDirs = fs.existsSync(patchRoot)
    ? new Set(fs.readdirSync(patchRoot).filter((n) => n.startsWith(tmpMarker)))
    : new Set();
  const liveOverflow = spawnSync(
    process.execPath,
    [HOOK, '--run', `--max-inline-chars=200`, `--cwd=${repoDir}`, '--files', 'big-patch.txt'],
    { encoding: 'utf8', env: { ...env, REVIEW_GATE_AGY_BIN: mockShim } }
  );
  assert.equal(liveOverflow.status, 0, liveOverflow.stderr);
  assert.ok(liveOverflow.stdout.includes('addDir=true'));
  const afterDirs = fs.existsSync(patchRoot)
    ? fs.readdirSync(patchRoot).filter((n) => n.startsWith(tmpMarker) && !beforeDirs.has(n))
    : [];
  assert.deepEqual(afterDirs, []);
});
