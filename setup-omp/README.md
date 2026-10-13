# setup-omp

Script bootstrap thiết lập môi trường và cấu hình `.omp` (`mcp.json`, `models.yml`, `config.yml`) cho máy mới, bám sát tài liệu chính thức của từng nhà cung cấp MCP. Default AI Base URL sử dụng `http://localhost:20128/v1`.

## Danh sách MCP Servers & Tài liệu chính thức

1. **gitnexus**: Tài liệu [GitNexus Windows MCP](https://github.com/abhigyanpatwari/GitNexus)
   - Bootstrap cài global (`npm i -g gitnexus`) rồi dùng đường dẫn tuyệt đối `cmd /c <abs-path>\gitnexus mcp` để tối ưu thời gian khởi động.
   - Yêu cầu Node.js >= 22.18.0. Quá trình bootstrap sẽ tự kiểm tra và báo lỗi nếu chưa đáp ứng hoặc cài lỗi thiếu file.
   - Index trống (`list_repos total=0`) thì chạy: `gitnexus analyze`
2. **company-atlassian**: Tài liệu [mcp-atlassian Installation](https://mcp-atlassian.soomiles.com/docs/installation)
   - Quản lý cài đặt/cập nhật qua `uv`: `uv tool install mcp-atlassian==0.23.1 --upgrade`
   - Lệnh chạy trực tiếp: `mcp-atlassian` (không dùng `uvx --from`)
   - Biến môi trường: `JIRA_URL`, `JIRA_PERSONAL_TOKEN`, `CONFLUENCE_URL`, `CONFLUENCE_PERSONAL_TOKEN`, `TOOLSETS`
3. **context7**: Tài liệu [Upstash Context7 MCP](https://github.com/upstash/context7)
   - Bootstrap cài global (`npm i -g @upstash/context7-mcp`), dùng lệnh `node <npm-root>/@upstash/context7-mcp/dist/index.js`
   - Yêu cầu Node.js >= 22.18.0.
   - Biến môi trường (optional, tăng rate limit): `CONTEXT7_API_KEY` — không có thì chạy anonymous, bootstrap tự bỏ block `env`
4. **cloakbrowser**: Trình duyệt ẩn danh
   - Hỗ trợ quét danh sách ổ đĩa và cho phép chọn vị trí lưu trữ (mặc định D:, C:).
   - Tự động kiểm tra và bảo toàn dữ liệu profile cũ nếu thư mục nguồn và mã nguồn đã tồn tại.
5. **memorix** (Tùy chọn / Optional): Tài liệu [AVIDS2/memorix](https://github.com/AVIDS2/memorix)
   - Cung cấp tính năng Session Memory & MCP server cho OMP (`memorix serve --mode lite`).
   - Mặc định **không cài đặt** khi bootstrap nếu chưa có trên máy (người dùng có thể chọn cài đặt theo nhu cầu). Nếu hệ thống đã có sẵn Memorix trong PATH, script sẽ tự động nhận diện và cập nhật lên phiên bản mới nhất.
> Ghi chú: `mcp.json` không còn trường `$schema` vì URL schema cũ trả 404.
## Trash Guard (Hook Chặn Xóa Cứng)

Hệ thống triển khai cơ chế **Trash Guard** để ngăn chặn hoàn toàn việc xóa vĩnh viễn (xóa cứng) tệp tin và thư mục ngoài ý muốn. Mọi thao tác xóa đều bắt buộc phải chuyển vào Recycle Bin (Thùng rác). 

**Cơ chế bảo vệ cho OMP:**
- **OMP (Oh-My-Pi / Orca OMP):** Cài đặt tự động extension `no-hard-delete.ts` vào thư mục `extensions/` của OMP để chặn các lệnh xóa cứng (`rm`, `Remove-Item`, `del`, `rmdir`...) phát ra từ Bash/PowerShell trong quá trình thực thi tool.
**Hướng dẫn sử dụng:**
- **TUYỆT ĐỐI KHÔNG SỬ DỤNG:** `rm`, `del`, `Remove-Item` hoặc `rmdir`.
- **HÃY SỬ DỤNG:** Lệnh `trash <path>` để chuyển tệp/thư mục vào Recycle Bin một cách an toàn.

> **Quy tắc tiên quyết (MANDATORY):** TẤT CẢ các lệnh xóa file/thư mục BẮT BUỘC phải dùng cách di chuyển nó vào thùng rác (Trash / Recycle Bin). Tuyệt đối không được xóa luôn/xóa vĩnh viễn dưới mọi hình thức.

## Cài đặt nhanh (1 dòng lệnh duy nhất)

Mở PowerShell trên máy mới và chạy trực tiếp lệnh duy nhất sau:

```powershell
irm https://raw.githubusercontent.com/thanhpk6120/setup-omp/main/install.ps1 | iex
```

### Quy trình cài đặt tương tác (Interactive Setup Flow)

Script cài đặt sẽ tự động điều phối toàn bộ quá trình:

1. **Kiểm tra và cài đặt OMP CLI**:
   - Tự động kiểm tra binary `omp` trong biến môi trường `PATH`.
   - Nếu chưa cài đặt, script sẽ hỏi:
     `OMP CLI chưa được cài đặt. Bạn có muốn cài đặt OMP chính gốc ngay bây giờ không? [Y/n]: `
   - Khi xác nhận (nhấn Enter hoặc 'Y'), script tự động tải và cài đặt OMP chính gốc qua `https://omp.sh/install.ps1` (`-Binary`), đồng thời cập nhật ngay `PATH` cho session hiện tại.

2. **Cấu hình kết nối AI Provider**:
   - Hỏi **AI Base URL** (Mặc định: `http://localhost:20128/v1`): Chỉ cần nhấn Enter để dùng giá trị mặc định, hoặc nhập URL proxy/gateway mong muốn.
   - Hỏi **AI API Key** (Bắt buộc): Người dùng bắt buộc phải nhập AI API Key khi được hỏi (không có giá trị mặc định, không được để trống).
   - Script tự động thiết lập biến môi trường và nạp vào quá trình khởi tạo cấu hình.

3. **Quản lý ghi đè và hợp nhất cấu hình (Overwrite / Merge / Skip)**:
   - Tự động quét các file cấu hình hiện có (`config.yml`, `models.yml`, `mcp.json`).
   - Nếu file đã tồn tại:
     * Đối với `mcp.json`: Script hỗ trợ xác nhận `[O]verwrite / [M]erge / [S]kip` (Merge giúp gộp các MCP server mới vào cấu hình cũ mà không làm mất cấu hình sẵn có).
     * Đối với file YAML (`config.yml`, `models.yml`): Script hỗ trợ xác nhận `[O]verwrite / [S]kip`.
   - Tự động tạo file sao lưu `.bak` trước khi thực hiện ghi đè hoặc hợp nhất.
   - Các file quy tắc hệ thống (`AGENTS.md`, `RULES.md`, `SYSTEM.md`) và thư mục `skills/` luôn được đồng bộ cập nhật mới nhất.

4. **Tùy chọn cài đặt Memorix (MCP & Session Memory)**:
   - **Tự động nhận diện**: Nếu hệ thống đã có sẵn Memorix trong PATH, script sẽ tự động nhận diện và cập nhật lên phiên bản mới nhất mà không cần hỏi lại.
   - **Nếu chưa có sẵn**: Script sẽ hỏi người dùng có muốn cài đặt Memorix hay không:
     `Bạn có muốn cài đặt Memorix (MCP & Session Memory) không? [y/N]: `
   - **Mặc định là [y/N] (Không cài đặt)**: Nhấn Enter hoặc `N` để bỏ qua hoàn toàn. Hệ thống sẽ giữ môi trường tinh gọn (không cài package npm, không kích hoạt hook OMP, không cấu hình vào `mcp.json`, không cài các skill `skills/memorix-*` vào OMP, và không tích hợp hướng dẫn Memorix vào `AGENTS.md`).
   - **Nếu chọn Yes (`y`/`yes`)**: Hệ thống sẽ tự động cài đặt npm package (`npm install -g memorix`), đăng ký hook OMP (`memorix setup --agent omp --global`), bổ sung server `memorix` vào `mcp.json`, cài đặt toàn bộ skill `skills/memorix-*` vào OMP, và tích hợp tài liệu hướng dẫn Memorix vào `AGENTS.md` của OMP.

5. **Cài đặt công cụ & cấu hình MCP Servers**:
   - Tự động cài đặt và cấu hình đầy đủ các MCP Servers cốt lõi: `gitnexus`, `company-atlassian`, `context7`, `cloakbrowser` (và `memorix` nếu đã chọn Yes ở bước trên).
   - Kích hoạt extension **Trash Guard** để chặn triệt để mọi hành vi xóa cứng/xóa vĩnh viễn dữ liệu.
---
## Hợp đồng hành vi & Nguyên tắc (Contract Updates)

Bộ script tuân thủ 7 hợp đồng nguyên tắc:
1. **Evidence loop**: Không giả định kết quả; mọi thao tác cấu hình và tạo file đều có bước xác thực bằng chứng (evidence) qua test thực tế (`test-bootstrap.ps1`) trước khi kết luận hoàn tất.
2. **MCP generic**: Cấu hình file `mcp.json` theo chuẩn generic mcpServers, loại bỏ schema cũ 404, tách biệt rõ ràng giữa config và runtime args.
3. **Cloakbrowser + chọn ổ**: Hỗ trợ CloakBrowser MCP với tính năng quét danh sách ổ đĩa và cho phép chọn ổ đĩa cài đặt (mặc định D:, C:), bảo toàn mã nguồn và profile cũ nếu đã có.
4. **uv mcp-atlassian**: Quản lý cài đặt/cập nhật `mcp-atlassian` qua `uv tool install mcp-atlassian==0.23.1 --upgrade`, chạy trực tiếp bằng command `mcp-atlassian`.
5. **Overwrite & Merge (Ghi đè và gộp an toàn kèm backup)**: Hỗ trợ xác nhận [O]verwrite / [M]erge / [S]kip cho `mcp.json` và [O]verwrite / [S]kip cho file YAML (`config.yml`, `models.yml`) kèm sao lưu `.bak` tự động; hỗ trợ switch `-Force` hoặc `-OverwriteAll` để ghi đè tự động không cần hỏi; luôn ghi đè (`overwrite`) các file quy tắc (`AGENTS.md`, `RULES.md`, `SYSTEM.md`) và thư mục `skills/` để đồng bộ mới nhất.
6. **Reload-context**: Hỗ trợ workflow tải lại ngữ cảnh (`reload-context` / nạp lại rules, skills, agents) ngay sau khi cấu hình/tool cập nhật mà không cần khởi động lại toàn bộ session.
7. **Cleanup skill**: Đồng bộ thư mục `skills/` giúp dọn dẹp các rule và skill lỗi thời hoặc thừa, giữ hệ sinh thái skill tinh gọn và chuẩn xác.

---

## Chạy thủ công từ repo

### Chạy bootstrap

```powershell
# Chạy cài đặt đầy đủ (yêu cầu Node.js, npm, git)
.\bootstrap.ps1

# Ghi đè toàn bộ cấu hình cũ mà không cần hỏi xác nhận từng file
.\bootstrap.ps1 -Force

# Dry-run xem trước thay đổi (không ghi file)
.\bootstrap.ps1 -DryRun

# Bỏ qua bước cài đặt runtime (chỉ tạo file config)
.\bootstrap.ps1 -SkipInstall
```
## Chạy kiểm tra

```powershell
.\test-bootstrap.ps1
```