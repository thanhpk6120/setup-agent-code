## Claude Code-specific notes

- **Memory file:** `~/.claude/CLAUDE.md` (user scope). Project scope uses `./CLAUDE.md` or `./.claude/CLAUDE.md`. `AGENTS.md` is only read at project scope (v2.1.277+) — do not duplicate it at the user scope.
- **Modular rules:** `~/.claude/rules/*.md` loads with the same priority as `CLAUDE.md`; path-scoped rules use `paths:` frontmatter.
- **Skills:** `~/.claude/skills/<name>/SKILL.md` (also read by OpenCode when Claude compatibility is enabled).
- **MCP:** `~/.claude.json` (`mcpServers`). Settings, permissions, model aliases and env live in `~/.claude/settings.json`.
- **Hooks:** `PreToolUse` in `settings.json`; the trash-guard handler runs through `node`.
- **Size:** keep `CLAUDE.md` under ~200 lines; move task-specific procedures into skills or rules to preserve adherence.
