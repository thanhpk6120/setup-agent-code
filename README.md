# Setup Agent Code — Bộ Cài Đặt AI Coding Agents

> **Một lệnh duy nhất** để tự động cài đặt, cấu hình và thiết lập hoàn chỉnh **6 AI Coding Agent** hàng đầu trên cả **Windows** và **macOS / Linux**: **OMP**, **Claude Code**, **OpenCode**, **Codex CLI**, **DSH (DeepSeek Harness)**, và **Antigravity CLI (Google agy)**.

---

## 1. Cài Đặt Nhanh (Quickstart)

Chỉ cần mở terminal và chạy **1 dòng lệnh duy nhất**:

### Trên Windows (PowerShell 5.1 / 7+)

**Cài đặt toàn bộ 6 Agent (Khuyên dùng):**
```powershell
irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.ps1 | iex
```

**Hoặc cài đặt từng Agent riêng lẻ:**
```powershell
# Cài đặt OMP Agent
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.ps1))) -Target omp

# Cài đặt Claude Code
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.ps1))) -Target claude-code

# Cài đặt OpenCode
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.ps1))) -Target opencode

# Cài đặt Codex CLI (OpenAI)
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.ps1))) -Target codex-cli

# Cài đặt DSH (DeepSeek Harness)
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.ps1))) -Target dsh

# Cài đặt Antigravity CLI (Google agy)
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.ps1))) -Target antigravity-cli
```

---

### Trên macOS / Linux (Bash / Zsh)

**Cài đặt toàn bộ 6 Agent:**
```bash
curl -fsSL https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.sh | bash
```

**Hoặc cài đặt từng Agent riêng lẻ:**
```bash
# Cài đặt OMP Agent
curl -fsSL https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.sh | bash -s -- --target omp

# Cài đặt Claude Code
curl -fsSL https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.sh | bash -s -- --target claude-code

# Cài đặt OpenCode
curl -fsSL https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.sh | bash -s -- --target opencode

# Cài đặt Codex CLI (OpenAI)
curl -fsSL https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.sh | bash -s -- --target codex-cli

# Cài đặt DSH (DeepSeek Harness)
curl -fsSL https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.sh | bash -s -- --target dsh

# Cài đặt Antigravity CLI (Google agy)
curl -fsSL https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.sh | bash -s -- --target antigravity-cli
```

---

## 2. Danh Mục 6 Agent Được Hỗ Trợ

| Target | Tên Agent | Nhà Phát Triển | Vị Trí Cấu Hình (Windows) | Vị Trí Cấu Hình (macOS) |
|---|---|---|---|---|
| `omp` | **OMP Agent** | AIEGUU / OMP | `%USERPROFILE%\.omp\agent\` | `~/.omp/agent/` |
| `claude-code` | **Claude Code** | Anthropic | `%USERPROFILE%\.claude\` | `~/.claude/` |
| `opencode` | **OpenCode** | OpenCode AI | `%USERPROFILE%\.config\opencode\` | `~/.config/opencode/` |
| `codex-cli` | **Codex CLI** | OpenAI | `%USERPROFILE%\.codex\` | `~/.codex/` |
| `dsh` | **DSH CLI** | DeepSeek | `%APPDATA%\dsh-desktop\...` | `~/.dsh/` |
| `antigravity-cli`| **Antigravity** | Google | `%USERPROFILE%\.gemini\antigravity-cli\`| `~/.gemini/antigravity-cli/` |

---

## 3. Các Tính Năng Thông Minh & Độc Quyền

### 🔄 Khôi Phục Cấu Hình Thông Minh (Resume .env)
- Toàn bộ biến môi trường (AI Base URL, API Key, Token Jira/Confluence...) và các lựa chọn MCP/Hook được lưu vào file cấu hình cố định.
- **Nếu quá trình cài đặt gặp sự cố và bạn chạy lại**: Script sẽ tự động nhận diện cấu hình cũ và hỏi bạn có muốn tái sử dụng không.
- **Chỉ hỏi những biến chưa có**: Bạn không phải gõ lại API key hay chọn lại các MCP server đã chọn trước đó!

### 🛠️ Tự Động Can Thiệp Sửa Lỗi (Auto-Fix)
- Khi gặp lỗi phổ biến (EBUSY do file bị tiến trình khác khóa, lỗi PATH session chưa nhận command mới cài, xung đột package):
- Script sẽ **chủ động hỏi bạn trước**:
  `[?] Phat hien su co <ten_loi>. Ban co cho phep script tu can thiep sua loi khong? [Y/n]`
- Nếu bạn đồng ý, script sẽ tự động thực hiện xử lý (giải phóng khóa, nạp lại PATH, retry an toàn) rồi tiếp tục.

### ⏸️ Tạm Dừng Chờ Người Dùng Xác Nhận (Wait-User-Intervention)
- Đối với những lỗi cần người dùng can thiệp thủ công (ví dụ cần quyền Administrator, cần bật VPN, kiểm tra kết nối mạng):
- Script **tuyệt đối không bị crash hay thoát đột ngột**, mà sẽ in hướng dẫn xử lý chi tiết và dừng lại chờ:
  `[?] Sau khi ban da xu ly xong, nhan [Enter] de tiep tuc kiem tra lai hoac [c] de huy`
- Sau khi bạn xử lý xong ở cửa sổ khác và nhấn Enter, script sẽ kiểm tra lại điều kiện và tiếp tục cài đặt bình thường.

### 🛡️ Bảo Vệ Chống Xóa Cứng (Trash Guard)
- Toàn bộ 6 agent đều được tích hợp cơ chế bảo vệ mã nguồn tối đa:
- Chặn hoàn toàn các lệnh xóa vĩnh viễn (`rm -rf`, `del`, `Remove-Item`). Mọi thao tác xóa đều được chuyển hướng an toàn vào **Recycle Bin (Thùng rác)** của Windows hoặc `~/.Trash` của macOS.

### 🔌 Tích Hợp Sẵn 7 MCP Server Hàng Đầu
Mỗi agent khi cài đặt đều có thể kích hoạt ngay:
1. `company-atlassian`: Tra cứu, đọc/viết Jira Issue và Confluence Page.
2. `gitnexus`: Knowledge Graph & Code Intelligence diện rộng.
3. `context7`: Tra cứu tài liệu thư viện, framework, SDK mới nhất theo thời gian thực.
4. `glab`: Tích hợp GitLab CLI quản lý Issue, MR, Pipeline.
5. `cloakbrowser`: Tự động hóa trình duyệt chống phát hiện bot.
6. `memorix`: Bộ nhớ ngữ cảnh dài hạn qua nhiều phiên làm việc.
7. `agency`: Điều phối đa Agent chuyên gia (Software Architect, Security Reviewer, Code Reviewer...).

---

## 4. Bảng Tham Số Tùy Chọn

Khi chạy script cài đặt, bạn có thể truyền thêm các tham số:

| Tham số Windows | Tham số macOS | Ý nghĩa |
|---|---|---|
| `-Target <name>` | `--target <name>` | Chỉ định agent cần cài: `all`, `omp`, `claude-code`, `opencode`, `codex-cli`, `dsh`, `antigravity-cli`. |
| `-DryRun` | `--dry-run` | Chạy thử mô phỏng (WhatIf), không ghi file thật, không cài đặt thật. |
| `-SkipInstall` | `--skip-install` | Bỏ qua bước cài đặt binary agent CLI và các gói npm/uv, chỉ cấu hình file config. |
| `-Force` | `--force` | Tự động đồng ý tất cả MCP, ghi đè file cấu hình mà không hỏi xác nhận. |
| `-OverwriteAll` | — | Tự động ghi đè tất cả các file cấu hình đã có từ trước (vẫn tự động sao lưu `.bak`). |
| `-EnableMemorix` | `--enable-memorix` | Bật tính năng Memorix và copy toàn bộ 36 skills. |
| `-DisableMemorix` | `--disable-memorix`| Tắt Memorix và dọn sạch các skill liên quan đến Memorix. |

---

## 5. Cấu Hình Biến Môi Trường (.env)

Bạn có thể tạo file `.env` tại thư mục cài đặt hoặc nhập trực tiếp khi script hỏi:

```env
# AI Provider (Gateway hoặc Router local)
AI_BASE_URL=http://localhost:20128/v1
AI_API_KEY=your-api-key-here

# Atlassian (Jira & Confluence)
JIRA_URL=https://jira.yourcompany.com
JIRA_PERSONAL_TOKEN=your-jira-token
CONFLUENCE_URL=https://conf.yourcompany.com
CONFLUENCE_PERSONAL_TOKEN=your-confluence-token

# GitLab CLI
GITLAB_HOST=gitlab.yourcompany.com
GITLAB_TOKEN=your-gitlab-token

# Context7 (Tra cứu tài liệu trực tuyến)
CONTEXT7_API_KEY=your-context7-api-key
```

---

## 6. Xử Lý Sự Cố & Câu Hỏi Thường Gặp (FAQ)

### Q: Tôi vừa bị mất mạng khi đang cài đặt thì làm sao?
> **Đáp:** Bạn chỉ cần chạy lại câu lệnh cài đặt ban đầu. Script sẽ tự động nhận diện cấu hình bạn đã nhập trước đó và hỏi `[?] Ban co muon su dung lai cac bien da nhap khong? [Y/n]`. Bạn chỉ cần nhấn `Enter` là script sẽ tiếp tục cài đặt mà không bắt bạn nhập lại!

### Q: Làm sao để đổi API Key sau khi đã cài đặt?
> **Đáp:** Bạn có thể sửa trực tiếp trong file cấu hình của từng agent (ví dụ `~/.omp/agent/config.yml` hoặc `~/.claude/settings.json`) hoặc chạy lại installer và chọn `n` khi được hỏi có tái sử dụng cấu hình cũ không.

### Q: Khi cài đặt xong một số lệnh báo `Command not found`?
> **Đáp:** Bạn chỉ cần đóng cửa sổ terminal hiện tại và mở một cửa sổ terminal mới để nạp lại đầy đủ biến môi trường PATH hệ thống.

---

**Tác giả:** thanhpk  
**Giấy phép:** MIT License
