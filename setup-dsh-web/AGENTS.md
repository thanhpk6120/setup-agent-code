# Agent Instructions

> **[CRITICAL INSTRUCTION: READ TO THE END. DO NOT IGNORE ANY RULE. DO NOT TRUNCATE CODE (NO `...` PLACEHOLDERS). FULL COMPLIANCE REQUIRED.]**
> AI MUST strictly read, preserve, and follow 100% of the instructions in this document without exception. NEVER truncate, omit, skip, or summarize away any section. Output must always be validated against these instructions prior to response delivery.

## Pre-flight Task Complexity, Skills & Plugin/MCP Assessment [HIGHEST PRIORITY]

**[CRITICAL INVARIANT]** You MUST explicitly analyze the incoming request upfront to determine task complexity, applicable Skills, and applicable Plugins/MCP tools. Decide whether to spawn specialized subagents or use the main agent directly.
- **NGUYÊN TẮC CỐT LÕI:** Main Agent là người thực thi chính (Default: Direct Execution). Hạn chế tối đa việc spawn subagent bừa bãi. CHỈ spawn subagent khi tác vụ có tính chất đặc thù, chuyên biệt, hoặc các nhánh công việc thực sự độc lập cần chạy song song.
- **OUTPUT PREFIX REQUIREMENT:** Before calling ANY tool, you MUST output a one-line classification:
  `[Pre-flight] Tier: 1/2/3 | Skills: <Skill names or None> | Plugins/MCP: <Plugin/MCP names or None> | Rationale: <reason> | Action: <Direct / Single Subagent / Parallel Subagents>`.

### Mandatory Tool & Skill Resolution:
- **Skills (`skills/*/SKILL.md`):** E.g. `create-plan`, `implement-task`, `init-docs`, `delivery`, `security-review`. If a task matches a skill's intent, MUST use it instead of ad-hoc steps.
- **Plugins / MCP Tools:** Luôn kiểm tra danh sách MCP tools đang có trong môi trường để ưu tiên sử dụng đúng công cụ cho domain (ví dụ: công cụ cho code graph/symbol, project memory, browser automation, issue tracking, docs, tra cứu thư viện...). *NEVER use generic `bash`/`grep`/`curl` if a dedicated Plugin/MCP handles the domain.*

Before executing actions or calling tool sequences, classify the incoming task:

1. **Tier 1: Trivial / Direct (Direct Execution by Main Agent)**
   - **Scope:** Chỉnh sửa vài dòng đến vài file trong cùng ngữ cảnh rõ ràng; đọc file; tra cứu CLI/môi trường; giải đáp thắc mắc; các thao tác tuần tự ngắn.
   - **Action:** Main Agent tự thực thi trực tiếp. TUYỆT ĐỐI KHÔNG spawn subagent.

2. **Tier 2: Moderate / Focused Tasks (Direct Execution ưu tiên, Subagent khi ĐẶC THÙ)**
   - **Scope:** Sửa 2–5 file trong cùng module; debug lỗi cục bộ; viết test hoặc tài liệu; refactor phạm vi hẹp.
   - **Action:** Mặc định Main Agent tự làm. Chỉ uỷ quyền (Single Subagent) khi:
     - Cần vai trò chuyên biệt sâu (ví dụ `security-reviewer` quét bảo mật chuyên sâu, `dely-reviewer` kiểm tra cổng chất lượng độc lập).
     - Hoặc cần môi trường test giả lập tách biệt để đảm bảo an toàn tuyệt đối cho máy chủ/môi trường thật.

3. **Tier 3: Complex / Multi-system / Broad Investigations (Subagent khi cần SONG SONG HOÁ)**
   - **Scope:** Tác vụ quy mô lớn, nhiều service/repo độc lập; di chuyển hạ tầng phức tạp; các đợt rà soát toàn bộ hệ thống lớn.
   - **Action:** Main Agent đóng vai trò Điều phối & Tích hợp (Dispatcher & Integrator). Phân rã thành các nhánh ĐỘC LẬP và spawn song song các subagent chuyên trách (`tasks[]`). TUYỆT ĐỐI KHÔNG spawn subagent nếu các bước phụ thuộc tuần tự hoặc nếu Main Agent có thể xử lý trực tiếp hiệu quả hơn.

Default behavioral guidelines for all workspaces.

---

## Think Before Coding

- State key assumptions briefly. Mention multiple interpretations; ask only if ambiguity blocks safe execution.
- For minor ambiguity, state the safest assumption and continue.
- Prefer simpler approaches. Push back on unnecessary complexity, risk, or unrelated work.
- Implement directly and verify fast. Tránh tạo các plan rườm rà khi không cần thiết.

Create/update a task-tracking `.md` inside the workspace only for large, risky, multi-session, dependent multi-step tasks, or work whose progress must survive context loss.

---

## Simplicity & Surgical Changes

Minimum code that solves the request. Touch only what is required. Clean up only your own mess.

- Execute only the request; suggest improvements afterward.
- No unrequested features, abstractions, configurability, or impossible-case error handling.
- Mention unrelated dead code but don't delete it. Remove only code your change made unused.
- If overcomplicated, simplify it.

---

## Goal-Driven Execution

Define success criteria and verify. Do not stop mid-task unless blocked by safety/destructive-risk confirmation, missing permissions, critical missing files, or tool failures. If requirements have minor ambiguities or missing non-critical parameters, choose the safest standard assumption, log it, and proceed to completion. Ask ONLY when the requirement is fundamentally contradictory or blocking safe execution.

---

## Communication

- Don't ask confirmation for obvious non-destructive steps; ask only when ambiguity blocks execution.
- Suggest improvements after completing the request.

---

## Agents, Sub-Agents, and Multi-Agent Orchestration

### Core Invariants
- Main Agent là trung tâm xử lý chính. Không lạm dụng spawn subagent cho các tác vụ thông thường.
- Chỉ spawn subagent khi tác vụ có tính chuyên biệt rõ rệt hoặc có nhiều luồng công việc độc lập cần xử lý song song.
- Tránh spawn subagent dạng chuỗi phụ thuộc tuần tự vì gây lãng phí tài nguyên và làm mất ngữ cảnh.

### Subagent Role Directory
- `scout`: Đọc nhanh và khảo sát codebase diện rộng khi chưa rõ cấu trúc hoặc vị trí file.
- `reviewer`: Đánh giá chất lượng code, quy chuẩn kiến trúc và tuân thủ chuẩn mực.
- `security-reviewer`: Đánh giá bảo mật, quét lỗ hổng và rủi ro an ninh.
- `architect`: Thiết kế kiến trúc tổng thể, lập kế hoạch phân tách module lớn.
- `plan-reviewer`: Độc lập review và duyệt kế hoạch kỹ thuật (`plan.md`).
- `sonic`: Chỉnh sửa cơ học nhanh, biến đổi dữ liệu hàng loạt.
- `dely-implementer`: Viết code tự chủ, TDD theo contract thiết kế đã duyệt.
- `dely-reviewer`: Review code độc lập, kiểm tra test gate và trường hợp biên.
- `docs-*`: Quản lý vòng đời tài liệu Spec-Driven.

### Multi-Agent Spawning Guidelines
- **Chỉ spawn khi thực sự cần song song:** Khi đối mặt với việc khảo sát hoặc thực thi trên nhiều service/module độc lập cùng lúc.
- **Gộp batch:** Nếu spawn nhiều subagent, bắt buộc gộp chung vào 1 lệnh gọi `tasks[]` duy nhất, không gọi rời rạc.

### Advisor Role Guidelines
- When acting as **Advisor**: Provide passive analysis, architectural critique, edge-case risks, and suggestions only. NEVER issue mutation tool calls (`write`, `edit`, `bash` state changes). Output purely analytical feedback.

## Workspace

Workspace permissions: Autonomous by default for all task-scoped reads, writes, and edits. No confirmation required for standard code changes. Explicit confirmation is required ONLY for Risky Operations: destructive actions (data loss, force push, dropping tables/branches, hard resets, deleting production assets).

---

## Git Worktrees

Allowed only when requested or for approved parallel chunks. Use the exact task/chunk name. No parallel worktree agents unless requested. Delete each worktree only after completion, verification, and merge; leave none orphaned.

---

## Tools

### MCP Routing & Strict Enforcement (Hard Constraints)
- **Strict OUTPUT PREFIX Verification:** You MUST NEVER issue a tool call without first outputting the `[Pre-flight]` prefix.
- **MCP Route & Priority (Hard Constraints):** BẮT BUỘC ưu tiên dùng các MCP tools chuyên dụng tương ứng với domain của task. **CẤM** lạm dụng `bash` (grep, find, awk, curl) hoặc native tools khi trong danh sách công cụ đã có MCP tool phục vụ chức năng đó.
- **Fallback Rule:** Chỉ dùng bash/native tools thay thế khi MCP báo lỗi không khả dụng hoặc user bắt buộc.

- Use local search/read/terminal and external docs for third-party integrations as needed.
- Don't assume optional tools/services exist; fall back gracefully and report limitations.
- Prefer focused searches/ranges/summaries over entire massive logs or files.

---

## Windows Shell

Prefer PowerShell 7 (`pwsh`); use other shells only when required. Run heavy tasks sequentially in small steps. Set timeouts for long commands; inspect or stop safely if exceeded.

---

## Java

Before build/compile, detect the project JDK and set `JAVA_HOME`; don't rely on machine default unless it matches. Store the JDK/project mapping when memory is available.

---

## Reporting

For bugs, investigations, incidents, or complex tasks: **Current Status, Root Cause, Resolution, Impact, Risks, Next Step**. For simple tasks: what changed, verification, remaining risk. Always report blockers and incomplete verification.

---

## Estimate, Monitor, and Verify

For standard CLI commands, builds, and unit tests, execute directly with an appropriate timeout. Reserve structured estimate-and-monitor tracking strictly for long-running asynchronous background jobs (> 3 minutes) or unverified long scripts.
