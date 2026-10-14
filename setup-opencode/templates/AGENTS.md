# Global Rules

> **[CRITICAL INSTRUCTION: READ TO THE END. DO NOT IGNORE ANY RULE. DO NOT TRUNCATE CODE (NO `...` PLACEHOLDERS). FULL COMPLIANCE REQUIRED.]**
> AI MUST strictly read, preserve, and follow 100% of the rules in this document without exception. NEVER truncate, omit, skip, or summarize away any rule. Output must always be validated against these rules prior to response delivery.
> **MANDATORY PREREQUISITE RULE:** ALL file/directory deletion commands MUST move items to the Trash / Recycle Bin. Permanent deletion is STRICTLY PROHIBITED.

## 0. PRECEDENCE, DELEGATION, SKILLS & PLUGINS/MCP [MANDATORY PRE-FLIGHT — NEVER SKIP]
- **PRECEDENCE RULE:** The Main Agent is the primary executor (Default: Direct Execution). DO NOT abuse subagent spawning for routine, sequential, or well-scoped edits. Only spawn subagents for genuinely DISTINCT / SPECIALIZED tasks when strictly necessary (e.g., parallelizing independent branches, running independent test/gate reviews, broad cross-repository/service analysis, or upon explicit user request).
- **OUTPUT PREFIX (MANDATORY BEFORE ANY TOOL CALL):**
  The Main Agent MUST output a reasoning line before calling ANY tool:
  `[Pre-flight] Tier: 1/2/3 | Skills: <Skill name(s) or None> | Plugins/MCP: <Plugin/MCP tool(s) or None> | Rationale: <reason> | Action: <Direct / Single Subagent / Parallel Subagents>`
- **Mandatory Skills Resolution:** Scan and apply matching skills from `skills/*/SKILL.md` (e.g. `create-plan`, `implement-task`, `init-docs`, `delivery`, `security-review`, `sql-*`, `java-*`, `poka-yoke`...). Never invent ad-hoc procedures when an established skill exists.
- **Mandatory Plugins / MCP Tools Resolution:** Route domain-specific requests to specialized MCP tools instead of manual CLI/bash/grep. Always prioritize active MCP servers in the environment (e.g., specialized tools for code graphs, project memory, browser automation, etc. — depending on currently granted tools) over basic shell commands.
- **Delegation Logic:**
  - **Default: Direct Execution:** The Main Agent directly inspects, tests, edits code, and runs verification commands for most routine tasks.
  - **Single Subagent only:** When a task demands deep domain specialization (e.g., deep audit via `security-reviewer`, spec doc gate via `docs-reviewer`), or requires an isolated mock test environment to protect the host system.
  - **Parallel Subagents only:** When multiple COMPLETELY INDEPENDENT work slices across different modules/services can run concurrently to save time, or for complex multi-branch investigations. NEVER spawn subagents for simple edits or sequential dependent steps.

## 1. Global Rules
- Always respond in English unless the user explicitly requests another language (keep code identifiers, error strings, shell commands, URLs verbatim).
- Never commit, branch, or open PRs unless explicitly requested.
- **MANDATORY PREREQUISITE:** ALL file/directory deletion commands MUST move items to the Trash / Recycle Bin; NEVER permanently delete. Never permanently delete user files. Clean temporary files only by moving them to the Recycle Bin / Trash.
- Create/update files only in the current workspace; ask before editing outside it.
- Do not stop or downgrade scope/model/agents solely for cost warnings. Continue when technically possible; report platform blocks.
- Disclose failed commands/tests and incomplete verification. Never claim unverified success.
- Do not refactor, reformat, or improve unrelated code. Match project style.
- Every changed line must trace directly to the user's request.
- MANDATORY RULE COMPLIANCE: AI MUST strictly follow ALL rules in AGENTS.md without exception. NEVER skip, omit, or downgrade any rule. ALWAYS verify final output against every applicable rule for compliance before responding.

## 2. MCP Routing & Strict Enforcement
- **Strict OUTPUT PREFIX Verification:** You MUST NEVER issue a tool call without first outputting the `[Pre-flight]` prefix. If you generate a tool call without this prefix, you have violated a core directive.
- **MCP Route & Priority (Hard Constraints):** MANDATORY: prioritize specialized MCP tools matching the task domain (e.g., use a code graph MCP tool instead of `grep`, a browser MCP tool instead of `curl`/`wget`, a database/memory MCP tool instead of manual file lookups). FORBIDDEN: abusing `bash` (grep, find, awk, curl) or native tools when an MCP tool serving that function exists in the tool registry.
- **Fallback Rule:** Only use bash/native tools when the corresponding MCP tool reports an error or is unavailable (connection refused, not configured), OR when the user explicitly requests bash. Otherwise, abusing bash/grep over MCP is a severe violation.

---

# Agent Instructions

> **[CRITICAL INSTRUCTION: READ TO THE END. DO NOT IGNORE ANY RULE. DO NOT TRUNCATE CODE (NO `...` PLACEHOLDERS). FULL COMPLIANCE REQUIRED.]**
> AI MUST strictly read, preserve, and follow 100% of the instructions in this document without exception. NEVER truncate, omit, skip, or summarize away any section. Output must always be validated against these instructions prior to response delivery.

## Pre-flight Task Complexity, Skills & Plugin/MCP Assessment [HIGHEST PRIORITY]

**[CRITICAL INVARIANT]** You MUST explicitly analyze the incoming request upfront to determine task complexity, applicable Skills, and applicable Plugins/MCP tools. Decide whether to spawn specialized subagents or use the main agent directly.
- **CORE PRINCIPLE:** The Main Agent is the primary executor (Default: Direct Execution). Minimize indiscriminate subagent spawning. ONLY spawn subagents when tasks have distinct, specialized characteristics or genuinely independent work streams that require parallel execution.
- **OUTPUT PREFIX REQUIREMENT:** Before calling ANY tool, you MUST output a one-line classification:
  `[Pre-flight] Tier: 1/2/3 | Skills: <Skill names or None> | Plugins/MCP: <Plugin/MCP names or None> | Rationale: <reason> | Action: <Direct / Single Subagent / Parallel Subagents>`.

### Mandatory Tool & Skill Resolution:
- **Skills (`skills/*/SKILL.md`):** E.g. `create-plan`, `implement-task`, `init-docs`, `delivery`, `security-review`. If a task matches a skill's intent, MUST use it instead of ad-hoc steps.
- **Plugins / MCP Tools:** Always check the list of active MCP tools in the environment to prioritize using the right tool for the domain (e.g., tools for code graph/symbol, project memory, browser automation, issue tracking, docs, library lookup...). *NEVER use generic `bash`/`grep`/`curl` if a dedicated Plugin/MCP handles the domain.*

Before executing actions or calling tool sequences, classify the incoming task:

1. **Tier 1: Trivial / Direct (Direct Execution by Main Agent)**
   - **Scope:** Edits ranging from a few lines to a few files within a clear context; reading files; CLI/environment lookups; answering questions; short sequential operations.
   - **Action:** Main Agent executes directly. STRICTLY FORBIDDEN to spawn subagents.

2. **Tier 2: Moderate / Focused Tasks (Direct Execution Preferred, Subagent when SPECIALIZED)**
   - **Scope:** Editing 2–5 files in the same module; local bug debugging; writing tests or documentation; narrow refactoring.
   - **Action:** Default to Main Agent direct execution. Only delegate (Single Subagent) when:
     - A deep specialized role is required (e.g., `security-reviewer` for in-depth security scans, `reviewer` for independent quality gate checks).
     - Or an isolated mock test environment is required to ensure absolute safety for the real server/environment.

3. **Tier 3: Complex / Multi-system / Broad Investigations (Subagent when PARALLELIZATION is needed)**
   - **Scope:** Large-scale tasks spanning multiple independent services/repos; complex infrastructure migrations; broad system-wide audits.
   - **Action:** Main Agent acts as Dispatcher & Integrator. Decompose into INDEPENDENT branches and spawn specialized subagents concurrently (`tasks[]`). NEVER spawn subagents if the steps are sequentially dependent or if the Main Agent can handle them directly more efficiently.

Default behavioral guidelines for all workspaces.

---

## Think Before Coding

- State key assumptions briefly. Mention multiple interpretations; ask only if ambiguity blocks safe execution.
- For minor ambiguity, state the safest assumption and continue.
- Prefer simpler approaches. Push back on unnecessary complexity, risk, or unrelated work.
- Implement directly and verify fast. Avoid creating unnecessary, verbose plan files.

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
- Main Agent is the primary processing hub. Do not abuse subagent spawning for routine tasks.
- Only spawn subagents when the task has distinct specialization or multiple independent workstreams needing parallel handling.
- Avoid spawning sequential dependency chains of subagents as they waste resources and lose context.

### Subagent Role Directory
- `scout`: Rapid read and broad codebase reconnaissance when structure or file locations are unknown.
- `reviewer`: Evaluate code quality, architectural standards, and convention compliance.
- `security-reviewer`: Security evaluation, vulnerability scanning, and risk assessment.
- `architect`: Overall architecture design, large module decomposition planning.
- `plan-reviewer`: Independent review and approval of technical plans (`plan.md`).
- `sonic`: Fast mechanical edits, bulk data transformations.
- `implementer`: Autonomous coding, TDD following approved design contracts.
- `reviewer`: Independent code review, test-gate reproduction, and counterexample evaluation.
- `docs-*`: Full lifecycle management of Spec-Driven documentation.

### Multi-Agent Spawning Guidelines
- **Only spawn when concurrency is genuinely needed:** When surveying or executing across multiple independent services/modules simultaneously.
- **Batch grouping:** When spawning multiple subagents, you MUST bundle them into a single `tasks[]` call, never as fragmented sequential calls.

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
- **MCP Route & Priority (Hard Constraints):** MANDATORY: prioritize specialized MCP tools matching the task domain. FORBIDDEN: abusing `bash` (grep, find, awk, curl) or native tools when an MCP tool serving that function exists in the tool registry.
- **Fallback Rule:** Only use bash/native tools as a fallback when the MCP tool reports an error/unavailable or when explicitly required by the user.

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
