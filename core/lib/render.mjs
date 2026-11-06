// core/lib/render.mjs - placeholder substitution + per-format config rendering.
import fs from 'node:fs';
import path from 'node:path';
import { ensureDir, exists, readText, writeFileAtomic } from './util.mjs';

export function substitutePlaceholders(text, vars, { json = false } = {}) {
  let out = text;
  for (const [key, value] of Object.entries(vars)) {
    const raw = value ?? '';
    // Inside JSON templates the value must not break string escaping (Windows paths!).
    const replacement = json ? JSON.stringify(String(raw)).slice(1, -1) : String(raw);
    out = out.split(`__${key}__`).join(replacement);
  }
  return out;
}

export function deepMerge(base, overlay) {
  if (Array.isArray(overlay)) return overlay.slice();
  if (overlay && typeof overlay === 'object') {
    const out = (base && typeof base === 'object' && !Array.isArray(base)) ? { ...base } : {};
    for (const [key, value] of Object.entries(overlay)) {
      out[key] = deepMerge(out[key], value);
    }
    return out;
  }
  return overlay;
}

/**
 * Merge a template config over a live one without destroying user data.
 * An empty template value never replaces a non-empty live value, so a missing
 * placeholder (no .env supplied) cannot erase a configured model key or token.
 */
export function mergeKeepExisting(base, overlay) {
  if (Array.isArray(overlay)) return overlay.length === 0 && Array.isArray(base) ? base.slice() : overlay.slice();
  if (overlay && typeof overlay === 'object') {
    const out = (base && typeof base === 'object' && !Array.isArray(base)) ? { ...base } : {};
    for (const [key, value] of Object.entries(overlay)) {
      out[key] = mergeKeepExisting(out[key], value);
    }
    return out;
  }
  // A value the installer could not fill must not clobber live config.
  if (typeof overlay === 'string' && (overlay === '' || overlay.includes('__'))) {
    if (typeof base === 'string' && base !== '') return base;
  }
  return overlay;
}

export function deleteByPath(obj, dotted) {
  const parts = dotted.split('.');
  let cursor = obj;
  for (let i = 0; i < parts.length - 1; i += 1) {
    if (!cursor || typeof cursor !== 'object') return;
    cursor = cursor[parts[i]];
  }
  if (cursor && typeof cursor === 'object') delete cursor[parts[parts.length - 1]];
}

/** Map selected servers to the shape each JSON adapter expects. */
export function jsonMcpObject(adapter, servers) {
  const out = {};
  for (const { id, spec } of servers) {
    if (adapter === 'opencode-json') {
      out[id] = {
        type: 'local',
        command: [spec.command, ...spec.args],
        enabled: true,
        ...(Object.keys(spec.env).length ? { environment: spec.env } : {})
      };
    } else {
      out[id] = {
        command: spec.command,
        args: spec.args,
        ...(Object.keys(spec.env).length ? { env: spec.env } : {})
      };
    }
  }
  return out;
}

const tomlString = (value) => `"${String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
const tomlArray = (values) => `[${values.map(tomlString).join(', ')}]`;

export function tomlMcpBlocks(servers) {
  const blocks = [];
  for (const { id, spec } of servers) {
    const lines = [`[mcp_servers.${id}]`, `command = ${tomlString(spec.command)}`, `args = ${tomlArray(spec.args)}`];
    if (Object.keys(spec.env).length) {
      lines.push(`[mcp_servers.${id}.env]`);
      for (const [key, value] of Object.entries(spec.env)) lines.push(`${key} = ${tomlString(value)}`);
    }
    blocks.push(lines.join('\n'));
  }
  return blocks.join('\n\n');
}

const yamlScalar = (value) => {
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  return JSON.stringify(String(value));
};

export function yamlMcpBlocks(servers) {
  const blocks = [];
  for (const { id, spec } of servers) {
    const lines = [
      `- id: mcp-${id}`,
      '  name: "@deepseek-ai/dsh-mcp-client"',
      '  config:',
      `    serverName: ${id}`,
      '    transport: stdio',
      `    command: ${yamlScalar(spec.command)}`
    ];
    if (spec.args.length) {
      lines.push('    args:');
      for (const arg of spec.args) lines.push(`      - ${yamlScalar(arg)}`);
    } else {
      lines.push('    args: []');
    }
    const envKeys = Object.keys(spec.env);
    if (envKeys.length) {
      lines.push('    env:');
      for (const key of envKeys) lines.push(`      ${key}: ${yamlScalar(spec.env[key])}`);
    }
    blocks.push(lines.join('\n'));
  }
  return blocks.join('\n');
}

function yamlId(value) {
  if (!value) return null;
  const text = value.trim();
  if (text.startsWith('"')) {
    const match = text.match(/^("(?:[^"\\]|\\.)*")(?:\s+#.*)?$/);
    if (!match) throw new Error('Unsupported YAML id');
    return JSON.parse(match[1]);
  }
  if (text.startsWith("'")) {
    const match = text.match(/^'((?:[^']|'')*)'(?:\s+#.*)?$/);
    if (!match) throw new Error('Unsupported YAML id');
    return match[1].replace(/''/g, "'");
  }
  return text.replace(/\s+#.*$/, '').trim() || null;
}

/**
 * Split a dsh-style patch layer (a top-level YAML array) into entries.
 * Entries start at column 0 with "- "; every indented line belongs to the entry.
 */
export function splitYamlEntries(text) {
  const preamble = [];
  const entries = [];
  let current = null;
  for (const line of text.split(/\r?\n/)) {
    if (/^-(?: |$)/.test(line)) {
      if (current) entries.push(current);
      current = { lines: [line] };
    } else if (current) current.lines.push(line);
    else preamble.push(line);
  }
  if (current) entries.push(current);
  return {
    preamble,
    entries: entries.map((entry) => ({
      text: entry.lines.join('\n').replace(/\s+$/, ''),
      id: yamlId((entry.lines[0].match(/^- id:\s*(.*?)\s*$/) || [])[1])
    }))
  };
}

/**
 * Normalize a patch layer into plain entries plus the items of its `- insert:` block.
 * Insert items are diffed by their own id, so a template can own `memory-memorix`
 * without disturbing other inserted plugins.
 */
function parseLayer(text) {
  const { preamble, entries } = splitYamlEntries(text);
  const plain = [];
  const inserts = [];
  for (const entry of entries) {
    const lines = entry.text.split('\n');
    if (/^- insert:\s*$/.test(lines[0])) {
      let item = null;
      let itemIndent = null;
      for (const line of lines.slice(1)) {
        const dash = /^(\s*)-(?:\s|$)/.exec(line);
        if (dash) {
          const indent = dash[1].length;
          if (itemIndent === null) itemIndent = indent;
          // Deeper dashes are content of the current item (e.g. `args:` lists).
          if (indent > itemIndent) {
            if (item) item.lines.push(line);
            continue;
          }
          if (indent < itemIndent) throw new Error('Cannot safely merge nested YAML insert');
          const match = line.match(/^ {2,}- (?:id:\s*(.*?)\s*)?$/);
          if (!match) throw new Error('Cannot safely merge unsupported YAML insert item');
          if (item) inserts.push(item);
          item = { id: yamlId(match[1]), lines: [line] };
          continue;
        }
        if (item) item.lines.push(line);
        else if (line.trim()) throw new Error('Cannot safely merge YAML insert preamble');
      }
      if (item) inserts.push(item);
      continue;
    }
    plain.push(entry);
  }
  return { preamble, plain, inserts: inserts.map((item) => ({ id: item.id, text: item.lines.join('\n').replace(/\s+$/, '') })) };
}

function reindentInsertItem(text, targetIndent = 4) {
  const lines = text.split('\n');
  const m = /^(\s*)-/.exec(lines[0]);
  if (!m) return text;
  const currentIndent = m[1].length;
  const delta = targetIndent - currentIndent;
  if (delta === 0) return text;
  return lines.map((line) => {
    if (!line.trim()) return line;
    if (delta > 0) return ' '.repeat(delta) + line;
    return line.slice(Math.min(-delta, line.match(/^\s*/)[0].length));
  }).join('\n');
}

/**
 * Merge a managed patch layer into an existing one without dropping user entries.
 * Entries listed in `ownIds` are template-owned: the template value replaces them.
 * Every other template entry is only a default, so an existing entry wins.
 * Installer-managed MCP entries and insert items are dropped first so de-selected
 * plugins disappear. An insert item the installer does not manage keeps its live
 * value, so a duplicate id is never emitted twice. Entries the template does not
 * know about are preserved verbatim.
 */
export function mergeYamlLayer(existingText, templateText, { managedMcpIds = [], managedInsertIds = [], ownIds = [] } = {}) {
  // ponytail: Reject block scalars until a lossless YAML parser is used; a block
  // scalar's blank lines are indistinguishable from entry separators here.
  for (const text of [existingText, templateText]) {
    if (/^\s*(?:-\s+|[^#\n]+:\s*)[|>][-+\d]*\s*(?:#.*)?$/m.test(text)) throw new Error('Cannot safely merge YAML block scalar');
  }
  const existing = parseLayer(existingText);
  const template = parseLayer(templateText);
  const own = new Set(ownIds);
  const dropMcp = new Set(managedMcpIds.map((id) => `mcp-${id}`));
  // MCP entries are installer-managed, so a stale one must not block the regenerated entry.
  const existingIds = new Set(existing.plain.map((entry) => entry.id).filter((id) => id && !dropMcp.has(id)));
  const dropInserts = new Set(managedInsertIds);
  const existingInsertIds = new Set(existing.inserts.map((item) => item.id).filter((id) => id && !dropInserts.has(id)));

  const keptPlain = existing.plain
    .filter((entry) => !(entry.id && own.has(entry.id)))
    .filter((entry) => !(entry.id && dropMcp.has(entry.id)))
    .map((entry) => entry.text);
  // Insert items belong to the user unless the installer declares them managed,
  // so an unmanaged duplicate keeps the live item and never doubles the id.
  const keptInserts = existing.inserts
    .filter((item) => !(item.id && dropInserts.has(item.id)))
    .map((item) => item.text);

  const templatePlain = template.plain
    .filter((entry) => !(entry.id && existingIds.has(entry.id) && !own.has(entry.id)))
    .map((entry) => entry.text)
    .filter(Boolean);
  const templateInserts = template.inserts
    .filter((item) => !(item.id && existingInsertIds.has(item.id)))
    .map((item) => item.text)
    .filter(Boolean);
  const inserts = [...keptInserts, ...templateInserts];
  const targetIndent = (inserts[0] && /^(\s*)-/.exec(inserts[0])?.[1]?.length) || 4;
  const normalizedInserts = inserts.map((text) => reindentInsertItem(text, targetIndent));

  const body = [...keptPlain, ...templatePlain];
  if (normalizedInserts.length) body.push(`- insert:\n${normalizedInserts.join('\n')}`);
  const preambleLines = existing.preamble.join('\n').trim() ? existing.preamble : template.preamble;
  const merged = body.join('\n').replace(/^# <<MCP_SERVERS>>$/gm, '').replace(/\n{3,}/g, '\n\n');
  const text = [preambleLines.join('\n').trim(), merged.trim()].filter(Boolean).join('\n');
  return text ? `${text.replace(/\s+$/, '')}\n` : '';
}

export function composeInstruction(parts, optionalSections = []) {
  const chunks = [...parts];
  for (const section of optionalSections) if (section) chunks.push(section);
  return `${chunks.map((c) => c.trim()).join('\n\n---\n\n')}\n`;
}

/** Read a template and apply __PLACEHOLDER__ values. */
export function renderTemplate(root, templateRel, vars, options = {}) {
  const file = path.join(root, 'templates', ...templateRel.split('/'));
  return substitutePlaceholders(readText(file), vars, options);
}

/** Register a hook into a JSON settings object (idempotent). */
export function registerJsonHook(settings, hook) {
  settings.hooks = settings.hooks || {};
  const list = Array.isArray(settings.hooks[hook.event]) ? settings.hooks[hook.event] : [];
  const matchers = Array.isArray(hook.matcher) ? hook.matcher : [hook.matcher];
  // Claude Code nests the handler list; other agents accept a flat entry.
  const shape = hook.shape === 'claude' ? 'claude' : 'flat';
  const commandsOf = (entry) => {
    if (!entry) return [];
    if (Array.isArray(entry.hooks)) return entry.hooks.map((h) => h && h.command).filter(Boolean);
    return entry.command ? [entry.command] : [];
  };
  for (const matcher of matchers) {
    const entry = shape === 'claude'
      ? { matcher, hooks: [{ type: 'command', command: hook.command, timeout: hook.timeout ?? 15 }] }
      : { matcher, command: hook.command, timeout: hook.timeout ?? 15 };
    const existingIndex = list.findIndex((item) => item && item.matcher === matcher && commandsOf(item).includes(hook.command));
    if (existingIndex >= 0) list[existingIndex] = entry;
    else list.push(entry);
  }
  settings.hooks[hook.event] = list;
  return settings;
}

/**
 * Canonical table key for a TOML header line, or null when this line-based parser
 * cannot safely reason about the header. Quoted segments are legal TOML and are how
 * Codex writes ids such as [mcp_servers."9remote"], so they are unquoted before
 * comparison. An escape or an empty segment is refused rather than guessed.
 */
export function tomlHeaderKey(headerText) {
  const m = String(headerText).trim().match(/^\[([^\]]*)\]$/);
  if (!m || !m[1].trim()) return null;
  const parts = [];
  for (const raw of m[1].split('.')) {
    const seg = raw.trim();
    if (/^[A-Za-z0-9_-]+$/.test(seg)) parts.push(seg);
    else {
      const q = seg.match(/^"(.*)"$/) || seg.match(/^'(.*)'$/);
      if (!q || !/^[A-Za-z0-9_@/-]+$/.test(q[1]) || /\\/.test(q[1])) return null;
      parts.push(q[1]);
    }
  }
  return parts.join('.');
}

/**
 * Merge a managed TOML config into a live one without losing user content.
 *
 * Ownership rules, in order of precedence:
 * 1. A table is installer-owned when the template declares it or `ownedHeaders`
 *    names it. Inside an owned table the template sets the shape, but a live
 *    value survives whenever the template still carries an empty placeholder.
 * 2. Any other table (user MCP servers, providers, hooks, projects) is copied
 *    verbatim.
 * 3. A top-level scalar already present in the live file keeps its live value;
 *    the template only fills keys the live file is missing. Re-running the
 *    installer therefore never rewrites a working configuration.
 */
export function mergeToml(existingText, templateText, { ownedHeaders = [] } = {}) {
  // ponytail: Reject TOML outside this line-based parser's subset; use a lossless parser to expand it.
  for (const text of [existingText, templateText]) {
    const seen = new Set();
    for (const line of text.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      if (trimmed.startsWith('[')) {
        // Quoted segments are legal TOML and are how Codex writes ids such as
        // [mcp_servers."9remote"], so headers are compared by canonical table key.
        const key = tomlHeaderKey(trimmed);
        if (!key || seen.has(key)) throw new Error('Cannot safely merge unsupported TOML table');
        seen.add(key);
      } else if (!/^[A-Za-z_][\w-]*\s*=/.test(trimmed) || /(?:"""|''')/.test(trimmed)) {
        throw new Error('Cannot safely merge unsupported TOML value');
      }
    }
  }
  // ponytail: Multiline arrays require a TOML parser; reject them rather than lose data.
  for (const text of [existingText, templateText]) {
    for (const line of text.split(/\r?\n/)) {
      const match = line.match(/^\s*[^#=]+\s*=\s*(\[.*)$/);
      if (!match) continue;
      let depth = 0;
      let quote = null;
      let escaped = false;
      for (const char of match[1]) {
        if (quote) {
          if (escaped) escaped = false;
          else if (quote === '"' && char === '\\') escaped = true;
          else if (char === quote) quote = null;
        } else if (char === '#' ) break;
        else if (char === '"' || char === "'") quote = char;
        else if (char === '[') depth += 1;
        else if (char === ']') depth -= 1;
      }
      if (depth !== 0 || quote) throw new Error('Cannot safely merge multiline TOML array');
    }
  }
  const headerOf = (line) => {
    const m = line.match(/^\s*(\[[^\]]+\])\s*$/);
    return m ? m[1] : null;
  };
  const split = (text) => {
    const top = [];
    const blocks = new Map();
    let current = null;
    for (const line of text.split(/\r?\n/)) {
      const header = headerOf(line);
      if (header) {
        const key = tomlHeaderKey(header);
        if (!key) throw new Error('Cannot safely merge unsupported TOML table');
        current = key;
        blocks.set(key, [line]);
        continue;
      }
      if (current) blocks.get(current).push(line);
      else top.push(line);
    }
    return { top, blocks };
  };
  const scalarOf = (line) => {
    const m = line.match(/^\s*([A-Za-z_][\w-]*)\s*=\s*(.*?)\s*$/);
    return m ? { key: m[1], value: m[2] } : null;
  };
  const isEmpty = (value) => value === '""' || value === "''" || value === '';

  const live = split(existingText);
  const tpl = split(templateText);
  // ownedHeaders accepts both spellings, so they are canonicalised the same way as live headers.
  const owned = new Set([...tpl.blocks.keys()]);
  for (const header of ownedHeaders) {
    const key = tomlHeaderKey(header);
    if (key) owned.add(key);
  }
  const liveTopKeys = new Set();
  for (const line of live.top) {
    const s = scalarOf(line);
    if (s) liveTopKeys.add(s.key);
  }

  const top = [...live.top.filter((line) => line.trim() !== '')];
  for (const line of tpl.top) {
    const s = scalarOf(line);
    if (!s || liveTopKeys.has(s.key)) continue;
    top.push(line);
  }

  const mergeBlock = (liveLines, tplLines) => {
    const liveByKey = new Map();
    for (const line of liveLines) {
      const s = scalarOf(line);
      if (s) liveByKey.set(s.key, line);
    }
    const out = [tplLines[0]];
    const seen = new Set();
    for (const line of tplLines.slice(1)) {
      const s = scalarOf(line);
      if (!s) {
        if (line.trim() !== '') out.push(line);
        continue;
      }
      seen.add(s.key);
      const liveLine = liveByKey.get(s.key);
      out.push(isEmpty(s.value) && liveLine ? liveLine : line);
    }
    for (const [key, line] of liveByKey) if (!seen.has(key)) out.push(line);
    return out.join('\n');
  };

  const parts = [top.join('\n').replace(/\s+$/, '')];
  for (const [header, lines] of live.blocks) {
    if (owned.has(header) && tpl.blocks.has(header)) parts.push(mergeBlock(lines, tpl.blocks.get(header)));
    else if (!owned.has(header)) parts.push(lines.join('\n'));
  }
  for (const [header, lines] of tpl.blocks) {
    if (!live.blocks.has(header)) parts.push(lines.join('\n'));
  }
  return `${parts.map((p) => p.replace(/\s+$/, '')).filter(Boolean).join('\n\n')}\n`;
}

/** Register a plugin path into a JSON config array (idempotent). */
export function registerJsonArray(config, dottedKey, value) {
  const parts = dottedKey.split('.');
  let cursor = config;
  for (let i = 0; i < parts.length - 1; i += 1) {
    cursor[parts[i]] = cursor[parts[i]] || {};
    cursor = cursor[parts[i]];
  }
  const key = parts[parts.length - 1];
  const list = Array.isArray(cursor[key]) ? cursor[key] : [];
  if (!list.includes(value)) list.push(value);
  cursor[key] = list;
  return config;
}

export function writeJson(file, obj, dryRun) {
  const content = `${JSON.stringify(obj, null, 2)}\n`;
  if (dryRun) return content;
  ensureDir(path.dirname(file));
  writeFileAtomic(file, content);
  return content;
}

export function writeText(file, content, dryRun) {
  if (dryRun) return content;
  ensureDir(path.dirname(file));
  writeFileAtomic(file, content);
  return content;
}

export function readJsonIfExists(file) {
  if (!exists(file)) return null;
  return JSON.parse(readText(file));
}

export function fileHasMarker(file, marker) {
  return exists(file) && readText(file).includes(marker);
}
