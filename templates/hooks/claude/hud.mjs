#!/usr/bin/env node
/**
 * OMC HUD - Statusline Script
 * Renders a compact HUD from Claude Code statusline stdin payload.
 * Falls back to the OMC HUD runtime when stdin data is unavailable.
 */

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
import { join, sep } from "node:path";
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
  reset: "\x1b[0m",
};

const AUTO_COMPACT_BUFFER_PCT = 16.5;
const MAX_TAIL_BYTES = 512 * 1024;
const MAX_JSON_BYTES = 1024 * 1024;
const MAX_AGENT_DETAIL_LINES = 5;
const THINKING_RECENCY_MS = 30_000;
const THINKING_PART_TYPES = new Set(["thinking", "reasoning"]);
const AGENT_TOOL_NAMES = new Set(["Task", "proxy_Task", "Agent"]);
const SKILL_TOOL_NAMES = new Set(["Skill", "proxy_Skill"]);

function readJson(filePath) {
  try {
    const stat = statSync(filePath);
    if (!stat.isFile() || stat.size > MAX_JSON_BYTES) return null;
    return JSON.parse(readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
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
      process.stdin.pause();
    };

    const finish = (value) => {
      if (settled) return;
      settled = true;
      cleanup();
      resolve(value);
    };

    const armTimer = () => {
      clearTimeout(timer);
      timer = setTimeout(() => finish(input), 250);
    };

    const onData = (chunk) => {
      input += chunk;
      if (input.length > 1024 * 1024) {
        finish(input.slice(0, 1024 * 1024));
        return;
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

function formatContext(remainingPercentage) {
  const used = calculateUsedContext(remainingPercentage);
  const filled = Math.floor(used / 10);
  const bar = "█".repeat(filled) + "░".repeat(10 - filled);
  const color = colorizeContext(used);
  return `${color}${bar} ${used}%${ANSI.reset}`;
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

  const startedAt = Date.parse(startTimestamp);
  if (Number.isNaN(startedAt)) return null;

  const minutes = Math.max(0, Math.floor((Date.now() - startedAt) / 60000));
  if (minutes < 60) return `${minutes}m`;

  const hours = Math.floor(minutes / 60);
  const remainderMinutes = minutes % 60;
  if (remainderMinutes === 0) return `${hours}h`;
  return `${hours}h${remainderMinutes}m`;
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

function deriveActiveMode(workspacePath, sessionId) {
  const modes = ["ralph", "autopilot", "ultrawork", "team", "ultraqa"];

  for (const mode of modes) {
    const state = readSessionState(workspacePath, sessionId, `${mode}-state.json`);
    if (state?.active) {
      return mode;
    }
  }

  return null;
}

function deriveSkillName(workspacePath, sessionId) {
  const activeMode = deriveActiveMode(workspacePath, sessionId);
  if (activeMode) return activeMode;

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

function readTailText(filePath) {
  try {
    const { size } = statSync(filePath);
    if (size <= MAX_TAIL_BYTES) {
      return readFileSync(filePath, "utf8");
    }

    const start = size - MAX_TAIL_BYTES;
    const fd = openSync(filePath, "r");
    const buffer = Buffer.alloc(MAX_TAIL_BYTES);

    try {
      readSync(fd, buffer, 0, MAX_TAIL_BYTES, start);
    } finally {
      closeSync(fd);
    }

    const text = buffer.toString("utf8");
    const firstNewline = text.indexOf("\n");
    return firstNewline === -1 ? text : text.slice(firstNewline + 1);
  } catch {
    return null;
  }
}

function getModelTierColor(model) {
  if (!model) return ANSI.cyan;
  const tier = String(model).toLowerCase();
  if (tier.includes("opus")) return ANSI.magenta;
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

function renderAgentDetailLines(agents) {
  const running = [...agents]
    .filter((agent) => agent.status === "running")
    .sort((a, b) => b.startTime - a.startTime);

  if (running.length === 0) return [];

  const detailLines = [];
  const now = Date.now();
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
    toolCallCount: 0,
    agentCallCount: 0,
    skillCallCount: 0,
    runningAgentCount: 0,
    lastSkill: null,
    thinkingActive: false,
    agents: [],
  };

  if (!transcriptPath || !existsSync(transcriptPath)) {
    return summary;
  }

  const raw = readTailText(transcriptPath);
  if (!raw) {
    return summary;
  }

  const agentMap = new Map();
  const backgroundAgentMap = new Map();
  let lastThinkingSeen = null;

  for (const line of raw.split(/\r?\n/)) {
    if (!line.trim()) continue;

    try {
      const entry = JSON.parse(line);
      const timestamp = parseEventTimestamp(entry?.timestamp);
      const content = entry?.message?.content;
      if (!Array.isArray(content)) continue;

      for (const block of content) {
        if (THINKING_PART_TYPES.has(block?.type) && timestamp != null) {
          lastThinkingSeen = timestamp;
        }

        if (block?.type === "tool_use" && block.id && typeof block.name === "string") {
          summary.toolCallCount++;

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
          }
        }

        if (block?.type === "tool_result" && block.tool_use_id) {
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

  const runningAgents = [...agentMap.values()].filter((agent) => agent.status === "running");
  summary.runningAgentCount = runningAgents.length;
  summary.agents = runningAgents;
  if (lastThinkingSeen != null) {
    summary.thinkingActive = Date.now() - lastThinkingSeen <= THINKING_RECENCY_MS;
  }

  return summary;
}

function formatCallCounts(summary) {
  return `🔧 ${summary.toolCallCount} 🤖 ${summary.agentCallCount} ⚡ ${summary.skillCallCount}`;
}

function deriveDisplayModel(data, stdinCache) {
  return data?.model?.display_name || stdinCache?.model?.display_name || null;
}

function deriveWorkspacePath(data, stdinCache) {
  return data?.workspace?.current_dir
    || data?.cwd
    || stdinCache?.workspace?.current_dir
    || stdinCache?.cwd
    || null;
}

function deriveRemainingPercentage(data, stdinCache) {
  const value = data?.context_window?.remaining_percentage
    ?? stdinCache?.context_window?.remaining_percentage
    ?? null;

  if (typeof value === "string" && !value.trim()) {
    return null;
  }

  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : null;
}

function renderFromPayload(data) {
  const directWorkspacePath = data?.workspace?.current_dir || data?.cwd || null;
  const sessionMeta = deriveSessionMeta(directWorkspacePath);
  const stdinCache = sessionMeta.stdinCache;
  const workspacePath = deriveWorkspacePath(data, stdinCache);
  if (!workspacePath) return null;

  const resolvedSessionMeta = workspacePath === directWorkspacePath
    ? sessionMeta
    : deriveSessionMeta(workspacePath);
  const activeStdinCache = resolvedSessionMeta.stdinCache;
  const model = deriveDisplayModel(data, activeStdinCache);
  const remainingPercentage = deriveRemainingPercentage(data, activeStdinCache);

  if (!model || remainingPercentage == null) {
    return null;
  }

  const sessionId = data?.session_id || resolvedSessionMeta.sessionId;
  const sessionDuration = formatSessionDuration(resolvedSessionMeta.sessionStartTimestamp);
  const transcriptSummary = parseTranscriptSummary(
    deriveTranscriptPath(workspacePath, sessionId, activeStdinCache, data),
  );
  const skillName = transcriptSummary.lastSkill || deriveSkillName(workspacePath, sessionId);
  const used = calculateUsedContext(remainingPercentage);
  writeContextBridge(sessionId, remainingPercentage, used);

  const leadingParts = [
    `${ANSI.bold}${model}${ANSI.reset}`,
    `${ANSI.dim}${workspacePath}${ANSI.reset}`,
  ];
  const trailingParts = [];

  if (transcriptSummary.thinkingActive) {
    trailingParts.push(`${ANSI.cyan}thinking${ANSI.reset}`);
  }

  if (sessionDuration) {
    trailingParts.push(`${ANSI.cyan}session:${sessionDuration}${ANSI.reset}`);
  }

  if (skillName) {
    trailingParts.push(`${ANSI.cyan}skill:${skillName}${ANSI.reset}`);
  }

  trailingParts.push(formatContext(remainingPercentage));
  trailingParts.push(`${ANSI.cyan}agents:${transcriptSummary.runningAgentCount}${ANSI.reset}`);
  trailingParts.push(`${ANSI.dim}${formatCallCounts(transcriptSummary)}${ANSI.reset}`);

  const leading = leadingParts.join(` ${ANSI.dim}│${ANSI.reset} `);
  const header = trailingParts.length === 0
    ? leading
    : `${leading} ${ANSI.dim}|${ANSI.reset} ${trailingParts.join(` ${ANSI.dim}|${ANSI.reset} `)}`;
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

process.stdout.on("error", (error) => {
  if (error?.code === "EPIPE") {
    process.exit(0);
  }
  throw error;
});

main();
