#!/usr/bin/env node
/**
 * AGY HUD - Statusline Script
 * Renders a 2-line (or compact) HUD for Antigravity CLI (agy) using full
 * statusLine stdin JSON payload + transcript.jsonl (/goal, steps, subagents, phase).
 */

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  closeSync,
  existsSync,
  openSync,
  readFileSync,
  readSync,
  realpathSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, join, resolve, sep } from "node:path";

const ANSI = {
  dim: "\x1b[2m",
  bold: "\x1b[1m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  orange: "\x1b[38;5;208m",
  red: "\x1b[31m",
  redBlink: "\x1b[5;31m",
  cyan: "\x1b[36m",
  magenta: "\x1b[35m",
  blue: "\x1b[34m",
  reset: "\x1b[0m",
};

const MAX_TAIL_BYTES = 512 * 1024;
const MAX_HEAD_BYTES = 8 * 1024;
const MAX_JSON_BYTES = 256 * 1024;
const MAX_AGENT_DETAIL_LINES = 5;
const THINKING_RECENCY_MS = 30_000;
const STALE_AGENT_MS = 15 * 60_000;
const STALE_GOAL_MS = 24 * 60 * 60_000;
const RECENT_GOAL_BADGE_MS = 60_000;
const GIT_CACHE_TTL_MS = 10_000;
const AGENT_TOOL_NAMES = new Set(["invoke_subagent", "run_workflow"]);

const DEFAULT_HUD_CONFIG = {
  layout: "two-line",
  showCost: true,
  showQuota: true,
  showReviewGate: true,
  showChecklist: true,
  showGoal: true,
};

function sanitizeSessionId(sessionId) {
  if (typeof sessionId !== "string") return null;
  const trimmed = sessionId.trim();
  if (!trimmed) return null;
  return trimmed.replace(/[^a-zA-Z0-9_-]/g, "_");
}

function toFiniteNumber(val) {
  if (val === null || val === undefined) return null;
  if (typeof val === "string" && !val.trim()) return null;
  const n = Number(val);
  return Number.isFinite(n) ? n : null;
}

function readJsonSafe(filePath) {
  try {
    const stat = statSync(filePath);
    if (!stat.isFile() || stat.size > MAX_JSON_BYTES) return null;
    return JSON.parse(readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function loadHudConfig() {
  const cfgPath = join(homedir(), ".gemini", "antigravity-cli", "hud-config.json");
  const parsed = readJsonSafe(cfgPath);
  if (!parsed || typeof parsed !== "object") return { ...DEFAULT_HUD_CONFIG };
  return {
    layout: parsed.layout === "compact" ? "compact" : "two-line",
    showCost: parsed.showCost !== false,
    showQuota: parsed.showQuota !== false,
    showReviewGate: parsed.showReviewGate !== false,
    showChecklist: parsed.showChecklist !== false,
    showGoal: parsed.showGoal !== false,
  };
}

function readStdin() {
  return new Promise((resolveStdin) => {
    if (process.stdin.isTTY) {
      resolveStdin("");
      return;
    }

    let input = "";
    let settled = false;
    let timer = null;

    const cleanup = () => {
      clearTimeout(timer);
      process.stdin.off("data", onData);
      process.stdin.off("end", onEnd);
      process.stdin.off("error", onError);
      try {
        process.stdin.pause();
        process.stdin.unref?.();
        process.stdin.destroy?.();
      } catch {
        // Ignore stream cleanup errors.
      }
    };

    const finish = (value) => {
      if (settled) return;
      settled = true;
      cleanup();
      resolveStdin(value);
    };

    const armTimer = () => {
      clearTimeout(timer);
      timer = setTimeout(() => finish(input), input.trim() ? 50 : 200);
    };

    const onData = (chunk) => {
      input += chunk;
      if (input.length > 1024 * 1024) {
        finish(input.slice(0, 1024 * 1024));
        return;
      }
      const trimmed = input.trim();
      if (trimmed.startsWith("{") && trimmed.endsWith("}")) {
        try {
          JSON.parse(trimmed);
          finish(input);
          return;
        } catch {
          // Incomplete JSON chunk, wait for more data.
        }
      }
      armTimer();
    };
    const onEnd = () => finish(input);
    const onError = () => finish("");

    process.stdin.setEncoding("utf8");
    process.stdin.on("data", onData);
    process.stdin.on("end", onEnd);
    process.stdin.on("error", onError);
    process.stdin.resume();
    armTimer();
  });
}

function colorizeContext(used) {
  if (used < 50) return ANSI.green;
  if (used < 65) return ANSI.yellow;
  if (used < 80) return ANSI.orange;
  return ANSI.redBlink;
}

function formatCompactTokens(tokens) {
  if (!Number.isFinite(tokens) || tokens <= 0) return null;
  if (tokens >= 1_000_000) {
    const val = tokens / 1_000_000;
    return Number.isInteger(val) ? `${val}M` : `${val.toFixed(1)}M`;
  }
  if (tokens >= 1_000) {
    return `${Math.round(tokens / 1_000)}k`;
  }
  return String(Math.round(tokens));
}

function deriveContextUsage(contextWindow) {
  if (!contextWindow || typeof contextWindow !== "object") {
    return { usedPct: null, currentTokens: null, windowSize: null, cacheHitPct: null };
  }

  const windowSize = Number(contextWindow.context_window_size);
  const validWindowSize = Number.isFinite(windowSize) && windowSize > 0 ? windowSize : null;

  let currentTokens = null;
  let cacheHitPct = null;
  const cu = contextWindow.current_usage;
  if (cu && typeof cu === "object") {
    const inputTok = Number(cu.input_tokens) || 0;
    const cacheCreateTok = Number(cu.cache_creation_input_tokens) || 0;
    const cacheReadTok = Number(cu.cache_read_input_tokens) || 0;
    const sum = inputTok + cacheCreateTok + cacheReadTok;
    if (sum > 0) {
      currentTokens = sum;
      if (cacheReadTok > 0) {
        cacheHitPct = Math.max(0, Math.min(100, Math.round((cacheReadTok / sum) * 100)));
      }
    }
  }

  const usedRaw = contextWindow.used_percentage;
  if (usedRaw !== null && usedRaw !== undefined && String(usedRaw).trim() !== "") {
    const usedNum = Number(usedRaw);
    if (Number.isFinite(usedNum)) {
      return {
        usedPct: Math.max(0, Math.min(100, Math.round(usedNum))),
        currentTokens,
        windowSize: validWindowSize,
        cacheHitPct,
      };
    }
  }

  const remRaw = contextWindow.remaining_percentage;
  if (remRaw !== null && remRaw !== undefined && String(remRaw).trim() !== "") {
    const remNum = Number(remRaw);
    if (Number.isFinite(remNum)) {
      return {
        usedPct: Math.max(0, Math.min(100, Math.round(100 - remNum))),
        currentTokens,
        windowSize: validWindowSize,
        cacheHitPct,
      };
    }
  }

  if (currentTokens != null && validWindowSize != null) {
    return {
      usedPct: Math.max(0, Math.min(100, Math.round((currentTokens / validWindowSize) * 100))),
      currentTokens,
      windowSize: validWindowSize,
      cacheHitPct,
    };
  }

  return { usedPct: null, currentTokens, windowSize: validWindowSize, cacheHitPct };
}

function formatContext(contextWindow) {
  const { usedPct, currentTokens, windowSize, cacheHitPct } = deriveContextUsage(contextWindow);
  if (usedPct == null) return null;

  const filled = Math.floor(usedPct / 10);
  const bar = "█".repeat(filled) + "░".repeat(10 - filled);
  const color = colorizeContext(usedPct);

  const curStr = formatCompactTokens(currentTokens);
  const maxStr = formatCompactTokens(windowSize);
  const tokenSuffix = curStr && maxStr ? ` ${ANSI.dim}(${curStr}/${maxStr})${ANSI.reset}` : "";
  const cacheSuffix = cacheHitPct != null ? ` ${ANSI.dim}⚡${cacheHitPct}%${ANSI.reset}` : "";

  return `${color}${bar} ${usedPct}%${ANSI.reset}${tokenSuffix}${cacheSuffix}`;
}

function getModelTierColor(model) {
  if (!model) return ANSI.cyan;
  const tier = String(model).toLowerCase();
  if (tier.includes("opus") || tier.includes("fable") || tier.includes("pro") || tier.includes("ultra") || tier.includes("neon")) {
    return ANSI.magenta;
  }
  if (tier.includes("sonnet") || tier.includes("hydrogen") || tier.includes("argon") || tier.includes("medium")) {
    return ANSI.yellow;
  }
  if (tier.includes("haiku") || tier.includes("flash") || tier.includes("lite")) {
    return ANSI.green;
  }
  return ANSI.cyan;
}

function shortenModelName(modelId) {
  if (!modelId || typeof modelId !== "string") return "";
  return modelId
    .trim()
    .replace(/^(?:gemini-[0-9.]+-|claude-|gpt-)/i, "")
    .slice(0, 22);
}

function formatDurationCompact(ms) {
  if (!Number.isFinite(ms)) return "0s";
  const totalSec = Math.max(0, Math.floor(ms / 1000));
  if (totalSec < 60) return `${totalSec}s`;
  const minutes = Math.floor(totalSec / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  const rem = minutes % 60;
  return rem === 0 ? `${hours}h` : `${hours}h${rem}m`;
}

function formatResetCompact(seconds) {
  const s = Number(seconds);
  if (!Number.isFinite(s) || s <= 0) return "";
  if (s < 3600) return `${Math.max(1, Math.round(s / 60))}m`;
  if (s < 86400) return `${Math.round(s / 3600)}h`;
  return `${Math.round(s / 86400)}d`;
}

function formatSessionDuration(startTimestamp) {
  if (!startTimestamp) return null;

  const startedAt = typeof startTimestamp === "number" ? startTimestamp : Date.parse(startTimestamp);
  if (!Number.isFinite(startedAt)) return null;

  const minutes = Math.max(0, Math.floor((Date.now() - startedAt) / 60000));
  if (minutes < 60) return `${minutes}m`;

  const hours = Math.floor(minutes / 60);
  const remainderMinutes = minutes % 60;
  if (remainderMinutes === 0) return `${hours}h`;
  return `${hours}h${remainderMinutes}m`;
}

function getOrCreateSessionStart(sessionId) {
  const safeSessionId = sanitizeSessionId(sessionId);
  if (!safeSessionId) return null;

  const cachePath = join(tmpdir(), `agy-hud-session-${safeSessionId}.json`);
  try {
    if (existsSync(cachePath)) {
      const parsed = JSON.parse(readFileSync(cachePath, "utf8"));
      if (Number.isFinite(parsed?.startedAt)) {
        return parsed.startedAt;
      }
    }
  } catch {
    // Ignore cache read error.
  }

  const startedAt = Date.now();
  try {
    writeFileSync(cachePath, JSON.stringify({ session_id: safeSessionId, startedAt }));
  } catch {
    // Best effort.
  }
  return startedAt;
}

function getGoalCachePath(sessionId) {
  const safeSessionId = sanitizeSessionId(sessionId);
  if (!safeSessionId) return null;
  return join(tmpdir(), `agy-hud-goal-${safeSessionId}.json`);
}

function readCachedGoal(sessionId) {
  const cachePath = getGoalCachePath(sessionId);
  if (!cachePath) return null;
  const parsed = readJsonSafe(cachePath);
  if (!parsed || typeof parsed !== "object") return null;
  const now = Date.now();
  const startedAt = Number.isFinite(parsed.startedAt) ? parsed.startedAt : (Number.isFinite(parsed.updatedAt) ? parsed.updatedAt : now);
  if (parsed.active && Number.isFinite(parsed.updatedAt) && now - parsed.updatedAt < STALE_GOAL_MS) {
    return { ...parsed, startedAt };
  }
  if (!parsed.active && Number.isFinite(parsed.completedAt) && now - parsed.completedAt <= RECENT_GOAL_BADGE_MS) {
    return { ...parsed, startedAt };
  }
  return null;
}

function writeCachedGoal(sessionId, goal) {
  const cachePath = getGoalCachePath(sessionId);
  if (!cachePath || !goal) return;
  try {
    writeFileSync(cachePath, JSON.stringify({ ...goal, updatedAt: Date.now() }));
  } catch {
    // Best effort.
  }
}

function findGitHead(startDir) {
  let current = startDir;
  for (let i = 0; i < 10; i++) {
    const dotGit = join(current, ".git");
    if (existsSync(dotGit)) {
      try {
        const stat = statSync(dotGit);
        if (stat.isDirectory()) {
          return { repoRoot: current, headPath: join(dotGit, "HEAD") };
        }
        if (stat.isFile()) {
          const content = readFileSync(dotGit, "utf8");
          const match = content.match(/^gitdir:\s*(.+)$/m);
          if (match) {
            const gitDir = resolve(current, match[1].trim());
            return { repoRoot: current, headPath: join(gitDir, "HEAD") };
          }
        }
      } catch {
        return null;
      }
    }
    const parent = dirname(current);
    if (parent === current) break;
    current = parent;
  }
  return null;
}

function resolveGitBin() {
  if (process.platform === "win32") {
    const directGit = "C:\\Program Files\\Git\\mingw64\\bin\\git.exe";
    if (existsSync(directGit)) return directGit;
  }
  return "git";
}

function getGitInfo(workspacePath, data) {
  if (typeof data?.vcs?.branch === "string" && data.vcs.branch.trim()) {
    return { branch: data.vcs.branch.trim(), dirty: Boolean(data.vcs.dirty) };
  }
  if (!workspacePath || !existsSync(workspacePath)) return null;
  const gitLoc = findGitHead(workspacePath);
  if (!gitLoc || !existsSync(gitLoc.headPath)) return null;

  let branch = null;
  try {
    const head = readFileSync(gitLoc.headPath, "utf8").trim();
    if (head.startsWith("ref:")) {
      branch = head.replace(/^ref:\s*(?:refs\/heads\/)?/, "").trim();
    } else if (head.length >= 7) {
      branch = head.slice(0, 7);
    }
  } catch {
    return null;
  }

  if (!branch) return null;

  const safeRepoKey = createHash("sha1").update(gitLoc.repoRoot).digest("hex").slice(0, 12);
  const cachePath = join(tmpdir(), `agy-hud-git-${safeRepoKey}.json`);
  const now = Date.now();
  let cachedDirty = false;
  try {
    if (existsSync(cachePath)) {
      const cached = JSON.parse(readFileSync(cachePath, "utf8"));
      if (cached && cached.branch === branch && Number.isFinite(cached.ts)) {
        cachedDirty = Boolean(cached.dirty);
        if (now >= cached.ts && now - cached.ts < GIT_CACHE_TTL_MS) {
          return { branch, dirty: cachedDirty };
        }
      }
    }
  } catch {
    // Ignore cache read error.
  }

  let dirty = cachedDirty;
  try {
    const out = execFileSync(
      resolveGitBin(),
      ["--no-optional-locks", "status", "--porcelain", "--untracked-files=no"],
      {
        cwd: gitLoc.repoRoot,
        timeout: 150,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
        windowsHide: true,
      },
    );
    dirty = Boolean(out && out.trim().length > 0);
  } catch {
    // Keep previous cached dirty state and cache the attempt to prevent retry storms under heavy disk I/O.
  }

  try {
    writeFileSync(cachePath, JSON.stringify({ branch, dirty, ts: now }));
  } catch {
    // Best effort.
  }

  return { branch, dirty };
}

function normalizePathForComparison(targetPath) {
  return process.platform === "win32" ? targetPath.toLowerCase() : targetPath;
}

function isPathInside(parentPath, childPath) {
  const normalizedParent = normalizePathForComparison(parentPath);
  const normalizedChild = normalizePathForComparison(childPath);
  return normalizedChild === normalizedParent || normalizedChild.startsWith(`${normalizedParent}${sep}`);
}

function validateTranscriptPath(candidatePath) {
  if (typeof candidatePath !== "string" || !candidatePath.trim()) return null;

  try {
    const resolvedPath = realpathSync(candidatePath);
    const allowedRoot = realpathSync(join(homedir(), ".gemini", "antigravity-cli"));
    const stat = statSync(resolvedPath);
    if (!stat.isFile()) return null;
    return isPathInside(allowedRoot, resolvedPath) ? resolvedPath : null;
  } catch {
    return null;
  }
}

function deriveTranscriptPath(sessionId, data) {
  const direct = validateTranscriptPath(data?.transcript_path);
  if (direct) return direct;

  const safeSessionId = sanitizeSessionId(sessionId);
  if (!safeSessionId) return null;

  return validateTranscriptPath(
    join(homedir(), ".gemini", "antigravity-cli", "brain", safeSessionId, ".system_generated", "logs", "transcript.jsonl"),
  );
}

function readHeadAndTail(filePath) {
  try {
    const { size } = statSync(filePath);
    if (size <= MAX_TAIL_BYTES) {
      return { head: "", tail: readFileSync(filePath, "utf8") };
    }

    const fd = openSync(filePath, "r");
    try {
      const headLen = Math.min(MAX_HEAD_BYTES, size);
      const headBuf = Buffer.alloc(headLen);
      readSync(fd, headBuf, 0, headLen, 0);

      const tailStart = size - MAX_TAIL_BYTES;
      const tailBuf = Buffer.alloc(MAX_TAIL_BYTES);
      readSync(fd, tailBuf, 0, MAX_TAIL_BYTES, tailStart);

      const tailText = tailBuf.toString("utf8");
      const firstNewline = tailText.indexOf("\n");
      return {
        head: headBuf.toString("utf8"),
        tail: firstNewline === -1 ? tailText : tailText.slice(firstNewline + 1),
      };
    } finally {
      closeSync(fd);
    }
  } catch {
    return { head: "", tail: null };
  }
}

function unwrapArgString(value) {
  if (typeof value !== "string") return "";
  const trimmed = value.trim();
  if ((trimmed.startsWith('"') && trimmed.endsWith('"')) || (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
    try {
      const parsed = JSON.parse(trimmed);
      if (typeof parsed === "string") return parsed;
    } catch {
      return trimmed.slice(1, -1);
    }
  }
  return trimmed;
}

function extractSkillFromPath(pathValue) {
  const clean = unwrapArgString(pathValue);
  if (!clean) return null;
  const match = clean.match(/[/\\]skills[/\\]([^/\\]+)[/\\]SKILL\.md$/i);
  return match ? match[1] : null;
}

function parseEventTimestamp(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value > 1e12 ? value : value * 1000;
  }
  if (typeof value === "string" && value.trim()) {
    const parsed = Date.parse(value);
    if (!Number.isNaN(parsed)) return parsed;
  }
  return null;
}

function hasStandaloneGoalMarker(text, markerName) {
  if (!text) return false;
  const stripped = text.replace(/```[\s\S]*?```/g, "").replace(/`[^`]*`/g, "");
  return new RegExp(`<!--\\s*${markerName}\\s*-->`).test(stripped);
}

function parseStepsArg(rawSteps) {
  let list = rawSteps;
  if (typeof list === "string") {
    try {
      list = JSON.parse(list);
    } catch {
      return null;
    }
  }
  if (!Array.isArray(list) || list.length === 0) return null;
  let done = 0;
  let current = null;
  for (const s of list) {
    if (!s || typeof s !== "object") continue;
    const st = String(s.status || "").toLowerCase();
    if (st === "done" || st === "skipped") done += 1;
    else if (st === "in_progress" && !current) {
      current = String(s.title || "").replace(/[\r\n]+/g, " ").trim().slice(0, 32);
    }
  }
  return { done, total: list.length, current };
}

function getDurationColor(durationMs) {
  const minutes = durationMs / 60000;
  if (minutes >= 5) return ANSI.red;
  if (minutes >= 2) return ANSI.yellow;
  return ANSI.green;
}

function formatDurationPadded(durationMs) {
  const seconds = Math.floor(durationMs / 1000);
  const minutes = Math.floor(seconds / 60);
  if (seconds < 10) return "    ";
  if (seconds < 60) return `${seconds}s`.padStart(4);
  return `${minutes}m`.padStart(4);
}

function renderAgentDetailLines(agents) {
  const now = Date.now();
  const running = agents
    .filter((agent) => agent.status === "running" && now - agent.startTime < STALE_AGENT_MS)
    .sort((a, b) => b.startTime - a.startTime);

  if (running.length === 0) return [];

  const detailLines = [];
  const displayCount = Math.min(running.length, MAX_AGENT_DETAIL_LINES);

  running.slice(0, MAX_AGENT_DETAIL_LINES).forEach((agent, index) => {
    const isLast = index === displayCount - 1 && running.length <= MAX_AGENT_DETAIL_LINES;
    const prefix = isLast ? "└─" : "├─";
    const modelColor = getModelTierColor(agent.model);
    const code = (agent.type || "a").charAt(0).toLowerCase();
    const shortName = String(agent.type || "subagent").slice(0, 12).padEnd(12);
    const durationMs = now - agent.startTime;
    const duration = formatDurationPadded(durationMs);
    const durationColor = getDurationColor(durationMs);
    const description = String(agent.description || "...").replace(/[\r\n]+/g, " ").trim().slice(0, 45);

    detailLines.push(
      `${ANSI.dim}${prefix}${ANSI.reset} ${modelColor}${code}${ANSI.reset} ${ANSI.dim}${shortName}${ANSI.reset}${durationColor}${duration}${ANSI.reset}  ${description}`,
    );
  });

  if (running.length > MAX_AGENT_DETAIL_LINES) {
    detailLines.push(`${ANSI.dim}└─ +${running.length - MAX_AGENT_DETAIL_LINES} more agents...${ANSI.reset}`);
  }

  return detailLines;
}

function parseTranscriptSummary(transcriptPath, sessionId) {
  const summary = {
    sessionStartTimestamp: null,
    toolCallCount: 0,
    agentCallCount: 0,
    skillCallCount: 0,
    runningAgentCount: 0,
    lastSkill: null,
    lastModel: null,
    orchestratorPhase: null,
    checklist: null,
    goal: null,
    thinkingActive: false,
    agents: [],
  };

  if (!transcriptPath || !existsSync(transcriptPath)) {
    const cached = readCachedGoal(sessionId);
    if (cached) summary.goal = cached;
    return summary;
  }

  const { head, tail } = readHeadAndTail(transcriptPath);
  if (!tail) {
    const cached = readCachedGoal(sessionId);
    if (cached) summary.goal = cached;
    return summary;
  }

  if (head) {
    const firstLine = head.split(/\r?\n/, 1)[0];
    try {
      const firstEntry = JSON.parse(firstLine);
      summary.sessionStartTimestamp = firstEntry?.created_at || null;
    } catch {
      // Ignore malformed first line.
    }
  }

  let lastThinkingSeen = null;
  const activeSubagents = new Map();
  const pendingSubagents = [];
  let tailGoal = null;
  const seenContStamps = new Set();
  const now = Date.now();

  for (const line of tail.split(/\r?\n/)) {
    if (!line.trim()) continue;

    let entry;
    try {
      entry = JSON.parse(line);
    } catch {
      continue;
    }

    if (!summary.sessionStartTimestamp && entry?.created_at) {
      summary.sessionStartTimestamp = entry.created_at;
    }

    const timestamp = parseEventTimestamp(entry?.created_at);
    const entryContent = typeof entry?.content === "string" ? entry.content : "";

    // Track /goal lifecycle from USER_INPUT, goal stop-hook reminders, and standalone completion markers.
    if (entry?.type === "USER_INPUT" && entryContent.includes("/goal is a [Slash Command]:")) {
      seenContStamps.clear();
      tailGoal = {
        active: true,
        status: "active",
        startedAt: timestamp ?? now,
        continuations: 0,
        completedAt: null,
        hasStartInTail: true,
        contStamps: [],
      };
    } else if (
      (entry?.source === "SYSTEM" || entry?.type === "SYSTEM_MESSAGE" || (entry?.type === "USER_INPUT" && entry?.source !== "USER_EXPLICIT"))
      && entryContent.includes("GOAL_COMPLETE")
      && !entryContent.includes("/goal is a [Slash Command]:")
    ) {
      const existing = tailGoal || readCachedGoal(sessionId);
      if (existing && existing.active) {
        if (!tailGoal) {
          const prevStamps = Array.isArray(existing.contStamps) ? existing.contStamps : [];
          for (const s of prevStamps) seenContStamps.add(s);
          tailGoal = {
            ...existing,
            active: true,
            status: "active",
            continuations: Number.isFinite(existing.continuations) ? existing.continuations : 0,
            hasStartInTail: false,
            contStamps: [...prevStamps],
          };
        }
        const stamp = entry?.step_index != null
          ? `s:${entry.step_index}`
          : `h:${createHash("sha1").update(line).digest("hex").slice(0, 12)}`;
        if (!seenContStamps.has(stamp)) {
          seenContStamps.add(stamp);
          tailGoal.continuations += 1;
          tailGoal.contStamps.push(stamp);
          if (tailGoal.contStamps.length > 500) tailGoal.contStamps.shift();
        }
      }
    }

    if (entry?.type === "PLANNER_RESPONSE") {
      if (typeof entry?.model === "string" && entry.model.trim()) {
        summary.lastModel = entry.model.trim();
      }
      if (typeof entry?.thinking === "string" && entry.thinking.trim() && timestamp != null) {
        lastThinkingSeen = timestamp;
      }
      if (hasStandaloneGoalMarker(entryContent, "GOAL_COMPLETE")) {
        const base = tailGoal || readCachedGoal(sessionId);
        if (base) {
          const doneAt = timestamp ?? (Number.isFinite(base.completedAt) ? base.completedAt : now);
          tailGoal = { ...base, active: false, status: "completed", completedAt: doneAt };
        }
      } else if (hasStandaloneGoalMarker(entryContent, "GOAL_CANCELLED")) {
        const base = tailGoal || readCachedGoal(sessionId);
        if (base) {
          const doneAt = timestamp ?? (Number.isFinite(base.completedAt) ? base.completedAt : now);
          tailGoal = { ...base, active: false, status: "cancelled", completedAt: doneAt };
        }
      }
    }

    if (entry?.source === "SYSTEM" || entry?.type === "SYSTEM_MESSAGE") {
      if (entryContent.includes("Plan mode is off:")) {
        summary.orchestratorPhase = "exec";
      } else if (entryContent.includes("[plan review due]")) {
        summary.orchestratorPhase = "plan";
      }
    }

    if (Array.isArray(entry?.tool_calls)) {
      for (const tc of entry.tool_calls) {
        if (!tc || typeof tc.name !== "string") continue;
        summary.toolCallCount++;

        const args = tc.args && typeof tc.args === "object" ? tc.args : {};

        if (tc.name === "exit_plan_mode") {
          summary.orchestratorPhase = "exec";
        } else if (tc.name === "enter_plan_mode") {
          summary.orchestratorPhase = "plan";
        } else if (tc.name === "update_steps") {
          const parsedSteps = parseStepsArg(args.steps);
          if (parsedSteps) summary.checklist = parsedSteps;
        }

        if (AGENT_TOOL_NAMES.has(tc.name)) {
          summary.agentCallCount++;
          const agentEntry = {
            id: `pending-${summary.agentCallCount}`,
            type: unwrapArgString(args.TypeName) || "subagent",
            model: unwrapArgString(args.Model) || "",
            description: unwrapArgString(args.Role) || unwrapArgString(args.Description) || unwrapArgString(args.Prompt),
            status: "running",
            startTime: timestamp ?? now,
          };
          pendingSubagents.push(agentEntry);
          activeSubagents.set(agentEntry.id, agentEntry);
        } else if (tc.name === "swarm") {
          const action = unwrapArgString(args.action);
          if (action === "add") {
            summary.agentCallCount++;
          } else if (action === "kill") {
            const name = unwrapArgString(args.name);
            if (name) activeSubagents.delete(name);
          }
        } else if (tc.name === "manage_subagents") {
          const action = unwrapArgString(args.Action);
          if (action === "kill_all") {
            activeSubagents.clear();
            pendingSubagents.length = 0;
          } else if (action === "kill") {
            const ids = unwrapArgString(args.ConversationIds);
            for (const key of activeSubagents.keys()) {
              if (ids.includes(key)) activeSubagents.delete(key);
            }
          }
        } else if (tc.name === "read_file") {
          const skillName = extractSkillFromPath(args.Path);
          if (skillName) {
            summary.skillCallCount++;
            summary.lastSkill = skillName;
          }
        }
      }
    }

    // Bind returned conversationId (FIFO) or detect subagent completion / server restart message
    if (entry?.type === "GENERIC" && entryContent) {
      const idMatch = entryContent.match(/conversation[_\s]?id["'\s:=]+([0-9a-f-]{8,})/i);
      if (idMatch) {
        while (pendingSubagents.length > 0) {
          const nextPending = pendingSubagents.shift();
          if (nextPending && activeSubagents.has(nextPending.id)) {
            activeSubagents.delete(nextPending.id);
            nextPending.id = idMatch[1];
            activeSubagents.set(nextPending.id, nextPending);
            break;
          }
        }
      }
    }

    if (entryContent && activeSubagents.size > 0) {
      if (entryContent.includes("All your subagents and background tasks have been stopped")) {
        activeSubagents.clear();
        pendingSubagents.length = 0;
        continue;
      }
      for (const [subId, agent] of activeSubagents.entries()) {
        if (
          !subId.startsWith("pending-") &&
          entryContent.includes(`sender=${subId}`) &&
          (entryContent.includes("<SYSTEM_MESSAGE>") || entry.type === "USER_INPUT")
        ) {
          agent.status = "completed";
          activeSubagents.delete(subId);
        }
      }
    }
  }

  if (tailGoal) {
    const { hasStartInTail: _ignore, ...persistGoal } = tailGoal;
    writeCachedGoal(sessionId, persistGoal);
    summary.goal = persistGoal;
  } else {
    const cached = readCachedGoal(sessionId);
    if (cached) summary.goal = cached;
  }

  const runningAgents = [...activeSubagents.values()].filter(
    (a) => a.status === "running" && now - a.startTime < STALE_AGENT_MS,
  );
  summary.runningAgentCount = runningAgents.length;
  summary.agents = runningAgents;

  if (lastThinkingSeen != null) {
    summary.thinkingActive = now - lastThinkingSeen <= THINKING_RECENCY_MS;
  }

  return summary;
}

function mergeSubagents(payloadSubagents, transcriptAgents) {
  if (!Array.isArray(payloadSubagents)) return transcriptAgents;
  const usedIndices = new Set();
  const runningPayload = payloadSubagents.filter((s) => s && s.status === "running");
  const merged = runningPayload.map((s) => {
    const matchIdx = transcriptAgents.findIndex(
      (ta, idx) =>
        !usedIndices.has(idx) &&
        ((s.role && ta.description && ta.description.includes(s.role)) ||
          (s.name && ta.type && ta.type === s.name)),
    );
    const match = matchIdx >= 0 ? transcriptAgents[matchIdx] : null;
    if (matchIdx >= 0) usedIndices.add(matchIdx);
    return {
      id: match?.id || s.name || s.role || "subagent",
      type: s.name || match?.type || "subagent",
      model: match?.model || "",
      description: s.role || match?.description || s.name || "...",
      status: "running",
      startTime: match?.startTime ?? Date.now(),
    };
  });
  for (let i = 0; i < transcriptAgents.length; i++) {
    if (!usedIndices.has(i) && transcriptAgents[i].type === "run_workflow") {
      merged.push(transcriptAgents[i]);
    }
  }
  return merged;
}

function formatCallCounts(summary) {
  return `🔧 ${summary.toolCallCount} 🤖 ${summary.agentCallCount} ⚡ ${summary.skillCallCount}`;
}

function formatUsd(val) {
  if (!Number.isFinite(val) || val <= 0) return null;
  return val < 0.01 ? `$${val.toFixed(4)}` : `$${val.toFixed(2)}`;
}

function formatCost(costObj) {
  if (!costObj || typeof costObj !== "object") return null;
  const usd = Number(costObj.total_usd ?? costObj.total_cost_usd);
  const main = formatUsd(usd);
  if (!main) return null;
  const prefix = costObj.estimated ? "~" : "";
  const sub = Number(costObj.subagent_usd);
  const subStr = Number.isFinite(sub) && sub > 0 ? ` ${ANSI.dim}(sub:${formatUsd(sub)})${ANSI.reset}` : "";
  return `${ANSI.green}${prefix}${main}${ANSI.reset}${subStr}`;
}

function resolveBucketReset(val) {
  const sec = toFiniteNumber(val?.reset_in_seconds);
  if (sec !== null && sec > 0) return formatResetCompact(sec);
  if (typeof val?.reset_time === "string" && val.reset_time.trim()) {
    const parsed = Date.parse(val.reset_time);
    if (Number.isFinite(parsed) && parsed > Date.now()) {
      return formatResetCompact((parsed - Date.now()) / 1000);
    }
  }
  return "";
}

function formatQuotaPct(label, entry) {
  const color = entry.pct >= 50 ? ANSI.green : entry.pct >= 20 ? ANSI.yellow : ANSI.red;
  const resetSuffix = entry.reset ? `/${entry.reset}` : "";
  return `${color}${label}:${entry.pct}%${resetSuffix}${ANSI.reset}`;
}

function formatQuota(quotaObj, modelName = "") {
  if (!quotaObj || typeof quotaObj !== "object") return null;
  const entries = [];
  for (const [key, val] of Object.entries(quotaObj)) {
    if (!val || typeof val !== "object" || val.disabled) continue;
    const frac = toFiniteNumber(val.remaining_fraction);
    if (frac === null) continue;
    const pct = Math.max(0, Math.min(100, Math.round(frac * 100)));
    entries.push({ key, val, pct, reset: resolveBucketReset(val) });
  }
  if (entries.length === 0) return null;

  const lowerModel = String(modelName || "").toLowerCase();
  let scoped = entries;
  if (/claude|opus|sonnet|haiku|gpt|\bo[134]\b/i.test(lowerModel)) {
    const thirdParty = entries.filter((e) => /^(?:3p|claude|gpt)/i.test(e.key));
    if (thirdParty.length > 0) scoped = thirdParty;
  } else if (/gemini|orchestrator|neon|argon|carbon|hydrogen|flash|pro/i.test(lowerModel)) {
    const geminiOnly = entries.filter((e) => /^gemini/i.test(e.key));
    if (geminiOnly.length > 0) scoped = geminiOnly;
  }

  let fiveHour = null;
  let weekly = null;
  let lowest = null;
  for (const e of scoped) {
    if (!lowest || e.pct < lowest.pct) lowest = e;
    const win = typeof e.val.window === "string" ? e.val.window.toLowerCase() : "";
    if (win === "5h" || /5h|five[_-]?hour/i.test(e.key)) {
      if (!fiveHour || e.pct < fiveHour.pct) fiveHour = e;
    } else if (win === "weekly" || /weekly|7d|seven[_-]?day/i.test(e.key)) {
      if (!weekly || e.pct < weekly.pct) weekly = e;
    }
  }

  if (fiveHour || weekly) {
    const parts = [];
    if (fiveHour) parts.push(formatQuotaPct("5h", fiveHour));
    if (weekly) parts.push(formatQuotaPct("7d", weekly));
    return parts.join(" ");
  }

  return lowest ? formatQuotaPct("Q", lowest) : null;
}

function formatAgentState(data) {
  if (data?.tool_confirmation_pending === true) {
    return `${ANSI.redBlink}⚠ WAIT y/n${ANSI.reset}`;
  }
  const st = typeof data?.agent_state === "string" ? data.agent_state.toLowerCase() : "";
  switch (st) {
    case "working":
      return `${ANSI.cyan}● WORK${ANSI.reset}`;
    case "tool_use":
      return `${ANSI.yellow}● TOOL${ANSI.reset}`;
    case "reviewing":
      return `${ANSI.magenta}● REVIEW${ANSI.reset}`;
    case "idle":
      return `${ANSI.green}● IDLE${ANSI.reset}`;
    case "initializing":
      return `${ANSI.dim}◌ INIT${ANSI.reset}`;
    case "authenticating":
      return `${ANSI.yellow}🔑 AUTH${ANSI.reset}`;
    case "error":
      return `${ANSI.red}✖ ERR${ANSI.reset}`;
    default:
      return null;
  }
}

function resolveActiveMode(data) {
  for (const raw of [data?.cycle_mode, data?.permission_mode]) {
    if (typeof raw !== "string") continue;
    const trimmed = raw.trim();
    if (trimmed && trimmed.toLowerCase() !== "default") return trimmed;
  }
  return null;
}

function formatCycleMode(mode) {
  if (!mode) return null;
  const lower = String(mode).trim().toLowerCase();
  if (!lower || lower === "default") return null;
  if (lower === "plan") return `${ANSI.magenta}plan${ANSI.reset}`;
  if (lower === "auto") return `${ANSI.green}auto${ANSI.reset}`;
  if (lower === "accept-edits") return `${ANSI.yellow}accept-edits${ANSI.reset}`;
  return `${ANSI.magenta}${mode}${ANSI.reset}`;
}

function formatGoalBadge(goal) {
  if (!goal) return null;
  const now = Date.now();
  if (goal.active) {
    const elapsed = formatDurationCompact(now - goal.startedAt);
    const cont = goal.continuations > 0 ? ` #${goal.continuations}` : "";
    return `${ANSI.bold}${ANSI.magenta}🎯 GOAL ${elapsed}${cont}${ANSI.reset}`;
  }
  if (goal.completedAt && now - goal.completedAt <= RECENT_GOAL_BADGE_MS) {
    return goal.status === "cancelled"
      ? `${ANSI.dim}✕ GOAL${ANSI.reset}`
      : `${ANSI.green}✓ GOAL${ANSI.reset}`;
  }
  return null;
}

function readReviewGateBadge() {
  const cfgPath = join(homedir(), ".gemini", "antigravity-cli", "review-gate.json");
  const cfg = readJsonSafe(cfgPath);
  if (!cfg || typeof cfg !== "object") return null;
  if (cfg.enabled === false) return `${ANSI.dim}RG:off${ANSI.reset}`;
  const model = typeof cfg.model === "string" ? cfg.model.trim() : "";
  if (!model || model === "inherit") return null;
  return `${ANSI.dim}RG:${shortenModelName(model)}${ANSI.reset}`;
}

function formatWorkspacePath(workspacePath, terminalWidth) {
  if (!workspacePath) return "";
  if (Number.isFinite(terminalWidth) && terminalWidth > 0 && terminalWidth < 120 && workspacePath.length > 36) {
    const base = basename(workspacePath);
    const parent = basename(dirname(workspacePath));
    return parent ? `…/${parent}/${base}` : `…/${base}`;
  }
  return workspacePath;
}

function renderFromPayload(data) {
  const cfg = loadHudConfig();
  const modelName = data?.model?.display_name || data?.model?.id || "Antigravity";
  const workspacePath = data?.workspace?.current_dir || data?.cwd || process.cwd();
  const sessionId = data?.session_id || data?.conversation_id || null;

  const transcriptSummary = parseTranscriptSummary(deriveTranscriptPath(sessionId, data), sessionId);
  const sessionStart = transcriptSummary.sessionStartTimestamp || getOrCreateSessionStart(sessionId);
  const sessionDuration = formatSessionDuration(sessionStart);
  const gitInfo = getGitInfo(workspacePath, data);
  const contextText = formatContext(data?.context_window);
  const costText = cfg.showCost ? formatCost(data?.cost) : null;
  const quotaText = cfg.showQuota ? formatQuota(data?.quota, modelName) : null;
  const activeMode = resolveActiveMode(data);
  const modeBadge = formatCycleMode(activeMode);
  const stateBadge = formatAgentState(data);
  const goalBadge = cfg.showGoal ? formatGoalBadge(transcriptSummary.goal) : null;
  const rgBadge = cfg.showReviewGate ? readReviewGateBadge() : null;

  const runningAgents = mergeSubagents(data?.subagents, transcriptSummary.agents);
  const runningCount = runningAgents.length;

  const modelColor = getModelTierColor(modelName);
  let modelLabel = modelName;
  if (/orchestrator/i.test(modelName) && transcriptSummary.lastModel) {
    const isPlanCycle = activeMode?.toLowerCase() === "plan";
    const phaseTag = (transcriptSummary.orchestratorPhase === "plan" || (!transcriptSummary.orchestratorPhase && isPlanCycle))
      ? "Plan"
      : "Exec";
    modelLabel += ` ${ANSI.dim}[${phaseTag}:${shortenModelName(transcriptSummary.lastModel)}]${ANSI.reset}`;
  } else if (data?.model?.effort && !modelName.toLowerCase().includes(String(data.model.effort).toLowerCase())) {
    modelLabel += ` ${ANSI.dim}[${data.model.effort}]${ANSI.reset}`;
  }

  const displayWorkspace = formatWorkspacePath(workspacePath, Number(data?.terminal_width));
  const gitBadge = gitInfo
    ? ` ${ANSI.cyan}(${gitInfo.branch}${gitInfo.dirty ? `${ANSI.yellow}*${ANSI.cyan}` : ""})${ANSI.reset}`
    : "";

  const line1Parts = [];
  if (stateBadge) line1Parts.push(stateBadge);
  line1Parts.push(`${ANSI.bold}${modelColor}${modelLabel}${ANSI.reset}`);
  if (data?.agent?.name && data.agent.name !== "default") {
    line1Parts.push(`${ANSI.magenta}@${data.agent.name}${ANSI.reset}`);
  }
  if (modeBadge) line1Parts.push(modeBadge);
  if (data?.sandbox?.enabled === true) line1Parts.push(`${ANSI.green}🔒SBX${ANSI.reset}`);
  if (data?.vim?.mode) line1Parts.push(`${ANSI.blue}VIM:${data.vim.mode}${ANSI.reset}`);
  line1Parts.push(`${ANSI.dim}${displayWorkspace}${ANSI.reset}${gitBadge}`);
  if (goalBadge) line1Parts.push(goalBadge);
  if (rgBadge) line1Parts.push(rgBadge);

  const line2Parts = [];
  if (contextText) line2Parts.push(contextText);
  if (costText) line2Parts.push(costText);
  if (quotaText) line2Parts.push(quotaText);
  if (sessionDuration) line2Parts.push(`${ANSI.cyan}session:${sessionDuration}${ANSI.reset}`);
  if (transcriptSummary.thinkingActive) line2Parts.push(`${ANSI.cyan}thinking${ANSI.reset}`);
  if (transcriptSummary.lastSkill) line2Parts.push(`${ANSI.cyan}skill:${transcriptSummary.lastSkill}${ANSI.reset}`);

  if (cfg.showChecklist && transcriptSummary.checklist) {
    const { done, total, current } = transcriptSummary.checklist;
    const curLabel = current ? `: ${current}` : "";
    line2Parts.push(`${ANSI.cyan}☑ ${done}/${total}${curLabel}${ANSI.reset}`);
  }

  if (Number(data?.task_count) > 0) line2Parts.push(`${ANSI.yellow}tasks:${data.task_count}${ANSI.reset}`);
  if (Number(data?.artifact_count) > 0) line2Parts.push(`${ANSI.dim}📄${data.artifact_count}${ANSI.reset}`);
  if (Number(data?.pending_input_count) > 0) line2Parts.push(`${ANSI.yellow}📥${data.pending_input_count}${ANSI.reset}`);

  line2Parts.push(`${ANSI.cyan}agents:${runningCount}${ANSI.reset}`);
  line2Parts.push(`${ANSI.dim}${formatCallCounts(transcriptSummary)}${ANSI.reset}`);

  const sepPipe = ` ${ANSI.dim}│${ANSI.reset} `;
  let header;
  if (cfg.layout === "compact") {
    header = `${line1Parts.join(sepPipe)} ${ANSI.dim}|${ANSI.reset} ${line2Parts.join(` ${ANSI.dim}|${ANSI.reset} `)}`;
  } else {
    header = `${line1Parts.join(sepPipe)}\n${line2Parts.join(` ${ANSI.dim}|${ANSI.reset} `)}`;
  }

  const detailLines = renderAgentDetailLines(runningAgents);
  return detailLines.length > 0 ? `${header}\n${detailLines.join("\n")}` : header;
}

async function main() {
  const stdin = await readStdin();
  try {
    process.stdin.unref?.();
  } catch {
    // Ignore.
  }

  if (stdin.trim()) {
    try {
      const data = JSON.parse(stdin);
      const rendered = renderFromPayload(data);
      if (rendered) {
        process.stdout.write(rendered);
        return;
      }
    } catch {
      // Fall through to safe fallback line.
    }
  }

  process.stdout.write(renderFromPayload({}));
}

process.stdout.on("error", () => {
  process.exit(0);
});
process.on("uncaughtException", () => {
  process.exit(0);
});
process.on("unhandledRejection", () => {
  process.exit(0);
});

main();
