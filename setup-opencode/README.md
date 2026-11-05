# setup-opencode

> **Deprecated:** thư mục này chỉ còn shim tương thích ngược. Toàn bộ logic nằm trong engine dùng chung ở [README gốc](../README.md).

## Cài đặt

```powershell
..\install.ps1 -Target opencode
```
```bash
../install.sh --target opencode
```

## File được ghi

| Loại | Đường dẫn |
|---|---|
| Global rules | `~/.config/opencode/AGENTS.md` |
| Cấu hình + MCP + plugin | `~/.config/opencode/opencode.json` |
| Skills | `~/.config/opencode/skills/` |
| Trash Guard plugin | `~/.config/opencode/plugins/no-hard-delete.js` |

MCP dùng shape `{ "type": "local", "command": [bin, ...args], "environment": {...} }`.

Chi tiết option, MCP, verify: xem [README gốc](../README.md).
