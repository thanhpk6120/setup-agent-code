// core/lib/util.mjs - shared plumbing for the setup engine.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import readline from 'node:readline';
import { spawnSync } from 'node:child_process';

export const isWin = process.platform === 'win32';
export const isMac = process.platform === 'darwin';
export const osKey = isWin ? 'win' : 'unix';

const COLORS = {
  reset: '\u001b[0m', red: '\u001b[31m', green: '\u001b[32m', yellow: '\u001b[33m',
  cyan: '\u001b[36m', gray: '\u001b[90m', bold: '\u001b[1m'
};

export const log = {
  quiet: false,
  verbose: false,
  info(msg) { if (!this.quiet) console.log(msg); },
  phase(id, title) { if (!this.quiet) console.log(`\n${COLORS.cyan}== [${id}] ${title}${COLORS.reset}`); },
  ok(msg) { if (!this.quiet) console.log(`  ${COLORS.green}-> ${msg}${COLORS.reset}`); },
  skip(msg) { if (!this.quiet) console.log(`  ${COLORS.gray}-> [Skip] ${msg}${COLORS.reset}`); },
  warn(msg) { (this.quiet ? console.error : console.log)(`  ${COLORS.yellow}[!] ${msg}${COLORS.reset}`); },
  error(msg) { console.error(`  ${COLORS.red}[X] ${msg}${COLORS.reset}`); },
  debug(msg) { if (this.verbose && !this.quiet) console.log(`  ${COLORS.gray}... ${msg}${COLORS.reset}`); }
};

/** Expand %VAR% (Windows), ~ and environment variables in a manifest path. */
export function expand(rawPath, env = process.env) {
  if (!rawPath) return '';
  let out = String(rawPath);
  out = out.replace(/%([A-Za-z_][A-Za-z0-9_]*)%/g, (_, name) => env[name] ?? '');
  out = out.replace(/^~(?=$|[\\/])/, os.homedir());
  return path.normalize(out);
}

export function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

export function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

export function writeFileAtomic(file, content) {
  ensureDir(path.dirname(file));
  const tmp = `${file}.tmp-${process.pid}`;
  fs.writeFileSync(tmp, content, 'utf8');
  fs.renameSync(tmp, file);
}

export function exists(p) {
  try { fs.accessSync(p); return true; } catch { return false; }
}

/** Timestamp used for .bak files: YYYYMMDD-HHmmss */
export function stamp(d = new Date()) {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

/** Copy target to <target>.bak.<stamp> before overwriting. Returns backup path or null. */
export function backupFile(target, dryRun = false) {
  if (!exists(target)) return null;
  const bak = `${target}.bak.${stamp()}`;
  if (dryRun) { log.debug(`[dry-run] backup ${target} -> ${bak}`); return bak; }
  fs.copyFileSync(target, bak);
  log.debug(`backup: ${bak}`);
  return bak;
}

/** Move a file or directory to the OS trash. Never permanently deletes. */
export function trash(target, dryRun = false) {
  if (!exists(target)) return true;
  if (dryRun) { log.debug(`[dry-run] trash ${target}`); return true; }
  if (isWin) {
    const isDir = fs.statSync(target).isDirectory();
    const method = isDir ? 'DeleteDirectory' : 'DeleteFile';
    const escaped = target.replace(/'/g, "''");
    const script = [
      'Add-Type -AssemblyName Microsoft.VisualBasic',
      `[Microsoft.VisualBasic.FileIO.FileSystem]::${method}('${escaped}',` +
      `[Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,` +
      `[Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)`
    ].join('; ');
    const r = spawnSync('powershell', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8' });
    if (r.status !== 0) {
      log.warn(`Khong chuyen duoc vao Recycle Bin: ${target} (${(r.stderr || '').trim()})`);
      return false;
    }
    log.debug(`trash: ${target}`);
    return true;
  }
  const trashDir = path.join(os.homedir(), '.Trash');
  ensureDir(trashDir);
  const dest = path.join(trashDir, `${path.basename(target)}.${Date.now()}`);
  fs.renameSync(target, dest);
  log.debug(`trash: ${target} -> ${dest}`);
  return true;
}

export function which(cmd) {
  const finder = isWin ? 'where' : 'which';
  const r = spawnSync(finder, [cmd], { encoding: 'utf8' });
  if (r.status !== 0) return null;
  const results = (r.stdout || '').split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
  if (!results.length) return null;
  if (isWin) {
    const prefer = ['.exe', '.cmd', '.bat', '.ps1'];
    for (const ext of prefer) {
      const match = results.find((item) => item.toLowerCase().endsWith(ext));
      if (match) return match;
    }
  }
  return results[0];
}

export function versionOf(cmd, args = ['--version'], timeout = 15000) {
  try {
    const bin = which(cmd) || cmd;
    const { file, argv } = spawnAdapter(bin, args);
    const r = spawnSync(file, argv, { encoding: 'utf8', timeout, windowsHide: true });
    if (r.error || r.status !== 0) return '';
    const out = `${r.stdout || ''} ${r.stderr || ''}`.trim();
    const m = out.match(/\d+\.\d+\.\d+/);
    return m ? m[0] : (out ? out.split(/\r?\n/)[0].slice(0, 60) : '');
  } catch { return ''; }
}

/** Windows cannot execute .cmd/.bat without cmd.exe; wrap explicitly instead of shell:true. */
function spawnAdapter(cmd, args) {
  if (isWin && /\.(cmd|bat)$/i.test(cmd)) {
    const quoted = [cmd, ...args].map((item) => {
      const text = String(item);
      return /[\s"]/.test(text) ? `"${text.replace(/"/g, '\\"')}"` : text;
    });
    return { file: process.env.ComSpec || 'cmd.exe', argv: ['/d', '/s', '/c', quoted.join(' ')] };
  }
  return { file: cmd, argv: args };
}

export function run(cmd, args = [], opts = {}) {
  const { timeout = 600000, allowFail = false, capture = true, env = process.env, cwd } = opts;
  // Bare names must be resolved first: on Windows spawnSync cannot execute `npm`/`npx`
  // (they are .cmd shims), and it fails with ENOENT instead of finding them on PATH.
  const resolved = /[\\/]/.test(cmd) ? cmd : (which(cmd) || cmd);
  log.debug(`run: ${resolved} ${args.join(' ')}`);
  const { file, argv } = spawnAdapter(resolved, args);
  const r = spawnSync(file, argv, {
    encoding: 'utf8',
    timeout,
    cwd,
    env,
    windowsHide: true,
    stdio: capture ? 'pipe' : 'inherit'
  });
  if (r.error) {
    if (!allowFail) log.debug(`spawn error: ${r.error.message}`);
    return { ok: false, status: -1, stdout: '', stderr: r.error.message };
  }
  const ok = r.status === 0;
  if (!ok && !allowFail) log.debug(`exit ${r.status}: ${(r.stderr || '').slice(0, 400)}`);
  return { ok, status: r.status ?? -1, stdout: r.stdout || '', stderr: r.stderr || '' };
}

export function npmGlobalRoot() {
  const r = run('npm', ['root', '-g'], { allowFail: true, timeout: 20000 });
  return r.ok ? r.stdout.trim() : '';
}

export function resolveNpmPath(relative) {
  const root = npmGlobalRoot();
  return root ? path.join(root, ...relative.split('/')) : '';
}

/** Version compare for x.y.z strings. Returns true when a >= b. */
export function versionGte(a, b) {
  const pa = String(a).match(/\d+\.\d+\.\d+/);
  const pb = String(b).match(/\d+\.\d+\.\d+/);
  if (!pa || !pb) return false;
  const A = pa[0].split('.').map(Number);
  const B = pb[0].split('.').map(Number);
  for (let i = 0; i < 3; i += 1) {
    if (A[i] > B[i]) return true;
    if (A[i] < B[i]) return false;
  }
  return true;
}

export function readText(file) {
  return fs.readFileSync(file, 'utf8');
}

export function listDirs(dir) {
  if (!exists(dir)) return [];
  return fs.readdirSync(dir, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name);
}

export function copyDir(src, dest, { filter } = {}) {
  ensureDir(dest);
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const from = path.join(src, entry.name);
    const to = path.join(dest, entry.name);
    if (filter && !filter(entry.name, from)) continue;
    if (entry.isDirectory()) copyDir(from, to, { filter });
    else { ensureDir(path.dirname(to)); fs.copyFileSync(from, to); }
  }
}

export function parseEnvFile(file) {
  const vars = {};
  if (!exists(file)) return vars;
  for (const raw of readText(file).split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const idx = line.indexOf('=');
    if (idx <= 0) continue;
    const key = line.slice(0, idx).trim();
    let value = line.slice(idx + 1).trim();
    // Strip an inline comment only when the value is not quoted.
    if (!/^["']/.test(value)) value = value.replace(/\s+#.*$/, '');
    value = value.replace(/^["'](.*)["']$/, '$1');
    if (key) vars[key] = value;
  }
  return vars;
}

export function saveEnvValue(file, key, value) {
  ensureDir(path.dirname(file));
  const current = exists(file) ? readText(file) : '';
  const lines = current ? current.split(/\r?\n/).filter((l) => l && !l.startsWith(`${key}=`)) : [];
  lines.push(`${key}=${value}`);
  writeFileAtomic(file, `${lines.join('\n')}\n`);
}

export function tty() {
  return Boolean(process.stdin.isTTY && process.stdout.isTTY);
}

export function createPrompt(options) {
  const rl = tty() ? readline.createInterface({ input: process.stdin, output: process.stdout }) : null;
  async function ask(question) {
    if (!rl) return '';
    return new Promise((resolve) => rl.question(question, (answer) => resolve(answer)));
  }
  function close() { if (rl) rl.close(); }
  return { ask, close, interactive: Boolean(rl) && !options.yes };
}

export function mask(value) {
  return value ? '***' : '';
}
