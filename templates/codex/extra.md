## Codex CLI-specific notes

- **Instructions:** `~/.codex/AGENTS.md` (user scope) plus a project `AGENTS.md`. `CODEX.md` is not a global instruction filename — do not create it.
- **Config:** `~/.codex/config.toml` holds the model provider and `[mcp_servers.<name>]` blocks.
- **Skills:** `~/.codex/skills/<name>/SKILL.md`; the skill list is injected automatically.
- **Sandboxing:** Codex runs commands inside its sandbox — write operations outside the workspace fail by design. Report the sandbox limitation instead of retrying with elevated flags.
- **Approval modes:** respect the configured approval policy; never assume unattended execution.
- **Subagents & parallelism:** Fan out independent exploration or non-overlapping tasks when subagent tools are available in the active Codex session; otherwise batch parallel read/search calls directly.
