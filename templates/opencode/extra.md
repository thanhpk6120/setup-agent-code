## OpenCode-specific notes

- **Rules:** `~/.config/opencode/AGENTS.md` is the global rule file. `CLAUDE.md` is only a fallback (disable with `OPENCODE_DISABLE_CLAUDE_CODE=1`). Extra files can be listed in the `instructions` array of `opencode.json`.
- **Skills:** `~/.config/opencode/skills/<name>/SKILL.md`; frontmatter MUST contain `name` and `description`, and `name` must equal the folder name.
- **MCP:** `~/.config/opencode/opencode.json` under `mcp`, shape `{ type: "local", command: [bin, ...args], environment: {...} }`.
- **Plugins:** `plugin` array in `opencode.json`; the bundled `no-hard-delete` plugin blocks hard-delete commands.
- **Permissions:** `permission.bash` / `permission.skill` patterns are enforced before tool execution — prefer them over prose rules when the action must be blocked.
