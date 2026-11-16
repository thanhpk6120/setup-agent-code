import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
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

function runHook(payload, configPath, hookPath = HOOK) {
  const env = { ...process.env };
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
