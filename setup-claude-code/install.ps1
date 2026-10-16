# install.ps1 - One-line interactive installer for setup-claude-code
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$OverwriteAll,
    [switch]$DryRun,
    [switch]$SkipInstall,
    [switch]$EnableMemorix,
    [switch]$DisableMemorix,
    [string]$ClaudeDir = "$env:USERPROFILE\.claude"
)

$ErrorActionPreference = "Stop"

function Get-NpmLatestVersion {
    param([Parameter(Mandatory = $true)][string]$Package)
    try {
        $o = (npm view $Package version 2>$null | Out-String).Trim()
        if ($o -match '([0-9]+\.[0-9]+\.[0-9]+)') { return $Matches[1] }
    } catch {}
    return ""
}
function Test-VersionAtLeast {
    param([string]$Installed, [string]$Latest)
    if (-not $Installed -or -not $Latest) { return $false }
    try { if ([version]$Installed -ge [version]$Latest) { return $true } } catch {}
    return $false
}
function Get-NpmInstalledVersion {
    param([Parameter(Mandatory = $true)][string]$Package)
    try {
        $npmRoot = (npm root -g 2>$null | Out-String).Trim()
        if ($npmRoot) {
            $pkgJson = Join-Path (Join-Path $npmRoot $Package) "package.json"
            if (Test-Path -LiteralPath $pkgJson) {
                $j = Get-Content -LiteralPath $pkgJson -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
                if ($j -and $j.version -match '([0-9]+\.[0-9]+\.[0-9]+)') { return $Matches[1] }
            }
        }
    } catch {}
    return ""
}
function Test-ShouldSkipInstall {
    param([string]$CommandName, [string]$Label = "", [string]$NpmPackage = "")
    # NOTE: -Force/-OverwriteAll chi auto-confirm prompt + ghi de config, KHONG ep cai lai tool da moi nhat.
    $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
    if (-not $cmd) { $cmd = Get-Command "$CommandName.cmd" -ErrorAction SilentlyContinue }
    if (-not $cmd) { return $false }
    $lbl = if ($Label) { $Label } else { $CommandName }
    if ($NpmPackage) {
        $inst = Get-NpmInstalledVersion -Package $NpmPackage
        if (-not $inst) {
            try { $v = (& $CommandName --version 2>$null | Out-String); if ($v -match '([0-9]+\.[0-9]+\.[0-9]+)') { $inst = $Matches[1] } } catch {}
        }
        if ($inst) {
            $latest = Get-NpmLatestVersion -Package $NpmPackage
            if ($latest -and (Test-VersionAtLeast -Installed $inst -Latest $latest)) {
                Write-Host "  -> [Skip] $lbl da moi nhat (v$inst). Bo qua de cai nhanh hon." -ForegroundColor Green
                return $true
            }
            if (-not $latest) {
                Write-Host "  -> [Skip] $lbl da cai (v$inst, khong kiem tra duoc ban moi - offline). Bo qua." -ForegroundColor Green
                return $true
            }
            return $false
        }
        Write-Host "  -> [Skip] $lbl da cai (khong doc duoc version, giu ban hien tai). Bo qua." -ForegroundColor Green
        return $true
    }
    $ver = ""
    try { $ver = (& $CommandName --version 2>$null | Out-String).Trim() } catch {}
    if (-not $ver) { try { $ver = (& $CommandName -v 2>$null | Out-String).Trim() } catch {} }
    if ($ver) { Write-Host "  -> [Skip] $lbl da cai ($ver). Bo qua de cai nhanh hon." -ForegroundColor Green }
    else { Write-Host "  -> [Skip] $lbl da cai tai: $($cmd.Source). Bo qua." -ForegroundColor Green }
    return $true
}
function Test-Context7Installed {
    try {
        $npmRoot = (npm root -g 2>$null | Out-String).Trim()
        if ($npmRoot) {
            $candidate = Join-Path $npmRoot "@upstash/context7-mcp/dist/index.js"
            if (Test-Path -LiteralPath $candidate) {
                $inst = Get-NpmInstalledVersion -Package "@upstash/context7-mcp"
                $latest = Get-NpmLatestVersion -Package "@upstash/context7-mcp"
                if ($inst -and $latest -and (Test-VersionAtLeast -Installed $inst -Latest $latest)) {
                    Write-Host "  -> [Skip] context7 da moi nhat (v$inst). Bo qua de cai nhanh hon." -ForegroundColor Green
                    return $true
                }
                if ($inst -and -not $latest) {
                    Write-Host "  -> [Skip] context7 da cai (v$inst). Bo qua de cai nhanh hon." -ForegroundColor Green
                    return $true
                }
                if (-not $inst -or -not $latest) {
                    Write-Host "  -> [Skip] context7 da cai ($candidate). Bo qua de cai nhanh hon." -ForegroundColor Green
                    return $true
                }
                return $false
            }
        }
    } catch {}
    return $false
}

if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "       SETUP-CLAUDE-CODE INSTALLER - INTERACTIVE SETUP          " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Kiểm tra Claude Code CLI trong PATH
Write-Host "==> Kiểm tra Claude Code CLI trong hệ thống..." -ForegroundColor Cyan
$claudeCmd = Get-Command "claude" -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Host "[!] Claude Code CLI chưa được cài đặt trong PATH." -ForegroundColor Yellow
    $installClaudePrompt = Read-Host "Claude Code CLI chưa được cài đặt. Bạn có muốn cài đặt Claude Code chính gốc ngay bây giờ không? [Y/n]"
    if ([string]::IsNullOrWhiteSpace($installClaudePrompt) -or $installClaudePrompt.Trim().ToLower() -eq 'y') {
        # Nhận diện terminal
        $terminalType = if ($PSVersionTable.PSEdition -eq "Core") {
            "PowerShell Core (pwsh)"
        } elseif ($env:WT_SESSION) {
            "Windows Terminal ($($PSVersionTable.PSEdition))"
        } elseif ($PSVersionTable.PSVersion) {
            "Windows PowerShell"
        } else {
            "CMD / Standard Console"
        }
        Write-Host "==> Nhận diện terminal: $terminalType (PSVersion: $($PSVersionTable.PSVersion))." -ForegroundColor Cyan

        Write-Host "==> Dang cai dat Claude Code chinh thuc..." -ForegroundColor Cyan
        $claudeInstalled = $false
        $claudeViaNpm = $false
        if ($SkipInstall) {
            Write-Host "  -> Bo qua cai dat Claude Code CLI do -SkipInstall." -ForegroundColor Yellow
        } elseif ($DryRun) {
            Write-Host "  -> [WhatIf] Se chay: irm https://claude.ai/install.ps1 | iex (fallback: npm install -g @anthropic-ai/claude-code)" -ForegroundColor DarkGray
            $claudeInstalled = $true
        } else {
        try {
            Write-Host "  -> Dang chay installer chinh thuc cua Anthropic (https://claude.ai/install.ps1)..." -ForegroundColor Cyan
            & ([scriptblock]::Create((Invoke-RestMethod -Uri "https://claude.ai/install.ps1" -UseBasicParsing)))
            $claudeInstalled = $true
        } catch {
            Write-Host "  [!] Installer chinh thuc gap loi: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "  -> Thu cai dat qua npm: npm install -g @anthropic-ai/claude-code..." -ForegroundColor Cyan
            if (Get-Command "npm" -ErrorAction SilentlyContinue) {
                npm install -g @anthropic-ai/claude-code
                $claudeInstalled = ($LASTEXITCODE -eq 0)
                $claudeViaNpm = $claudeInstalled
            } else {
                Write-Warning "Khong tim thay npm tren he thong de cai dat fallback."
            }
        }
        # Nap lai PATH session: irm hang (~/.claude) + npm fallback (prefix -g, APPDATA/npm)
        Write-Host "==> Dang nap lai bien moi truong PATH trong session hien tai..." -ForegroundColor Cyan
        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        $npmPrefix = ""
        try {
            $npmPrefix = (npm config get prefix 2>$null).Trim()
        } catch {}
        $searchPaths = @(
            (Join-Path $env:USERPROFILE ".claude"),
            "$env:APPDATA\npm",
            "$env:LOCALAPPDATA\npm",
            $npmPrefix,
            "$env:USERPROFILE\.local\bin"
        )
        $allPaths = (@($searchPaths) + ($userPath -split ';') + ($machinePath -split ';') + ($env:PATH -split ';')) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) } |
            Select-Object -Unique
        $env:PATH = ($allPaths -join ';')
        Write-Host "  -> Da cap nhat PATH session (irm: ~/.claude; npm: $npmPrefix / %APPDATA%\npm)." -ForegroundColor DarkGray
        $claudeCheck = Get-Command "claude" -ErrorAction SilentlyContinue
        if ($claudeCheck) {
            Write-Host "==> Da nhan dien lenh 'claude' tai: $($claudeCheck.Source)" -ForegroundColor Green
        } else {
            Write-Warning "Lenh 'claude' chua nhan dien duoc ngay qua Get-Command. Ban co the can mo lai terminal sau khi cai dat hoan tat."
        }
        }
    } else {
        Write-Host "[-] Đã bỏ qua cài đặt Claude Code CLI theo lựa chọn của người dùng." -ForegroundColor Yellow
    }
} else {
    Write-Host "==> Đã phát hiện Claude Code CLI tại: $($claudeCmd.Source)" -ForegroundColor Green
    try { $v = (& claude --version 2>$null | Out-String).Trim(); if ($v) { Write-Host "  -> Version: $v" -ForegroundColor DarkGray } } catch {}
    Write-Host "  -> [Skip] Da dung version hien tai. Bo qua cai lai." -ForegroundColor DarkGray
}

# 2. Luồng hỏi tương tác cấu hình AI Provider
Write-Host ""
Write-Host "==> Cấu hình kết nối AI Provider..." -ForegroundColor Cyan
$defaultAiUrl = "http://localhost:20128/v1"
$inputAiUrl = Read-Host "Nhập AI Base URL [Mặc định: $defaultAiUrl]"
$aiBaseUrl = if ([string]::IsNullOrWhiteSpace($inputAiUrl)) { $defaultAiUrl } else { $inputAiUrl.Trim() }

# AI_API_KEY: Mặc định không có, bắt buộc nhập
$aiApiKey = ""
while ([string]::IsNullOrWhiteSpace($aiApiKey)) {
    if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
        if (-not [string]::IsNullOrWhiteSpace($env:AI_API_KEY)) {
            $aiApiKey = $env:AI_API_KEY.Trim()
            break
        }
        throw "Lỗi: Đang chạy ở chế độ non-interactive nhưng AI API Key chưa được cung cấp qua biến môi trường `$env:AI_API_KEY`."
    }
    $inputKey = Read-Host "Nhập AI API Key (Bắt buộc)"
    if (-not [string]::IsNullOrWhiteSpace($inputKey)) {
        $aiApiKey = $inputKey.Trim()
        break
    }
    Write-Host "Lỗi: AI API Key là bắt buộc, không được để trống. Vui lòng nhập lại!" -ForegroundColor Red
}

# 3. Hỏi tương tác cài đặt Memorix
Write-Host ""
Write-Host "==> Cấu hình tiện ích bổ sung..." -ForegroundColor Cyan
if ($PSBoundParameters.ContainsKey('EnableMemorix')) {
    $enableMemorixVal = $EnableMemorix.IsPresent
} elseif ($PSBoundParameters.ContainsKey('DisableMemorix')) {
    $enableMemorixVal = -not $DisableMemorix.IsPresent
} else {
    $memorixCmd = Get-Command "memorix" -ErrorAction SilentlyContinue
    if ($memorixCmd) {
        Write-Host "==> Đã phát hiện Memorix trên hệ thống tại: $($memorixCmd.Source)" -ForegroundColor Green
    }
    $memorixPrompt = Read-Host "Bạn có muốn cài đặt Memorix (MCP & Session Memory) không? [y/N]"
    if (-not [string]::IsNullOrWhiteSpace($memorixPrompt) -and $memorixPrompt.Trim().ToLower() -eq 'y') {
        $enableMemorixVal = $true
        Write-Host "==> Đã kích hoạt cài đặt Memorix." -ForegroundColor Green
    } else {
        $enableMemorixVal = $false
        Write-Host "==> Bỏ qua cài đặt Memorix (mặc định)." -ForegroundColor Yellow
    }
}

# 4. Thiết lập biến môi trường phiên làm việc
$env:AI_BASE_URL = $aiBaseUrl
$env:AI_API_KEY = $aiApiKey

# Chuẩn bị nội dung file .env tạm thời
$envContent = @"
AI_BASE_URL=$aiBaseUrl
AI_API_KEY=$aiApiKey
"@

$monoZipUrl = "https://github.com/thanhpk6120/setup-agent-code/archive/refs/heads/main.zip"
$subFolder = "setup-claude-code"
$tempBase = Join-Path ([System.IO.Path]::GetTempPath()) "setup-agent-code"
$zipFile = Join-Path ([System.IO.Path]::GetTempPath()) "setup-agent-code-repo.zip"

# Verify agent binary sau cai (test-safe: bo qua khi DryRun)
if (-not $DryRun) {
    $ac = Get-Command "claude" -ErrorAction SilentlyContinue
    if ($ac) { Write-Host "  -> [OK] Agent binary 'claude' san sang: $($ac.Source)" -ForegroundColor Green }
    else { Write-Warning "[Verify] Chua tim thay binary 'claude' sau cai. Hay mo terminal moi (PATH) roi chay lai." }
} else {
    Write-Host "  -> [WhatIf] Bo qua verify binary 'claude' (DryRun)." -ForegroundColor DarkGray
}

$localBootstrap = Join-Path $PSScriptRoot "bootstrap.ps1"
$extractedRoot = $null

try {
    if (Test-Path $localBootstrap) {
        $extractedRoot = $PSScriptRoot
        Write-Host "==> Dung bootstrap local: $localBootstrap" -ForegroundColor DarkGray
    } else {
        # Thu muc temp co dinh: uu tien git clone / pull vao subfolder repo de giu .env
        $repoDir = Join-Path $tempBase "repo"
        if (-not (Test-Path $tempBase)) { New-Item -ItemType Directory -Path $tempBase -Force | Out-Null }
        
        $gitCmd = Get-Command "git" -ErrorAction SilentlyContinue
        $useGitClone = $false
        if ($gitCmd) {
            try {
                if (Test-Path (Join-Path $repoDir ".git")) {
                    Write-Host "==> Thu muc temp co dinh da ton tai: $repoDir. Dong bo ma nguon moi nhat (git pull)..." -ForegroundColor Cyan
                    git -C $repoDir fetch --quiet 2>$null
                    git -C $repoDir checkout main --quiet 2>$null
                    git -C $repoDir pull --quiet 2>$null
                    $useGitClone = (Test-Path (Join-Path $repoDir (Join-Path $subFolder "bootstrap.ps1")))
                } else {
                    Write-Host "==> Clone monorepo ve thu muc temp co dinh: $repoDir..." -ForegroundColor Cyan
                    git clone --depth 1 https://github.com/thanhpk6120/setup-agent-code.git $repoDir --quiet 2>$null
                    if ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $repoDir (Join-Path $subFolder "bootstrap.ps1")))) {
                        $useGitClone = $true
                    }
                }
            } catch { $useGitClone = $false }
        }
        
        if (-not $useGitClone) {
            Write-Host "==> Khong thay bootstrap local. Tai monorepo setup-agent-code qua ZIP..." -ForegroundColor Cyan
            Write-Host "    URL: $monoZipUrl (subfolder: $subFolder)" -ForegroundColor DarkGray
            Invoke-WebRequest -Uri $monoZipUrl -OutFile $zipFile -UseBasicParsing
            Write-Host "==> Giai nen goi cai dat..." -ForegroundColor Cyan
            if (-not (Test-Path $repoDir)) { New-Item -ItemType Directory -Path $repoDir -Force | Out-Null }
            Expand-Archive -Path $zipFile -DestinationPath $repoDir -Force
            $foundRoot = Join-Path $repoDir "setup-agent-code-main"
            if (-not (Test-Path $foundRoot)) {
                $item = Get-ChildItem -Directory $repoDir | Where-Object { Test-Path (Join-Path $_.FullName (Join-Path $subFolder "bootstrap.ps1")) } | Select-Object -First 1
                if ($item) { $foundRoot = $item.FullName } else { $foundRoot = $repoDir }
            }
            $repoDir = $foundRoot
        }
        
        $extractedRoot = Join-Path $repoDir $subFolder
        if (-not (Test-Path (Join-Path $extractedRoot "bootstrap.ps1"))) {
            $found = Get-ChildItem -Directory $repoDir -Recurse | Where-Object { $_.Name -eq $subFolder -and (Test-Path (Join-Path $_.FullName "bootstrap.ps1")) } | Select-Object -First 1
            if ($found) { $extractedRoot = $found.FullName }
            else { throw "Khong tim thay bootstrap.ps1 cua $subFolder trong thu muc $repoDir." }
        }
    }

    # Ghi file .env tạm thời để bootstrap.ps1 đọc (chỉ khi dùng gói tải về; local dùng $env: sẵn có)
    if ($extractedRoot -ne $PSScriptRoot) {
        $tempEnvPath = Join-Path $tempBase ".env"
        Set-Content -Path $tempEnvPath -Value $envContent -Encoding UTF8
        $extractedEnvPath = Join-Path $extractedRoot ".env"
        Copy-Item -Path $tempEnvPath -Destination $extractedEnvPath -Force
    }

    $bootstrapScript = Join-Path $extractedRoot "bootstrap.ps1"
    if (-not (Test-Path $bootstrapScript)) {
        throw "Lỗi: Không tìm thấy bootstrap.ps1 trong gói cài đặt tại: $bootstrapScript"
    }
    # Chuẩn bị tham số gọi bootstrap.ps1
    $bootstrapParams = @{}
    if ($DryRun) { $bootstrapParams["DryRun"] = $true }
    if ($SkipInstall) { $bootstrapParams["SkipInstall"] = $true }
    if ($Force) { $bootstrapParams["Force"] = $true }
    if ($OverwriteAll) { $bootstrapParams["OverwriteAll"] = $true }
    if ($ClaudeDir) { $bootstrapParams["ClaudeDir"] = $ClaudeDir }
    if ($enableMemorixVal) {
        $bootstrapParams["EnableMemorix"] = $true
    } else {
        $bootstrapParams["DisableMemorix"] = $true
    }

    Write-Host "==> Đang khởi chạy bootstrap.ps1 với các tham số đã chọn..." -ForegroundColor Cyan
    $paramList = @()
    foreach ($key in $bootstrapParams.Keys) {
        if ($bootstrapParams[$key] -eq $true) {
            $paramList += "-$key"
        } else {
            $paramList += "-$key", "$($bootstrapParams[$key])"
        }
    }

    $psExe = Join-Path $PSHOME "pwsh.exe"
    if (-not (Test-Path $psExe)) { $psExe = Join-Path $PSHOME "powershell.exe" }
    if (-not (Test-Path $psExe)) { $psExe = "powershell" }

    $argsArray = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $bootstrapScript) + $paramList
    & $psExe $argsArray
    if ($LASTEXITCODE -ne 0) { throw "bootstrap.ps1 failed with exit code $LASTEXITCODE." }
} finally {
    Write-Host "==> Dọn dẹp tài nguyên tạm thời vào Thùng rác (Recycle Bin)..." -ForegroundColor Cyan
    Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

    if (Test-Path $zipFile) {
        try {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                $zipFile,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
            )
        } catch {
            Write-Warning "Không thể chuyển file zip tạm vào Thùng rác: $($_.Exception.Message)"
        }
    }

    # Giu lai thu muc temp co dinh $tempBase de luu .env va cau hinh resume cho lan chay sau
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host " CAI DAT THANH CONG CHO CLAUDE CODE!" -ForegroundColor Green
Write-Host " Da bao ve va kich hoat hook chan xoa cung (Trash Guard) cho Claude Code" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Green
