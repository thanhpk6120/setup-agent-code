# Global Rules

> **[CRITICAL INSTRUCTION: READ TO THE END. DO NOT IGNORE ANY RULE. DO NOT TRUNCATE CODE (NO `...` PLACEHOLDERS). FULL COMPLIANCE REQUIRED.]**
> AI MUST strictly read, preserve, and follow 100% of the rules in this document without exception. NEVER truncate, omit, skip, or summarize away any rule. Output must always be validated against these rules prior to response delivery.
> **QUY TẮC TIÊN QUYẾT Ở ĐẦU (MANDATORY PREREQUISITE):** TẤT CẢ các lệnh xoá file/thư mục BẮT BUỘC phải dùng cách di chuyển nó vào thùng rác (Trash / Recycle Bin), TUYỆT ĐỐI KHÔNG ĐƯỢC xoá luôn/xóa vĩnh viễn.

## 0. PRECEDENCE, DELEGATION, SKILLS & PLUGINS/MCP [MANDATORY PRE-FLIGHT — NEVER SKIP]
- **PRECEDENCE RULE:** Main Agent là người thực thi chính (Default: Direct Execution). KHÔNG lạm dụng spawn subagent cho các tác vụ thông thường, tuần tự hoặc các chỉnh sửa có phạm vi rõ ràng. Chỉ spawn subagent khi gặp các tác vụ ĐẶC THÙ / CHUYÊN BIỆT thực sự cần thiết (ví dụ: song song hoá nhiều nhánh độc lập, chạy test/gate review độc lập, phân tích diện rộng nhiều repository/service, hoặc khi người dùng yêu cầu rõ ràng).
- **OUTPUT PREFIX (MANDATORY BEFORE ANY TOOL CALL):**
  The Main Agent MUST output a reasoning line before calling ANY tool:
  `[Pre-flight] Tier: 1/2/3 | Skills: <Skill name(s) or None> | Plugins/MCP: <Plugin/MCP tool(s) or None> | Rationale: <reason> | Action: <Direct / Single Subagent / Parallel Subagents>`
- **Mandatory Skills Resolution:** Scan and apply matching skills from `skills/*/SKILL.md` (e.g. `create-plan`, `implement-task`, `init-docs`, `delivery`, `security-review`, `sql-*`, `java-*`, `poka-yoke`...). Never invent ad-hoc procedures when an established skill exists.
- **Mandatory Plugins / MCP Tools Resolution:** Route domain-specific requests to specialized MCP tools instead of manual CLI/bash/grep. Luôn ưu tiên dùng các MCP server hiện có trong hệ thống (ví dụ: công cụ chuyên dụng cho code graph, project memory, browser automation, v.v. - tùy thuộc vào danh sách tools đang được cấp) thay vì tự xử lý bằng các lệnh shell cơ bản.
- **Delegation logic (Nguyên tắc uỷ quyền):**
  - **Mặc định tự thực thi (Direct Execution):** Main Agent trực tiếp đọc, kiểm tra, sửa code và chạy lệnh xác thực cho hầu hết công việc thông thường.
  - **Chỉ spawn Single Subagent:** Khi task đòi hỏi một vai trò chuyên biệt sâu (ví dụ: review bảo mật chuyên sâu `security-reviewer`, duyệt tài liệu spec `docs-reviewer`), hoặc khi cần môi trường cô lập để test không gây ảnh hưởng.
  - **Chỉ spawn Parallel Subagents:** Khi có nhiều lát cắt công việc HOÀN TOÀN ĐỘC LẬP trên các module/service khác nhau cần thực hiện đồng thời để tiết kiệm thời gian, hoặc điều tra đa nhánh phức tạp. TUYỆT ĐỐI KHÔNG spawn nhiều subagent cho các chỉnh sửa đơn giản hoặc các bước tuần tự phụ thuộc lẫn nhau.

## 1. Global Rules
- Always respond in Vietnamese (except code identifiers, error strings, shell commands, URLs).
- Never commit, branch, or open PRs unless explicitly requested.
- **QUY TẮC TIÊN QUYẾT (MANDATORY):** TẤT CẢ các lệnh xoá file/thư mục BẮT BUỘC phải dùng cách di chuyển nó vào thùng rác, KHÔNG ĐƯỢC xoá luôn. Never permanently delete user files. Clean temporary files only by moving them to the Recycle Bin / Trash.
- Create/update files only in the current workspace; ask before editing outside it.
- Do not stop or downgrade scope/model/agents solely for cost warnings. Continue when technically possible; report platform blocks.
- Disclose failed commands/tests and incomplete verification. Never claim unverified success.
- Do not refactor, reformat, or improve unrelated code. Match project style.
- Every changed line must trace directly to the user's request.
- MANDATORY RULE COMPLIANCE: AI MUST strictly follow ALL rules in AGENTS.md and RULES.md without exception. NEVER skip, omit, or downgrade any rule. ALWAYS verify final output against every applicable rule for compliance before responding.

## 2. MCP Routing & Strict Enforcement
- **Strict OUTPUT PREFIX Verification:** You MUST NEVER issue a tool call without first outputting the `[Pre-flight]` prefix. If you generate a tool call without this prefix, you have violated a core directive.
- **MCP Route & Priority (Hard Constraints):** BẮT BUỘC ưu tiên dùng các MCP tools chuyên dụng tương ứng với domain của task (ví dụ: dùng MCP tool về code graph thay vì `grep`, dùng MCP tool về browser thay vì `curl`/`wget`, dùng MCP tool về database/memory thay vì tra cứu file thủ công). **CẤM** lạm dụng `bash` (grep, find, awk, curl) hoặc native tools khi trong danh sách công cụ đã có MCP tool phục vụ chức năng đó.
- **Fallback Rule:** Chỉ được dùng bash/native tools khi MCP tool tương ứng báo lỗi không khả dụng (connection refused, not configured) HOẶC user rõ ràng yêu cầu dùng bash. Trừ khi đó, lạm dụng bash/grep thay cho MCP là vi phạm nghiêm trọng.
