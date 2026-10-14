// @opencode-plugin: no-hard-delete
// Block every permanent (hard delete) file/directory deletion. Always move to Trash / Recycle Bin instead.

interface OpenCodePluginContext {
  on?(event: string, handler: (event: unknown) => unknown): void;
}

const HARD_DELETE_PATTERN = /(?:^|[;&|`\s])(?:rm\s|rmdir\s|del\s|erase\s|rd\s|ri\s|Remove-Item\s|unlink\s|shred\s)/i;
const BLOCK_REASON = "[BLOCKED] Hard delete blocked! TOP-PRIORITY RULE: NEVER hard-delete files/directories. You MUST move them to Trash ('trash <path>' or Recycle Bin).";

function checkCommand(cmd: unknown): { block: boolean; reason: string } | null {
  if (typeof cmd === "string" && HARD_DELETE_PATTERN.test(cmd)) {
    return {
      block: true,
      reason: BLOCK_REASON,
    };
  }
  return null;
}

export default function noHardDeletePlugin(context?: OpenCodePluginContext) {
  if (context && typeof context.on === "function") {
    context.on("tool_call", async (event: unknown) => {
      let cmd = "";
      if (event && typeof event === "object") {
        const input = (event as Record<string, unknown>).input;
        if (typeof input === "string") {
          cmd = input;
        } else if (input && typeof input === "object") {
          const obj = input as Record<string, unknown>;
          cmd = (obj.command as string) || (obj.cmd as string) || "";
        }
      }
      return checkCommand(cmd);
    });

    context.on("before_tool_execute", async (event: unknown) => {
      const ev = event as Record<string, unknown>;
      const params = ev?.params as Record<string, unknown>;
      const cmd = (params?.command as string) || (params?.cmd as string) || "";
      return checkCommand(cmd);
    });
  }

  return {
    name: "no-hard-delete",
    hooks: {
      beforeToolExecution: async (_tool: string, params: unknown) => {
        const p = params as Record<string, unknown>;
        const cmd = p?.command || p?.cmd || (typeof params === "string" ? params : "");
        const check = checkCommand(cmd);
        if (check && check.block) {
          throw new Error(check.reason);
        }
      },
    },
  };
}
