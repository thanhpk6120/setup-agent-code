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
        [Parameter(Position = 0, Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Path,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$AdditionalArgs
    )

    begin {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
    }

    process {
        $allTargets = @()
        if ($Path) { $allTargets += $Path }
        if ($AdditionalArgs) { $allTargets += $AdditionalArgs }

        # Lọc bỏ các cờ của rm như -r, -rf, -f, /s, /q, -Recurse, -Force
        $targets = $allTargets | Where-Object {
            $_ -and
            $_ -notmatch '^-[rRfF]+$' -and
            $_ -notmatch '^/[sSqQ]$' -and
            $_ -notmatch '^-(Recurse|Force|Confirm|WhatIf)$'
        }

        if (-not $targets -or $targets.Count -eq 0) {
            Write-Host "trash: không có file hoặc thư mục nào được chỉ định." -ForegroundColor Yellow
            return
        }

        foreach ($target in $targets) {
            $resolvedPaths = @()
            try {
                $resolvedPaths = Resolve-Path -LiteralPath $target -ErrorAction Stop | ForEach-Object { $_.Path }
            } catch {
                try {
                    $resolvedPaths = Resolve-Path -Path $target -ErrorAction Stop | ForEach-Object { $_.Path }
                } catch {
                    Write-Host "trash: không tìm thấy đường dẫn '$target'" -ForegroundColor Yellow
                    continue
                }
            }

            foreach ($p in $resolvedPaths) {
                try {
                    if (Test-Path -LiteralPath $p -PathType Container) {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                            $p,
                            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                        )
                        Write-Host "  [Trash] Đã chuyển thư mục vào Recycle Bin: $p" -ForegroundColor Green
                    } elseif (Test-Path -LiteralPath $p -PathType Leaf) {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                            $p,
                            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                        )
                        Write-Host "  [Trash] Đã chuyển file vào Recycle Bin: $p" -ForegroundColor Green
                    }
                } catch {
                    Write-Warning "Không thể chuyển '$p' vào Recycle Bin: $($_.Exception.Message)"
                }
            }
        }
    }
}

Set-Alias -Name recycle -Value trash -Option AllScope -Force -ErrorAction SilentlyContinue
Set-Alias -Name trash-cli -Value trash -Option AllScope -Force -ErrorAction SilentlyContinue
