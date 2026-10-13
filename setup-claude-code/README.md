# setup-claude-code

Hệ thống tự động hóa cài đặt, cấu hình và tối ưu hóa môi trường cho **Claude Code CLI** trên Windows (PowerShell), bám sát kiến trúc an toàn, thông minh và tinh gọn (chuẩn hóa theo kiến trúc `setup-omp`).

Bộ cài đặt tự động thiết lập toàn diện:
- **Claude Code CLI**: Tự động phát hiện, hướng dẫn cài đặt chính thức từ Anthropic và tự nạp lại PATH.
- **Cấu hình chuẩn hóa**: Quản lý tập trung qua thư mục `templates/` (`~/.claude.json`, `~/.claude/settings.json`, `~/.claude/CLAUDE.md`).
- **Hệ sinh thái MCP Servers**: Tích hợp sẵn `gitnexus`, `company-atlassian`, `context7`, `glab`, `cloakbrowser` và tùy chọn `memorix`.
- **Cơ chế giải quyết xung đột thông minh**: Hỗ trợ `[O]verwrite` (Ghi đè), `[M]erge` (Hợp nhất cấu hình) và `[S]kip` (Bỏ qua), luôn tự động sao lưu an toàn `.bak`.
- **TrashGuard (Bảo vệ an toàn dữ liệu)**: Chặn đứng mọi lệnh xoá vĩnh viễn, bắt buộc chuyển file/thư mục vào Thùng rác (Windows Recycle Bin).
- **Bộ kỹ năng chuyên sâu (`skills/`)**: Cung cấp sẵn các kỹ năng kiểm thử lặp (TDD, Unit Test 90% coverage), rà soát bảo mật (Security Review, Secret Scanning), kiến trúc và quy trình phân rã task.

---

## 1. Cài đặt nhanh (1 dòng lệnh duy nhất)

Mở PowerShell (hỗ trợ cả PowerShell 7 `pwsh` và Windows PowerShell) và chạy lệnh sau:

```powershell
irm https://raw.githubusercontent.com/thanhpk6120/setup-claude-code/main/install.ps1 | iex
```

### Các cờ nâng cao (Advanced Flags)

Bạn có thể truyền các tham số tùy chọn khi chạy script cài đặt:

| Cờ (Flag) | Kiểu dữ liệu | Ý nghĩa & Hành vi |
|---|---|---|
| `-EnableMemorix` | `[switch]` | Bật cài đặt Memorix (MCP Server & Hooks) tự động mà không cần hỏi tương tác. |
| `-DisableMemorix` | `[switch]` | Bỏ qua hoàn toàn Memorix, giữ môi trường khởi động nhanh và siêu nhẹ (khuyến nghị). |
| `-Force` / `-OverwriteAll` | `[switch]` | Tự động sao lưu cấu hình cũ (`.bak`) và ghi đè toàn bộ cấu hình mới, không dừng hỏi xác nhận. |
| `-DryRun` | `[switch]` | Chạy chế độ mô phỏng kiểm tra; không tải package, không ghi file thật. |
| `-SkipInstall` | `[switch]` | Bỏ qua bước tải/cài đặt các công cụ bên ngoài (Node global, uv, glab), chỉ tạo và cập nhật cấu hình. |
| `-ClaudeDir <path>` | `[string]` | Đường dẫn thư mục cấu hình Claude Code tùy chỉnh (mặc định: `$env:USERPROFILE\.claude`). |

### Ví dụ sử dụng nâng cao

Chạy cài đặt tự động không dùng Memorix và tự động ghi đè cấu hình:

```powershell
# Chạy trực tiếp qua mạng với tham số:
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/thanhpk6120/setup-claude-code/main/install.ps1))) -DisableMemorix -Force

# Hoặc nếu chạy từ mã nguồn cục bộ sau khi clone:
.\install.ps1 -DisableMemorix -Force
```

---

## 2. Luồng tương tác thông minh từng bước (Workflow)

Quá trình cài đặt diễn ra mạch lạc qua 4 bước tự động hóa thông minh:

```text
[Bước 1: Kiểm tra CLI] ──► [Bước 2: Cấu hình AI & Token] ──► [Bước 3: Tùy chọn Memorix] ──► [Bước 4: Giải quyết xung đột]
       │                                                                                             │
       ▼                                                                                             ▼
Tự động cài & nạp PATH                                                                   [O]verwrite / [M]erge / [S]kip
```

### Bước 1: Tự động kiểm tra Claude Code CLI
- Hệ thống quét lệnh `claude` trong `$env:PATH`.
- Nếu chưa có: Nhận diện terminal và hiển thị câu hỏi:
  `Claude Code CLI chưa được cài đặt. Bạn có muốn cài đặt Claude Code chính gốc ngay bây giờ không? [Y/n]: `
- Khi người dùng đồng ý (nhấn Enter hoặc `Y`):
  - Chạy lệnh cài đặt chính thức từ Anthropic: `npm install -g @anthropic-ai/claude-code`.
  - Tự động nạp lại `$env:PATH` ngay trong phiên PowerShell hiện tại (quét qua npm global prefix, AppData...). Lệnh `claude` có thể sử dụng ngay mà không cần khởi động lại Terminal.

### Bước 2: Hỏi cấu hình thông minh (Interactive Configuration)
Script thu thập các thông tin cấu hình cần thiết để thiết lập môi trường:
1. **AI Base URL**: Mặc định là `http://localhost:20128/v1` (nhấn Enter để chọn mặc định).
2. **AI API Key**: **Bắt buộc nhập**. Hệ thống kiểm tra lặp; nếu để trống sẽ hiển thị cảnh báo đỏ và yêu cầu nhập lại, tuyệt đối không gán key giả định.
3. **Các tích hợp dịch vụ doanh nghiệp (Tùy chọn - nhấn Enter để bỏ qua)**:
   - `Jira URL` & `Jira Personal Token` (dành cho `company-atlassian`)
   - `Confluence URL` & `Confluence Personal Token` (dành cho `company-atlassian`)
   - `GitLab Host` & `GitLab Token` (dành cho `glab`)
   - `Context7 API Key` (dành cho `context7` - tăng giới hạn rate limit tra cứu tài liệu)

### Bước 3: Tùy chọn cài đặt Memorix (Opt-in Memory)
- Nếu chưa truyền cờ `-EnableMemorix` hay `-DisableMemorix`, script sẽ hỏi:
  `Bạn có muốn cài đặt Memorix (MCP & Session Memory) không? [y/N]: `
- **Mặc định là [N]** (không cài đặt) để giữ cho Claude Code môi trường nhẹ nhất, khởi động tức thì.
- **Nếu chọn `y`**:
  - Tự động cài đặt package `@memorix/core` globally qua npm.
  - Tích hợp Memorix MCP Server vào `~/.claude.json`.
  - Cấu hình session hooks (`session_start`, `before_agent_start`, `session_compact`, `session_shutdown`) vào `settings.json`.
  - Bổ sung hướng dẫn Memorix Autopilot vào `CLAUDE.md` và sao chép các kỹ năng `memorix-*`.
- **Nếu chọn `N`**:
  - Không cài đặt Memorix, giữ cấu hình tinh gọn và sạch sẽ.
  - Tự động dọn dẹp các kỹ năng `memorix-*` cũ nếu từng tồn tại (chuyển vào Thùng rác an toàn).

### Bước 4: Kiểm tra và giải quyết xung đột cấu hình (Smart Conflict Resolution)
- Trước khi ghi bất kỳ file cấu hình nào (`~/.claude.json`, `~/.claude/settings.json`, `~/.claude/CLAUDE.md`), script kiểm tra xem file đã tồn tại hay chưa.
- Luôn tự động tạo bản sao lưu an toàn có đuôi `.bak` trước khi can thiệp.
- Đối với file cấu hình JSON (`.claude.json`, `settings.json`), người dùng được lựa chọn:
  - `[O]verwrite`: Ghi đè hoàn toàn bằng cấu hình chuẩn mới.
  - `[M]erge` (Khuyến nghị): Hợp nhất thông minh — giữ lại toàn bộ các MCP Server riêng, các thiết lập cá nhân đã có của người dùng, đồng thời bổ sung và cập nhật các mục mới từ bộ cài.
  - `[S]kip`: Bỏ qua, giữ nguyên file hiện tại.
- Đối với file văn bản (`CLAUDE.md`): Lựa chọn `[O]verwrite` hoặc `[S]kip`.

---

## 3. Cấu trúc thư mục dự án

Hệ thống được tổ chức chuẩn hóa với thư mục `templates/` đóng vai trò là nguồn chân lý (Source of Truth):

```text
setup-claude-code/
├── install.ps1                   # Script cài đặt trực tuyến 1 dòng qua PowerShell
├── bootstrap.ps1                 # Script thiết lập cốt lõi và khởi tạo môi trường
├── test-bootstrap.ps1            # Bộ kiểm thử tự động xác minh cài đặt và xử lý xung đột
├── CLAUDE.md                     # Quy tắc toàn cục cho Claude Code trong workspace này
├── README.md                     # Tài liệu hướng dẫn sử dụng chi tiết
├── .env.example                  # File mẫu biến môi trường ở thư mục gốc
├── templates/                    # Nguồn chân lý các file mẫu cấu hình (Templates)
│   ├── .env.example              # Mẫu biến môi trường đầy đủ (AI, Jira, Conf, GitLab, Context7)
│   ├── claude.json               # Mẫu cấu hình gốc cho ~/.claude.json (mcpServers, tools, config)
│   ├── settings.json             # Mẫu cấu hình settings chuẩn cho ~/.claude/settings.json
│   ├── CLAUDE.md                 # Mẫu hướng dẫn toàn cục tiêu chuẩn (không chứa Memorix)
│   └── memorix-claude-section.md # Phần tài liệu Memorix ghép nối vào CLAUDE.md khi bật
├── trash-guard/                  # Bộ công cụ bảo vệ Thùng rác (Recycle Bin Safe Guard)
│   ├── trash-guard.ps1           # Hook PowerShell ngăn chặn các lệnh xoá vĩnh viễn
│   ├── trash-cli.ps1             # Tiện ích xoá file an toàn qua Recycle Bin API
│   ├── trash-guard.sh            # Script bảo vệ dành cho môi trường Bash / Git Bash
│   ├── claude-pre-tool.ps1       # PreToolCall hook cho Claude Code
│   ├── claude-pre-tool.cmd       # Wrapper CMD cho PreToolCall hook
│   └── claude-pre-tool.js        # Wrapper Node.js cho PreToolCall hook
├── hud/                          # Tiện ích mở rộng hiển thị trạng thái (HUD/Statusline)
│   └── hud.mjs
└── skills/                       # Thư viện kỹ năng chuyên sâu cho Claude Code
    ├── react-impact-unittest-loop/  # Tạo test React tự động đạt coverage 90%
    ├── java-impact-unittest-loop/   # Phân tích ảnh hưởng và tạo test JUnit Mockito 90%
    ├── dotnet-impact-unittest-loop/ # Tạo test xUnit/Moq đạt coverage 90%
    ├── security-review/             # Kiểm tra lỗ hổng bảo mật mã nguồn
    ├── secret-scanning/             # Rà soát lộ API key, secrets, token
    ├── poka-yoke/                   # Kiểm toán chống lỗi lặp lại và trạng thái không hợp lệ
    ├── delivery/                    # Quy trình bàn giao phần mềm theo chuẩn Dely
    ├── create-plan/                 # Chuyển đổi yêu cầu thành kế hoạch kỹ thuật
    ├── implement-task/              # Thực thi checklist công việc chuẩn hóa
    ├── memorix-*/                   # Nhóm kỹ năng bộ nhớ (chỉ kích hoạt khi cài Memorix)
    └── ...
```

---

## 4. Danh sách MCP Servers & Tài liệu chính thức

Bộ cài đặt cấu hình sẵn các MCP Server hàng đầu phục vụ quy trình lập trình chuyên nghiệp:

| MCP Server | Nguồn tài liệu | Mô tả & Cách vận hành |
|---|---|---|
| **gitnexus** | [GitNexus MCP](https://github.com/abhigyanpatwari/GitNexus) | Trình phân tích đồ thị quan hệ mã nguồn (code graph, symbol index) tối ưu cho Claude Code. Cài đặt toàn cục qua `npm i -g gitnexus` và chạy bằng lệnh trực tiếp `gitnexus mcp`. |
| **company-atlassian** | [mcp-atlassian](https://mcp-atlassian.soomiles.com/docs/installation) | Tích hợp Jira và Confluence hai chiều. Được quản lý cài đặt tự động qua `uv tool install mcp-atlassian==0.23.1 --upgrade` và chạy trực tiếp bằng lệnh `mcp-atlassian`. |
| **context7** | [Upstash Context7](https://github.com/upstash/context7) | Tra cứu tài liệu thư viện, framework, SDK mới nhất theo thời gian thực. Cài đặt toàn cục qua `npm i -g @upstash/context7-mcp` và chạy trực tiếp qua Node.js script. |
| **glab** | [GitLab CLI MCP](https://gitlab.com/gitlab-org/cli) | GitLab CLI MCP Server chính thức từ GitLab, hỗ trợ tra cứu issue, MR, repo, CI/CD pipeline. Chạy qua lệnh `glab mcp serve`. |
| **cloakbrowser** | [CloakBrowser](https://github.com/thanhpk6120/setup-claude-code) | Trình duyệt Playwright tự động hóa phục vụ web scraping, kiểm thử giao diện và render PDF. Hỗ trợ quét chọn ổ đĩa lưu trữ (D:, C:) và bảo toàn dữ liệu profile cũ. |
| **memorix** *(Tùy chọn)* | [AVIDS2/memorix](https://github.com/AVIDS2/memorix) | Hệ thống bộ nhớ ngữ cảnh project và session dài hạn. Cài đặt qua `@memorix/core` và chạy qua `memorix serve --mode lite`. |

---

## 5. Cơ chế an toàn TrashGuard

Nhằm ngăn chặn rủi ro mất mát dữ liệu do AI tự động thực thi các lệnh xoá phá hủy (`rm -rf`, `Remove-Item -Recurse -Force`, `del /s /q`), hệ thống tích hợp **TrashGuard**:
- **PreToolCall Hook**: Can thiệp trước mỗi lần gọi công cụ bash/shell của Claude Code. Nếu phát hiện lệnh xoá vĩnh viễn, hook sẽ chặn lại và hướng dẫn sử dụng lệnh chuyển vào Thùng rác.
- **Recycle Bin API**: Mọi thao tác dọn dẹp file tạm, gỡ bỏ kỹ năng hoặc dọn dẹp bản sao lưu cũ đều bắt buộc sử dụng Windows API:
  ```powershell
  [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($path, 'OnlyErrorDialogs', 'SendToRecycleBin')
  [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($path, 'OnlyErrorDialogs', 'SendToRecycleBin')
  ```

---

## 6. Hướng dẫn sử dụng sau khi cài đặt

Sau khi hoàn tất cài đặt, bạn có thể khởi động Claude Code ngay trong bất kỳ thư mục dự án nào:

```powershell
# Di chuyển tới dự án của bạn
cd D:\Projects\MyProject

# Khởi chạy Claude Code
claude
```

Khi ở trong phiên làm việc của Claude Code:
- Gõ `/mcp` để kiểm tra danh sách các MCP Servers đang kết nối (`gitnexus`, `company-atlassian`, `context7`, `glab`, `cloakbrowser`).
- Nhập lệnh `/help` để xem các lệnh tích hợp sẵn.
- Claude Code sẽ tự động tuân thủ các quy tắc trong `CLAUDE.md`, sử dụng đúng các kỹ năng trong `skills/` và được bảo vệ bởi TrashGuard.

---

## 7. Chạy kiểm thử hệ thống

Để kiểm tra tính toàn vẹn của bộ cài đặt, template và cơ chế giải quyết xung đột mà không ảnh hưởng tới cấu hình máy thật:

```powershell
.\test-bootstrap.ps1
```

Bộ kiểm thử sẽ tự động chạy trong môi trường sandbox cô lập tại thư mục tạm của hệ thống để xác minh 100% các kịch bản:
1. Nhận diện Node.js, git, npm, uv.
2. Kiểm tra sinh cấu hình từ thư mục `templates/`.
3. Kiểm tra luồng bật/tắt Memorix chính xác.
4. Kiểm tra cơ chế giải quyết xung đột `[O]verwrite`, `[M]erge`, `[S]kip`.
5. Xác minh cơ chế an toàn Recycle Bin của TrashGuard.
