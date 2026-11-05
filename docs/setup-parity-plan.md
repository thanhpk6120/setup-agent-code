# Kế hoạch: Chuẩn hoá `setup-agent-code` (parity Windows ↔ macOS/Linux)

> Mục tiêu người dùng: **mọi lệnh setup chạy cùng một thứ tự, cùng một bộ lựa chọn**; chỉ **instruction files** và các phần đặc thù của từng agent được khác nhau; **mọi option/công cụ được chọn phải thực sự được cài và được kiểm chứng**, không dừng ở việc hỏi.
>
> Trạng thái: **ĐÃ TRIỂN KHAI (v1.0.0)** — xem §13 để đối chiếu hạng mục nào đã xong.


---

## 0. Kết quả tra cứu: mỗi agent thực sự đọc file instruction nào

Nguồn: tài liệu chính thức (link ở cột "Nguồn") + kiểm tra máy thật (`~/.dsh`, `~/.gemini`, `~/.omp`...).

| Agent | File global ĐÚNG | Repo đang ghi | Kết luận |
|---|---|---|---|
| **OMP** | `~/.omp/agent/AGENTS.md` (user context) | `~/.omp/agent/AGENTS.md` | ✅ đúng |
| **OMP** | `~/.omp/agent/RULES.md` (sticky, always-apply) | `~/.omp/agent/RULES.md` | ✅ đúng |
| **OMP** | `~/.omp/agent/SYSTEM.md` = **THAY THẾ toàn bộ default system prompt** (mất tool inventory, tool policy, workflow, personality). Muốn thêm thì dùng `APPEND_SYSTEM.md` | `~/.omp/agent/SYSTEM.md` ← copy `setup-omp/templates/SYSTEM.md` (321 dòng, là template `AGENTS.md` cho project, còn placeholder `{{BRANCH_RULE}}`) | ❌ **SAI NGHIÊM TRỌNG** |
| **Claude Code** | `~/.claude/CLAUDE.md` (user scope), `~/.claude/rules/*.md`, `~/.claude/skills/` | `~/.claude/CLAUDE.md` | ✅ đúng |
| **Claude Code** | `AGENTS.md` chỉ được đọc ở **project scope** (v2.1.277+, và chỉ khi không có CLAUDE.md) | copy thêm `~/.claude/AGENTS.md` ([install.sh#L900-L901](install.sh#L900-L901)) | ⚠️ file chết, gây nhiễu |
| **OpenCode** | `~/.config/opencode/AGENTS.md` (+ field `instructions`), `~/.config/opencode/skills/<name>/SKILL.md`, plugins | `~/.config/opencode/AGENTS.md`, skills, plugins | ✅ đúng |
| **Codex CLI** | `~/.codex/AGENTS.md` (user) + `~/.codex/config.toml`; project dùng `AGENTS.md` | `~/.codex/AGENTS.md` ✅, `~/.codex/CODEX.md` ❌ | ⚠️ `CODEX.md` không phải convention → bỏ |
| **DSH** | `~/.dsh/AGENTS.md` (xác nhận qua runtime: system-reminder "Instructions from: ~/.dsh/AGENTS.md"), skills `~/.dsh/skills/` | `~/.dsh/AGENTS.md` ✅ | ✅ đúng |
| **DSH** | profile thật: `~/.dsh/profiles/<name>/cordis.patch.yml` (máy này: `~/.dsh/profiles/web/cordis.patch.yml`) | `%APPDATA%\dsh-desktop\harness\profiles\web\cordis.patch.yml` ([setup-dsh/bootstrap.ps1#L14-L15](setup-dsh/bootstrap.ps1#L14-L15), [install.sh#L1038-L1042](install.sh#L1038-L1042)) | ❌ **SAI ĐƯỜNG DẪN** (thư mục này không tồn tại trên máy) |
| **DSH** | `.credentials.yaml` schema: `version: 1` + `refs:` + `apiKey:` (đã kiểm tra file thật) | bash ghi `Refs:` + chỉ `ANTHROPIC_API_KEY` ([install.sh#L1070-L1077](install.sh#L1070-L1077)) | ❌ sai schema |
| **Antigravity CLI** | Global rules: `~/.gemini/AGENTS.md`, `~/.gemini/GEMINI.md`, `~/.gemini/config/AGENTS.md`, `~/.gemini/config/GEMINI.md`, `~/.gemini/config/rules/*.md` | `~/.gemini/antigravity-cli/AGENTS.md` + `GEMINI.md` ([install.sh#L1098-L1100](install.sh#L1098-L1100), [setup-antigravity-cli/bootstrap.ps1#L1462-L1468](setup-antigravity-cli/bootstrap.ps1#L1462-L1468)) | ❌ **SAI ĐƯỜNG DẪN** (không nằm trong danh sách rules) |
| **Antigravity CLI** | Skills: `~/.gemini/config/skills/` (global, dùng chung App+CLI) + `~/.gemini/antigravity-cli/skills/` (CLI-only) | chỉ `~/.gemini/antigravity-cli/skills/` | ⚠️ App không thấy skills; nên ghi cả `~/.gemini/config/skills` |
| **Antigravity** | `settings.json` (`~/.gemini/antigravity-cli/settings.json`) + `hooks.PreToolUse` | ✅ đúng path/key; nhưng hook trỏ `.cmd` | ⚠️ hook Windows-only |

Nguồn:
- Claude Code memory: https://code.claude.com/docs/en/memory.md
- OMP context files: https://raw.githubusercontent.com/can1357/oh-my-pi/main/docs/context-files.md
- OMP system prompt: https://raw.githubusercontent.com/can1357/oh-my-pi/main/docs/system-prompt-customization.md
- OpenCode rules: https://opencode.ai/docs/rules/ · skills: https://opencode.ai/docs/skills/
- Antigravity rules: https://antigravity.google/docs/rules.md · skills: https://antigravity.google/docs/skills.md
- Codex: `openai/codex` `docs/skills.md`, `docs/config.md` (nội dung đã chuyển sang learn.chatgpt.com)

### 0.1 Kết quả kiểm tra bổ sung
- 36/36 `SKILL.md` có frontmatter `name` + `description`, `name` khớp tên thư mục → hợp lệ cho OpenCode/Claude/Antigravity. ✅
- Nội dung "Global Rules" đang tồn tại ở **4 biến thể** (OMP tách `RULES.md`; Claude/Codex/OpenCode inline + lặp MCP Routing 2 lần; DSH inline thiếu MCP Routing; Antigravity không có).
- Quy tắc ngôn ngữ trả lời: Claude/Codex/OpenCode = English, DSH = Vietnamese, OMP/Antigravity = **không có**.

### 0.2 Cần verify nốt trước khi code (không chặn plan)
| # | Câu hỏi | Cách verify |
|---|---|---|
| V1 | Codex có đọc `~/.codex/skills/` không? | `codex --help`; docs learn.chatgpt.com/docs/build-skills; thử 1 skill rồi `/skills` |
| V2 | OMP global skills có đúng `~/.omp/agent/skills/`? | `omp --help`; docs `oh-my-pi/docs/skills.md` |
| V3 | `glab` winget id đúng: `GLab.GLab` hay `GitLab.glab`? | `winget search glab` |
| V4 | Antigravity CLI đọc `~/.gemini/AGENTS.md` hay `~/.gemini/config/AGENTS.md` (ưu tiên nào)? | chạy `agy` với 2 file marker khác nhau |
| V5 | DSH desktop có fallback đọc `%APPDATA%\...\profiles\web` không? | grep app.asar (strings) hoặc test bằng file marker |

---

## 1. Tiêu chí nghiệm thu (Definition of Done)

1. **Một nguồn sự thật**: mọi quyết định per-agent nằm trong `manifest/`, không nằm trong code engine. 6 bản `bootstrap.ps1` (45–70% dòng trùng nhau) bị loại bỏ.
2. **Cùng thứ tự**: 2 OS chạy đúng 12 phase, cùng ID phase, cùng thứ tự prompt, cùng format log.
3. **Cùng lựa chọn**: cùng bộ option, cùng tên, cùng ngữ nghĩa trên Windows và macOS/Linux (kể cả `--overwrite-all` hiện chỉ có trên Windows).
4. **Cài thật – verify thật**: mỗi mục được chọn phải qua `install → config → verify`; verify fail ⇒ exit code ≠ 0 + báo cáo. Không còn `|| true` nuốt lỗi mà không kiểm chứng.
5. **Idempotent**: chạy 2 lần cho cùng kết quả; `--dry-run` không ghi file nào; resume không hỏi lại biến/MCP đã chọn.
6. **An toàn dữ liệu**: mọi ghi đè tạo `.bak.<timestamp>` trên **cả 2 OS**; mọi xoá đi qua Trash/Recycle Bin (kể cả file tạm).
7. **Parity test trong CI**: 1 test so sánh "kế hoạch chạy" (`--dry-run --json`) của 2 engine phải giống nhau.

---

## 2. Kiến trúc đích

```
manifest/
  agents.json          # per-agent: dirs[os], instructionFiles[], skillsDirs[], mcpAdapter, hooks, binary
  mcp.json             # catalog 7 MCP: install{win,mac,linux}, verify, config snippet cho từng adapter
  prompts.json         # thứ tự + wording prompt + resume key (1 nguồn cho 2 OS)
  options.json         # schema option dùng chung → sinh --help + validate
core/
  engine.ps1  engine.sh        # pipeline 12 phase, chỉ plumbing
  lib/{json,yaml,toml,backup,trash,verify}.ps1|.sh
templates/
  common/global-rules.md       # khối Global Rules dùng chung (precedence, MCP routing, ngôn ngữ, xoá)
  <agent>/<instruction files>  # PHẦN DUY NHẤT khác nhau giữa các agent
skills/                        # 1 bản canonical (English), không còn 6 bản
install.ps1  install.sh        # launcher mỏng: parse → engine
setup-*/                       # shim deprecated (in cảnh báo, gọi root)
```

Nguyên tắc: **dữ liệu khác nhau → manifest/templates; code giống nhau → engine**. Hai engine (PS/sh) chỉ khác ngôn ngữ, không khác hành vi; mọi khác biệt hành vi là bug.

---

## 3. Hợp đồng CLI chung (2 OS giống hệt)

| Chức năng | PowerShell | Bash | Ghi chú |
|---|---|---|---|
| Chọn agent | `-Target all\|omp\|claude-code\|opencode\|codex-cli\|dsh\|antigravity-cli` | `--target <...>` | giữ alias `antigravity` |
| Mô phỏng | `-DryRun` | `--dry-run` | không ghi file, in kế hoạch JSON nếu thêm `--json` |
| Bỏ cài binary/MCP | `-SkipInstall` | `--skip-install` | vẫn render config + verify config |
| Auto-confirm | `-Force` | `--force` | không ép cài lại tool đã mới nhất |
| Ghi đè config | `-OverwriteAll` | `--overwrite-all` | **bổ sung cho bash**; luôn tạo `.bak` |
| Memorix | `-EnableMemorix` / `-DisableMemorix` | `--enable-memorix` / `--disable-memorix` | thêm alias `--memorix` / `--no-memorix` |
| Agency | `-EnableAgency` / `-DisableAgency` | `--enable-agency` / `--disable-agency` | **bổ sung cho bash + README** |
| Chọn MCP | `-Mcp all\|none\|a,b,c` | `--mcp ...` | mới, thay cho 7 prompt rời |
| Non-interactive | `-Yes` | `--yes` | mọi prompt lấy default |
| Chỉ kiểm tra | `-Doctor` | `--doctor` | không sửa gì, xuất bảng PASS/FAIL |
| Báo cáo | `-Report <path>` | `--report <path>` | JSON: phase, action, kết quả, version |
| Trợ giúp | `-Help` | `--help` | sinh từ `options.json` |

Quy tắc: option lạ ⇒ exit 2 + in usage; `-Enable*` + `-Disable*` cùng lúc ⇒ exit 2.

---

## 4. Pipeline 12 phase (2 OS bắt buộc giống nhau)

| Phase | Việc | Fail behavior |
|---|---|---|
| **P0 Preflight** | OS/arch/shell, version PS ≥ 5.1, TLS, chuẩn hoá PATH (npm global, uv, brew, cargo) | fail-fast |
| **P1 Args & policy** | parse option, validate, normalize target, kiểm tra xung đột | exit 2 |
| **P2 MCP selection** | 1 lượt chọn (atlassian → gitnexus → context7 → glab → cloakbrowser → memorix → agency), reuse từ key `SETUP_MCP_*` | prompt |
| **P3 Resume & env** | load `.env`, hỏi reuse 1 lần, chỉ thu biến mà MCP đã chọn/target cần | prompt |
| **P4 Prereqs** | Node ≥ 22.18, uv, git, npm | auto-fix / wait-user |
| **P5 Agent binary** | cài CLI của (các) agent target, skip-if-latest | warn + verify fail |
| **P6 MCP tools** | cài từng MCP đã chọn, theo `manifest/mcp.json` | warn + verify fail |
| **P7 Render config** | mcp/agent config, policy `[O]verwrite/[M]erge/[S]kip` + `.bak` (cả 2 OS) | prompt/skip |
| **P8 Instruction files** | ghi đúng path/đúng tên theo `manifest/agents.json` (phần khác nhau duy nhất) | fail-fast |
| **P9 Skills** | sync 1 bản canonical; xoá `memorix-*` cũ qua Trash khi tắt Memorix | warn |
| **P10 Hooks/guards** | đăng ký trash-guard + memorix hooks thật sự (không chỉ copy file) | warn |
| **P11 Verify** | mỗi tool đã chọn: tồn tại + `--version` + parse config + MCP handshake (`initialize`) | **exit ≠ 0** |
| **P12 Cleanup & summary** | dọn temp qua Trash, in bảng tổng kết, ghi report | — |

Điểm sửa so với hiện tại: P7/P8/P10/P11 gần như không tồn tại ở bash; P11 không tồn tại ở cả 2 (chỉ có test MCP rời rạc trong bootstrap).

---

## 5. Ma trận instruction files đích (phần được phép khác nhau)

| Agent | File(s) ghi | Nguồn template | Bỏ / cấm ghi |
|---|---|---|---|
| OMP | `~/.omp/agent/AGENTS.md`, `~/.omp/agent/RULES.md` | `templates/omp/AGENTS.md`, `templates/common/global-rules.md` | ❌ `SYSTEM.md` (nếu tồn tại: cảnh báo + chuyển Trash khi user đồng ý) |
| Claude Code | `~/.claude/CLAUDE.md` | `templates/claude/CLAUDE.md` | ❌ `~/.claude/AGENTS.md` |
| OpenCode | `~/.config/opencode/AGENTS.md` | `templates/opencode/AGENTS.md` | — |
| Codex CLI | `~/.codex/AGENTS.md` | `templates/codex/AGENTS.md` | ❌ `CODEX.md` |
| DSH | `~/.dsh/AGENTS.md` | `templates/dsh/AGENTS.md` | — (profile path sửa ở P7) |
| Antigravity | `~/.gemini/AGENTS.md` (1 file, không trùng `GEMINI.md`) | `templates/antigravity/AGENTS.md` | ❌ `~/.gemini/antigravity-cli/AGENTS.md`, ❌ `GEMINI.md` trùng nội dung |

Cách chống drift nội dung: **build-time composition** — `templates/common/global-rules.md` được render nối vào đầu mỗi template agent (không dựa vào cú pháp `@import` khác nhau của từng tool). Mỗi agent có phần "Agent-specific" riêng ở cuối file.

Quy tắc nội dung thống nhất: cùng 1 câu cho ngôn ngữ trả lời, cùng 1 khối MCP Routing, cùng 1 chính sách xoá file, cùng Subagent role directory.

---

## 6. Ma trận MCP: install → config → verify

| MCP | Install (Windows) | Install (mac/linux) | Verify |
|---|---|---|---|
| company-atlassian | `uv tool install mcp-atlassian==0.23.1` | như trên | `mcp-atlassian --version` |
| gitnexus | `npm i -g gitnexus` | như trên | `gitnexus mcp --help` |
| context7 | `npm i -g @upstash/context7-mcp` | như trên | file `dist/index.js` tồn tại |
| glab | `winget install -e --id <ID đúng>` (V3) | `brew install glab` + fallback `apt/dnf` | `glab --version` |
| cloakbrowser | copy source + `npm ci` | như trên | `mcp-server-full.mjs` + node_modules |
| memorix | `npm i -g memorix` | như trên | `memorix --version` |
| agency | `npm i -g agency-mcp-server` | như trên | resolve path động (**bỏ hardcode `C:\nvm4w\...`**) |

Adapter ghi config (1 hàm/lọng format, không 6 bản):
- JSON: `mcpServers` / `mcp` (opencode) → lọc theo lựa chọn.
- TOML: `[mcp_servers.<name>]` (Codex) → lọc theo lựa chọn (**thiếu ở bash**).
- YAML: `- id: mcp-<name>` (DSH) → lọc theo block + đúng schema (**bash đang lỗi**).
- Antigravity: `settings.json` + hooks.

Chuẩn hoá lệnh: `glab mcp serve` cho mọi agent (DSH đang `glab mcp`); memorix `memorix serve --mode lite` cho mọi agent; gitnexus `gitnexus mcp` (không `cmd /c` trên mac).

---

## 7. Danh sách phải sửa

### P0 — Sai chức năng (phải sửa trước khi release)
1. **OMP `SYSTEM.md`**: ngừng cài; thêm bước phát hiện + di chuyển vào Trash. [install.sh#L960](install.sh#L960), [setup-omp/bootstrap.ps1#L1603-L1605](setup-omp/bootstrap.ps1#L1603-L1605)
2. **Antigravity rules sai thư mục**: chuyển sang `~/.gemini/AGENTS.md`; bỏ bản trong `antigravity-cli/`. [install.sh#L1098-L1100](install.sh#L1098-L1100), [setup-antigravity-cli/bootstrap.ps1#L1462-L1468](setup-antigravity-cli/bootstrap.ps1#L1462-L1468)
3. **DSH profile sai đường dẫn**: dùng `~/.dsh/profiles/<name>` (+ fallback APPDATA). [setup-dsh/bootstrap.ps1#L14-L15](setup-dsh/bootstrap.ps1#L14-L15), [install.sh#L1038-L1042](install.sh#L1038-L1042)
4. **DSH `cordis.patch.yml` (bash) sai cấu trúc**: `__MEMORIX_CONFIG__` chèn `command/args` vào `config:` của `subagent`, không tạo `mcp-memorix`. [install.sh#L1060-L1068](install.sh#L1060-L1068)
5. **DSH `.credentials.yaml` sai schema** (`Refs:` vs `version/refs/apiKey`). [install.sh#L1070-L1077](install.sh#L1070-L1077)
6. **Lọc MCP theo lựa chọn**: bổ sung cho TOML (Codex) + YAML (DSH) trên macOS. [install.sh#L760-L784](install.sh#L760-L784)
7. **Claude memorix MCP không được ghi** trên macOS (template thiếu, bash không thêm). [setup-claude-code/templates/claude.json](setup-claude-code/templates/claude.json)
8. **Không có `.bak` trên macOS** — mọi ghi đè phải backup. [install.sh#L760-L784](install.sh#L760-L784)
9. **Trash-guard không được đăng ký trên macOS** (chỉ copy file); hook dùng `.cmd` (Windows-only). [install.sh#L910-L936](install.sh#L910-L936)
10. **`--disable-memorix` không dọn skills** trên macOS. [install.sh#L860-L880](install.sh#L860-L880)
11. **Resume key MCP đọc sai file** (`SAVED_ENV_PATH` vs `RESUME_ENV_FILE`). [install.sh#L254-L265](install.sh#L254-L265), [#L326-L341](install.sh#L326-L341), [#L409-L420](install.sh#L409-L420)
12. **Antigravity CLI không được cài** (không có bước install binary) + `AGY_MODEL` mặc định lệch (`gemini-2.5-pro` vs `custom/claude-sonnet-5`). [install.sh#L696](install.sh#L696), [install.sh#L1086-L1096](install.sh#L1086-L1096)
13. **DSH không cài CLI** mà chỉ yêu cầu có sẵn (`dsh` trong PATH) — phải có bước cài hoặc fail rõ ràng. [setup-dsh/bootstrap.ps1#L807-L810](setup-dsh/bootstrap.ps1#L807-L810)
14. **`rm -f` vi phạm chính sách xoá mềm** của repo. [install.sh#L247](install.sh#L247)

### P1 — Lệch chuẩn / thiếu đồng bộ
15. Thống nhất khối Global Rules + MCP Routing + ngôn ngữ trong 6 instruction file (§5).
16. Regenerate `setup-{omp,dsh,antigravity-cli}/skills/` từ bản canonical (đang lệch 18 file).
17. Bỏ file chết: `~/.claude/AGENTS.md`, `~/.codex/CODEX.md`, `no-hard-delete.ts` (opencode), skill `delivery` được tham chiếu nhưng không ship.
18. Chuẩn hoá lệnh MCP: glab args, version pin (`$targetAtlassianVer` dùng cho cả 6).
19. Bỏ hardcode `C:\nvm4w\nodejs\agency-mcp-server.cmd` (5 bootstrap).
20. `.env.example`: bỏ inline comment sau `=`; thêm loader strip comment.
21. Thêm trash-guard cho Codex + DSH (hoặc bỏ tuyên bố "6 agent" trong README).
22. `--help` bash thiếu `--disable-memorix`; README thiếu `-EnableAgency/-DisableAgency`, `-Target antigravity`, biến `SETUP_TARGET`.

### P2 — Vệ sinh & bảo trì
23. Dọn `logs/` (48 file), `local_cache/`, `cordis.patch.yml` (root), `.credentials.yaml` (root) → Trash.
24. Xoá 6 `bootstrap.ps1` sau khi migrate; giữ shim `install.sh`/`install.ps1` 1 release.
25. Thêm `.github/workflows/ci.yml` (matrix 3 OS) + Pester + bash test.

---

## 8. Test & CI

| Loại | Nội dung | Gate |
|---|---|---|
| Unit (PS) | Pester cho mỗi hàm lib: render JSON/TOML/YAML, backup, trash, filter MCP | PR |
| Unit (bash) | test bash thuần (không phụ thuộc Pester) cùng bộ case | PR |
| Contract | `--dry-run --json` trên 2 OS → so sánh danh sách phase/prompt/option phải **giống hệt** | PR |
| Golden | render config với key giả → snapshot (JSON/TOML/YAML parse + so sánh) | PR |
| Smoke | cài trong `$HOME` giả lập (như `test-bootstrap.ps1` hiện tại) cho 6 agent × 2 OS | nightly |
| Negative | giả lập tool không cài được ⇒ phải exit ≠ 0 + báo cáo đúng | PR |

---

## 9. Danh sách đề xuất cải tiến (ngoài phạm vi sửa lỗi)

| # | Đề xuất | Lợi ích |
|---|---|---|
| P-01 | `--doctor`: chỉ kiểm tra (path instruction file đúng chỗ, MCP sống, skills load được, hook đã đăng ký) | phát hiện lệch sau khi agent update |
| P-02 | `--report json` + `--json` cho dry-run | CI đọc được, so sánh parity |
| P-03 | Preset `--preset minimal\|full\|offline` thay vì 7 prompt | setup nhanh, ít lỗi nhập |
| P-04 | MCP handshake thật (`initialize` + `tools/list`) thay vì chỉ `--version` | đúng cam kết "cài thật" |
| P-05 | Manifest có JSON Schema + validate trong CI | manifest sai bị chặn sớm |
| P-06 | Sinh README (bảng agent/option/path) từ manifest | docs không lệch |
| P-07 | `--uninstall` (chuyển file do installer tạo vào Trash, giữ config user) | gỡ sạch |
| P-08 | Backup retention (giữ N bản `.bak`) + `--restore <file>` | tránh rác `.bak` như hiện tại (máy đang có 4 bản AGENTS.md.bak) |
| P-09 | Hook cross-platform viết bằng Node (không `.cmd`, không `pwsh` trên mac) | trash-guard chạy được cả 3 OS |
| P-10 | Version pin trong manifest + `--upgrade` tường minh | tái lập được |
| P-11 | Log file + xoay vòng, `--quiet`/`--verbose` | debug dễ, CI gọn |
| P-12 | Kiểm tra trùng instruction file (ví dụ cùng nội dung ở `CLAUDE.md` và `AGENTS.md`) | tránh đốt context |
| P-13 | Cảnh báo khi `~/.omp/agent/SYSTEM.md` hoặc `~/.gemini/antigravity-cli/AGENTS.md` còn tồn tại | dọn di sản |
| P-14 | `--only mcp:gitnexus` / `--only skills` | cài lẻ, sửa nhanh |
| P-15 | Đo và cảnh báo kích thước instruction file (Claude khuyến nghị < 200 dòng; Antigravity 24 KB/file) | tránh bị cắt ngầm |

---

## 10. Migration & tương thích ngược

1. Giữ `-Target`/`--target` và shim `setup-*/install.sh` (deprecated warning, gọi root engine).
2. Map flag cũ → mới: `-EnableMemorix` → `--memorix`, `-DisableMemorix` → `--no-memorix`.
3. Phát hiện di sản khi chạy: `SYSTEM.md` (OMP), `antigravity-cli/AGENTS.md`, `CODEX.md`, cordis ở path cũ → cảnh báo + đề nghị dọn (Trash), không tự xoá.
4. Không đổi URL quickstart trong README.

---

## 11. Thứ tự thực thi

| Đợt | Nội dung | DoD |
|---|---|---|
| **Đ1** | Chốt manifest (agents/mcp/prompts/options) + JSON Schema; verify V1–V5 | manifest validate được, review xong |
| **Đ2** | Engine PS 12 phase + lib + test Pester | 6 agent pass smoke + negative test |
| **Đ3** | Engine bash **port 1-1** từ engine PS (không viết lại logic) | contract test 2 OS giống nhau |
| **Đ4** | Sửa toàn bộ P0 (1–14) trên cả 2 engine | 6 agent × 2 OS verify PASS |
| **Đ5** | P1 (instruction files, skills canonical, dead files, docs) | 36 skills 1 bản; 6 instruction file cùng khung |
| **Đ6** | CI matrix + golden test + docs sinh tự động | CI xanh trên 3 OS |
| **Đ7** | Dọn P2 + release note + deprecation | repo sạch, không còn 6 bootstrap |

---

## 12. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| macOS/Linux không có `pwsh` → hook/hud hỏng | hook viết bằng Node; engine.sh thuần bash |
| DSH đổi đường dẫn profile giữa các bản | detect cả `~/.dsh/profiles/*` và `%APPDATA%`; verify bằng file marker |
| Antigravity CLI đổi tên file rules | `--doctor` kiểm tra cả 4 vị trí global rules |
| Mất config người dùng khi migrate | luôn `.bak` + `[M]erge` mặc định + không xoá cứng |
| Manifest thành "ngôn ngữ lập trình thứ 3" quá phức tạp | giữ manifest khai báo thuần, mọi logic nằm trong engine; review schema ở Đ1 |

---

## 13. Trạng thái triển khai (v1.0.0)

### Đã hoàn thành

| Hạng mục | Kết quả |
|---|---|
| Kiến trúc manifest | `manifest/{agents,mcp,prompts,options}.json` + `scripts/validate.mjs` (6 agents, 7 MCP, 10 prompt, 21 option) |
| Engine dùng chung | `core/engine.mjs` + `core/lib/{util,manifest,render,verify}.mjs` — 1 code path cho Windows/macOS/Linux |
| 13 phase cố định | P0…P12, có `--dry-run --json` xuất đúng danh sách phase/prompt |
| Launcher | `install.ps1` / `install.sh` mỏng, cùng bộ option; shim `setup-*` deprecated |
| Instruction files đúng chuẩn | OMP (AGENTS+RULES, bỏ SYSTEM.md), Claude (CLAUDE.md), OpenCode (AGENTS.md), Codex (AGENTS.md, bỏ CODEX.md), DSH (AGENTS.md), Antigravity (`~/.gemini/AGENTS.md`) |
| Nội dung thống nhất | `templates/common/{global-rules,instructions}.md` + `templates/<agent>/extra.md`; 1 quy tắc ngôn ngữ, 1 khối MCP routing, không lặp |
| Skills canonical | `skills/` (36 skills, 1 bản duy nhất); dọn `memorix-*` vào Thùng rác khi tắt |
| DSH P0 | profile `~/.dsh/profiles/web`, credentials đúng schema, `cordis.patch.yml` sinh `- id: mcp-*` đúng cấu trúc |
| Lọc MCP theo lựa chọn | JSON (`mcpServers`/`mcp`), TOML (`[mcp_servers.*]`), YAML (`- id: mcp-*`) — giữ server người dùng tự thêm |
| Backup + an toàn | `.bak.<timestamp>` trên mọi OS; mọi xoá đi qua Recycle Bin/`~/.Trash` |
| Hooks cross-platform | `pre-tool.mjs` (Node) cho Claude + Antigravity, đăng ký thật trong settings.json |
| Verify | file/config/binary + MCP handshake; MCP cài thất bại ⇒ FAIL (exit ≠ 0) |
| Option mới | `--overwrite-all` (bash), `--agency/--no-agency`, `--mcp`, `--preset`, `--yes`, `--doctor`, `--json`, `--report`, `--strict`, `--quiet/--verbose`, `--env-file` |
| Test | `tests/engine.test.mjs` — 20 test (unit + integration cô lập HOME + contract) |
| CI | `.github/workflows/ci.yml` — matrix 3 OS × Node 22.18/24, validate + test + dry-run + syntax |
| Dọn rác | `logs/`, `local_cache/`, `cordis.patch.yml`, `.credentials.yaml`, 6 engine trùng, 6 bộ skills trùng → Recycle Bin |

### Còn lại (khuyến nghị, không chặn v1.0.0)

- Chạy `--doctor` trên từng máy thật để migrate cấu hình cũ (SYSTEM.md/CODEX.md/antigravity-cli/AGENTS.md sẽ được cảnh báo và dọn khi chạy install).
- Verify `agy`/`codex` skill path (V1/V2) trên máy có cài binary tương ứng.
- Các đề xuất P-01…P-15 ở §9: đã có `--doctor`, `--report`, `--preset`, `--json`, `--strict`, hook Node, backup retention chưa làm.

### Bổ sung v1.0.1 — Consent cho dependency & PATH

| Hạng mục | Kết quả |
|---|---|
| Khai báo dependency | `manifest/prerequisites.json` (node, npm, uv, git) + `requires` trong `manifest/mcp.json`; mỗi dep có `install` theo OS và `guidance` bắt buộc |
| Luồng bắt buộc | Thiếu → in lý do + MCP cần → **hỏi** `[Y/n]` → cài → **verify** → fail thì in hướng dẫn + `[r]etry/[s]kip` (tối đa 3 lần) |
| Chặn đúng phạm vi | Dep thiếu chỉ block các MCP khai báo dep đó; MCP bị block **không được ghi vào config**, verify ghi WARN, cuối chương trình in mục "HƯỚNG XỬ LÝ" + `blockedMcp` trong report |
| PATH setup | `pathRequirements` (npm global bin, uv tool bin, `~/.local/bin`): **hỏi trước khi thêm vào PATH phiên hiện tại**, in cách thêm vĩnh viễn nếu từ chối |
| CloakBrowser | `postInstall` khai báo riêng: hỏi trước khi `npm install` (playwright-core/cloakbrowser), hướng dẫn `cd ... && npm install` nếu fail/từ chối |
| Bỏ cài ngầm | Xoá `ensureUv()` tự động; `--skip-install` không còn cố cài/cảnh báo PATH |
| Test | +7 test: mapping dep, guidance bắt buộc, declined, present, PATH consent, install-then-verify, block đúng MCP (tổng **28/28**) |

### Bổ sung v1.0.2 — Check-first, chỉ hỏi khi chưa đạt

| Hạng mục | Kết quả |
|---|---|
| Đánh giá trước khi hỏi | `assessCommand` / `assessVerify` phân loại `ok \| missing \| outdated \| mismatch \| broken` (PATH + chạy được `--version` + version pin/minVersion) |
| Version requirements | node ≥ 22.18.0, npm ≥ 10.0.0, uv ≥ 0.5.0, git ≥ 2.30.0; `mcp-atlassian` **đúng 0.23.1** (mismatch ⇒ hỏi cài lại) |
| Agent binary (P5) | Chỉ hỏi khi thiếu/sai version/hỏng; `ok` ⇒ bỏ qua im lặng; từ chối ⇒ WARN/FAIL + guidance |
| MCP tools (P6) | Như trên, áp cho từng MCP (kể cả khi binary đã có nhưng sai version) |
| CloakBrowser | Kiểm tra đủ `mcp-server-full.mjs` + `node_modules/playwright-core` + `node_modules/cloakbrowser`; chỉ `npm install` khi thiếu, và chỉ hỏi khi thực sự thiếu |
| Doctor | Seed selection từ flag/default để kiểm tra đúng MCP; thêm dòng `version:<mcp>` PASS/FAIL theo pin |
| Verify (P11) | Kiểm tra version pin cho mọi MCP được chọn (không chỉ lúc cài) |
| Test | +2 test check-first (phân loại 5 trạng thái; doctor phát hiện `mcp-atlassian 0.22.0` lệch pin) — tổng **31/31** |

### Bổ sung v1.0.3 — Doctor kiểm tra đúng cấu hình thực tế

- `--doctor` suy ra danh sách MCP đang có trong config (JSON `mcpServers`/`mcp`, TOML `[mcp_servers.*]`, YAML `- id: mcp-*`) và chỉ verify đúng bộ đó; config chưa có MCP ⇒ `SKIP` thay vì báo FAIL sai.
- `verifyBinary` coi binary "có nhưng `--version` lỗi" là `broken` (FAIL/WARN) và kiểm tra `version`/`minVersion` của agent nếu manifest khai báo.
- Kết quả doctor trên máy thật của repo: 4 vấn đề thật (SYSTEM.md, CODEX.md, antigravity rules sai chỗ) thay vì 16 false-positive.

### Bổ sung v1.0.4 — Cập nhật máy thật DSH + OMP (merge lớp cấu hình, không mất custom)

Bối cảnh: chạy thử installer trên HOME mô phỏng chứa chính file thật của máy (`~/.dsh/profiles/web/cordis.patch.yml`, `~/.dsh/cordis.patch.yml`, `~/.omp/agent/config.yml`, skills, credentials) cho thấy installer **ghi đè** cả cấu hình người dùng.

| Hạng mục | Trước | Sau |
|---|---|---|
| DSH profile layer | Render template rồi `replace('# <<MCP_SERVERS>>')` ⇒ xoá sạch 15 entry custom (3042 B → 4288 B, mất `plugin-market`, `better-sidebar`, `desktop-shell`, `reasoningEffort: max`, `192.168.1.68`) | `R.mergeYamlLayer(existing, template, {ownIds, managedMcpIds})`: entry template sở hữu (`llm-pi-ai`, `agent-preset-registry`, `agent-default-model`, `subagent`, `subagent-model-selection-settings`, `permission`) bị thay; entry khác của user **giữ nguyên**; entry `- id: mcp-*` được regenerate theo lựa chọn |
| Giá trị đang chạy | `baseURL` mất, quay về default `http://localhost:20128/v1` | `preserveFromExisting: { baseURL: AI_BASE_URL }` — giữ endpoint thật trừ khi operator cấp `AI_BASE_URL` qua `.env`/`--env-file` (dùng `ctx.explicitVars`) |
| DSH home layer | Không quản lý | `templates/dsh/home-patch.yml` + config `whenMcp: memorix` ⇒ chỉ ghi `~/.dsh/cordis.patch.yml` khi Memorix được chọn; insert item `memory-memorix` được diff theo id, plugin khác của user trong cùng `- insert:` được giữ |
| DSH credentials | Ghi đè cả khi `--overwrite-all` (mất secret + records) | `preserve: 'sealed'` trong `writeConfig`: file tồn tại ⇒ **không bao giờ** ghi đè, kể cả `--overwrite-all` |
| DSH danh sách rác | Chỉ dọn `memorix-*` | Prune **mọi** thư mục skills không có trong bộ chuẩn 36 (`delivery`, `skills/skills`) vào Thùng rác ở mỗi lần chạy |
| DSH chặn xoá cứng | Không có | Khối `plugins` trong manifest + `ensurePlugin()` (P10): check profile `package.json` (`dependencies` + `dsh.profile.bundles`) → skip nếu đã có → hỏi consent → `dsh plugin --profile web add cc-safety-net` → verify `cc-safety-net status`; tự tìm `pnpm` trong PATH hoặc `%LOCALAPPDATA%\pnpm\bin` |
| OMP `config.yml` | Sẽ bị reset về default của template | `preserve: true` — không ghi; template đã được **đồng bộ ngược** từ máy thật (`advisor: custom/claude-opus-5:high`, `memory/smol/commit/tiny: sonnet-5:medium`, `agentModelOverrides.memory`, `snapcompact.systemPrompt: "agents-md,rules-md"` có quote, có `advisor.enabled: true`) |
| OMP `SYSTEM.md` | Vẫn còn (FAIL doctor) | P8 phát hiện → cảnh báo → chuyển Thùng rác |
| Validator | Không kiểm tra plugin/credential template | Bắt buộc `plugins[].id/package/profile/installGuidance`, `credentialFile.template` tồn tại |
| Test | 31 | **38**: merge giữ entry user + thay entry sở hữu, diff insert theo id, re-run dsh không mất entry/comment + prune skill, credentials không bị ghi đè, home patch chỉ ghi khi bật memorix, entry không sở hữu thắng template, `baseURL` preserve + override bằng `AI_BASE_URL` |

Kết quả mô phỏng trên file thật (HOME tạm): 7/7 MCP trong profile layer, `192.168.1.68` giữ nguyên, `provider: deepseek` (bỏ anthropic), các entry UI/custom còn đủ, `SYSTEM.md` + `delivery` + `skills/skills` vào Thùng rác, `config.yml` của OMP không đổi byte nào.

### Bổ sung v1.0.5 — Ba lỗi lộ ra khi chạy installer trên máy thật

Chỉ chạy trên máy thật mới lộ ra: các test cũ dùng HOME tạm sạch nên không chạm tới nhánh này.

| Lỗi | Triệu chứng | Nguyên nhân | Sửa |
|---|---|---|---|
| `profileDirOf()` đọc `ctx.paths` | `cc-safety-net: cai dat that bai (spawnSync C:\Windows\system32\cmd.exe ENOENT)` và plugin đã cài vẫn bị báo "chua cai" | `paths` nằm trên context **của từng agent** (`agentCtx.paths`), không phải `ctx`; fallback tính ra `~/.dsh/web` (không tồn tại) ⇒ `spawn` với `cwd` sai trả ENOENT | `profileDirOf(plugin, agentCtx)` dùng `agentCtx.paths.extra.profile` |
| `U.run()` không resolve tên trần | `npm install cho CloakBrowser that bai: spawnSync npm ENOENT`; `handshake:memorix spawn memorix ENOENT` | Trên Windows `npm`/`npx`/`memorix` là shim `.cmd`; `spawnSync('npm')` không tự tìm qua PATH | `run()` và `handshake()` gọi `which(cmd)` trước khi `spawnAdapter` |
| `verify.file` của context7 sai | `context7: cai dat khong dung (thieu file )` và `[X]` mỗi lần chạy | Manifest ghi `<npm:context7>` → `resolveNpmPath('context7')` trỏ vào `node_modules/context7` (không tồn tại) | `"<npm:@upstash/context7-mcp/dist/index.js>"` |

Ngoài ra `pluginStatus()` kiểm tra CLI trong `<profile>/node_modules/.bin` trước (`cc-safety-net` không nằm trên PATH toàn cục).

Test bổ sung (40 tổng): `run` resolve tên trần qua PATH; `dsh` nhận diện guard plugin đã có trong profile (không báo "chua cai").
Kết quả trên máy thật: `--target dsh --mcp all` PASS=29 WARN=2 FAIL=0; `--target all --skip-install --mcp all` PASS=79 WARN=4 FAIL=0; `--target all --doctor` PASS=57 WARN=3 FAIL=0 (3 WARN là `opencode`/`codex`/`agy` không có trong PATH máy này).

### Bổ sung v1.0.6 — Sự cố ghi đè config thật và luật merge an toàn

Sự cố: lần chạy `--target all` đầu tiên **ghi đè** cấu hình đang dùng của người vận hành. Nguyên nhân gốc: nhánh JSON chỉ merge khi `policy === 'merge'`, mà chế độ non-interactive/`--overwrite-all` đặt `policy = 'overwrite'` ⇒ ghi template thuần; nhánh TOML/YAML cũng render rồi thay marker nên mất mọi thứ ngoài template.

| File thật bị ảnh hưởng | Mất gì | Đã khôi phục |
|---|---|---|
| `~/.claude/settings.json` | 17 event hooks + `env`; engine sinh entry `{matcher, command, timeout}` phẳng, Claude Code cần `{matcher, hooks:[{type:'command', …}]}` | Từ `settings.json.bak.20261105-053139`; bản bị hỏng giữ lại dưới tên `settings.json.clobbered-<ts>` |
| `~/.codex/config.toml` | MCP `[mcp_servers."9remote"]` + bearer token, `model_providers.9router` + token, 5 `[marketplaces.*]`, 20+ `[plugins.*]`, `[shell_environment_policy.set]`, `[windows] sandbox`, `[projects.*]`, `[memories]`, 25+ `[hooks.state.*]` | Từ `config.toml.bak` (bản gốc 269 dòng, `model_provider = "9router"`) |
| `~/.config/opencode/opencode.json` | `mcp.9remote` (remote + `x-9remote-session` header) | Thêm lại entry `9remote` |

Luật merge sau khi sửa:

| Cơ chế | Hành vi |
|---|---|
| `mergeKeepExisting(base, overlay)` (JSON) | Đệ quy theo object; giá trị `''` hoặc còn chứa `__` **không** ghi đè giá trị live khác rỗng; mảng lấy theo template |
| P7 nhánh JSON | `if (existing) obj = R.mergeKeepExisting(existing, obj)` — bỏ hẳn điều kiện `policy === 'merge'`, nên `--overwrite-all` không còn xoá dữ liệu người dùng |
| `mergeToml(existing, template, {ownedHeaders})` | Template là chủ cho bảng nó khai báo (hoặc có trong `ownedHeaders`) → thay cả bảng, nhưng giá trị live được giữ khi template chỉ có placeholder rỗng; bảng không thuộc quyền installer giữ nguyên từng byte; **scalar top-level đã có trong file live luôn thắng**, template chỉ điền khoá còn thiếu ⇒ re-run không bao giờ viết lại `model_provider`/`model`/`api_key` đang chạy |
| Bảng MCP trong TOML | `[mcp_servers.<id>]` và `[mcp_servers."<id>"]` được thêm vào `ownedHeaders` ⇒ MCP bị bỏ chọn sẽ biến mất, MCP của người dùng (`9remote`) vẫn còn |
| `registerJsonHook(settings, hook, {shape})` | `shape: 'claude'` ⇒ `{matcher, hooks:[{type:'command', command, timeout}]}`; mặc định vẫn phẳng cho Antigravity; dedupe đọc cả `entry.hooks[].command` và `entry.command` |
| P10 hook | `R.writeJson(file, obj, ctx.mode !== 'install')` (trước hardcode dry-run `false`) |
| `manifest/agents.json` | hook claude có `"shape": "claude"`; config codex `kind: "toml"`, `mcpMerge: true` |

Test bổ sung (46 tổng): json merge không xoá khoá người dùng kể cả `--overwrite-all`; hook Claude đúng shape lồng; merge TOML giữ bảng MCP của người dùng; **merge TOML giữ scalar live + bảng provider/hook của người dùng và xoá MCP bị bỏ chọn, không sinh khoá trùng**; placeholder rỗng không xoá giá trị live.

Kiểm chứng trên máy thật sau sửa (`--target all --yes --skip-install --mcp all` → PASS=79 WARN=4 FAIL=0): `settings.json` còn 17 event/3 entry PreToolUse (orca + notify curl + trash-guard), `~/.claude.json` 8 MCP gồm `9remote`; codex 299 dòng còn đủ 14/14 marker người dùng; opencode giữ token `9remote` + plugin `no-hard-delete`; OMP `config.yml` không đổi (`advisor: custom/claude-opus-5:high`), `SYSTEM.md` đã vào Thùng rác, skills 36; DSH `cordis.patch.yml` 23 entry giữ `192.168.1.68`/`plugin-market`/`better-sidebar`/`reasoningEffort: max`, `AGENTS.md` chỉ còn 1 khối Pre-flight, skills 36; Antigravity giữ shape phẳng 2 matcher.

### Bổ sung v1.0.7 — Fail-closed cho parser, cách ly test, siết launcher

Rà soát độc lập sau sự cố v1.0.6 cho thấy các bộ merge từng **âm thầm làm mất dữ liệu** thay vì từ chối. Nguyên tắc mới: cấu trúc nằm ngoài tập con mà parser dòng có thể xử lý an toàn thì phải **ném lỗi**, không được đoán.

| Hạng mục | Lỗi tái hiện được | Sửa |
|---|---|---|
| `mergeToml` — header trích dẫn | `[mcp_servers."9remote"]` (đúng cách Codex ghi id) bị coi là bảng không hỗ trợ, còn `engine.mjs:486` lại đẩy chính header đó vào `ownedHeaders` | Thêm `tomlHeaderKey()` (export): chuẩn hoá segment trích dẫn về cùng khoá bảng với dạng trần nên `[a."b"]` ≡ `[a.b]`; segment rỗng hoặc chứa escape vẫn fail-closed |
| `mergeToml` — quoted/dotted key, `[[array-of-tables]]`, multiline string | `"my.key"`, `child.key`, `[[jobs]]`, `"""…"""` bị xoá khỏi bảng live | Guard fail-closed ở đầu hàm (`Cannot safely merge unsupported TOML table` / `… TOML value`), kiểm trên **cả** hai lớp |
| `mergeToml` — multiline array | `args = [\n "one",\n]` bị nén thành một dòng, mất phần tử | Fail-closed `Cannot safely merge multiline TOML array` (quét độ sâu ngoặc có tính quote/escape/comment) |
| `mergeYamlLayer` — block scalar | `- \|` (sequence) lọt guard chỉ bắt `key: \|`, rồi `replace(/\n{3,}/g,'\n\n')` gộp newline **bên trong** scalar | Regex phủ cả `- \|`, `- >`, `- \|-`, `- \|+` và mapping, trên cả hai lớp ⇒ `Cannot safely merge YAML block scalar` |
| `mergeYamlLayer` — insert trùng id | Insert không thuộc `managedInsertIds` bị template ghi đè (mất item người dùng); luật cũ còn để template phát lại item trùng id | `existingInsertIds` loại id managed; `keptInserts` chỉ lọc theo `managedInsertIds`; `templateInserts` bỏ id đã có ở live không managed ⇒ live thắng, mỗi `id:` xuất hiện đúng một lần |
| `mergeYamlLayer` — insert không theo mẫu | Item bắt đầu `- name: user` bị **bỏ toàn bộ** (parser chỉ nhận `- id:`) | Fail-closed `Cannot safely merge unsupported YAML insert item` / `… nested YAML insert` / `… YAML insert preamble` |
| `mergeKeepExisting` (JSON) | Mảng rỗng trong template xoá `permissions.allow/deny` của người dùng | Mảng rỗng ở template **không** ghi đè mảng live khác rỗng; JSON live hỏng thì `readJsonIfExists` ném lỗi thay vì trả rỗng |
| `versionOf` | Đọc version từ stdout/stderr dù exit code 1 ⇒ tool hỏng bị báo `ok v99.0.0` | Chỉ nhận khi `status === 0` và không có `r.error` |
| `refreshPath` (deps) | Tự sửa PATH phiên hiện tại không hỏi | No-op; chỉ `ensurePathRequirements` sửa PATH **sau consent từng thư mục** |
| P10 memorix hooks | `--skip-install` vẫn gọi `memorix hooks install --global` (ghi ra ngoài HOME test) | Guard `!ctx.skip-install` |
| P11 doctor | Chỉ kiểm bộ MCP theo lựa chọn, không theo cấu hình thật; JSON MCP thiếu/hỏng rơi vào SKIP | Đối chiếu `activeMcp` đọc từ config; JSON MCP thiếu/hỏng ⇒ FAIL (không tạo thư mục khi chỉ kiểm tra) |
| P0/P6 | `ensureDir` chạy cả khi chỉ kiểm tra; MCP bị từ chối/lỗi cài vẫn được ghi vào config | Chỉ tạo thư mục khi install; MCP lỗi vào `blockedMcp` và bị loại khỏi P7/P8/P9/P10 |
| P9 skills | Prune mọi thư mục ngoài bộ chuẩn ⇒ xoá skill riêng của người dùng | Không prune; chỉ ghi skill còn thiếu, không ghi đè skill trùng tên chưa rõ chủ sở hữu |
| Launcher | `-Version`/`-Verbose` không map; `--dry-run/--doctor/--help/--version` vẫn thử cài Node | Map `-Version` → `--version`, `-Verbose` → `--verbose`; `NODE_INSTALL_DISABLED` cho các chế độ chỉ đọc, chỉ cài Node sau `--yes/-y/--force` |
| Test | `runEngine` kế thừa `process.env` + `os.tmpdir()` ⇒ test có thể chạm HOME/PATH thật | `tempHome()` trong `tests/.tmp-engine`; env allowlist (chỉ `SystemRoot`); preload `tests/engine-process-guard.cjs` trả bảng giả cho `which`/`--version` và chặn mọi `spawn/exec/fork`; ca dùng CLI thật chuyển sang opt-in `SAC_TEST_LAUNCHERS=1` / `SAC_TEST_REAL_CLI=1` |

Test hiện tại: **109 test, 107 pass, 2 skip** (2 ca opt-in), `node scripts/validate.mjs` OK, `bash -n install.sh` OK. Test mới trong đợt này: `tests/parser-fail-closed.test.mjs`, `tests/merge-safety.test.mjs`, `tests/yaml-scalar-regression.test.mjs`, `tests/yaml-insert-collision-scalar.test.mjs`, `tests/mcp-block-safety.test.mjs`, `tests/plugin-safety.test.mjs`, `tests/skills-safety.test.mjs`, `tests/doctor-mcp-safety.test.mjs`, `tests/doctor-mcp-version.test.mjs`, `tests/version-safety.test.mjs`, `tests/deps-refresh-path.test.mjs`, `tests/uv-path-consent.test.mjs`, `tests/memorix-hooks-skip-install.test.mjs`, `tests/install-shim-parity.test.ps1`.

Hạn chế đã biết của v1.0.7: parser vẫn là dòng-based nên chỉ hỗ trợ tập con TOML/YAML; mọi cấu trúc ngoài tập con đó bị **từ chối** (an toàn nhưng không cập nhật được file), muốn mở rộng phải dùng parser thật. Preload test trả kết quả giả nên nhánh "cài thành công" của dependency/version chỉ được mô phỏng, không chứng minh binary thật.

---

## Bổ sung v1.1.0 — Bỏ hoàn toàn MCP `agency`

**Quyết định (m04240):** người dùng bỏ agency, kể cả trong lệnh setup.

| Hạng mục | Trước | Sau |
|---|---|---|
| `manifest/mcp.json` | 7 server (có `agency`, `kind: "agency"`) | 6 server (bỏ hẳn entry) |
| `manifest/options.json` | 21 option, có `--agency` / `--no-agency` | 19 option |
| `manifest/agents.json` | `optionalSections.agency` ở 6 agent | Bỏ (không còn chèn mục Agency vào instruction file) |
| `templates/sections/agency.md` | 14 dòng | Chuyển vào Thùng rác |
| `templates/antigravity/settings.json`, `templates/opencode/opencode.json` | Có block `agency` tĩnh | Bỏ |
| `core/lib/manifest.mjs` | `buildServerSpec` có nhánh `kind === 'agency'` | Bỏ |
| `core/engine.mjs` | Xử lý `--agency/--no-agency`, biến `AGENCY_PATH` | Bỏ cả hai |
| `install.ps1`, `install.sh` | `-EnableAgency/-DisableAgency`, `--agency/--no-agency` | Bỏ |
| 12 shim `setup-*` | Map `EnableAgency/DisableAgency`, `-AgencyPath` | Bỏ |
| `manifest/prerequisites.json` | 3 mô tả nhắc agency | Sửa lại còn gitnexus/context7/memorix |

**Không có cơ chế tự gỡ:** `knownMcpIds()` chỉ gồm server manifest còn ship, nên entry `mcp-agency` / `mcp-glab` có sẵn trong config vẫn được coi là server người dùng và **được giữ nguyên**. Máy nào muốn bỏ thì xoá tay (máy này đã xoá surgical ở trên).

**Test:** `tests/engine.test.mjs` chuyển ca "dsh re-run" sang chọn `context7`, thêm entry `- id: mcp-agency` có sẵn trong patch và assert nó bị gỡ; ca merge dùng `mcp-context7`.

### Cập nhật cùng v1.1.0 — Bỏ luôn `glab`

Người dùng chốt bỏ `glab` (máy có binary `glab` nhưng **không có** `~/.config/glab-cli` và chưa `glab auth login`; remote đang dùng là GitHub).

- `manifest/mcp.json`: còn 5 server (bỏ hẳn entry).
- `manifest/prompts.json`: bỏ 2 prompt `GITLAB_HOST` (default `10.30.1.17`) và `GITLAB_TOKEN`; còn 8 prompt.
- `core/engine.mjs`: bỏ `GITLAB_HOST`/`GITLAB_TOKEN` khỏi `buildVars`.
- `manifest/prerequisites.json`: mô tả `git` không còn nhắc glab.
- `templates/antigravity/settings.json`, `templates/opencode/opencode.json`: bỏ block `glab`.
- `README.md`: bỏ dòng dependency glab, bỏ `glab` khỏi danh sách MCP, bỏ 2 dòng `GITLAB_*` trong `.env` mẫu.

**Áp dụng lên máy thật (surgical, có backup):** xoá đúng entry `agency`/`glab` trong 6 file, giữ nguyên phần còn lại:

| File | Trước | Sau |
|---|---|---|
| `~/.omp/agent/mcp.json` | 7 server | 5 server |
| `~/.claude.json` | 8 server (giữ `9remote`) | 6 server |
| `~/.config/opencode/opencode.json` | 8 (giữ `9remote`) | 6 |
| `~/.gemini/antigravity-cli/settings.json` | 7 | 5 |
| `~/.dsh/profiles/web/cordis.patch.yml` | 23 entry / 7 mcp | 21 entry / 5 mcp |
| `~/.codex/config.toml` | 12 header `[mcp_servers.*]` | 9 header (giữ `"9remote"`, `node_repl`) |

Verify sau khi xoá: mọi JSON parse được, không mất top-level key nào, `9remote` + token còn nguyên, các marker custom của DSH (`192.168.1.68`, `plugin-market`, `better-sidebar`, `desktop-shell`, `windowsMaterial`, `fontSize: 13`, `computer-use`) còn nguyên. Backup: `<file>.bak.202611050724` cho từng file.

**Quyết định cuối (m04491):** chỉ **ngừng cài / ngừng kiểm tra / ngừng hỏi** về `agency` và `glab`. Không thêm cơ chế tự xoá entry trên máy khác.
