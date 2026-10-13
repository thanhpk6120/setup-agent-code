// @orca-managed-pi-extension
interface PiInstance {
  on(event: string, handler: (event: unknown) => unknown): void;
}

export default function (pi: PiInstance) {
  pi.on('tool_call', async (event: unknown) => {
    let cmd = '';
    if (event && typeof event === 'object') {
      const input = (event as Record<string, unknown>).input;
      if (typeof input === 'string') {
        cmd = input;
      } else if (input && typeof input === 'object') {
        const obj = input as Record<string, unknown>;
        if (typeof obj.command === 'string') {
          cmd = obj.command;
        } else if (typeof obj.cmd === 'string') {
          cmd = obj.cmd;
        }
      }
    }
    if (cmd) {
      const hardDeletePattern = /(?:^|[;&|`\s])(?:rm\s|rmdir\s|del\s|erase\s|rd\s|ri\s|Remove-Item\s|unlink\s|shred\s)/i;
      if (hardDeletePattern.test(cmd)) {
        return {
          block: true,
          reason: "[BLOCKED] Thao tác xóa cứng bị chặn! QUY TẮC TIÊN QUYẾT: TUYỆT ĐỐI KHÔNG ĐƯỢC xoá cứng file/thư mục. BẮT BUỘC dùng lệnh di chuyển vào thùng rác ('trash <path>')."
        };
      }
    }
  });
}
