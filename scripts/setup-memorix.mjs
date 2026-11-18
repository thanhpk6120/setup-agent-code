#!/usr/bin/env node
/**
 * Full Memorix setup helper for a new machine (Windows / macOS / Linux):
 * - Installs `memorix` + `fastembed` (--allow-scripts=onnxruntime-node)
 * - Installs `memorix-mcp-wrapper.mjs`, `ensure-serve-http.mjs`, `prune-snapshots.mjs`
 * - Initializes `~/.memorix/config.toml` from `templates/memorix/config.toml.example` (never overwrites existing unless --force-config)
 * - Installs OS auto-start for `memorix serve-http` (port 3211) and starts it immediately
 */
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

function parseArgs(argv) {
  const opts = {
    apiKey: process.env.OPENROUTER_API_KEY || '',
    model: 'baidu/ernie-5.5-flash-preview:free',
    home: os.homedir(),
    skipFastembed: false,
    noAutostart: false,
    forceConfig: false,
    prune: false,
    dryRun: false
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--api-key' && argv[i + 1]) opts.apiKey = argv[++i];
    else if (a === '--model' && argv[i + 1]) opts.model = argv[++i];
    else if (a === '--home' && argv[i + 1]) opts.home = path.resolve(argv[++i]);
    else if (a === '--skip-fastembed') opts.skipFastembed = true;
    else if (a === '--no-autostart') opts.noAutostart = true;
    else if (a === '--force-config') opts.forceConfig = true;
    else if (a === '--prune') opts.prune = true;
    else if (a === '--dry-run') opts.dryRun = true;
    else if (a === '--help' || a === '-h') opts.help = true;
  }
  return opts;
}

function printHelp() {
  console.log(`Usage: node scripts/setup-memorix.mjs [options]

Options:
  --api-key <key>     OpenRouter API key for ~/.memorix/config.toml (or set OPENROUTER_API_KEY)
  --model <slug>      LLM model slug (default: baidu/ernie-5.5-flash-preview:free)
  --home <dir>        Target home directory (default: os.homedir())
  --skip-fastembed    Skip installing optional fastembed package
  --no-autostart      Skip OS auto-start registration and starting serve-http
  --force-config      Overwrite existing ~/.memorix/config.toml
  --prune             Run prune-snapshots.mjs after setup
  --dry-run           Show actions without writing files or running npm
`);
}

function stableNodeExe() {
  try {
    return fs.realpathSync(process.execPath);
  } catch {
    return process.execPath;
  }
}

function findGlobalModule(pkgName) {
  const nodeDir = path.dirname(stableNodeExe());
  const candidates = [
    path.join(nodeDir, 'node_modules', pkgName, 'package.json'),
    path.resolve(nodeDir, '..', 'lib', 'node_modules', pkgName, 'package.json')
  ];
  return candidates.some((p) => fs.existsSync(p));
}

function runNpm(args, dryRun) {
  const cmd = process.platform === 'win32' ? 'npm.cmd' : 'npm';
  if (dryRun) {
    console.log(`[dry-run] ${cmd} ${args.join(' ')}`);
    return true;
  }
  const res = spawnSync(cmd, args, { stdio: 'inherit', shell: process.platform === 'win32' });
  return res.status === 0;
}

function copyFileSynced(src, dest, dryRun) {
  const content = fs.readFileSync(src, 'utf8');
  if (fs.existsSync(dest) && fs.readFileSync(dest, 'utf8') === content) {
    console.log(`[ok] unchanged: ${dest}`);
    return;
  }
  if (dryRun) {
    console.log(`[dry-run] write ${dest}`);
    return;
  }
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, content, 'utf8');
  console.log(`[ok] wrote ${dest}`);
}

function installAutostart(homeDir, nodeExe, ensureScript, dryRun) {
  if (process.platform === 'win32') {
    const startupDir = path.join(homeDir, 'AppData', 'Roaming', 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Startup');
    const vbsPath = path.join(startupDir, 'memorix-serve-http.vbs');
    const vbs = [
      'Set FSO = CreateObject("Scripting.FileSystemObject")',
      'Set WshShell = CreateObject("WScript.Shell")',
      `nodeExe = "${nodeExe.replace(/"/g, '""')}"`,
      'If Not FSO.FileExists(nodeExe) Then nodeExe = "node"',
      `WshShell.Run """" & nodeExe & """ ""${ensureScript.replace(/"/g, '""')}""", 0, False`,
      ''
    ].join('\r\n');
    if (dryRun) {
      console.log(`[dry-run] write ${vbsPath}`);
      return;
    }
    fs.mkdirSync(startupDir, { recursive: true });
    fs.writeFileSync(vbsPath, vbs, 'utf8');
    console.log(`[ok] autostart (Windows Startup): ${vbsPath}`);
    return;
  }

  if (process.platform === 'darwin') {
    const plistDir = path.join(homeDir, 'Library', 'LaunchAgents');
    const plistPath = path.join(plistDir, 'com.memorix.serve-http.plist');
    const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.memorix.serve-http</string>
  <key>ProgramArguments</key>
  <array>
    <string>${nodeExe}</string>
    <string>${ensureScript}</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
`;
    if (dryRun) {
      console.log(`[dry-run] write ${plistPath}`);
      return;
    }
    fs.mkdirSync(plistDir, { recursive: true });
    fs.writeFileSync(plistPath, plist, 'utf8');
    console.log(`[ok] autostart (macOS LaunchAgent): ${plistPath}`);
    return;
  }

  const autostartDir = path.join(homeDir, '.config', 'autostart');
  const desktopPath = path.join(autostartDir, 'memorix-serve-http.desktop');
  const desktop = `[Desktop Entry]
Type=Application
Name=Memorix HTTP Server
Exec="${nodeExe}" "${ensureScript}"
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
`;
  if (dryRun) {
    console.log(`[dry-run] write ${desktopPath}`);
    return;
  }
  fs.mkdirSync(autostartDir, { recursive: true });
  fs.writeFileSync(desktopPath, desktop, 'utf8');
  console.log(`[ok] autostart (Linux XDG): ${desktopPath}`);
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    printHelp();
    return;
  }

  const nodeExe = stableNodeExe();
  console.log(`[info] Node: ${nodeExe}`);
  console.log(`[info] Home: ${opts.home}`);

  if (!findGlobalModule('memorix')) {
    console.log('[step] Installing memorix globally...');
    if (!runNpm(['install', '-g', 'memorix'], opts.dryRun)) {
      console.error('[error] Failed to install memorix.');
      process.exit(1);
    }
  } else {
    console.log('[ok] memorix already installed.');
  }

  if (!opts.skipFastembed) {
    if (!findGlobalModule('fastembed')) {
      console.log('[step] Installing fastembed globally (with onnxruntime-node script)...');
      if (!runNpm(['install', '-g', 'fastembed', '--allow-scripts=onnxruntime-node'], opts.dryRun)) {
        console.warn('[warn] fastembed installation failed; continuing without local vector embedding.');
      }
    } else {
      console.log('[ok] fastembed already installed.');
    }
  }

  const memorixDir = path.join(opts.home, '.memorix');
  const wrapperDest = path.join(opts.home, 'mcp-servers', 'memorix', 'memorix-mcp-wrapper.mjs');
  const ensureDest = path.join(memorixDir, 'ensure-serve-http.mjs');
  const pruneDest = path.join(memorixDir, 'prune-snapshots.mjs');

  copyFileSynced(path.join(ROOT, 'templates', 'hooks', 'memorix-mcp-wrapper.mjs'), wrapperDest, opts.dryRun);
  copyFileSynced(path.join(ROOT, 'templates', 'memorix', 'ensure-serve-http.mjs'), ensureDest, opts.dryRun);
  copyFileSynced(path.join(ROOT, 'templates', 'memorix', 'prune-snapshots.mjs'), pruneDest, opts.dryRun);

  const configDest = path.join(memorixDir, 'config.toml');
  if (!fs.existsSync(configDest) || opts.forceConfig) {
    let tpl = fs.readFileSync(path.join(ROOT, 'templates', 'memorix', 'config.toml.example'), 'utf8');
    if (opts.apiKey) tpl = tpl.replace(/<OPENROUTER_API_KEY>/g, opts.apiKey);
    if (opts.model) tpl = tpl.replace(/baidu\/ernie-5\.5-flash-preview:free/g, opts.model);
    if (opts.dryRun) {
      console.log(`[dry-run] write ${configDest}`);
    } else {
      fs.mkdirSync(memorixDir, { recursive: true });
      fs.writeFileSync(configDest, tpl, 'utf8');
      console.log(`[ok] wrote ${configDest}${opts.apiKey ? '' : ' (remember to replace <OPENROUTER_API_KEY>)'}`);
    }
  } else {
    console.log(`[ok] keeping existing ${configDest}`);
  }

  if (!opts.noAutostart) {
    installAutostart(opts.home, nodeExe, ensureDest, opts.dryRun);
    if (!opts.dryRun) {
      spawnSync(nodeExe, [ensureDest], { stdio: 'inherit' });
    } else {
      console.log(`[dry-run] ${nodeExe} ${ensureDest}`);
    }
  }

  if (opts.prune) {
    if (opts.dryRun) {
      console.log(`[dry-run] ${nodeExe} ${pruneDest}`);
    } else {
      spawnSync(nodeExe, [pruneDest], { stdio: 'inherit' });
    }
  }

  console.log('\nDone. Next: run `memorix doctor` (or `.\install.ps1 -EnableMemorix` / `./install.sh --memorix` to attach MCP & hooks to all coding agents).');
}

main();
