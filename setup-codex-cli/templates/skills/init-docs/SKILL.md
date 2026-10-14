---
name: init-docs
description: Use when the user asks to initialize, regenerate, refresh, audit, or update project map docs such as architecture.md, specs/*.md, design.md, or run the Spec-Driven init docs workflow.
---

# Rule 00 — Init Docs

**Goal:** Initialize for the first time or resynchronize source documents of the project (`ARCHITECTURE.md`, `specs/*.md`, `DESIGN.md`, `COMMANDS.md`) from source code and `AGENTS.md` across services.

**When to run:**
- When the docs repo was freshly cloned and lacks a canonical `ARCHITECTURE.md`.
- After adding a new service to the workspace.
- After a major refactoring that alters overall architecture.

**Input:**
- Full source code of peer service repositories.
- `AGENTS.md` of each service repository (if present).
- Project root `AGENTS.md`.

**Output:**
- `docs/ARCHITECTURE.md` — overall architecture.
- `docs/DESIGN.md` — UI/UX design.
- `docs/COMMANDS.md` — quick commands catalog for dev/CI.
- `docs/specs/<domain>.md` — business domain specifications.

### File Naming Conventions
- **Level 1 Docs (Root docs inside `docs/`):** MUST use **UPPERCASE** (`README.md`, `ARCHITECTURE.md`, `DESIGN.md`, `COMMANDS.md`, `AGENTS-TEMPLATE.md`).
- **Level 2 Docs (Domain specs, Rules, Features):** MUST use **lowercase kebab-case** (`docs/specs/<domain-name>.md`, `docs/rules/<rule-name>.md`, `expect.md`, `plan.md`, `tasks.md`, `report.md`, `deploy.md`).

---

> **Multi-Agent Orchestration Contract:** Main session acts as Dispatcher/Control. MUST use the `task` tool to call the `docs-init` (or `docs-update`) agent to analyze the entire system and draft documents, partitioning slices by service/module when inspecting multiple parts. Afterward, call `docs-reviewer` to assess quality before submitting for user approval.

## Document Preservation Rules (MANDATORY INVARIANT)
> **ADDITIVE-ONLY (NEVER DELETE):** When documentation (files inside `docs/`) already exists, it is **STRICTLY FORBIDDEN** to delete or overwrite/regenerate whole files causing the loss of existing sections, paragraphs, or notes.
> - ONLY allowed to **append new information** (additive update) or adjust old content if it genuinely deviates from real code.
> - All human-authored existing content (context, business rules, edge-case rationale) must be kept intact.
> - Must use granular edits (patch/diff) instead of blowing away existing files with entirely new content.

## Procedure

### 0. Mandatory Pre-requisites Before Writing
- Start every session with `git pull` inside `docs/`.
- On the first instruction read, read **only one instruction file** by precedence:
  1. If `CLAUDE.md` exists at workspace root: read `CLAUDE.md` and **do not read `AGENTS.md`**.
  2. If `CLAUDE.md` is absent but `AGENTS.md` exists: read `AGENTS.md`.
  3. If both are absent: continue with `README.md` and report missing instruction file.
- The chosen instruction file provides:
  - workspace role,
  - canonical project conventions,
  - which doc portions may be auto-updated vs. requiring diff/PR.
- If the chosen instruction file forbids generating/updating certain files, stop and report to the user.

### 1. Architecture Survey
- Map services: repo name, primary responsibility, application type (web/api/worker/...), tech stack.
- Determine communication paths: HTTP, message queue, gRPC, events, shared files...
- Explicitly note external entry/egress points: auth providers, external databases, CDN, gateway...
- If the service repo has a GitNexus index, use `mcp__gitnexus__query` for primary execution flows, `mcp__gitnexus__context` on central symbols to verify responsibilities, `mcp__gitnexus__route_map` to list known APIs/handlers, and `mcp__gitnexus__cypher` only for advanced graph queries. If `gitnexus://repo/<name>/context` reports a stale index, notify the user and stop without guessing.

### 2. Decide Whether Project Map Needs Generation / Update
- Project map consists of: `docs/ARCHITECTURE.md`, `docs/specs/*.md`, `docs/DESIGN.md`.
- If source/docs are inspected and map files are already sufficient and accurate: **do not ask**, simply report no changes required.
- If creating new or updating any project map file is needed: **MUST ask the user before writing files**.
- The inquiry must clearly state:
  - which files will be generated/updated,
  - reasons for the change,
  - information sources used,
  - risks if docs are inaccurate.
- Only write files after explicit user confirmation.

### 3. Generate / Update `ARCHITECTURE.md`
- Minimum structure:
  - System overview (1 paragraph).
  - Service list + 1-line responsibility per service.
  - Text-based communication diagram (diagram image not required).
  - Tech stack per service (verified from source, never fabricated).
  - Deployment mechanisms / run directories if readable from repo (e.g. `docker-compose.yml`, `Dockerfile`, scripts in `bundles/`).
- Clearly differentiate confirmed sections from assumed ones.

### 4. Generate / Update `specs/<domain>.md`
- 1 domain = 1 file. Domains are partitioned by business capabilities, not by services.
- Each file includes:
  - domain goal,
  - primary flow (happy path),
  - alternative / exception flows,
  - primary actors (which user roles).
- Do not arbitrarily split domains without clear signals from code; when ambiguous, ask before writing.

### 5. Generate / Update `DESIGN.md`
- Describe current UI/UX according to real service observations.
- List primary screens/portlets/components; avoid enumerating every micro detail.

### 6. Open Questions
- After generation, consolidate uncertainties under "Open Questions" for BA/TechLead resolution before using docs for planning.

---

## Stopping Criteria (Gates)
- AI does **not** write code, does not open PRs to service repos.
- If missing information prevents confirming a section, mark "unconfirmed" with reason rather than guessing.
- All changes are proposed as diffs awaiting TechLead approval (Gate 2 in `README.md`).
- **Data preservation:** Must ensure no existing content is lost or accidentally deleted during documentation updates.
