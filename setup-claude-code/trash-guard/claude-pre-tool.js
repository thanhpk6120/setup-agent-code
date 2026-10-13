#!/usr/bin/env node
const fs = require('fs');

const BLOCKED_MESSAGE = 
  "[LỖI NGHIÊM TRỌNG] Thao tác xóa cứng bị chặn!\n" +
  "QUY TẮC TIÊN QUYẾT: TUYỆT ĐỐI KHÔNG ĐƯỢC xoá cứng/xoá vĩnh viễn file hoặc thư mục.\n" +
  "BẮT BUỘC phải dùng lệnh di chuyển vào thùng rác (Trash / Recycle Bin).\n" +
  "Vui lòng dùng: trash <đường_dẫn>\n";

function checkCommand(cmd) {
  if (typeof cmd !== 'string' || !cmd.trim()) return false;
  // Match hard delete commands: rm, rmdir, del, erase, rd, ri, Remove-Item, unlink, shred
  const hardDeletePattern = /(?:^|[;&|`\s\(\$])(?:rm|rmdir|del|erase|rd|ri|Remove-Item|unlink|shred)(?:\.exe)?(?:\s+|$)/i;
  return hardDeletePattern.test(cmd);
}

function extractCommands(data) {
  const commands = [];
  if (!data) return commands;

  if (data.tool_input) {
    if (typeof data.tool_input === 'string') {
      commands.push(data.tool_input);
    } else if (typeof data.tool_input === 'object') {
      if (typeof data.tool_input.command === 'string') commands.push(data.tool_input.command);
      if (typeof data.tool_input.cmd === 'string') commands.push(data.tool_input.cmd);
      if (typeof data.tool_input.script === 'string') commands.push(data.tool_input.script);
    }
  }

  if (typeof data.command === 'string') commands.push(data.command);
  if (typeof data.cmd === 'string') commands.push(data.cmd);

  return commands;
}

try {
  const raw = fs.readFileSync(0, 'utf-8');
  if (raw && raw.trim()) {
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch {
      if (checkCommand(raw)) {
        process.stderr.write(BLOCKED_MESSAGE);
        process.exit(2);
      }
      process.exit(0);
    }

    const commands = extractCommands(parsed);
    for (const cmd of commands) {
      if (checkCommand(cmd)) {
        process.stderr.write(BLOCKED_MESSAGE);
        process.exit(2);
      }
    }
  }
} catch {
  process.exit(0);
}

process.exit(0);
