// @orca-managed-pi-extension
// Lightweight Memorix gate extension for OMP (Oh My Pi):
// - before_agent_start: once per session, injects a hidden reminder to call MCP `memorix_project_context`.
// - agent_end: if files were edited without a subsequent Memorix save call, sends one followUp reminder.
interface PiInstance {
  on(event: string, handler: (event: unknown) => unknown): void;
  sendUserMessage?(content: string, options?: { deliverAs?: 'steer' | 'followUp' }): void | Promise<void>;
}

const EDIT_TOOLS = new Set(['write', 'edit', 'multiedit', 'patch', 'apply_patch', 'write_file', 'edit_file']);
const MEMORIX_LOAD_RE = /(?:^|[_:])memorix_(?:project_context|session_start)$/;
const MEMORIX_SAVE_RE = /(?:^|[_:])memorix_(?:store|store_reasoning|session_end|resolve)$/;

export default function (pi: PiInstance) {
  let seenStart = false;
  let dirty = false;
  let blockedOnce = false;

  pi.on('session_start', () => {
    seenStart = false;
    dirty = false;
    blockedOnce = false;
  });

  pi.on('before_agent_start', () => {
    if (process.env.MEMORIX_GATE_ENABLED === '0' || seenStart) return;
    seenStart = true;
    return {
      message: {
        customType: 'memorix-gate',
        content: '[Memorix] Đầu session mới: nếu tác vụ này liên quan đến repo/code hoặc tiếp tục công việc cũ, hãy gọi MCP tool `memorix_project_context` (với mô tả task) trước khi đọc sâu codebase.',
        display: false
      }
    };
  });

  pi.on('tool_call', (event: unknown) => {
    if (!event || typeof event !== 'object') return;
    const obj = event as Record<string, unknown>;
    const tool = String(obj.toolName || obj.name || '').toLowerCase();
    if (!tool) return;
    if (MEMORIX_LOAD_RE.test(tool)) {
      seenStart = true;
      return;
    }
    if (MEMORIX_SAVE_RE.test(tool)) {
      dirty = false;
      blockedOnce = false;
      return;
    }
    if (EDIT_TOOLS.has(tool)) {
      dirty = true;
      blockedOnce = false;
    }
  });

  pi.on('agent_end', () => {
    if (process.env.MEMORIX_GATE_ENABLED === '0' || !dirty) return;
    if (blockedOnce) {
      dirty = false;
      blockedOnce = false;
      return;
    }
    blockedOnce = true;
    if (typeof pi.sendUserMessage === 'function') {
      return pi.sendUserMessage(
        '[Memorix Gate] Bạn vừa thay đổi file trong lượt này nhưng chưa cập nhật bộ nhớ phiên. Nếu có quyết định kỹ thuật, bugfix, thay đổi cấu hình hoặc kết quả quan trọng cần nhớ cho phiên sau, hãy gọi MCP `memorix_store` hoặc `memorix_session_end` trước khi kết thúc (nếu chỉ là sửa nhỏ không đáng lưu, hãy trả lời ngắn gọn để hoàn tất).',
        { deliverAs: 'followUp' }
      );
    }
  });
}
