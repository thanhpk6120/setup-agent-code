# Antigravity CLI - MCP map
# List of MCP servers managed by bootstrap.ps1 (prompt y/N per server).

| Key in templates/settings.json | Command | Notes |
|---|---|---|
| company-atlassian | mcp-atlassian (uvx mcp-atlassian==0.23.1) | Requires JIRA_URL / JIRA_PERSONAL_TOKEN / CONFLUENCE_URL / CONFLUENCE_PERSONAL_TOKEN |
| gitnexus | cmd /c <gitnexus> mcp | Resolves gitnexus path from PATH |
| context7 | node <npm-root>/@upstash/context7-mcp/dist/index.js | Requires CONTEXT7_API_KEY (optional, allows empty) |
| glab | glab mcp serve | Requires glab CLI + GITLAB_TOKEN (optional) |
| cloakbrowser | node <CLOAKBROWSER_DIR>/mcp-server-full.mjs | Copied from mcp-servers/cloakbrowser (if available) |

# Rules
- SkipInstall / DryRun / non-interactive: all MCP servers are stripped from settings.json.
- Memorix: entry `memorix` in settings.json (command `memorix`, args `serve --mode lite`); bootstrap removes `memorix` when disabled, injects `memorix-agents-section.md` into AGENTS.md when enabled, removes when disabled.
