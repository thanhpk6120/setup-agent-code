#!/usr/bin/env node
// Smart Memorix MCP stdio wrapper:
// 1. Probes local `memorix serve-http` (default: http://127.0.0.1:3211/mcp).
// 2. If reachable, bridges MCP stdio <-> sessionful Streamable HTTP (`Mcp-Session-Id`
//    + `Mcp-Project-Root: <cwd>`) so all agents share one control plane without SQLite locks.
// 3. Otherwise, transparently spawns `memorix serve ...` on stdio as fallback.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import net from 'node:net';
import path from 'node:path';
import readline from 'node:readline';

const DEFAULT_HTTP_URL = process.env.MEMORIX_HTTP_URL || 'http://127.0.0.1:3211/mcp';

function parseCliArgs(argv) {
  let fallbackBin = process.env.MEMORIX_FALLBACK_BIN || 'memorix';
  const passArgs = [];
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--bin' && argv[i + 1]) {
      fallbackBin = argv[++i];
    } else {
      passArgs.push(argv[i]);
    }
  }
  return { fallbackBin, passArgs };
}

function probeTcp(host, port, timeoutMs = 250) {
  return new Promise((resolve) => {
    const socket = net.createConnection({ host, port });
    let settled = false;
    const done = (ok) => {
      if (settled) return;
      settled = true;
      socket.destroy();
      resolve(ok);
    };
    socket.setTimeout(timeoutMs);
    socket.once('connect', () => done(true));
    socket.once('timeout', () => done(false));
    socket.once('error', () => done(false));
  });
}

function resolveFallbackBin(bin) {
  const hasSep = /[\\/]/.test(bin);
  if (!hasSep || fs.existsSync(bin)) return bin;
  const base = path.basename(bin);
  let realDir = path.dirname(process.execPath);
  try { realDir = path.dirname(fs.realpathSync(process.execPath)); } catch {}
  const sibling = path.join(realDir, base);
  if (fs.existsSync(sibling)) return sibling;
  return base;
}

function runFallbackStdio(rawBin, args) {
  const bin = resolveFallbackBin(rawBin);
  const isWinCmd = process.platform === 'win32' && (/\.(cmd|bat)$/i.test(bin) || !/[\\/]/.test(bin));
  const child = isWinCmd
    ? spawn(process.env.ComSpec || 'cmd.exe', ['/d', '/c', bin, ...args], { stdio: 'inherit' })
    : spawn(bin, args, { stdio: 'inherit' });

  child.on('error', (err) => {
    process.stderr.write(`[memorix-wrapper] Failed to start fallback (${bin}): ${err.message}\n`);
    process.exit(1);
  });
  child.on('exit', (code, signal) => {
    if (signal) process.kill(process.pid, signal);
    process.exit(code ?? 0);
  });
}

function writeJsonLine(obj) {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
}

function normalizeResponse(obj, reqMsg) {
  if (
    reqMsg &&
    reqMsg.method === 'initialize' &&
    typeof reqMsg.params?.protocolVersion === 'string' &&
    obj &&
    obj.id === reqMsg.id &&
    obj.result &&
    typeof obj.result.protocolVersion === 'string' &&
    obj.result.protocolVersion !== reqMsg.params.protocolVersion
  ) {
    obj.result.protocolVersion = reqMsg.params.protocolVersion;
  }
  return obj;
}

async function emitSseMessages(bodyStream, reqMsg, onNegotiated) {
  const reader = bodyStream.getReader();
  const decoder = new TextDecoder();
  let buf = '';
  let dataLines = [];

  const flushEvent = () => {
    if (dataLines.length === 0) return;
    const raw = dataLines.join('\n').trim();
    dataLines = [];
    if (!raw || raw === '[DONE]') return;
    try {
      const parsed = JSON.parse(raw);
      if (reqMsg?.method === 'initialize' && parsed?.result?.protocolVersion && typeof onNegotiated === 'function') {
        onNegotiated(parsed.result.protocolVersion);
      }
      writeJsonLine(normalizeResponse(parsed, reqMsg));
    } catch {
      // Ignore non-JSON SSE comments/heartbeats
    }
  };

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream: true });
    let nlIdx;
    while ((nlIdx = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, nlIdx).replace(/\r$/, '');
      buf = buf.slice(nlIdx + 1);
      if (line === '') {
        flushEvent();
      } else if (line.startsWith('data:')) {
        dataLines.push(line.slice(5).trimStart());
      }
    }
  }
  if (buf.trim().startsWith('data:')) {
    dataLines.push(buf.trim().slice(5).trimStart());
  }
  flushEvent();
}

async function runHttpBridge(httpUrl) {
  const projectRoot = process.cwd();
  let projectHandle = '';
  let sessionId = '';
  let negotiatedProtocol = '';
  process.stderr.write(`[memorix-wrapper] Using shared HTTP control plane: ${httpUrl} (cwd: ${projectRoot})\n`);

  const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  const ac = new AbortController();
  const inFlight = new Set();
  let initGate = Promise.resolve();

  const forwardMessage = async (msg, rawBody) => {
    if (msg.method === 'initialize') {
      sessionId = '';
      negotiatedProtocol = '';
    }

    const headers = {
      'Content-Type': 'application/json',
      Accept: 'application/json, text/event-stream',
      'Mcp-Project-Root': projectRoot
    };
    const metaProto = msg?.params?._meta?.['io.modelcontextprotocol/protocolVersion'];
    const protoHeader = typeof metaProto === 'string' && metaProto
      ? metaProto
      : (msg.method !== 'initialize' ? negotiatedProtocol : '');
    if (protoHeader) {
      headers['MCP-Protocol-Version'] = protoHeader;
      if (msg.method) headers['Mcp-Method'] = msg.method;
      if (typeof msg?.params?.name === 'string' && msg.params.name) {
        headers['Mcp-Name'] = msg.params.name;
      }
    }
    if (projectHandle) headers['Mcp-Project-Handle'] = projectHandle;
    if (sessionId) headers['Mcp-Session-Id'] = sessionId;
    if (process.env.MEMORIX_HTTP_AUTH_TOKEN) {
      headers.Authorization = `Bearer ${process.env.MEMORIX_HTTP_AUTH_TOKEN}`;
    }

    let res;
    try {
      res = await fetch(httpUrl, {
        method: 'POST',
        headers,
        body: rawBody,
        signal: ac.signal
      });

      const nextHandle = res.headers.get('mcp-project-handle');
      if (nextHandle) projectHandle = nextHandle;
      const nextSid = res.headers.get('mcp-session-id');
      if (res.ok && nextSid) sessionId = nextSid;

      if (res.status === 202 || res.status === 204) {
        await res.body?.cancel?.();
        return;
      }

      const ct = (res.headers.get('content-type') || '').toLowerCase();
      if (ct.includes('text/event-stream') && res.body) {
        await emitSseMessages(res.body, msg, (proto) => { negotiatedProtocol = proto; });
        return;
      }

      const text = await res.text();
      if (!text.trim()) {
        if (!res.ok && msg && msg.id !== undefined && msg.id !== null) {
          writeJsonLine({
            jsonrpc: '2.0',
            id: msg.id,
            error: { code: -32000, message: `Memorix HTTP error ${res.status}` }
          });
        }
        return;
      }

      try {
        const payload = JSON.parse(text);
        if (Array.isArray(payload)) {
          for (const item of payload) {
            if (msg.method === 'initialize' && item?.result?.protocolVersion) {
              negotiatedProtocol = item.result.protocolVersion;
            }
            writeJsonLine(normalizeResponse(item, msg));
          }
        } else {
          if (msg.method === 'initialize' && payload?.result?.protocolVersion) {
            negotiatedProtocol = payload.result.protocolVersion;
          }
          writeJsonLine(normalizeResponse(payload, msg));
        }
      } catch {
        if (msg && msg.id !== undefined && msg.id !== null) {
          writeJsonLine({
            jsonrpc: '2.0',
            id: msg.id,
            error: { code: -32000, message: `Invalid JSON from Memorix HTTP (${res.status}): ${text.slice(0, 200)}` }
          });
        }
      }
    } catch (err) {
      if (ac.signal.aborted) return;
      if (msg && msg.id !== undefined && msg.id !== null) {
        writeJsonLine({
          jsonrpc: '2.0',
          id: msg.id,
          error: { code: -32000, message: `Memorix HTTP bridge error: ${err.message}` }
        });
      }
    }
  };

  rl.on('line', (line) => {
    const trimmed = line.trim();
    if (!trimmed) return;
    let msg;
    try {
      msg = JSON.parse(trimmed);
    } catch {
      return;
    }

    if (msg.method === 'initialize') {
      const p = initGate.then(() => forwardMessage(msg, trimmed)).catch((err) => {
        process.stderr.write(`[memorix-wrapper] Init error: ${err instanceof Error ? err.message : String(err)}\n`);
      });
      initGate = p;
      inFlight.add(p);
      p.finally(() => inFlight.delete(p));
    } else {
      // Run non-init requests concurrently after initGate so long-lived streams
      // like `subscriptions/listen` never block subsequent requests.
      const p = initGate.then(() => forwardMessage(msg, trimmed)).catch((err) => {
        process.stderr.write(`[memorix-wrapper] Request error: ${err instanceof Error ? err.message : String(err)}\n`);
      });
      inFlight.add(p);
      p.finally(() => inFlight.delete(p));
    }
  });

  await new Promise((resolve) => {
    rl.once('close', () => {
      ac.abort();
      Promise.allSettled([...inFlight]).finally(resolve);
    });
  });
}

async function main() {
  const { fallbackBin, passArgs } = parseCliArgs(process.argv.slice(2));
  const preferHttp = process.env.MEMORIX_PREFER_HTTP !== '0';

  if (preferHttp) {
    try {
      const url = new URL(DEFAULT_HTTP_URL);
      const port = Number(url.port || (url.protocol === 'https:' ? 443 : 80));
      const host = (url.hostname || '127.0.0.1').replace(/^\[|\]$/g, '');
      if (await probeTcp(host, port, 250)) {
        await runHttpBridge(url.toString());
        return;
      }
    } catch {
      // Invalid URL -> fall back to stdio
    }
  }

  runFallbackStdio(fallbackBin, passArgs.length > 0 ? passArgs : ['serve', '--mode', 'lite']);
}

main();
