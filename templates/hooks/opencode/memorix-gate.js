// @opencode-plugin: memorix-gate
// OpenCode v2 plugin:
// - context: once per session, appends a reminder to call MCP `memorix_project_context`.
// - experimental.idle: if the session edited files without a subsequent Memorix save call, sends one synthetic reminder.
import { Plugin } from '@opencode/plugin';

const EDIT_TOOLS = new Set(['write', 'edit', 'multiedit', 'patch', 'apply_patch']);
const MEMORIX_LOAD_RE = /(?:^|[_:])memorix_(?:project_context|session_start)$/;
const MEMORIX_SAVE_RE = /(?:^|[_:])memorix_(?:store|store_reasoning|session_end|resolve)$/;

export default Plugin.define({
  id: 'memorix-gate',
  async setup(ctx) {
    const loadedSessions = new Set();
    const remindedStart = new Set();
    const editState = new Map();

    await ctx.session.hook('context', (event) => {
      if (process.env.MEMORIX_GATE_ENABLED === '0') return;
      if (!event?.sessionID) return;
      if (loadedSessions.has(event.sessionID) || remindedStart.has(event.sessionID)) return;
      remindedStart.add(event.sessionID);
      if (Array.isArray(event.system)) {
        event.system.push({
          text: '[Memorix] Đầu session mới: nếu tác vụ này liên quan đến repo/code hoặc tiếp tục công việc cũ, hãy gọi MCP tool `memorix_project_context` (với mô tả task) trước khi đọc sâu codebase.'
        });
      }
    });

    await ctx.tool.hook('execute.after', (event) => {
      if (event.status !== 'completed' || !event.sessionID) return;
      const tool = String(event.tool || '').toLowerCase();
      if (MEMORIX_LOAD_RE.test(tool)) {
        loadedSessions.add(event.sessionID);
        return;
      }
      if (MEMORIX_SAVE_RE.test(tool)) {
        editState.delete(event.sessionID);
        return;
      }
      if (EDIT_TOOLS.has(tool)) {
        editState.set(event.sessionID, { dirty: true, blockedOnce: false });
      }
    });

    await ctx.session.hook('experimental.idle', async (event) => {
      if (process.env.MEMORIX_GATE_ENABLED === '0') {
        editState.delete(event.sessionID);
        return;
      }
      if (Array.isArray(event.background) && event.background.length > 0) return;
      const st = editState.get(event.sessionID);
      if (!st || !st.dirty) return;
      if (st.blockedOnce) {
        editState.delete(event.sessionID);
        return;
      }

      st.blockedOnce = true;
      await ctx.session.synthetic({
        sessionID: event.sessionID,
        text: '[Memorix Gate] Bạn vừa thay đổi file trong lượt này nhưng chưa cập nhật bộ nhớ phiên. Nếu có quyết định kỹ thuật, bugfix, thay đổi cấu hình hoặc kết quả quan trọng cần nhớ cho phiên sau, hãy gọi MCP `memorix_store` hoặc `memorix_session_end` trước khi kết thúc (nếu chỉ là sửa nhỏ không đáng lưu, hãy trả lời ngắn gọn để hoàn tất).'
      });
    });
  }
});
