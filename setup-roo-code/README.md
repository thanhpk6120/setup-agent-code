# setup-roo-code

> **Roo Code (VS Code Extension)**: AI coding assistant chạy trong VS Code. Toàn bộ logic cấu hình nằm trong engine dùng chung ở [README gốc](../README.md).

## Cài đặt

```powershell
..\install.ps1 -Target roo-code            # Windows
```
```bash
../install.sh --target roo-code            # macOS / Linux
```

## File được ghi

| Loại | Windows | macOS / Linux |
|---|---|---|
| Hướng dẫn (Global Rules) | `%USERPROFILE%\.roo\rules\AGENTS.md` | `~/.roo/rules/AGENTS.md` |
| MCP Settings | `%APPDATA%\Code\User\globalStorage\rooveterinaryinc.roo-cline\settings\mcp_settings.json` | `~/.config/Code/User/globalStorage/rooveterinaryinc.roo-cline/settings/mcp_settings.json` (macOS: `~/Library/Application Support/...`) |
| Skills | `%USERPROFILE%\.roo\skills\` | `~/.roo/skills/` |

Chi tiết option, MCP, verify: xem [README gốc](../README.md).
