import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

function runHook(relPath, event, payload, env = {}) {
  const script = path.join(ROOT, relPath);
  const res = spawnSync(process.execPath, [script, '--event', event], {
    input: JSON.stringify(payload),
    encoding: 'utf8',
    env: { ...process.env, ...env },
    timeout: 10000
  });
  assert.equal(res.status, 0, `Hook ${relPath} --event ${event} failed: ${res.stderr}`);
  return JSON.parse(res.stdout.trim());
}

function makeTranscript(lines) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'memorix-gate-test-'));
  const file = path.join(dir, 'transcript.jsonl');
  fs.writeFileSync(file, lines.map((x) => JSON.stringify(x)).join('\n') + '\n', 'utf8');
  return { dir, file };
}

test('antigravity memorix-gate: start reminds once per session and skips after memorix_project_context', () => {
  const sid = `agy-${Date.now()}-${Math.random()}`;
  const t = makeTranscript([
    { type: 'USER_INPUT', source: 'USER_EXPLICIT', content: 'fix bug' }
  ]);
  try {
    const first = runHook('templates/hooks/antigravity/memorix-gate.mjs', 'start', { conversationId: sid, transcriptPath: t.file });
    assert.ok(Array.isArray(first.injectSteps) && first.injectSteps.length === 1);
    const sys = first.injectSteps[0].systemMessage;
    assert.match(sys?.systemMessage || '', /memorix_project_context/);
    assert.match(sys?.systemMessage || '', /memorix_session_start/);
    assert.match(sys?.metadata?.user_markdown || '', /memorix_project_context/);

    const second = runHook('templates/hooks/antigravity/memorix-gate.mjs', 'start', { conversationId: sid, transcriptPath: t.file });
    assert.deepEqual(second, {});

    const tLoaded = makeTranscript([
      { type: 'USER_INPUT', source: 'USER_EXPLICIT', content: 'fix bug' },
      { type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'mcp_memorix_memorix_project_context', args: {} }] }
    ]);
    const alreadyLoaded = runHook('templates/hooks/antigravity/memorix-gate.mjs', 'start', { session_id: `${sid}-2`, transcriptPath: tLoaded.file });
    assert.deepEqual(alreadyLoaded, {});
    fs.rmSync(tLoaded.dir, { recursive: true, force: true });
  } finally {
    fs.rmSync(t.dir, { recursive: true, force: true });
  }
});

test('antigravity memorix-gate: stop allows read-only, blocks unpersisted edits once, allows after memorix_store', () => {
  const readOnly = makeTranscript([
    { type: 'USER_INPUT', source: 'USER_EXPLICIT', content: 'explain' },
    { type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'read_file', args: { Path: 'a.js' } }] }
  ]);
  const unpersisted = makeTranscript([
    { type: 'USER_INPUT', source: 'USER_EXPLICIT', content: 'edit' },
    { type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'edit_file', args: { Path: 'a.js' } }] }
  ]);
  const persisted = makeTranscript([
    { type: 'USER_INPUT', source: 'USER_EXPLICIT', content: 'edit' },
    { type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'edit_file', args: { Path: 'a.js' } }, { name: 'mcp_memorix_memorix_store', args: {} }] }
  ]);
  const persistedLazy = makeTranscript([
    { type: 'USER_INPUT', source: 'USER_EXPLICIT', content: 'edit' },
    { type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'edit_file', args: { Path: 'a.js' } }, { name: 'call_mcp_tool', args: { ServerName: '"memorix"', ToolName: '"memorix_store"' } }] }
  ]);
  try {
    assert.deepEqual(runHook('templates/hooks/antigravity/memorix-gate.mjs', 'stop', { transcriptPath: readOnly.file, terminationReason: 'NO_TOOL_CALL' }), {});

    const blocked = runHook('templates/hooks/antigravity/memorix-gate.mjs', 'stop', { transcriptPath: unpersisted.file, terminationReason: 'NO_TOOL_CALL' });
    assert.equal(blocked.decision, 'continue');
    assert.match(blocked.reason, /memorix_store/);

    // Re-running Stop in the same turn without new edits must not block in a loop
    assert.deepEqual(runHook('templates/hooks/antigravity/memorix-gate.mjs', 'stop', { transcriptPath: unpersisted.file, terminationReason: 'NO_TOOL_CALL' }), {});

    assert.deepEqual(runHook('templates/hooks/antigravity/memorix-gate.mjs', 'stop', { transcriptPath: unpersisted.file, continuationActive: true, terminationReason: 'NO_TOOL_CALL' }), {});
    assert.deepEqual(runHook('templates/hooks/antigravity/memorix-gate.mjs', 'stop', { transcriptPath: persisted.file, terminationReason: 'NO_TOOL_CALL' }), {});
    assert.deepEqual(runHook('templates/hooks/antigravity/memorix-gate.mjs', 'stop', { transcriptPath: persistedLazy.file, terminationReason: 'NO_TOOL_CALL' }), {});

    const persistedCli = makeTranscript([
      { type: 'USER_INPUT', source: 'USER_EXPLICIT', content: 'edit' },
      { type: 'PLANNER_RESPONSE', tool_calls: [{ name: 'edit_file', args: { Path: 'a.js' } }, { name: 'run_command', args: { CommandLine: 'memorix remember "Saved note"' } }] }
    ]);
    try {
      assert.deepEqual(runHook('templates/hooks/antigravity/memorix-gate.mjs', 'stop', { transcriptPath: persistedCli.file, terminationReason: 'NO_TOOL_CALL' }), {});
    } finally {
      fs.rmSync(persistedCli.dir, { recursive: true, force: true });
    }
  } finally {
    fs.rmSync(readOnly.dir, { recursive: true, force: true });
    fs.rmSync(unpersisted.dir, { recursive: true, force: true });
    fs.rmSync(persisted.dir, { recursive: true, force: true });
    fs.rmSync(persistedLazy.dir, { recursive: true, force: true });
  }
});

test('antigravity memorix-gate: post emits user_markdown once per memorix call with response summary', () => {
  const sid = `agy-post-${Date.now()}-${Math.random()}`;
  const t = makeTranscript([
    { type: 'USER_INPUT', source: 'USER_EXPLICIT', content: 'check' },
    {
      type: 'PLANNER_RESPONSE',
      tool_calls: [
        { name: 'read_file', args: { Path: 'a.js' } },
        { name: 'call_mcp_tool', args: { ServerName: '"memorix"', ToolName: '"memorix_project_context"' } }
      ]
    },
    { type: 'GENERIC', source: 'MODEL', content: 'file content' },
    { type: 'GENERIC', source: 'MODEL', content: 'Created At: 2026-11-17\nMemorix Autopilot Brief for demo\nMemories: 2 active / 3 total' }
  ]);
  try {
    const first = runHook('templates/hooks/antigravity/memorix-gate.mjs', 'post', { conversationId: sid, transcriptPath: t.file });
    assert.ok(Array.isArray(first.injectSteps) && first.injectSteps.length === 1);
    const msg = first.injectSteps[0].systemMessage;
    assert.equal(msg.systemMessage, '');
    assert.match(msg.metadata.user_markdown, /memorix_project_context/);
    assert.match(msg.metadata.user_markdown, /Memorix Autopilot Brief for demo/);

    // Re-running without new steps should not duplicate output
    const second = runHook('templates/hooks/antigravity/memorix-gate.mjs', 'post', { conversationId: sid, transcriptPath: t.file });
    assert.deepEqual(second, {});

    // Appending another memorix call reports only the new call
    fs.appendFileSync(t.file, JSON.stringify({
      type: 'PLANNER_RESPONSE',
      tool_calls: [{ name: 'mcp_memorix_memorix_store', args: { title: 'Save note' } }]
    }) + '\n', 'utf8');
    const third = runHook('templates/hooks/antigravity/memorix-gate.mjs', 'post', { conversationId: sid, transcriptPath: t.file });
    assert.ok(Array.isArray(third.injectSteps) && third.injectSteps.length === 1);
    assert.match(third.injectSteps[0].systemMessage.metadata.user_markdown, /memorix_store/);
    assert.doesNotMatch(third.injectSteps[0].systemMessage.metadata.user_markdown, /memorix_project_context/);
  } finally {
    fs.rmSync(t.dir, { recursive: true, force: true });
  }
});

test('claude memorix-gate: UserPromptSubmit and Stop enforce MCP load/save without blocking read-only or stop_hook_active', () => {
  const sid = `claude-${Date.now()}-${Math.random()}`;
  const unpersisted = makeTranscript([
    { type: 'user', message: { content: 'edit' } },
    { type: 'assistant', message: { content: [{ type: 'tool_use', name: 'Edit', input: { file_path: 'a.js' } }] } }
  ]);
  const persisted = makeTranscript([
    { type: 'user', message: { content: 'edit' } },
    { type: 'assistant', message: { content: [{ type: 'tool_use', name: 'Edit', input: { file_path: 'a.js' } }, { type: 'tool_use', name: 'mcp__memorix__memorix_session_end', input: {} }] } }
  ]);
  try {
    const start1 = runHook('templates/hooks/claude/memorix-gate.mjs', 'start', { session_id: sid, transcript_path: unpersisted.file });
    assert.equal(start1.hookSpecificOutput?.hookEventName, 'UserPromptSubmit');
    assert.match(start1.hookSpecificOutput?.additionalContext || '', /memorix_project_context/);

    const start2 = runHook('templates/hooks/claude/memorix-gate.mjs', 'start', { session_id: sid, transcript_path: unpersisted.file });
    assert.deepEqual(start2, {});

    const blocked = runHook('templates/hooks/claude/memorix-gate.mjs', 'stop', { transcript_path: unpersisted.file });
    assert.equal(blocked.decision, 'block');

    assert.deepEqual(runHook('templates/hooks/claude/memorix-gate.mjs', 'stop', { transcript_path: unpersisted.file, stop_hook_active: true }), {});
    assert.deepEqual(runHook('templates/hooks/claude/memorix-gate.mjs', 'stop', { transcript_path: persisted.file }), {});

    const postMem = runHook('templates/hooks/claude/memorix-gate.mjs', 'post', {
      tool_name: 'mcp__memorix__memorix_project_context',
      tool_response: 'Memorix Autopilot Brief\nMemories: 3 active'
    });
    assert.match(postMem.systemMessage || '', /memorix_project_context/);
    assert.match(postMem.systemMessage || '', /Memorix Autopilot Brief/);
    assert.deepEqual(runHook('templates/hooks/claude/memorix-gate.mjs', 'post', { tool_name: 'Read', tool_response: 'ok' }), {});
  } finally {
    fs.rmSync(unpersisted.dir, { recursive: true, force: true });
    fs.rmSync(persisted.dir, { recursive: true, force: true });
  }
});

test('codex memorix-gate: UserPromptSubmit and Stop handle apply_patch and memorix_store', () => {
  const sid = `codex-${Date.now()}-${Math.random()}`;
  const unpersisted = makeTranscript([
    { type: 'event_msg', payload: { type: 'user_message', text: 'patch' } },
    { type: 'response_item', payload: { type: 'custom_tool_call', name: 'apply_patch', input: '*** Update File: a.js\n' } }
  ]);
  const persisted = makeTranscript([
    { type: 'event_msg', payload: { type: 'user_message', text: 'patch' } },
    { type: 'response_item', payload: { type: 'custom_tool_call', name: 'apply_patch', input: '*** Update File: a.js\n' } },
    { type: 'response_item', payload: { type: 'function_call', name: 'memorix_store', arguments: '{}' } }
  ]);
  try {
    const start1 = runHook('templates/hooks/codex/memorix-gate.mjs', 'start', { session_id: sid, transcript_path: unpersisted.file });
    assert.equal(start1.hookSpecificOutput?.hookEventName, 'UserPromptSubmit');

    const blocked = runHook('templates/hooks/codex/memorix-gate.mjs', 'stop', { transcript_path: unpersisted.file });
    assert.equal(blocked.decision, 'block');

    assert.deepEqual(runHook('templates/hooks/codex/memorix-gate.mjs', 'stop', { transcript_path: persisted.file }), {});

    const postMem = runHook('templates/hooks/codex/memorix-gate.mjs', 'post', {
      tool_name: 'memorix_store',
      tool_response: '[OK] Stored observation #42'
    });
    assert.match(postMem.systemMessage || '', /memorix_store/);
    assert.match(postMem.systemMessage || '', /Stored observation #42/);
    assert.deepEqual(runHook('templates/hooks/codex/memorix-gate.mjs', 'post', { tool_name: 'apply_patch', tool_response: 'ok' }), {});
  } finally {
    fs.rmSync(unpersisted.dir, { recursive: true, force: true });
    fs.rmSync(persisted.dir, { recursive: true, force: true });
  }
});

test('opencode memorix-gate plugin reminds once on context and once on idle after unpersisted edits', async () => {
  const pluginSrc = fs.readFileSync(path.join(ROOT, 'templates/hooks/opencode/memorix-gate.js'), 'utf8');
  const modDir = fs.mkdtempSync(path.join(os.tmpdir(), 'memorix-opencode-test-'));
  try {
    fs.mkdirSync(path.join(modDir, 'node_modules/@opencode/plugin'), { recursive: true });
    fs.writeFileSync(path.join(modDir, 'node_modules/@opencode/plugin/package.json'), '{"name":"@opencode/plugin","type":"module","main":"index.js"}');
    fs.writeFileSync(path.join(modDir, 'node_modules/@opencode/plugin/index.js'), 'export const Plugin = { define: (p) => p };');
    const pluginFile = path.join(modDir, 'memorix-gate.mjs');
    fs.writeFileSync(pluginFile, pluginSrc);
    const { default: plugin } = await import(new URL(`file://${pluginFile.replace(/\\/g, '/')}`).href);

    const hooks = {};
    const synthetics = [];
    const toasts = [];
    await plugin.setup({
      tui: {
        showToast: async (t) => { toasts.push(t); }
      },
      session: {
        hook: (name, fn) => { hooks[`session.${name}`] = fn; },
        synthetic: async (msg) => { synthetics.push(msg); }
      },
      tool: {
        hook: (name, fn) => { hooks[`tool.${name}`] = fn; }
      }
    });

    const sys1 = [];
    await hooks['session.context']({ sessionID: 's1', system: sys1 });
    assert.equal(sys1.length, 1);
    assert.match(sys1[0].text, /memorix_project_context/);

    const sys2 = [];
    await hooks['session.context']({ sessionID: 's1', system: sys2 });
    assert.equal(sys2.length, 0);

    await hooks['tool.execute.after']({ sessionID: 's1', status: 'completed', tool: 'edit' });
    await hooks['session.experimental.idle']({ sessionID: 's1', background: [] });
    assert.equal(synthetics.length, 1);
    assert.match(synthetics[0].text, /memorix_store/);

    await hooks['session.experimental.idle']({ sessionID: 's1', background: [] });
    assert.equal(synthetics.length, 1);

    await hooks['tool.execute.after']({ sessionID: 's1', status: 'completed', tool: 'edit' });
    await hooks['tool.execute.after']({ sessionID: 's1', status: 'completed', tool: 'mcp_memorix_memorix_store', output: '[OK] Stored #7' });
    await hooks['session.experimental.idle']({ sessionID: 's1', background: [] });
    assert.equal(synthetics.length, 1);
    assert.equal(toasts.length, 1);
    assert.match(toasts[0].message, /memorix_store: \[OK\] Stored #7/);
  } finally {
    fs.rmSync(modDir, { recursive: true, force: true });
  }
});

test('omp memorix-gate extension reminds once on before_agent_start and followUp on agent_end after unpersisted edits', async () => {
  const tsSrc = fs.readFileSync(path.join(ROOT, 'templates/hooks/omp/memorix-gate.ts'), 'utf8');
  const jsSrc = tsSrc
    .replace(/interface PiContext \{[\s\S]*?\}\r?\n/, '')
    .replace(/interface PiInstance \{[\s\S]*?\}\r?\n\r?\n/, '')
    .replace(/function extractText\(raw: unknown\): string/g, 'function extractText(raw)')
    .replace(/function summarizeToolResult\(raw: unknown\): string/g, 'function summarizeToolResult(raw)')
    .replace(/const obj = raw as Record<string, unknown>;/g, 'const obj = raw;')
    .replace(/\(pi: PiInstance\)/g, '(pi)')
    .replace(/\(event: unknown, ctx\?: PiContext\)/g, '(event, ctx)')
    .replace(/\(event: unknown\)/g, '(event)')
    .replace(/event as Record<string, unknown>/g, 'event');
  const modDir = fs.mkdtempSync(path.join(os.tmpdir(), 'memorix-omp-test-'));
  try {
    const extFile = path.join(modDir, 'memorix-gate.mjs');
    fs.writeFileSync(extFile, jsSrc);
    const { default: register } = await import(new URL(`file://${extFile.replace(/\\/g, '/')}`).href);

    const handlers = {};
    const followUps = [];
    const messages = [];
    register({
      on: (ev, fn) => { handlers[ev] = fn; },
      sendMessage: (msg, opts) => { messages.push({ msg, opts }); },
      sendUserMessage: (msg, opts) => { followUps.push({ msg, opts }); }
    });

    const start1 = handlers.before_agent_start({});
    assert.equal(start1?.message?.customType, 'memorix-gate');
    assert.match(start1?.message?.content || '', /memorix_project_context/);
    assert.equal(handlers.before_agent_start({}), undefined);

    handlers.tool_call({ toolName: 'edit' });
    handlers.agent_end({});
    assert.equal(followUps.length, 1);
    assert.equal(followUps[0].opts.deliverAs, 'followUp');

    handlers.agent_end({});
    assert.equal(followUps.length, 1);

    handlers.tool_call({ toolName: 'edit' });
    handlers.tool_call({ toolName: 'memorix_store' });
    handlers.tool_result({ toolName: 'memorix_store', content: 'Stored #99' });
    assert.equal(messages.length, 1);
    assert.equal(messages[0].msg.display, true);
    assert.equal(messages[0].opts.triggerTurn, false);
    assert.match(messages[0].msg.content, /memorix_store: Stored #99/);
    handlers.agent_end({});
    assert.equal(followUps.length, 1);
  } finally {
    fs.rmSync(modDir, { recursive: true, force: true });
  }
});
