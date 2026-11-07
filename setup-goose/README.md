# setup-goose

> **Goose agent harness (Block)**: MCP-native coding assistant. Toàn bộ logic cấu hình nằm trong engine dùng chung ở [README gốc](../README.md).

## Cài đặt

```powershell
..\install.ps1 -Target goose            # Windows
```
```bash
../install.sh --target goose            # macOS / Linux
```

## File được ghi

| Loại | Windows | macOS / Linux |
|---|---|---|
| Hướng dẫn (Global Hints) | `%APPDATA%\Block\goose\config\.goosehints` | `~/.config/goose/.goosehints` |
| Cấu hình & MCP Extensions | `%APPDATA%\Block\goose\config\config.yaml` | `~/.config/goose/config.yaml` |
| Skills | `%APPDATA%\Block\goose\config\skills\` | `~/.config/goose/skills/` |

Chi tiết option, MCP, verify: xem [README gốc](../README.md).
