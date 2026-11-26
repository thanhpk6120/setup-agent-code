#!/usr/bin/env node
// Stop hook for Antigravity CLI: requires a fast independent subagent review
// whenever the current turn modified non-trivial code/config files.
import { execFileSync, spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DEFAULT_CONFIG = { enabled: true, model: 'inherit' };
const SUBAGENT_TIERS = new Set(['flash_lite', 'flash', 'pro', 'inherit']);
const RESERVED_WORDS = new Set(['on', 'off', 'enable', 'disable', 'status', 'help']);
const SAFE_MODEL_RE = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$/;
const AGY_BINS = new Set(['agy', 'agy.exe', 'agy.cmd', 'agy.ps1']);
const NODE_BINS = new Set(['node', 'node.exe']);
const AGY_NON_PRINT_SUBCOMMANDS = new Set([
  'acp', 'agent', 'agents', 'changelog', 'chat', 'help',
  'install', 'mcp', 'mic-serve', 'models', 'plugin', 'plugins',
  'remote-control', 'update'
]);
const AGY_VALUE_FLAGS = new Set([
  '--add-dir', '--agent', '--conversation', '-r', '--resume',
  '--cwd', '--effort', '--input-format', '--json-schema', '--log-file',
  '--mode', '--model', '--output-format', '--print-timeout',
  '--project', '--prompt-interactive', '-i', '--settings'
]);
const NODE_VALUE_FLAGS = new Set([
  '-r', '--require', '--import', '--loader', '--env-file',
  '--conditions', '-C', '--input-type'
]);
const NODE_EVAL_FLAGS = new Set(['-e', '--eval', '-p', '--print']);
const RUN_KNOWN_FLAGS = new Set(['--run', '--dry-run', '--model', '--cwd', '--files', '--max-inline-chars', '--']);
const GENERATED_FILE_RE = /(?:^|[/\\])(?:package-lock\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lockb?|composer\.lock|Cargo\.lock|poetry\.lock|Gemfile\.lock|go\.sum)$|\.(?:min\.(?:js|css)|map|snap|svg)$/i;
const GENERATED_DIFF_EXCLUDES = [
  ':(exclude)*package-lock.json', ':(exclude)*pnpm-lock.yaml', ':(exclude)*yarn.lock',
  ':(exclude)*bun.lock', ':(exclude)*bun.lockb', ':(exclude)*composer.lock',
  ':(exclude)*Cargo.lock', ':(exclude)*poetry.lock', ':(exclude)*Gemfile.lock',
  ':(exclude)*go.sum', ':(exclude)*.min.js', ':(exclude)*.min.css',
  ':(exclude)*.map', ':(exclude)*.snap', ':(exclude)*.svg'
];
const MAX_INLINE_CHARS = 120_000;
const MAX_FILE_CHARS = 30_000;
const MAX_PATCH_CHARS = 2_000_000;
const SELF_SCRIPT = fileURLToPath(import.meta.url);

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
    const rawModel = typeof parsed.model === 'string' ? parsed.model.trim() : '';
    const lower = rawModel.toLowerCase();
    const normalizedTier = lower === 'flash-lite' ? 'flash_lite' : lower;
    let model = DEFAULT_CONFIG.model;
    if (SUBAGENT_TIERS.has(normalizedTier)) {
      model = normalizedTier;
    } else if (!RESERVED_WORDS.has(lower) && SAFE_MODEL_RE.test(rawModel)) {
      model = rawModel;
    }
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

const SHELL_TOOLS = new Set([
  'run_command',
  'bash',
  'powershell'
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

function unquoteArg(val) {
  if (typeof val !== 'string') return '';
  const trimmed = val.trim();
  if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
    try {
      const parsed = JSON.parse(trimmed);
      if (typeof parsed === 'string') return parsed;
    } catch {
      // Fall through and treat as raw command string.
    }
  }
  return val;
}

function splitShellStatements(cmd) {
  const normalized = cmd.replace(/[\\`]\r?\n/g, ' ');
  const statements = [];
  let tokens = [];
  let cur = '';
  let startsQuoted = false;
  let hasToken = false;
  let quoteChar = '';

  const flushToken = () => {
    if (hasToken) {
      tokens.push({ text: cur, startsQuoted });
      cur = '';
      startsQuoted = false;
      hasToken = false;
    }
  };
  const flushStmt = () => {
    flushToken();
    if (tokens.length > 0) {
      statements.push(tokens);
      tokens = [];
    }
  };

  for (let i = 0; i < normalized.length; i++) {
    const ch = normalized[i];
    if (quoteChar) {
      if (quoteChar === '"' && (ch === '\\' || ch === '`') && normalized[i + 1] === '"') {
        cur += '"';
        i += 1;
      } else if (ch === quoteChar) {
        quoteChar = '';
      } else {
        cur += ch;
      }
      continue;
    }
    if (ch === '"' || ch === "'") {
      if (!hasToken) startsQuoted = true;
      hasToken = true;
      quoteChar = ch;
    } else if (ch === ';' || ch === '&' || ch === '|' || ch === '\r' || ch === '\n' || ch === '{' || ch === '}') {
      flushStmt();
    } else if (/\s/.test(ch)) {
      flushToken();
    } else {
      hasToken = true;
      cur += ch;
    }
  }
  flushStmt();
  return statements;
}

function isCliReviewCall(call) {
  const name = String(call?.name || call?.toolName || '').toLowerCase();
  if (!SHELL_TOOLS.has(name)) return false;
  const args = call?.args || call?.arguments || {};
  const cmd = unquoteArg(String(args.CommandLine || args.command || args.cmd || ''));
  for (const stmt of splitShellStatements(cmd)) {
    let idx = 0;
    while (idx < stmt.length && !stmt[idx].startsQuoted) {
      const tok = stmt[idx].text;
      if (tok === 'try' || tok === 'env' || /^(?:\$env:)?[A-Za-z_][A-Za-z0-9_]*=/.test(tok)) {
        idx += 1;
        continue;
      }
      break;
    }
    if (idx >= stmt.length) continue;
    const bin = stmt[idx].text.split(/[/\\]/).pop().toLowerCase();
    if (AGY_BINS.has(bin)) {
      let seenPositional = false;
      for (let j = idx + 1; j < stmt.length; j++) {
        if (stmt[j].startsQuoted) continue;
        const flag = stmt[j].text;
        if (flag === '--') break;
        if (
          flag === '--print' || flag === '-p' || flag === '--prompt' ||
          flag.startsWith('--print=') || flag.startsWith('-p=') || flag.startsWith('--prompt=')
        ) {
          return true;
        }
        if (!flag.includes('=') && AGY_VALUE_FLAGS.has(flag)) {
          j += 1;
          continue;
        }
        if (!flag.startsWith('-') && !seenPositional) {
          seenPositional = true;
          if (AGY_NON_PRINT_SUBCOMMANDS.has(flag.toLowerCase())) break;
        }
      }
    } else if (NODE_BINS.has(bin) && idx + 1 < stmt.length) {
      let scriptIdx = -1;
      for (let j = idx + 1; j < stmt.length; j++) {
        const tok = stmt[j];
        if (!tok.startsQuoted && tok.text === '--') break;
        if (!tok.startsQuoted && tok.text.startsWith('-')) {
          const flagName = tok.text.split('=')[0];
          if (NODE_EVAL_FLAGS.has(flagName)) break;
          if (!tok.text.includes('=') && NODE_VALUE_FLAGS.has(flagName)) {
            j += 1;
          }
          continue;
        }
        scriptIdx = j;
        break;
      }
      if (scriptIdx !== -1) {
        const scriptBase = stmt[scriptIdx].text.split(/[/\\]/).pop().toLowerCase();
        if (scriptBase === 'review-gate.mjs') {
          let hasRun = false;
          let hasDryRun = false;
          for (let j = scriptIdx + 1; j < stmt.length; j++) {
            if (stmt[j].startsQuoted) continue;
            const flag = stmt[j].text;
            if (flag === '--') break;
            if (flag === '--run') hasRun = true;
            if (flag === '--dry-run') hasDryRun = true;
          }
          if (hasRun && !hasDryRun) return true;
        }
      }
    }
  }
  return false;
}

function isReviewCall(call) {
  const name = call?.name || call?.toolName || '';
  if (REVIEW_TOOLS.has(name)) return true;
  if (name === 'swarm') {
    const action = call?.args?.action || call?.arguments?.action;
    return action === 'add';
  }
  return isCliReviewCall(call);
}

function extractEditedPath(call) {
  const args = call?.args || call?.arguments || {};
  return unquoteArg(String(args.Path || args.path || args.TargetFile || args.file || '')).trim();
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

function runGit(args, cwd) {
  try {
    return execFileSync('git', ['--no-optional-locks', ...args], {
      cwd,
      encoding: 'utf8',
      timeout: 5000,
      maxBuffer: 16 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'ignore'],
      windowsHide: true
    });
  } catch {
    return null;
  }
}

function findGitRoot(cwd) {
  const out = runGit(['rev-parse', '--show-toplevel'], cwd);
  return out ? path.resolve(out.trim()) : null;
}

function realPathOrResolve(targetPath) {
  let cur = path.resolve(targetPath);
  const tail = [];
  while (!fs.existsSync(cur)) {
    const parent = path.dirname(cur);
    if (parent === cur) return path.resolve(targetPath);
    tail.push(path.basename(cur));
    cur = parent;
  }
  try {
    cur = fs.realpathSync(cur);
  } catch {
    // Keep resolved path if realpath fails.
  }
  return tail.length > 0 ? path.join(cur, ...tail.reverse()) : cur;
}

function isSubPath(parentDir, targetPath) {
  const rawParent = realPathOrResolve(parentDir);
  const rawTarget = realPathOrResolve(targetPath);
  const normParent = process.platform === 'win32' ? rawParent.toLowerCase() : rawParent;
  const normTarget = process.platform === 'win32' ? rawTarget.toLowerCase() : rawTarget;
  const rel = path.relative(normParent, normTarget);
  return rel !== '' && rel !== '..' && !rel.startsWith(`..${path.sep}`) && !path.isAbsolute(rel);
}

function readTextFileSafe(filePath, maxChars = MAX_FILE_CHARS) {
  let fd = null;
  try {
    fd = fs.openSync(filePath, 'r');
    const stat = fs.fstatSync(fd);
    if (!stat.isFile()) return { text: '[not a regular file]', truncated: false };
    const maxBytes = maxChars * 4 + 64;
    const toRead = Math.min(stat.size, maxBytes);
    const buf = Buffer.allocUnsafe(toRead);
    const bytesRead = toRead > 0 ? fs.readSync(fd, buf, 0, toRead, 0) : 0;
    const probeLen = Math.min(bytesRead, 1024);
    for (let i = 0; i < probeLen; i++) {
      if (buf[i] === 0) return { text: '[binary file omitted]', truncated: false };
    }
    const text = buf.subarray(0, bytesRead).toString('utf8');
    if (text.length <= maxChars && stat.size <= bytesRead) return { text, truncated: false };
    return {
      text: `${text.slice(0, maxChars)}\n... [truncated; file size ${stat.size} bytes]`,
      truncated: true
    };
  } catch (err) {
    return { text: `[unable to read: ${err?.message || 'error'}]`, truncated: false };
  } finally {
    if (fd !== null) {
      try { fs.closeSync(fd); } catch {}
    }
  }
}

function getPatchTempRoot() {
  if (process.platform !== 'win32') {
    const homeCache = path.join(os.homedir(), '.cache', 'agy-review-gate');
    try {
      fs.mkdirSync(homeCache, { recursive: true, mode: 0o700 });
      return homeCache;
    } catch {
      // Fallback to os.tmpdir() if home directory is read-only.
    }
  }
  return os.tmpdir();
}

function writeRollingPatchFile(content) {
  const dir = fs.mkdtempSync(path.join(getPatchTempRoot(), 'agy-review-gate-'));
  const patchPath = path.join(dir, 'changes.patch');
  const capped = content.length > MAX_PATCH_CHARS;
  const body = capped
    ? `${content.slice(0, MAX_PATCH_CHARS)}\n\n... [patch truncated at ${MAX_PATCH_CHARS} chars; original ${content.length} chars]`
    : content;
  fs.writeFileSync(patchPath, body, { encoding: 'utf8', mode: 0o600 });
  return { patchPath, patchCapped: capped };
}

function findGitRootCached(dirPath, cache) {
  const existingDir = realPathOrResolve(dirPath);
  let cur = existingDir;
  while (!fs.existsSync(cur) || !fs.statSync(cur).isDirectory()) {
    const parent = path.dirname(cur);
    if (parent === cur) break;
    cur = parent;
  }
  const key = process.platform === 'win32' ? cur.toLowerCase() : cur;
  if (cache.has(key)) return cache.get(key);
  const root = findGitRoot(cur);
  const canonical = root ? realPathOrResolve(root) : null;
  cache.set(key, canonical);
  return canonical;
}

function collectChanges({ cwd, files, maxInlineChars = MAX_INLINE_CHARS }) {
  const baseDir = realPathOrResolve(cwd || process.cwd());
  const seen = new Set();
  const resolvedFiles = [];
  for (const f of files || []) {
    if (!f || typeof f !== 'string') continue;
    const abs = realPathOrResolve(path.resolve(baseDir, f));
    const key = process.platform === 'win32' ? abs.toLowerCase() : abs;
    if (!seen.has(key)) {
      seen.add(key);
      resolvedFiles.push(abs);
    }
  }

  const gitRootCache = new Map();
  const repoGroups = new Map();
  const outsideFiles = [];
  if (resolvedFiles.length === 0) {
    const root = findGitRootCached(baseDir, gitRootCache);
    if (root) repoGroups.set(root, []);
  } else {
    for (const abs of resolvedFiles) {
      const root = findGitRootCached(path.dirname(abs), gitRootCache);
      if (root && isSubPath(root, abs)) {
        if (!repoGroups.has(root)) repoGroups.set(root, []);
        repoGroups.get(root).push(abs);
      } else {
        outsideFiles.push(abs);
      }
    }
  }

  const sections = [];
  let hasPartialContent = false;
  const multiRepo = repoGroups.size > 1;

  for (const [canonicalGitRoot, inRepoFiles] of repoGroups.entries()) {
    const isWholeRepo = inRepoFiles.length === 0;
    const repoSuffix = multiRepo ? ` (${path.basename(canonicalGitRoot)})` : '';
    const relTargets = inRepoFiles.map((abs) => path.relative(canonicalGitRoot, abs));
    const codeRelTargets = [];
    const codeAbsTargets = [];
    const generatedTargets = [];
    for (let i = 0; i < relTargets.length; i++) {
      if (GENERATED_FILE_RE.test(relTargets[i])) generatedTargets.push(relTargets[i]);
      else {
        codeRelTargets.push(relTargets[i]);
        codeAbsTargets.push(inRepoFiles[i]);
      }
    }

    const hasHead = runGit(['rev-parse', '--verify', 'HEAD'], canonicalGitRoot) !== null;
    const allStatArgs = relTargets.length > 0 ? ['--', ...relTargets] : [];
    const statOut = hasHead
      ? runGit(['diff', 'HEAD', '--stat', ...allStatArgs], canonicalGitRoot)
      : [runGit(['diff', '--cached', '--stat', ...allStatArgs], canonicalGitRoot), runGit(['diff', '--stat', ...allStatArgs], canonicalGitRoot)]
          .filter(Boolean)
          .join('\n');
    if (statOut && statOut.trim()) {
      sections.push(`=== GIT DIFF STAT${repoSuffix} ===\n${statOut.trim()}`);
    }

    const runDiffForCode = isWholeRepo || codeRelTargets.length > 0;
    const diffPathArgs = codeRelTargets.length > 0 ? ['--', ...codeRelTargets] : ['--', '.', ...GENERATED_DIFF_EXCLUDES];
    const fallbackIncluded = new Set();
    let diffText = '';
    if (runDiffForCode) {
      if (hasHead) {
        diffText = runGit(['diff', 'HEAD', '--unified=3', ...diffPathArgs], canonicalGitRoot);
      } else {
        const staged = runGit(['diff', '--cached', '--unified=3', ...diffPathArgs], canonicalGitRoot);
        const unstaged = runGit(['diff', '--unified=3', ...diffPathArgs], canonicalGitRoot);
        const parts = [staged?.trim(), unstaged?.trim()].filter(Boolean);
        if (staged === null || unstaged === null) {
          hasPartialContent = true;
          diffText = parts.length > 0 ? parts.join('\n') : null;
          if (diffText) {
            sections.push(`[Warning${repoSuffix}: partial git diff failure; some staged or unstaged changes may be missing]`);
          }
        } else {
          diffText = parts.join('\n');
        }
      }
      if (diffText && diffText.trim()) {
        sections.push(`=== GIT DIFF${repoSuffix} ===\n${diffText.trim()}`);
      } else if (diffText === null) {
        hasPartialContent = true;
        if (codeAbsTargets.length > 0) {
          for (let i = 0; i < codeRelTargets.length; i++) {
            if (fs.existsSync(codeAbsTargets[i])) {
              const r = readTextFileSafe(codeAbsTargets[i]);
              if (r.truncated) hasPartialContent = true;
              fallbackIncluded.add(codeAbsTargets[i]);
              sections.push(`=== FILE (diff fallback): ${codeRelTargets[i]} ===\n${r.text}`);
            }
          }
        } else {
          sections.push(`[Warning${repoSuffix}: git diff failed or timed out; inspect working tree changes carefully]`);
        }
      }
    }

    if (generatedTargets.length > 0) {
      sections.push(`[Skipped inline diff for generated/lockfile(s): ${generatedTargets.join(', ')}]`);
    }

    if (!isWholeRepo) {
      for (let i = 0; i < codeRelTargets.length; i++) {
        const rel = codeRelTargets[i];
        const abs = codeAbsTargets[i];
        if (fallbackIncluded.has(abs)) continue;
        const isTracked = runGit(['ls-files', '--error-unmatch', '--', rel], canonicalGitRoot) !== null;
        if (!isTracked && fs.existsSync(abs)) {
          const r = readTextFileSafe(abs);
          if (r.truncated) hasPartialContent = true;
          sections.push(`=== NEW FILE (untracked): ${rel} ===\n${r.text}`);
        }
      }
    } else {
      const statusOut = runGit(['status', '--porcelain', '-z', '-uall'], canonicalGitRoot) || '';
      const allUntracked = statusOut
        .split('\0')
        .filter((entry) => entry.startsWith('?? '))
        .map((entry) => entry.slice(3))
        .filter((entry) => entry && !GENERATED_FILE_RE.test(entry));
      const untracked = allUntracked.slice(0, 10);
      if (allUntracked.length > untracked.length) {
        hasPartialContent = true;
        sections.push(`[Note: ${allUntracked.length - untracked.length} additional untracked file(s) omitted: ${allUntracked.slice(10, 20).join(', ')}]`);
      }
      for (const rel of untracked) {
        const abs = path.resolve(canonicalGitRoot, rel);
        if (fs.existsSync(abs)) {
          const r = readTextFileSafe(abs);
          if (r.truncated) hasPartialContent = true;
          sections.push(`=== NEW FILE (untracked): ${rel} ===\n${r.text}`);
        }
      }
    }
  }

  for (const abs of outsideFiles) {
    const rel = path.relative(baseDir, abs);
    const display = rel && rel !== '..' && !rel.startsWith(`..${path.sep}`) && !path.isAbsolute(rel) ? rel : abs;
    if (GENERATED_FILE_RE.test(display)) {
      sections.push(`[Skipped generated/lockfile (no git diff): ${display}]`);
    } else if (fs.existsSync(abs)) {
      const r = readTextFileSafe(abs);
      if (r.truncated) hasPartialContent = true;
      sections.push(`=== FILE (no git diff): ${display} ===\n${r.text}`);
    } else {
      sections.push(`=== FILE (deleted/missing): ${display} ===`);
    }
  }

  const reportedGitRoot = repoGroups.size === 1
    ? [...repoGroups.keys()][0]
    : (findGitRootCached(baseDir, gitRootCache) || null);
  if (sections.length === 0) hasPartialContent = true;
  const fullText = sections.join('\n\n').trim() || 'No diff or edited file content found.';
  if (fullText.length <= maxInlineChars) {
    return { gitRoot: reportedGitRoot, truncated: false, partial: hasPartialContent, patchPath: null, patchCapped: false, text: fullText };
  }

  const { patchPath, patchCapped } = writeRollingPatchFile(fullText);
  const label = patchCapped ? `diff up to ${MAX_PATCH_CHARS} chars saved at` : 'FULL diff saved at';
  const headText = `${fullText.slice(0, maxInlineChars)}\n\n... [truncated ${fullText.length - maxInlineChars} chars; ${label}: ${patchPath}]`;
  return { gitRoot: reportedGitRoot, truncated: true, partial: hasPartialContent, patchPath, patchCapped, text: headText };
}

function buildInlineReviewPrompt(changes) {
  const focusRule = 'Reply in 5-8 lines max: report ONLY concrete bugs, security/data-loss risks, or broken logic/config in the changed lines (skip speculative or minor style nitpicks); if no concrete bug exists, reply `OK — no issues`.';
  if (changes.truncated && changes.patchPath) {
    return [
      'Independent Reviewer: The changes exceeded the inline budget, so a summary + prefix are shown below and the diff is saved in the patch file.',
      `Use \`read_file\` on "${changes.patchPath}" (with StartLine/EndLine or ByteOffset) to inspect the remaining diff; do NOT edit files or run tests.`,
      focusRule,
      '',
      changes.text
    ].join('\n');
  }
  if (changes.partial) {
    return [
      'Independent Reviewer: Changes are shown below (some oversized/omitted files were truncated or no diff was found). Use `read_file` only if you need a truncated/missing file; do NOT edit files or run tests.',
      focusRule,
      '',
      changes.text
    ].join('\n');
  }
  return [
    'Independent Reviewer: ALL changes to review are provided inline below (100% complete).',
    'CRITICAL: Do NOT call any tools (no run_command, no read_file, no search, no MCP). Answer directly in ONE turn using only the inline changes below.',
    focusRule,
    '',
    changes.text
  ].join('\n');
}

function parseRunArgs(argv) {
  const out = { model: '', cwd: process.cwd(), dryRun: false, maxInlineChars: 0, files: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--') break;
    if (a === '--run') continue;
    if (a === '--dry-run') {
      out.dryRun = true;
    } else if (a.startsWith('--model=')) {
      out.model = a.slice('--model='.length);
    } else if (a === '--model' && i + 1 < argv.length) {
      out.model = argv[++i];
    } else if (a.startsWith('--cwd=')) {
      out.cwd = a.slice('--cwd='.length);
    } else if (a === '--cwd' && i + 1 < argv.length) {
      out.cwd = argv[++i];
    } else if (a.startsWith('--max-inline-chars=')) {
      const n = Number(a.slice('--max-inline-chars='.length));
      if (Number.isInteger(n) && n > 0) out.maxInlineChars = n;
    } else if (a === '--max-inline-chars' && i + 1 < argv.length) {
      const n = Number(argv[++i]);
      if (Number.isInteger(n) && n > 0) out.maxInlineChars = n;
    } else if (a === '--files') {
      while (i + 1 < argv.length && !RUN_KNOWN_FLAGS.has(argv[i + 1].split('=')[0])) {
        out.files.push(argv[++i]);
      }
    }
  }
  return out;
}

function extractStreamJsonResult(stdout) {
  if (!stdout || !stdout.trim()) return { text: '', error: '' };
  let finalResponse = null;
  let finalError = '';
  const deltas = [];
  let sawJson = false;

  for (const line of stdout.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      const obj = JSON.parse(trimmed);
      if (!obj || typeof obj !== 'object') continue;
      sawJson = true;
      if (obj.event === 'result' && obj.result) {
        if (typeof obj.result.response === 'string') finalResponse = obj.result.response;
        if (obj.result.error) {
          finalError = typeof obj.result.error === 'string'
            ? obj.result.error
            : JSON.stringify(obj.result.error);
        } else if (String(obj.result.status || '').toUpperCase() === 'ERROR') {
          finalError = 'agy returned result status ERROR';
        }
      } else if (obj.event === 'error' || obj.error) {
        const errVal = obj.error || obj.message || 'agy stream error';
        finalError = typeof errVal === 'string' ? errVal : JSON.stringify(errVal);
      } else if (obj.event === 'step_update' && typeof obj.step_update?.text_delta === 'string') {
        deltas.push(obj.step_update.text_delta);
      }
    } catch {
      // Ignore non-JSON lines.
    }
  }

  if (!sawJson) return { text: stdout, error: '' };
  const text = finalResponse && finalResponse.trim() ? finalResponse : deltas.join('');
  return { text, error: finalError };
}

function quoteCmdArg(arg) {
  if (arg === '') return '""';
  let out = arg;
  if (/[\s()^&|<>%"=,;]/.test(out)) {
    out = `"${out.replace(/"/g, '\\"')}"`;
  }
  return out.replace(/%/g, '"^%"');
}

function trashDirSafe(dirPath) {
  if (!dirPath || !fs.existsSync(dirPath)) return;
  if (process.platform === 'win32') {
    const escaped = dirPath.replace(/'/g, "''");
    const script = [
      'Add-Type -AssemblyName Microsoft.VisualBasic',
      `[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory('${escaped}',` +
      `[Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,` +
      `[Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)`
    ].join('; ');
    spawnSync('powershell', ['-NoProfile', '-NonInteractive', '-Command', script], {
      encoding: 'utf8',
      timeout: 5000,
      stdio: ['ignore', 'ignore', 'ignore'],
      windowsHide: true
    });
    return;
  }
  if (process.platform === 'darwin') {
    const trashDir = path.join(os.homedir(), '.Trash');
    fs.mkdirSync(trashDir, { recursive: true });
    try {
      fs.renameSync(dirPath, path.join(trashDir, `${path.basename(dirPath)}.${Date.now()}`));
    } catch {}
    return;
  }
  for (const [cmd, args] of [['gio', ['trash', dirPath]], ['trash-put', [dirPath]]]) {
    const r = spawnSync(cmd, args, { encoding: 'utf8', timeout: 3000, stdio: ['ignore', 'ignore', 'ignore'] });
    if (r.status === 0) return;
  }
  const xdgTrashFiles = path.join(
    process.env.XDG_DATA_HOME || path.join(os.homedir(), '.local', 'share'),
    'Trash',
    'files'
  );
  try {
    fs.mkdirSync(xdgTrashFiles, { recursive: true });
    fs.renameSync(dirPath, path.join(xdgTrashFiles, `${path.basename(dirPath)}.${Date.now()}`));
  } catch {
    // Ignore EXDEV across tmpfs/home filesystems; patch content was already zeroed out.
  }
}

function hasCommand(bin) {
  try {
    execFileSync('where.exe', [bin], {
      encoding: 'utf8',
      timeout: 2000,
      stdio: ['ignore', 'ignore', 'ignore'],
      windowsHide: true
    });
    return true;
  } catch {
    return false;
  }
}

function resolveAgyLaunch(agyBin, args) {
  if (process.platform !== 'win32') {
    return { cmd: agyBin, args, verbatim: false };
  }
  let resolved = agyBin;
  if (/[\\/]/.test(agyBin) && !/\.(?:exe|cmd|bat|ps1)$/i.test(agyBin)) {
    for (const ext of ['.exe', '.cmd', '.bat', '.ps1']) {
      if (fs.existsSync(`${agyBin}${ext}`)) {
        resolved = `${agyBin}${ext}`;
        break;
      }
    }
  } else if (!/[\\/]/.test(agyBin) && !/\.(?:exe|cmd|bat|ps1)$/i.test(agyBin)) {
    try {
      const out = execFileSync('where.exe', [agyBin], {
        encoding: 'utf8',
        timeout: 3000,
        stdio: ['ignore', 'pipe', 'ignore'],
        windowsHide: true
      });
      const candidates = out.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
      const preferred = candidates.find((c) => /\.exe$/i.test(c))
        || candidates.find((c) => /\.(?:cmd|bat)$/i.test(c))
        || candidates.find((c) => /\.ps1$/i.test(c))
        || candidates[0];
      if (preferred) resolved = preferred;
    } catch {
      // Keep original binary name and let spawnSync report ENOENT if missing.
    }
  }
  if (/\.ps1$/i.test(resolved)) {
    const psBin = hasCommand('pwsh') ? 'pwsh' : 'powershell.exe';
    return {
      cmd: psBin,
      args: ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', resolved, ...args],
      verbatim: false
    };
  }
  if (/\.(?:cmd|bat)$/i.test(resolved)) {
    // Safe: args contain only static CLI flags + validated model ID; user diff goes over stdin.
    const cmdLine = [quoteCmdArg(resolved), ...args.map(quoteCmdArg)].join(' ');
    return {
      cmd: process.env.ComSpec || 'cmd.exe',
      args: ['/d', '/s', '/c', `"${cmdLine}"`],
      verbatim: true
    };
  }
  return { cmd: resolved, args, verbatim: false };
}

function killProcessTree(pid) {
  if (!pid || pid <= 0) return;
  if (process.platform === 'win32') {
    try {
      spawnSync('taskkill', ['/T', '/F', '/PID', String(pid)], {
        stdio: 'ignore',
        timeout: 3000,
        windowsHide: true
      });
    } catch {}
    return;
  }
  try { process.kill(-pid, 'SIGTERM'); } catch {}
  try { process.kill(-pid, 'SIGKILL'); } catch {}
}

function spawnAsyncReview(launch, { cwd, input, timeoutMs }) {
  return new Promise((resolve) => {
    let settled = false;
    let timedOut = false;
    let sawTerminalEvent = false;
    let stdout = '';
    let stdoutCapped = false;
    let tailEvents = '';
    let stderr = '';
    let lineBuf = '';
    let hardTimer = null;
    let resultKillTimer = null;
    const maxBytes = 8 * 1024 * 1024;

    const child = spawn(launch.cmd, launch.args, {
      cwd,
      env: { ...process.env, REVIEW_GATE_SKIP: '1' },
      stdio: ['pipe', 'pipe', 'pipe'],
      shell: false,
      detached: process.platform !== 'win32',
      windowsVerbatimArguments: launch.verbatim,
      windowsHide: true
    });

    const finish = (status, error = null) => {
      if (settled) return;
      settled = true;
      clearTimeout(hardTimer);
      clearTimeout(resultKillTimer);
      try { child.stdout?.destroy(); } catch {}
      try { child.stderr?.destroy(); } catch {}
      const combinedStdout = tailEvents ? `${stdout}\n${tailEvents}` : stdout;
      resolve({ status, stdout: combinedStdout, stderr, error, timedOut, sawTerminalEvent });
    };

    const inspectLine = (rawLine) => {
      const trimmed = rawLine.trim();
      if (!trimmed) return;
      try {
        const obj = JSON.parse(trimmed);
        if (obj && typeof obj === 'object' && (obj.event === 'result' || obj.event === 'error')) {
          if (stdoutCapped && tailEvents.length < 65_536) {
            tailEvents += `${trimmed}\n`;
          }
          sawTerminalEvent = true;
          if (!resultKillTimer) {
            resultKillTimer = setTimeout(() => {
              killProcessTree(child.pid);
              finish(0);
            }, 1500);
            resultKillTimer.unref();
          }
        }
      } catch {
        // Ignore non-JSON lines.
      }
    };

    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (chunk) => {
      if (stdout.length < maxBytes) {
        if (stdout.length + chunk.length > maxBytes) stdoutCapped = true;
        stdout += chunk.slice(0, maxBytes - stdout.length);
      } else {
        stdoutCapped = true;
      }
      lineBuf += chunk;
      let nlIdx;
      while ((nlIdx = lineBuf.indexOf('\n')) !== -1) {
        const line = lineBuf.slice(0, nlIdx);
        lineBuf = lineBuf.slice(nlIdx + 1);
        inspectLine(line);
      }
    });

    child.stderr.setEncoding('utf8');
    child.stderr.on('data', (chunk) => {
      if (stderr.length < maxBytes) {
        stderr += chunk.slice(0, maxBytes - stderr.length);
      }
    });

    child.on('error', (err) => finish(1, err));
    child.on('close', (code) => {
      if (lineBuf.trim()) inspectLine(lineBuf);
      finish(sawTerminalEvent && !timedOut ? 0 : (code ?? 1));
    });

    hardTimer = setTimeout(() => {
      timedOut = true;
      killProcessTree(child.pid);
      finish(1);
    }, timeoutMs);
    hardTimer.unref();

    try {
      child.stdin.on('error', () => {});
      child.stdin.end(input);
    } catch {}
  });
}

async function runCliReview(argv) {
  const opts = parseRunArgs(argv);
  const rawModel = (opts.model || loadConfig().model || '').trim();
  const lower = rawModel.toLowerCase();
  const normalizedTier = lower === 'flash-lite' ? 'flash_lite' : lower;
  if (!rawModel || SUBAGENT_TIERS.has(normalizedTier) || RESERVED_WORDS.has(lower) || !SAFE_MODEL_RE.test(rawModel)) {
    process.stderr.write(`[Review Gate] Invalid exact model for --run: "${rawModel}"\n`);
    process.exitCode = 2;
    return;
  }

  const changes = collectChanges({
    cwd: opts.cwd,
    files: opts.files,
    maxInlineChars: opts.maxInlineChars || MAX_INLINE_CHARS
  });
  const prompt = buildInlineReviewPrompt(changes);

  if (opts.dryRun) {
    process.stdout.write(`${JSON.stringify({
      model: rawModel,
      cwd: path.resolve(opts.cwd),
      gitRoot: changes.gitRoot,
      truncated: changes.truncated,
      patchPath: changes.patchPath,
      promptChars: prompt.length,
      prompt
    })}\n`);
    return;
  }

  const agyBin = process.env.REVIEW_GATE_AGY_BIN || 'agy';
  const streamInput = `${JSON.stringify({ event: 'user', message: { content: prompt } })}\n`;
  const agyArgs = [];
  if (changes.patchPath) {
    agyArgs.push('--add-dir', path.dirname(changes.patchPath));
  }
  agyArgs.push(
    '--model', rawModel,
    '--disable-slash-commands',
    '--print-timeout', '180s',
    '--input-format', 'stream-json',
    '--output-format', 'stream-json',
    '--print='
  );
  const launch = resolveAgyLaunch(agyBin, agyArgs);
  const rawTimeout = Number(process.env.REVIEW_GATE_TIMEOUT_MS);
  const timeoutMs = Number.isInteger(rawTimeout) && rawTimeout > 0 ? rawTimeout : 190_000;

  try {
    const res = await spawnAsyncReview(launch, {
      cwd: opts.cwd,
      input: streamInput,
      timeoutMs
    });

    const parsed = extractStreamJsonResult(res.stdout);
    if (parsed.text) {
      process.stdout.write(parsed.text.endsWith('\n') ? parsed.text : `${parsed.text}\n`);
    }
    if (res.stderr) process.stderr.write(res.stderr);
    if (parsed.error) process.stderr.write(`${parsed.error}\n`);
    if (res.timedOut) {
      process.stderr.write(`[Review Gate] Timed out after ${timeoutMs}ms\n`);
      process.exitCode = 1;
      return;
    }
    if (res.error) {
      process.stderr.write(`[Review Gate] Failed to launch ${agyBin}: ${res.error.message}\n`);
      process.exitCode = 1;
      return;
    }
    const hasAgyStderrError = /\bAGY_ERROR:/m.test(res.stderr || '');
    const emptyOutput = !parsed.text || !parsed.text.trim();
    if (emptyOutput && res.status === 0 && !parsed.error && !hasAgyStderrError) {
      process.stderr.write('[Review Gate] Reviewer returned empty output\n');
    }
    process.exitCode = res.status !== 0
      ? (res.status ?? 1)
      : ((parsed.error || hasAgyStderrError || emptyOutput) ? 1 : 0);
  } finally {
    if (changes.patchPath) {
      try {
        if (fs.existsSync(changes.patchPath)) {
          fs.writeFileSync(changes.patchPath, '', { encoding: 'utf8', mode: 0o600 });
        }
        trashDirSafe(path.dirname(changes.patchPath));
      } catch {
        // Best-effort soft cleanup.
      }
    }
  }
}

function formatShellFileArg(filePath) {
  if (/[$`]/.test(filePath)) {
    return process.platform === 'win32'
      ? `'${filePath.replace(/'/g, "''")}'`
      : `'${filePath.replace(/'/g, "'\\''")}'`;
  }
  return `"${filePath.replace(/"/g, '\\"')}"`;
}

function isCliRunMode(argv) {
  for (const a of argv) {
    if (a === '--') break;
    if (a === '--run') return true;
  }
  return false;
}

async function main() {
  const argv = process.argv.slice(2);
  if (isCliRunMode(argv)) {
    await runCliReview(argv);
    return;
  }

  if (process.env.REVIEW_GATE_SKIP === '1' || process.env.REVIEW_GATE_SKIP === 'true') {
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
      const scriptPath = SELF_SCRIPT.split(path.sep).join('/');
      const fileArgs = analysis.files.map((f) => formatShellFileArg(f)).join(' ');
      const cliHint = fileArgs
        ? `node ${formatShellFileArg(scriptPath)} --run --files ${fileArgs}`
        : `node ${formatShellFileArg(scriptPath)} --run`;
      const invokeHint = SUBAGENT_TIERS.has(config.model)
        ? `Hãy gọi \`invoke_subagent\` với \`TypeName: "research"\`, \`Model: "${config.model}"\` (dùng \`/advisor\` để đổi model hoặc tắt/bật), \`Role: "Independent Reviewer"\` để kiểm tra nhanh:`
        : `Hãy chạy review độc lập 1-lượt bằng đúng model \`${config.model}\` (tự đính kèm \`git diff\` hoặc nội dung file nếu không có git) qua \`run_command\` với lệnh \`${cliHint}\` (đặt \`NotificationTimeoutSeconds: 195\`; sau khi task chạy nền hoàn tất hãy đọc kết quả review, sửa lỗi thật nếu có rồi mới trả lời kết luận cho người dùng; dùng \`/advisor\` để đổi model hoặc tắt/bật):`;
      process.stdout.write(`${JSON.stringify({
        decision: 'continue',
        reason: [
          `[Review Gate] Bạn vừa sửa file${targetHint} nhưng chưa có review độc lập.`,
          invokeHint,
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
