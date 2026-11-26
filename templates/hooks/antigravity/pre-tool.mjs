#!/usr/bin/env node
// Cross-platform PreToolUse trash-guard for Antigravity CLI & App.
// Reads toolCall.args (or legacy tool_input/input) and outputs Antigravity PreToolUse JSON.
import fs from 'node:fs';
import process from 'node:process';

const BLOCKED = [
  '[LOI NGHIEM TRONG] Thao tac xoa cung bi chan!',
  'QUY TAC TIEN QUYET: TUYET DOI KHONG duoc xoa cung/xoa vinh vien file hoac thu muc.',
  'BAT BUOC phai di chuyen vao thung rac (Trash / Recycle Bin).',
  'Vi du: trash <duong_dan>  |  Move to Recycle Bin.'
].join('\n');

const HARD_DELETE = /(?:^|[;&|`\s($])(?:rm|rmdir|del|erase|rd|ri|Remove-Item|unlink|shred)(?:\.exe)?(?:\s+|$)/i;
const SAFE_STMT = /^(?:trash(?:-put)?|gio\s+trash|Recycle(?:-Item)?|Move-Item\s+.*-Destination\s+\$?env:TEMP)\b/i;
const COMMAND_KEYS = ['CommandLine', 'command', 'cmd', 'script', 'Script'];

function collectStrings(value, out = []) {
  if (typeof value === 'string') out.push(value);
  else if (Array.isArray(value)) value.forEach((item) => collectStrings(item, out));
  else if (value && typeof value === 'object') Object.values(value).forEach((item) => collectStrings(item, out));
  return out;
}

function extractCommandText(toolArgs) {
  if (typeof toolArgs === 'string' || Array.isArray(toolArgs)) {
    return collectStrings(toolArgs).join('\n');
  }
  if (!toolArgs || typeof toolArgs !== 'object') return '';
  const selected = [];
  for (const key of COMMAND_KEYS) {
    if (key in toolArgs) collectStrings(toolArgs[key], selected);
  }
  if (selected.length > 0) return selected.join('\n');
  // Fallback for unknown shapes, excluding descriptive metadata such as toolSummary.
  const rest = Object.entries(toolArgs)
    .filter(([key]) => key !== 'toolSummary' && key !== 'description')
    .map(([, val]) => val);
  return collectStrings(rest).join('\n');
}

function hasUnsafeHardDelete(commandText) {
  const segments = commandText.split(/[;&|\r\n`()]+/);
  return segments.some((segment) => {
    const stmt = segment.trim();
    if (!stmt) return false;
    if (SAFE_STMT.test(stmt)) return false;
    return HARD_DELETE.test(stmt);
  });
}

async function readStdin() {
  if (process.stdin.isTTY) return '';
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString('utf8');
}

function writeSyncStdout(text) {
  fs.writeSync(1, text);
}

async function main() {
  const raw = await readStdin();
  if (!raw.trim()) return;

  let payload;
  try { payload = JSON.parse(raw); } catch { return; }

  const toolArgs = payload?.toolCall?.args ?? payload?.tool_input ?? payload?.input;
  if (toolArgs == null) return;

  const commandText = extractCommandText(toolArgs);
  if (!commandText.trim()) return;

  if (hasUnsafeHardDelete(commandText)) {
    writeSyncStdout(`${JSON.stringify({ decision: 'deny', reason: BLOCKED })}\n`);
  }
}

await main();
