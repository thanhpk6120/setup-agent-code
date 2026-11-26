#!/usr/bin/env node
// Lightweight Memorix gate hook for Antigravity CLI:
// - start (PreInvocation): once per session, reminds the agent to load repo context via MCP `memorix_project_context`.
// - post (PostInvocation): emits inline `user_markdown` log/response summary whenever a Memorix MCP tool ran.
// - stop (Stop): if the current turn edited files without calling a Memorix save tool, blocks Stop once.
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const EDIT_TOOLS = new Set([
  'write_file',
  'edit_file',
  'replace_file_content',
  'multi_replace_file_content',
  'write_to_file'
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
  if (!step || step.type !== 'USER_INPUT') return false;
  if (step.source && step.source !== 'USER_EXPLICIT') return false;
  const text = typeof step.content === 'string' ? step.content.trim() : '';
  if (text.startsWith('<SYSTEM_MESSAGE>')) return false;
  return true;
}

function getCurrentTurn(steps) {
  let lastUserIdx = -1;
  for (let i = steps.length - 1; i >= 0; i--) {
    if (isRealUserTurnStart(steps[i])) {
      lastUserIdx = i;
      break;
    }
  }
  return {
    turnStartIdx: lastUserIdx,
    steps: lastUserIdx >= 0 ? steps.slice(lastUserIdx + 1) : steps
  };
}

function unquoteArg(val) {
  if (typeof val !== 'string') return '';
  try {
    const parsed = JSON.parse(val);
    return typeof parsed === 'string' ? parsed : val;
  } catch {
    return val.replace(/^"|"$/g, '');
  }
}

function extractToolCalls(step) {
  if (!step || !Array.isArray(step.tool_calls)) return [];
  return step.tool_calls.map((c) => {
    const rawName = String(c?.name || c?.toolName || '');
    const rawArgs = c?.args ?? c?.arguments ?? c?.input ?? {};
    if (rawName === 'call_mcp_tool') {
      const serverName = unquoteArg(rawArgs.ServerName);
      const toolName = unquoteArg(rawArgs.ToolName);
      if (toolName) {
        return {
          name: toolName,
          isMemorix: serverName === 'memorix' || /^memorix_/.test(toolName),
          args: rawArgs
        };
      }
    }
    return {
      name: rawName,
      isMemorix: /(?:^|[_:])memorix_/.test(rawName),
      args: rawArgs
    };
  });
}

function getSessionHash(payload, transcriptPath) {
  const sessionKey = String(
    payload.conversationId || payload.session_id || payload.sessionId || payload.conversation_id || transcriptPath || ''
  );
  if (!sessionKey) return '';
  return crypto.createHash('sha1').update(`antigravity:${sessionKey}`).digest('hex').slice(0, 16);
}

function cleanToolResponse(content) {
  if (typeof content !== 'string' || !content.trim()) return [];
  const lines = content
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l && !/^(?:Created|Completed) At:\s/i.test(l));
  return lines.slice(0, 4).map((l) => (l.length > 160 ? `${l.slice(0, 157)}...` : l));
}

function findToolResponseLines(steps, plannerIdx, toolPos) {
  let seenGeneric = 0;
  for (let j = plannerIdx + 1; j < steps.length; j++) {
    const st = steps[j];
    if (!st) continue;
    if (st.type === 'PLANNER_RESPONSE' || st.type === 'USER_INPUT') break;
    if (st.type === 'GENERIC') {
      if (seenGeneric === toolPos) return cleanToolResponse(st.content);
      seenGeneric += 1;
    }
  }
  return [];
}

function handlePost(payload) {
  const transcriptPath = payload.transcriptPath || payload.transcript_path;
  const steps = readSteps(transcriptPath);
  if (steps.length === 0) return {};

  const hash = getSessionHash(payload, transcriptPath);
  const cursorFile = hash ? path.join(os.tmpdir(), `memorix-gate-post-${hash}.cursor`) : '';

  let startIdx = 0;
  if (cursorFile && fs.existsSync(cursorFile)) {
    const prev = Number.parseInt(fs.readFileSync(cursorFile, 'utf8').trim(), 10);
    if (Number.isFinite(prev) && prev >= 0 && prev <= steps.length) startIdx = prev;
  } else {
    for (let i = steps.length - 1; i >= 0; i--) {
      if (isRealUserTurnStart(steps[i])) {
        startIdx = i + 1;
        break;
      }
    }
  }

  if (cursorFile) {
    try { fs.writeFileSync(cursorFile, String(steps.length), 'utf8'); } catch {}
  }

  const entries = [];
  for (let i = startIdx; i < steps.length; i++) {
    const calls = extractToolCalls(steps[i]);
    for (let pos = 0; pos < calls.length; pos++) {
      const call = calls[pos];
      if (!call.isMemorix) continue;
      const respLines = findToolResponseLines(steps, i, pos);
      const shortName = call.name.replace(/^mcp_memorix_/, '');
      const header = `> **Memorix** \`${shortName}\``;
      const body = respLines.length > 0 ? respLines.map((l) => `> ${l}`).join('\n') : '> *(executed)*';
      entries.push(`${header}\n${body}`);
    }
  }

  if (entries.length === 0) return {};
  return {
    injectSteps: [{
      systemMessage: {
        systemMessage: '',
        metadata: {
          user_markdown: entries.join('\n>\n')
        }
      }
    }]
  };
}

function handleStart(payload) {
  const transcriptPath = payload.transcriptPath || payload.transcript_path;
  const steps = readSteps(transcriptPath);
  for (const step of steps) {
    for (const call of extractToolCalls(step)) {
      if (MEMORIX_LOAD_RE.test(call.name)) return {};
    }
  }

  const hash = getSessionHash(payload, transcriptPath);
  if (hash) {
    const marker = path.join(os.tmpdir(), `memorix-gate-${hash}.seen`);
    if (fs.existsSync(marker)) return {};
    try { fs.writeFileSync(marker, String(Date.now()), 'utf8'); } catch {}
  }

  return {
    injectSteps: [{
      systemMessage: {
        systemMessage: '[Memorix] Đầu session mới: hãy gọi MCP tool `memorix_project_context` (với mô tả task) ngay trong lượt đầu tiên trước khi đọc sâu codebase hoặc git log (nếu chạy trên Antigravity App và báo lỗi chưa nhận diện được git project/workspace root, gọi `memorix_session_start({ projectRoot: "<workspace>" })` để bind workspace trước rồi gọi lại `memorix_project_context`; chỉ bỏ qua nếu là chào hỏi/hỏi đáp thuần túy không liên quan workspace).',
        metadata: {
          user_markdown: '> **Memorix** `session-start` — đã nhắc nạp ngữ cảnh dự án (`memorix_project_context`)'
        }
      }
    }]
  };
}

function isCliMemorixSave(call) {
  if (!call || !/^(?:run_command|bash|powershell)$/i.test(call.name)) return false;
  const cmd = String(call.args?.CommandLine || call.args?.command || call.args?.cmd || '');
  return /\bmemorix\s+(?:store|remember|session)\b/i.test(cmd);
}

function handleStop(payload) {
  if (payload.continuationActive === true || (payload.terminationReason && payload.terminationReason !== 'NO_TOOL_CALL')) {
    return {};
  }
  const transcriptPath = payload.transcriptPath || payload.transcript_path;
  const { turnStartIdx, steps } = getCurrentTurn(readSteps(transcriptPath));

  let seq = 0;
  let lastEditSeq = -1;
  let lastSaveSeq = -1;
  for (const step of steps) {
    for (const call of extractToolCalls(step)) {
      seq += 1;
      if (EDIT_TOOLS.has(call.name)) lastEditSeq = seq;
      if (MEMORIX_SAVE_RE.test(call.name) || isCliMemorixSave(call)) lastSaveSeq = seq;
    }
  }

  if (lastEditSeq === -1 || lastSaveSeq >= lastEditSeq) return {};

  const hash = getSessionHash(payload, transcriptPath);
  if (hash) {
    const blockKey = `${turnStartIdx}:${lastEditSeq}`;
    const marker = path.join(os.tmpdir(), `memorix-gate-stop-${hash}.seen`);
    try {
      if (fs.existsSync(marker) && fs.readFileSync(marker, 'utf8').trim() === blockKey) return {};
      fs.writeFileSync(marker, blockKey, 'utf8');
    } catch {}
  }

  return {
    decision: 'continue',
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
    const out = event === 'start'
      ? handleStart(payload)
      : event === 'post'
        ? handlePost(payload)
        : handleStop(payload);
    process.stdout.write(`${JSON.stringify(out)}\n`);
  } catch {
    process.stdout.write('{}\n');
  }
}

main();
