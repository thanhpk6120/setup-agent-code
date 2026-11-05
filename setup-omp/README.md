# setup-omp

> **Deprecated:** thư mục này chỉ còn shim tương thích ngược. Toàn bộ logic nằm trong engine dùng chung ở [README gốc](../README.md).

## Cài đặt

```powershell
..\install.ps1 -Target omp            # Windows
```
```bash
../install.sh --target omp            # macOS / Linux
```

`bootstrap.ps1` / `install.ps1` trong thư mục này in cảnh báo deprecated và gọi engine chung.

## File được ghi

| Loại | Đường dẫn |
|---|---|
| Context (session) | `~/.omp/agent/AGENTS.md` |
| Sticky rules (always-apply) | `~/.omp/agent/RULES.md` |
| MCP | `~/.omp/agent/mcp.json` |
| Cấu hình | `~/.omp/agent/config.yml`, `~/.omp/agent/models.yml` |
| Skills | `~/.omp/agent/skills/` |
| Trash Guard | `~/.omp/extensions/no-hard-delete.ts` |

**Không cài `SYSTEM.md`**: file đó thay thế toàn bộ system prompt mặc định của OMP. Nếu tồn tại từ bản cũ, engine cảnh báo và chuyển vào Thùng rác.

Chi tiết option, MCP, verify: xem [README gốc](../README.md).
