#!/usr/bin/env node
/**
 * OMC HUD - Statusline Script
 * Renders a 2-line (or compact) HUD from Claude Code statusline stdin payload
 * + transcript.jsonl (TodoWrite/TaskCreate/TaskUpdate, subagents, skills) + OMC state.
 * Falls back to the OMC HUD runtime when stdin data is unavailable.
 */

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  closeSync,
  existsSync,
  openSync,
  readFileSync,
  readSync,
  readdirSync,
  realpathSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, join, resolve, sep } from "node:path";
import { pathToFileURL } from "node:url";

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

const AUTO_COMPACT_BUFFER_PCT = 16.5;
const MAX_TAIL_BYTES = 512 * 1024;
const MAX_HEAD_BYTES = 8 * 1024;
const MAX_JSON_BYTES = 1024 * 1024;
const MAX_AGENT_DETAIL_LINES = 5;
const THINKING_RECENCY_MS = 30_000;
const STALE_AGENT_MS = 15 * 60_000;
const GIT_CACHE_TTL_MS = 10_000;
const THINKING_PART_TYPES = new Set(["thinking", "reasoning"]);
const AGENT_TOOL_NAMES = new Set(["Task", "proxy_Task", "Agent"]);
const SKILL_TOOL_NAMES = new Set(["Skill", "proxy_Skill"]);

const DEFAULT_HUD_CONFIG = {
  layout: "two-line",
  showCost: true,
  showQuota: true,
  showReviewGate: true,
  showChecklist: true,
  showMode: true,
};

function toFiniteNumber(val) {
  if (val === null || val === undefined) return null;
  if (typeof val === "string" && !val.trim()) return null;
  const n = Number(val);
  return Number.isFinite(n) ? n : null;
}

function readJson(filePath) {
  try {
    const stat = statSync(filePath);
    if (!stat.isFile() || stat.size > MAX_JSON_BYTES) return null;
    return JSON.parse(readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function loadHudConfig() {
  const configDir = process.env.CLAUDE_CONFIG_DIR || join(homedir(), ".claude");
  const parsed = readJson(join(configDir, "hud-config.json"));
  if (!parsed || typeof parsed !== "object") return { ...DEFAULT_HUD_CONFIG };
  return {
    layout: parsed.layout === "compact" ? "compact" : "two-line",
    showCost: parsed.showCost !== false,
    showQuota: parsed.showQuota !== false,
    showReviewGate: parsed.showReviewGate !== false,
    showChecklist: parsed.showChecklist !== false,
    showMode: parsed.showMode !== false,
  };
}

function sanitizeSessionId(sessionId) {
  if (typeof sessionId !== "string") return null;
  const trimmed = sessionId.trim();
  if (!trimmed) return null;
  return trimmed.replace(/[^a-zA-Z0-9_-]/g, "_");
}

function readStdin() {
  return new Promise((resolve) => {
    if (process.stdin.isTTY) {
      resolve("");
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
      resolve(value);
    };

    const armTimer = () => {
      clearTimeout(timer);
      timer = setTimeout(() => finish(input), input.trim() ? 50 : 250);
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

function calculateUsedContext(remainingPercentage) {
  const usableRemaining = Math.max(
    0,
    ((remainingPercentage - AUTO_COMPACT_BUFFER_PCT) / (100 - AUTO_COMPACT_BUFFER_PCT)) * 100,
  );
  return Math.max(0, Math.min(100, Math.round(100 - usableRemaining)));
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

function deriveContextDetails(data, stdinCache) {
  const cw = data?.context_window || stdinCache?.context_window;
  if (!cw || typeof cw !== "object") {
    return { currentTokens: null, windowSize: null, cacheHitPct: null };
  }

  const ws = Number(cw.context_window_size);
  const windowSize = Number.isFinite(ws) && ws > 0 ? ws : null;
  let currentTokens = null;
  let cacheHitPct = null;

  const cu = cw.current_usage;
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
  return { currentTokens, windowSize, cacheHitPct };
}

function formatContext(remainingPercentage, details) {
  const used = calculateUsedContext(remainingPercentage);
  const filled = Math.floor(used / 10);
  const bar = "█".repeat(filled) + "░".repeat(10 - filled);
  const color = colorizeContext(used);

  const curStr = formatCompactTokens(details?.currentTokens);
  const maxStr = formatCompactTokens(details?.windowSize);
  const tokenSuffix = curStr && maxStr ? ` ${ANSI.dim}(${curStr}/${maxStr})${ANSI.reset}` : "";
  const cacheSuffix = details?.cacheHitPct != null ? ` ${ANSI.dim}⚡${details.cacheHitPct}%${ANSI.reset}` : "";

  return `${color}${bar} ${used}%${ANSI.reset}${tokenSuffix}${cacheSuffix}`;
}

function writeContextBridge(sessionId, remainingPercentage, used) {
  if (remainingPercentage == null) return;

  const safeSessionId = sanitizeSessionId(sessionId);
  if (!safeSessionId) return;

  try {
    const bridgePath = join(tmpdir(), `claude-ctx-${safeSessionId}.json`);
    const bridgeData = JSON.stringify({
      session_id: safeSessionId,
      remaining_percentage: remainingPercentage,
      used_pct: used,
      timestamp: Math.floor(Date.now() / 1000),
    });
    writeFileSync(bridgePath, bridgeData);
  } catch {
    // Best effort only.
  }
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

  const cachePath = join(tmpdir(), `claude-hud-session-${safeSessionId}.json`);
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
  const cachePath = join(tmpdir(), `claude-hud-git-${safeRepoKey}.json`);
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

function extractSkillFromPath(pathValue) {
  if (typeof pathValue !== "string" || !pathValue.trim()) return null;
  const match = pathValue.trim().match(/[/\\]skills[/\\]([^/\\]+)[/\\]SKILL\.md$/i);
  return match ? match[1] : null;
}

function normalizeSkillName(skillName) {
  if (typeof skillName !== "string" || !skillName.trim()) return null;
  const parts = skillName.trim().split(":");
  return parts[parts.length - 1] || skillName.trim();
}

function normalizePathForComparison(targetPath) {
  return process.platform === "win32" ? targetPath.toLowerCase() : targetPath;
}

function resolveWorkspacePath(workspacePath) {
  if (typeof workspacePath !== "string" || !workspacePath.trim()) return null;

  try {
    const resolvedPath = realpathSync(workspacePath);
    const stat = statSync(resolvedPath);
    return stat.isDirectory() ? resolvedPath : null;
  } catch {
    return null;
  }
}

function readSessionState(workspacePath, sessionId, fileName) {
  const resolvedWorkspacePath = resolveWorkspacePath(workspacePath);
  if (!resolvedWorkspacePath) return null;

  const baseStateDir = join(resolvedWorkspacePath, ".omc", "state");
  const safeSessionId = sanitizeSessionId(sessionId);
  const candidates = [];

  if (safeSessionId) {
    candidates.push(join(baseStateDir, "sessions", safeSessionId, fileName));
  }

  candidates.push(join(baseStateDir, fileName));

  for (const candidate of candidates) {
    const state = readJson(candidate);
    if (state) return state;
  }

  return null;
}

function deriveSessionMeta(workspacePath) {
  const resolvedWorkspacePath = resolveWorkspacePath(workspacePath);
  if (!resolvedWorkspacePath) {
    return {
      sessionId: null,
      sessionStartTimestamp: null,
      stdinCache: null,
    };
  }

  const hudState = readJson(join(resolvedWorkspacePath, ".omc", "state", "hud-state.json"));
  const stdinCache = readJson(join(resolvedWorkspacePath, ".omc", "state", "hud-stdin-cache.json"));
  return {
    sessionId: sanitizeSessionId(hudState?.sessionId || stdinCache?.session_id || null),
    sessionStartTimestamp: hudState?.sessionStartTimestamp || null,
    stdinCache,
  };
}

function deriveActiveModeState(workspacePath, sessionId) {
  const modes = ["ralph", "autopilot", "ultrawork", "team", "ultraqa"];

  for (const mode of modes) {
    const state = readSessionState(workspacePath, sessionId, `${mode}-state.json`);
    if (state?.active) {
      return {
        mode,
        iteration: toFiniteNumber(state.iteration),
        maxIterations: toFiniteNumber(state.max_iterations ?? state.maxIterations),
      };
    }
  }

  return null;
}

function deriveSkillName(workspacePath, sessionId) {
  const state = readSessionState(workspacePath, sessionId, "skill-active-state.json");
  if (state?.active && typeof state.skill_name === "string" && state.skill_name.trim()) {
    return normalizeSkillName(state.skill_name);
  }

  return null;
}

function sanitizeProjectDir(projectDir) {
  if (typeof projectDir !== "string" || !projectDir.trim()) return null;
  return projectDir.replace(/[^a-zA-Z0-9]/g, "-");
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
    const allowedRoot = realpathSync(join(homedir(), ".claude", "projects"));
    const stat = statSync(resolvedPath);
    if (!stat.isFile()) return null;
    return isPathInside(allowedRoot, resolvedPath) ? resolvedPath : null;
  } catch {
    return null;
  }
}

function deriveTranscriptPath(workspacePath, sessionId, stdinCache, data) {
  const directTranscriptPath = validateTranscriptPath(data?.transcript_path)
    || validateTranscriptPath(stdinCache?.transcript_path);
  if (directTranscriptPath) return directTranscriptPath;

  if (!sessionId) return null;

  const sanitizedProjectDir = sanitizeProjectDir(workspacePath);
  const safeSessionId = sanitizeSessionId(sessionId);
  if (!sanitizedProjectDir || !safeSessionId) return null;

  return validateTranscriptPath(
    join(
      homedir(),
      ".claude",
      "projects",
      sanitizedProjectDir,
      `${safeSessionId}.jsonl`,
    ),
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

      const start = size - MAX_TAIL_BYTES;
      const buffer = Buffer.alloc(MAX_TAIL_BYTES);
      readSync(fd, buffer, 0, MAX_TAIL_BYTES, start);

      const text = buffer.toString("utf8");
      const firstNewline = text.indexOf("\n");
      return {
        head: headBuf.toString("utf8"),
        tail: firstNewline === -1 ? text : text.slice(firstNewline + 1),
      };
    } finally {
      closeSync(fd);
    }
  } catch {
    return { head: "", tail: null };
  }
}

function getModelTierColor(model) {
  if (!model) return ANSI.cyan;
  const tier = String(model).toLowerCase();
  if (tier.includes("opus") || tier.includes("fable")) return ANSI.magenta;
  if (tier.includes("sonnet")) return ANSI.yellow;
  if (tier.includes("haiku")) return ANSI.green;
  return ANSI.cyan;
}

function getDurationColor(durationMs) {
  const minutes = durationMs / 60000;
  if (minutes >= 5) return ANSI.red;
  if (minutes >= 2) return ANSI.yellow;
  return ANSI.green;
}

function getAgentCode(agentType, model) {
  const shortName = String(agentType || "unknown").split(":").pop() || "unknown";
  const codeMap = {
    explore: "e",
    analyst: "T",
    planner: "P",
    architect: "A",
    debugger: "g",
    executor: "x",
    verifier: "V",
    "style-reviewer": "y",
    "api-reviewer": "i",
    "security-reviewer": "K",
    "performance-reviewer": "o",
    "code-reviewer": "R",
    "dependency-expert": "l",
    "test-engineer": "t",
    "quality-strategist": "Qs",
    designer: "d",
    writer: "w",
    "qa-tester": "q",
    scientist: "s",
    "git-master": "m",
    "product-manager": "Pm",
    "ux-researcher": "u",
    "information-architect": "Ia",
    "product-analyst": "a",
    critic: "C",
    vision: "v",
    "document-specialist": "D",
    researcher: "r",
  };
  let code = codeMap[shortName] || shortName.charAt(0).toUpperCase();

  if (model) {
    const tier = String(model).toLowerCase();
    if (code.length === 1) {
      code = tier.includes("opus") ? code.toUpperCase() : code.toLowerCase();
    } else {
      const first = tier.includes("opus") ? code[0].toUpperCase() : code[0].toLowerCase();
      code = first + code.slice(1);
    }
  }

  return code;
}

function getShortAgentName(agentType) {
  const name = String(agentType || "unknown").split(":").pop() || "unknown";
  const abbrevs = {
    executor: "exec",
    "deep-executor": "exec",
    debugger: "debug",
    verifier: "verify",
    "style-reviewer": "style",
    "quality-reviewer": "review",
    "api-reviewer": "api-rev",
    "security-reviewer": "sec",
    "performance-reviewer": "perf",
    "code-reviewer": "review",
    "dependency-expert": "dep-exp",
    "document-specialist": "doc-spec",
    "test-engineer": "test-eng",
    "quality-strategist": "qs",
    "build-fixer": "debug",
    designer: "design",
    "qa-tester": "qa",
    scientist: "sci",
    "git-master": "git",
    "product-manager": "pm",
    "ux-researcher": "uxr",
    "information-architect": "ia",
    "product-analyst": "pa",
    researcher: "dep-exp",
  };
  return abbrevs[name] || name;
}

function formatDurationPadded(durationMs) {
  const seconds = Math.floor(durationMs / 1000);
  const minutes = Math.floor(seconds / 60);

  if (seconds < 10) return "    ";
  if (seconds < 60) return `${seconds}s`.padStart(4);
  return `${minutes}m`.padStart(4);
}

function truncateDescription(description, maxWidth = 45) {
  if (typeof description !== "string" || !description.trim()) return "...";
  return description.replace(/[\r\n]+/g, " ").trim().slice(0, maxWidth);
}

function extractTextContent(content) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .map((item) => (typeof item?.text === "string" ? item.text : ""))
    .filter(Boolean)
    .join("\n");
}

function parseEventTimestamp(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value > 1e12 ? value : value * 1000;
  }

  if (typeof value === "string" && value.trim()) {
    const numeric = Number(value);
    if (Number.isFinite(numeric)) {
      return numeric > 1e12 ? numeric : numeric * 1000;
    }

    const parsed = Date.parse(value);
    if (!Number.isNaN(parsed)) return parsed;
  }

  return null;
}

function extractBackgroundAgentId(content) {
  const text = extractTextContent(content);
  const match = text.match(/agentId:\s*([a-zA-Z0-9_-]+)/);
  return match ? match[1] : null;
}

function parseTaskOutputResult(content) {
  const text = extractTextContent(content);
  const taskIdMatch = text.match(/<task_id>([^<]+)<\/task_id>/)
    || text.match(/["']task_id["']\s*[:=]\s*["']([^"']+)["']/)
    || text.match(/["']taskId["']\s*[:=]\s*["']([^"']+)["']/);
  const statusMatch = text.match(/<status>([^<]+)<\/status>/)
    || text.match(/["']status["']\s*[:=]\s*["']([^"']+)["']/);
  if (taskIdMatch && statusMatch) {
    return { taskId: taskIdMatch[1], status: statusMatch[1] };
  }
  return null;
}

function summarizeTodos(todos) {
  if (!Array.isArray(todos) || todos.length === 0) return null;
  let done = 0;
  let current = null;
  for (const t of todos) {
    if (!t || typeof t !== "object") continue;
    const st = String(t.status || "").toLowerCase();
    if (st === "completed") done += 1;
    else if (st === "in_progress" && !current) {
      current = String(t.activeForm || t.content || t.subject || "")
        .replace(/[\r\n]+/g, " ")
        .trim()
        .slice(0, 32);
    }
  }
  return { done, total: todos.length, current };
}

function renderAgentDetailLines(agents) {
  const now = Date.now();
  const running = [...agents]
    .filter((agent) => agent.status === "running" && now - agent.startTime < STALE_AGENT_MS)
    .sort((a, b) => b.startTime - a.startTime);

  if (running.length === 0) return [];

  const detailLines = [];
  const displayCount = Math.min(running.length, MAX_AGENT_DETAIL_LINES);

  running.slice(0, MAX_AGENT_DETAIL_LINES).forEach((agent, index) => {
    const isLast = index === displayCount - 1 && running.length <= MAX_AGENT_DETAIL_LINES;
    const prefix = isLast ? "└─" : "├─";
    const code = getAgentCode(agent.type, agent.model);
    const modelColor = getModelTierColor(agent.model);
    const shortName = getShortAgentName(agent.type).padEnd(12);
    const durationMs = now - agent.startTime;
    const duration = formatDurationPadded(durationMs);
    const durationColor = getDurationColor(durationMs);
    const description = truncateDescription(agent.description, 45);

    detailLines.push(
      `${ANSI.dim}${prefix}${ANSI.reset} ${modelColor}${code}${ANSI.reset} ${ANSI.dim}${shortName}${ANSI.reset}${durationColor}${duration}${ANSI.reset}  ${description}`,
    );
  });

  if (running.length > MAX_AGENT_DETAIL_LINES) {
    detailLines.push(`${ANSI.dim}└─ +${running.length - MAX_AGENT_DETAIL_LINES} more agents...${ANSI.reset}`);
  }

  return detailLines;
}

function parseTranscriptSummary(transcriptPath) {
  const summary = {
    sessionStartTimestamp: null,
    toolCallCount: 0,
    agentCallCount: 0,
    skillCallCount: 0,
    runningAgentCount: 0,
    lastSkill: null,
    checklist: null,
    thinkingActive: false,
    agents: [],
  };

  if (!transcriptPath || !existsSync(transcriptPath)) {
    return summary;
  }

  const { head, tail } = readHeadAndTail(transcriptPath);
  if (!tail) {
    return summary;
  }

  if (head) {
    for (const hLine of head.split(/\r?\n/)) {
      if (!hLine.trim()) continue;
      try {
        const ts = parseEventTimestamp(JSON.parse(hLine)?.timestamp);
        if (ts != null) {
          summary.sessionStartTimestamp = ts;
          break;
        }
      } catch {
        // Ignore malformed or partial boundary line.
      }
    }
  }

  const agentMap = new Map();
  const backgroundAgentMap = new Map();
  const taskMap = new Map();
  const pendingTaskCreates = new Map();
  let taskSeq = 0;
  let lastThinkingSeen = null;

  for (const line of tail.split(/\r?\n/)) {
    if (!line.trim()) continue;

    try {
      const entry = JSON.parse(line);
      const timestamp = parseEventTimestamp(entry?.timestamp);
      if (!summary.sessionStartTimestamp && timestamp != null) {
        summary.sessionStartTimestamp = timestamp;
      }
      const content = entry?.message?.content;
      if (!Array.isArray(content)) continue;

      for (const block of content) {
        if (THINKING_PART_TYPES.has(block?.type) && timestamp != null) {
          lastThinkingSeen = timestamp;
        }

        if (block?.type === "tool_use" && block.id && typeof block.name === "string") {
          summary.toolCallCount++;

          if (block.name === "TodoWrite") {
            if (Array.isArray(block?.input?.todos)) {
              summary.checklist = summarizeTodos(block.input.todos);
            }
          } else if (block.name === "TaskCreate") {
            pendingTaskCreates.set(block.id, {
              subject: block?.input?.subject || "",
              activeForm: block?.input?.activeForm || "",
              status: "pending",
            });
          } else if (block.name === "TaskUpdate") {
            const tid = String(block?.input?.taskId || "").trim();
            if (tid) {
              if (block?.input?.status === "deleted") {
                taskMap.delete(tid);
              } else {
                const existing = taskMap.get(tid) || { subject: "", activeForm: "", status: "pending" };
                if (block?.input?.status) existing.status = block.input.status;
                if (block?.input?.subject) existing.subject = block.input.subject;
                if (block?.input?.activeForm) existing.activeForm = block.input.activeForm;
                taskMap.set(tid, existing);
              }
              summary.checklist = summarizeTodos([...taskMap.values()]);
            }
          }

          if (AGENT_TOOL_NAMES.has(block.name)) {
            summary.agentCallCount++;
            agentMap.set(block.id, {
              id: block.id,
              type: block?.input?.subagent_type || "unknown",
              model: block?.input?.model,
              description: block?.input?.description,
              status: "running",
              startTime: timestamp ?? Date.now(),
            });
          }

          if (SKILL_TOOL_NAMES.has(block.name)) {
            summary.skillCallCount++;
            summary.lastSkill = normalizeSkillName(block?.input?.skill) || summary.lastSkill;
          } else if (block.name === "Read" || block.name === "read_file") {
            const skillFromPath = extractSkillFromPath(block?.input?.file_path || block?.input?.Path);
            if (skillFromPath) {
              summary.skillCallCount++;
              summary.lastSkill = skillFromPath;
            }
          }
        }

        if (block?.type === "tool_result" && block.tool_use_id) {
          const pendingTask = pendingTaskCreates.get(block.tool_use_id);
          if (pendingTask) {
            pendingTaskCreates.delete(block.tool_use_id);
            if (!block.is_error) {
              const resText = extractTextContent(block.content);
              const idMatch = resText.match(/Task\s*#([a-zA-Z0-9_-]+)/i)
                || resText.match(/["'](?:taskId|task_id|id)["']\s*[:=]\s*["']?([a-zA-Z0-9_-]+)/i);
              taskSeq += 1;
              const resolvedId = idMatch ? idMatch[1] : String(taskSeq);
              taskMap.set(resolvedId, pendingTask);
              summary.checklist = summarizeTodos([...taskMap.values()]);
            }
          }

          const agent = agentMap.get(block.tool_use_id);
          if (agent) {
            const blockText = extractTextContent(block.content);
            const isBackgroundLaunch = blockText.includes("Async agent launched");

            if (isBackgroundLaunch) {
              const backgroundAgentId = extractBackgroundAgentId(block.content);
              if (backgroundAgentId) {
                backgroundAgentMap.set(backgroundAgentId, block.tool_use_id);
              }
            } else {
              agent.status = "completed";
            }
          }

          const taskOutput = parseTaskOutputResult(block.content);
          if (taskOutput?.status === "completed") {
            const toolUseId = backgroundAgentMap.get(taskOutput.taskId);
            const backgroundAgent = toolUseId ? agentMap.get(toolUseId) : null;
            if (backgroundAgent) {
              backgroundAgent.status = "completed";
            }
          }
        }
      }
    } catch {
      // Skip malformed lines.
    }
  }

  const now = Date.now();
  const runningAgents = [...agentMap.values()].filter(
    (agent) => agent.status === "running" && now - agent.startTime < STALE_AGENT_MS,
  );
  summary.runningAgentCount = runningAgents.length;
  summary.agents = runningAgents;
  if (lastThinkingSeen != null) {
    summary.thinkingActive = now - lastThinkingSeen <= THINKING_RECENCY_MS;
  }

  return summary;
}

function formatCallCounts(summary) {
  return `🔧 ${summary.toolCallCount} 🤖 ${summary.agentCallCount} ⚡ ${summary.skillCallCount}`;
}

function formatCostAndLines(costObj) {
  if (!costObj || typeof costObj !== "object") return null;
  const parts = [];
  const usd = Number(costObj.total_cost_usd ?? costObj.total_usd);
  if (Number.isFinite(usd) && usd > 0) {
    parts.push(`${ANSI.green}${usd < 0.01 ? `$${usd.toFixed(4)}` : `$${usd.toFixed(2)}`}${ANSI.reset}`);
  }
  const added = Number(costObj.total_lines_added) || 0;
  const removed = Number(costObj.total_lines_removed) || 0;
  if (added > 0 || removed > 0) {
    parts.push(`${ANSI.green}+${added}${ANSI.reset}${ANSI.dim}/${ANSI.reset}${ANSI.red}-${removed}${ANSI.reset}`);
  }
  return parts.length > 0 ? parts.join(" ") : null;
}

function formatResetShort(val) {
  const sec = toFiniteNumber(val?.reset_in_seconds);
  const ts = sec !== null && sec > 0
    ? sec
    : (() => {
        const raw = val?.resets_at ?? val?.reset_time;
        const n = toFiniteNumber(raw);
        if (n !== null) {
          const ms = n > 1e12 ? n : n * 1000;
          return ms > Date.now() ? (ms - Date.now()) / 1000 : 0;
        }
        if (typeof raw === "string" && raw.trim()) {
          const parsed = Date.parse(raw);
          return Number.isFinite(parsed) && parsed > Date.now() ? (parsed - Date.now()) / 1000 : 0;
        }
        return 0;
      })();
  if (ts <= 0) return "";
  if (ts < 3600) return `/${Math.max(1, Math.round(ts / 60))}m`;
  if (ts < 86400) return `/${Math.round(ts / 3600)}h`;
  return `/${Math.round(ts / 86400)}d`;
}

function formatRateLimits(rateLimits, quota) {
  if (rateLimits && typeof rateLimits === "object") {
    const parts = [];
    for (const [label, bucket] of [["5h", rateLimits.five_hour], ["7d", rateLimits.seven_day]]) {
      if (!bucket || typeof bucket !== "object") continue;
      const used = toFiniteNumber(bucket.used_percentage);
      if (used === null) continue;
      const rem = Math.max(0, Math.min(100, Math.round(100 - used)));
      const color = rem >= 50 ? ANSI.green : rem >= 20 ? ANSI.yellow : ANSI.red;
      parts.push(`${color}${label}:${rem}%${formatResetShort(bucket)}${ANSI.reset}`);
    }
    if (parts.length > 0) return parts.join(" ");
  }
  if (quota && typeof quota === "object") {
    let fiveHour = null;
    let weekly = null;
    let lowest = null;
    for (const [key, val] of Object.entries(quota)) {
      if (!val || typeof val !== "object" || val.disabled) continue;
      const frac = toFiniteNumber(val.remaining_fraction);
      if (frac === null) continue;
      const pct = Math.max(0, Math.min(100, Math.round(frac * 100)));
      const item = { pct, reset: formatResetShort(val) };
      if (!lowest || pct < lowest.pct) lowest = item;
      const win = typeof val.window === "string" ? val.window.toLowerCase() : "";
      if (win === "5h" || /5h|five[_-]?hour/i.test(key)) {
        if (!fiveHour || pct < fiveHour.pct) fiveHour = item;
      } else if (win === "weekly" || /weekly|7d|seven[_-]?day/i.test(key)) {
        if (!weekly || pct < weekly.pct) weekly = item;
      }
    }
    if (fiveHour || weekly) {
      const parts = [];
      for (const [label, item] of [["5h", fiveHour], ["7d", weekly]]) {
        if (!item) continue;
        const color = item.pct >= 50 ? ANSI.green : item.pct >= 20 ? ANSI.yellow : ANSI.red;
        parts.push(`${color}${label}:${item.pct}%${item.reset}${ANSI.reset}`);
      }
      return parts.join(" ");
    }
    if (lowest) {
      const color = lowest.pct >= 50 ? ANSI.green : lowest.pct >= 20 ? ANSI.yellow : ANSI.red;
      return `${color}Q:${lowest.pct}%${lowest.reset}${ANSI.reset}`;
    }
  }
  return null;
}

function formatPermissionMode(mode) {
  if (!mode) return null;
  const trimmed = String(mode).trim();
  const lower = trimmed.toLowerCase();
  if (!lower || lower === "default") return null;
  if (lower === "plan") return `${ANSI.magenta}plan${ANSI.reset}`;
  if (lower === "bypasspermissions" || lower === "dontask") return `${ANSI.yellow}${trimmed}${ANSI.reset}`;
  if (lower === "acceptedits") return `${ANSI.green}acceptEdits${ANSI.reset}`;
  return `${ANSI.cyan}${trimmed}${ANSI.reset}`;
}

function readReviewGateBadge() {
  const configDir = process.env.CLAUDE_CONFIG_DIR || join(homedir(), ".claude");
  const cfg = readJson(join(configDir, "review-gate.json"));
  if (!cfg || typeof cfg !== "object") return null;
  if (cfg.enabled === false) return `${ANSI.dim}RG:off${ANSI.reset}`;
  const model = typeof cfg.model === "string" ? cfg.model.trim() : "";
  if (!model || model === "inherit") return null;
  return `${ANSI.dim}RG:${model.slice(0, 18)}${ANSI.reset}`;
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

function deriveDisplayModel(data, stdinCache) {
  return data?.model?.display_name
    || data?.model?.id
    || stdinCache?.model?.display_name
    || stdinCache?.model?.id
    || null;
}

function deriveWorkspacePath(data, stdinCache) {
  return data?.workspace?.current_dir
    || data?.cwd
    || stdinCache?.workspace?.current_dir
    || stdinCache?.cwd
    || null;
}

function parseFinitePercentage(raw) {
  if (raw === null || raw === undefined) return null;
  if (typeof raw === "string" && !raw.trim()) return null;
  const numeric = Number(raw);
  return Number.isFinite(numeric) ? Math.max(0, Math.min(100, numeric)) : null;
}

function deriveRemainingPercentage(data, stdinCache) {
  const cw = data?.context_window || stdinCache?.context_window;
  if (!cw || typeof cw !== "object") return null;

  const directRemaining = parseFinitePercentage(cw.remaining_percentage);
  if (directRemaining != null) return directRemaining;

  const usedPct = parseFinitePercentage(cw.used_percentage);
  if (usedPct != null) return Math.max(0, Math.min(100, 100 - usedPct));

  const windowSize = Number(cw.context_window_size);
  const cu = cw.current_usage;
  if (Number.isFinite(windowSize) && windowSize > 0 && cu && typeof cu === "object") {
    const sum =
      (Number(cu.input_tokens) || 0) +
      (Number(cu.cache_creation_input_tokens) || 0) +
      (Number(cu.cache_read_input_tokens) || 0);
    if (sum > 0) {
      return Math.max(0, Math.min(100, 100 - (sum / windowSize) * 100));
    }
  }

  return null;
}

function renderFromPayload(data) {
  if (!data || typeof data !== "object") return null;

  const cfg = loadHudConfig();
  const directWorkspacePath = data?.workspace?.current_dir || data?.cwd || null;
  const sessionMeta = deriveSessionMeta(directWorkspacePath);
  const stdinCache = sessionMeta.stdinCache;
  const workspacePath = deriveWorkspacePath(data, stdinCache) || process.cwd();

  const resolvedSessionMeta = workspacePath === directWorkspacePath
    ? sessionMeta
    : deriveSessionMeta(workspacePath);
  const activeStdinCache = resolvedSessionMeta.stdinCache;
  const model = deriveDisplayModel(data, activeStdinCache);

  if (!model) {
    return null;
  }

  const remainingPercentage = deriveRemainingPercentage(data, activeStdinCache);
  const contextDetails = deriveContextDetails(data, activeStdinCache);
  const sessionId = data?.session_id || resolvedSessionMeta.sessionId;
  const transcriptSummary = parseTranscriptSummary(
    deriveTranscriptPath(workspacePath, sessionId, activeStdinCache, data),
  );
  const sessionStart = resolvedSessionMeta.sessionStartTimestamp
    || transcriptSummary.sessionStartTimestamp
    || getOrCreateSessionStart(sessionId);
  const sessionDuration = formatSessionDuration(sessionStart);
  const gitInfo = getGitInfo(workspacePath, data);
  const activeMode = cfg.showMode ? deriveActiveModeState(workspacePath, sessionId) : null;
  const skillName = transcriptSummary.lastSkill || deriveSkillName(workspacePath, sessionId);
  const modeBadge = formatPermissionMode(data?.permission_mode) || formatPermissionMode(data?.cycle_mode);
  const costText = cfg.showCost ? formatCostAndLines(data?.cost) : null;
  const rateText = cfg.showQuota ? formatRateLimits(data?.rate_limits, data?.quota) : null;
  const rgBadge = cfg.showReviewGate ? readReviewGateBadge() : null;

  const modelColor = getModelTierColor(model);
  const displayWorkspace = formatWorkspacePath(workspacePath, Number(data?.terminal_width));
  const gitBadge = gitInfo
    ? ` ${ANSI.cyan}(${gitInfo.branch}${gitInfo.dirty ? `${ANSI.yellow}*${ANSI.cyan}` : ""})${ANSI.reset}`
    : "";

  const line1Parts = [`${ANSI.bold}${modelColor}${model}${ANSI.reset}`];
  if (data?.agent?.name && data.agent.name !== "default") {
    line1Parts.push(`${ANSI.magenta}@${data.agent.name}${ANSI.reset}`);
  }
  if (modeBadge) line1Parts.push(modeBadge);
  if (data?.output_style?.name && data.output_style.name !== "default") {
    line1Parts.push(`${ANSI.dim}style:${data.output_style.name}${ANSI.reset}`);
  }
  if (data?.vim?.mode) line1Parts.push(`${ANSI.blue}VIM:${data.vim.mode}${ANSI.reset}`);
  line1Parts.push(`${ANSI.dim}${displayWorkspace}${ANSI.reset}${gitBadge}`);

  if (activeMode) {
    const iterSuffix = activeMode.iteration != null
      ? ` #${activeMode.iteration}${activeMode.maxIterations != null ? `/${activeMode.maxIterations}` : ""}`
      : "";
    line1Parts.push(`${ANSI.bold}${ANSI.magenta}🎯 ${activeMode.mode.toUpperCase()}${iterSuffix}${ANSI.reset}`);
  }
  if (rgBadge) line1Parts.push(rgBadge);

  const line2Parts = [];
  if (remainingPercentage != null) {
    const used = calculateUsedContext(remainingPercentage);
    writeContextBridge(sessionId, remainingPercentage, used);
    line2Parts.push(formatContext(remainingPercentage, contextDetails));
  }
  if (costText) line2Parts.push(costText);
  if (rateText) line2Parts.push(rateText);
  if (sessionDuration) line2Parts.push(`${ANSI.cyan}session:${sessionDuration}${ANSI.reset}`);
  if (transcriptSummary.thinkingActive) line2Parts.push(`${ANSI.cyan}thinking${ANSI.reset}`);
  if (skillName) line2Parts.push(`${ANSI.cyan}skill:${skillName}${ANSI.reset}`);

  if (cfg.showChecklist && transcriptSummary.checklist) {
    const { done, total, current } = transcriptSummary.checklist;
    const curLabel = current ? `: ${current}` : "";
    line2Parts.push(`${ANSI.cyan}☑ ${done}/${total}${curLabel}${ANSI.reset}`);
  }

  line2Parts.push(`${ANSI.cyan}agents:${transcriptSummary.runningAgentCount}${ANSI.reset}`);
  line2Parts.push(`${ANSI.dim}${formatCallCounts(transcriptSummary)}${ANSI.reset}`);

  const sepPipe = ` ${ANSI.dim}│${ANSI.reset} `;
  let header;
  if (cfg.layout === "compact") {
    header = `${line1Parts.join(sepPipe)} ${ANSI.dim}|${ANSI.reset} ${line2Parts.join(` ${ANSI.dim}|${ANSI.reset} `)}`;
  } else {
    header = `${line1Parts.join(sepPipe)}\n${line2Parts.join(` ${ANSI.dim}|${ANSI.reset} `)}`;
  }

  const detailLines = renderAgentDetailLines(transcriptSummary.agents);
  return detailLines.length > 0 ? `${header}\n${detailLines.join("\n")}` : header;
}

async function fallbackToOmnHud() {
  const home = homedir();
  let pluginCacheDir = null;

  if (process.env.OMC_DEV === "1") {
    const devPaths = [
      join(home, "Workspace/oh-my-claudecode/dist/hud/index.js"),
      join(home, "workspace/oh-my-claudecode/dist/hud/index.js"),
      join(home, "projects/oh-my-claudecode/dist/hud/index.js"),
    ];

    for (const devPath of devPaths) {
      if (existsSync(devPath)) {
        try {
          await import(pathToFileURL(devPath).href);
          return;
        } catch {}
      }
    }
  }

  const configDir = process.env.CLAUDE_CONFIG_DIR || join(home, ".claude");
  const pluginCacheBase = join(configDir, "plugins", "cache", "omc", "oh-my-claudecode");

  if (existsSync(pluginCacheBase)) {
    try {
      const versions = readdirSync(pluginCacheBase);
      const builtVersions = versions.filter((version) =>
        existsSync(join(pluginCacheBase, version, "dist/hud/index.js")),
      );

      if (builtVersions.length > 0) {
        const latestVersion = builtVersions
          .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))
          .reverse()[0];
        pluginCacheDir = join(pluginCacheBase, latestVersion);
        await import(pathToFileURL(join(pluginCacheDir, "dist/hud/index.js")).href);
        return;
      }
    } catch {}
  }

  try {
    await import("oh-my-claudecode/dist/hud/index.js");
    return;
  } catch {}

  if (pluginCacheDir && existsSync(pluginCacheDir)) {
    const distDir = join(pluginCacheDir, "dist");
    if (!existsSync(distDir)) {
      console.log(`[OMC HUD] Plugin installed but not built. Run: cd "${pluginCacheDir}" && npm install && npm run build`);
    } else {
      console.log(`[OMC HUD] Plugin dist/ exists but HUD not found. Run: cd "${pluginCacheDir}" && npm run build`);
    }
  } else if (existsSync(pluginCacheBase)) {
    console.log("[OMC HUD] Plugin cache found but no built versions. Run: /oh-my-claudecode:omc-setup");
  } else {
    console.log("[OMC HUD] Plugin not installed. Run: /oh-my-claudecode:omc-setup");
  }
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
      // Fall through to OMC HUD runtime.
    }
  }

  await fallbackToOmnHud();
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
