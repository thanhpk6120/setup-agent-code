# Cài đặt & cấu hình OpenCode v2 trên Windows — từ đầu đến cuối

> Tài liệu này ghi lại **đúng quy trình đã chạy và đã kiểm chứng trên máy** (Windows 10.0.19045, fnm 1.39.0,
> Node v24.21.0, npm 12.2.2, OpenCode **2.2.7**, `@opencode/plugin` **2.2.7**).
> Mọi đường dẫn/tên lệnh dưới đây là bản đã thử, không phải ví dụ lý thuyết.

---

## 0. Tóm tắt nhanh (TL;DR)

```powershell
# 1) npm 12 chặn postinstall của @opencode/cli -> phải allow-list trước khi cài
npm config set allow-scripts "opencode-ai,@opencode/cli" --location=user
npm i -g @opencode/cli --foreground-scripts
opencode --version                      # phải ra 2.2.7

# 2) Cấu hình LLM + quyền (file global)
notepad "$env:USERPROFILE\.config\opencode\opencode.json"

# 3) Cài SDK plugin v2 (cho plugin chặn hard-delete)
cd "$env:USERPROFILE\.config\opencode"
npm i @opencode/plugin@2.2.7 --no-fund --no-audit

# 4) Cài plugin + khai báo key qua biến môi trường
setx CUSTOM_AI_API_KEY "sk-..."          # key của proxy/LLM
# -> mở terminal mới, chạy lại: opencode
```

---

## 1. Kiến trúc file & thư mục

| Mục đích | Đường dẫn (máy này) |
| --- | --- |
| Binary CLI | `%APPDATA%\fnm\node-versions\v24.21.0\installation\node_modules\@opencode\cli\bin\opencode.exe` |
| Shim gọi từ PATH | `%LOCALAPPDATA%\fnm_multishells\<pid>_<ts>\opencode.cmd` / `.ps1` (symlink tới node đang active) |
| Config toàn cục | `%USERPROFILE%\.config\opencode\opencode.json` (hoặc `opencode.jsonc`) |
| Config theo project | `<repo>\opencode.jsonc`, `<repo>\.opencode\opencode.jsonc` |
| Plugin local | `%USERPROFILE%\.config\opencode\plugins\*.js` (auto-discovery) |
| Dependency cho plugin | `%USERPROFILE%\.config\opencode\package.json` + `node_modules\` |
| Log | `%USERPROFILE%\.local\share\opencode\log\opencode.log` (`opencode debug paths log`) |
| Skills / AGENTS.md | `%USERPROFILE%\.config\opencode\skills\`, `AGENTS.md` |

> Ghi chú: npm cài global theo **prefix của Node đang active** (fnm), không phải `%APPDATA%\npm`.
> Vì vậy file thật nằm trong thư mục `installation` của version Node, còn lệnh `opencode` đi qua shim multishell của fnm.

---

## 2. Bước 1 — Chuẩn bị máy

Bắt buộc:

- **fnm** + **Node LTS** (đã dùng `v24.21.0`) và **npm ≥ 12** (`npm -v` → 12.2.2).
- **Git Bash** (đường dẫn `C:\Program Files\Git\bin\bash.exe`) — OpenCode dùng shell này cho tool bash.
- **PowerShell 7** (`pwsh`) để chạy script/cấu hình.
- Một endpoint **OpenAI-compatible** (ở đây là proxy nội bộ `http://localhost:20126/v1`) hoặc API key của provider thật.

Kiểm tra nhanh:

```powershell
node -v; npm -v; fnm --version
Test-NetConnection localhost -Port 20126      # proxy LLM phải mở
```

---

## 3. Bước 2 — Cài `@opencode/cli`

### 3.1. Cạm bẫy của npm 12: allow-scripts

npm 12 có cơ chế **allow-list script cài đặt** (`allow-scripts`). Script `postinstall` của gói chỉ chạy khi tên gói
nằm trong danh sách. Nếu không, gói `@opencode/cli` chỉ để lại **file stub 229 byte** (một script sh in ra
"postinstall script was not run"), và Windows báo:

```
ResourceUnavailable: ... Program 'opencode.exe' failed to run:
The specified executable is not a valid application for this OS platform.
```

Kiểm tra:

```powershell
npm config get ignore-scripts     # false KHÔNG đủ; npm 12 còn chặn bằng allow-scripts
npm config get allow-scripts      # phải chứa @opencode/cli
```

### 3.2. Cài đúng cách

```powershell
npm config set allow-scripts "opencode-ai,@opencode/cli" --location=user
npm i -g @opencode/cli --foreground-scripts
opencode --version
```

Kết quả đúng: `opencode v2.2.7` (hoặc bản mới hơn).

### 3.3. Xác minh binary thật (không phải stub)

```powershell
$p = "$env:APPDATA\fnm\node-versions\v24.21.0\installation\node_modules\@opencode\cli\bin\opencode.exe"
(Get-Item $p).Length          # ~265.672.584 bytes  (stub lỗi chỉ 229 bytes)
```

### 3.4. Nếu vẫn còn stub — sửa nhanh không cần mạng

Package optional dependency đã chứa sẵn binary Windows:

```powershell
$base = "$env:APPDATA\fnm\node-versions\v24.21.0\installation\node_modules\@opencode\cli"
Copy-Item "$base\node_modules\@opencode\cli-windows-x64\bin\opencode.exe" "$base\bin\opencode.exe" -Force
opencode --version
```

Hoặc chạy lại postinstall đúng cách:

```powershell
cd "$env:APPDATA\fnm\node-versions\v24.21.0\installation\node_modules\@opencode\cli"
node .\postinstall.mjs
```

### 3.5. Ghi nhớ để lần sau không tái phát

- Mỗi lần `npm i -g` / update `@opencode/cli`: phải còn `@opencode/cli` trong `allow-scripts`.
- `npm approve-scripts @opencode/cli` là cách tương đương để đưa gói vào allow-list (npm 12.2.2 có lệnh này).

---

## 4. Bước 3 — Cấu hình LLM (provider/model)

### 4.1. File cấu hình

- Toàn cục: `%USERPROFILE%\.config\opencode\opencode.json` (**file chính đang dùng**)
- Hoặc `opencode.jsonc` nếu muốn comment.
- Thứ tự áp dụng: global → `./opencode.jsonc` → `./.opencode/opencode.jsonc`.
- Schema để validate/autocomplete: `https://opencode.ai/config.json`.

### 4.2. v1 → v2: các key bị đổi tên

| v1 (bị bỏ qua ở v2) | v2 (đúng) |
| --- | --- |
| `provider` | `providers` |
| `permission: { bash: {...} }` | `permissions: [{ action, resource, effect }]` |
| `plugin: [...]` | `plugins: [...]` |

> Đây là lý do phổ biến nhất khiến "cấu hình mà không có tác dụng": app chạy v2 nhưng file viết theo v1.

### 4.3. Mẫu cấu hình đầy đủ (dùng cho proxy OpenAI-compatible)

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": ["AGENTS.md"],

  // Model mặc định: providerID/modelID
  "model": "custom/claude-sonnet-5",

  "providers": {
    "custom": {
      "name": "Custom AI",
      // Credential: ưu tiên biến môi trường (đặt bằng setx)
      // "apiKey" trong settings cũng được truyền xuống runtime package.
      "env": ["CUSTOM_AI_API_KEY"],
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": {
        "baseURL": "http://localhost:20126/v1",
        "apiKey": "sk-thay-bang-key-cua-ban"
      },
      "models": {
        "claude-sonnet-5": { "name": "Claude Sonnet 5", "limit": { "context": 1000000, "output": 128000 } },
        "claude-opus-5":   { "name": "Claude Opus 5",   "limit": { "context": 1000000, "output": 128000 } },
        "claude-fable-5":  { "name": "Claude Fable 5",  "limit": { "context": 1000000, "output": 128000 } },
        "claude-haiku-4-5-20251001": { "name": "Claude Haiku 4.5", "limit": { "context": 200000, "output": 66000 } }
      }
    }
  },

  "permissions": [
    { "action": "shell", "resource": "*", "effect": "ask" },
    { "action": "shell", "resource": "rm *", "effect": "deny" }
    // ... xem mục 5
  ]
}
```

### 4.4. Đặt API key (khuyến nghị)

```powershell
setx CUSTOM_AI_API_KEY "sk-..."
# mở terminal mới rồi kiểm tra:
echo $env:CUSTOM_AI_API_KEY
```

### 4.5. Kiểm chứng provider

```powershell
opencode models | Select-String "^custom/"
# custom/claude-sonnet-5
# custom/claude-opus-5
# custom/claude-fable-5
# custom/claude-haiku-4-5-20251001
```

Nếu danh sách trống: sai key `providers` (v1), sai `baseURL`, hoặc proxy chưa chạy
(`curl http://localhost:20126/v1/models` phải trả JSON).

---

## 5. Bước 4 — Chặn hard-delete (2 lớp bảo vệ)

### 5.1. Lớp 1 — `permissions` của OpenCode v2

Rule khớp **cuối cùng sẽ thắng**, nên đặt `*: ask` trước rồi tới các rule `deny`:

```jsonc
"permissions": [
  { "action": "shell", "resource": "*", "effect": "ask" },
  { "action": "shell", "resource": "rm *",          "effect": "deny" },
  { "action": "shell", "resource": "rmdir *",       "effect": "deny" },
  { "action": "shell", "resource": "del *",         "effect": "deny" },
  { "action": "shell", "resource": "erase *",       "effect": "deny" },
  { "action": "shell", "resource": "rd *",          "effect": "deny" },
  { "action": "shell", "resource": "ri *",          "effect": "deny" },
  { "action": "shell", "resource": "Remove-Item *", "effect": "deny" },
  { "action": "shell", "resource": "unlink *",      "effect": "deny" },
  { "action": "shell", "resource": "shred *",       "effect": "deny" }
]
```

Mẫu kết thúc bằng ` *` khớp cả khi không có tham số (vd `git status *` khớp `git status`).

### 5.2. Lớp 2 — Plugin v2 (`Plugin.define`)

**Cài SDK** (trong thư mục config):

```powershell
cd "$env:USERPROFILE\.config\opencode"
npm i @opencode/plugin@2.2.7 --no-fund --no-audit
```

**Bật ESM** — file `package.json` trong thư mục config phải có `"type": "module"` để `import` chạy:

```json
{
  "type": "module",
  "dependencies": { "@opencode/plugin": "^2.2.7" }
}
```

**File plugin** `%USERPROFILE%\.config\opencode\plugins\no-hard-delete.js`:

```js
import { Plugin } from "@opencode/plugin"

const HARD_DELETE_PATTERN =
  /(?:^|[;&|`\s])(?:rm|rmdir|del|erase|rd|ri|remove-item|unlink|shred)\s/i

export default Plugin.define({
  id: "no-hard-delete",
  async setup(ctx) {
    await ctx.permission.hook("evaluate", (event) => {
      if (event.action !== "shell") return
      const hit = (event.resources ?? []).some((r) => HARD_DELETE_PATTERN.test(String(r)))
      if (!hit) return
      event.effect = "deny"
      event.message = "[BLOCKED] Không hard-delete. Hãy chuyển vào Trash/Recycle Bin."
    })
  },
})
```

Vì sao dùng `ctx.permission.hook("evaluate")`:

- Hook permission chạy sau khi rule cấu hình được đánh giá và **có quyền đổi `effect`** thành `allow/ask/deny`.
- `ctx.shell.hook("create.before")` **không** có cờ block — chỉ sửa được `command/cwd/timeout/shell/env`.
- Rule `deny` cấu hình sẵn là "final" nên hook không cần chạy cho các trường hợp đó (2 lớp bổ sung nhau).

### 5.3. Những lỗi cấu hình plugin thường gặp (và cách tránh)

| Triệu chứng | Nguyên nhân | Cách sửa |
| --- | --- | --- |
| `Plugin failed: ...\no-hard-delete.js` | Plugin export function kiểu v1/giả (`context.on`, `hooks.beforeToolExecution`) | Export `Plugin.define({ id, setup/effect })` |
| Log: `Plugin must export a default definition with an id and an effect or setup function` | Default export không phải object definition | Dùng đúng mẫu mục 5.2 |
| Log: `configured plugin path must be a directory` | Còn key `"plugin"` (số ít) trỏ tới **file** | Xoá key đó; file `.js` trong `plugins/` đã được auto-discovery |
| Plugin không load, không báo lỗi | Thiếu dependency `@opencode/plugin` hoặc package.json thiếu `"type": "module"` | Làm lại mục 5.2 |

> `opencode plugin list` chỉ liệt kê **package plugin** (khai báo trong `plugins`), không liệt kê plugin local
> auto-discovery. Muốn kiểm tra plugin local: xem log (`opencode debug paths log`) hoặc `/plugins` trong TUI.

---

## 6. Bước 5 — MCP servers (tuỳ chọn)

Key `mcp` vẫn giữ nguyên ở v2. Ví dụ tối giản:

```jsonc
"mcp": {
  "company-atlassian": {
    "type": "local",
    "command": ["mcp-atlassian"],
    "enabled": true,
    "environment": {
      "JIRA_URL": "https://jira.example.com",
      "JIRA_PERSONAL_TOKEN": "<token>",
      "CONFLUENCE_URL": "https://conf.example.com",
      "CONFLUENCE_PERSONAL_TOKEN": "<token>"
    }
  }
}
```

**Cảnh báo bảo mật:** `opencode.json` chứa token/API key dạng plaintext. Không commit file này lên git;
nếu cần chia sẻ, thay bằng placeholder.

---

## 7. Bước 6 — Chạy & kiểm chứng

```powershell
opencode                      # TUI
opencode --version
opencode models               # danh sách model (gồm custom/*)
opencode debug paths log      # in đường dẫn log
```

Trong TUI:

- `/models` — chọn model
- `/plugins` — xem trạng thái plugin (không còn dòng "Plugin failed")

Kiểm tra log sau khi mở app:

```powershell
$log = "$env:USERPROFILE\.local\share\opencode\log\opencode.log"
Select-String -Path $log -Pattern "loading plugin|failed to load plugin|Plugin must export|configured plugin path" |
  Select-Object -Last 10
```

Kỳ vọng: có `loading plugin ... no-hard-delete.js`, **không** có `failed to load plugin`.

---

## 8. Troubleshooting tổng hợp

| Lỗi | Nguyên nhân gốc | Xử lý |
| --- | --- | --- |
| `The specified executable is not a valid application for this OS platform` | `bin/opencode.exe` là stub 229 byte, postinstall bị npm 12 chặn | Mục 3.1–3.4 |
| `Plugin must export a default definition...` | Plugin sai API v2 | Mục 5.2 |
| `configured plugin path must be a directory` | Key `plugin` (v1) + path file | Xoá key; dùng `plugins` hoặc auto-discovery |
| Rule `rm/del/Remove-Item` không chặn | Viết `permission.bash` kiểu v1 | Chuyển sang `permissions` (mục 5.1) |
| `opencode models` không thấy `custom/*` | `providers` sai schema / proxy chết / sai key | Mục 4.5 |
| Proxy trả 401 | Thiếu `CUSTOM_AI_API_KEY` ở terminal hiện tại | `setx` rồi mở terminal mới |

---

## 9. Checklist hoàn tất

- [ ] `opencode --version` trả `2.2.7` (không lỗi ResourceUnavailable)
- [ ] `opencode.exe` ~265 MB (không phải 229 byte)
- [ ] `allow-scripts` có `@opencode/cli` để update sau này không hỏng
- [ ] `opencode models` có `custom/*`
- [ ] `permissions` (không phải `permission`) có rule deny cho rm/del/Remove-Item...
- [ ] `plugins/no-hard-delete.js` export `Plugin.define({ id, setup })`
- [ ] `package.json` config có `"type": "module"` và `@opencode/plugin`
- [ ] Log không còn `failed to load plugin`
- [ ] `opencode.json` không commit lên git (có token)

---

## 10. Phụ lục — Dọn dẹp an toàn (không xoá vĩnh viễn)

Quy ước của workspace: **mọi file/thư mục thừa phải chuyển vào Recycle Bin**, không xoá vĩnh viễn.

```powershell
Add-Type -AssemblyName Microsoft.VisualBasic

# File
[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
  "C:\path\to\file.bak", "OnlyErrorDialogs", "SendToRecycleBin")

# Thư mục
[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
  "C:\path\to\dir", "OnlyErrorDialogs", "SendToRecycleBin")
```

Khi thay plugin/config, giữ bản cũ bằng cách **rename** (vd `no-hard-delete.js.v1.bak`) rồi mới tạo bản mới;
sau khi xác nhận chạy tốt mới chuyển bản cũ vào Recycle Bin.
