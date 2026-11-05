## OMP-specific notes

- **Context vs sticky rules:** `~/.omp/agent/AGENTS.md` is session-opening context; `~/.omp/agent/RULES.md` is an always-apply sticky rule. Task subagents drop every `AGENTS.md` but still receive `RULES.md` — put anything helpers MUST follow in `RULES.md`.
- **Do not install `SYSTEM.md`:** a discovered `~/.omp/agent/SYSTEM.md` replaces OMP's entire default instruction block (tool inventory, tool policy, workflow, personality). Use `APPEND_SYSTEM.md` when you only want to add text.
- **Skills:** `~/.omp/agent/skills/<name>/SKILL.md`; OMP injects the skill catalog automatically but respects `disabledProviders` / `disabledExtensions` in `config.yml`.
- **MCP:** `~/.omp/agent/mcp.json` (`mcpServers`), managed together with `config.yml` and `models.yml`.
- **Imports:** `@path` tokens inside context files are expanded at load time; prefer many small files over one huge `AGENTS.md`.
