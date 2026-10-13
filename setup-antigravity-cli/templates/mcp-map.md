# Antigravity CLI - MCP map
# Danh sach MCP server duoc bootstrap.ps1 quan ly (chon y/N tung server).

| Key trong templates/settings.json | Command | Ghi chu |
|---|---|---|
| company-atlassian | mcp-atlassian (uvx mcp-atlassian==0.23.1) | Can JIRA_URL / JIRA_PERSONAL_TOKEN / CONFLUENCE_URL / CONFLUENCE_PERSONAL_TOKEN |
| gitnexus | cmd /c <gitnexus> mcp | Do duong dan gitnexus tu PATH |
| context7 | node <npm-root>/@upstash/context7-mcp/dist/index.js | Can CONTEXT7_API_KEY (optional, cho phep rong) |
| glab | glab mcp serve | Can glab CLI + GITLAB_TOKEN (optional) |
| cloakbrowser | node <CLOAKBROWSER_DIR>/mcp-server-full.mjs | Copy tu mcp-servers/cloakbrowser (neu co) |

# Quy tac
- SkipInstall / DryRun / non-interactive: tat ca MCP bi loai khoi settings.json.
- Memorix: khong phai MCP entry trong settings.json; cau hinh qua `memorix hooks install --agent antigravity --global` (neu CLI ho tro) hoac bo qua.
