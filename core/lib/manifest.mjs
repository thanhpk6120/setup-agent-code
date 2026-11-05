// core/lib/manifest.mjs - load + validate manifests, resolve per-agent paths, build MCP specs.
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  exists, expand, osKey, isWin, log, readJson, which
} from './util.mjs';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

export const PHASES = [
  { id: 'P0', title: 'Preflight' },
  { id: 'P1', title: 'Args & policy' },
  { id: 'P2', title: 'MCP selection' },
  { id: 'P3', title: 'Resume & env' },
  { id: 'P4', title: 'Prerequisites' },
  { id: 'P5', title: 'Agent binary' },
  { id: 'P6', title: 'MCP tools' },
  { id: 'P7', title: 'Render config' },
  { id: 'P8', title: 'Instruction files' },
  { id: 'P9', title: 'Skills' },
  { id: 'P10', title: 'Hooks & guards' },
  { id: 'P11', title: 'Verify' },
  { id: 'P12', title: 'Cleanup & summary' }
];

export function loadManifests(root = ROOT) {
  const agents = readJson(path.join(root, 'manifest', 'agents.json'));
  const mcp = readJson(path.join(root, 'manifest', 'mcp.json'));
  const prompts = readJson(path.join(root, 'manifest', 'prompts.json'));
  const options = readJson(path.join(root, 'manifest', 'options.json'));
  const prereqs = readJson(path.join(root, 'manifest', 'prerequisites.json'));
  return { root, agents, mcp, prompts, options, prereqs };
}

export function validateManifests(m) {
  const errors = [];
  const ids = new Set();
  for (const agent of m.agents.agents) {
    if (!agent.id) errors.push('agent thieu id');
    if (ids.has(agent.id)) errors.push(`agent id trung: ${agent.id}`);
    ids.add(agent.id);
    for (const key of ['name', 'dir', 'instructionFiles', 'skillsDir', 'verify']) {
      if (!(key in agent)) errors.push(`${agent.id}: thieu "${key}"`);
    }
    if (!Array.isArray(agent.binary?.installGuidance) || agent.binary.installGuidance.length === 0) {
      errors.push(`${agent.id}: binary can installGuidance (huong dan khi cai that bai)`);
    }
    if (!agent.dir?.win || !agent.dir?.unix) errors.push(`${agent.id}: dir phai co win+unix`);
    for (const file of agent.instructionFiles || []) {
      if (!file.dest) errors.push(`${agent.id}: instructionFile thieu dest`);
      for (const part of file.content || []) {
        if (!exists(path.join(m.root, 'templates', part))) {
          errors.push(`${agent.id}: template khong ton tai: templates/${part}`);
        }
      }
      for (const section of Object.values(file.optionalSections || {})) {
        if (!exists(path.join(m.root, 'templates', section))) {
          errors.push(`${agent.id}: section khong ton tai: templates/${section}`);
        }
      }
    }
    for (const cfg of agent.configs || []) {
      if (!exists(path.join(m.root, 'templates', cfg.template))) {
        errors.push(`${agent.id}: config template khong ton tai: templates/${cfg.template}`);
      }
      if (!cfg.dest) errors.push(`${agent.id}: config thieu dest`);
    }
    for (const hook of agent.hooks || []) {
      if (hook.template && !exists(path.join(m.root, 'templates', hook.template))) {
        errors.push(`${agent.id}: hook template khong ton tai: templates/${hook.template}`);
      }
    }
    for (const plugin of agent.plugins || []) {
      if (!plugin.id || !plugin.package) errors.push(`${agent.id}: plugin can id + package`);
      if (!plugin.profile) errors.push(`${agent.id}: plugin ${plugin.id}: thieu profile`);
      if (!Array.isArray(plugin.installGuidance) || plugin.installGuidance.length === 0) {
        errors.push(`${agent.id}: plugin ${plugin.id}: can installGuidance`);
      }
    }
    if (agent.credentialFile && !exists(path.join(m.root, 'templates', agent.credentialFile.template))) {
      errors.push(`${agent.id}: credential template khong ton tai: templates/${agent.credentialFile.template}`);
    }
    if (!agent.skillsDir) errors.push(`${agent.id}: thieu skillsDir`);
  }
  const mcpIds = new Set();
  const depIds = new Set();
  for (const dep of m.prereqs?.deps || []) {
    if (!dep.id) errors.push('prerequisite thieu id');
    if (depIds.has(dep.id)) errors.push(`prerequisite id trung: ${dep.id}`);
    depIds.add(dep.id);
    if (!dep.verify) errors.push(`prerequisite ${dep.id}: thieu verify`);
    for (const osName of ['win', 'unix']) {
      if (dep.install && !Array.isArray(dep.install[osName])) errors.push(`prerequisite ${dep.id}: install.${osName} phai la array`);
    }
    if (!Array.isArray(dep.guidance) || dep.guidance.length === 0) {
      errors.push(`prerequisite ${dep.id}: can guidance de huong dan khi cai that bai`);
    }
  }
  for (const requirement of m.prereqs?.pathRequirements || []) {
    if (!requirement.id) errors.push('pathRequirement thieu id');
    if (!requirement.resolve) errors.push(`pathRequirement ${requirement.id}: thieu resolve`);
    if (!Array.isArray(requirement.guidance || []) && !requirement.why) {
      errors.push(`pathRequirement ${requirement.id}: can why/guidance`);
    }
  }
  for (const server of m.mcp.servers) {
    if (!server.id) errors.push('mcp thieu id');
    if (mcpIds.has(server.id)) errors.push(`mcp id trung: ${server.id}`);
    mcpIds.add(server.id);
    for (const osName of ['win', 'unix']) {
      if (!Array.isArray(server.install?.[osName])) errors.push(`${server.id}: install.${osName} phai la array`);
    }
    if (!server.verify) errors.push(`${server.id}: thieu verify`);
    if (!Array.isArray(server.installGuidance) || server.installGuidance.length === 0) {
      errors.push(`${server.id}: can installGuidance de huong dan khi cai that bai`);
    }
    for (const depId of server.requires || []) {
      if (!depIds.has(depId)) errors.push(`${server.id}: requires dep khong ton tai: ${depId}`);
    }
    if (server.postInstall && !server.postInstall.type) errors.push(`${server.id}: postInstall thieu type`);
  }
  const promptKeys = new Set();
  for (const prompt of m.prompts.prompts) {
    if (!prompt.key) errors.push('prompt thieu key');
    if (promptKeys.has(prompt.key)) errors.push(`prompt key trung: ${prompt.key}`);
    promptKeys.add(prompt.key);
    if (prompt.when?.mcp && !mcpIds.has(prompt.when.mcp)) {
      errors.push(`prompt ${prompt.key}: when.mcp khong ton tai: ${prompt.when.mcp}`);
    }
  }
  const optionIds = new Set();
  for (const option of m.options.options) {
    if (!option.id) errors.push('option thieu id');
    if (optionIds.has(option.id)) errors.push(`option id trung: ${option.id}`);
    optionIds.add(option.id);
    if (!option.long && !option.ps) errors.push(`option ${option.id}: thieu long/ps`);
  }
  for (const agentId of ['omp', 'claude-code', 'opencode', 'codex-cli', 'dsh', 'antigravity-cli']) {
    if (!ids.has(agentId)) errors.push(`thieu agent bat buoc: ${agentId}`);
  }
  return errors;
}

/** Resolve every path token used by a manifest entry. */
export function resolvePaths(agent) {
  const dir = expand(agent.dir[osKey]);
  const extra = {};
  for (const [name, value] of Object.entries(agent.extraDirs || {})) {
    const primary = expand(value[osKey]);
    const fallback = value.fallback?.[osKey] ? expand(value.fallback[osKey]) : '';
    extra[name] = (!exists(primary) && fallback && exists(fallback)) ? fallback : primary;
  }
  const tokens = { dir, ...extra };
  tokens.dirPath = dir.split(path.sep).join('/');
  if (tokens.trashGuard) tokens.trashGuardPath = tokens.trashGuard.split(path.sep).join('/');
  return { dir, extra, tokens };
}

export function resolveToken(value, tokens) {
  return String(value).replace(/<([A-Za-z][A-Za-z0-9_]*)>/g, (whole, name) => (name in tokens ? tokens[name] : whole));
}

export function templatePath(root, relative) {
  return path.join(root, 'templates', ...relative.split('/'));
}

let whichCache = null;
function bin(name) {
  if (!whichCache) whichCache = new Map();
  if (whichCache.has(name)) return whichCache.get(name);
  const found = which(name);
  whichCache.set(name, found);
  return found;
}

export function resetCaches() { whichCache = null; }

/**
 * Build the concrete MCP server spec for the current OS.
 * Returns { command, args, env } for a selected server id.
 * `resolvers` provides { bin(name), npmPath(rel), cloakbrowser, home }.
 */
export function buildServerSpec(server, resolvers) {
  const spec = server.spec || {};
  const platform = spec[osKey] || spec;
  let command = platform.command;
  let args = [...(platform.args || [])];
  const env = {};
  for (const [key, value] of Object.entries(platform.env || {})) {
    env[key] = value;
  }

  const binOf = (name) => resolvers.bin(name) || name;
  const substitute = (item) => String(item)
    .replace(/<bin:([^>]+)>/g, (_, name) => binOf(name))
    .replace(/<npm:([^>]+)>/g, (_, rel) => resolvers.npmPath(rel) || `<missing:${rel}>`)
    .replace(/<cloakbrowser>/g, resolvers.cloakbrowser);

  if (server.kind === 'gitnexus') {
    if (isWin) {
      command = 'cmd';
      args = ['/c', binOf('gitnexus'), 'mcp'];
    } else {
      command = 'gitnexus';
      args = ['mcp'];
    }
  } else if (server.kind === 'context7') {
    const ctxPath = resolvers.npmPath('@upstash/context7-mcp/dist/index.js');
    if (ctxPath && exists(ctxPath)) {
      command = 'node';
      args = [ctxPath];
    } else {
      // Package not installed globally (e.g. --skip-install): use npx so the server still starts.
      command = 'npx';
      args = ['-y', '@upstash/context7-mcp'];
    }
  } else if (server.kind === 'cloakbrowser') {
    command = 'node';
    args = [resolvers.cloakbrowser];
  } else {
    args = args.map(substitute);
  }
  return { command, args, env };
}

export function agentById(manifests, id) {
  return manifests.agents.agents.find((a) => a.id === id);
}

export function sortTargets(manifests, target) {
  const ordered = manifests.agents.agents.map((a) => a.id);
  if (target === 'all') return ordered;
  return [target];
}

export function logManifestSummary(manifests) {
  log.debug(`agents: ${manifests.agents.agents.map((a) => a.id).join(', ')}`);
}
