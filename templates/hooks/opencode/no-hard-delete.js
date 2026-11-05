// @opencode-plugin: no-hard-delete
// Block every permanent (hard delete) file/directory deletion. Always move to Trash / Recycle Bin instead.

const HARD_DELETE_PATTERN = /(?:^|[;&|`\s])(?:rm\s|rmdir\s|del\s|erase\s|rd\s|ri\s|Remove-Item\s|unlink\s|shred\s)/i;
const BLOCK_REASON = "[BLOCKED] Hard delete blocked! TOP-PRIORITY RULE: NEVER hard-delete files/directories. You MUST move them to Trash ('trash <path>' or Recycle Bin).";

function checkCommand(cmd) {
  if (typeof cmd === "string" && HARD_DELETE_PATTERN.test(cmd)) {
    return {
      block: true,
      reason: BLOCK_REASON,
    };
  }
  return null;
}

// Plugin interface cho OpenCode
export default function noHardDeletePlugin(context) {
  // Listen for tool_call / pre_tool events
  if (context && typeof context.on === "function") {
    context.on("tool_call", async (event) => {
      let cmd = "";
      if (event && typeof event === "object") {
        const input = event.input;
        if (typeof input === "string") {
          cmd = input;
        } else if (input && typeof input === "object") {
          cmd = input.command || input.cmd || "";
        }
      }
      return checkCommand(cmd);
    });

    context.on("before_tool_execute", async (event) => {
      const cmd = event?.params?.command || event?.params?.cmd || "";
      return checkCommand(cmd);
    });
  }

  return {
    name: "no-hard-delete",
    hooks: {
      beforeToolExecution: async (tool, params) => {
        const cmd = params?.command || params?.cmd || (typeof params === "string" ? params : "");
        const check = checkCommand(cmd);
        if (check && check.block) {
          throw new Error(check.reason);
        }
      },
    },
  };
}
