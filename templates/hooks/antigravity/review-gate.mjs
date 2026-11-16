#!/usr/bin/env node
// Stop hook for Antigravity CLI: requires a fast independent subagent review
// whenever the current turn modified non-trivial code/config files.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DEFAULT_CONFIG = { enabled: true, model: 'inherit' };
const VALID_MODELS = new Set(['flash_lite', 'flash', 'pro', 'inherit']);

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
    const normalizedModel = rawModel === 'flash-lite' ? 'flash_lite' : rawModel;
    const model = VALID_MODELS.has(normalizedModel)
      ? normalizedModel
      : DEFAULT_CONFIG.model;
    return { enabled, model };
  } catch {
    return { ...DEFAULT_CONFIG };
  }
}

const EDIT_TOOLS = new Set([
  'write_file',
  'edit_file',
  'replace_file_content',
  'multi_replace_file_content',
  'write_to_file'
]);

const DOC_ONLY_EXTS = new Set(['.md', '.txt', '.mdx']);

const REVIEW_TOOLS = new Set([
  'invoke_subagent',
  'run_workflow'
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
  if (step.type !== 'USER_INPUT') return false;
  const text = String(step.content || '').trimStart();
  return !text.startsWith('<SYSTEM_MESSAGE>') && !text.startsWith('Stop hook blocked termination:');
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

function isReviewCall(call) {
  const name = call?.name || call?.toolName || '';
  if (REVIEW_TOOLS.has(name)) return true;
  if (name === 'swarm') {
    const action = call?.args?.action || call?.arguments?.action;
    return action === 'add';
  }
  return false;
}

function extractEditedPath(call) {
  const args = call?.args || call?.arguments || {};
  return String(args.Path || args.path || args.TargetFile || args.file || '');
}

function analyzeTurn(steps) {
  let lastEditSeq = -1;
  let lastReviewSeq = -1;
  let seq = 0;
  const editedPathsAfterReview = [];
  let hasUnreviewedUnknownEdit = false;

  for (const step of steps) {
    const calls = Array.isArray(step?.tool_calls) ? step.tool_calls : [];
    for (const call of calls) {
      seq += 1;
      const name = call?.name || call?.toolName || '';
      if (EDIT_TOOLS.has(name)) {
        lastEditSeq = seq;
        const p = extractEditedPath(call);
        if (p) editedPathsAfterReview.push({ seq, path: p });
        else hasUnreviewedUnknownEdit = true;
      }
      if (isReviewCall(call)) lastReviewSeq = seq;
    }
  }

  if (lastEditSeq === -1 || lastReviewSeq >= lastEditSeq) {
    return { needsReview: false, files: [] };
  }

  const pendingPaths = editedPathsAfterReview
    .filter((item) => item.seq > lastReviewSeq)
    .map((item) => item.path);
  const uniqueFiles = [...new Set(pendingPaths)];

  // Skip review overhead when the turn only touched a single doc/text file.
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

  // Only enforce on normal turn completion, and never re-trigger once continuation is active.
  if (payload.continuationActive === true || (payload.terminationReason && payload.terminationReason !== 'NO_TOOL_CALL')) {
    process.stdout.write('{}\n');
    return;
  }

  const config = loadConfig();
  if (!config.enabled) {
    process.stdout.write('{}\n');
    return;
  }

  try {
    const transcriptPath = payload.transcriptPath || payload.transcript_path;
    const steps = getCurrentTurnSteps(transcriptPath);
    const analysis = analyzeTurn(steps);
    if (analysis.needsReview) {
      const targetHint = analysis.files.length ? ` (${analysis.files.map((f) => path.basename(f)).join(', ')})` : '';
      process.stdout.write(`${JSON.stringify({
        decision: 'continue',
        reason: [
          `[Review Gate] Bạn vừa sửa file${targetHint} nhưng chưa có review độc lập.`,
          `Hãy gọi \`invoke_subagent\` với \`TypeName: "research"\`, \`Model: "${config.model}"\` (dùng \`/advisor\` để đổi model hoặc tắt/bật), \`Role: "Independent Reviewer"\` để kiểm tra nhanh:`,
          '1) Chỉ soi `git diff` hoặc đúng các file vừa sửa (áp dụng cho cả code, config, docs, schema), KHÔNG chạy lại toàn bộ test suite;',
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
