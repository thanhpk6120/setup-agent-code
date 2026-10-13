# ==============================================================================
# TRASH-GUARD.PS1 — HỆ THỐNG BẢO VỆ CHẶN XÓA CỨNG (POWERSHELL)
# ==============================================================================
# Quy tắc tiên quyết: Tuyệt đối không xóa cứng/vĩnh viễn file hoặc thư mục.
# Bắt buộc chuyển vào thùng rác (Windows Recycle Bin) qua lệnh 'trash'.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

function trash {
    <#
    .SYNOPSIS
        Di chuyển an toàn file hoặc thư mục vào Windows Recycle Bin.
    .EXAMPLE
        trash file.txt
        trash -rf folder1 folder2
        Get-ChildItem *.tmp | trash
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Path,

        [Alias('r', 'rf', 'fr')]
        [switch]$Recurse,

        [Alias('f')]
        [switch]$Force
    )

    begin {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
    }

    process {
        foreach ($p in $Path) {
            if ([string]::IsNullOrWhiteSpace($p)) { continue }

            # Bỏ qua nếu token là flag như -r, -rf, -f, /f, /q, v.v.
            if ($p -match '^[/-]{1,2}[a-zA-Z]+$') { continue }

            $resolvedPaths = @()
            try {
                if (Test-Path -LiteralPath $p) {
                    $resolvedPaths = @((Resolve-Path -LiteralPath $p -ErrorAction Stop).ProviderPath)
                } else {
                    $resolvedPaths = @((Resolve-Path -Path $p -ErrorAction Stop).ProviderPath)
                }
            } catch {
                Write-Error "[Trash] Lỗi: Không tìm thấy file hoặc thư mục: $p"
                continue
            }

            foreach ($fullPath in $resolvedPaths) {
                try {
                    if (Test-Path -LiteralPath $fullPath -PathType Container) {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                            $fullPath,
                            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                        )
                        Write-Host "[Trash] Đã chuyển thư mục vào thùng rác: $fullPath" -ForegroundColor Green
                    } elseif (Test-Path -LiteralPath $fullPath) {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                            $fullPath,
                            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                        )
                        Write-Host "[Trash] Đã chuyển file vào thùng rác: $fullPath" -ForegroundColor Green
                    } else {
                        Write-Warning "[Trash] Đường dẫn không còn tồn tại: $fullPath"
                    }
                } catch {
                    Write-Error "[Trash] Lỗi khi chuyển '$fullPath' vào thùng rác: $_"
                }
            }
        }
    }
}

Set-Alias -Name recycle -Value trash -Option AllScope -Force -ErrorAction SilentlyContinue
Set-Alias -Name trash-cli -Value trash -Option AllScope -Force -ErrorAction SilentlyContinue

# Tự động chuyển hướng an toàn các lệnh xóa tiện ích sang trash nếu là thao tác trên FileSystem
function Safe-RemoveRedirect {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )
    $fileTargets = @()
    $nonFileTargets = @()

    foreach ($arg in $Arguments) {
        if ([string]::IsNullOrWhiteSpace($arg)) { continue }
        if ($arg -match '^[/-]{1,2}[a-zA-Z]+$') { continue }
        if ($arg -match '^(alias|env|variable|function|cert|hkcu|hklm|wsman):' -or ($arg -like '*:*' -and $arg -notmatch '^[a-zA-Z]:')) {
            $nonFileTargets += $arg
        } else {
            $fileTargets += $arg
        }
    }

    if ($nonFileTargets.Count -gt 0) {
        Microsoft.PowerShell.Management\Remove-Item @Arguments
        return
    }

    if ($fileTargets.Count -gt 0) {
        Write-Host "[Trash Guard] Thao tác xóa đã được tự động chuyển hướng an toàn vào Thùng rác (Recycle Bin)." -ForegroundColor Yellow
        trash -Path $fileTargets
    } else {
        Microsoft.PowerShell.Management\Remove-Item @Arguments
    }
}

# Chỉ gán các alias gõ tắt (rm, del, erase, rd, rmdir) sang Safe-RemoveRedirect
# Tuyệt đối không override Remove-Item gốc để tránh ảnh hưởng đến các module nội bộ của PowerShell
$convenienceCommands = @('rm', 'del', 'erase', 'rd', 'rmdir')
foreach ($cmd in $convenienceCommands) {
    if (Test-Path "alias:$cmd") {
        Microsoft.PowerShell.Management\Remove-Item "alias:$cmd" -Force -ErrorAction SilentlyContinue
    }
    Set-Alias -Name $cmd -Value Safe-RemoveRedirect -Scope Global -Option AllScope -Force -ErrorAction SilentlyContinue
}
