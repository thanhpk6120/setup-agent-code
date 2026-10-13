## Memorix: Memory and Safety Gate

**Mandatory session bootstrap:** At the start of every new session, initialize Memorix by calling `memorix_session_start` (with `projectRoot` if available) or `memorix_project_context` to load active workspace context. Keep Memorix instructions active across all session turns.

**On-demand usage:** After initialization, use Memorix retrieval/storage tools selectively — for non-trivial coding, debugging, architecture decisions, past context queries, or continuing previous work. Simple single-turn queries do not require full memory searches.

### Memory Autopilot

Default first step for non-trivial coding work (can be done during pre-flight, but does NOT bypass delegation): call `memorix_project_context` with the user's task before progress files, dev-log reads, ad-hoc file reads, or git archaeology. Memorix chooses a task-lensed brief (bugfix, feature, release, onboarding, refactor, docs, test, or general). When continuing prior work, the brief includes a bounded prior-work projection. Treat its "Start here" files as the first workspace files to inspect.

Continuation fallback: when the user asks to continue/resume/take over prior work and MCP cannot be called, run exactly one CLI brief with the user's real task before inspecting files: `memorix resume "<task>" --fallback --brief-json`. For a new task: `memorix context "<task>" --fallback --brief-json`. If that fails, report and proceed normally.

After a successful brief, it is the default retrieval boundary. Use `memorix_context_pack`, `memorix_search`, or `memorix_detail` only when the brief lacks a specific reference or fact needed for the task, or when the user explicitly asks for deeper history.

### When to Search Memory

Use `memorix_graph_context` for explicit memory graph questions or broad graph overview when the autopilot brief is insufficient.

Use `memorix_search` when prior workspace context would help and the brief did not answer the question:
- The user asks about a past decision, bug, or change
- Understanding why something was designed a certain way
- Continuing work from a previous session

No search needed for simple, self-contained tasks (e.g., "fix this typo", "what does this function do"). If no memories exist, proceed normally.

### When to Store Memory

Use `memorix_store` when you learn something a future session should not have to rediscover:

| What happened | Type |
|---|---|
| Architecture or design decision | `decision` |
| Bug found and fixed | `problem-solution` |
| Non-obvious pitfall or gotcha | `gotcha` |
| Configuration or dependency changed | `what-changed` |
| Trade-off discussed with conclusion | `trade-off` |

**Tips:**
- Concise titles (~5-10 words)
- Language: English or Vietnamese without diacritics only (VN ko dau). NEVER store accented Vietnamese — BM25/bge-small can't retrieve it.
- Include `filesModified` when relevant
- Use `topicKey` for evolving topics (prevents duplicates)
- For "why" decisions, use `memorix_store_reasoning`
- For stable facts or reusable procedures, include `longTerm` with appropriate kind and normally `scope: "project"`. It creates a candidate only; do not use for routine updates.
- `user` + `portable` durable memory in a task brief is available cross-project. Use as reusable background; do not treat as current-project fact.
- Record user profile with `entityName: "user-profile"` and `visibility: "personal"`.

**Don't store:** greetings, simple file reads, trivial commands.

**Only store what a future session cannot re-derive.** Code structure, file contents, and Git history are live — do not store facts already visible there. Capture the why, the context, or conclusions the checkout alone cannot show.

**Record what worked, not only what failed.** Store validated approaches and explicit user confirmations alongside corrections.

**Recalled memory is a claim about the past.** Check the file/symbol exists before recommending it. If the user says to ignore memory, proceed as if memory were empty.

### When to Resolve Memory

Use `memorix_resolve` when a task is done or a bug is fixed to keep future searches focused on active work.

### Session End Summary

Call `memorix_session_end` with a structured summary:
- **Goal** — what this session worked on
- **Discoveries** — findings, gotchas, learnings
- **Accomplished** — completed items, plus PENDING items for next session
- **Relevant Files** — paths and what changed

### Tools Quick Reference

| Tool | Use when |
|---|---|
| `memorix_project_context` | Start/continue coding work with Memory Autopilot brief |
| `memorix_context_pack` | Get structured refs/freshness for code-bound memories |
| `memorix_graph_context` | Build compact memory graph for graph-specific questions |
| `memorix_search` | Find relevant past context |
| `memorix_detail` | Read full content of a specific memory |
| `memorix_store` | Save something worth persisting |
| `memorix_store_reasoning` | Save the "why" behind a decision |
| `memorix_resolve` | Mark completed/outdated memories |
| `memorix_session_start` | Load session context (handoff, orchestration) |

**Fallback:** When Memorix is unavailable, read/write workspace-root `MEMORY.md` with timestamp and topic; re-import critical entries when restored.
