# Agent Instructions

> **[CRITICAL INSTRUCTION: FULL COMPLIANCE REQUIRED.]**
> Read and follow all applicable instructions without truncating code (`...`) or skipping required checks.

## Execution & Subagent Delegation

Choose the fastest safe execution path based on task independence rather than defaulting everything to sequential work:

- **Direct Execution:** Handle small, well-scoped tasks (editing 1–2 known files, simple lookups) or **sequentially dependent steps** (`B` requires `A`'s output) directly on the Main Agent. Batch independent `read`/`grep`/`glob` tool calls in the same turn.
- **Parallel Subagents (Encouraged for Speed):** When there are `>= 2` **independent** workstreams that do not edit the same files, spawn subagents concurrently in a **single batch**:
  - Broad exploration across unfamiliar codebase areas or distinct subsystems.
  - Independent implementation, test authoring, or documentation across separate files/modules.
  - Independent verification: code review, security audit, or spec/doc fact-checking in a clean context.
- **Anti-patterns (Avoid):** Do not chain subagents sequentially (`subagent A -> wait -> subagent B` for dependent steps), keep fan-out flat (avoid deep nested spawning), and do not spawn a subagent to read or edit a single already-known file.
- **Conceptual Roles:**
  - *Explorer*: fast read-only mapping when file locations or call flows are unknown.
  - *Worker*: independent implementation, mechanical bulk edits, or isolated test execution.
  - *Reviewer / Security / Docs*: independent audit, gate check, or documentation sync.
  - *Advisor*: passive analysis and critique only; NEVER issue mutation tool calls (`write`, `edit`, state-changing shell commands).
  - Use the exact subagent tool and role names supported by the active runtime (see the agent-specific section below).

---

## Think Before Coding

- State key assumptions briefly. Mention multiple interpretations; ask only if ambiguity blocks safe execution; otherwise pick the safest assumption and proceed.
- Prefer simpler approaches. Push back on unnecessary complexity, risk, or unrelated work.
- Implement directly and verify fast. Avoid verbose plans when unnecessary.
- Create/update a workspace task-tracking `.md` only for large, risky, multi-session, or multi-step tasks whose progress must survive context loss.

---

## Simplicity & Surgical Changes

- Write the minimum code that solves the request; touch only what is required.
- No unrequested features, abstractions, configurability, or impossible-case error handling.
- Mention unrelated dead code without deleting it; remove only code your change made unused.

---

## Goal-Driven Execution & Communication

- Define success criteria and verify before yielding. Do not stop mid-task unless blocked by destructive-risk confirmation, missing permissions, critical missing files, or unrecoverable failures.
- Do not ask confirmation for obvious non-destructive steps; suggest improvements after completing the request.

---

## Workspace

Workspace permissions: Autonomous by default for all task-scoped reads, writes, and edits. No confirmation required for standard code changes. Explicit confirmation is required ONLY for Risky Operations: destructive actions (data loss, force push, dropping tables/branches, hard resets, deleting production assets).

---

## Git Worktrees

Allowed when requested or when parallel workers must isolate overlapping edits on separate branches. Use the exact task/chunk name, and delete each worktree only after completion, verification, and merge.

---

## Tools

- Use local search/read/terminal and external docs for third-party integrations as needed; don't assume optional tools/services exist.
- Prefer focused searches/ranges/summaries over massive files or logs.
- **File Edit Priority (Hard Constraint):** Modify files with native `edit`/`write` tools. FORBIDDEN: `python`, `sed`, `awk`, or shell heredocs for file edits (they bypass snapshot safety). Re-`read` on stale anchor rather than falling back to shell editors.
- **Shell Editor Exception:** Shell string-replace tools only for transforms not expressible as line-range edits (bulk regex across many files, generated code); state the reason in one line.

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
