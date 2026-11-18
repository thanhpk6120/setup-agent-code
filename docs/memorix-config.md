# Hướng dẫn cấu hình Memorix (`~/.memorix/config.toml`)

Tài liệu này hướng dẫn cấu hình LLM Formation, embedding local và các tùy chọn Git/Server cho **Memorix** để áp dụng nhanh trên máy mới (sau khi đã chạy bộ cài `install.ps1` / `install.sh` của repo này).

---

## 1. Vị trí file cấu hình

Tạo hoặc cập nhật file cấu hình toàn cục của Memorix tại:

- **Windows:** `%USERPROFILE%\.memorix\config.toml` (ví dụ `C:\Users\<User>\.memorix\config.toml`)
- **macOS / Linux:** `~/.memorix/config.toml`

> [!CAUTION]
> **Không commit `config.toml` chứa `api_key` thật lên Git.** Luôn giữ file này trong thư mục cá nhân `~/.memorix/`.

---

## 2. Cấu hình mẫu (OpenRouter `:free` + FastEmbed local)

```toml
[agent]
provider = "openai"
model = "baidu/ernie-5.5-flash-preview:free"
base_url = "https://openrouter.ai/api/v1"
api_key = "<OPENROUTER_API_KEY>"

[memory.llm]
provider = "openai"
model = "baidu/ernie-5.5-flash-preview:free"
base_url = "https://openrouter.ai/api/v1"
api_key = "<OPENROUTER_API_KEY>"

[embedding]
provider = "fastembed"

[git]
auto_hook = true
ingest_on_commit = true
max_diff_size = 500
skip_merge_commits = true
# exclude_patterns = ["*.lock", "dist/**"]

[memory]
inject = "full"
sync_advisory = true
auto_cleanup = true
formation = "active"

[server]
transport = "stdio"
dashboard = true
dashboard_port = 3210
```

### Lựa chọn model `:free` trên OpenRouter
Memorix đặt `DEFAULT_FORMATION_TIMEOUT_MS = 12000` (12 giây) và yêu cầu model trả về JSON sạch ở `message.content`:

| Model `:free` | Ghi chú |
|---|---|
| `baidu/ernie-5.5-flash-preview:free` | **Khuyến nghị**: phản hồi nhanh (~0.9–3.4s), trả JSON ổn định, context 1M |
| `inclusionai/ling-3.2-flash:free` | Dự phòng tốt (~2.5s), trả JSON sạch, context 1M |
| `cohere/north-mini-code:free` | Dự phòng thiên về code (~2.8s), context 256K |

> [!NOTE]
> Tránh dùng các model reasoning-only mà phần suy luận ăn hết `max_tokens` khiến `message.content` bị rỗng (ví dụ một số model `:free` bật reasoning mặc định), và kiểm tra lại danh sách `:free` nếu OpenRouter thay đổi slug theo thời gian.

---

## 3. Lưu ý khi dùng cùng `memorix-mcp-wrapper` & `serve-http`

1. **Wrapper mặc định của repo:** Bộ cài `setup-agent-code` cấu hình MCP `memorix` qua `memorix-mcp-wrapper.mjs` — ưu tiên kết nối `memorix serve-http` (`127.0.0.1:3211`) để tránh lỗi SQLite `database is locked` khi mở nhiều agent song song, và tự fallback sang `memorix serve --mode lite` nếu server HTTP chưa chạy.
2. **Nạp lại cấu hình khi đang chạy `serve-http`:** Nếu `memorix serve-http` đang chạy nền từ trước khi bạn sửa `~/.memorix/config.toml`, hãy khởi động lại tiến trình `serve-http` để nạp config mới.
3. **Thư mục `local_cache` & gói `fastembed`:**
   - Nếu đặt `[embedding] provider = "fastembed"`, gói `fastembed` là optional dependency — nếu chưa cài, `memorix doctor` sẽ báo `Cannot find package 'fastembed'` (`temporarily_unavailable`). Cài bằng `npm install -g fastembed --allow-scripts=onnxruntime-node` (cần `--allow-scripts=onnxruntime-node` để tải native binary ONNX Runtime nếu npm chặn install scripts), hoặc bỏ `[embedding]` để Memorix dùng provider mặc định.
   - Khi `fastembed` chạy qua `memorix serve` (stdio), nó có thể tải model `fast-bge-small-en-v1.5` (~75 MB) vào `./local_cache` tại `cwd` của tiến trình. Nên thêm `local_cache/` vào `.gitignore` toàn cục nếu không muốn dính vào git.
4. **Tắt LLM Formation nếu muốn chạy 100% offline/nhanh hơn:** Đổi `formation = "passive"` hoặc xóa `[agent]` / `[memory.llm]` nếu agent đã tự tóm tắt qua `memorix_store` + `topicKey`.

---

## 4. Cách áp dụng & kiểm tra trên máy mới (1 lệnh)

Bạn có thể dùng script tự động đi kèm trong repo để cài đặt toàn bộ giống hệ thống hiện tại (`memorix`, `fastembed --allow-scripts=onnxruntime-node`, `memorix-mcp-wrapper.mjs`, `~/.memorix/config.toml`, `ensure-serve-http.mjs`, `prune-snapshots.mjs` và auto-start khi khởi động máy):

```powershell
# Chạy setup đầy đủ (thay <OPENROUTER_API_KEY> bằng key của bạn)
node scripts/setup-memorix.mjs --api-key "<OPENROUTER_API_KEY>"

# Hoặc qua npm script (có thể truyền -- --dry-run để xem trước):
npm run setup:memorix -- --api-key "<OPENROUTER_API_KEY>"
```

Sau đó gắn MCP và hook `memorix-gate` cho các coding agent:

```powershell
# Windows:
.\install.ps1 -EnableMemorix

# macOS / Linux:
./install.sh --memorix
```

Kiểm tra trạng thái:

```powershell
memorix doctor
```

---

## 5. Tự động khởi động khi mở máy & dọn snapshot DB (khuyên dùng)

- **Auto-start `serve-http` (tự tạo bởi `scripts/setup-memorix.mjs`):**
  - **Windows:** `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\memorix-serve-http.vbs` gọi ẩn `~/.memorix/ensure-serve-http.mjs` (check port `3211`, idempotent).
  - **macOS:** `~/Library/LaunchAgents/com.memorix.serve-http.plist`.
  - **Linux:** `~/.config/autostart/memorix-serve-http.desktop`.
- **Dọn lịch sử snapshot code định kỳ (giữ nguyên observations):**
  Chạy `node ~/.memorix/prune-snapshots.mjs` (hỗ trợ `--dry-run` và biến `MEMORIX_KEEP_SNAPSHOTS=5`). Script chỉ giữ lại 5 snapshot mới nhất mỗi `projectId` trong `code_state_snapshots`, chạy `VACUUM` + `PRAGMA wal_checkpoint(TRUNCATE)`, **không chạm tới `observations`, `knowledge_claims` hay `evidence_cards`**.
