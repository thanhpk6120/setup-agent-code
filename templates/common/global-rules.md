# Global Rules

> **[CRITICAL INSTRUCTION: FULL COMPLIANCE REQUIRED.]**
> Follow all rules in this document without truncating code (`...`) or skipping verification.
> **MANDATORY PREREQUISITE:** ALL file and directory deletion commands MUST move the target to the Recycle Bin / Trash. PERMANENT DELETION IS STRICTLY FORBIDDEN.

## 1. Global Rules

- Always respond in Vietnamese (except when the user explicitly requests otherwise, or for code identifiers, error strings, shell commands, URLs).
- Never commit, branch, or open PRs unless explicitly requested.
- **Soft Delete Only:** Move deleted files/directories (including temporary cleanup) to the Recycle Bin / Trash. Never permanently delete user files.
- Create/update files only in the current workspace; ask before editing outside it.
- Do not stop or downgrade scope/model/agents solely for cost warnings. Continue when technically possible; report platform blocks.
- Disclose failed commands/tests and incomplete verification. Never claim unverified success.
- Do not refactor, reformat, or improve unrelated code. Match project style. Every changed line must trace directly to the user's request.

## 2. Skills & MCP Routing

- **Skills (`skills/*/SKILL.md`):** Apply matching skills (e.g. `create-plan`, `implement-task`, `init-docs`, `security-review`, `sql-*`, `java-*`, `poka-yoke`) when present; if a skill is absent, continue with the closest documented procedure.
- **MCP Priority:** Prefer specialized MCP tools when they fit the task (`gitnexus` for call-graph/impact on indexed repos, `context7` for library docs, `memorix` for project memory, `cloakbrowser` for JS/SPA web pages) instead of manual `curl`/`wget` or ad-hoc scripting.
- **Native Tools Allowed:** Use native `read`/`grep`/`glob` directly for routine text search or file reads, and fall back to bash/native tools whenever an MCP server is unavailable, unindexed, or fails.
