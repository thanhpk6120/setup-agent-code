import { rename } from 'node:fs/promises';

const CODES = new Set(['EACCES', 'EBUSY', 'EPERM']);
export const name = 'safe-fs-replace';
export const inject = ['fs'];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function renameWithRetry(target, staged) {
  let delay = 20;
  for (let i = 0; ; i += 1) {
    try {
      await rename(staged, target);
      return;
    } catch (error) {
      if (!CODES.has(error?.code) || i >= 12) throw error;
    }
    await sleep(delay);
    delay = Math.min(delay * 2, 250);
  }
}

function patch(service) {
  if (!service?.internals) return false;
  service.internals.replaceFile = renameWithRetry;
  return true;
}

export function apply(ctx) {
  if (process.platform !== 'win32') return;
  const patched = patch(ctx.get('fs'));
  try { ctx.logger?.info?.(`[safe-fs-replace] active, patched=${patched}`); } catch {}
  try {
    ctx.on('internal/service', (n, v) => {
      if (n === 'fs') { try { patch(v); } catch {} }
    });
  } catch {}
}
