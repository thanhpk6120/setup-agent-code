// @opencode-plugin: review-gate
// OpenCode v2 plugin: prompts for a fast independent subagent review before going idle
// whenever the session edited non-trivial files without a subsequent subagent check.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Plugin } from '@opencode/plugin';

const DEFAULT_CONFIG = { enabled: true, model: 'inherit' };
const EDIT_TOOLS = new Set(['write', 'edit', 'multiedit', 'patch', 'apply_patch']);
const REVIEW_TOOLS = new Set(['task', 'agent', 'subagent']);
const DOC_ONLY_EXTS = new Set(['.md', '.txt', '.mdx']);

function getConfigPath() {
  if (process.env.OPENCODE_REVIEW_GATE_CONFIG) return process.env.OPENCODE_REVIEW_GATE_CONFIG;
  return path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'review-gate.json');
}

function loadConfig() {
  try {
    const raw = fs.readFileSync(getConfigPath(), 'utf8');
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') return { ...DEFAULT_CONFIG };
    const enabled = typeof parsed.enabled === 'boolean' ? parsed.enabled : DEFAULT_CONFIG.enabled;
    const rawModel = typeof parsed.model === 'string' ? parsed.model.trim() : '';
    const model = rawModel && !/\s/.test(rawModel) ? rawModel : DEFAULT_CONFIG.model;
    return { enabled, model };
  } catch {
    return { ...DEFAULT_CONFIG };
  }
}

function extractPath(input) {
  if (!input || typeof input !== 'object') return '';
  return String(input.filePath || input.path || input.file || input.TargetFile || '');
}

export default Plugin.define({
  id: 'review-gate',
  async setup(ctx) {
    const sessions = new Map();

    const getState = (sessionID) => {
      let st = sessions.get(sessionID);
      if (!st) {
        st = { files: new Set(), unknownEdit: false, blockedOnce: false };
        sessions.set(sessionID, st);
      }
      return st;
    };

    await ctx.tool.hook('execute.after', (event) => {
      if (event.status !== 'completed') return;
      const tool = String(event.tool || '').toLowerCase();
      if (REVIEW_TOOLS.has(tool)) {
        sessions.delete(event.sessionID);
        return;
      }
      if (EDIT_TOOLS.has(tool)) {
        const st = getState(event.sessionID);
        st.blockedOnce = false;
        const p = extractPath(event.input);
        if (p) st.files.add(p);
        else st.unknownEdit = true;
      }
    });

    await ctx.session.hook('experimental.idle', async (event) => {
      const config = loadConfig();
      if (!config.enabled) {
        sessions.delete(event.sessionID);
        return;
      }
      if (Array.isArray(event.background) && event.background.length > 0) return;

      const st = sessions.get(event.sessionID);
      if (!st || (st.files.size === 0 && !st.unknownEdit)) return;
      if (st.blockedOnce) {
        sessions.delete(event.sessionID);
        return;
      }

      const files = [...st.files];
      if (!st.unknownEdit && files.length === 1) {
        const ext = path.extname(files[0]).toLowerCase();
        if (DOC_ONLY_EXTS.has(ext)) {
          sessions.delete(event.sessionID);
          return;
        }
      }

      st.blockedOnce = true;
      const targetHint = files.length ? ` (${files.map((f) => path.basename(f)).join(', ')})` : '';
      const modelHint = config.model === 'inherit' ? 'model mặc định (`inherit`)' : `model \`${config.model}\``;
      await ctx.session.synthetic({
        sessionID: event.sessionID,
        text: [
          `[Review Gate] Bạn vừa sửa file${targetHint} nhưng chưa có review độc lập.`,
          `Hãy gọi \`task\` / subagent (${modelHint}, có thể đổi qua \`/advisor\`) với vai trò Independent Reviewer để kiểm tra nhanh:`,
          '1) Chỉ soi `git diff` hoặc đúng các file vừa sửa, KHÔNG chạy lại toàn bộ test suite;',
          '2) Trả lời tối đa 5-8 dòng (chỉ nêu bug, edge-case, cấu hình sai, hoặc phản bác nếu giải pháp chưa hợp lý; nếu ổn trả `OK — no issues`);',
          '3) Sửa lại nếu có lỗi thật rồi mới kết luận.'
        ].join(' ')
      });
    });
  }
});
