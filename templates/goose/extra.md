# Goose Agent Guidelines

- Operate autonomously with direct, surgical code modifications.
- Prioritize built-in tools and configured MCP extensions before falling back to generic shell commands.
- Keep execution verifiable: verify every change before yielding.
- Respect project-scoped context files (.goosehints) alongside global instructions.
- **Subagents & parallelism:** Use Goose subagents or subrecipes to isolate context or parallelize independent exploration/tasks instead of relying on fixed external role names.
