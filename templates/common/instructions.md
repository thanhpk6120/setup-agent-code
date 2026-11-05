# Agent Instructions

> **[CRITICAL INSTRUCTION: READ TO THE END. DO NOT IGNORE ANY RULE. DO NOT TRUNCATE CODE (NO `...` PLACEHOLDERS). FULL COMPLIANCE REQUIRED.]**
> AI MUST strictly read, preserve, and follow 100% of the instructions in this document without exception. NEVER truncate, omit, skip, or summarize away any section. Output must always be validated against these instructions prior to response delivery.

## Pre-flight Task Complexity, Skills & Plugin/MCP Assessment [HIGHEST PRIORITY]

**[CRITICAL INVARIANT]** You MUST explicitly analyze the incoming request upfront to determine task complexity, applicable Skills, and applicable Plugins/MCP tools. Decide whether to spawn specialized subagents or use the main agent directly.
- **CORE PRINCIPLE:** The Main Agent is the primary executor (Default: Direct Execution). Minimize unnecessary subagent spawning. ONLY spawn subagents when the task is specialized, isolated, or consists of truly independent work streams that need parallel execution.
- **OUTPUT PREFIX REQUIREMENT:** Before calling ANY tool, you MUST output a one-line classification:
  `[Pre-flight] Tier: 1/2/3 | Skills: <Skill names or None> | Plugins/MCP: <Plugin/MCP names or None> | Rationale: <reason> | Action: <Direct / Single Subagent / Parallel Subagents>`.

### Mandatory Tool & Skill Resolution

- **Skills (`skills/*/SKILL.md`):** E.g. `create-plan`, `implement-task`, `init-docs`, `delivery`, `security-review`. If a task matches a skill's intent, MUST use it instead of ad-hoc steps.
- **Plugins / MCP Tools:** Always check the list of available MCP tools in the environment to prioritize using the right tool for the domain (e.g., tools for code graph/symbols, project memory, browser automation, issue tracking, docs, library docs). *NEVER use generic `bash`/`grep`/`curl` if a dedicated Plugin/MCP handles the domain.*

Before executing actions or calling tool sequences, classify the incoming task:

1. **Tier 1: Trivial / Direct (Direct Execution by Main Agent)**
   - **Scope:** Editing a few lines to a few files within clear context; reading files; CLI/environment lookups; answering questions; short sequential operations.
   - **Action:** The Main Agent executes directly. ABSOLUTELY DO NOT spawn subagents.

2. **Tier 2: Moderate / Focused Tasks (Direct Execution Preferred, Subagent for SPECIALIZED needs)**
   - **Scope:** Editing 2–5 files in the same module; debugging local errors; writing tests or documentation; narrow-scope refactoring.
   - **Action:** By default, the Main Agent performs the work directly. Only delegate (Single Subagent) when:
     - A deep specialized role is required (e.g. `security-reviewer` for deep security audits, `reviewer` for independent gate review).
     - Or an isolated mock test environment is needed to ensure safety for the host/real environment.

3. **Tier 3: Complex / Multi-system / Broad Investigations (Subagent when PARALLELIZATION is needed)**
   - **Scope:** Large-scale tasks, multiple independent services/repos; complex infrastructure migration; broad system-wide audits.
   - **Action:** The Main Agent acts as Dispatcher & Integrator. Decompose into INDEPENDENT branches and spawn specialized subagents in parallel (`tasks[]`). ABSOLUTELY DO NOT spawn subagents if steps are sequentially dependent or if the Main Agent can handle them directly more efficiently.

Default behavioral guidelines for all workspaces.

---

## Think Before Coding

- State key assumptions briefly. Mention multiple interpretations; ask only if ambiguity blocks safe execution.
- For minor ambiguity, state the safest assumption and continue.
- Prefer simpler approaches. Push back on unnecessary complexity, risk, or unrelated work.
- Implement directly and verify fast. Avoid creating verbose plans when unnecessary.

Create/update a task-tracking `.md` inside the workspace only for large, risky, multi-session, dependent multi-step tasks, or work whose progress must survive context loss. Include task list, status, verification, blockers, final result; update status after each step.

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

- The Main Agent is the central execution hub. Do not overuse subagents for standard tasks.
- Only spawn subagents when the task has clear specialization or multiple independent workstreams requiring parallel execution.
- Avoid sequential chain-of-subagent spawning as it wastes resources and loses context.

### Subagent Role Directory

- `scout`: Rapid reading and codebase exploration when structure or file locations are unfamiliar.
- `security-reviewer`: Security audit, vulnerability scanning, and risk assessment.
- `architect`: System architecture design, high-level planning for large module decomposition.
- `plan-reviewer`: Independent review and gate approval of technical plans (`plan.md`).
- `sonic`: High-speed mechanical edits and bulk data transformations.
- `implementer`: Autonomous coding, TDD following approved design contracts.
- `reviewer`: Code review, architectural standards, convention compliance, test-gate reproduction, and counterexample evaluation.
- `docs-*`: Full lifecycle management of Spec-Driven documentation.

### Multi-Agent Spawning Guidelines

- **Only spawn when truly requiring parallelism:** When facing exploration or execution across multiple independent services/modules simultaneously.
- **Batching:** If spawning multiple subagents, MUST combine them into a single `tasks[]` call, never call them disjointedly.

### Advisor Role Guidelines

- When acting as **Advisor**: Provide passive analysis, architectural critique, edge-case risks, and suggestions only. NEVER issue mutation tool calls (`write`, `edit`, `bash` state changes). Output purely analytical feedback.

## Workspace

Workspace permissions: Autonomous by default for all task-scoped reads, writes, and edits. No confirmation required for standard code changes. Explicit confirmation is required ONLY for Risky Operations: destructive actions (data loss, force push, dropping tables/branches, hard resets, deleting production assets).

---

## Git Worktrees

Allowed only when requested or for approved parallel chunks. Use the exact task/chunk name. No parallel worktree agents unless requested. Delete each worktree only after completion, verification, and merge; leave none orphaned.

---

## Tools

- Use local search/read/terminal and external docs for third-party integrations as needed.
- Don't assume optional tools/services exist; fall back gracefully and report limitations.
- Prefer focused searches/ranges/summaries over entire massive logs or files.
- **File Edit Priority (Hard Constraint):** MANDATORY: modify files with the native `edit`/`write` tools. FORBIDDEN: `python`, `sed`, `awk`, or shell heredocs for file edits — they bypass snapshot safety. If `edit` rejects a stale anchor or snapshot, re-`read` the file section for a fresh one; do NOT fall back to a shell editor.
- **Shell Editor Exception:** shell string-replace tools only for transforms not expressible as line-range edits (bulk regex across many files, generated code). State the reason in one line.

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

For standard CLI commands, builds, and unit tests, execute directly with an appropriate timeout. Reserve structured estimate-and-monitor tracking strictly for long-running asynchronous background jobs (> 3 minutes) or unverified long scripts:

1. Before starting, state the shortest accurate estimate without buffer, set a timeout if supported, and schedule a check at the deadline.
2. At each check: stop safely and report if failed/stalled/not progressing; otherwise give a new shortest estimate and schedule the next check.
3. Verify the real result before claiming success. Never use `sleep` or continuous polling, or leave a task blocking the agent queue.

Background tasks must be finite and non-interactive. Commands that stay open or run continuously (servers, watchers, log streams) must run in a separate system terminal, never an agent background task.
