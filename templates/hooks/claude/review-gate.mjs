#!/usr/bin/env node
// Stop hook for Claude Code: requires a fast independent subagent review
// whenever the current turn modified non-trivial code/config files.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DEFAULT_CONFIG = { enabled: true, model: 'inherit' };
const VALID_MODELS = new Set(['inherit', 'haiku', 'sonnet', 'opus']);

function getConfigPath() {
  if (process.env.REVIEW_GATE_CONFIG) return process.env.REVIEW_GATE_CONFIG;
  return path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'review-gate.json');
}

function loadConfig() {
  try {
    const raw = fs.readFileSync(getConfigPath(), 'utf8');
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') return { ...DEFAULT_CONFIG };
    const enabled = typeof parsed.enabled === 'boolean' ? parsed.enabled : DEFAULT_CONFIG.enabled;
    const rawModel = typeof parsed.model === 'string' ? parsed.model.trim().toLowerCase() : '';
    const model = VALID_MODELS.has(rawModel) ? rawModel : DEFAULT_CONFIG.model;
    return { enabled, model };
  } catch {
    return { ...DEFAULT_CONFIG };
  }
}

const EDIT_TOOLS = new Set([
  'Edit',
  'Write',
  'MultiEdit',
  'NotebookEdit',
  'edit_file',
  'write_file'
]);

const DOC_ONLY_EXTS = new Set(['.md', '.txt', '.mdx']);

const REVIEW_TOOLS = new Set([
  'Agent',
  'Task'
]);

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

function isRealUserTurnStart(step) {
  if (!step) return false;
  if (step.source === 'USER_EXPLICIT') return true;
  if (step.type === 'user' && step.isMeta !== true) {
    const content = step.message?.content;
    if (Array.isArray(content) && content.length > 0 && content.every((c) => c && c.type === 'tool_result')) return false;
    return true;
  }
  return false;
}

function getCurrentTurnSteps(transcriptPath) {
  if (!transcriptPath || !fs.existsSync(transcriptPath)) return [];
  const raw = fs.readFileSync(transcriptPath, 'utf8');
  const lines = raw.split(/\r?\n/).filter(Boolean);
  const steps = [];
  for (const line of lines) {
    try {
      steps.push(JSON.parse(line));
    } catch {
      // Ignore partial/malformed trailing lines.
    }
  }
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
      out.push({ name: c?.name || c?.toolName || '', input: c?.args || c?.arguments || c?.input || {} });
    }
  }
  const content = step?.message?.content;
  if (Array.isArray(content)) {
    for (const item of content) {
      if (item && item.type === 'tool_use') {
        out.push({ name: item.name || '', input: item.input || {} });
      }
    }
  }
  return out;
}

function extractEditedPath(input) {
  return String(input?.file_path || input?.notebook_path || input?.path || input?.Path || '');
}

function analyzeTurn(steps) {
  let lastEditSeq = -1;
  let lastReviewSeq = -1;
  let seq = 0;
  const editedPathsAfterReview = [];
  let hasUnreviewedUnknownEdit = false;

  for (const step of steps) {
    for (const call of extractToolCalls(step)) {
      seq += 1;
      if (EDIT_TOOLS.has(call.name)) {
        lastEditSeq = seq;
        const p = extractEditedPath(call.input);
        if (p) editedPathsAfterReview.push({ seq, path: p });
        else hasUnreviewedUnknownEdit = true;
      }
      if (REVIEW_TOOLS.has(call.name)) lastReviewSeq = seq;
    }
  }

  if (lastEditSeq === -1 || lastReviewSeq >= lastEditSeq) {
    return { needsReview: false, files: [] };
  }

  const pendingPaths = editedPathsAfterReview
    .filter((item) => item.seq > lastReviewSeq)
    .map((item) => item.path);
  const uniqueFiles = [...new Set(pendingPaths)];

  if (!hasUnreviewedUnknownEdit && uniqueFiles.length === 1) {
    const ext = path.extname(uniqueFiles[0]).toLowerCase();
    if (DOC_ONLY_EXTS.has(ext)) {
      return { needsReview: false, files: uniqueFiles };
    }
  }

  return { needsReview: true, files: uniqueFiles };
}

async function main() {
  let payload = {};
  try {
    const raw = await readStdin();
    if (raw.trim()) payload = JSON.parse(raw);
  } catch {
    process.stdout.write('{}\n');
    return;
  }

  if (payload.stop_hook_active === true) {
    process.stdout.write('{}\n');
    return;
  }

  const config = loadConfig();
  if (!config.enabled) {
    process.stdout.write('{}\n');
    return;
  }

  try {
    const transcriptPath = payload.transcript_path || payload.transcriptPath;
    const steps = getCurrentTurnSteps(transcriptPath);
    const analysis = analyzeTurn(steps);
    if (analysis.needsReview) {
      const targetHint = analysis.files.length ? ` (${analysis.files.map((f) => path.basename(f)).join(', ')})` : '';
      const modelHint = config.model === 'inherit' ? 'model mặc định (`inherit`)' : `\`model: "${config.model}"\``;
      process.stdout.write(`${JSON.stringify({
        decision: 'block',
        reason: [
          `[Review Gate] Bạn vừa sửa file${targetHint} nhưng chưa có review độc lập.`,
          `Hãy gọi \`Agent\` tool (\`subagent_type: "general-purpose"\`, ${modelHint}, có thể đổi qua \`/advisor\`) với vai trò Independent Reviewer để kiểm tra nhanh:`,
          '1) Chỉ soi `git diff` hoặc đúng các file vừa sửa, KHÔNG chạy lại toàn bộ test suite;',
          '2) Trả lời tối đa 5-8 dòng (chỉ nêu bug, edge-case, cấu hình sai, hoặc phản bác nếu giải pháp chưa hợp lý; nếu ổn trả `OK — no issues`);',
          '3) Sửa lại nếu có lỗi thật rồi mới kết luận.'
        ].join(' ')
      })}\n`);
      return;
    }
  } catch {
    // Fail-open so a hook error never locks the CLI session.
  }

  process.stdout.write('{}\n');
}

main();
