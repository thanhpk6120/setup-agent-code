import fs from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';

const rawKeep = Number(process.env.MEMORIX_KEEP_SNAPSHOTS ?? 5);
const KEEP_PER_PROJECT = Number.isInteger(rawKeep) && rawKeep >= 1 ? rawKeep : 5;
const DRY_RUN = process.argv.includes('--dry-run');

const nodeBin = fs.realpathSync(process.execPath);
const nodeDir = path.dirname(nodeBin);
const sqliteCandidates = [
  path.join(nodeDir, 'node_modules', 'memorix', 'node_modules', 'better-sqlite3'),
  path.join(nodeDir, 'node_modules', 'better-sqlite3'),
  path.resolve(nodeDir, '..', 'lib', 'node_modules', 'memorix', 'node_modules', 'better-sqlite3')
];
const sqlitePath = sqliteCandidates.find((p) => fs.existsSync(p));
if (!sqlitePath) {
  console.error('Cannot find better-sqlite3 near', nodeDir);
  process.exit(1);
}

const require = createRequire(import.meta.url);
const Database = require(sqlitePath);

const dbPath = path.join(os.homedir(), '.memorix', 'data', 'memorix.db');
if (!fs.existsSync(dbPath)) {
  console.error('Database not found:', dbPath);
  process.exit(1);
}

const sizeMB = (p) => (fs.existsSync(p) ? +(fs.statSync(p).size / (1024 * 1024)).toFixed(2) : 0);
const beforeDbMB = sizeMB(dbPath);
const beforeWalMB = sizeMB(`${dbPath}-wal`);

const db = new Database(dbPath);
db.pragma('busy_timeout = 10000');
db.pragma('foreign_keys = ON');

const obsBefore = db.prepare('SELECT COUNT(*) AS n FROM observations').get().n;
const snapsBefore = db.prepare('SELECT COUNT(*) AS n FROM code_state_snapshots').get().n;
const filesBefore = db.prepare('SELECT COUNT(*) AS n FROM code_state_snapshot_files').get().n;

const toDelete = db.prepare(`
  WITH ranked AS (
    SELECT id, projectId,
      ROW_NUMBER() OVER (PARTITION BY projectId ORDER BY indexedAt DESC, rowid DESC) AS rn
    FROM code_state_snapshots
  )
  SELECT id FROM ranked WHERE rn > ?
`).all(KEEP_PER_PROJECT).map((r) => r.id);

console.log(`Observations: ${obsBefore} (untouched)`);
console.log(`Snapshots: ${snapsBefore} | Snapshot files: ${filesBefore}`);
console.log(`Old snapshots to prune (keep latest ${KEEP_PER_PROJECT}/project): ${toDelete.length}`);
console.log(`Size before: db=${beforeDbMB} MB, wal=${beforeWalMB} MB`);

try {
  if (!DRY_RUN && toDelete.length > 0) {
    const tx = db.transaction((ids) => {
      const delSet = new Set(ids);
      const clearStmt = db.prepare('UPDATE code_state_snapshots SET previousSnapshotId = NULL WHERE previousSnapshotId = ?');
      for (const id of delSet) clearStmt.run(id);
      const delStmt = db.prepare('DELETE FROM code_state_snapshots WHERE id = ?');
      for (const id of ids) delStmt.run(id);
    });
    tx(toDelete);
  }

  const obsAfter = db.prepare('SELECT COUNT(*) AS n FROM observations').get().n;
  const snapsAfter = db.prepare('SELECT COUNT(*) AS n FROM code_state_snapshots').get().n;
  const filesAfter = db.prepare('SELECT COUNT(*) AS n FROM code_state_snapshot_files').get().n;
  if (obsAfter < obsBefore) {
    console.error(`SAFETY CHECK FAILED: observations decreased ${obsBefore} -> ${obsAfter}`);
    process.exitCode = 2;
  } else {
    console.log(`After prune: observations=${obsAfter}, snapshots=${snapsAfter}, snapshot_files=${filesAfter}`);

    if (!DRY_RUN) {
      try {
        db.exec('VACUUM');
        console.log('VACUUM: OK');
      } catch (e) {
        console.warn('VACUUM skipped (DB busy — close running memorix/agent processes and re-run):', e.message);
      }
      try {
        const ck = db.pragma('wal_checkpoint(TRUNCATE)');
        console.log('WAL checkpoint:', JSON.stringify(ck));
      } catch (e) {
        console.warn('WAL checkpoint skipped:', e.message);
      }
    }
  }
} finally {
  db.close();
}

console.log(`Size after: db=${sizeMB(dbPath)} MB, wal=${sizeMB(`${dbPath}-wal`)} MB`);
