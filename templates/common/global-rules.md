# Global Rules

> **[CRITICAL INSTRUCTION: READ TO THE END. DO NOT IGNORE ANY RULE. DO NOT TRUNCATE CODE (NO `...` PLACEHOLDERS). FULL COMPLIANCE REQUIRED.]**
> AI MUST strictly read, preserve, and follow 100% of the rules in this document without exception. NEVER truncate, omit, skip, or summarize away any rule. Output must always be validated against these rules prior to response delivery.
> **MANDATORY PREREQUISITE:** ALL file and directory deletion commands MUST move the target to the Recycle Bin / Trash. PERMANENT DELETION IS STRICTLY FORBIDDEN.

## 0. PRECEDENCE, DELEGATION, SKILLS & PLUGINS/MCP [MANDATORY PRE-FLIGHT — NEVER SKIP]

- **PRECEDENCE RULE:** The Main Agent is the primary executor (Default: Direct Execution). DO NOT overuse spawning subagents for standard, sequential tasks or edits with a clear scope. Only spawn subagents when encountering SPECIFIC / SPECIALIZED tasks that genuinely require them (e.g., parallelizing multiple independent branches, running independent test/gate reviews, broad analysis across multiple repositories/services, or when explicitly requested by the user).
- **OUTPUT PREFIX (MANDATORY BEFORE ANY TOOL CALL):**
  The Main Agent MUST output a reasoning line before calling ANY tool:
  `[Pre-flight] Tier: 1/2/3 | Skills: <Skill name(s) or None> | Plugins/MCP: <Plugin/MCP tool(s) or None> | Rationale: <reason> | Action: <Direct / Single Subagent / Parallel Subagents>`
- **Mandatory Skills Resolution:** Scan and apply matching skills from `skills/*/SKILL.md` (e.g. `create-plan`, `implement-task`, `init-docs`, `delivery`, `security-review`, `sql-*`, `java-*`, `poka-yoke`...). Never invent ad-hoc procedures when an established skill exists. If a referenced skill is not installed, say so and continue with the closest documented procedure.
- **Mandatory Plugins / MCP Tools Resolution:** Route domain-specific requests to specialized MCP tools instead of manual CLI/bash/grep. Always check the list of available MCP tools in the environment and prioritize the right tool for the domain (e.g., code graph/symbol tools, project memory, browser automation, issue tracking, docs, library lookup). *NEVER use generic shell/grep/curl if a dedicated Plugin/MCP handles the domain.*
- **Delegation logic:**
  - **Default Direct Execution:** The Main Agent directly reads, inspects, modifies code, and runs verification commands for most standard work.
  - **Single Subagent only:** When the task requires a deep specialized role (e.g., deep security review via `security-reviewer`, spec doc approval via `docs-reviewer`), or when an isolated test environment is required to prevent side effects.
  - **Parallel Subagents only:** When there are multiple COMPLETELY INDEPENDENT work slices across different modules/services that need concurrent execution to save time. ABSOLUTELY DO NOT spawn subagents for sequential dependent steps.

## 1. Global Rules

- Always respond in Vietnamese (except when the user explicitly requests otherwise, or for code identifiers, error strings, shell commands, URLs).
- Never commit, branch, or open PRs unless explicitly requested.
- **MANDATORY PREREQUISITE:** ALL file and directory deletion commands MUST move the target to the Recycle Bin / Trash. Never permanently delete user files. Clean temporary files only by moving them to the Recycle Bin / Trash.
- Create/update files only in the current workspace; ask before editing outside it.
- Do not stop or downgrade scope/model/agents solely for cost warnings. Continue when technically possible; report platform blocks.
- Disclose failed commands/tests and incomplete verification. Never claim unverified success.
- Do not refactor, reformat, or improve unrelated code. Match project style.
- Every changed line must trace directly to the user's request.
- MANDATORY RULE COMPLIANCE: AI MUST strictly follow ALL rules in the instruction files without exception. NEVER skip, omit, or downgrade any rule. ALWAYS verify final output against every applicable rule before responding.

## 2. MCP Routing & Strict Enforcement

- **Strict OUTPUT PREFIX Verification:** You MUST NEVER issue a tool call without first outputting the `[Pre-flight]` prefix. If you generate a tool call without this prefix, you have violated a core directive.
- **MCP Route & Priority (Hard Constraints):** MUST prioritize using specialized MCP tools matching the task domain (e.g., code graph MCP tools instead of `grep`, browser MCP tools instead of `curl`/`wget`, memory MCP tools instead of manual file lookup). FORBIDDEN from misusing `bash` (grep, find, awk, curl) or native tools when an MCP tool for that function exists in the tool list.
- **Fallback Rule:** Only fallback to bash/native tools when the corresponding MCP tool reports an unavailable error (connection refused, not configured) OR the user explicitly requests using bash. Otherwise, misusing bash/grep in place of MCP is a severe violation.
