---
name: reload-context
description: Use when the user says compact done, context lost, reload instructions, restore session, or after context compaction, session reset, /clear, or starting a new session in an existing workspace to reload and verify instructions and project state.
---

# Reload Context

**Goal:** Restore the full operating context (system instructions, global rules, project architecture, skills index, runtime config, and git state) immediately after session compaction, context loss, session clear, or when opening a new session on the current workspace.

**When to run:**
- Right after automatic compaction (`compact done`, `snapcompact`).
- When the user reports the agent forgot context, hallucinates, or lost context (`context lost`).
- When the user asks to `reload instructions` or `restore session`.
- Right at the start of a new session in a workspace that already has docs/source code.

**Input:**
- Project root instructions: `AGENTS.md`, `RULES.md`.
- Project template / role (if any): `SYSTEM.md`.
- Skills catalog: the `skills/*/SKILL.md` listing.
- Runtime configuration:
  - OMP: `~/.omp/agent/config.json`, `~/.omp/agent/mcp.json`, `bootstrap.ps1`.
  - DSH: `~/.dsh/`, `cordis.patch.yml`.
- Working tree state: output of `git status` and `git diff --stat`.

**Output:**
- Checklist confirming the context components loaded successfully.
- Brief summary of the current state (branch, dirty files, active tickets/tasks if any).
- Ready state to keep receiving commands without rule violations.

---

## 1. Source of truth hierarchy

When reloading context, the agent must follow this document priority order:

1. **`RULES.md`**: Global hard rules, precedence rule, pre-flight prefix requirement, MCP routing, data-preservation rule (Recycle Bin / Trash).
2. **`AGENTS.md`**: Project overview, Service registry, Layer read order, Tech stack, Task classification tier (1/2/3), Delegation logic, Quick rules.
3. **`SYSTEM.md`** (if present): Project guide template or root specification when the project has not finalized `AGENTS.md`.
4. **`docs/ARCHITECTURE.md` & `docs/specs/*.md`** (if a docs repo exists): Service architecture map and detailed business specifications.
5. **`skills/*/SKILL.md`**: Index of specialty skills registered in the workspace.
6. **Runtime config (`bootstrap.ps1`, `mcp.json`)**: Active MCP tools and model roles.
7. **`git status`**: Actual working tree at the current moment.

---

## 2. Context reload procedure

Execute these 6 mandatory steps in order:

### Step 1: Load core instructions (`AGENTS.md`)
- Read `AGENTS.md` at the workspace root.
- Identify:
  - Project overview and goals.
  - Pre-flight assessment and task tiering conventions (Tier 1 Direct, Tier 2 Single Subagent, Tier 3 Parallel Subagents).
  - Service registry table and layer read order (`{{LAYER_READ_ORDER}}`).
  - Verify command list (`{{VERIFY_COMMANDS}}`).

### Step 2: Load global rules (`RULES.md`)
- Read `RULES.md` at the workspace root.
- Note the mandatory invariants:
  - The `[Pre-flight] Tier: ... | Skills: ... | Plugins/MCP: ... | Rationale: ... | Action: ...` prefix before every tool call.
  - Precedence: Delegation and MCP override Simplicity and Think Before Coding.
  - Never delete files permanently (always use Recycle Bin / Trash).
  - Reply in Vietnamese (except code, commands, IDs).
  - Never commit/push/merge unprompted unless explicitly requested.

### Step 3: Check `SYSTEM.md` (if it exists)
- Check whether `SYSTEM.md` exists at the workspace root.
- If it exists with project info not yet migrated into `AGENTS.md`, read it for extra context; if it is a `{{PLACEHOLDER}}`-style template, record the template state.

### Step 4: Load the skills index
- Quickly scan the `skills/` listing (or `docs/skills/` for docs-repo layouts).
- Learn the available skills (e.g. `reload-context`, `init-docs`, `implement-task`, `create-plan`, `security-review`, `delivery`, `poka-yoke`...) to trigger the right one per task.

### Step 5: Load runtime config and MCP
- Inspect the bootstrap and MCP config files:
  - Read `bootstrap.ps1` (if present in the repo) or the runtime config to learn the configured MCP servers (`gitnexus`, `company-atlassian`, `context7`, `cloakbrowser`).
  - Note the `snapcompact.systemPrompt: agents-md,rules-md` directive to understand the agent runtime background-context mechanism.

### Step 6: Quick git status and diff scan
- Run `git status --short` and `git diff --stat`.
- Identify:
  - The current branch.
  - Pending changes (staged / unstaged).
  - Dirty-working-tree risks to warn about before the next task.

---

## 3. Adapters: OMP vs DSH

Depending on the active runtime environment, the agent applies the matching adapter:

| Criterion | OMP (Oh My Prompt) | DSH (Dev Shell / Cordis) |
|---|---|---|
| **Config Directory** | `~/.omp/agent/` (`$env:USERPROFILE\.omp\agent` on Windows) | `~/.dsh/` |
| **Config Files** | `config.json`, `mcp.json`, `models.json` | `cordis.patch.yml`, internal DSH config |
| **Snapcompact Hook** | `snapcompact.systemPrompt: agents-md,rules-md` auto-injects `AGENTS.md` and `RULES.md` into the system prompt after compaction | Managed via context buffer or a dedicated override file in Cordis |
| **Plugin / Extensions** | `~/.omp/agent/extensions/` | Injected via container layer or Cordis sandbox volume mount |
| **MCP Definition** | Declared in `~/.omp/agent/mcp.json` per the Desktop MCP JSON standard | Declared via `cordis.patch.yml` or the DSH server profile |

---

## 4. Post-load confirmation checklist (Output Checklist)

After completing the procedure, the agent emits a short status confirmation report:

```markdown
### [Context Reloaded]
- [x] AGENTS.md: Loaded (Tiering, Service Registry, Read Order)
- [x] RULES.md: Loaded (Pre-flight Prefix, Invariants, Trash rule)
- [x] SYSTEM.md: Checked (Loaded / Missing / Template form)
- [x] Skills Catalog: Indexed (count of ready skills)
- [x] Runtime & MCP: Confirmed OMP / DSH adapter + working MCP tools
- [x] Git Working Tree: Branch `<branch-name>` | Status: `<clean | dirty (file count)>`

Status: ready for the next command.
```
