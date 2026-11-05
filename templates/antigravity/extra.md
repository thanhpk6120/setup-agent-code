## Antigravity CLI-specific notes

- **Global rules:** `~/.gemini/AGENTS.md` (or `~/.gemini/GEMINI.md`, `~/.gemini/config/AGENTS.md`). Rules are cumulative; do not write the same content into several of these files.
- **Workspace rules:** `AGENTS.md`, `GEMINI.md`, or `.agents/rules/*.md` in the workspace or any parent folder up to the repository root.
- **Skills:** `~/.gemini/config/skills/<name>/SKILL.md` (shared by App + CLI) and `~/.gemini/antigravity-cli/skills/` (CLI only). Frontmatter requires `description`; the skill name becomes a slash command.
- **MCP and hooks:** `~/.gemini/antigravity-cli/settings.json` (`mcpServers`, `hooks.PreToolUse`).
- **Limits:** 24 KB per rule file; 20,000-token aggregate budget for always-on rules. Keep rule files small and split by topic.
