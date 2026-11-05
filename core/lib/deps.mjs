// core/lib/deps.mjs - prerequisite consent, installation, verification and PATH setup.
//
// Rule: never install a dependency silently. Ask -> install -> verify -> if it fails,
// give the user a concrete resolution path (guidance), and block only the MCP servers
// that actually need that dependency.
import path from 'node:path';
import fs from 'node:fs';
import os from 'node:os';
import {
  exists, isWin, log, osKey, readJson, run, versionGte, versionOf, which
} from './util.mjs';

let cached = null;

export function loadPrerequisites(root) {
  if (!cached) cached = readJson(path.join(root, 'manifest', 'prerequisites.json'));
  return cached;
}

export function resetCache() { cached = null; }

function normalizeVersion(value) {
  const match = String(value || '').match(/\d+\.\d+\.\d+/);
  return match ? match[0] : '';
}

/**
 * Assess one command without changing anything.
 * state: ok | missing | outdated | mismatch | broken
 */
export function assessCommand(cmd, args = ['--version'], { version, minVersion } = {}) {
  if (!cmd) return { state: 'missing', detail: 'khong khai bao command' };
  const bin = which(cmd);
  if (!bin) return { state: 'missing', detail: `khong tim thay '${cmd}' trong PATH` };
  const installedRaw = versionOf(cmd, args);
  const installed = normalizeVersion(installedRaw);
  if (!installed) {
    return { state: 'broken', detail: `'${cmd}' co trong PATH nhung khong chay duoc (${args.join(' ')})`, bin };
  }
  if (version && installed !== normalizeVersion(version)) {
    return { state: 'mismatch', detail: `${cmd} v${installed} != yeu cau v${normalizeVersion(version)}`, bin, version: installed };
  }
  if (minVersion && !versionGte(installed, minVersion)) {
    return { state: 'outdated', detail: `${cmd} v${installed} < ${minVersion}`, bin, version: installed };
  }
  return { state: 'ok', detail: `${bin} (v${installed})`, bin, version: installed };
}

/** Assess a manifest `verify` block (command or file based). */
export function assessVerify(verify, resolveFile = (value) => value) {
  if (!verify) return { state: 'missing', detail: 'khong co verify' };
  if (verify.file) {
    const file = resolveFile(verify.file);
    return exists(file)
      ? { state: 'ok', detail: file }
      : { state: 'missing', detail: `thieu file ${file}` };
  }
  return assessCommand(verify.cmd, verify.args || ['--version'], {
    version: verify.version,
    minVersion: verify.minVersion
  });
}

export function depStatus(dep) {
  // Test-only hook so CI can exercise the "missing dependency" flow deterministically.
  if ((process.env.SETUP_TEST_MISSING_DEPS || '').split(',').map((s) => s.trim()).includes(dep.id)) {
    return { present: false, state: 'missing', detail: `[test] gia lap thieu ${dep.id}` };
  }
  const assess = assessVerify(dep.verify);
  return { present: assess.state === 'ok', ...assess };
}

export function guidanceOf(dep) {
  return (dep.guidance || []).map((line) => `      - ${line}`).join('\n');
}

function evalWhen(condition) {
  if (!condition) return true;
  return condition.split('&&').every((part) => {
    const token = part.trim();
    if (!token) return true;
    if (token.startsWith('!')) return !which(token.slice(1).trim());
    return Boolean(which(token));
  });
}

function runAction(action) {
  if (action.type === 'powershell') {
    return run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', action.script], { allowFail: true }).ok;
  }
  if (action.type === 'shell') {
    return run('bash', ['-lc', action.script], { allowFail: true }).ok;
  }
  if (action.cmd) {
    const bin = which(action.cmd) || action.cmd;
    return run(bin, action.args || [], { allowFail: true }).ok;
  }
  return false;
}

/** Consent gate used by every install action that is not the explicitly selected target. */
export async function askConsent(ctx, question, defaultYes = true) {
  if (process.env.SETUP_TEST_DECLINE_DEPS === '1') return false; // test-only
  if (ctx.mode !== 'install') return false;
  if (ctx.opts['skip-install']) return false;
  if (ctx.opts.force || ctx.opts.yes) return true;
  if (!ctx.interactive) return false;
  const answer = await ctx.prompt.ask(question);
  if (!answer) return defaultYes;
  return /^y/i.test(answer);
}

/**
 * Ensure one declared dependency.
 * Returns { status: 'present'|'installed'|'skipped'|'declined'|'failed', detail, guidance }
 */
export async function ensureDependency(dep, ctx, { requiredBy = [] } = {}) {
  const before = depStatus(dep);
  if (before.present) {
    log.ok(`${dep.id}: ${before.detail}`);
    return { status: 'present', detail: before.detail };
  }

  const stateLabel = {
    missing: 'chua cai',
    outdated: 'version cu',
    mismatch: 'sai version',
    broken: 'cai dat hong'
  }[before.state] || 'khong dat yeu cau';
  const consumers = requiredBy.length ? ` (can cho: ${requiredBy.join(', ')})` : '';

  if (ctx.opts['skip-install'] || ctx.mode !== 'install') {
    log.warn(`${dep.label || dep.id}: ${before.detail} [${stateLabel}]${consumers}. Che do chi-cau-hinh: khong cai dat.`);
    return { status: 'skipped', detail: 'che do chi-cau-hinh', state: before.state, guidance: dep.guidance || [] };
  }

  log.warn(`${dep.label || dep.id}: ${before.detail} [${stateLabel}]${consumers}.`);
  if (dep.why) log.info(`    Ly do: ${dep.why}`);
  const question = before.state === 'missing'
    ? `[?] Cai ${dep.label || dep.id}? [Y/n]: `
    : `[?] ${dep.label || dep.id} hien khong phu hop (${stateLabel}). Cai lai/cap nhat? [Y/n]: `;
  const consent = await askConsent(ctx, question, true);
  if (!consent) {
    log.warn(`Khong cai lai ${dep.id} (nguoi dung tu choi hoac non-interactive).`);
    log.info('    Huong xu ly:');
    log.info(guidanceOf(dep));
    return { status: 'declined', detail: `nguoi dung tu choi (${stateLabel})`, state: before.state, guidance: dep.guidance || [] };
  }

  const maxAttempts = ctx.interactive ? 3 : 1;
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    log.info(`  -> Cai ${dep.id} (lan ${attempt}/${maxAttempts})...`);
    for (const action of dep.install?.[osKey] || []) {
      if (!evalWhen(action.when)) continue;
      const installed = runAction(action);
      refreshPath();
      if (!isWin && installed && dep.id === 'uv' && !depStatus(dep).present) {
        const requirement = { id: 'uv-tool-bin', label: 'uv', resolve: 'uv-tool-bin' };
        const dir = resolvePathRequirement(requirement);
        if (dir && fileExists(path.join(dir, 'uv'))) await ensurePathRequirements(ctx, [requirement]);
      }
      if (depStatus(dep).present) break;
    }
    const after = depStatus(dep);
    if (after.present) {
      log.ok(`${dep.id} da cai thanh cong: ${after.detail}`);
      return { status: 'installed', detail: after.detail };
    }
    log.error(`Cai ${dep.id} khong thanh cong.`);
    log.info('    Huong xu ly:');
    log.info(guidanceOf(dep));
    if (!ctx.interactive || attempt === maxAttempts) break;
    const answer = await ctx.prompt.ask('[?] Thu lai [r] / Bo qua [s]? [s]: ');
    if (!/^r/i.test(answer)) break;
  }
  return { status: 'failed', detail: 'cai dat that bai', guidance: dep.guidance || [] };
}

const seenPath = new Set();
/** Do not import registry PATH entries without consent for each directory. */
export function refreshPath() {}

function mergePath(dirs) {
  const current = (process.env.PATH || '').split(path.delimiter).filter(Boolean);
  const seen = new Set(current.map((entry) => entry.toLowerCase()));
  for (const dir of dirs) {
    const value = (dir || '').trim();
    if (!value || !exists(value)) continue;
    if (seen.has(value.toLowerCase())) continue;
    current.push(value);
    seen.add(value.toLowerCase());
  }
  process.env.PATH = current.join(path.delimiter);
}

export function resolvePathRequirement(requirement) {
  if (requirement.resolve === 'npm-prefix-bin') {
    const result = run('npm', ['prefix', '-g'], { allowFail: true, timeout: 20000 });
    if (!result.ok) return '';
    const prefix = result.stdout.trim();
    return isWin ? prefix : path.join(prefix, 'bin');
  }
  if (requirement.resolve === 'uv-tool-bin') {
    const home = isWin ? (process.env.USERPROFILE || process.env.HOME) : process.env.HOME;
    return home ? path.join(home, '.local', 'bin') : '';
  }
  if (requirement.resolve === 'local-bin') {
    return path.join(process.env.USERPROFILE || process.env.HOME || '', '.local', 'bin');
  }
  return requirement.path ? path.resolve(requirement.path) : '';
}

/**
 * Ensure PATH contains the dirs an MCP needs. Asks before touching the session PATH and
 * explains how to make it permanent when the user declines.
 */
export async function ensurePathRequirements(ctx, requirements, { only = [] } = {}) {
  const results = [];
  for (const requirement of requirements) {
    if (only.length && !only.includes(requirement.id)) continue;
    const dir = resolvePathRequirement(requirement);
    if (!dir || !exists(dir)) { results.push({ ...requirement, status: 'skip', detail: 'thu muc khong ton tai' }); continue; }
    const current = (process.env.PATH || '').split(path.delimiter).map((entry) => entry.toLowerCase());
    if (current.includes(dir.toLowerCase())) {
      results.push({ ...requirement, status: 'present', detail: dir });
      continue;
    }
    const key = `${requirement.id}:${dir}`;
    if (seenPath.has(key)) { results.push({ ...requirement, status: 'declined', detail: 'da hoi truoc do' }); continue; }
    seenPath.add(key);
    log.warn(`Thieu PATH cho ${requirement.label || requirement.id}: ${dir} (${requirement.why || ''})`);
    const consent = await askConsent(ctx, `[?] Them "${dir}" vao PATH cua phien hien tai? [Y/n]: `, true);
    if (consent) {
      mergePath([dir]);
      log.ok(`da them vao PATH phien hien tai: ${dir}`);
      log.info('    Luu y: de co dinh, them dong nay vao shell profile (hoac setx PATH tren Windows) va mo terminal moi.');
      results.push({ ...requirement, status: 'added', detail: dir });
    } else {
      log.info(`    Huong xu ly: them "${dir}" vao PATH (Windows: System Properties > Environment Variables; macOS/Linux: ~/.zshrc hoac ~/.bashrc), roi mo terminal moi.`);
      results.push({ ...requirement, status: 'declined', detail: dir });
    }
  }
  return results;
}

export function listDeps(prereqs) {
  return prereqs.deps || [];
}

export function fileExists(p) {
  try { return fs.statSync(p).isFile(); } catch { return false; }
}
