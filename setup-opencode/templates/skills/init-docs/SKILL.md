---
name: init-docs
description: Use when the user asks to initialize, regenerate, refresh, audit, or update project map docs such as architecture.md, specs/*.md, design.md, or run the Spec-Driven init docs workflow.
---

# Rule 00 — Init Docs

**Goal:** Bootstrap or re-sync the project source docs (`ARCHITECTURE.md`, `specs/*.md`, `DESIGN.md`, `COMMANDS.md`) from source code and each service `AGENTS.md`.

**When to run:**
- When the docs repo was just cloned and has no standard `ARCHITECTURE.md` yet.
- After adding a new service to the workspace.
- After a large refactor that changes the overall architecture.

**Inputs:**
- Full source code of the sibling service repos.
- Each service repo `AGENTS.md` (if present).
- Project root `AGENTS.md`.

**Outputs:**
- `docs/ARCHITECTURE.md` — overall architecture.
- `docs/DESIGN.md` — UI/UX design.
- `docs/COMMANDS.md` — quick command catalog for dev/CI.
- `docs/specs/<domain>.md` — business specification per domain.

### File naming convention
- **Level-1 docs (root docs in `docs/`):** MUST use **UPPERCASE** names (`README.md`, `ARCHITECTURE.md`, `DESIGN.md`, `COMMANDS.md`, `AGENTS-TEMPLATE.md`).
- **Level-2 docs (domain specs, rules, features):** MUST use **lowercase kebab-case** (`docs/specs/<domain-name>.md`, `docs/rules/<rule-name>.md`, `expect.md`, `plan.md`, `tasks.md`, `report.md`, `deploy.md`).

---

> **Multi-Agent Orchestration Contract:** The main session acts as Dispatcher/Control. You MUST use the `task` tool to call the `docs-init` (or `docs-update`) agent to analyze the whole system and draft docs, splitting slices by service/module when surveying many parts. Then call `docs-reviewer` for quality review before sending to the user for approval.

## Document preservation rule (MANDATORY INVARIANT)
> **NEVER DELETE (ADDITIVE-ONLY):** When docs (files in `docs/`) already exist, it is **FORBIDDEN** to remove them or blank-overwrite/regenerate a whole file in a way that loses existing sections, paragraphs, or notes. 
> - You may ONLY **append** new information (additive update) or adjust old content that is genuinely wrong versus the actual code.
> - All pre-existing human-written content (context, business rules, exception explanations) must stay intact.
> - Use partial edits (patch/diff) instead of overwriting old files with entirely new content.

## Procedure

### 0. Required before writing
- Start every session with `git pull` in `docs/`.
- On the first instruction read, read **exactly one instruction file** in priority order:
  1. If `CLAUDE.md` exists at the workspace root: read `CLAUDE.md` and **skip `AGENTS.md`**.
  2. If no `CLAUDE.md` but `AGENTS.md` exists: read `AGENTS.md`.
  3. If neither exists: continue with `README.md` and report the missing instruction file.
- The selected instruction file tells you:
  - the workspace role,
  - the normalized project conventions,
  - which docs may be self-updated and which need a diff/PR.
- If the selected instruction file forbids generating/updating some file, stop and tell the user.

### 1. Survey the architecture
- Map services: repo name, primary responsibility, app type (web/api/worker/...), technology.
- Identify how services communicate: HTTP, message queue, gRPC, events, shared files...
- Record external entry/exit points: auth provider, external DB, CDN, gateway...
- If a service repo has a GitNexus index, use `mcp__gitnexus__query` for key execution flows, `mcp__gitnexus__context` on central symbols to confirm responsibilities, `mcp__gitnexus__route_map` to list known APIs/handlers, and `mcp__gitnexus__cypher` only for advanced graph queries. If `gitnexus://repo/<name>/context` reports a stale index, tell the user and stop; do not infer.

### 2. Decide whether the project map needs generating/updating
- The project map consists of: `docs/ARCHITECTURE.md`, `docs/specs/*.md`, `docs/DESIGN.md`.
- If reading source/docs shows the map files are sufficient and correct with no update needed: **do not ask**, just report no change needed.
- If any map file needs creating or updating: you **MUST ask the user before writing files**.
- The question must state:
  - which files will be generated/updated,
  - why the change is needed,
  - which information sources were used,
  - the risk if the docs are wrong.
- Write files only after explicit user approval.

### 3. Generate/update `ARCHITECTURE.md`
- Minimum structure:
  - System overview (1 paragraph).
  - Service list + one-line responsibility per service.
  - Text communication diagram (figure optional).
  - Per-service stack (confirmed from source, never invented).
  - Deployment/operations layout if readable from the repo (e.g. `docker-compose.yml`, `Dockerfile`, scripts in `bundles/`).
- Mark clearly which parts are confirmed and which are still assumptions.

### 4. Generate/update `specs/<domain>.md`
- 1 domain = 1 file. Split domains by business area, not by service.
- Each file contains:
  - domain goal,
  - main flow (happy path),
  - secondary flows / exceptions,
  - primary actor (which user role).
- Do not split domains without clear code evidence; when ambiguous, ask before writing.

### 5. Generate/update `DESIGN.md`
- Describe the current UI/UX from real service observation.
- List key screens/portlets/components; avoid enumerating every small detail.

### 6. Open questions
- After generating, collect open questions under "Open questions" for the BA/TechLead to answer before the docs feed planning.

---

## Stop criteria (gate)
- The AI does **not** code and does **not** open PRs to service repos.
- When information is missing to confirm a part, write "unconfirmed" with a reason instead of guessing.
- All changes are proposed as diffs and wait for TechLead approval (Gate 2 in `README.md`).
- **Data preservation:** ensure no pre-existing content is lost or accidentally deleted during doc updates.
