# Setup Agent Code — Bộ Cài Đặt AI Coding Agents

> **Cảnh báo:** Installer đang được sửa sau sự cố ghi đè cấu hình. Không chạy trên cấu hình thật cho đến khi các kiểm thử bảo toàn dữ liệu và chạy thực tế trong môi trường cách ly hoàn tất. `--doctor` và `--dry-run` hiện chưa được xác nhận là chỉ đọc.

> **Một lệnh duy nhất** để cài đặt, cấu hình và **kiểm chứng** **6 AI Coding Agent** trên **Windows**, **macOS** và **Linux**: **OMP**, **Claude Code**, **OpenCode**, **Codex CLI**, **DSH (DeepSeek Harness)**, **Antigravity CLI**.

Từ v1.0, cả 3 hệ điều hành chạy **cùng một engine** (`core/engine.mjs`) với **cùng thứ tự 13 phase** và **cùng bộ option**; khác biệt giữa các agent chỉ nằm trong `manifest/` và `templates/`.

---

## 1. Cài Đặt Nhanh

### Windows (PowerShell 5.1 / 7+)

```powershell
# Toàn bộ 6 agent
irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.ps1 | iex

# Một agent
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.ps1))) -Target omp
```

### macOS / Linux

```bash
# Toàn bộ 6 agent
curl -fsSL https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.sh | bash

# Một agent
curl -fsSL https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.sh | bash -s -- --target omp
```

> Yêu cầu: **Node.js >= 22.18.0** (launcher sẽ thử cài nếu thiếu). Các MCP server dùng Node/uv nên đây cũng là yêu cầu runtime của agent.

---

## 2. Kiến Trúc

```
manifest/            # nguồn sự thật duy nhất (agents, mcp, prompts, options)
core/engine.mjs      # 1 engine, 13 phase cho Windows + macOS + Linux
core/lib/            # util, manifest loader, render (JSON/TOML/YAML), verify
templates/           # template cấu hình + instruction files (phần riêng từng agent)
skills/              # 36 skills canonical (1 bản duy nhất)
install.ps1/.sh      # launcher mỏng: kiểm tra Node -> gọi engine
setup-*/             # shim tương thích ngược (deprecated)
```

**13 phase cố định** (giống nhau trên mọi OS/agent):

| Phase | Nội dung |
|---|---|
| P0 | Preflight: OS/arch/Node, chuẩn hoá PATH |
| P1 | Args & policy: validate option |
| P2 | Chọn MCP (cùng thứ tự prompt) |
| P3 | Resume & env: `.env`, hỏi reuse 1 lần, chỉ hỏi biến cần cho MCP đã chọn |
| P4 | Prerequisites: hỏi → cài → verify → in hướng dẫn nếu fail (chặn đúng MCP thiếu dep) |
| P5 | Cài binary agent (skip-if-installed) |
| P6 | Cài MCP tools đã chọn |
| P7 | Render config + `.bak` trước khi ghi |
| P8 | Instruction files (đúng path từng agent) |
| P9 | Bổ sung skills còn thiếu; giữ nguyên skills đã tồn tại |
| P10 | Hooks & guards (đăng ký thật, không chỉ copy file) |
| P11 | **Verify**: file, config, binary, MCP handshake |
| P12 | Cleanup (Trash) + summary/report |

---

## 3. Bảng Option (giống nhau trên Windows & macOS/Linux)

| PowerShell | Bash | Ý nghĩa |
|---|---|---|
| `-Target <id>` | `--target <id>` | `all`, `omp`, `claude-code`, `opencode`, `codex-cli`, `dsh`, `antigravity-cli`, `goose`, `roo-code` |
| `-DryRun` | `--dry-run` | Mô phỏng, không ghi file, không cài |
| `-SkipInstall` | `--skip-install` | Chỉ ghi cấu hình: không cài binary/MCP/dependency, không sửa PATH |
| `-Force` | `--force` | Tự đồng ý mọi prompt (không ép cài lại tool đã mới nhất) |
| `-OverwriteAll` | `--overwrite-all` | Ghi đè cấu hình (luôn tạo `.bak.<timestamp>`) |
| `-EnableMemorix` | `--memorix` | Bật Memorix (MCP + hooks + skills) |
| `-DisableMemorix` | `--no-memorix` | Tắt Memorix, dọn `memorix-*` vào Thùng rác |
| `-Mcp <all\|none\|list>` | `--mcp ...` | Chọn MCP chính xác |
| `-Preset <minimal\|standard\|full>` | `--preset ...` | Preset MCP |
| `-Yes` | `--yes` | Non-interactive: dùng default, **đồng ý cài prerequisite** |
| `-Doctor` | `--doctor` | Chỉ kiểm tra, **không ghi gì** |
| `-Json` | `--json` | Xuất kết quả JSON |
| `-Report <path>` | `--report <path>` | Ghi báo cáo JSON |
| `-Strict` | `--strict` | WARN ⇒ exit code ≠ 0 |
| `-Quiet` / `-Verbose` | `--quiet` / `--verbose` | Mức log |
| `-EnvFile <path>` | `--env-file <path>` | Nạp `.env` chỉ định |

Ví dụ:

```bash
./install.sh --target omp --doctor --json
./install.sh --mcp gitnexus,context7 --yes
./install.sh --target all --preset full --overwrite-all
```

---

## 4. Prerequisites: check-first → hỏi → cài → verify → hướng dẫn

Mỗi MCP khai báo dependency trong [manifest/mcp.json](manifest/mcp.json) (`requires`), dependency được mô tả trong [manifest/prerequisites.json](manifest/prerequisites.json) (cách cài theo OS, `minVersion`, `guidance`).

**Nguyên tắc: kiểm tra trước, chỉ hỏi khi chưa đạt.** Mỗi dependency/binary/MCP được đánh giá thành một trong các trạng thái:

| Trạng thái | Ý nghĩa | Hành vi |
|---|---|---|
| `ok` | Có trong PATH + chạy được + version đúng | **Im lặng bỏ qua**, không hỏi |
| `missing` | Không tìm thấy | Hỏi cài |
| `outdated` | Version cũ hơn `minVersion` | Hỏi **cập nhật** |
| `mismatch` | Sai version pin (vd. `mcp-atlassian` ≠ 0.23.1) | Hỏi **cài lại đúng version** |
| `broken` | Có trong PATH nhưng `--version` lỗi | Hỏi **cài lại** |

Sau khi được đồng ý:

1. **Cài** theo manifest (winget/brew/apt/npm/uv/script tuỳ OS).
2. **Verify lại ngay** — chưa đạt thì chưa đi tiếp.
3. **Fail** → in hướng dẫn cụ thể cho OS của bạn, cho `[r]etry / [s]kip` (tối đa 3 lần).
4. **Từ chối / non-interactive** → in hướng dẫn thủ công, **chặn đúng MCP cần dependency đó** (không ghi entry rác vào config), verify ghi `WARN`, cuối chương trình có mục “HƯỚNG XỬ LÝ”.
5. **PATH**: thiếu thư mục (npm global bin, uv tool bin, `~/.local/bin`) → **hỏi trước khi thêm vào PATH phiên hiện tại**, kèm cách thêm vĩnh viễn.

Version đang được kiểm tra:

| Thành phần | Yêu cầu |
|---|---|
| Node.js | `>= 22.18.0` |
| npm | `>= 10.0.0` |
| uv | `>= 0.5.0` |
| git | `>= 2.30.0` |
| `mcp-atlassian` | **đúng `0.23.1`** (khớp `uv tool install mcp-atlassian==0.23.1`) |

Bảng dependency hiện tại:

| MCP | Cần |
|---|---|
| `company-atlassian` | `uv` (cài `mcp-atlassian==0.23.1`) |
| `gitnexus`, `context7`, `memorix` | `node` + `npm` |
| `cloakbrowser` | `node` + `npm`, và **hỏi riêng** trước khi chạy `npm install` (playwright-core/cloakbrowser); kiểm tra đủ 3 thành phần trước khi coi là đã cài |

`--skip-install` = chế độ **chỉ ghi cấu hình**: không cài dependency, không chặn MCP, không sửa PATH.
`--doctor` = chỉ **đọc và đánh giá** (kể cả version pin), không hỏi, không ghi; kiểm tra đúng bộ MCP đang có trong config hiện tại (không đoán theo default).

---

## 5. Mỗi Agent Được Ghi File Nào

| Agent | Instruction file (đúng chuẩn) | Cấu hình | Skills |
|---|---|---|---|
| **OMP** | `~/.omp/agent/AGENTS.md` (context) + `~/.omp/agent/RULES.md` (sticky) | `~/.omp/agent/{mcp.json,config.yml,models.yml}` | `~/.omp/agent/skills/` |
| **Claude Code** | `~/.claude/CLAUDE.md` | `~/.claude.json`, `~/.claude/settings.json` | `~/.claude/skills/` |
| **OpenCode** | `~/.config/opencode/AGENTS.md` | `~/.config/opencode/opencode.json` | `~/.config/opencode/skills/` |
| **Codex CLI** | `~/.codex/AGENTS.md` | `~/.codex/config.toml` | `~/.codex/skills/` |
| **DSH** | `~/.dsh/AGENTS.md` | `~/.dsh/profiles/web/cordis.patch.yml`, `~/.dsh/cordis.patch.yml`, `%APPDATA%\dsh-desktop\harness\.credentials.yaml` | `~/.dsh/skills/` |
| **Antigravity CLI** | `~/.gemini/AGENTS.md` (global rules) | `~/.gemini/antigravity-cli/settings.json`, `keybindings.json` | `~/.gemini/config/skills/` + `~/.gemini/antigravity-cli/skills/` |
| **Goose** | `~/.config/goose/.goosehints` (Win: `%APPDATA%\Block\goose\config\.goosehints`) | `~/.config/goose/config.yaml` (Win: `%APPDATA%\Block\goose\config\config.yaml`) | `~/.config/goose/skills/` |
| **Roo Code** | `~/.roo/rules/AGENTS.md` (Win: `%USERPROFILE%\.roo\rules\AGENTS.md`) | `~/.config/Code/User/globalStorage/rooveterinaryinc.roo-cline/settings/mcp_settings.json` (Win: `%APPDATA%\Code\User\...`) | `~/.roo/skills/` |

Ghi chú quan trọng:

- **OMP**: **không** cài `SYSTEM.md` — file này thay thế toàn bộ system prompt mặc định của OMP. Nếu đã có từ bản cũ, installer sẽ cảnh báo và chuyển vào Thùng rác.
- **Claude Code**: `AGENTS.md` chỉ được đọc ở project scope → không ghi `~/.claude/AGENTS.md`.
- **Codex**: `CODEX.md` không phải file global instruction → installer sẽ dọn nếu tồn tại.
- **Antigravity**: global rules nằm ở `~/.gemini/AGENTS.md`, **không phải** `~/.gemini/antigravity-cli/AGENTS.md`.
- **DSH**: profile thật là `~/.dsh/profiles/<name>/` (fallback `%APPDATA%\dsh-desktop\harness\profiles\<name>`).
- **DSH patch layer**: installer **merge từng entry** vào `cordis.patch.yml` — entry của bạn (`plugin-market`, `better-sidebar`, `desktop-shell`, …) được giữ nguyên. Entry template sở hữu (`llm-pi-ai`, `agent-default-model`, `subagent`, `permission`, `subagent-model-selection-settings`, `agent-preset-registry`) bị ghi đè để model/agent luôn đúng pin.
- **DSH endpoint**: `baseURL` trong `llm-pi-ai` **giữ nguyên giá trị đang chạy** trừ khi bạn cấp `AI_BASE_URL` qua `.env` / `--env-file`.
- **DSH credentials**: file `.credentials.yaml` **không bao giờ bị ghi đè** (kể cả `--overwrite-all`) vì chứa secret + OAuth records thật. Xoá file rồi chạy lại nếu muốn tạo mới.
- **DSH chặn xoá cứng**: DSH không có hook API kiểu PreToolUse; lớp bảo vệ là plugin bundle `cc-safety-net`. Installer kiểm tra → hỏi → cài bằng `dsh plugin --profile web add cc-safety-net` → verify `cc-safety-net status`. Cần `pnpm` (installer tự tìm trong cả PATH và `%LOCALAPPDATA%\pnpm\bin`).

- **DSH chống treo khi ghi file**: installer cài local plugin `safe-fs-replace` (`~/.dsh/local-plugins/safe-fs-replace.js`) và thêm đúng một entry `- insert: id: safe-fs-replace` vào `cordis.patch.yml`. Plugin chỉ chạy trên Windows: thay `internals.replaceFile` bằng `rename()` async có retry (`EACCES`/`EBUSY`/`EPERM`, 12 lần, 20→250 ms) để tránh `ReplaceFileW` treo app khi file bị lock. Idempotent: chạy lại không thêm entry thứ hai; rollback = xoá entry + restart DSH.

- **Goose**: MCP extensions được cấu hình trực tiếp dưới khoá `extensions:` trong `config.yaml` (dùng transport `stdio`). Installer merge tự động bảo toàn các extension người dùng tự thêm hoặc builtin.
- **Roo Code**: Cung cấp custom instructions toàn cục qua `%USERPROFILE%\.roo\rules\AGENTS.md` và đồng bộ 5 MCP servers vào `mcp_settings.json` của VS Code extension.
---

## 6. MCP Servers

`company-atlassian` (Jira/Confluence), `gitnexus` (code graph), `context7` (library docs), `cloakbrowser` (stealth browser), `memorix` (memory).

- `agency` và `glab` **không còn trong setup**: không cài, không kiểm tra, không hỏi. Entry `mcp-agency` / `mcp-glab` đã có sẵn trong config của máy khác sẽ **được giữ nguyên** — installer không tự xoá; muốn bỏ thì xoá tay.

- Cài đặt theo `manifest/mcp.json` (pin `mcp-atlassian==0.23.1`; `gitnexus`/`context7`/`memorix` qua npm).
- Cấu hình được **sinh theo lựa chọn** cho cả 4 định dạng: JSON (`mcpServers`/`mcp`), TOML (`[mcp_servers.*]`), YAML (`- id: mcp-*`), settings Antigravity.
- Server do installer quản lý sẽ bị gỡ khi bạn bỏ chọn; server bạn tự thêm **được giữ nguyên**.
- **Skills**: installer bổ sung skill chuẩn còn thiếu; skill đã tồn tại và skill riêng được giữ nguyên, kể cả khi trùng tên. Vì chưa theo dõi quyền sở hữu, skill cũ không được tự động cập nhật hoặc dọn khi tắt Memorix.

---

## 7. An Toàn & Kiểm Chứng

- **Không xoá cứng**: mọi thao tác xoá (kể cả file tạm) đều chuyển vào Recycle Bin / `~/.Trash`.
- **Luôn backup**: ghi đè cấu hình tạo `*.bak.<YYYYMMDD-HHmmss>` trên cả 3 OS.
- **Merge, không ghi đè** (v1.0.6): `--overwrite-all` không còn thay cấu hình bằng template. JSON merge đệ quy, chỉ điền khoá còn thiếu; TOML/YAML chỉ thay entry/bảng do installer sở hữu, scalar đang chạy (`model_provider`, `base_url`, `api_key`) và mọi MCP server của người dùng luôn được giữ; giá trị placeholder rỗng không bao giờ xoá giá trị live.
- **Fail-closed khi không chắc** (v1.0.7): parser cấu hình là dòng-based, nên cấu trúc nằm ngoài tập con nó xử lý an toàn (TOML `[[array-of-tables]]`, multiline string/array, key trích dẫn chứa dấu chấm; YAML block scalar `|`/`>`) sẽ **báo lỗi và bỏ qua file** thay vì ghi ra bản mất dữ liệu. Header trích dẫn dạng `[mcp_servers."9remote"]` được hỗ trợ và coi là cùng bảng với dạng trần.
- **Verify thật** (P11): file instruction đúng path, config parse được, binary chạy được (`--version`), MCP handshake `initialize` — kết quả PASS/WARN/FAIL, exit code ≠ 0 nếu có FAIL.
- **`--doctor`**: kiểm tra lại toàn bộ mà không sửa gì (dùng sau khi agent update).

```bash
./install.sh --target all --doctor --report report.json
```

---

## 8. Cấu Hình Biến Môi Trường

Tạo `.env` cạnh script (hoặc dùng `--env-file`):

```env
AI_BASE_URL=http://localhost:20128/v1
AI_API_KEY=your-api-key

JIRA_URL=https://jira.yourcompany.com
JIRA_PERSONAL_TOKEN=your-jira-token
CONFLUENCE_URL=https://conf.yourcompany.com
CONFLUENCE_PERSONAL_TOKEN=your-confluence-token

CONTEXT7_API_KEY=your-context7-api-key
AGY_MODEL=custom/claude-sonnet-5
```

Chạy lại sau khi gián đoạn: installer hỏi **một lần** có dùng lại cấu hình cũ không, sau đó chỉ hỏi biến còn thiếu.

---

## 9. Phát Triển

```bash
node scripts/validate.mjs          # kiểm tra manifest
node --test tests/engine.test.mjs  # 20 unit + integration tests
node core/engine.mjs --target all --dry-run --json   # xem kế hoạch chạy
```

CI (`.github/workflows/ci.yml`) chạy matrix **Windows / Ubuntu / macOS** × **Node 22.18 / 24**, gồm validate manifest, test, dry-run contract, `bash -n` và parse PowerShell.

---

**Tác giả:** thanhpk  
**Giấy phép:** MIT License



