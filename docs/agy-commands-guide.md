# Cẩm Nang Toàn Diện Các Lệnh Antigravity CLI (`agy`) — Khi Nào Dùng Lệnh Nào?

Tài liệu này tổng hợp đầy đủ các **Slash Commands (TUI)**, **Execution Modes**, **Phím tắt**, **CLI Subcommands**, **Startup Flags** và **Playbooks phối hợp lệnh** của **Google Antigravity CLI (`agy`)**, đối chiếu từ tài liệu chính thức (`antigravity.google/docs/cli/reference`, `slash-commands`, `cli/modes`, `cli/headless`, `cli/statusline`) và `agy --help` thực tế trên máy.

---

## 1. Bản Đồ Ra Quyết Định Nhanh ("Khi nào dùng lệnh nào?")

### 1.1. Tra cứu nhanh theo tình huống

| Tình huống thực tế | Lệnh nên dùng | Ghi chú nhanh |
|---|---|---|
| Tác vụ đơn giản, rõ ràng (sửa 1–2 file, hỏi đáp nhanh) | Prompt trực tiếp | Không cần slash command |
| Yêu cầu mơ hồ, còn nhiều quyết định thiết kế chưa chốt | `/grill-me <task>` | Agent hỏi từng câu một, luôn đề xuất đáp án `(Recommended)` |
| Cần thống nhất kế hoạch trước khi sửa code | `/plan <task>` hoặc `/plan /grill-me <task>` | Sinh *Implementation Plan artifact* để review/comment trước khi chạy |
| Tác vụ dài (chạy qua đêm, migration, fix toàn bộ test) không muốn dừng giữa chừng | `/goal <objective>` | Chặn dừng sớm, ép tự kiểm chứng bằng chứng thật trước khi kết thúc |
| Bug khó (race condition, deadlock, tối ưu thuật toán, refactor rối) | `/boost <task>` | *Paid plans*. Chạy pipeline đa-tác-tử phản biện & kiểm chứng nhiều vòng |
| Tác vụ rộng, chia sạch theo từng file / package / hướng điều tra | `/swarm <task>` | *All plans*. Nhiều worker + `@verifier` phối hợp trên message board (`Alt+S`) |
| Quy trình lặp theo danh sách file hoặc theo pha tuần tự có schema chặt | `/run-workflow <task>` | *All plans*. Sinh script Python (`parallel()`, `pipeline()`), sạch context chính |
| Dự án lớn nhiều cột mốc kéo dài nhiều giờ/ngày | `/teamwork <goal>` | *Paid plans*. Phỏng vấn scoping + `~/teamwork_projects/` + 4 cổng audit |
| Kiểm tra giao diện web, console error, network, chụp screenshot | `/browser <task>` | Trên CLI cần Chrome `v144+` bật remote debugging |
| Hẹn giờ kiểm tra CI/deploy hoặc chạy cron ngay trong phiên chat | `/schedule <when> <task>` | Timer 1 lần hoặc cron 5 trường; xem/hủy ở `/tasks` |
| Muốn hỏi ngang 1 câu nhanh trong lúc agent chính đang chạy | `/btw <question>` | Chạy fork read-only, không làm bẩn lịch sử hội thoại chính |
| Context đầy/dài sau khi explore xong, muốn nén lại để làm tiếp | `/compact [next-step]` | Tóm tắt thành checkpoint, giữ lại quyết định, path, artifacts, subagents |
| Muốn xem token đang tốn vào đâu (MCP, rules, tool calls…) | `/context` | Hiện lưới trực quan & phân bổ token từng hạng mục |
| Muốn xem diff, lịch sử từng turn hoặc comment thẳng vào dòng code | `/diff` | 3 chế độ: All Changes / Per Turn / Commit Tree; nhấn `C` để comment |
| Tìm kiếm code nhanh trong workspace không làm gián đoạn agent | `/codesearch <query>` (`/cs`, `/search`) | Hỗ trợ regex, `-F` (literal), `f:<glob>`, comment dòng `C` → `Y` |
| Agent đi sai hướng nhiều bước, muốn quay lui | `/rewind` (`/undo`) hoặc `Esc` | `Esc` ngắt lượt đang chạy; `/rewind` lùi lịch sử hội thoại |
| Muốn thử hướng khác song song mà không mất nhánh chính | `/fork` (`/branch`) | Nhân bản session hiện tại; quay lại bằng `/resume` |
| Muốn lưu bài học/quy tắc vừa sửa agent cho các phiên sau | `/learn [instruction]` | Đề xuất `learning_proposal.md` (Rule hoặc Skill) để bạn duyệt |
| Đổi model cho **1 lượt duy nhất** không đổi mặc định | `/model <model> <prompt>` | Đổi mặc định thì dùng `/model` không tham số |
| Chỉnh độ sâu suy luận (tốc độ vs độ kỹ) | `/effort [low\|medium\|high\|xhigh\|max]` | Không áp dụng cho model cố định effort (như Orchestrator) |
| Kiểm tra hạn mức / credit còn lại | `/usage` (`/quota`), `/credits` | `/usage` làm mới quota theo nhóm model |
| Cấu hình model riêng cho Review Gate (custom skill của repo này) | `/advisor [tier\|<model-id>\|on\|off\|status]` | Lưu vào `~/.gemini/antigravity-cli/review-gate.json` |

---

### 1.2. Ma trận chọn chế độ Lập kế hoạch & Đa tác tử

| Lệnh | Trọng tâm | Cách phối hợp & Cô lập | Cơ chế kiểm chứng | Thời lượng | Gói (Plan Tier) | Tránh dùng khi |
|---|---|---|---|---|---|---|
| **Prompt thường** | Sửa nhanh, hỏi đáp | 1 agent chính (hoặc Orchestrator) | Bạn tự kiểm tra / test | Giây – phút | All plans | Việc nhiều file phức tạp hoặc dễ sửa nhầm |
| **`/grill-me`** | Phỏng vấn làm rõ yêu cầu | 1 agent đọc code rồi hỏi từng câu | Đồng thuận quyết định trước khi code | Phút | All plans | Yêu cầu đã rõ 100%, chỉ cần làm ngay |
| **`/plan`** | Khám phá & lập kế hoạch | Read-only explore → *Implementation Plan* | Bạn duyệt/comment (`Proceed`) | Phút | All plans | Sửa nhỏ 1–2 dòng không cần artifact |
| **`/goal`** | Tự chủ chạy đến khi xong | 1 agent + subagent; *goal stop hook* chặn dừng sớm | Bắt buộc đối chiếu từng deliverable với output thật | Phút – nhiều giờ | All plans | Tiêu chí xong mơ hồ, chưa thống nhất thiết kế |
| **`/boost`** | Suy luận sâu cho bài toán khó | Pipeline: Worker làm → Worker phản biện/phá lỗi → Orchestrator kiểm tra | Vòng phản biện + chạy test thật | Giây – nhiều giờ | **Paid plans** | Việc đơn giản hoặc chỉ cần chia đều nhiều file |
| **`/swarm`** | Chia việc song song giao tiếp ngang hàng | Coordinator + Named Workers + `@verifier` trên message board | `@verifier` riêng (có thể pin model khác) review diff & chạy test | Phút – giờ | All plans | Các bước phụ thuộc chặt chẽ tuần tự không tách được |
| **`/run-workflow`** | Điều phối kịch bản có cấu trúc | Script Python (`parallel()`, `pipeline()`, `phase()`) | Mỗi agent trả JSON theo Schema | Phút – giờ | All plans | Agent cần trao đổi tự do với nhau giữa chừng |
| **`/teamwork`** | Dự án dài nhiều cột mốc | `Sentinel` + `Project Orchestrator` + `Explorers` + `Workers` trong `~/teamwork_projects/` | 4 cổng độc lập: `Critic`, `Challenger`, `Auditor`, `Success Auditor` | Giờ – nhiều ngày | **Paid plans** | Task nhỏ gọn trong 1–2 giờ hoặc sửa ngay trên repo chính không muốn tách thư mục |

---

### 1.3. Ma trận Quản lý Context & Session

| Mục tiêu | Lệnh | Tác động lên Context & Lịch sử |
|---|---|---|
| Làm gọn context để tiếp tục công việc hiện tại | `/compact [message]` | Nén các lượt cũ thành *checkpoint*, giữ quyết định, file paths, artifacts, subagents đang chạy |
| Hỏi thông tin phụ mà không tốn token cho các lượt sau | `/btw <question>` | Tạo fork read-only chạy ngầm; câu hỏi & kết quả **không** ghi vào thread chính |
| Xem chi tiết token đang bị chiếm bởi thành phần nào | `/context` | Chỉ đọc: hiện lưới ô vuông, tỷ lệ từng nhóm (User, Agent, Tool, MCP, Rules, Skills, Checkpoint) |
| Quay lui trước một loạt bước sai/hỏng build | `/rewind` (`/undo`) | Cuộn ngược lịch sử hội thoại về message trước đó |
| Thử nghiệm hướng đi rủi ro song song | `/fork` (`/branch`) | Tạo bản sao thread hiện tại thành session mới độc lập |
| Chuyển sang việc hoàn toàn khác | `/clear` (`/new`) | Xóa trắng context hiện tại, bắt đầu hội thoại mới |
| Mở lại hội thoại cũ (CLI hoặc import từ Antigravity App) | `/resume` (`/switch`, `/conversation`) | Mở picker; hỗ trợ tìm kiếm, `F2` đổi tên, `F4` xóa, `Tab` import từ App |

---

### 1.4. Ma trận Lập lịch: `/schedule` vs `/automation`

| Tiêu chí | `/schedule` | `/automation` |
|---|---|---|
| **Mặt nền hỗ trợ** | App, **CLI**, IDE extensions | **Chỉ Antigravity App** (không có trên CLI) |
| **Phạm vi sống** | Gắn với **phiên hội thoại hiện tại** (trừ `IsDaemon: true` trong tool) | **Bền vững**, chạy nền kể cả khi đóng hội thoại (`~/.gemini/config/sidecars/`) |
| **Context khi chạy** | Đánh thức chính agent đang mở với đầy đủ lịch sử chat | Mỗi lần chạy mở một hội thoại mới tinh |
| **Khi nào dùng** | Poll CI/CD, đợi deploy, nhắc kiểm tra sau N phút trong lúc đang làm việc | Job định kỳ hàng ngày/tuần (báo cáo PR, chạy test đêm) |

---

## 2. Chi Tiết Toàn Bộ Slash Commands Trong TUI `agy`

Gõ `/` trong ô nhập lệnh của `agy` để mở menu gợi ý (gõ tiếp để lọc, nhấn `Tab` để điền nhanh).

### A. Lập kế hoạch & Làm rõ yêu cầu

- **`/plan [task]`**
  - **Chức năng:** Khám phá codebase ở chế độ chỉ đọc, hỏi làm rõ nếu thiếu thông tin, xuất *Implementation Plan* để duyệt trước khi sửa code. Chạy `/plan` không tham số để mở phiên khám phá dựa trên ngữ cảnh hiện tại.
  - **Dùng khi:** Refactor nhiều file, thay đổi kiến trúc, migration rủi ro cao, hoặc khi muốn kiểm soát chiến lược của agent trước khi nó chạm vào file.
- **`/grill-me [task]`**
  - **Chức năng:** Agent đọc code trước để tránh hỏi những gì code đã trả lời được, sau đó phỏng vấn bạn **từng câu một** kèm phương án `(Recommended)` đứng đầu và tùy chọn `Write-in…` (`Esc` để bỏ qua câu hỏi).
  - **Dùng khi:** Yêu cầu còn ngắn/mơ hồ (nhiều trade-off về DB, auth, API contract, error handling) hoặc muốn agent vặn lại các giả định trong thiết kế của bạn.
  - **Mẹo phối hợp:** Dùng `/plan /grill-me <task>` để agent phỏng vấn xong sẽ xuất thành *Implementation Plan* chờ bạn duyệt.

### B. Tự chủ, Ủy thác & Đa tác tử

- **`/goal <objective>`**
  - **Chức năng:** Bật **Goal Mode**. Mỗi khi agent định kết thúc lượt trước khi hoàn thành, *goal stop hook* sẽ chặn lại, hiển thị thời gian đã chạy + số lần tiếp tục + yêu cầu gốc, ép agent lập checklist và đối chiếu từng mục với output thật (test, build, file). Kết thúc bằng `<!-- GOAL_COMPLETE -->` hoặc hủy khi bạn nhắn yêu cầu dừng (`<!-- GOAL_CANCELLED -->`).
  - **Lưu ý:** Chỉ có **1 goal active** tại một thời điểm trong 1 hội thoại (gõ `/goal` mới sẽ hủy cái cũ). Không thay đổi quyền tool (`/permissions`) hay `artifactReviewPolicy`. Luôn viết tiêu chí hoàn thành đo được (lệnh test nào phải pass, file nào phải có).
- **`/boost <task>`** *(Paid plans)*
  - **Chức năng:** Kích hoạt pipeline 3 pha (`DeepCoder` / `DeepInvestigator`): Worker triển khai/điều tra → Improvement workers chủ động tìm lỗ hổng, phá case biên và chạy test → Orchestrator kiểm chứng lại.
  - **Dùng khi:** Bài toán **khó về chiều sâu** (deadlock, race condition, memory leak, tối ưu thuật toán, refactor rối) mà 1 lượt code thông thường dễ sót.
- **`/swarm <task>`** & **`/swarm board`** *(All plans)*
  - **Chức năng:** Tạo đội agent có tên riêng (`@worker`, `@verifier`) phối hợp trên một **message board chung**. Có thể chỉ định mỗi worker phụ trách 1 file/package hoặc chạy trên worktree riêng, và ép `@verifier` dùng model khác để review chéo.
  - **Điều khiển:** `/swarm board` (hoặc `Alt+S`) mở toàn màn hình bảng trao đổi; `Alt+X` ẩn thanh trạng thái khi swarm đã xong.
- **`/teamwork <goal>`** *(Paid plans)*
  - **Chức năng:** Đội đa tác tử quy mô lớn cho dự án kéo dài nhiều giờ/ngày. Gồm 2 pha: phỏng vấn scoping (chọn integrity mode `development` / `demo` / `benchmark`) → thực thi tự chủ trong thư mục riêng `~/teamwork_projects/{PROJECT_NAME}` với các cổng kiểm duyệt `Critic`, `Challenger`, `Auditor`, `Success Auditor`.
- **`/run-workflow <task>`** *(All plans)*
  - **Chức năng:** Agent đọc skill `run-workflow`, sinh script Python dùng `phase()`, `parallel()`, `pipeline()`, `agent(prompt, schema, model, type_name, workspace)` và trình bạn duyệt trước khi chạy nền. Hỗ trợ tái sử dụng file `.py` có sẵn (`/run-workflow Run scripts/check.py`).
  - **Dùng khi:** Cần kiểm soát luồng chạy chặt chẽ (ví dụ: quét N file song song trả JSON Schema chuẩn, hoặc pipeline viết test fail rồi mới sửa code) và giữ sạch context hội thoại chính.
- **`/browser <task>`**
  - **Chức năng:** Ủy thác cho `browser` subagent thông qua Chrome DevTools MCP (`chrome-devtools-mcp` qua `npx`). Hỗ trợ điều hướng, click/type/upload, chụp screenshot, đọc console/network, đo performance trace, Lighthouse, evaluate JS, quay video MP4 (`v1.5.9+`).
  - **Điều kiện trên CLI:** Máy local phải cài Node.js (`npx` trên `PATH`) và đang mở **Google Chrome `v144+`** đã bật `chrome://inspect/#remote-debugging` (nhấn **Allow** trong 60s khi kết nối). Không hỗ trợ gắn từ phiên SSH/Dev Container về Chrome ở máy client (chỉ gắn Chrome trên cùng máy chạy `agy`).
- **`/schedule <when> <task>`**
  - **Chức năng:** Tạo one-shot timer (`DurationSeconds`, hỗ trợ `TimerCondition` để hủy sớm khi subagent/task báo xong) hoặc recurring cron (`CronExpression` 5 trường, `MaxIterations`, `IsDaemon`) ngay trong phiên chat.
  - **Dùng khi:** Đợi CI chạy xong rồi báo lại, poll trạng thái deploy mỗi 2 phút trong 30 phút, nhắc kiểm tra tiến độ trong `/goal`.

### C. Hỏi nhanh, Tìm kiếm & Trợ giúp

- **`/btw <query>`**
  - **Chức năng:** Mở `/btw` card phía trên ô nhập lệnh, tạo fork read-only từ lịch sử hiện tại để trả lời câu hỏi phụ trong lúc agent chính vẫn đang chạy (có thể đọc file, search code).
  - **Lưu ý trên CLI:** Mỗi lần chỉ chạy 1 `/btw` card, không hỏi nối tiếp trong cùng card, và các tool cần hỏi quyền (chưa có allow rule như `command(grep)`) sẽ bị **tự động từ chối** trên card. Gõ `/btw` không tham số để mở lại card gần nhất; dùng `←`/`→` để lướt lại các câu đã hỏi, `Tab` để mở rộng, `/copy btw` để chép đáp án.
- **`/codesearch <query>`** *(Aliases: `/cs`, `/search`)*
  - **Chức năng:** Mở panel tìm kiếm code toàn màn hình trong workspace, nhóm kết quả theo file, không làm gián đoạn agent.
  - **Cú pháp:** Mặc định là regex smart-case; thêm `-F` / `--literal` để tìm chuỗi nguyên văn; `f:<glob>` (hoặc `file:`, `path:`) để lọc file; `-f:<glob>` để loại trừ.
  - **Tương tác:** `Enter` mở file tại dòng khớp; `Ctrl+G` mở trong editor ngoài; bên trong file viewer nhấn `C` để viết comment gắn thẳng vào dòng code, rồi `Esc` → `Y` để gửi `<file>:<line>: <comment>` cho agent xử lý.
- **`/voice [live|dictate]`** & **`/record`**
  - **Chức năng:** `/voice live` (`F6`) nói chuyện 2 chiều với agent; `/voice dictate` / `/record` (`F5`) đọc thành văn bản (speech-to-text) vào thẳng ô nhập lệnh để bạn sửa rồi mới bấm gửi. Trên SSH có thể dùng kèm `agy mic-serve` ở máy local. *(Lưu ý: cần phiên đăng nhập có quyền mic/dictation; nếu lỗi hãy `/logout` đăng nhập lại 1 lần).*
- **`/antigravity-guide [question]`**
  - **Chức năng:** Nạp tài liệu chính thức của Antigravity (và fetch `.md` từ `antigravity.google/docs` nếu cần) để trả lời mọi thắc mắc cách dùng CLI/App/IDE/SDK ngay trong chat.
- **`/help`**
  - **Chức năng:** Mở bảng tra cứu nhanh danh sách lệnh và phím tắt trong TUI.

### D. Quản lý Context, Diff & Hội thoại

- **`/diff`**
  - **Chức năng:** Mở trình xem diff toàn màn hình với 3 tab (`←`/`→` hoặc `Tab` để đổi): **All Changes** (Git/Hg/JJ, cả untracked), **Per Turn** (thay đổi theo từng lượt agent), **Commit Tree** (cây commit).
  - **Mẹo review:** Trong Detail View nhấn `F` để chuyển giữa xem diff và xem toàn bộ file; nhấn `N`/`Shift+N` nhảy giữa các hunk; nhấn `C` để comment vào dòng code, `D` để xóa comment, thoát ra nhấn `Y` để gửi toàn bộ comment thành prompt chỉ đạo agent sửa tiếp.
- **`/compact [message]`**
  - **Chức năng:** Chủ động tóm tắt hội thoại thành checkpoint để giải phóng context window. Gõ `/compact` để nén và dừng chờ bạn nhập tiếp; gõ `/compact <chỉ dẫn>` để nén (ưu tiên giữ phần bạn dặn) rồi chạy tiếp luôn trong cùng lượt. Có thể bấm `Esc` / `Ctrl+C` để hủy giữa chừng.
- **`/context`**
  - **Chức năng:** Hiển thị lưới phần trăm context window đang dùng, phân bổ token theo từng nhóm (`User messages`, `Agent responses`, `Tool calls`, `System prompt/tools`, `Rules`, `Skills`, `MCP tools`, `Checkpoint buffer`) và danh sách file đang được nạp. Rất hữu ích để phát hiện MCP server nào đang ngốn nhiều schema token nhất rồi tắt bớt bằng `/mcp`.
- **`/resume`** *(Aliases: `/switch`, `/conversation`)*
  - **Chức năng:** Mở danh sách hội thoại cũ (gõ để lọc theo tiêu đề/ID, `←`/`→` chuyển trang, `F2` đổi tên, `F4` xóa, `Tab` sang tab **Other** để import hội thoại từ Antigravity App).
- **`/fork`** *(Alias: `/branch`)*
  - **Chức năng:** Nhân bản hội thoại hiện tại sang một session song song mới từ thời điểm hiện tại.
- **`/rewind`** *(Alias: `/undo`)*
  - **Chức năng:** Lùi lịch sử hội thoại về một message trước đó khi agent đi sai hướng.
- **`/clear`** *(Alias: `/new`)*
  - **Chức năng:** Xóa màn hình và reset ngữ cảnh hội thoại để bắt đầu tác vụ mới.
- **`/rename <name>`**
  - **Chức năng:** Đặt lại tên cho thread hiện tại (giúp dễ tìm trong `/resume` và hiển thị ở `conversation_title`).
- **`/copy [n|btw]`**
  - **Chức năng:** Chép phản hồi gần nhất của agent (hoặc phản hồi thứ `n`, hoặc kết quả `/btw` mới nhất với `/copy btw`) vào clipboard.
- **`/artifact`**
  - **Chức năng:** Mở bảng *Artifact Review* để xem/duyệt các artifact (plan, walkthrough, file…).

### E. Giám sát Subagent, Task & Workspace

- **`/agents`**
  - **Chức năng:** Mở *Agent Manager* gồm 2 phần: (1) chọn/chuyển custom agent (nếu đang giữa hội thoại, việc chuyển agent sẽ tự fork sang session mới); (2) theo dõi các subagent nền (`running`, `done`, `error`, `killed`), nhấn `Enter` xem thought/stdout, `A`/`D` duyệt nhanh tool call của subagent, hoặc `K` để kill subagent đang chạy.
- **`/tasks`**
  - **Chức năng:** Mở *Task Manager* để xem log các lệnh shell chạy nền, workflow và timer/cron của `/schedule` (`K` để kill, `X` để dọn task đã xong, `Enter` xem chi tiết).
- **`/add-dir <path>`**
  - **Chức năng:** Gắn thêm thư mục bên ngoài vào workspace hiện tại của phiên.
- **`/open <path>`**
  - **Chức năng:** Mở file/đường dẫn bằng trình soạn thảo mặc định của hệ điều hành.
- **`/remote-control [on|off]`**
  - **Chức năng:** Bật/tắt kết nối Remote Control cho phiên terminal đang mở.
- **`/feedback`** & **`/exit`** *(Alias: `/quit`)*
  - **Chức năng:** Gửi phản hồi sản phẩm hoặc thoát TUI `agy` (phím tắt `Ctrl+D` khi ô nhập trống).

### F. Tùy biến Agent (Customizations)

- **`/learn [instruction]`**
  - **Chức năng:** Phân tích các lần bạn chỉnh sửa agent trong phiên (hoặc theo chỉ dẫn cụ thể), phân loại thành **Rule** (ràng buộc ngắn luôn nhớ) hay **Skill** (quy trình nhiều bước), ưu tiên cập nhật file có sẵn và luôn tạo `learning_proposal.md` cho bạn duyệt trước khi ghi vào `.agents/` hoặc `~/.gemini/`.
- **`/agy-customizations [request]`**
  - **Chức năng:** Nạp tài liệu chuẩn về Rules, Skills, Plugins, Hooks, MCP Servers, `skills.json`/`plugins.json` để agent tạo mới hoặc sửa lỗi customization đúng chuẩn.
- **`/skills [reload]`**
  - **Chức năng:** Duyệt danh sách các Agent Skills local và global đang nạp; chạy `/skills reload` để nạp lại skill mới sửa từ đĩa mà không cần khởi động lại CLI.
- **`/hooks`**
  - **Chức năng:** Xem các lifecycle hook (`PreToolUse`, `Stop`, `PreInvocation`, `PostInvocation`…) đang đăng ký.
- **`/mcp`**
  - **Chức năng:** Mở trình quản lý MCP server để xem trạng thái kết nối, số lượng tool hoặc bật/tắt server cho gọn context.
- **`/plugin [list|install|uninstall|enable|disable]`** *(Alias: `/plugins`)*
  - **Chức năng:** Mở Marketplace / quản lý plugin đóng gói sẵn (skills, MCP, subagents, rules, hooks).
- **`/advisor [inherit|flash_lite|flash|pro|<model-id>|on|off|status]`** *(Custom skill của bộ cài `setup-agent-code`)*
  - **Chức năng:** Cấu hình model hoặc bật/tắt Stop hook `review-gate` (lưu tại `~/.gemini/antigravity-cli/review-gate.json`).

### G. Cấu hình CLI, Model & Tài khoản

- **`/model [model] [prompt]`**
  - **Chức năng:** Mở bảng chọn model mặc định (lưu vào `settings.json`). Nếu truyền `/model <model> <prompt>` thì chạy **duy nhất prompt đó** trên `<model>` mà không làm đổi model mặc định.
- **`/effort [low|medium|high|xhigh|max]`**
  - **Chức năng:** Điều chỉnh mức ngân sách suy luận (thinking effort) của model hiện tại (lưu làm mặc định cho các phiên sau). Không dùng được với model có effort cố định như `Orchestrator`.
- **`/config`** *(Alias: `/settings`)*
  - **Chức năng:** Mở giao diện chỉnh `settings.json` (theme, `agentMode`, `toolPermission`, `verbosity`, `altScreenMode`, `notifications`, `hideActiveItems`…).
- **`/permissions`**
  - **Chức năng:** Quản lý danh sách rule `allowlist` / `denylist` / `asklist` theo 3 scope (**Project**, **Shared**, **Global**) với cú pháp `action(target)` như `command(git)`, `read_file(...)`.
- **`/keybindings`**
  - **Chức năng:** Mở trình chỉnh sửa phím tắt TUI.
- **`/statusline [on|off|enable|disable|delete|reset|help|<cmd>]`**
  - **Chức năng:** Bật/tắt thanh trạng thái, gán script tùy biến (như `hud.mjs`), hoặc `delete`/`reset` về mặc định của CLI.
- **`/title [on|off]`**
  - **Chức năng:** Bật/tắt cập nhật tiêu đề cửa sổ terminal động (hiển thị model, workspace, trạng thái agent).
- **`/usage`** *(Alias: `/quota`)* & **`/credits`**
  - **Chức năng:** `/usage` làm mới và hiển thị quota theo nhóm model (giới hạn 5 giờ và theo tuần); `/credits` xem số dư AI Premium credits.
- **`/changelog`** & **`/logout`**
  - **Chức năng:** `/changelog` xem release notes của `agy` (cache tại `~/.gemini/antigravity-cli/cache/CHANGELOG.md`); `/logout` đăng xuất và xóa token khỏi keyring.

> [!NOTE]
> **Các lệnh chỉ có trên Antigravity App (KHÔNG có trên CLI `agy`):**
> - `/automation`: Quản lý cron sidecar chạy nền độc lập ở tab Automations (trên CLI dùng `/schedule` cho tác vụ theo phiên, hoặc tạo `sidecar.json` theo `/agy-customizations`).
> - `/generative_ui`: Sinh widget HTML tương tác inline/side-panel (CLI không render được HTML widget).
> - `/mcp-app-development`: Hướng dẫn dựng MCP App có giao diện `ui://` (CLI không render được `ui://`).

---

## 3. Chế Độ Thực Thi (Execution Modes) & Phím Tắt TUI Cốt Lõi

### 3.1. Execution Modes (`Shift+Tab` để xoay vòng hoặc `--mode` khi khởi chạy)

| Chế độ | Hành vi duyệt sửa file & chạy lệnh | Khi nào nên chọn |
|---|---|---|
| `default` | Hỏi xác nhận diff trước khi sửa/tạo file; hỏi trước khi chạy lệnh terminal | Code nhạy cảm, refactor rủi ro, muốn soi từng diff |
| `accept-edits` | Tự động duyệt tạo/sửa file trong workspace (kể cả subagent), vẫn hỏi trước khi chạy shell command | Lặp nhanh trên code tin cậy nhưng vẫn muốn kiểm soát lệnh terminal |
| `auto` | Tự duyệt sửa file + chạy terminal trong OS sandbox mặc định; lệnh ngoài sandbox được tự đánh giá an toàn (lệnh nguy hiểm/bất khả nghịch vẫn hỏi). *Cần sandbox OS (`Win11 24H2+` / macOS / Linux) và tài khoản cá nhân* | Tối ưu cho `/goal` hoặc tác vụ tự chủ dài mà không phải bấm `y` liên tục |
| `plan` | Tự gắn tiền tố `/plan` để phân tích và lập kế hoạch trước khi đụng code | Bắt đầu feature lớn hoặc khám phá codebase lạ |

### 3.2. Phím tắt TUI quan trọng nhất

| Phím | Tác dụng |
|---|---|
| `Esc` / `Ctrl+C` | Ngắt lượt agent đang chạy hoặc đóng panel đang mở (`Ctrl+C` 2 lần khi rảnh để thoát) |
| `Shift+Tab` | Đổi nhanh Execution Mode (`default` → `accept-edits` → `auto` → `plan`) |
| `Ctrl+O` | Mở rộng / thu gọn chi tiết tool calls, suy luận và cây phase của `/run-workflow` |
| `Ctrl+R` | Mở nhanh bảng Artifact Review (`/artifact`) |
| `Ctrl+G` | Mở prompt đang gõ (hoặc file trong `/codesearch`) bằng trình soạn thảo ngoài (`$EDITOR`) |
| `Ctrl+V` | Dán ảnh/screenshot từ clipboard thẳng vào prompt để debug UI |
| `Alt+J` | Nhảy thẳng tới subagent đang chờ bạn duyệt quyền |
| `Ctrl+K` | Duyệt nhanh yêu cầu đang chờ của subagent ngay từ màn hình chính |
| `Alt+S` / `Alt+X` | Mở toàn màn hình `/swarm board` / Ẩn thanh trạng thái swarm đã xong |
| `F5` / `F6` | Bật/tắt đọc giọng nói vào ô prompt (`F5`) / Hội thoại voice 2 chiều (`F6`) |
| `@` | Autocomplete đính kèm file/thư mục/agent vào prompt |

---

## 4. CLI Subcommands & Startup Flags (Chạy Từ Terminal / Script / CI)

### 4.1. Toàn bộ Subcommands của `agy`

| Lệnh | Chức năng | Ví dụ / Khi nào dùng |
|---|---|---|
| `agy` | Mở giao diện TUI tương tác | Làm việc hàng ngày |
| `agy models` | Liệt kê tất cả model ID hợp lệ trên tài khoản | Tra exact model ID cho `--model` hoặc `/advisor <model-id>` |
| `agy agent` / `agy agents` | Liệt kê các custom agent khả dụng | Tra tên cho `--agent <name>` |
| `agy changelog` | In release notes ra stdout (không tốn model quota) | Kiểm tra tính năng mới sau khi update |
| `agy mcp <add\|remove\|list\|enable\|disable>` | Quản lý cấu hình MCP server từ shell | Script hóa cài đặt MCP không cần mở TUI |
| `agy plugin <list\|import\|install\|uninstall\|enable\|disable\|validate\|link>` | Quản lý plugin, import từ `gemini`/`claude`, kiểm tra manifest plugin | Phát triển & cài plugin từ terminal |
| `agy install [--dir\|--skip-aliases\|--skip-path]` | Cấu hình `PATH` và shell cho `agy` | Thiết lập môi trường sau khi cài binary |
| `agy update` | Cập nhật `agy` lên phiên bản mới nhất | Bảo trì CLI |
| `agy acp [flags]` | Khởi chạy Agent Client Protocol (stdio JSON-RPC) | Tích hợp vào editor/IDE khác (như Zed) hỗ trợ ACP |
| `agy remote-control <start\|status\|stop>` | Quản lý daemon Remote Control | Điều khiển phiên CLI từ xa |
| `agy mic-serve [--addr 127.0.0.1:4713]` | Chia sẻ microphone local qua loopback cho `agy` chạy trên host SSH khác | Dùng `/voice` khi code qua SSH |

### 4.2. Startup Flags & Headless Mode (`-p` / `--print`)

- **Phiên & Chế độ:**
  - `-c` / `--continue`: Tiếp tục hội thoại gần nhất của thư mục hiện tại (đọc từ `~/.gemini/antigravity-cli/cache/last_conversations.json`).
  - `--conversation <id>` (hoặc `-r`, `--resume`): Mở lại đúng hội thoại theo ID.
  - `-i` / `--prompt-interactive "<prompt>"`: Gửi prompt mở đầu rồi giữ nguyên phiên TUI để chat tiếp.
  - `--mode <accept-edits|auto|plan>`, `--model <id>`, `--effort <level>`, `--agent <name>`, `--add-dir <dir>`.
- **Headless / Scripting / CI:**
  - `-p` / `--print` / `--prompt "<prompt>"`: Chạy 1 lượt non-interactive và in kết quả ra `stdout`.
  - `--input-format <text|stream-json>` & `--output-format <text|json|stream-json>`: Giao tiếp NDJSON (chính là cơ chế `review-gate.mjs --run` đang dùng).
  - `--json-schema <json|path>`: Ép output đầu ra tuân thủ đúng JSON Schema.
  - `--print-timeout <duration>`: Giới hạn thời gian chạy headless (`0s` = chờ đến khi xong).
  - `--disable-slash-commands`: Gửi nguyên văn chuỗi bắt đầu bằng `/` mà không kích hoạt slash command/skill.
- **Bảo mật & Remote:**
  - `--sandbox`: Bật terminal sandbox ở mức OS.
  - `--dangerously-skip-permissions`: Tự động duyệt mọi yêu cầu quyền (chỉ dùng trong môi trường cô lập/CI).
  - `--remote-control`, `--remote-agent`, `--project <id|name>`, `--new-project`, `--log-file <path>`.

**Ví dụ thực tế:**

```bash
# 1. Review git diff không cần mở TUI
agy -p "Review git diff hiện tại, chỉ báo bug thật" --model gemini-4-neon-medium --effort medium

# 2. Nén hội thoại gần nhất rồi chạy tiếp headless
agy -c -p "/compact Giữ lại kết quả điều tra auth, giờ viết unit test"

# 3. Chạy CI ép trả về JSON theo schema
agy -p "Kiểm tra các file vừa sửa" --json-schema ./schema.json --output-format json --print-timeout 120s
```

---

## 5. Playbooks Phối Hợp Lệnh Thực Chiến

1. **Làm feature lớn, ít sửa lại:**
   `/grill-me <mô tả ngắn>` → chốt thiết kế → `/plan` (hoặc gộp `/plan /grill-me <task>`) → duyệt plan → chuyển sang `/goal Hãy thực hiện đúng plan đã duyệt và verify toàn bộ test pass`.
2. **Săn bug khó hoặc race condition:**
   `/boost <triệu chứng + cách tái hiện>` → dùng `/diff` (chế độ *Per Turn*) kiểm tra từng bước sửa → comment sửa nhỏ trực tiếp bằng phím `C`.
3. **Sửa hàng loạt nhiều file / nhiều package độc lập:**
   - Nếu các worker cần trao đổi chéo hoặc cần `@verifier` review diff tổng thể → `/swarm <chia rõ scope từng file + yêu cầu verifier>`.
   - Nếu chỉ chạy cùng 1 thao tác kiểm tra/audit lặp lại trên danh sách file và muốn gom kết quả JSON sạch → `/run-workflow <mô tả các phase>`.
4. **Giữ phiên làm việc dài luôn nhanh & thông minh:**
   Kiểm tra `/context` định kỳ → hỏi chi tiết vặt bằng `/btw` → sau mỗi milestone gõ `/compact <mục tiêu tiếp theo>` → khi muốn thử hướng mạo hiểm gõ `/fork` → kết thúc phiên chạy `/learn` để lưu lại quy tắc vừa rút ra.
5. **Kiểm thử giao diện & theo dõi tác vụ dài:**
   Mở Chrome bật remote debugging → `/browser <kịch bản test UI>` → song song đó đặt `/schedule every 3 minutes check CI status` → theo dõi tất cả ở `/tasks` và `/agents`.

---

## 6. Phụ Lục: `/statusline` & Dữ Liệu JSON Của HUD (`hud.mjs`)

- **Cách cấu hình trong `~/.gemini/antigravity-cli/settings.json`:**
  ```json
  {
    "statusLine": {
      "type": "command",
      "command": "node C:/Users/ThanhPK/.gemini/antigravity-cli/hud/hud.mjs",
      "enabled": true,
      "padding": 0,
      "stack_with_default": false
    }
  }
  ```
- **Giới hạn vận hành của `agy`:** CLI gọi script tối đa **1 lần mỗi 300 ms**, timeout cứng **5 giây** mỗi lần chạy; nếu fail **30 lần liên tiếp**, CLI tạm tắt statusline cho hết phiên (khôi phục bằng `/statusline enable`).
- **Các trường JSON `agy` gửi vào `stdin` của HUD:**
  `cwd`, `session_id`, `conversation_id`, `conversation_title`, `transcript_path`, `model` (`id`, `display_name`, `effort`), `workspace` (`current_dir`, `project_dir`), `version`, `context_window` (`total_input_tokens`, `total_output_tokens`, `context_window_size`, `used_percentage`, `remaining_percentage`, `current_usage`), `exceeds_200k_tokens`, `agent` (`name`), `product`, `quota` (map bucket → `remaining_fraction` / `remaining_amount`, `reset_time`, `reset_in_seconds`, `disabled`), `agent_state` (`idle`, `working`, `tool_use`, `reviewing`, `authenticating`, `initializing`, `error`), `vcs` (`type`), `cycle_mode` (`accept-edits`, `auto`, `plan`), `sandbox` (`enabled`), `subagents` (`name`, `role`, `status`), `artifact_count`, `plan_tier`, `email`, `pending_input_count`, `tool_confirmation_pending`, `task_count`, `terminal_width`, `vim` (`mode`), `cost` (`total_usd`, `subagent_usd`, `estimated`).
- **Lưu ý quan trọng về `/goal`:** Payload JSON `stdin` của `agy` **chưa có trường nào cho `/goal`**. Để HUD CLI hiển thị được trạng thái `/goal`, script HUD cần đọc bổ sung từ `transcript_path` (nhận diện marker `/goal is a [Slash Command]:` ở `USER_INPUT` và kết thúc ở `<!-- GOAL_COMPLETE -->` / `<!-- GOAL_CANCELLED -->` kèm file cache trạng thái theo `session_id` để không bị mất khi file log vượt quá 512 KB).
