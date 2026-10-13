# Setup DSH Web Runner (`dsh --profile web-runner`)

Bộ công cụ thiết lập môi trường cho **DeepSeek Harness Web Runner (Headless Server)**, phân biệt với profile desktop.

## Cấu trúc thư mục đích
- Profile web runner: `%APPDATA%\dsh-desktop\harness\profiles\web-runner\cordis.patch.yml`
- Credentials: `%APPDATA%\dsh-desktop\harness\.credentials.yaml`
- DSH Home: `~/.dsh/AGENTS.md`
- Skills: `~/.dsh/skills/`

## Đặc điểm cấu hình profile web
- Webserver host / port / tls cấu hình linh hoạt (`DSH_HOST`, `DSH_PORT`).
- Runtime headless: `openBrowser: false`, `printUrl: true`, `publicUrl` từ `DSH_PUBLIC_URL`.
- Danh sách `trustedHosts` cấu hình qua `DSH_TRUSTED_HOSTS`.
- Kích hoạt `session-query-sqlite` với chế độ `walMode: true`.
- Không lặp toàn bộ desktop telemetry sang web runner.
- Giữ đầy đủ MCP servers và kho 36 skills nghiệp vụ.

## Cách cài đặt
Trước khi cài đặt, có thể tạo file `.env` từ template mẫu:
```powershell
copy templates\.env.example .env
```

```powershell
# Chạy tương tác
.\install.ps1

# Hoặc bootstrap trực tiếp
.\bootstrap.ps1 -Force
```
