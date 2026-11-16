#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __filename = fs.realpathSync(fileURLToPath(import.meta.url));
const __dirname = path.dirname(__filename);

const nodeMajor = Number(process.versions.node.split('.')[0]);
if (Number.isFinite(nodeMajor) && nodeMajor < 20) {
  throw new Error(`Node.js >= 20 is required (found ${process.versions.node}).`);
}

/**
 * 19 built-in Agent Team IDE roles with recommended default models and extra skills.
 * Built-in roleId defaults (se-*) are injected automatically by the IDE, so extraSkills
 * stays empty except for `grilling` on orchestrator and planner.
 */
export const STANDARD_AGENTS = [
  { id: 'orchestrator', name: 'Orchestrator', roleId: 'orchestrator', model: 'gemini-4-hydrogen-medium', extraSkills: ['grilling'] },
  { id: 'research', name: 'Research', roleId: 'research', model: 'gemini-4-argon-medium', extraSkills: [] },
  { id: 'coder', name: 'Coder', roleId: 'coder', model: 'gemini-4-hydrogen-low', extraSkills: [] },
  { id: 'tester', name: 'Tester', roleId: 'tester', model: 'gemini-4-hydrogen-medium', extraSkills: [] },
  { id: 'reviewer', name: 'Reviewer', roleId: 'reviewer', model: 'gemini-4-carbon-medium', extraSkills: [] },
  { id: 'planner', name: 'Planner', roleId: 'planner', model: 'gemini-4-argon-medium', extraSkills: ['grilling'] },
  { id: 'architect', name: 'Architect', roleId: 'architect', model: 'gemini-4-argon-medium', extraSkills: [] },
  { id: 'critic', name: 'Critic', roleId: 'critic', model: 'gemini-4-carbon-medium', extraSkills: [] },
  { id: 'debugger', name: 'Debugger', roleId: 'debugger', model: 'gemini-4-hydrogen-medium', extraSkills: [] },
  { id: 'frontend', name: 'Frontend Engineer', roleId: 'frontend', model: 'gemini-4-hydrogen-medium', extraSkills: [] },
  { id: 'backend', name: 'Backend Engineer', roleId: 'backend', model: 'gemini-4-hydrogen-medium', extraSkills: [] },
  { id: 'security', name: 'Security Reviewer', roleId: 'security', model: 'gemini-4-carbon-medium', extraSkills: [] },
  { id: 'accessibility', name: 'Accessibility Auditor', roleId: 'accessibility', model: 'gemini-4-hydrogen-medium', extraSkills: [] },
  { id: 'performance', name: 'Performance Engineer', roleId: 'performance', model: 'gemini-4-hydrogen-medium', extraSkills: [] },
  { id: 'devops', name: 'Release Engineer', roleId: 'devops', model: 'gemini-4-hydrogen-medium', extraSkills: [] },
  { id: 'docs', name: 'Docs', roleId: 'docs', model: 'gemini-4-hydrogen-low', extraSkills: [] },
  { id: 'git', name: 'Git', roleId: 'git', model: 'gemini-4-hydrogen-low', extraSkills: [] },
  { id: 'db', name: 'DB', roleId: 'db', model: 'gemini-4-argon-medium', extraSkills: [] },
  { id: 'log', name: 'Log', roleId: 'log', model: 'gemini-4-argon-medium', extraSkills: [] },
];

const BUILTIN_ROLE_IDS = new Set(STANDARD_AGENTS.map((a) => a.roleId));

/** Resolve the default Agent Team IDE globalStorage directory for the current OS. */
export function resolveDefaultStorageDir(platform = process.platform, env = process.env, homeDir = os.homedir()) {
  if (platform === 'win32') {
    const appData = env.APPDATA || path.join(homeDir, 'AppData', 'Roaming');
    return path.join(appData, 'Agent Team', 'User', 'globalStorage', 'agent-team.agent-team');
  }
  if (platform === 'darwin') {
    return path.join(homeDir, 'Library', 'Application Support', 'Agent Team', 'User', 'globalStorage', 'agent-team.agent-team');
  }
  const configHome = env.XDG_CONFIG_HOME || path.join(homeDir, '.config');
  return path.join(configHome, 'Agent Team', 'User', 'globalStorage', 'agent-team.agent-team');
}

function copyDirRecursive(srcDir, dstDir, force, dryRun = false) {
  let copied = 0;
  if (!dryRun) {
    fs.mkdirSync(dstDir, { recursive: true });
  }
  for (const entry of fs.readdirSync(srcDir, { withFileTypes: true })) {
    const srcPath = path.join(srcDir, entry.name);
    const dstPath = path.join(dstDir, entry.name);
    if (entry.isDirectory()) {
      copied += copyDirRecursive(srcPath, dstPath, force, dryRun);
    } else if (entry.isFile()) {
      if (force || !fs.existsSync(dstPath)) {
        if (!dryRun) {
          fs.copyFileSync(srcPath, dstPath);
        }
        copied += 1;
      }
    }
  }
  return copied;
}

/** Move a file or directory to OS Trash / Recycle Bin (never permanent delete). */
export function moveToTrash(targetPath, platform = process.platform) {
  const resolved = path.resolve(targetPath);
  if (!fs.existsSync(resolved)) return false;

  if (platform === 'win32') {
    const isDir = fs.statSync(resolved).isDirectory();
    const escaped = resolved.replace(/'/g, "''");
    const method = isDir ? 'DeleteDirectory' : 'DeleteFile';
    const psCmd = `Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::${method}('${escaped}', 'OnlyErrorDialogs', 'SendToRecycleBin')`;
    execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', psCmd], { stdio: 'pipe' });
    return true;
  }

  const home = os.homedir();
  const trashBase = platform === 'darwin'
    ? path.join(home, '.Trash')
    : path.join(process.env.XDG_DATA_HOME || path.join(home, '.local', 'share'), 'Trash', 'files');
  fs.mkdirSync(trashBase, { recursive: true });
  const baseName = path.basename(resolved);
  let dest = path.join(trashBase, baseName);
  if (fs.existsSync(dest)) {
    dest = path.join(trashBase, `${baseName}.${Date.now()}-${Math.random().toString(36).slice(2, 6)}`);
  }
  try {
    fs.renameSync(resolved, dest);
  } catch (err) {
    if (err && err.code === 'EXDEV') {
      fs.cpSync(resolved, dest, { recursive: true });
      fs.rmSync(resolved, { recursive: true, force: true });
    } else {
      throw err;
    }
  }
  return true;
}

function readAgentsFile(agentsFile) {
  if (!fs.existsSync(agentsFile)) {
    return { existed: false, data: { version: 1, agents: [] } };
  }
  const raw = fs.readFileSync(agentsFile, 'utf8');
  const cleaned = raw.replace(/^\uFEFF/, '').trim();
  if (!cleaned) {
    throw new Error(`Empty agents.json at ${agentsFile}`);
  }
  let parsed;
  try {
    parsed = JSON.parse(cleaned);
  } catch (err) {
    throw new Error(`Malformed JSON in ${agentsFile}: ${err instanceof Error ? err.message : String(err)}`);
  }
  if (!parsed || typeof parsed !== 'object' || !Array.isArray(parsed.agents)) {
    throw new Error(`Invalid agents.json format at ${agentsFile}: expected { version, agents: [] }`);
  }
  return { existed: true, raw, data: parsed };
}

function arraysEqual(a, b) {
  if (a === b) return true;
  if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
  return a.every((v, i) => v === b[i]);
}

/**
 * Apply the standard Agent Team IDE configuration (19 role agents + grilling skill).
 */
export function setupAgentTeamIde(options = {}) {
  const storageDir = path.resolve(options.storageDir || resolveDefaultStorageDir());
  const dryRun = Boolean(options.dryRun);
  const force = Boolean(options.force);
  const cleanSkills = options.cleanSkills !== false;
  const skillsSourceDir = path.resolve(options.skillsSourceDir || path.join(__dirname, 'skills'));

  const agentsFile = path.join(storageDir, 'agents.json');
  const targetSkillsDir = path.join(storageDir, 'skills');

  const { existed, raw: previousRaw, data } = readAgentsFile(agentsFile);
  const existingAgents = data.agents.map((a) => ({ ...a }));

  const existingOrchestrator = existingAgents.find((a) => a.id === 'orchestrator' || a.roleId === 'orchestrator');
  const cliId = options.cliId || existingOrchestrator?.cliId || 'antigravity';
  const sameCliProfile = existingAgents.find((a) => a.cliId === cliId && a.profileId)?.profileId;
  const profileId = options.profileId || sameCliProfile || (cliId === 'antigravity' ? 'antigravity-this-computer' : undefined);

  const byId = new Map(existingAgents.map((a) => [a.id, a]));
  const byRole = new Map(existingAgents.filter((a) => a.roleId).map((a) => [a.roleId, a]));

  const addedAgents = [];
  const cleanedAgents = [];
  let timestampSeed = Date.now();

  for (const spec of STANDARD_AGENTS) {
    const existing = byId.get(spec.id) || byRole.get(spec.roleId);
    if (existing) {
      if (cleanSkills && BUILTIN_ROLE_IDS.has(existing.roleId)) {
        const desired = spec.extraSkills.length > 0 ? [...spec.extraSkills] : undefined;
        const current = Array.isArray(existing.skills) && existing.skills.length > 0 ? existing.skills : undefined;
        if (!arraysEqual(current, desired)) {
          if (desired) {
            existing.skills = desired;
          } else {
            delete existing.skills;
          }
          cleanedAgents.push(existing.id);
        }
      }
      continue;
    }

    const newAgent = {
      id: spec.id,
      name: spec.name,
      cliId,
      ...(profileId ? { profileId } : {}),
      model: spec.model,
      roleId: spec.roleId,
      permissionMode: 'agent',
      mcpServers: [],
      createdAt: timestampSeed++,
      ...(spec.extraSkills.length > 0 ? { skills: [...spec.extraSkills] } : {}),
    };
    existingAgents.push(newAgent);
    byId.set(newAgent.id, newAgent);
    byRole.set(newAgent.roleId, newAgent);
    addedAgents.push(newAgent.id);
  }

  const nextData = {
    ...data,
    version: typeof data.version === 'number' ? data.version : 1,
    agents: existingAgents,
  };
  const nextRaw = `${JSON.stringify(nextData, null, 2)}\n`;
  const agentsChanged = !existed || nextRaw !== previousRaw;

  let backupFile = null;
  let copiedSkillFiles = 0;
  const trashedItems = [];

  const grillingSrc = path.join(skillsSourceDir, 'grilling');
  const grillingDst = path.join(targetSkillsDir, 'grilling');
  const duplicateGrillingDir = path.join(targetSkillsDir, 'grilling-2');
  const duplicateGrillingMarker = path.join(storageDir, 'grilling-2');

  if (fs.existsSync(grillingSrc)) {
    copiedSkillFiles = copyDirRecursive(grillingSrc, grillingDst, force, dryRun);
  }

  if (cleanSkills) {
    if (fs.existsSync(duplicateGrillingDir)) {
      if (dryRun || moveToTrash(duplicateGrillingDir)) {
        trashedItems.push(duplicateGrillingDir);
      }
    }
    if (fs.existsSync(duplicateGrillingMarker) && fs.statSync(duplicateGrillingMarker).isFile()) {
      if (dryRun || moveToTrash(duplicateGrillingMarker)) {
        trashedItems.push(duplicateGrillingMarker);
      }
    }
  }

  if (!dryRun) {
    fs.mkdirSync(storageDir, { recursive: true });
    if (agentsChanged) {
      if (existed) {
        const stamp = new Date().toISOString().replace(/[:.]/g, '-');
        backupFile = path.join(storageDir, `agents.json.bak.${stamp}`);
        fs.writeFileSync(backupFile, previousRaw, 'utf8');
      }
      fs.writeFileSync(agentsFile, nextRaw, 'utf8');
    }
  }

  return {
    storageDir,
    agentsFile,
    dryRun,
    cliId,
    profileId: profileId || null,
    totalAgents: existingAgents.length,
    addedAgents,
    cleanedAgents,
    agentsChanged,
    backupFile,
    copiedSkillFiles,
    trashedItems,
  };
}

function readFlagValue(argv, index, flag) {
  const val = argv[index + 1];
  if (!val || val.startsWith('-')) {
    throw new Error(`Missing value for option: ${flag}`);
  }
  return val;
}

export function parseArgs(argv) {
  const opts = {};
  for (let i = 0; i < argv.length; i += 1) {
    const raw = argv[i];
    const eqIdx = raw.indexOf('=');
    const arg = eqIdx > 0 && raw.startsWith('--') ? raw.slice(0, eqIdx) : raw;
    const inlineVal = eqIdx > 0 && raw.startsWith('--') ? raw.slice(eqIdx + 1) : null;

    if (arg === '--help' || arg === '-h' || arg === '--dry-run' || arg === '--force' || arg === '--json' || arg === '--clean-skills' || arg === '--no-clean-skills') {
      if (inlineVal !== null) throw new Error(`Option does not take a value: ${raw}`);
      if (arg === '--help' || arg === '-h') opts.help = true;
      else if (arg === '--dry-run') opts.dryRun = true;
      else if (arg === '--force') opts.force = true;
      else if (arg === '--json') opts.json = true;
      else if (arg === '--clean-skills') opts.cleanSkills = true;
      else opts.cleanSkills = false;
    } else if (arg === '--storage-dir' || arg === '--cli' || arg === '--profile') {
      if (inlineVal === '') throw new Error(`Missing value for option: ${arg}`);
      const val = inlineVal ?? readFlagValue(argv, i++, arg);
      if (arg === '--storage-dir') opts.storageDir = val;
      else if (arg === '--cli') opts.cliId = val;
      else opts.profileId = val;
    } else {
      throw new Error(`Unknown or incomplete option: ${raw}`);
    }
  }
  return opts;
}

function printHelp() {
  console.log(`Usage: node setup.mjs [options]

Set up full 19 built-in role agents and clean skill configuration for Agent Team IDE.

Options:
  --storage-dir <path>   Override Agent Team IDE globalStorage directory
  --cli <cliId>          CLI backend for newly added agents (default: existing or "antigravity")
  --profile <profileId>  Profile ID for newly added agents (default: existing or "antigravity-this-computer")
  --no-clean-skills      Do not strip bloated skills from existing role agents
  --force                Overwrite existing skills/grilling files
  --dry-run              Preview changes without writing files
  --json                 Print result as JSON
  -h, --help             Show this help message`);
}

const isMainEntry = (() => {
  if (!process.argv[1]) return false;
  try {
    return fs.realpathSync(path.resolve(process.argv[1])) === __filename;
  } catch {
    return false;
  }
})();

if (isMainEntry) {
  try {
    const opts = parseArgs(process.argv.slice(2));
    if (opts.help) {
      printHelp();
      process.exit(0);
    }
    const result = setupAgentTeamIde(opts);
    if (opts.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      console.log(`Agent Team IDE storage: ${result.storageDir}`);
      console.log(`Mode: ${result.dryRun ? 'DRY RUN (no files modified)' : 'APPLIED'}`);
      console.log(`Total agents: ${result.totalAgents} (added: ${result.addedAgents.length}, cleaned: ${result.cleanedAgents.length})`);
      if (result.addedAgents.length > 0) console.log(`  Added: ${result.addedAgents.join(', ')}`);
      if (result.cleanedAgents.length > 0) console.log(`  Cleaned skills on: ${result.cleanedAgents.join(', ')}`);
      if (result.copiedSkillFiles > 0) console.log(`  Installed grilling skill files: ${result.copiedSkillFiles}`);
      if (result.trashedItems.length > 0) console.log(`  Moved duplicates to Trash: ${result.trashedItems.join(', ')}`);
      if (result.backupFile) console.log(`  Backup created: ${result.backupFile}`);
    }
  } catch (err) {
    console.error(`Error: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  }
}
