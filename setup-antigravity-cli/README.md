# Setup Antigravity CLI (Google agy)

Automation toolset to configure the environment for **Antigravity CLI** (Google Gemini agy).

## Destination Directory Structure
- `~/.gemini/antigravity-cli/settings.json` (agent configuration, MCP servers, permissions, telemetry)
- `~/.gemini/antigravity-cli/keybindings.json` (keyboard shortcuts for artifact review and cancellation)
- `~/.gemini/antigravity-cli/AGENTS.md` (standard agent operating instructions)
- `~/.gemini/antigravity-cli/skills/` (standard skill repository shared with setup-omp)
- `~/.gemini/antigravity-cli/hooks/` (hooks enforcing trash-guard safe file deletion)

## Installation
Before running, optionally initialize a `.env` file from the template:
```powershell
copy templates\.env.example .env
```

```powershell
# Interactive install via wrapper
.\install.ps1

# Or run bootstrap directly with parameters
.\bootstrap.ps1 -Force
```
