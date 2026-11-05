#!/usr/bin/env node
// Cross-platform PreToolUse trash-guard for Antigravity CLI.
// Same contract as the Claude Code handler: block hard-delete commands, allow the rest.
import process from 'node:process';

const BLOCKED = [
  '[LOI NGHIEM TRONG] Thao tac xoa cung bi chan!',
  'QUY TAC TIEN QUYET: TUYET DOI KHONG duoc xoa cung/xoa vinh vien file hoac thu muc.',
  'BAT BUOC phai di chuyen vao thung rac (Trash / Recycle Bin).',
  'Vi du: trash <duong_dan>  |  Move to Recycle Bin.'
].join('\n');

const HARD_DELETE = /(?:^|[;&|`\s($])(?:rm|rmdir|del|erase|rd|ri|Remove-Item|unlink|shred)(?:\.exe)?(?:\s+|$)/i;
const SAFE = /(?:^|[;&|`\s($])(?:trash|Recycle|Move-Item\s+.*-Destination\s+\$?env:TEMP)\b/i;

function collectStrings(value, out = []) {
  if (typeof value === 'string') out.push(value);
  else if (Array.isArray(value)) value.forEach((item) => collectStrings(item, out));
  else if (value && typeof value === 'object') Object.values(value).forEach((item) => collectStrings(item, out));
  return out;
}

async function readStdin() {
  if (process.stdin.isTTY) return '';
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString('utf8');
}

function block(reason) {
  process.stdout.write(`${JSON.stringify({ decision: 'block', reason })}\n`);
  process.stderr.write(`${reason}\n`);
  process.exit(2);
}

const raw = await readStdin();
if (!raw.trim()) process.exit(0);

let payload;
try { payload = JSON.parse(raw); } catch { process.exit(0); }

const commands = collectStrings(payload.tool_input ?? payload.input ?? payload);
const commandText = commands.join('\n');
if (!commandText.trim()) process.exit(0);
if (SAFE.test(commandText)) process.exit(0);
if (HARD_DELETE.test(commandText)) block(BLOCKED);
process.exit(0);
