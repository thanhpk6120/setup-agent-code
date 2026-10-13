# Setup OpenCode

Bộ cài đặt tự động môi trường làm việc chuẩn hóa cho **OpenCode** trên Windows, tích hợp Router AI Gateway, MCP Servers (GitNexus, Atlassian Jira/Confluence, Context7, GitLab CLI, CloakBrowser, Memorix) và hệ thống Rules / Skills phân tầng.

---

## 1. Cài đặt nhanh (1 dòng lệnh)

Mở PowerShell (Run as Administrator hoặc User bình thường) và chạy:

```powershell
irm https://raw.githubusercontent.com/thanhpk6120/setup-opencode/main/install.ps1 | iex
```

### Các tùy chọn nâng cao:
* **Tự động chấp thuận toàn bộ (Unattended / CI):**
  ```powershell
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/thanhpk6120/setup-opencode/main/install.ps1))) -Force
  ```
* **Bỏ qua cài đặt gói tải về (dùng cho máy offline/đã có sẵn binary):**
  ```powershell
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/thanhpk6120/setup-opencode/main/install.ps1))) -SkipInstall
  ```

---

## 2. Kiến trúc & Vị trí cấu hình

* **Thư mục cấu hình:** `~/.config/opencode/` (hoặc `%USERPROFILE%\.config\opencode\`)
* **File cấu hình chính:** `~/.config/opencode/opencode.json`
* **Agent Guidelines:** `~/.config/opencode/AGENTS.md`
* **Skills nghiệp vụ:** `~/.config/opencode/skills/`

---

## 3. Danh mục MCP Servers tích hợp

| MCP Server | Chức năng | Command |
| :--- | :--- | :--- |
| **company-atlassian** | Tra cứu và cập nhật ticket Jira, tài liệu Confluence | `mcp-atlassian` |
| **gitnexus** | Lập bản đồ code graph, tra cứu symbol/reference | `cmd /c gitnexus.cmd mcp` |
| **context7** | Tra cứu tài liệu thư viện, SDK, framework trực tiếp | `node .../dist/index.js` |
| **glab** | Thao tác GitLab repository, issues, merge requests, CI pipelines | `glab mcp serve` |
| **cloakbrowser** | Tự động hóa trình duyệt web stealth, scraping, screenshot | `node mcp-server-full.mjs` |
| **memorix** | Lưu trữ và phục hồi trí nhớ dài hạn (project memory / reasoning) | `memorix` |

---

## 4. Kiểm thử cô lập

Script đi kèm bộ kiểm thử tự động `test-bootstrap.ps1` kiểm tra assertion không làm thay đổi file thật trên máy:

```powershell
pwsh -NoProfile -File test-bootstrap.ps1
```
