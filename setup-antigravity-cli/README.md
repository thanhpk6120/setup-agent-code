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
| Cấu hình + MCP + hooks | `~/.gemini/antigravity-cli/settings.json` |
| Keybindings | `~/.gemini/antigravity-cli/keybindings.json` |
| Skills (global) | `~/.gemini/config/skills/` |
| Skills (CLI-only) | `~/.gemini/antigravity-cli/skills/` |
| Trash Guard hook | `~/.gemini/antigravity-cli/hooks/pre-tool.mjs` |

**Không** ghi `~/.gemini/antigravity-cli/AGENTS.md` hay `~/.gemini/GEMINI.md` (không nằm trong danh sách global rules / trùng nội dung). Binary `agy` do Google phát hành — installer chỉ cấu hình, không tự cài.

Chi tiết option, MCP, verify: xem [README gốc](../README.md).
