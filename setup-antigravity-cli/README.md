# setup-antigravity-cli

> **Deprecated:** thư mục này chỉ còn shim tương thích ngược. Toàn bộ logic nằm trong engine dùng chung ở [README gốc](../README.md).

## Cài đặt

```powershell
..\install.ps1 -Target antigravity-cli
```
```bash
../install.sh --target antigravity-cli
```

## File được ghi

| Loại | Đường dẫn |
|---|---|
| Global rules | `~/.gemini/AGENTS.md` |
| Cấu hình CLI + statusLine | `~/.gemini/antigravity-cli/settings.json` |
| MCP servers | `~/.gemini/config/mcp_config.json` |
| Hooks (`trash-guard`) | `~/.gemini/config/hooks.json` |
| Skills (global) | `~/.gemini/config/skills/` |
| Skills (CLI-only) | `~/.gemini/antigravity-cli/skills/` |
| Trash Guard hook | `~/.gemini/antigravity-cli/hooks/pre-tool.mjs` |
| HUD statusline | `~/.gemini/antigravity-cli/hud/hud.mjs` |

**Không** ghi `~/.gemini/antigravity-cli/AGENTS.md`, `~/.gemini/GEMINI.md`, hay `~/.gemini/config/{GEMINI.md,AGENTS.md}` (nếu tồn tại từ trước sẽ được chuyển vào Thùng rác để tránh nạp kép global rules). Binary `agy` do Google phát hành — installer chỉ cấu hình, không tự cài.

Chi tiết option, MCP, verify: xem [README gốc](../README.md).
