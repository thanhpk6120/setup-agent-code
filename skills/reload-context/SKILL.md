---
name: reload-context
description: Use when the user says compaction completed, lost context, reload instructions, restore session, or after context compaction, session reset, /clear, or starting a new session in an existing workspace to reload and verify instructions and project state.
---

# Reload Context

**Goal:** Restore complete operational context (system instructions, global rules, project architecture, skills index, runtime config, and git state) immediately after session compaction, lost context, cleared session, or when starting a new session in an existing workspace.

**When to run:**
- Immediately after automatic compaction takes place (`compact xong`, `snapcompact`).
- When the user reports the agent lost context, is hallucinating, or experienced context loss.
- When the user requests `reload instructions` or `restore session`.
- Immediately upon starting a new session in a workspace with existing documentation/source code.

**Input:**
- Project root instructions: `AGENTS.md`, `RULES.md`.
- Project template / role (if present): `SYSTEM.md`.
- Skills catalog: directory `skills/*/SKILL.md`.
- Runtime configuration:
  - OMP: `~/.omp/agent/config.json`, `~/.omp/agent/mcp.json`, `bootstrap.ps1`.
  - DSH: `~/.dsh/`, `cordis.patch.yml`.
- Working tree state: output from `git status` and `git diff --stat`.

**Output:**
- Checklist confirming context components loaded successfully.
- Brief summary of current state (Branch, Dirty files, Active tickets/tasks if applicable).
- Ready state to continue receiving commands without rule violations.

---

## 1. Source of Truth Hierarchy

When reloading context, the agent must adhere to the document precedence order:

1. **`RULES.md`**: Global invariants (Vietnamese default response, Recycle Bin / Trash soft-delete, workspace scope, verification honesty, MCP priority with native search/read allowed).
2. **`AGENTS.md`**: Project overview, Service registry, Layer read order, Tech stack, Execution & Subagent Delegation rules, Quick rules.
3. **`SYSTEM.md`** (if present): Project guide template or root specification when `AGENTS.md` has not been finalized.
4. **`docs/ARCHITECTURE.md` & `docs/specs/*.md`** (if docs repo exists): Service architecture map and detailed business specifications.
5. **`skills/*/SKILL.md`**: Index of registered specialized skills in the workspace.
6. **Runtime config (`bootstrap.ps1`, `mcp.json`)**: Active MCP tools and model roles.
7. **`git status`**: Real working tree state at current time.

---

## 2. Reload Procedure

Execute sequentially through 6 mandatory steps:

### Step 1: Load Core Instructions (`AGENTS.md`)
- Read `AGENTS.md` at workspace root.
- Determine:
  - Project overview & project objectives.
  - Execution & Subagent Delegation conventions (direct for small/sequential work, parallel batch fan-out for independent streams).
  - Service registry table and layer read order (`{{LAYER_READ_ORDER}}`).
  - Verification command catalog (`{{VERIFY_COMMANDS}}`).

### Step 2: Load Global Rules (`RULES.md`)
- Read `RULES.md` at workspace root.
- Note mandatory invariants:
  - Prefer specialized MCP tools when fitting; use native `read`/`grep`/`glob` directly for routine file/text lookups.
  - Never permanently delete files (must use Recycle Bin / Trash).
  - Language rules (always respond in Vietnamese unless requested otherwise; keep code/commands verbatim).
  - Do not autonomously commit/push/merge unless explicitly requested.

### Step 3: Inspect `SYSTEM.md` (if present)
- Check whether `SYSTEM.md` exists at workspace root.
- If present with un-migrated project info, read for supplementary context; if template with `{{PLACEHOLDER}}`, note template state.

### Step 4: Load Skills Index
- Quick-scan `skills/` directory (or `docs/skills/` under docs repo structure).
- Inventory available skills (e.g. `reload-context`, `init-docs`, `implement-task`, `create-plan`, `security-review`, `poka-yoke`...) to activate correctly when matching tasks arise.

### Step 5: Load Runtime Config & MCP
- Check bootstrap config and MCP files:
  - Read `bootstrap.ps1` (if present) or runtime config to understand active MCP servers (`gitnexus`, `company-atlassian`, `context7`, `cloakbrowser`).
  - Note directive `snapcompact.systemPrompt: agents-md,rules-md` to understand background context retention.

### Step 6: Scan Git Status & Diff
- Run `git status --short` and `git diff --stat`.
- Identify:
  - Current branch.
  - Pending changes (staged / unstaged).
  - Dirty working tree risks to warn before executing subsequent tasks.

---

## 3. Adapters: OMP vs DSH

Depending on the active runtime environment, apply the matching adapter:

| Criterion | OMP (oh-my-pi) | DSH (DeepSeek Harness) |
|---|---|---|
| **Config Directory** | `~/.omp/agent/` (`$env:USERPROFILE\.omp\agent` on Windows) | `~/.dsh/` |
| **Config Files** | `config.yml`, `models.yml`, `mcp.json` | `cordis.patch.yml`, internal DSH config |
| **Snapcompact Hook** | `snapcompact.systemPrompt: agents-md,rules-md` automatically injects `AGENTS.md` and `RULES.md` into system prompt post-compaction | Managed via context buffer or dedicated cordis file override |
| **Plugin / Extensions** | `~/.omp/agent/extensions/` | Injected via container layers or sandbox volume mounts |
| **MCP Definition** | Declared in `~/.omp/agent/mcp.json` per Desktop MCP JSON standard | Declared via `cordis.patch.yml` or DSH server profiles |

---

## 4. Output Checklist

After completing the procedure, output a concise status confirmation:

```markdown
### [Context Reloaded]
- [x] AGENTS.md: Loaded (Delegation, Service Registry, Read Order)
- [x] RULES.md: Loaded (Global Invariants, MCP Routing, Trash rule)
- [x] SYSTEM.md: Checked (Loaded / Absent / Template form)
- [x] Skills Catalog: Indexed (Number of skills ready)
- [x] Runtime & MCP: Confirmed OMP / DSH adapter + active MCP tools
- [x] Git Working Tree: Branch `<branch-name>` | Status: `<clean | dirty (number of files)>`

Status: Ready for the next instruction.
```
