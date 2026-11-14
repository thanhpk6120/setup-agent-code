## OpenCode-specific notes

- **Rules:** `~/.config/opencode/AGENTS.md` is the global rule file. `CLAUDE.md` is only a fallback (disable with `OPENCODE_DISABLE_CLAUDE_CODE=1`). Extra files can be listed in the `instructions` array of `opencode.json`.
- **Skills:** `~/.config/opencode/skills/<name>/SKILL.md`; frontmatter MUST contain `name` and `description`, and `name` must equal the folder name.
- **MCP:** `~/.config/opencode/opencode.json` under `mcp`, shape `{ type: "local", command: [bin, ...args], environment: {...} }`.
- **Plugins:** v2 auto-discovers `plugins/*.js`. Do NOT add a `plugin` array with a file path (fails with "configured plugin path must be a directory"). A plugin exports `Plugin.define({ id, setup })` from `@opencode/plugin`, and the config dir `package.json` needs `"type": "module"` + that dependency. The bundled `no-hard-delete` plugin blocks hard-delete commands.
- **Permissions:** v2 uses `permissions: [{ action, resource, effect }]`; the LAST matching rule wins, so deny rules go after the catch-all `ask` rule.
- **Subagents & parallelism:** Batch independent `task`/subagent calls in the same turn for parallel exploration or non-overlapping edits; configured `permissions` and `no-hard-delete.js` still apply to all shell calls.
