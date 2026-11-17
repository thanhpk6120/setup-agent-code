import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as M from '../core/lib/manifest.mjs';
import * as U from '../core/lib/util.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const WRAPPER = path.join(ROOT, 'templates', 'hooks', 'memorix-mcp-wrapper.mjs');

test('manifest builds memorix spec using memorix-mcp-wrapper.mjs', () => {
  const manifests = M.loadManifests(ROOT);
  const memorix = manifests.mcp.servers.find((s) => s.id === 'memorix');
  assert.ok(memorix);
  const spec = M.buildServerSpec(memorix, {
    bin: (name) => (name === 'memorix' ? '/usr/local/bin/memorix' : null),
    npmPath: () => null,
    cloakbrowser: '/tmp/cloak.mjs',
    memorixWrapper: '/tmp/memorix-mcp-wrapper.mjs'
  });
  assert.equal(spec.command, 'node');
  assert.deepEqual(spec.args, [
    '/tmp/memorix-mcp-wrapper.mjs',
    '--bin',
    '/usr/local/bin/memorix',
    'serve',
    '--mode',
    'lite'
  ]);
  const resolved = U.resolveStableBin('memorix');
  assert.doesNotMatch(resolved, /fnm_multishells/i);
  const npmP = U.resolveNpmPath('@upstash/context7-mcp/dist/index.js');
  if (npmP) assert.doesNotMatch(npmP, /fnm_multishells/i);
});

test('memorix-mcp-wrapper bridges stdio to HTTP when server is reachable (JSON, SSE, 202, 500)', async () => {
  const seen = [];
  const server = http.createServer((req, res) => {
    let body = '';
    req.on('data', (c) => { body += c; });
    req.on('end', () => {
      const msg = JSON.parse(body);
      seen.push({ method: msg.method, headers: req.headers });
      if (msg.method === 'notifications/initialized') {
        res.writeHead(202);
        res.end();
        return;
      }
      if (msg.method === 'tools/list') {
        res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Mcp-Session-Id': 'sid-1' });
        res.write(`data: ${JSON.stringify({ jsonrpc: '2.0', id: msg.id, result: { tools: [{ name: 'memorix_store' }] } })}\n\n`);
        res.end();
        return;
      }
      if (msg.method === 'fail/empty') {
        res.writeHead(500);
        res.end();
        return;
      }
      res.writeHead(200, { 'Content-Type': 'application/json', 'Mcp-Session-Id': 'sid-1' });
      res.end(JSON.stringify({ jsonrpc: '2.0', id: msg.id, result: { ok: true } }));
    });
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();

  try {
    const child = spawn(process.execPath, [WRAPPER, 'serve', '--mode', 'lite'], {
      env: { ...process.env, MEMORIX_HTTP_URL: `http://127.0.0.1:${port}/mcp` },
      stdio: ['pipe', 'pipe', 'pipe']
    });
    const lines = await new Promise((resolve, reject) => {
      let out = '';
      const timer = setTimeout(() => { child.kill(); reject(new Error(`timeout: ${out}`)); }, 5000);
      child.stdout.on('data', (d) => {
        out += d.toString();
        const parsed = out.split(/\r?\n/).filter(Boolean);
        if (parsed.length >= 3) {
          clearTimeout(timer);
          child.kill();
          resolve(parsed.map((l) => JSON.parse(l)));
        }
      });
      child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: {} }) + '\n');
      child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
      child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} }) + '\n');
      child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: 3, method: 'fail/empty', params: {} }) + '\n');
    });

    assert.equal(lines[0].id, 1);
    assert.equal(lines[0].result.ok, true);
    assert.equal(lines[1].id, 2);
    assert.equal(lines[1].result.tools[0].name, 'memorix_store');
    assert.equal(lines[2].id, 3);
    assert.match(lines[2].error.message, /HTTP error 500/);
    assert.equal(seen[1].headers['mcp-session-id'], 'sid-1');
    assert.ok(seen[0].headers['mcp-project-root']);
  } finally {
    server.close();
  }
});

test('memorix-mcp-wrapper falls back to stdio binary when HTTP port is unreachable', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'memorix-fb-'));
  const fakeBin = path.join(dir, process.platform === 'win32' ? 'fake-memorix.cmd' : 'fake-memorix.sh');
  const script = path.join(dir, 'echo-mcp.mjs');
  fs.writeFileSync(script, 'process.stdin.once("data", (d) => { const m = JSON.parse(d.toString()); process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id: m.id, result: { fallback: process.argv.slice(2) } }) + "\\n"); });\n', 'utf8');
  if (process.platform === 'win32') {
    fs.writeFileSync(fakeBin, `@echo off\r\n"${process.execPath}" "${script}" %*\r\n`, 'utf8');
  } else {
    fs.writeFileSync(fakeBin, `#!/bin/sh\nexec "${process.execPath}" "${script}" "$@"\n`, 'utf8');
    fs.chmodSync(fakeBin, 0o755);
  }

  try {
    const child = spawn(process.execPath, [WRAPPER, '--bin', fakeBin, 'serve', '--mode', 'lite'], {
      env: { ...process.env, MEMORIX_HTTP_URL: 'http://127.0.0.1:1/mcp' },
      stdio: ['pipe', 'pipe', 'pipe']
    });
    const res = await new Promise((resolve, reject) => {
      let out = '';
      const timer = setTimeout(() => { child.kill(); reject(new Error('fallback timeout')); }, 5000);
      child.stdout.on('data', (d) => {
        out += d.toString();
        if (out.includes('\n')) {
          clearTimeout(timer);
          child.kill();
          resolve(JSON.parse(out.trim()));
        }
      });
      child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: 9, method: 'initialize' }) + '\n');
    });
    assert.equal(res.id, 9);
    assert.deepEqual(res.result.fallback, ['serve', '--mode', 'lite']);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('memorix-mcp-wrapper gracefully falls back when --bin points to a stale/missing path', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'memorix-stale-'));
  const binDir = path.join(dir, 'bin');
  fs.mkdirSync(binDir, { recursive: true });
  const binName = process.platform === 'win32' ? 'fake-memorix.cmd' : 'fake-memorix';
  const pathBin = path.join(binDir, binName);
  const script = path.join(dir, 'echo-mcp.mjs');
  fs.writeFileSync(script, 'process.stdin.once("data", (d) => { const m = JSON.parse(d.toString()); process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id: m.id, result: { via: "path" } }) + "\\n"); });\n', 'utf8');
  if (process.platform === 'win32') {
    fs.writeFileSync(pathBin, `@echo off\r\n"${process.execPath}" "${script}" %*\r\n`, 'utf8');
  } else {
    fs.writeFileSync(pathBin, `#!/bin/sh\nexec "${process.execPath}" "${script}" "$@"\n`, 'utf8');
    fs.chmodSync(pathBin, 0o755);
  }

  try {
    const stalePath = path.join(dir, 'fnm_multishells', '12345', binName);
    const child = spawn(process.execPath, [WRAPPER, '--bin', stalePath, 'serve', '--mode', 'lite'], {
      env: { ...process.env, MEMORIX_HTTP_URL: 'http://127.0.0.1:1/mcp', PATH: `${binDir}${path.delimiter}${process.env.PATH || ''}` },
      stdio: ['pipe', 'pipe', 'pipe']
    });
    const res = await new Promise((resolve, reject) => {
      let out = '';
      const timer = setTimeout(() => { child.kill(); reject(new Error('stale fallback timeout')); }, 5000);
      child.stdout.on('data', (d) => {
        out += d.toString();
        if (out.includes('\n')) {
          clearTimeout(timer);
          child.kill();
          resolve(JSON.parse(out.trim()));
        }
      });
      child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: 10, method: 'initialize' }) + '\n');
    });
    assert.equal(res.id, 10);
    assert.equal(res.result.via, 'path');
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
