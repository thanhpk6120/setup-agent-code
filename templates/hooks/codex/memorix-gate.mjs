#!/usr/bin/env node
// Lightweight Memorix gate hook for OpenAI Codex CLI:
// - start (UserPromptSubmit): once per session, reminds the agent to load repo context via MCP `memorix_project_context`.
// - stop (Stop): if the current turn edited files without calling a Memorix save tool, blocks Stop once.
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const EDIT_TOOLS = new Set([
  'apply_patch',
  'write_file',
  'edit_file',
  'create_file',
  'replace_file_content'
]);

const MEMORIX_LOAD_RE = /(?:^|[_:])memorix_(?:project_context|session_start)$/;
const MEMORIX_SAVE_RE = /(?:^|[_:])memorix_(?:store|store_reasoning|session_end|resolve)$/;

function getEventArg() {
  const idx = process.argv.indexOf('--event');
  if (idx >= 0 && process.argv[idx + 1]) return process.argv[idx + 1].trim().toLowerCase();
  return 'stop';
}

function readStdin() {
  if (process.stdin.isTTY) return Promise.resolve('');
  return new Promise((resolve) => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => { data += chunk; });
    process.stdin.on('end', () => resolve(data));
    process.stdin.on('error', () => resolve(''));
  });
}

function readSteps(transcriptPath) {
  if (!transcriptPath || !fs.existsSync(transcriptPath)) return [];
  const raw = fs.readFileSync(transcriptPath, 'utf8');
  const lines = raw.split(/\r?\n/).filter(Boolean);
  const steps = [];
  for (const line of lines) {
    try { steps.push(JSON.parse(line)); } catch {}
  }
  return steps;
}

function isRealUserTurnStart(step) {
  if (!step) return false;
  if (step.source === 'USER_EXPLICIT') return true;
  if (step.type === 'event_msg' && step.payload?.type === 'user_message') return true;
  if (step.type === 'response_item' && step.payload?.type === 'message' && step.payload?.role === 'user') return true;
  return false;
}

function getCurrentTurnSteps(steps) {
  let lastUserIdx = -1;
  for (let i = steps.length - 1; i >= 0; i--) {
    if (isRealUserTurnStart(steps[i])) {
      lastUserIdx = i;
      break;
    }
  }
  return lastUserIdx >= 0 ? steps.slice(lastUserIdx + 1) : steps;
}

function extractToolCalls(step) {
  const out = [];
  if (Array.isArray(step?.tool_calls)) {
    for (const c of step.tool_calls) {
      out.push({ name: String(c?.name || c?.toolName || '') });
    }
  }
  if (step?.type === 'response_item' && (step.payload?.type === 'function_call' || step.payload?.type === 'custom_tool_call')) {
    out.push({ name: String(step.payload.name || '') });
  }
  if (step?.type === 'function_call' || step?.type === 'custom_tool_call') {
    out.push({ name: String(step.name || '') });
  }
  return out;
}

function handleStart(payload) {
  const transcriptPath = payload.transcript_path || payload.transcriptPath;
  const steps = readSteps(transcriptPath);
  for (const step of steps) {
    for (const call of extractToolCalls(step)) {
      if (MEMORIX_LOAD_RE.test(call.name)) return {};
    }
  }

  const sessionKey = String(
    payload.session_id || payload.sessionId || transcriptPath || ''
  );
  if (sessionKey) {
    const hash = crypto.createHash('sha1').update(`codex:${sessionKey}`).digest('hex').slice(0, 16);
    const marker = path.join(os.tmpdir(), `memorix-gate-${hash}.seen`);
    if (fs.existsSync(marker)) return {};
    try { fs.writeFileSync(marker, String(Date.now()), 'utf8'); } catch {}
  }

  return {
    hookSpecificOutput: {
      hookEventName: 'UserPromptSubmit',
      additionalContext: '[Memorix] Đầu session mới: nếu tác vụ này liên quan đến repo/code hoặc tiếp tục công việc cũ, hãy gọi MCP tool `memorix_project_context` (với mô tả task) trước khi đọc sâu codebase.'
    }
  };
}

function handleStop(payload) {
  if (payload.stop_hook_active === true) return {};
  const transcriptPath = payload.transcript_path || payload.transcriptPath;
  const steps = getCurrentTurnSteps(readSteps(transcriptPath));

  let seq = 0;
  let lastEditSeq = -1;
  let lastSaveSeq = -1;
  for (const step of steps) {
    for (const call of extractToolCalls(step)) {
      seq += 1;
      if (EDIT_TOOLS.has(call.name)) lastEditSeq = seq;
      if (MEMORIX_SAVE_RE.test(call.name)) lastSaveSeq = seq;
    }
  }

  if (lastEditSeq === -1 || lastSaveSeq >= lastEditSeq) return {};

  return {
    decision: 'block',
    reason: '[Memorix Gate] Bạn vừa thay đổi file trong lượt này nhưng chưa cập nhật bộ nhớ phiên. Nếu có quyết định kỹ thuật, bugfix, thay đổi cấu hình hoặc kết quả quan trọng cần nhớ cho phiên sau, hãy gọi MCP `memorix_store` hoặc `memorix_session_end` trước khi kết thúc (nếu chỉ là sửa nhỏ không đáng lưu, hãy trả lời ngắn gọn để hoàn tất).'
  };
}

async function main() {
  if (process.env.MEMORIX_GATE_ENABLED === '0') {
    process.stdout.write('{}\n');
    return;
  }
  let payload = {};
  try {
    const raw = await readStdin();
    if (raw.trim()) payload = JSON.parse(raw);
  } catch {
    process.stdout.write('{}\n');
    return;
  }

  try {
    const event = getEventArg();
    const out = event === 'start' ? handleStart(payload) : handleStop(payload);
    process.stdout.write(`${JSON.stringify(out)}\n`);
  } catch {
    process.stdout.write('{}\n');
  }
}

main();
