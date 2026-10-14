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
- MANDATORY RULE COMPLIANCE: AI MUST strictly follow ALL rules in AGENTS.md and RULES.md without exception. NEVER skip, omit, or downgrade any rule. ALWAYS verify final output against every applicable rule for compliance before responding.

## 2. MCP Routing & Strict Enforcement
- **Strict OUTPUT PREFIX Verification:** You MUST NEVER issue a tool call without first outputting the `[Pre-flight]` prefix. If you generate a tool call without this prefix, you have violated a core directive.
- **MCP Route & Priority (Hard Constraints):** MANDATORY: prioritize specialized MCP tools matching the task domain (e.g., use a code graph MCP tool instead of `grep`, a browser MCP tool instead of `curl`/`wget`, a database/memory MCP tool instead of manual file lookups). FORBIDDEN: abusing `bash` (grep, find, awk, curl) or native tools when an MCP tool serving that function exists in the tool registry.
- **Fallback Rule:** Only use bash/native tools when the corresponding MCP tool reports an error or is unavailable (connection refused, not configured), OR when the user explicitly requests bash. Otherwise, abusing bash/grep over MCP is a severe violation.
