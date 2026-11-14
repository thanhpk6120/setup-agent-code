## DSH-specific notes

- **Instructions:** `~/.dsh/AGENTS.md` (user scope). Workspace `AGENTS.md` files add project-level context.
- **Skills:** `~/.dsh/skills/<name>/SKILL.md`.
- **Profile config:** `~/.dsh/profiles/<profile>/cordis.patch.yml` (default profile: `web`). The MCP clients are `@deepseek-ai/dsh-mcp-client` entries with `serverName`, `transport: stdio`, `command`, `args`, `env`.
- **Credentials:** `%APPDATA%\dsh-desktop\harness\.credentials.yaml` on Windows, `~/.dsh/.credentials.yaml` elsewhere. Schema: `version`, `refs`, `apiKey`, `records`. Never print secret values.
- **Hooks:** Memorix hooks are installed with `memorix hooks install --agent dsh --global`; verify the exit code instead of assuming success.
- **Subagents & parallelism:** `cordis.patch.yml` allows high concurrency (`maxActiveSubagents: 32`, `maxDepth: 6`); fan out independent streams in parallel at shallow depth (prefer 1 level) and match model to difficulty (`deepseek-flash` for fast search/mechanical work, `deepseek-v4-pro` for deep reasoning/review).
