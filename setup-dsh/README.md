# setup-dsh (DeepSeek Harness)

> **Deprecated:** thư mục này chỉ còn shim tương thích ngược. Toàn bộ logic nằm trong engine dùng chung ở [README gốc](../README.md).

## Cài đặt

```powershell
..\install.ps1 -Target dsh
```
```bash
../install.sh --target dsh
```

## File được ghi

| Loại | Đường dẫn |
|---|---|
| Instructions | `~/.dsh/AGENTS.md` |
| Profile (MCP clients) | `~/.dsh/profiles/web/cordis.patch.yml` (fallback `%APPDATA%\dsh-desktop\harness\profiles\web`) |
| Credentials | `%APPDATA%\dsh-desktop\harness\.credentials.yaml` (fallback `~/.dsh/.credentials.yaml`) |
| Skills | `~/.dsh/skills/` |

Schema credentials: `version`, `refs`, `apiKey`, `records` — engine render từ `templates/dsh/.credentials.yaml`.

Chi tiết option, MCP, verify: xem [README gốc](../README.md).
