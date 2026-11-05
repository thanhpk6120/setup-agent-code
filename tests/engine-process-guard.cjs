'use strict';

// Test-only preload: no real process may be spawned while the engine runs.
// Tool discovery and version probes are answered from a fixed fake table so the
// engine can complete a configure-only run without touching the host.
const childProcess = require('node:child_process');
const { EventEmitter } = require('node:events');
const { syncBuiltinESMExports } = require('node:module');
const path = require('node:path');

const FAKE_VERSION = '99.0.0';
// Tools whose manifest pin would otherwise fail with a generic fake version.
const FAKE_VERSION_BY_TOOL = { 'mcp-atlassian': '0.23.1' };
const FAKE_BIN_DIR = path.join(process.env.HOME || process.env.USERPROFILE || '.', 'fake-bin');
const FAKE_TOOLS = new Set([
  'node', 'npm', 'npx', 'pnpm', 'uv', 'git', 'winget', 'brew',
  'mcp-atlassian', 'memorix', 'gitnexus', 'context7', 'cloakbrowser', 'agency-mcp-server',
  'omp', 'claude', 'opencode', 'codex', 'dsh', 'agy', 'cc-safety-net'
]);

const ok = (stdout) => ({ status: 0, stdout, stderr: '' });
const denied = (command) => ({ status: 1, stdout: '', stderr: `subprocess blocked by test: ${command}` });

childProcess.spawnSync = (command, args = []) => {
  const invocation = [command, ...args].join(' ');
  if (command === 'which' || command === 'where') {
    return FAKE_TOOLS.has(args[0]) ? ok(`${path.join(FAKE_BIN_DIR, args[0])}\n`) : denied(command);
  }
  // Windows .cmd/.bat shims are wrapped as: cmd.exe /d /s /c "<abs shim>" <args>
  if (/cc-safety-net(\.cmd)?["\s]+status/i.test(invocation)) return ok('');
  if (path.dirname(String(command)) === FAKE_BIN_DIR) {
    const tool = path.basename(String(command));
    const argv = args.join(' ');
    if (argv === '--version' || argv === '-v' || argv === '--v') return ok(`${FAKE_VERSION_BY_TOOL[tool] || FAKE_VERSION}\n`);
    if (tool === 'cc-safety-net' && argv === 'status') return ok('');
    if (tool === 'npm' && (argv === 'prefix -g' || argv === 'root -g')) return ok(`${path.join(FAKE_BIN_DIR, 'npm-root')}\n`);
    return denied(command);
  }
  if (/cc-safety-net/.test(String(command)) && args.includes('status')) return ok('');
  return denied(command);
};

const blockedAsync = (command) => {
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { write() {}, end() {} };
  child.kill = () => {};
  process.nextTick(() => child.emit('error', new Error(`subprocess blocked by test: ${command}`)));
  return child;
};
const blockedSync = (command) => { throw new Error(`subprocess blocked by test: ${command}`); };

childProcess.spawn = blockedAsync;
childProcess.exec = blockedAsync;
childProcess.fork = blockedAsync;
childProcess.execFile = (command) => blockedAsync(command);
childProcess.execSync = blockedSync;
childProcess.execFileSync = blockedSync;
syncBuiltinESMExports();
