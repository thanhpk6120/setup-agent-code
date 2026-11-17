// @opencode-plugin: memorix-gate
// OpenCode v2 plugin:
// - context: once per session, appends a reminder to call MCP `memorix_project_context`.
// - experimental.idle: if the session edited files without a subsequent Memorix save call, sends one synthetic reminder.
import { Plugin } from '@opencode/plugin';

const EDIT_TOOLS = new Set(['write', 'edit', 'multiedit', 'patch', 'apply_patch']);
const MEMORIX_ANY_RE = /(?:^|[_:])memorix_/;
const MEMORIX_LOAD_RE = /(?:^|[_:])memorix_(?:project_context|session_start)$/;
const MEMORIX_SAVE_RE = /(?:^|[_:])memorix_(?:store|store_reasoning|session_end|resolve)$/;

function extractText(raw) {
  if (typeof raw === 'string') return raw;
  if (Array.isArray(raw)) return raw.map((x) => extractText(x)).filter(Boolean).join('\n');
  if (raw && typeof raw === 'object') {
    if (raw.content !== undefined) return extractText(raw.content);
    if (raw.output !== undefined) return extractText(raw.output);
    if (typeof raw.text === 'string') return raw.text;
  }
  return '';
}

function summarizeOutput(raw) {
  const lines = extractText(raw).split(/\r?\n/).map((l) => l.trim()).filter(Boolean).slice(0, 3);
  if (lines.length === 0) return 'executed';
  const joined = lines.join(' | ');
  return joined.length > 200 ? `${joined.slice(0, 197)}...` : joined;
}

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
          text: '[Memorix] Đầu session mới: hãy gọi MCP tool `memorix_project_context` (với mô tả task) ngay trong lượt đầu tiên trước khi đọc sâu codebase hoặc git log (chỉ bỏ qua nếu là chào hỏi/hỏi đáp thuần túy không liên quan workspace).'
        });
      }
    });

    await ctx.tool.hook('execute.after', async (event) => {
      if (event.status !== 'completed' || !event.sessionID) return;
      const tool = String(event.tool || '').toLowerCase();
      if (MEMORIX_ANY_RE.test(tool)) {
        const shortName = String(event.tool || '').replace(/^.*?(memorix_)/i, '$1');
        const msg = `[Memorix] ${shortName}: ${summarizeOutput(event.output ?? event.result ?? event.metadata?.output)}`;
        try {
          if (typeof ctx?.tui?.showToast === 'function') {
            await ctx.tui.showToast({ message: msg, variant: 'info' });
          } else if (typeof ctx?.client?.tui?.showToast === 'function') {
            await ctx.client.tui.showToast({ body: { message: msg, variant: 'info' } });
          } else if (typeof ctx?.ui?.notify === 'function') {
            await ctx.ui.notify(msg, 'info');
          }
        } catch {}
      }
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
