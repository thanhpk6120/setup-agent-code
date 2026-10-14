# Agent Instructions

> **[CRITICAL INSTRUCTION: READ TO THE END. DO NOT IGNORE ANY RULE. DO NOT TRUNCATE CODE (NO `...` PLACEHOLDERS). FULL COMPLIANCE REQUIRED.]**
> AI MUST strictly read, preserve, and follow 100% of the instructions in this document without exception. NEVER truncate, omit, skip, or summarize away any section. Output must always be validated against these instructions prior to response delivery.

## Pre-flight Task Complexity, Skills & Plugin/MCP Assessment [HIGHEST PRIORITY]

**[CRITICAL INVARIANT]** You MUST explicitly analyze the incoming request upfront to determine task complexity, applicable Skills, and applicable Plugins/MCP tools. Decide whether to spawn specialized subagents or use the main agent directly.
- **CORE PRINCIPLE:** The Main Agent is the primary executor (Default: Direct Execution). Minimize indiscriminate subagent spawning. Spawn subagents ONLY when a task is genuinely specialized, or when branches of work are truly independent and need to run in parallel.
- **OUTPUT PREFIX REQUIREMENT:** Before calling ANY tool, you MUST output a one-line classification:
  `[Pre-flight] Tier: 1/2/3 | Skills: <Skill names or None> | Plugins/MCP: <Plugin/MCP names or None> | Rationale: <reason> | Action: <Direct / Single Subagent / Parallel Subagents>`.

### Mandatory Tool & Skill Resolution:
- **Skills (`skills/*/SKILL.md`):** E.g. `create-plan`, `implement-task`, `init-docs`, `delivery`, `security-review`. If a task matches a skill's intent, MUST use it instead of ad-hoc steps.
- **Plugins / MCP Tools:** Always check the list of MCP tools available in the environment to prioritize the right tool for the domain (e.g., tools for code graph/symbol, project memory, browser automation, issue tracking, docs, library lookup...). *NEVER use generic `bash`/`grep`/`curl` if a dedicated Plugin/MCP handles the domain.*

Before executing actions or calling tool sequences, classify the incoming task:

1. **Tier 1: Trivial / Direct (Direct Execution by Main Agent)**
   - **Scope:** Edits of a few lines to a few files within a clear context; file reads; CLI/environment lookups; answering questions; short sequential operations.
   - **Action:** The Main Agent executes directly. NEVER spawn subagents.

2. **Tier 2: Moderate / Focused Tasks (Direct Execution first, Subagent only when SPECIALIZED)**
   - **Scope:** Editing 2–5 files in the same module; local bug debugging; writing tests or docs; narrow-scope refactors.
   - **Action:** The Main Agent does it by default. Delegate (Single Subagent) only when:
     - Deep specialized expertise is needed (e.g., `security-reviewer` for in-depth security scanning, `reviewer` for independent quality-gate checks).
     - Or an isolated simulated test environment is needed to guarantee absolute safety for the real server/environment.

3. **Tier 3: Complex / Multi-system / Broad Investigations (Subagents only for PARALLELIZATION)**
   - **Scope:** Large-scale tasks, many independent services/repos; complex infra migrations; large system-wide review waves.
   - **Action:** The Main Agent acts as Dispatcher & Integrator. Decompose into INDEPENDENT branches and spawn dedicated subagents in parallel (`tasks[]`). NEVER spawn subagents when steps are sequentially dependent or when the Main Agent can handle them directly and more efficiently.

Default behavioral guidelines for all workspaces.

---

## Think Before Coding

- State key assumptions briefly. Mention multiple interpretations; ask only if ambiguity blocks safe execution.
- For minor ambiguity, state the safest assumption and continue.
- Prefer simpler approaches. Push back on unnecessary complexity, risk, or unrelated work.
- Implement directly and verify fast. Avoid creating elaborate plans when unnecessary.

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
- The Main Agent is the central processor. Do not overuse subagent spawning for ordinary tasks.
- Spawn subagents only when a task is clearly specialized or has multiple independent work streams needing parallel handling.
- Avoid spawning sequentially dependent subagent chains because they waste resources and lose context.

### Subagent Role Directory
- `scout`: Fast read-only exploration and broad codebase surveys when structure or file locations are unclear.
- `reviewer`: Code quality review, architecture standards, and convention compliance.
- `security-reviewer`: Security review, vulnerability scanning, and safety risks.
- `architect`: Overall architecture design and large-module decomposition planning.
- `plan-reviewer`: Independent review and approval of technical plans (`plan.md`).
- `sonic`: Fast mechanical edits and bulk data transformations.
- `implementer`: Autonomous coding with TDD per the approved design contract.
- `reviewer`: Independent code review, test-gate checks, and edge cases.
- `docs-*`: Spec-Driven documentation lifecycle management.

### Multi-Agent Spawning Guidelines
- **Spawn only when parallelism is truly needed:** When surveying or executing across multiple independent services/modules at the same time.
- **Batch together:** When spawning multiple subagents, they MUST be grouped into a single `tasks[]` call, never issued separately.

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
- **MCP Route & Priority (Hard Constraints):** You MUST prioritize the dedicated MCP tools matching the task domain. **FORBIDDEN** to abuse `bash` (grep, find, awk, curl) or native tools when the tool list already has an MCP tool serving that function.
- **Fallback Rule:** Use bash/native tools as substitutes only when MCP reports unavailable or the user mandates it.

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
