// @opencode-plugin: no-hard-delete
// Block every permanent (hard delete) file/directory deletion. Always move to Trash / Recycle Bin instead.
// OpenCode v2 plugin: needs @opencode/plugin + "type": "module" in the config dir package.json.
import { Plugin } from "@opencode/plugin"

const HARD_DELETE_PATTERN = /(?:^|[;&|`\s])(?:rm|rmdir|del|erase|rd|ri|remove-item|unlink|shred)\s/i
const BLOCK_REASON = "[BLOCKED] Hard delete blocked! TOP-PRIORITY RULE: NEVER hard-delete files/directories. You MUST move them to Trash ('trash <path>' or Recycle Bin)."

export default Plugin.define({
  id: "no-hard-delete",
  async setup(ctx) {
    await ctx.permission.hook("evaluate", (event) => {
      if (event.action !== "shell") return
      const resources = event.resources ?? []
      if (!resources.some((r) => HARD_DELETE_PATTERN.test(String(r)))) return
      event.effect = "deny"
      event.message = BLOCK_REASON
    })
  },
})
