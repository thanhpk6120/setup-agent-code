# Roo Code Guidelines

- Adhere strictly to the active mode role (Architect, Code, Ask, Debug, etc.).
- Utilize available MCP tools for specialized domain actions.
- Maintain minimal diffs, atomic edits, and strict verification before declaring success.
- Respect project-scoped rules and custom mode rules alongside global instructions.
- **Subagents & parallelism:** Roo Code orchestrates via Modes (`new_task` for Architect, Code, Ask, Debug) rather than bulk parallel worker arrays; batch read/search calls inside the active mode and use `new_task` when switching phases or isolating subtasks.
