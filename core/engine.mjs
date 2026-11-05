#!/usr/bin/env node
// core/engine.mjs - single cross-platform setup engine (Windows + macOS + Linux).
// One pipeline, one option surface, one prompt order. Agent differences live in manifest/ + templates/.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import * as U from './lib/util.mjs';
import * as M from './lib/manifest.mjs';
import * as R from './lib/render.mjs';
import * as V from './lib/verify.mjs';
import * as D from './lib/deps.mjs';

const ROOT = M.ROOT;
const ENGINE_VERSION = '1.0.0';
const RESUME_FILE = process.env.SETUP_RESUME_ENV_PATH || path.join(os.tmpdir(), 'setup-agent-code', '.env');

let ctx;

async function main() {
  const manifests = M.loadManifests(ROOT);
  const manifestErrors = M.validateManifests(manifests);
  if (manifestErrors.length) {
    manifestErrors.forEach((e) => U.log.error(`manifest: ${e}`));
    process.exit(2);
  }
  const opts = parseArgs(process.argv.slice(2), manifests.options);
  if (opts.help) return printHelp(manifests);
  if (opts.version) return console.log(`setup-agent-code ${ENGINE_VERSION}`);

  U.log.quiet = Boolean(opts.quiet) || Boolean(opts.json);
  U.log.verbose = Boolean(opts.verbose);

  const mode = opts['dry-run'] ? 'dry-run' : opts.doctor ? 'doctor' : 'install';
  ctx = await createContext(opts, manifests, mode);

  const plan = { phases: M.PHASES.map((p) => p.id), targets: ctx.targets, mode, options: opts };
  if (mode === 'dry-run') {
    const preview = await runAll(manifests, { previewOnly: true });
    if (opts.json) {
      process.stdout.write(`${JSON.stringify({ ...plan, prompts: ctx.promptOrder, mcp: [...ctx.selectedMcp], preview }, null, 2)}\n`);
    } else {
      U.log.info(`Dry-run: ${ctx.targets.join(', ')} | MCP: ${[...ctx.selectedMcp].join(', ') || 'none'}`);
      U.log.info(`Phases: ${plan.phases.join(' -> ')}`);
    }
    return;
  }
  if (mode === 'doctor') {
    const report = await runAll(manifests, { verifyOnly: true });
    finish(report, opts, manifests, mode);
    return;
  }
  const report = await runAll(manifests, {});
  finish(report, opts, manifests, mode);
}

// ---------------------------------------------------------------- options
function parseArgs(argv, optionsManifest) {
  const defs = new Map();
  for (const option of optionsManifest.options) {
    if (option.long) defs.set(option.long, option);
    if (option.short) defs.set(option.short, option);
    if (option.ps) defs.set(option.ps.toLowerCase(), option);
  }
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    let token = argv[i];
    if (token === '--') break;
    let inlineValue;
    if (token.includes('=')) {
      const [flag, ...rest] = token.split('=');
      token = flag;
      inlineValue = rest.join('=');
    }
    const key = token.toLowerCase();
    const def = defs.get(key) || defs.get(token);
    if (!def) {
      if (/^[-/]/.test(token)) {
        U.log.error(`Option khong hop le: ${token}`);
        U.log.error('Dung --help de xem danh sach option.');
        process.exit(2);
      }
      continue;
    }
    if (def.type === 'boolean') out[def.id] = true;
    else {
      const value = inlineValue ?? argv[i + 1];
      if (value === undefined || (/^-/.test(value) && def.id !== 'mcp')) {
        U.log.error(`Option ${token} can gia tri.`);
        process.exit(2);
      }
      out[def.id] = value;
      if (inlineValue === undefined) i += 1;
    }
  }
  out.target = (out.target || 'all').toLowerCase().replace(/_/g, '-');
  if (out.target === 'antigravity') out.target = 'antigravity-cli';
  if (out.memorix && out['no-memorix']) fail('Khong dung dong thoi --memorix va --no-memorix.');
  return out;
}

function fail(message) {
  U.log.error(message);
  process.exit(2);
}

function printHelp(manifests) {
  console.log(`setup-agent-code ${ENGINE_VERSION} - cai dat & cau hinh AI coding agents\n`);
  console.log('Usage: install.ps1 -Target <agent> [options]   |   install.sh --target <agent> [options]\n');
  console.log('Agents:');
  for (const agent of manifests.agents.agents) console.log(`  ${agent.id.padEnd(18)} ${agent.name}`);
  console.log('\nOptions:');
  for (const option of manifests.options.options) {
    const names = [option.ps, option.long].filter(Boolean).join(' / ');
    console.log(`  ${names.padEnd(34)} ${option.description || ''}`);
  }
  console.log('\nVi du:');
  console.log('  install.sh --target omp --dry-run --json');
  console.log('  install.ps1 -Target claude-code -EnableMemorix -OverwriteAll');
  console.log('  install.sh --mcp gitnexus,context7 --yes');
}

// ---------------------------------------------------------------- context
async function createContext(opts, manifests, mode) {
  const targets = M.sortTargets(manifests, opts.target);
  if (!targets.length || (opts.target !== 'all' && !M.agentById(manifests, opts.target))) {
    fail(`Target khong hop le: ${opts.target}. Hop le: all, ${manifests.agents.agents.map((a) => a.id).join(', ')}`);
  }
  const envFile = opts['env-file'] || path.join(ROOT, '.env');
  const env = { ...U.parseEnvFile(envFile) };
  const resume = U.parseEnvFile(RESUME_FILE);
  const prompt = U.createPrompt({ yes: Boolean(opts.yes) || mode === 'dry-run' });
  const interactive = prompt.interactive && !opts.force && !opts.yes;

  let reuse = false;
  if (interactive && Object.keys(resume).length) {
    U.log.info(`\n[?] Phat hien cau hinh tu lan chay truoc (${RESUME_FILE}):`);
    for (const [key, value] of Object.entries(resume)) {
      U.log.info(`    ${key} = ${/(KEY|TOKEN|SECRET|PASSWORD)/i.test(key) ? '***' : value}`);
    }
    const answer = await prompt.ask('[?] Su dung lai cau hinh cu? [Y/n]: ');
    reuse = !answer || /^y/i.test(answer);
  }
  const vars = reuse ? { ...resume, ...env } : { ...env, ...Object.fromEntries(Object.keys(resume).map((k) => [k, ''])) };
  // Values the operator actually supplied (.env file or remembered answers), as opposed
  // to prompt defaults. Used to decide whether a re-run may rewrite a live config value.
  const explicitVars = new Set(Object.entries(vars).filter(([, value]) => value !== '' && value != null).map(([key]) => key));

  return {
    opts,
    manifests,
    mode,
    targets,
    prompt,
    interactive,
    vars,
    explicitVars,
    phases: [],
    results: [],
    warnings: [],
    errors: [],
    selectedMcp: new Set(),
    blockedMcp: new Set(),
    guidance: [],
    promptOrder: [],
    choices: {},
    reuse,
    username: os.userInfo().username,
    home: os.homedir(),
    isWin: U.isWin
  };
}

// ---------------------------------------------------------------- pipeline
async function runAll(manifests, { verifyOnly = false, previewOnly = false } = {}) {
  const report = { targets: [], results: [] };
  // Doctor has no P2/P3, so seed the selection from flags/defaults to know what to verify.
  if (verifyOnly && ctx.selectedMcp.size === 0) seedSelection(manifests);
  for (const target of ctx.targets) {
    const agent = M.agentById(manifests, target);
    const paths = M.resolvePaths(agent);
    const tokens = { ...paths.tokens };
    if (agent.credentialFile) tokens.credentials = tokens.credentials || tokens.dir;
    const agentCtx = { agent, paths, tokens, rows: [] };
    await runPhases(agentCtx, { verifyOnly, previewOnly });
    report.targets.push({ id: agent.id, rows: agentCtx.rows });
    report.results.push(...agentCtx.rows.map((r) => ({ ...r, agent: agent.id })));
  }
  return report;
}

async function runPhases(agentCtx, { verifyOnly, previewOnly }) {
  const phases = M.PHASES;
  const list = verifyOnly ? phases.filter((p) => ['P0', 'P11'].includes(p.id)) : phases;
  for (const phase of list) {
    if (previewOnly && !['P0', 'P1', 'P2', 'P3'].includes(phase.id)) continue;
    U.log.phase(phase.id, `${phase.title} [${agentCtx.agent.id}]`);
    ctx.phases.push({ id: phase.id, agent: agentCtx.agent.id });
    try {
      await PHASE_IMPL[phase.id](agentCtx);
    } catch (error) {
      U.log.error(`${phase.id} that bai: ${error.message}`);
      agentCtx.rows.push(V.result(`phase:${phase.id}`, 'FAIL', error.message));
      ctx.errors.push({ agent: agentCtx.agent.id, phase: phase.id, message: error.message });
      if (!verifyOnly) break;
    }
  }
}

const PHASE_IMPL = {
  P0: async (c) => {
    U.log.info(`  OS: ${process.platform}/${process.arch} | Node: ${process.version} | Shell: ${process.env.SHELL || process.env.ComSpec || 'n/a'}`);
    U.log.info(`  Agent dir: ${c.paths.dir}`);
    const major = Number(process.versions.node.split('.')[0]);
    if (major < 22) U.log.warn(`Node ${process.version} < 22.18.0 - mot so MCP co the khong chay.`);
    if (ctx.mode === 'install') U.ensureDir(c.paths.dir);
  },

  P1: async (c) => {
    U.log.info(`  Target: ${c.agent.id} | Mode: ${ctx.mode} | Force: ${Boolean(ctx.opts.force)} | OverwriteAll: ${Boolean(ctx.opts['overwrite-all'])}`);
  },

  P2: async (c) => {
    const servers = ctx.manifests.mcp.servers;
    const explicit = parseMcpSelection(ctx.opts, servers);
    ctx.selectedMcp.clear();
    for (const server of servers) {
      if (explicit) {
        if (explicit.has(server.id)) ctx.selectedMcp.add(server.id);
        continue;
      }
      const saved = ctx.vars[`SETUP_MCP_${server.id.toUpperCase().replace(/-/g, '_')}`];
      const def = ctx.reuse && /^(true|false)$/.test(saved || '') ? saved === 'true' : server.default !== false;
      if (!ctx.interactive) {
        if (def) ctx.selectedMcp.add(server.id);
        continue;
      }
      const answer = await ctx.prompt.ask(`[?] Cai MCP '${server.id}' (${server.label})? [${def ? 'Y/n' : 'y/N'}]: `);
      const enabled = answer ? /^y/i.test(answer) : def;
      if (enabled) ctx.selectedMcp.add(server.id);
      U.saveEnvValue(RESUME_FILE, `SETUP_MCP_${server.id.toUpperCase().replace(/-/g, '_')}`, String(enabled));
    }
    if (ctx.opts.memorix) ctx.selectedMcp.add('memorix');
    if (ctx.opts['no-memorix']) ctx.selectedMcp.delete('memorix');
    U.log.info(`  MCP da chon: ${[...ctx.selectedMcp].join(', ') || 'none'}`);
  },

  P3: async (c) => {
    // Only ask for variables that the chosen MCP servers / target actually need.
    const all = ctx.manifests.prompts.prompts;
    const applicable = all.filter((p) => {
      if (p.when?.target && !ctx.targets.includes(p.when.target)) return false;
      if (p.when?.mcp && !ctx.selectedMcp.has(p.when.mcp)) return false;
      return true;
    });
    ctx.promptOrder = applicable.map((p) => p.key);
    for (const promptDef of applicable) {
      const { key } = promptDef;
      const current = ctx.vars[key];
      const shown = /(KEY|TOKEN|SECRET|PASSWORD)/i.test(key) ? (current ? '***' : '') : current;
      if (current) {
        U.log.skip(`Reuse ${key} = ${shown}`);
        continue;
      }
      if (promptDef.required && ctx.mode === 'dry-run') {
        ctx.vars[key] = promptDef.default || `<${key}>`;
        continue;
      }
      if (!ctx.interactive) {
        ctx.vars[key] = promptDef.default || '';
        if (promptDef.required && !ctx.vars[key] && ctx.mode !== 'dry-run') {
          U.log.warn(`Thieu ${key} (bat buoc) nhung dang chay non-interactive -> dung gia tri rong.`);
        }
        continue;
      }
      const suffix = promptDef.default ? ` [${promptDef.default}]` : '';
      const answer = await ctx.prompt.ask(`[?] ${promptDef.label}${suffix}: `);
      ctx.vars[key] = answer || promptDef.default || '';
      U.saveEnvValue(RESUME_FILE, key, ctx.vars[key]);
    }
  },

  P4: async (c) => {
    const prereqs = D.loadPrerequisites(ROOT);
    // Map dependency -> MCP servers that need it, so a missing dep blocks only those servers.
    const consumersByDep = new Map();
    for (const id of ctx.selectedMcp) {
      if (ctx.blockedMcp.has(id)) continue;
      const server = ctx.manifests.mcp.servers.find((s) => s.id === id);
      for (const depId of server?.requires || []) {
        if (!consumersByDep.has(depId)) consumersByDep.set(depId, new Set());
        consumersByDep.get(depId).add(id);
      }
    }
    for (const dep of D.listDeps(prereqs)) {
      const consumers = new Set([...(consumersByDep.get(dep.id) || [])].filter((id) => !ctx.blockedMcp.has(id)));
      if (consumers.size === 0) continue;
      const requiredBy = [...consumers];
      const outcome = await D.ensureDependency(dep, ctx, { requiredBy });
      if (outcome.guidance?.length) ctx.guidance.push({ scope: `dep:${dep.id}`, steps: outcome.guidance });
      if (outcome.status === 'present' || outcome.status === 'installed') {
        c.rows.push(V.result(`dep:${dep.id}`, 'PASS', outcome.detail));
      } else if (outcome.status === 'skipped') {
        c.rows.push(V.result(`dep:${dep.id}`, 'SKIP', outcome.detail));
      } else {
        // declined / failed -> do not set up the MCP servers that depend on this.
        for (const mcpId of consumers) ctx.blockedMcp.add(mcpId);
        const status = outcome.status === 'failed' ? 'FAIL' : 'WARN';
        c.rows.push(V.result(`dep:${dep.id}`, status, `${outcome.detail} -> bo qua: ${requiredBy.join(', ')}`));
        U.log.warn(`MCP bi bo qua vi thieu ${dep.id}: ${requiredBy.join(', ')}`);
      }
    }
    if (ctx.opts['skip-install']) {
      U.log.skip('skip-install: bo qua kiem tra/cai prerequisites va PATH');
    } else {
      const pathResults = await D.ensurePathRequirements(ctx, prereqs.pathRequirements || []);
      for (const row of pathResults) {
        if (row.status === 'added') c.rows.push(V.result(`path:${row.id}`, 'PASS', `da them: ${row.detail}`));
        else if (row.status === 'declined') c.rows.push(V.result(`path:${row.id}`, 'WARN', `chua co trong PATH: ${row.detail}`));
      }
    }
    D.refreshPath();
    c.tokens.node = U.which('node') || 'node';
    c.tokens.npm = U.which('npm') || 'npm';
  },

  P5: async (c) => {
    const binary = c.agent.binary;
    if (!binary) return;
    const check = () => D.assessCommand(binary.command, binary.versionArgs || ['--version'], {
      version: binary.version,
      minVersion: binary.minVersion
    });
    let assess = check();

    // Check first: only ask for (re)install when the current state is not acceptable.
    if (assess.state === 'ok') {
      U.log.skip(`${binary.command} da cai dung: ${assess.detail}`);
      c.rows.push(V.result(`binary:${binary.command}`, 'PASS', assess.detail));
      return;
    }
    U.log.warn(`${binary.command}: ${assess.detail} [${assess.state}]`);

    const guidance = () => {
      if (!binary.installGuidance?.length) return;
      U.log.info('    Huong xu ly:');
      for (const step of binary.installGuidance) U.log.info(`      - ${step}`);
      ctx.guidance.push({ scope: `agent:${c.agent.id}`, steps: binary.installGuidance });
    };

    if (ctx.opts['skip-install']) {
      U.log.skip('skip-install: khong cai lai binary agent');
      c.rows.push(V.result(`binary:${binary.command}`, binary.optional ? 'WARN' : 'SKIP', assess.detail));
      return;
    }

    const question = assess.state === 'missing'
      ? `[?] Cai ${binary.command}? [Y/n]: `
      : `[?] ${binary.command} hien khong phu hop (${assess.state}). Cai lai/cap nhat? [Y/n]: `;
    const consent = await D.askConsent(ctx, question, true);
    if (!consent) {
      const status = binary.optional ? 'WARN' : 'FAIL';
      U.log.warn(`Khong cai lai ${binary.command}.`);
      c.rows.push(V.result(`binary:${binary.command}`, status, `nguoi dung tu choi (${assess.detail})`));
      guidance();
      return;
    }

    for (const action of binary.install?.[U.osKey] || []) {
      if (action.type === 'note') { U.log.warn(action.message); continue; }
      executeInstallAction(action, binary);
      D.refreshPath();
      if (check().state === 'ok') break;
    }
    assess = check();
    if (assess.state === 'ok') {
      U.log.ok(`${binary.command} san sang: ${assess.detail}`);
      c.rows.push(V.result(`binary:${binary.command}`, 'PASS', assess.detail));
    } else {
      const status = binary.optional ? 'WARN' : 'FAIL';
      (status === 'FAIL' ? U.log.error : U.log.warn)(`${binary.command} van khong dung: ${assess.detail}`);
      c.rows.push(V.result(`binary:${binary.command}`, status, assess.detail));
      guidance();
    }
  },

  P6: async (c) => {
    if (ctx.opts['skip-install']) { U.log.skip('skip-install: bo qua cai MCP'); return; }
    const resolveFile = (value) => String(value).replace(/<npm:([^>]+)>/g, (_, rel) => U.resolveNpmPath(rel));
    for (const id of ctx.selectedMcp) {
      const server = ctx.manifests.mcp.servers.find((s) => s.id === id);
      if (!server) continue;
      if (ctx.blockedMcp.has(id)) {
        U.log.skip(`${id}: bo qua vi thieu dependency (xem huong xu ly o P4)`);
        c.rows.push(V.result(`install:${id}`, 'SKIP', 'thieu dependency'));
        continue;
      }
      if (id === 'cloakbrowser') {
        const ok = await installCloakbrowser(c, server);
        if (!ok) ctx.blockedMcp.add(id);
        c.rows.push(V.result(`install:${id}`, ok ? 'PASS' : 'FAIL', ok ? 'da cai' : 'copy/npm install that bai'));
        continue;
      }

      const check = () => D.assessVerify(server.verify, resolveFile);
      let assess = check();
      // Check first: a healthy, correct-version MCP never triggers a reinstall prompt.
      if (assess.state === 'ok') {
        U.log.skip(`${id}: da cai dung (${assess.detail})`);
        c.rows.push(V.result(`install:${id}`, 'PASS', assess.detail));
        continue;
      }
      U.log.warn(`${id}: ${assess.detail} [${assess.state}]`);

      const guidance = () => {
        if (!server.installGuidance?.length) return;
        U.log.info('    Huong xu ly:');
        for (const step of server.installGuidance) U.log.info(`      - ${step}`);
        ctx.guidance.push({ scope: `mcp:${id}`, steps: server.installGuidance });
      };

      const question = assess.state === 'missing'
        ? `[?] Cai MCP '${id}'? [Y/n]: `
        : `[?] '${id}' hien khong phu hop (${assess.state}). Cai lai/cap nhat? [Y/n]: `;
      const consent = await D.askConsent(ctx, question, true);
      if (!consent) {
        U.log.warn(`Khong cai lai ${id}.`);
        ctx.blockedMcp.add(id);
        c.rows.push(V.result(`install:${id}`, 'WARN', `nguoi dung tu choi (${assess.detail})`));
        guidance();
        continue;
      }

      for (const action of server.install?.[U.osKey] || []) {
        if (action.when && !evalWhen(action.when)) continue;
        executeInstallAction(action, server.verify);
        D.refreshPath();
        if (check().state === 'ok') break;
      }
      assess = check();
      if (assess.state === 'ok') {
        U.log.ok(`${id} da cai dung: ${assess.detail}`);
        c.rows.push(V.result(`install:${id}`, 'PASS', assess.detail));
      } else {
        // A selected tool that did not install correctly is a failure, not a warning.
        U.log.error(`${id}: cai dat khong dung (${assess.detail})`);
        ctx.blockedMcp.add(id);
        c.rows.push(V.result(`install:${id}`, 'FAIL', assess.detail));
        guidance();
      }
    }
  },

  P7: async (c) => {
    const policy = await chooseWritePolicy();
    const servers = buildSelectedSpecs(c);
    const vars = buildVars(c);
    const writes = [];

    for (const cfg of c.agent.configs || []) {
      const dest = M.resolveToken(cfg.dest, c.tokens);
      // Optional config: only written when the MCP server it belongs to is selected.
      if (cfg.whenMcp && (!ctx.selectedMcp.has(cfg.whenMcp) || ctx.blockedMcp.has(cfg.whenMcp))) continue;
      const rendered = R.renderTemplate(ROOT, cfg.template, vars, { json: cfg.kind === 'json' });
      if (cfg.kind === 'json') {
        let obj;
        try { obj = JSON.parse(rendered); } catch (e) { throw new Error(`template JSON loi (${cfg.template}): ${e.message}`); }
        const existing = R.readJsonIfExists(dest);
        // Merge whenever a live file exists: `--overwrite-all` must not delete
        // user data (hooks, MCP servers) the template does not know about.
        if (existing) obj = R.mergeKeepExisting(existing, obj);
        for (const dotted of (!isWindows() ? cfg.stripKeys || [] : [])) R.deleteByPath(obj, dotted);
        if (cfg.hooks) applyHookRegistrations(obj, c);
        if (cfg.mcpMerge) attachMcp(obj, c.agent.mcp.adapter, servers, knownMcpIds(c));
        writes.push({ dest, kind: 'json', content: `${JSON.stringify(obj, null, 2)}\n`, preserve: cfg.preserve });
      } else if (cfg.kind === 'toml') {
        let text = rendered;
        if (cfg.mcpMerge) text = text.replace('# <<MCP_SERVERS>>', R.tomlMcpBlocks(servers));
        if (U.exists(dest)) {
          // The installer owns the MCP tables it can generate, so a de-selected
          // server disappears; every other table stays the user's.
          const headers = [];
          for (const id of knownMcpIds(c)) headers.push(`[mcp_servers.${id}]`, `[mcp_servers."${id}"]`);
          text = R.mergeToml(U.readText(dest), ensureTrailingNewline(text), {
            ownedHeaders: [...(cfg.ownedHeaders || []), ...headers]
          });
        }
        writes.push({ dest, kind: 'toml', content: ensureTrailingNewline(text), preserve: false });
      } else if (cfg.kind === 'yaml') {
        let text = rendered;
        if (cfg.mcpMerge) text = text.replace('# <<MCP_SERVERS>>', R.yamlMcpBlocks(servers));
        // A patch layer is merged entry-by-entry so user entries survive every write.
        if (cfg.layerMerge && U.exists(dest)) {
          const previous = U.readText(dest);
          // Preserve live values the operator did not explicitly re-supply.
          for (const [placeholder, varName] of Object.entries(cfg.preserveFromExisting || {})) {
            if (ctx.explicitVars.has(varName)) continue;
            const current = previous.match(new RegExp(`^\\s*${placeholder}:\\s*(\\S+)\\s*$`, 'm'));
            if (current) text = text.replace(new RegExp(`^(\\s*${placeholder}:\\s*)\\S+\\s*$`, 'm'), `$1${current[1]}`);
          }
          text = R.mergeYamlLayer(previous, text, {
            managedMcpIds: cfg.mcpMerge ? [...knownMcpIds(c)] : [],
            managedInsertIds: cfg.managedInserts || [],
            ownIds: cfg.ownIds || []
          });
        }
        writes.push({ dest, kind: 'yaml', content: ensureTrailingNewline(text), preserve: false });
      } else {
        writes.push({ dest, kind: 'yaml', content: ensureTrailingNewline(rendered), preserve: cfg.preserve });
      }
    }

    // MCP-only JSON files (omp mcp.json, claude.json)
    const mcpFile = M.resolveToken(c.agent.mcp.file, c.tokens);
    const coveredByConfig = (c.agent.configs || []).some((cfg) => M.resolveToken(cfg.dest, c.tokens) === mcpFile);
    if (!coveredByConfig && c.agent.mcp.adapter !== 'codex-toml' && c.agent.mcp.adapter !== 'dsh-yaml') {
      const existing = R.readJsonIfExists(mcpFile) || {};
      attachMcp(existing, c.agent.mcp.adapter, servers, knownMcpIds(c));
      writes.push({ dest: mcpFile, kind: 'json', content: `${JSON.stringify(existing, null, 2)}\n`, preserve: false });
    }

    // DSH credentials: never clobber an existing file (it holds real secrets + OAuth records).
    if (c.agent.credentialFile) {
      const dest = M.resolveToken(c.agent.credentialFile.dest, c.tokens);
      const content = R.renderTemplate(ROOT, c.agent.credentialFile.template, vars);
      writes.push({ dest, kind: 'yaml', content: ensureTrailingNewline(content), preserve: c.agent.credentialFile.preserve === false ? false : 'sealed' });
    }

    for (const write of writes) await writeConfig(c, write, policy);
    c.tokens.servers = servers;
  },

  P8: async (c) => {
    const policy = await chooseWritePolicy();
    const sections = {};
    for (const file of c.agent.instructionFiles) {
      const parts = (file.content || []).map((rel) => R.renderTemplate(ROOT, rel, buildVars(c)));
      const optional = [];
      for (const [key, rel] of Object.entries(file.optionalSections || {})) {
        const enabled = ctx.selectedMcp.has(key) && !ctx.blockedMcp.has(key);
        if (enabled) optional.push(R.renderTemplate(ROOT, rel, buildVars(c)));
      }
      const content = R.composeInstruction(parts, optional);
      const dest = M.resolveToken(file.dest, c.tokens);
      sections[dest] = content.length;
      await writeConfig(c, { dest, kind: 'markdown', content, preserve: false }, policy);
    }
    for (const forbidden of c.agent.forbiddenFiles || []) {
      const dest = M.resolveToken(forbidden.dest, c.tokens);
      if (!U.exists(dest)) continue;
      U.log.warn(`File di san khong con dung: ${dest} (${forbidden.code}) -> chuyen vao Thung rac`);
      U.trash(dest, ctx.mode !== 'install');
    }
  },

  P9: async (c) => {
    const source = path.join(ROOT, 'skills');
    if (!U.exists(source)) { U.log.warn('Khong tim thay thu muc skills/ canonical.'); return; }
    const withMemorix = ctx.selectedMcp.has('memorix') && !ctx.blockedMcp.has('memorix');
    const dests = [c.agent.skillsDir, ...(c.agent.extraSkillsDirs || [])]
      .map((d) => M.resolveToken(d, c.tokens));
    for (const dest of dests) {
      for (const name of U.listDirs(source)) {
        if (!withMemorix && name.startsWith('memorix-')) continue;
        const target = path.join(dest, name);
        // Existing skill ownership is unknown, even when its name matches canonical.
        if (fs.existsSync(target)) continue;
        U.copyDir(path.join(source, name), target);
      }
      U.log.ok(`skills -> ${dest} (${U.listDirs(dest).length} skills)`);
    }
  },

  P10: async (c) => {
    for (const hook of c.agent.hooks || []) {
      const dest = M.resolveToken(hook.dest, c.tokens);
      if (hook.template) {
        const content = R.renderTemplate(ROOT, hook.template, buildVars(c));
        await writeConfig(c, { dest, kind: 'script', content, preserve: false }, 'overwrite');
        if (!U.isWin) { try { fs.chmodSync(dest, 0o755); } catch {} }
      }
      if (hook.register) {
        const file = M.resolveToken(hook.register.file, c.tokens);
        const obj = R.readJsonIfExists(file) || {};
        if (hook.register.key) {
          R.registerJsonArray(obj, hook.register.key, hook.register.value);
        } else {
          const command = M.resolveToken(hook.register.command, { ...c.tokens, dirPath: c.paths.dir.split(path.sep).join('/') });
          R.registerJsonHook(obj, { event: hook.register.event, matcher: hook.register.matcher, command, shape: hook.register.shape });
        }
        R.writeJson(file, obj, ctx.mode !== 'install');
        U.log.ok(`hook ${hook.register.event || hook.register.key} -> ${file}`);
      }
    }
    for (const plugin of c.agent.plugins || []) {
      await ensurePlugin(c, plugin);
    }
    if (!ctx.opts['skip-install'] && ctx.selectedMcp.has('memorix') && !ctx.blockedMcp.has('memorix') && (ctx.opts.memorix || ctx.interactive)) {
      const agentFlag = { 'claude-code': 'claude', 'codex-cli': 'codex', dsh: 'dsh' }[c.agent.id];
      if (agentFlag && U.which('memorix')) {
        const r = U.run('memorix', ['hooks', 'install', '--agent', agentFlag, '--global'], { allowFail: true, timeout: 120000 });
        if (r.ok) U.log.ok(`memorix hooks (${agentFlag}) da cai`);
        else U.log.warn(`memorix hooks (${agentFlag}) that bai: ${(r.stderr || r.stdout).slice(0, 160)}`);
      }
    }
  },

  P11: async (c) => {
    const rows = [];
    const isDoctor = ctx.mode === 'doctor';
    // Doctor verifies what is actually configured; install verifies what we just selected.
    let activeMcp = [...ctx.selectedMcp].filter((id) => !ctx.blockedMcp.has(id));
    if (isDoctor) {
      const configuredMcp = inferConfiguredMcp(c);
      activeMcp = configuredMcp || [];
      if (configuredMcp && !configuredMcp.length) rows.push(V.result('mcp', 'SKIP', 'chua co MCP nao duoc cau hinh'));
    }
    rows.push(...V.verifyFiles(c.agent, c.tokens));
    rows.push(...V.verifyBinary(c.agent, { skipInstall: Boolean(ctx.opts["skip-install"]), mode: ctx.mode }));
    rows.push(...V.verifyConfigEntries(c.agent, c.tokens, activeMcp));
    if (isDoctor) {
      for (const plugin of c.agent.plugins || []) rows.push(verifyPlugin(c, plugin));
    }
    if (!isDoctor) {
      for (const id of ctx.blockedMcp) {
        rows.push(V.result(`mcp:${id}`, 'WARN', 'khong duoc cau hinh (thieu dependency) - xem huong xu ly'));
      }
    }
    // Version pin check (e.g. mcp-atlassian==0.23.1) even when the MCP was already installed.
    const resolveFile = (value) => String(value).replace(/<npm:([^>]+)>/g, (_, rel) => U.resolveNpmPath(rel));
    const serversForVerify = isDoctor
      ? (ctx.manifests?.mcp?.servers || []).filter((server) => activeMcp.includes(server.id)).map((server) => ({ id: server.id, server }))
      : (c.tokens.servers || buildSelectedSpecs(c));
    for (const row of serversForVerify) {
      const verify = row.server?.verify;
      if (!verify?.version && !verify?.minVersion) continue;
      const assess = D.assessVerify(verify, resolveFile);
      rows.push(V.result(`version:${row.id}`, assess.state === 'ok' ? 'PASS' : 'FAIL', assess.detail));
    }
    if (ctx.mode === 'install' && !ctx.opts['skip-install'] && c.tokens.servers) {
      for (const server of c.tokens.servers) {
        if (!U.which(server.spec.command === 'node' ? 'node' : server.spec.command.split(/[\\/]/).pop())) continue;
        const row = await V.handshake(server.spec);
        rows.push({ ...row, check: `handshake:${server.id}` });
      }
    }
    c.rows.push(...rows);
    U.log.info(`\n${V.formatTable(rows)}`);
    const counts = V.summarize(rows);
    U.log.info(`  Tong: PASS=${counts.PASS} WARN=${counts.WARN} FAIL=${counts.FAIL} SKIP=${counts.SKIP}`);
  },

  P12: async (c) => {
    U.log.ok(`Hoan tat ${c.agent.id}`);
  }
};

// ---------------------------------------------------------------- helpers
function ensureTrailingNewline(text) {
  return text.endsWith('\n') ? text : `${text}\n`;
}

function parseMcpSelection(opts, servers) {
  if (opts.preset) {
    if (opts.preset === 'minimal') return new Set();
    if (opts.preset === 'standard') return new Set(servers.filter((s) => s.default !== false).map((s) => s.id));
    if (opts.preset === 'full') return new Set(servers.map((s) => s.id));
    fail(`Preset khong hop le: ${opts.preset}`);
  }
  if (!opts.mcp) return null;
  if (opts.mcp === 'all') return new Set(servers.map((s) => s.id));
  if (opts.mcp === 'none') return new Set();
  const wanted = opts.mcp.split(',').map((s) => s.trim()).filter(Boolean);
  for (const id of wanted) if (!servers.some((s) => s.id === id)) fail(`MCP khong ton tai: ${id}`);
  return new Set(wanted);
}

function seedSelection(manifests) {
  const servers = manifests.mcp.servers;
  const explicit = parseMcpSelection(ctx.opts, servers);
  if (explicit) for (const id of explicit) ctx.selectedMcp.add(id);
  else for (const server of servers) if (server.default !== false) ctx.selectedMcp.add(server.id);
  if (ctx.opts.memorix) ctx.selectedMcp.add('memorix');
  if (ctx.opts['no-memorix']) ctx.selectedMcp.delete('memorix');
}

/** Read which MCP servers a rendered config actually contains (used by --doctor). */
function inferConfiguredMcp(c) {
  const file = M.resolveToken(c.agent.mcp.file, c.tokens);
  if (!U.exists(file)) return null;
  const text = U.readText(file);
  const adapter = c.agent.mcp.adapter;
  if (adapter === 'codex-toml') {
    return [...text.matchAll(/^\[mcp_servers\.([A-Za-z0-9-]+)\]$/gm)].map((match) => match[1]);
  }
  if (adapter === 'dsh-yaml') {
    return [...text.matchAll(/^- id: mcp-([A-Za-z0-9-]+)$/gm)].map((match) => match[1]);
  }
  try {
    const obj = JSON.parse(text);
    if (!obj || typeof obj !== 'object' || Array.isArray(obj)) return null;
    const servers = obj[adapter === 'opencode-json' ? 'mcp' : 'mcpServers'];
    if (!servers || typeof servers !== 'object' || Array.isArray(servers)) return null;
    return Object.keys(servers);
  } catch { return null; }
}

function evalWhen(condition) {
  if (!condition) return true;
  if (condition.startsWith('!')) return !U.which(condition.slice(1));
  return Boolean(U.which(condition));
}

function executeInstallAction(action, meta) {
  if (action.type === 'npm') {
    U.log.info(`  npm install -g ${action.package} ...`);
    let r = U.run('npm', ['install', '-g', action.package], { allowFail: true });
    if (!r.ok) {
      U.log.warn(`npm install that bai, thu lai voi --force: ${(r.stderr || '').slice(0, 200)}`);
      r = U.run('npm', ['install', '-g', action.package, '--force'], { allowFail: true });
    }
    return r.ok;
  }
  if (action.type === 'powershell') {
    return U.run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', action.script], { allowFail: true }).ok;
  }
  if (action.type === 'shell') {
    return U.run('bash', ['-lc', action.script], { allowFail: true }).ok;
  }
  if (action.type === 'note') { U.log.warn(action.message); return false; }
  if (action.cmd) {
    const bin = U.which(action.cmd) || action.cmd;
    U.log.info(`  ${action.cmd} ${(action.args || []).join(' ')}`);
    return U.run(bin, action.args || [], { allowFail: true }).ok;
  }
  return false;
}

function buildVars(c) {
  const servers = c.tokens.servers || buildSelectedSpecs(c);
  const gitnexus = servers.find((s) => s.id === 'gitnexus');
  const context7 = servers.find((s) => s.id === 'context7');
  const cloak = servers.find((s) => s.id === 'cloakbrowser');
  return {
    ...ctx.vars,
    AI_BASE_URL: ctx.vars.AI_BASE_URL || 'http://localhost:20128/v1',
    AI_API_KEY: ctx.vars.AI_API_KEY || '',
    JIRA_URL: ctx.vars.JIRA_URL || 'https://jira.cybertech.vn',
    JIRA_PERSONAL_TOKEN: ctx.vars.JIRA_PERSONAL_TOKEN || '',
    CONFLUENCE_URL: ctx.vars.CONFLUENCE_URL || 'https://conf.cybertech.vn',
    CONFLUENCE_PERSONAL_TOKEN: ctx.vars.CONFLUENCE_PERSONAL_TOKEN || '',
    CONTEXT7_API_KEY: ctx.vars.CONTEXT7_API_KEY || '',
    AGY_MODEL: ctx.vars.AGY_MODEL || 'custom/claude-sonnet-5',
    GITNEXUS_PATH: gitnexus ? gitnexus.spec.command === 'cmd' ? gitnexus.spec.args[1] : gitnexus.spec.command : 'gitnexus',
    CONTEXT7_PATH: context7 ? context7.spec.args[0] : '',
    CLOAKBROWSER_SCRIPT: cloak ? cloak.spec.args[0] : '',
    OMP_EXT_DIR: c.paths.extra.ompExt || '',
    CLAUDE_DIR: c.paths.dir,
    CLAUDE_HUD_PATH: path.join(c.paths.dir, 'hud', 'hud.mjs').split(path.sep).join('/'),
    HOME: ctx.home,
    USERPROFILE: ctx.home,
    OS: process.platform
  };
}

function buildSelectedSpecs(c) {
  const resolvers = {
    bin: (name) => U.which(name),
    npmPath: (rel) => U.resolveNpmPath(rel),
    cloakbrowser: path.join(ctx.home, 'mcp-servers', 'cloakbrowser', 'mcp-server-full.mjs')
  };
  const specs = [];
  for (const id of ctx.selectedMcp) {
    if (ctx.blockedMcp.has(id)) continue; // dependency missing: never write a broken MCP entry
    const server = ctx.manifests.mcp.servers.find((s) => s.id === id);
    if (!server) continue;
    const spec = M.buildServerSpec(server, resolvers);
    for (const [key, value] of Object.entries(spec.env)) {
      spec.env[key] = String(value).replace(/\$\{([A-Z0-9_]+)\}/g, (_, name) => ctx.vars[name] ?? '');
    }
    specs.push({ id, spec, server });
  }
  return specs;
}

function knownMcpIds(c) {
  // Only servers the manifest still ships are owned by the installer.
  return new Set(ctx.manifests.mcp.servers.map((s) => s.id));
}

/**
 * Replace the manifest-owned MCP entries and keep user-added servers untouched.
 * `knownIds` are the ids the installer manages: only those can be removed.
 */
function attachMcp(obj, adapter, servers, knownIds) {
  const generated = R.jsonMcpObject(adapter, servers);
  const managed = knownIds || new Set(Object.keys(generated));
  const key = adapter === 'opencode-json' ? 'mcp' : 'mcpServers';
  const current = obj[key] || {};
  const next = { ...current, ...generated };
  for (const id of Object.keys(next)) {
    if (managed.has(id) && !(id in generated)) delete next[id];
  }
  obj[key] = next;
  return obj;
}

function applyHookRegistrations(obj, c) {
  for (const hook of c.agent.hooks || []) {
    if (!hook.register || hook.register.key) continue;
    const command = M.resolveToken(hook.register.command, {
      ...c.tokens,
      dirPath: c.paths.dir.split(path.sep).join('/'),
      trashGuardPath: (c.paths.extra.trashGuard || '').split(path.sep).join('/')
    });
    R.registerJsonHook(obj, { event: hook.register.event, matcher: hook.register.matcher, command, shape: hook.register.shape });
  }
}

let writePolicyPromise = null;
async function chooseWritePolicy() {
  if (ctx.mode !== 'install') return 'skip';
  if (ctx.opts['overwrite-all'] || ctx.opts.force) return 'overwrite';
  if (!ctx.interactive) return 'overwrite';
  if (writePolicyPromise) return writePolicyPromise;
  writePolicyPromise = (async () => {
    const answer = await ctx.prompt.ask('[?] File cau hinh da ton tai: [O]verwrite / [M]erge / [S]kip? [M]: ');
    if (/^o/i.test(answer)) return 'overwrite';
    if (/^s/i.test(answer)) return 'skip';
    return 'merge';
  })();
  return writePolicyPromise;
}

async function writeConfig(c, { dest, content, preserve }, policy) {
  const target = String(dest);
  if (ctx.mode === 'dry-run') {
    U.log.debug(`[dry-run] write ${target} (${content.length} bytes)`);
    return;
  }
  if (policy === 'skip') { U.log.skip(`giu nguyen ${target}`); return; }
  if (U.exists(target)) {
    // 'preserve' protects files that hold user state. 'sealed' is stronger: even
    // --overwrite-all must not replace a file with real secrets (credentials store).
    if (preserve === 'sealed') {
      U.log.skip(`giu nguyen (sealed, chua secret): ${target}`);
      return;
    }
    if (preserve && !ctx.opts['overwrite-all']) { U.log.skip(`giu nguyen (preserve): ${target}`); return; }
    const current = U.readText(target);
    if (current === content) { U.log.skip(`khong doi: ${target}`); return; }
    U.backupFile(target);
  }
  U.ensureDir(path.dirname(target));
  U.writeFileAtomic(target, content);
  U.log.ok(`ghi ${target}`);
}

async function installCloakbrowser(c, server) {
  const destDir = path.join(ctx.home, 'mcp-servers', 'cloakbrowser');
  const srcDir = path.join(ROOT, 'templates', 'hooks', 'cloakbrowser');
  if (!U.exists(srcDir)) { U.log.warn('Khong co source cloakbrowser trong templates/hooks/cloakbrowser.'); return false; }

  const required = [
    'mcp-server-full.mjs',
    path.join('node_modules', 'playwright-core', 'package.json'),
    path.join('node_modules', 'cloakbrowser', 'package.json')
  ];
  const isReady = () => required.every((rel) => U.exists(path.join(destDir, rel)));

  // Check first: refresh the source only when it is missing or differs from the template.
  const srcPkg = path.join(srcDir, 'package.json');
  const destPkg = path.join(destDir, 'package.json');
  const sourceChanged = !U.exists(destPkg) || (U.exists(srcPkg) && U.readText(srcPkg) !== U.readText(destPkg));
  if (!isReady() || sourceChanged) U.copyDir(srcDir, destDir);

  if (isReady()) {
    U.log.skip(`cloakbrowser: da cai day du (${destDir})`);
    return true;
  }

  const post = server?.postInstall;
  if (post) {
    const consent = await D.askConsent(ctx, `[?] Thieu dependencies cho CloakBrowser (playwright-core/cloakbrowser). Chay npm install? [Y/n]: `, true);
    if (!consent) {
      U.log.warn('Khong cai dependencies cho CloakBrowser -> MCP nay se khong chay duoc.');
      U.log.info('    Huong xu ly:');
      U.log.info(`      - cd "${destDir}" && npm install`);
      ctx.guidance.push({ scope: 'mcp:cloakbrowser', steps: [`cd "${destDir}" && npm install`, 'Sau do chay lai installer voi --mcp cloakbrowser.'] });
      return false;
    }
    const r = U.run('npm', ['install', '--omit=dev', '--silent'], { cwd: destDir, allowFail: true });
    if (!r.ok) {
      U.log.error(`npm install cho CloakBrowser that bai: ${(r.stderr || '').slice(0, 200)}`);
      U.log.info(`    Huong xu ly: cd "${destDir}" && npm install  (kiem tra mang/proxy roi chay lai)`);
      ctx.guidance.push({ scope: 'mcp:cloakbrowser', steps: [`cd "${destDir}" && npm install`, 'Kiem tra mang/proxy roi chay lai installer.'] });
      return false;
    }
    U.log.ok(`cloakbrowser dependencies -> ${destDir}`);
  }
  return isReady();
}

/** Locate pnpm (dsh forwards `dsh plugin` to it, and it must be on PATH for that child). */
function pnpmPath() {
  const found = U.which('pnpm');
  if (found) return found;
  const candidates = U.isWin
    ? [path.join(process.env.LOCALAPPDATA || '', 'pnpm', 'bin', 'pnpm.cmd'), path.join(ctx.home, 'AppData', 'Local', 'pnpm', 'bin', 'pnpm.cmd')]
    : [path.join(ctx.home, '.local', 'share', 'pnpm', 'pnpm'), '/usr/local/bin/pnpm'];
  return candidates.find((item) => U.exists(item)) || null;
}

function profileDirOf(plugin, agentCtx) {
  // `paths` is per-agent context, not the global one; falling back to ctx.paths resolved
  // a non-existent directory and made every spawn fail with ENOENT.
  const base = agentCtx?.paths?.extra?.profile || path.join(ctx.home, '.dsh', 'profiles');
  return plugin.profile ? path.join(path.dirname(base), plugin.profile) : base;
}

function pluginInstalled(dir, name) {
  const pkg = R.readJsonIfExists(path.join(dir, 'package.json'));
  if (!pkg) return false;
  const dep = Boolean(pkg.dependencies?.[name]);
  const bundle = (pkg.dsh?.profile?.bundles || []).includes(name);
  return dep && bundle;
}

/** Plugin CLIs live in the profile's own node_modules/.bin, not on the global PATH. */
function pluginBin(dir, name) {
  const local = path.join(dir, 'node_modules', '.bin', U.isWin ? `${name}.cmd` : name);
  return U.exists(local) ? local : null;
}

function pluginStatus(dir, plugin) {
  if (!plugin.verifyCmd) return { ok: false, detail: 'chua cau hinh lenh kiem tra' };
  const bin = pluginBin(dir, plugin.verifyCmd);
  if (!bin) return { ok: false, detail: 'khong tim thay CLI trong profile' };
  const r = U.run(bin, plugin.verifyArgs || [], { allowFail: true, timeout: 60000, cwd: dir });
  return r.ok && r.status === 0
    ? { ok: true, detail: 'kiem tra thanh cong (exit 0)' }
    : { ok: false, detail: `kiem tra that bai (exit ${r.status})` };
}

function verifyPlugin(c, plugin) {
  const dir = profileDirOf(plugin, c);
  if (!pluginInstalled(dir, plugin.package)) return V.result(`plugin:${plugin.id}`, 'WARN', 'chua cai hoac chua cau hinh bundle');
  const status = pluginStatus(dir, plugin);
  return V.result(`plugin:${plugin.id}`, status.ok ? 'PASS' : 'FAIL', status.detail);
}

/**
 * DSH guard plugins (e.g. cc-safety-net) are profile bundles: they hook the tool
 * registry instead of using a hook command, so they are installed through pnpm.
 * Check first, ask consent, install, then verify before moving on.
 */
async function ensurePlugin(c, plugin) {
  const dir = profileDirOf(plugin, c);
  if (pluginInstalled(dir, plugin.package)) {
    const row = verifyPlugin(c, plugin);
    if (row.status === 'PASS') U.log.skip(`${plugin.id}: ${row.detail}`);
    else {
      U.log.error(`${plugin.id}: ${row.detail}`);
      ctx.guidance.push({ scope: `plugin:${plugin.id}`, steps: plugin.installGuidance || [] });
    }
    c.rows.push(row);
    return;
  }
  if (ctx.opts['skip-install']) {
    U.log.warn(`${plugin.id}: chua cai (bo qua theo --skip-install)`);
    c.rows.push(V.result(`plugin:${plugin.id}`, 'WARN', 'bo qua theo --skip-install'));
    ctx.guidance.push({ scope: `plugin:${plugin.id}`, steps: plugin.installGuidance || [] });
    return;
  }
  const consent = await D.askConsent(ctx, `[?] Chua co plugin chan xoa cung '${plugin.label}'. Cai ngay? [Y/n]: `, true);
  if (!consent) {
    U.log.warn(`${plugin.id}: nguoi dung tu choi cai -> lop bao ve xoa cung se khong hoat dong.`);
    c.rows.push(V.result(`plugin:${plugin.id}`, 'WARN', 'nguoi dung tu choi cai'));
    ctx.guidance.push({ scope: `plugin:${plugin.id}`, steps: plugin.installGuidance || [] });
    return;
  }
  const pnpm = pnpmPath();
  if (!pnpm) {
    U.log.error(`${plugin.id}: khong tim thay pnpm (dsh plugin can pnpm).`);
    c.rows.push(V.result(`plugin:${plugin.id}`, 'FAIL', 'thieu pnpm'));
    ctx.guidance.push({ scope: `plugin:${plugin.id}`, steps: plugin.installGuidance || [] });
    return;
  }
  const env = { ...process.env, PATH: `${path.dirname(pnpm)}${path.delimiter}${process.env.PATH || ''}` };
  U.log.info(`  cai plugin ${plugin.package} vao profile '${plugin.profile}' ...`);
  // dsh forwards to pnpm and must run from the profile directory.
  U.ensureDir(dir);
  const target = U.which('dsh') || 'dsh';
  const args = ['plugin', '--profile', plugin.profile, 'add', plugin.package];
  const r = U.run(target, args, { cwd: dir, allowFail: true, timeout: 600000, env });
  if (!r.ok || r.status !== 0 || !pluginInstalled(dir, plugin.package)) {
    const detail = !r.ok || r.status !== 0 ? `cai dat that bai (exit ${r.status})` : 'cai dat thieu metadata';
    U.log.error(`${plugin.id}: ${detail}`);
    c.rows.push(V.result(`plugin:${plugin.id}`, 'FAIL', detail));
    ctx.guidance.push({ scope: `plugin:${plugin.id}`, steps: plugin.installGuidance || [] });
    return;
  }
  const row = verifyPlugin(c, plugin);
  if (row.status === 'PASS') U.log.ok(`${plugin.id} -> ${row.detail}`);
  else {
    U.log.error(`${plugin.id}: ${row.detail}`);
    ctx.guidance.push({ scope: `plugin:${plugin.id}`, steps: plugin.installGuidance || [] });
  }
  c.rows.push(row);
}

function finish(report, opts, manifests, mode) {
  const rows = report.results;
  const counts = V.summarize(rows);
  const payload = {
    engine: ENGINE_VERSION, mode, platform: process.platform,
    targets: report.targets.map((t) => t.id),
    phases: [...new Set(ctx.phases.map((p) => p.id))],
    counts,
    blockedMcp: [...ctx.blockedMcp],
    guidance: ctx.guidance,
    results: rows, warnings: ctx.warnings, errors: ctx.errors
  };
  if (opts.report) {
    U.writeFileAtomic(opts.report, `${JSON.stringify(payload, null, 2)}\n`);
    U.log.info(`\nBao cao: ${opts.report}`);
  }
  if (!opts.json && (ctx.blockedMcp.size || ctx.guidance.length)) {
    U.log.info('\n----------------------------------------------------------------');
    U.log.info('HUONG XU LY CHO CAC MUC CHUA CAI DUOC');
    U.log.info('----------------------------------------------------------------');
    if (ctx.blockedMcp.size) U.log.info(`  MCP bi bo qua: ${[...ctx.blockedMcp].join(', ')}`);
    for (const item of ctx.guidance) {
      U.log.info(`  [${item.scope}]`);
      for (const step of item.steps) U.log.info(`      - ${step}`);
    }
    U.log.info('  Sau khi xu ly xong: chay lai installer (hoac --doctor) de kiem tra lai.');
  }
  if (opts.json) process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
  U.log.info(`\n${'='.repeat(64)}`);
  U.log.info(` KET QUA: PASS=${counts.PASS} WARN=${counts.WARN} FAIL=${counts.FAIL} SKIP=${counts.SKIP} (${mode})`);
  U.log.info(`${'='.repeat(64)}`);
  ctx.prompt.close();
  if (counts.FAIL > 0) process.exit(1);
  if (counts.WARN > 0 && opts.strict) process.exit(1);
}

main().catch((error) => {
  U.log.error(error.stack || error.message);
  process.exit(1);
});






function isWindows() { return process.platform === 'win32'; }

