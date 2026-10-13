# claude-pre-tool.ps1 - Claude Code PreToolUse hook for hard-delete prevention
[CmdletBinding()]
param()

$msg = @"
[LỖI NGHIÊM TRỌNG] Thao tác xóa cứng bị chặn!
QUY TẮC TIÊN QUYẾT: TUYỆT ĐỐI KHÔNG ĐƯỢC xoá cứng/xoá vĩnh viễn file hoặc thư mục.
BẮT BUỘC phải dùng lệnh di chuyển vào thùng rác (Trash / Recycle Bin).
Vui lòng dùng: trash <đường_dẫn>
"@

$hardDeletePattern = '(?:^|[;&|`\s\(\$])(?:rm|rmdir|del|erase|rd|ri|Remove-Item|unlink|shred)(?:\.exe)?(?:\s+|$)'

try {
    $rawInput = [Console]::In.ReadToEnd()
    if (-not [string]::IsNullOrWhiteSpace($rawInput)) {
        $cmd = ""
        try {
            $json = $rawInput | ConvertFrom-Json
            if ($json.tool_input -is [string]) {
                $cmd = $json.tool_input
            } elseif ($json.tool_input.command) {
                $cmd = $json.tool_input.command
            } elseif ($json.tool_input.cmd) {
                $cmd = $json.tool_input.cmd
            } elseif ($json.command) {
                $cmd = $json.command
            }
        } catch {
            $cmd = $rawInput
        }

        if ($cmd -match $hardDeletePattern) {
            [Console]::Error.WriteLine($msg)
            exit 2
        }
    }
} catch {
    exit 0
}

exit 0
