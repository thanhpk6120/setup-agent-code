# Setup Codex CLI

Bộ cài đặt tự động môi trường làm việc chuẩn hóa cho **OpenAI Codex CLI** trên Windows, tích hợp Router AI Gateway, MCP Servers (GitNexus, Atlassian Jira/Confluence, Context7, GitLab CLI, CloakBrowser, Memorix) và hệ thống Rules / Skills phân tầng.

---

## 1. Cài đặt nhanh (1 dòng lệnh)

Mở PowerShell (Run as Administrator hoặc User bình thường) và chạy:

```powershell
irm https://raw.githubusercontent.com/thanhpk6120/setup-codex-cli/main/install.ps1 | iex
```

### Các tùy chọn nâng cao:
* **Tự động chấp thuận toàn bộ (Unattended / CI):**
  ```powershell
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/thanhpk6120/setup-codex-cli/main/install.ps1))) -Force
  ```
* **Bỏ qua cài đặt gói tải về (dùng cho máy offline/đã có sẵn binary):**
  ```powershell
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/thanhpk6120/setup-codex-cli/main/install.ps1))) -SkipInstall
  ```

---

## 2. Kiến trúc & Vị trí cấu hình

* **Thư mục cấu hình:** `~/.codex/` (tức `%USERPROFILE%\.codex\`)
* **File cấu hình chính:** `~/.codex/config.toml`
* **Agent Guidelines:** `~/.codex/AGENTS.md` (đồng thời tạo alias `CODEX.md`)
* **Skills nghiệp vụ:** `~/.codex/skills/`

---

## 3. Danh mục MCP Servers tích hợp

Cấu hình MCP được sinh chuẩn TOML theo đặc tả của Codex CLI (`[mcp_servers.<name>]`):

| MCP Server | Chức năng | Command |
| :--- | :--- | :--- |
| **company-atlassian** | Tra cứu và cập nhật ticket Jira, tài liệu Confluence | `mcp-atlassian` |
| **gitnexus** | Lập bản đồ code graph, tra cứu symbol/reference | `cmd /c gitnexus.cmd mcp` |
| **context7** | Tra cứu tài liệu thư viện, SDK, framework trực tiếp | `node .../dist/index.js` |
| **glab** | Thao tác GitLab repository, issues, merge requests, CI pipelines | `glab mcp serve` |
| **cloakbrowser** | Tự động hóa trình duyệt web stealth, scraping, screenshot | `node mcp-server-full.mjs` |
| **memorix** | Lưu trữ và phục hồi trí nhớ dài hạn (project memory / reasoning) | `memorix serve --mode lite` |

---
## Trash Guard & Bảo vệ an toàn dữ liệu

Hệ thống áp dụng nghiêm ngặt nguyên tắc an toàn dữ liệu:
- **QUY TẮC TIÊN QUYẾT:** Mọi thao tác xóa tệp tin/thư mục bắt buộc phải di chuyển vào Thùng rác (Recycle Bin / Trash via `Safe-Trash` / `trash <path>`), TUYỆT ĐỐI KHÔNG xóa vĩnh viễn (`rm`, `Remove-Item`, `del`).
- **Dọn dẹp tự động:** Dọn dẹp an toàn các file legacy (`RULES.md`, `SYSTEM.md`) và file trùng ngoài `templates/` vào Recycle Bin.


## 4. Kiểm thử cô lập

Script đi kèm bộ kiểm thử tự động `test-bootstrap.ps1` kiểm tra assertion không làm thay đổi file thật trên máy:

```powershell
pwsh -NoProfile -File test-bootstrap.ps1
```
