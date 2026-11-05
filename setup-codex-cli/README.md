# setup-codex-cli

> **Deprecated:** thư mục này chỉ còn shim tương thích ngược. Toàn bộ logic nằm trong engine dùng chung ở [README gốc](../README.md).

## Cài đặt

```powershell
..\install.ps1 -Target codex-cli
```
```bash
../install.sh --target codex-cli
```

## File được ghi

| Loại | Đường dẫn |
|---|---|
| Instructions | `~/.codex/AGENTS.md` |
| Cấu hình + MCP | `~/.codex/config.toml` (`[mcp_servers.<name>]`) |
| Skills | `~/.codex/skills/` |

`CODEX.md` không phải file global instruction → engine không tạo và sẽ dọn nếu tồn tại.

Chi tiết option, MCP, verify: xem [README gốc](../README.md).
