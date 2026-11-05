// scripts/validate.mjs - fail fast when the manifests are inconsistent.
// Used by CI and by `npm run validate`.
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as M from '../core/lib/manifest.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const manifests = M.loadManifests(ROOT);
const errors = M.validateManifests(manifests);

if (errors.length) {
  console.error(`Manifest khong hop le (${errors.length} loi):`);
  for (const error of errors) console.error(`  - ${error}`);
  process.exit(1);
}

const agents = manifests.agents.agents.map((a) => a.id);
const servers = manifests.mcp.servers.map((s) => s.id);
const deps = manifests.prereqs.deps.map((d) => d.id);
const prompts = manifests.prompts.prompts.map((p) => p.key);
const options = manifests.options.options.map((o) => o.id);
console.log(`OK: ${agents.length} agents, ${servers.length} MCP servers, ${deps.length} prerequisites, ${prompts.length} prompts, ${options.length} options`);
console.log(`agents : ${agents.join(', ')}`);
console.log(`mcp    : ${servers.join(', ')}`);
console.log(`deps   : ${deps.join(', ')}`);
