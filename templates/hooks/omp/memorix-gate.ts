// @orca-managed-pi-extension
// Lightweight Memorix gate extension for OMP (Oh My Pi):
// - before_agent_start: once per session, injects a hidden reminder to call MCP `memorix_project_context`.
// - tool_result: displays a compact UI/chat notification whenever a Memorix MCP tool completes.
// - agent_end: if files were edited without a subsequent Memorix save call, sends one followUp reminder.
interface PiContext {
  ui?: { notify?(message: string, level?: 'info' | 'warning' | 'error'): void };
}
interface PiInstance {
  on(event: string, handler: (event: unknown, ctx?: PiContext) => unknown): void;
  sendMessage?(message: { customType: string; content: string; display?: boolean }, options?: { triggerTurn?: boolean }): void | Promise<void>;
  sendUserMessage?(content: string, options?: { deliverAs?: 'steer' | 'followUp' }): void | Promise<void>;
}

const EDIT_TOOLS = new Set(['write', 'edit', 'multiedit', 'patch', 'apply_patch', 'write_file', 'edit_file']);
const MEMORIX_ANY_RE = /(?:^|[_:])memorix_/;
const MEMORIX_LOAD_RE = /(?:^|[_:])memorix_(?:project_context|session_start)$/;
const MEMORIX_SAVE_RE = /(?:^|[_:])memorix_(?:store|store_reasoning|session_end|resolve)$/;

function extractText(raw: unknown): string {
  if (typeof raw === 'string') return raw;
  if (Array.isArray(raw)) return raw.map((x) => extractText(x)).filter(Boolean).join('\n');
  if (raw && typeof raw === 'object') {
    const obj = raw as Record<string, unknown>;
    if (obj.content !== undefined) return extractText(obj.content);
    if (obj.output !== undefined) return extractText(obj.output);
    if (typeof obj.text === 'string') return obj.text;
  }
  return '';
}

function summarizeToolResult(raw: unknown): string {
  const lines = extractText(raw).split(/\r?\n/).map((l) => l.trim()).filter(Boolean).slice(0, 3);
  if (lines.length === 0) return 'executed';
  const joined = lines.join(' | ');
  return joined.length > 200 ? `${joined.slice(0, 197)}...` : joined;
}

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
        content: '[Memorix] Đầu session mới: hãy gọi MCP tool `memorix_project_context` (với mô tả task) ngay trong lượt đầu tiên trước khi đọc sâu codebase hoặc git log (chỉ bỏ qua nếu là chào hỏi/hỏi đáp thuần túy không liên quan workspace).',
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

  pi.on('tool_result', (event: unknown, ctx?: PiContext) => {
    if (process.env.MEMORIX_GATE_ENABLED === '0' || !event || typeof event !== 'object') return;
    const obj = event as Record<string, unknown>;
    const tool = String(obj.toolName || obj.name || '');
    if (!MEMORIX_ANY_RE.test(tool.toLowerCase())) return;
    const shortName = tool.replace(/^.*?(memorix_)/i, '$1');
    const summary = summarizeToolResult(obj.content ?? obj.result ?? obj.output);
    const msg = `[Memorix] ${shortName}: ${summary}`;
    if (typeof pi.sendMessage === 'function') {
      void pi.sendMessage({ customType: 'memorix-gate', content: msg, display: true }, { triggerTurn: false });
    } else {
      ctx?.ui?.notify?.(msg, 'info');
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
