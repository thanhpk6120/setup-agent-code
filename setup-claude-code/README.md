# setup-claude-code

> **Deprecated:** thư mục này chỉ còn shim tương thích ngược. Toàn bộ logic nằm trong engine dùng chung ở [README gốc](../README.md).

## Cài đặt

```powershell
..\install.ps1 -Target claude-code
```
```bash
../install.sh --target claude-code
```

## File được ghi

| Loại | Đường dẫn |
|---|---|
| Instructions | `~/.claude/CLAUDE.md` |
| MCP | `~/.claude.json` |
| Settings (env, model, hooks, statusLine) | `~/.claude/settings.json` |
| Skills | `~/.claude/skills/` |
| Trash Guard hook | `~/.trash-guard/pre-tool.mjs` (đăng ký `PreToolUse`) |
| HUD statusline | `~/.claude/hud/hud.mjs` |

Ghi chú: `~/.claude/AGENTS.md` **không** được tạo — Claude Code chỉ đọc `AGENTS.md` ở project scope (v2.1.277+). Trên macOS/Linux, `CLAUDE_CODE_USE_POWERSHELL_TOOL` được tự động bỏ khỏi `settings.json`.

Chi tiết option, MCP, verify: xem [README gốc](../README.md).
