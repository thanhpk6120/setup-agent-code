# Setup Agent Team IDE

Bộ script cài đặt nhanh cấu hình chuẩn cho **Agent Team IDE** (Windows, macOS, Linux):
- Tạo đầy đủ **19 role agent chuẩn** (`orchestrator`, `research`, `coder`, `tester`, `reviewer`, `planner`, `architect`, `critic`, `debugger`, `frontend`, `backend`, `security`, `accessibility`, `performance`, `devops`, `docs`, `git`, `db`, `log`).
- Đóng gói và cài sẵn skill **`grilling`** (bật cho `orchestrator` và `planner`).
- Dọn sạch các skill bị bật thừa trên các built-in `roleId` agent (giữ nguyên agent tùy chỉnh và `profileId`/`model` sẵn có, tự tạo file backup `agents.json.bak.*` trước khi sửa).
- Nếu phát hiện `skills/grilling-2` bị trùng, tự động chuyển vào Recycle Bin / Trash.

## Yêu cầu
- **Node.js >= 20** (đã cài sẵn nếu dùng `setup-agent-code`).
- Đã cài **Agent Team IDE** và đăng nhập tài khoản CLI (mặc định `antigravity`).

## Cách chạy nhanh trên máy mới

### Windows (PowerShell)
```powershell
.\setup-agent-team-ide\install.ps1
```

Xem trước thay đổi (không ghi file):
```powershell
.\setup-agent-team-ide\install.ps1 -DryRun
```

### macOS / Linux
```bash
bash ./setup-agent-team-ide/install.sh
```

### Tùy chọn nâng cao (`setup.mjs`)
```bash
node ./setup-agent-team-ide/setup.mjs --help
```
- `--cli <cliId>`: đổi CLI mặc định cho agent mới (mặc định: kế thừa từ `orchestrator` hoặc `antigravity`).
- `--profile <profileId>`: chỉ định `profileId` cho agent mới.
- `--storage-dir <path>`: chỉ định thư mục `globalStorage` tùy chọn (hữu ích khi test).
- `--no-clean-skills`: không dọn skill đang bật trên các agent có sẵn.
- `--force`: ghi đè lại file trong `skills/grilling`.
- `--dry-run`: chạy thử, không ghi file.
- `--json`: xuất kết quả dạng JSON.

## Chạy test
```bash
node --test ./setup-agent-team-ide/setup.test.mjs
```
