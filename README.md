# Setup Agent Code

Kho mã nguồn và bộ công cụ tự động hóa thiết lập môi trường làm việc chuẩn hóa cho các **AI Coding Agent CLI** trên nền tảng Windows (PowerShell). Dự án cung cấp quy trình bootstrap 1 chạm, cấu hình kết nối AI Gateway, tích hợp hệ sinh thái MCP Servers đồng nhất, thư viện kỹ năng (skills) chuyên sâu và cơ chế bảo vệ an toàn dữ liệu Trash Guard.

---

## 1. Tổng quan & Danh mục Agent CLI hỗ trợ

Repository đóng vai trò là kho quản lý tập trung (monorepo) chứa các gói cấu hình và kịch bản cài đặt cho từng agent coding:

| Thư mục | Agent CLI mục tiêu | Cấu hình sinh ra / Vị trí đích | Trạng thái |
|---|---|---|---|
| `setup-claude-code/` | **Claude Code CLI** (Anthropic) | `~/.claude.json`, `~/.claude/settings.json`, `~/.claude/CLAUDE.md` | Hoạt động đầy đủ |
| `setup-opencode/` | **OpenCode CLI** | `~/.config/opencode/opencode.json`, `~/.config/opencode/AGENTS.md` | Hoạt động đầy đủ |
| `setup-codex-cli/` | **OpenAI Codex CLI** | `~/.codex/config.toml`, `~/.codex/AGENTS.md` (alias `CODEX.md`) | Hoạt động đầy đủ |
| `setup-omp/` | **Oh My Prompt (OMP / Orca OMP)** | `~/.omp/agent/config.yml`, `~/.omp/agent/models.yml`, `~/.omp/agent/mcp.json`, `~/.omp/agent/AGENTS.md`, `~/.omp/agent/skills/`, `~/.omp/extensions/no-hard-delete.ts` | Hoạt động đầy đủ |
| `setup-dsh/` | **DeepSeek Harness (DSH Desktop)** | `%APPDATA%\dsh-desktop\harness\profiles\web\cordis.patch.yml`, `%APPDATA%\dsh-desktop\harness\.credentials.yaml`, `~/.dsh/AGENTS.md`, `~/.dsh/skills/` | Hoạt động đầy đủ |
| `setup-antigravity-cli/` | **Antigravity CLI** | `~/.gemini/antigravity-cli/settings.json`, `~/.gemini/antigravity-cli/keybindings.json`, `~/.gemini/antigravity-cli/AGENTS.md`, `~/.gemini/antigravity-cli/hooks/`, `~/.gemini/antigravity-cli/skills/` | Hoạt động đầy đủ |
| `setup-dsh-web/` | **DSH Web Runner** | `%APPDATA%\dsh-desktop\harness\profiles\web-runner\cordis.patch.yml`, `%APPDATA%\dsh-desktop\harness\.credentials.yaml`, `~/.dsh/AGENTS.md`, `~/.dsh/skills/` | Hoạt động đầy đủ |

---

## 2. Cấu trúc thư mục dự án

```text
setup-agent-code/
├── README.md                      # Tài liệu tổng quan toàn bộ dự án
│
├── setup-claude-code/             # Bộ cài đặt & cấu hình Claude Code CLI
│   ├── install.ps1                # Local runner: gọi bootstrap.ps1 nội bộ (không tải zip)
│   ├── bootstrap.ps1              # Script cài đặt chính và xử lý cấu hình
│   ├── test-bootstrap.ps1         # Bộ test assertion cô lập môi trường
│   ├── README.md                  # Tài liệu chi tiết cho Claude Code
│   ├── templates/                 # File mẫu nguồn: claude.json, settings.json, templates/CLAUDE.md, memorix-claude-section.md, templates/.env.example
│   ├── hud/hud.mjs                # HUD hiển thị trạng thái phiên Claude
│   └── trash-guard/               # Bộ hook & tiện ích Trash Guard chặn xóa vĩnh viễn
│
├── setup-opencode/                # Bộ cài đặt & cấu hình OpenCode CLI
│   ├── install.ps1                # Local runner: gọi bootstrap.ps1 nội bộ (không tải zip)
│   ├── bootstrap.ps1              # Script cài đặt chính và xử lý cấu hình
│   ├── test-bootstrap.ps1         # Bộ test assertion cô lập môi trường
│   ├── README.md                  # Tài liệu chi tiết cho OpenCode
│   └── templates/                 # File mẫu: opencode.json, templates/AGENTS.md, memorix-agents-section.md, templates/.env.example
│
├── setup-codex-cli/               # Bộ cài đặt & cấu hình OpenAI Codex CLI
│   ├── install.ps1                # Local runner: gọi bootstrap.ps1 nội bộ (không tải zip)
│   ├── bootstrap.ps1              # Script cài đặt chính và xử lý cấu hình
│   ├── test-bootstrap.ps1         # Bộ test assertion cô lập môi trường
│   ├── README.md                  # Tài liệu chi tiết cho Codex CLI
│   └── templates/                 # File mẫu: config.toml, templates/AGENTS.md, memorix-agents-section.md, templates/.env.example
│
├── setup-omp/                     # Bộ cài đặt & cấu hình Oh My Prompt (OMP)
│   ├── install.ps1                # Local runner: gọi bootstrap.ps1 nội bộ (không tải zip)
│   ├── bootstrap.ps1              # Script cài đặt chính và xử lý cấu hình
│   ├── test-bootstrap.ps1         # Bộ test assertion cô lập môi trường
│   ├── AGENTS.md / RULES.md / SYSTEM.md  # Bộ quy tắc agent, global rules và system prompt (root, ngoài templates/)
│   ├── README.md                  # Tài liệu chi tiết cho OMP
│   ├── templates/                 # File mẫu: config.yml, models.yml, mcp.json, memorix-agents-section.md, templates/.env.example
│   ├── extensions/no-hard-delete.ts  # Extension chặn lệnh xóa cứng OMP
│   ├── mcp-servers/               # Mã nguồn MCP servers nội bộ
│   │   └── cloakbrowser/          # MCP server điều khiển trình duyệt stealth (mcp-server-full.mjs, open-verify-ui.mjs, package.json, run-ui.mjs, setup-guide.md)
│   └── skills/                    # Kho 36 kỹ năng nghiệp vụ chuyên sâu (Skills Library)
│
├── setup-dsh/                     # Bộ cài đặt & cấu hình DeepSeek Harness (DSH)
│   ├── install.ps1                # Local runner: gọi bootstrap.ps1 nội bộ (không tải zip)
│   ├── bootstrap.ps1              # Script cài đặt chính và xử lý cấu hình
│   ├── test-bootstrap.ps1         # Bộ test assertion cô lập môi trường
│   ├── AGENTS.md                  # Nguồn quy tắc agent (root, copy sang DshHome/AGENTS.md)
│   ├── README.md                  # Tài liệu chi tiết cho DSH
│   └── templates/                 # File mẫu: cordis.patch.yml, templates/.credentials.yaml, memorix-agents-section.md, templates/.env.example
│
├── setup-antigravity-cli/         # Bộ cài đặt & cấu hình Antigravity CLI
│   ├── install.ps1                # Local runner: gọi bootstrap.ps1 nội bộ (không tải zip)
│   ├── bootstrap.ps1              # Script cài đặt chính và xử lý cấu hình
│   ├── test-bootstrap.ps1         # Bộ test assertion cô lập môi trường
│   ├── AGENTS.md                  # Nguồn quy tắc agent (copy sang AgyDir/AGENTS.md)
│   ├── README.md                  # Tài liệu chi tiết cho Antigravity CLI
│   ├── templates/                 # File mẫu: settings.json, keybindings.json, memorix-agents-section.md, templates/.env.example
│   ├── hooks/                     # Hook Trash Guard (antigravity-pre-tool.*)
│   └── skills/                    # Kho kỹ năng (copy sang AgyDir/skills/)
│
└── setup-dsh-web/                 # Bộ cài đặt & cấu hình DSH Web Runner (profile web-runner tách biệt setup-dsh profiles\web)
    ├── install.ps1                # Local runner: gọi bootstrap.ps1 nội bộ (không tải zip)
    ├── bootstrap.ps1              # Script cài đặt chính và xử lý cấu hình
    ├── test-bootstrap.ps1         # Bộ test assertion cô lập môi trường
    ├── AGENTS.md                  # Nguồn quy tắc agent (copy sang DshHome/AGENTS.md)
    ├── README.md                  # Tài liệu chi tiết cho DSH Web Runner
    ├── templates/                 # File mẫu: cordis.patch.yml, .credentials.yaml, memorix-agents-section.md, templates/.env.example
    └── skills/                    # Kho kỹ năng (copy sang DshHome/skills/)
```

---

## 3. Kiến trúc & Nguyên tắc cốt lõi

Toàn bộ các gói cài đặt trong kho tuân thủ chặt chẽ 7 nguyên tắc kiến trúc:

### 3.1. Kết nối AI Gateway chuẩn hóa
- Mặc định trỏ về Gateway nội bộ: `http://localhost:20128/v1`.
- Quản lý API Key an toàn: Bắt buộc cung cấp thông qua biến môi trường hoặc nhập tương tác khi cài đặt, tuyệt đối không hardcode API key vào mã nguồn.
- Hỗ trợ đầy đủ các model Claude thông qua Gateway: `claude-opus-5`, `claude-sonnet-5`, `claude-haiku-4-5-20251001`, `claude-fable-5`.

### 3.2. Hệ sinh thái MCP Servers đồng nhất
Tất cả các agent CLI đều được chuẩn hóa cấu hình để sử dụng chung danh mục MCP Servers thiết yếu:

| MCP Server | Chức năng chính | Lệnh khởi chạy / Gói cài đặt | Yêu cầu runtime |
|---|---|---|---|
| **gitnexus** | Lập bản đồ code knowledge graph, AST, symbol navigation | `cmd /c <abs-path>\gitnexus.cmd mcp` | Node.js >= 22.18.0, Git |
| **company-atlassian** | Tra cứu và cập nhật Jira Issue, Confluence page | `mcp-atlassian` (ghim phiên bản `0.23.1`) | Python `uv` tool |
| **context7** | Tra cứu trực tiếp tài liệu chính thức của thư viện, framework, SDK | `node <npm-root>/@upstash/context7-mcp/dist/index.js` | Node.js >= 22.18.0 |
| **glab** | Thao tác dự án GitLab, Issues, Merge Requests, Pipelines | `glab mcp serve` | GitLab CLI (`glab`) |
| **cloakbrowser** | Trình duyệt stealth tự động hóa, cào dữ liệu, chụp màn hình | `node mcp-server-full.mjs` | Node.js, Playwright |
| **memorix** *(Opt-in)* | Trí nhớ phiên làm việc, reasoning memory cho agent | `memorix serve --mode lite` | npm `memorix` / `@memorix/core` |
| **agency** | Kho chuyên gia đa tác vụ từ dự án agency-agents (agency_search, agency_browse) | `<abs-path>\agency-mcp-server.cmd` | npm `agency-mcp-server` toàn cầu (Node.js) |

### 3.3. Cơ chế giải quyết xung đột thông minh (Smart Conflict Resolution)
Trước khi ghi đè bất kỳ file cấu hình nào đã tồn tại trên máy người dùng, script cung cấp các lựa chọn:
- **`[O]verwrite`**: Ghi đè toàn bộ bằng cấu hình mới. Luôn tự động tạo bản sao lưu `.bak`.
- **`[M]erge`** *(Khuyến nghị cho JSON/YAML/Patch)*: Hợp nhất thông minh — bảo toàn các MCP Server cá nhân hoặc thiết lập riêng của người dùng và gộp bổ sung các server mới từ template.
- **`[S]kip`**: Bỏ qua file hiện tại, giữ nguyên trạng.
- Hỗ trợ cờ `-Force` hoặc `-OverwriteAll` để chạy tự động trong môi trường CI/CD không có giao diện tương tác.

### 3.4. Trash Guard (Bảo vệ an toàn dữ liệu - Không xóa vĩnh viễn)
- **Quy tắc tiên quyết (Mandatory):** Tuyệt đối cấm sử dụng các lệnh xóa cứng (`rm`, `del`, `Remove-Item`, `rmdir`) làm mất dữ liệu vĩnh viễn.
- Mọi thao tác xóa bắt buộc phải chuyển tệp/thư mục vào **Recycle Bin (Thùng rác Windows)**.
- Triển khai chặn xóa cứng:
  - OMP: Extension `setup-omp/extensions/no-hard-delete.ts` cài vào `~/.omp/extensions/`.
  - Claude Code: Hook tiền xử lý lệnh công cụ `setup-claude-code/trash-guard/claude-pre-tool.ps1` / `claude-pre-tool.js` và script tiện ích `trash-cli.ps1`, kèm `trash-guard.ps1` / `trash-guard.sh`.
  - Tất cả 7 script `bootstrap.ps1` đều nhúng hàm chuyển vào Recycle Bin qua API .NET `Microsoft.VisualBasic.FileIO.FileSystem::DeleteFile` / `DeleteDirectory` với tham số `SendToRecycleBin`.

### 3.5. Kho kỹ năng nghiệp vụ chuyên sâu (`skills/`)
Nằm tại `setup-omp/skills/`, cung cấp 36 kỹ năng tiêu chuẩn cho các quy trình phát triển phần mềm:
- **Phát triển & Lập kế hoạch:** `create-plan`, `create-testcase`, `implement`, `implement-task`, `implement-spec`, `init-project`, `init-docs`, `reload-context`.
- **Kiểm thử lặp đạt coverage >= 90%:** `java-impact-unittest-loop`, `dotnet-impact-unittest-loop`, `react-impact-unittest-loop`, `angular-impact-unittest-loop`, `php-impact-unittest-loop`.
- **Bảo mật & Rà soát:** `security-review`, `secret-scanning`, `codeql`, `github-actions-hardening`, `poka-yoke`, `sql-code-review`, `sql-object-impact-analysis`.
- **Trí nhớ & Điều phối Memorix:** `memorix-memory`, `memorix-git-memory`, `memorix-sessions`, `memorix-orchestrate`, `memorix-reasoning`, `memorix-troubleshooting`, `memorix-mini-skills`.
- **Tối ưu & Kiến trúc:** `postgresql-optimization`, `improve-codebase-architecture`, `acquire-codebase-knowledge`, `docs-sync-audit`, `agent-skill-stack`, `gem-devops-guidelines`, `monthly-report-and-logwork`, `git-commit`, `bug-reproduction-brief`.

### 3.6. Kiểm thử tự động cô lập (Evidence Loop)
Mỗi bộ cài đặt đều trang bị file `test-bootstrap.ps1`. Bộ kiểm thử sử dụng biến môi trường giả lập (mock profile directories), kiểm tra đầy đủ các kịch bản:
- Cài đặt mới từ đầu (fresh install).
- Xử lý xung đột Overwrite / Merge / Skip.
- Tùy chọn bật / tắt Memorix.
- Cơ chế sao lưu `.bak` và kiểm tra tính hợp lệ của JSON/YAML/TOML sinh ra.

---

### 3.7. Chuẩn hóa tập tin chỉ dẫn Agent (Canonical Instruction Files)
Tất cả các tệp chỉ dẫn tác tử (`AGENTS.md`, `CLAUDE.md`, `RULES.md`, `SYSTEM.md`) cùng các file mẫu đi kèm trong thư mục `templates/` của toàn bộ 7 setup được quy chuẩn hóa đồng nhất:
- **Canonical templates:** Mọi tệp mẫu cấu hình và chỉ dẫn nguồn được lưu trữ chuẩn hóa tại thư mục `templates/` (hoặc thư mục gốc của từng setup theo đặc thù runtime).
- **English-only rule for instruction files:** All agent instruction files and prompt templates (`AGENTS.md`, `CLAUDE.md`, `RULES.md`, `SYSTEM.md`, and section snippets) MUST be maintained in English to ensure cross-model compatibility, deterministic system prompt interpretation, and uniform behavior across heterogeneous CLI runtimes. (This rule applies strictly to agent instruction files and prompt templates; repository-level user documentation such as this `README.md` remains in Vietnamese).

## 4. Hướng dẫn cài đặt & Sử dụng nhanh

### 4.0. Lệnh chung root dispatcher (khuyến nghị)

Mở PowerShell trên máy mục tiêu, chạy 1 dòng duy nhất. Dispatcher root (`install.ps1`) đọc `$env:SETUP_TARGET` để hỗ trợ online `irm|iex` một dòng có biến, sau đó dispatch sang `setup-<target>/bootstrap.ps1` đúng thứ tự, log rõ target nào đang chạy. Không sửa logic bên trong các setup con.

```powershell
# Cài tất cả target theo thứ tự: omp -> claude-code -> opencode -> codex-cli -> dsh -> antigravity-cli -> dsh-web
irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.ps1 | iex

# Cài 1 target qua biến môi trường (online 1 dòng có biến):
$env:SETUP_TARGET='omp'; irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.ps1 | iex
$env:SETUP_TARGET='claude-code'; irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.ps1 | iex
$env:SETUP_TARGET='opencode'; irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.ps1 | iex
$env:SETUP_TARGET='codex-cli'; irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.ps1 | iex
$env:SETUP_TARGET='dsh'; irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.ps1 | iex
$env:SETUP_TARGET='dsh-web'; irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.ps1 | iex
$env:SETUP_TARGET='antigravity-cli'; irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.ps1 | iex
```

Chạy local sau khi clone (passthrough `-DryRun -SkipInstall -Force -OverwriteAll -EnableMemorix -DisableMemorix` xuống `bootstrap.ps1` con):

```powershell
git clone https://github.com/thanhpk6120/setup-agent-code.git
cd setup-agent-code
copy .env.example .env   # gộp AI_BASE_URL/AI_API_KEY/JIRA/CONFLUENCE/CONTEXT7/GITLAB/DSH_*/AGY_*
.\install.ps1 -Target all -DryRun
.\install.ps1 -Target dsh -DryRun
```

| Giá trị `-Target` / `$env:SETUP_TARGET` | Dispatch tới | Ghi chú |
|---|---|---|
| `all` (mặc định) | Lần lượt `omp` -> `claude-code` -> `opencode` -> `codex-cli` -> `dsh` -> `antigravity-cli` -> `dsh-web` | Log rõ `[i/n] TARGET: <t>` từng bước |
| `omp` | `setup-omp/bootstrap.ps1` | Oh My Prompt |
| `claude-code` | `setup-claude-code/bootstrap.ps1` | Claude Code CLI |
| `opencode` | `setup-opencode/bootstrap.ps1` | OpenCode CLI |
| `codex-cli` | `setup-codex-cli/bootstrap.ps1` | OpenAI Codex CLI |
| `dsh` | `setup-dsh/bootstrap.ps1` | DeepSeek Harness Desktop (`profiles\web`) |
| `antigravity-cli` | `setup-antigravity-cli/bootstrap.ps1` | Antigravity CLI (`AGY_MODEL`, Memorix MCP `memorix serve --mode lite` + chèn/gỡ `templates/memorix-agents-section.md` vào `AGENTS.md`) |
| `dsh-web` | `setup-dsh-web/bootstrap.ps1` | DSH Web Runner (`profiles\web-runner` tách biệt `setup-dsh`, Memorix block `mcp-memorix` + chèn/gỡ `templates/memorix-agents-section.md` vào `~/.dsh/AGENTS.md`) |

> Phân biệt installer: `install.ps1` ở root là dispatcher — dùng bản local nếu có `setup-*/bootstrap.ps1`, nếu không thì tải zip monorepo `setup-agent-code/main.zip` rồi dispatch. `install.ps1` trong từng `setup-*/` là local runner — chỉ gọi `bootstrap.ps1` nội bộ cùng thư mục, không tải zip.

### 4.1. Cài đặt trực tuyến 1 dòng lệnh (PowerShell)

Mở PowerShell trên máy mục tiêu và chạy lệnh tương ứng với Agent bạn muốn cấu hình:
```powershell
# 1. Claude Code CLI
irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/setup-claude-code/install.ps1 | iex

# 2. OpenCode CLI
irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/setup-opencode/install.ps1 | iex

# 3. OpenAI Codex CLI
irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/setup-codex-cli/install.ps1 | iex

# 4. Oh My Prompt (OMP)
irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/setup-omp/install.ps1 | iex

# 5. DeepSeek Harness (DSH Desktop, profiles\web)
irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/setup-dsh/install.ps1 | iex

# 6. Antigravity CLI (1 dòng online)
irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/setup-antigravity-cli/install.ps1 | iex

# 7. DSH Web Runner (1 dòng online, profile web-runner)
irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/setup-dsh-web/install.ps1 | iex
```

### 4.2. Cài đặt từ mã nguồn cục bộ (Offline / Local clone)

Sau khi clone repository về máy:

```powershell
git clone https://github.com/thanhpk6120/setup-agent-code.git
cd setup-agent-code

# Cấu hình Claude Code
cd setup-claude-code
.\bootstrap.ps1

# Cấu hình OpenCode
cd ..\setup-opencode
.\bootstrap.ps1

# Cấu hình Codex CLI
cd ..\setup-codex-cli
.\bootstrap.ps1

# Cấu hình OMP
cd ..\setup-omp
.\bootstrap.ps1

# Cấu hình DSH Desktop (profiles\web)
cd ..\setup-dsh
.\bootstrap.ps1

# Cấu hình Antigravity CLI
cd ..\setup-antigravity-cli
.\bootstrap.ps1

# Cấu hình DSH Web Runner (profiles\web-runner tách biệt setup-dsh)
cd ..\setup-dsh-web
.\bootstrap.ps1
```

### 4.3. Các tham số cài đặt nâng cao

Tất cả các script `bootstrap.ps1` và `install.ps1` đều hỗ trợ các tham số chuẩn:

| Tham số | Ý nghĩa | Ví dụ |
|---|---|---|
| `-Force` hoặc `-OverwriteAll` | Tự động sao lưu và ghi đè toàn bộ cấu hình cũ, không dừng hỏi xác nhận | `.\bootstrap.ps1 -Force` |
| `-DryRun` | Chạy mô phỏng kiểm tra, không ghi file thật vào hệ thống | `.\bootstrap.ps1 -DryRun` |
| `-SkipInstall` | Chỉ cập nhật cấu hình và template, bỏ qua bước cài đặt gói binary bên ngoài | `.\bootstrap.ps1 -SkipInstall` |
| `-EnableMemorix` | Kích hoạt cài đặt Memorix (MCP & Session Memory) | `.\bootstrap.ps1 -EnableMemorix` |
| `-DisableMemorix` | Bỏ qua hoàn toàn Memorix, giữ môi trường tối giản và khởi động nhanh | `.\bootstrap.ps1 -DisableMemorix` |

---

## 5. Chạy kiểm thử tự động (Verification)

Để xác minh tính ổn định của các kịch bản cài đặt mà không làm ảnh hưởng đến cấu hình thật trên máy:

```powershell
# Kiểm thử setup-claude-code
pwsh -NoProfile -File setup-claude-code/test-bootstrap.ps1

# Kiểm thử setup-opencode
pwsh -NoProfile -File setup-opencode/test-bootstrap.ps1

# Kiểm thử setup-codex-cli
pwsh -NoProfile -File setup-codex-cli/test-bootstrap.ps1

# Kiểm thử setup-omp
pwsh -NoProfile -File setup-omp/test-bootstrap.ps1

# Kiểm thử setup-dsh
pwsh -NoProfile -File setup-dsh/test-bootstrap.ps1

# Kiểm thử setup-antigravity-cli (Memorix MCP + AGENTS.md)
pwsh -NoProfile -File setup-antigravity-cli/test-bootstrap.ps1

# Kiểm thử setup-dsh-web (profile web-runner + Memorix)
pwsh -NoProfile -File setup-dsh-web/test-bootstrap.ps1
```

---

## 6. Yêu cầu hệ thống

- **Hệ điều hành:** Windows 10 / Windows 11 (x64).
- **Shell:** PowerShell 5.1 (Windows PowerShell) hoặc PowerShell 7+ (`pwsh`).
- **Node.js & npm:** Node.js >= 22.18.0 (yêu cầu bắt buộc cho `gitnexus`, `context7`).
- **Python & uv:** Khuyến nghị cài đặt công cụ `uv` để quản lý `mcp-atlassian`.
- **Git:** Git for Windows.
- **GitLab CLI (`glab`):** Tùy chọn (cần thiết khi sử dụng tích hợp GitLab).
