// core/lib/verify.mjs - verification of installed tools, rendered configs and MCP handshakes.
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { exists, isWin, readText, versionGte, versionOf, which } from './util.mjs';

const READY = new Set(['PASS', 'WARN', 'SKIP']);

export function result(check, status, detail = '') {
  return { check, status, detail };
}

export function isOk(row) { return READY.has(row.status); }

export function verifyBinary(agent, { skipInstall = false, mode = 'install' } = {}) {
  const bin = agent.binary?.command;
  if (!bin) return [result('binary', 'SKIP', 'agent khong khai bao binary')];
  const found = which(bin);
  if (!found) {
    const status = (skipInstall || agent.binary.optional || mode !== 'install') ? 'WARN' : 'FAIL';
    return [result(`binary:${bin}`, status, `${skipInstall ? 'bo qua theo --skip-install / ' : ''}khong tim thay trong PATH`)];
  }
  const version = versionOf(bin, agent.binary.versionArgs || ['--version']);
  if (!version) {
    // Present in PATH but cannot report a version -> installed incorrectly / broken.
    return [result(`binary:${bin}`, agent.binary.optional ? 'WARN' : 'FAIL', `${found} khong chay duoc --version`)];
  }
  const required = agent.binary.version || agent.binary.minVersion;
  if (required) {
    const ok = agent.binary.version
      ? version === agent.binary.version
      : versionGte(version, agent.binary.minVersion);
    return [result(`binary:${bin}`, ok ? 'PASS' : 'FAIL', ok ? `${found} (v${version})` : `${found} v${version} khong dat ${required}`)];
  }
  return [result(`binary:${bin}`, 'PASS', `${found} (v${version})`)];
}

export function verifyFiles(agent, tokens) {
  const rows = [];
  for (const raw of agent.verify?.files || []) {
    const file = String(raw).replace(/<([A-Za-z][A-Za-z0-9_]*)>/g, (w, n) => (n in tokens ? tokens[n] : w));
    rows.push(exists(file)
      ? result(`file:${path.basename(file)}`, 'PASS', file)
      : result(`file:${path.basename(file)}`, 'FAIL', `thieu: ${file}`));
  }
  for (const raw of agent.verify?.forbiddenAbsent || []) {
    const file = String(raw).replace(/<([A-Za-z][A-Za-z0-9_]*)>/g, (w, n) => (n in tokens ? tokens[n] : w));
    rows.push(exists(file)
      ? result(`forbidden:${path.basename(file)}`, 'FAIL', `file khong duoc phep ton tai: ${file}`)
      : result(`forbidden:${path.basename(file)}`, 'PASS', 'khong ton tai'));
  }
  return rows;
}

export function verifyConfigEntries(agent, tokens, selectedIds) {
  const rows = [];
  const configs = (agent.configs || []).filter((cfg) => cfg.mcpMerge);
  if (['omp-json', 'json-mcpServers'].includes(agent.mcp?.adapter) && agent.mcp.file &&
      !configs.some((cfg) => cfg.dest === agent.mcp.file)) {
    configs.push({ dest: agent.mcp.file, kind: 'json' });
  }
  for (const cfg of configs) {
    const file = String(cfg.dest).replace(/<([A-Za-z][A-Za-z0-9_]*)>/g, (w, n) => (n in tokens ? tokens[n] : w));
    if (!exists(file)) { rows.push(result(`config:${path.basename(file)}`, 'FAIL', 'thieu file')); continue; }
    let text;
    try { text = readText(file); } catch { rows.push(result(`config:${path.basename(file)}`, 'FAIL', 'khong doc duoc file')); continue; }
    let servers;
    if (cfg.kind === 'json') {
      let config;
      try { config = JSON.parse(text); } catch { rows.push(result(`config:${path.basename(file)}`, 'FAIL', 'JSON loi')); continue; }
      const key = agent.mcp?.adapter === 'opencode-json' ? 'mcp' : 'mcpServers';
      servers = config && typeof config === 'object' && !Array.isArray(config) ? config[key] : null;
      if (!servers || typeof servers !== 'object' || Array.isArray(servers)) {
        rows.push(result(`config:${path.basename(file)}`, 'FAIL', `${key} khong hop le`));
        continue;
      }
    }
    for (const id of selectedIds) {
      const present = cfg.kind === 'toml'
        ? text.includes(`[mcp_servers.${id}]`)
        : cfg.kind === 'yaml'
          ? (agent.mcp?.adapter === 'goose-yaml' ? new RegExp(`^  ${id}:`, 'm').test(text) : text.includes(`- id: mcp-${id}`))
          : Object.hasOwn(servers, id) && servers[id] !== null && typeof servers[id] === 'object' && !Array.isArray(servers[id]);
      rows.push(result(`mcp:${id}`, present ? 'PASS' : 'FAIL', path.basename(file)));
    }
  }
  return rows;
}

/** JSON-RPC initialize handshake against a stdio MCP server. */
export function handshake(spec, timeoutMs = 8000) {
  return new Promise((resolve) => {
    let settled = false;
    let child;
    const done = (status, detail) => {
      if (settled) return;
      settled = true;
      try { child?.kill(); } catch {}
      resolve(result(`mcp-handshake:${spec.command}`, status, detail));
    };
    try {
      // Resolve bare names first: npm/npx/memorix are .cmd shims on Windows.
      const resolved = /[\\/]/.test(spec.command) ? spec.command : (which(spec.command) || spec.command);
      const needsShell = isWin && /\.(cmd|bat)$/i.test(resolved);
      const file = needsShell ? (process.env.ComSpec || 'cmd.exe') : resolved;
      const argv = needsShell
        ? ['/d', '/s', '/c', [resolved, ...spec.args].map((a) => (/[\s"]/.test(a) ? `"${a}"` : a)).join(' ')]
        : spec.args;
      child = spawn(file, argv, {
        env: { ...process.env, ...spec.env },
        windowsHide: true,
        stdio: ['pipe', 'pipe', 'pipe']
      });
    } catch (e) {
      return done('WARN', `khong spawn duoc: ${e.message}`);
    }
    const timer = setTimeout(() => done('WARN', `timeout ${timeoutMs}ms`), timeoutMs);
    let buffer = '';
    child.stdout.on('data', (chunk) => {
      buffer += chunk.toString();
      const line = buffer.split(/\r?\n/).find((l) => l.trim().startsWith('{'));
      if (!line) return;
      try {
        const msg = JSON.parse(line);
        if (msg.result || msg.error) {
          clearTimeout(timer);
          done(msg.result ? 'PASS' : 'WARN', msg.result ? 'initialize OK' : `server error: ${JSON.stringify(msg.error).slice(0, 120)}`);
        }
      } catch { /* keep buffering */ }
    });
    child.on('error', (e) => { clearTimeout(timer); done('WARN', e.message); });
    child.on('exit', (code) => {
      clearTimeout(timer);
      if (!settled) done('WARN', `thoat som (code ${code})`);
    });
    try {
      child.stdin.write(`${JSON.stringify({
        jsonrpc: '2.0', id: 1, method: 'initialize',
        params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'setup-agent-code', version: '1' } }
      })}\n`);
    } catch { /* handled by error event */ }
  });
}

export function summarize(rows) {
  const counts = { PASS: 0, WARN: 0, FAIL: 0, SKIP: 0 };
  for (const row of rows) counts[row.status] = (counts[row.status] || 0) + 1;
  return counts;
}

export function formatTable(rows) {
  const width = Math.max(...rows.map((r) => r.check.length), 20);
  return rows.map((r) => `  ${r.status.padEnd(5)} ${r.check.padEnd(width)}  ${r.detail}`).join('\n');
}

export function fileSize(file) {
  try { return fs.statSync(file).size; } catch { return 0; }
}
