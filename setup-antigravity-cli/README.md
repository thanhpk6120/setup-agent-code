# Setup Antigravity CLI (Google agy)

Bộ công cụ tự động hóa thiết lập môi trường cho **Antigravity CLI** (Google Gemini agy).

## Cấu trúc thư mục đích
- `~/.gemini/antigravity-cli/settings.json` (cấu hình agent, MCP servers, quyền hạn, telemetry)
- `~/.gemini/antigravity-cli/keybindings.json` (phím tắt điều khiển artifact review và cancel)
- `~/.gemini/antigravity-cli/AGENTS.md` (chỉ thị vận hành agent tiêu chuẩn)
- `~/.gemini/antigravity-cli/skills/` (kho kỹ năng chuẩn từ setup-omp)
- `~/.gemini/antigravity-cli/hooks/` (hook chặn xóa cứng Trash Guard)

## Cách cài đặt
Trước khi chạy, có thể tạo file `.env` từ template mẫu:
```powershell
copy templates\.env.example .env
```

```powershell
# Chạy trực tuyến qua bootstrap
.\install.ps1

# Hoặc chạy trực tiếp bootstrap với tham số
.\bootstrap.ps1 -Force
```
