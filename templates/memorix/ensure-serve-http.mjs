import { spawn } from 'node:child_process';
import fs from 'node:fs';
import net from 'node:net';
import path from 'node:path';

const HOST = '127.0.0.1';
const rawPort = Number(process.env.MEMORIX_HTTP_PORT ?? 3211);
const PORT = Number.isInteger(rawPort) && rawPort > 0 && rawPort <= 65535 ? rawPort : 3211;

function isPortListening(port, host) {
  return new Promise((resolve) => {
    const sock = net.createConnection({ port, host });
    const done = (ok) => {
      sock.removeAllListeners();
      sock.destroy();
      resolve(ok);
    };
    sock.setTimeout(300);
    sock.once('connect', () => done(true));
    sock.once('timeout', () => done(false));
    sock.once('error', () => done(false));
  });
}

async function main() {
  if (await isPortListening(PORT, HOST)) return;

  const nodeBin = fs.realpathSync(process.execPath);
  const nodeDir = path.dirname(nodeBin);
  const candidates = [
    path.join(nodeDir, 'node_modules', 'memorix', 'dist', 'cli', 'index.js'),
    path.resolve(nodeDir, '..', 'lib', 'node_modules', 'memorix', 'dist', 'cli', 'index.js')
  ];
  const cliJs = candidates.find((p) => fs.existsSync(p));
  if (!cliJs) {
    process.stderr.write('[memorix-autostart] Cannot locate memorix/dist/cli/index.js\n');
    process.exit(1);
  }

  const child = spawn(nodeBin, [cliJs, 'serve-http', '--port', String(PORT)], {
    detached: true,
    stdio: 'ignore',
    windowsHide: true,
    cwd: process.env.USERPROFILE || process.env.HOME || nodeDir
  });
  child.unref();
}

main().catch(() => process.exit(1));
