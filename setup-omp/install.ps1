# install.ps1 - One-line interactive installer for setup-omp
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$OverwriteAll,
    [switch]$DryRun,
    [switch]$SkipInstall,
    [switch]$EnableMemorix,
    [switch]$DisableMemorix,
    [string]$OmpDir = "$env:USERPROFILE\.omp\agent"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

function Safe-Trash {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
        if ((Get-Item -LiteralPath $Path) -is [System.IO.DirectoryInfo]) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory((Convert-Path -LiteralPath $Path), [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
        } else {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile((Convert-Path -LiteralPath $Path), [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
        }
    } catch {
        Write-Warning "Khong the chuyen vao Recycle Bin: $($_.Exception.Message)"
    }
}
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "             SETUP-OMP INSTALLER - INTERACTIVE SETUP            " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Kiểm tra OMP CLI trong PATH
Write-Host "==> Kiểm tra OMP CLI trong hệ thống..." -ForegroundColor Cyan
$ompCmd = Get-Command "omp" -ErrorAction SilentlyContinue
if (-not $ompCmd) {
    Write-Host "[!] OMP CLI chưa được cài đặt trong PATH." -ForegroundColor Yellow
    $installOmpPrompt = Read-Host "OMP CLI chưa được cài đặt. Bạn có muốn cài đặt OMP chính gốc ngay bây giờ không? [Y/n]"
    if ([string]::IsNullOrWhiteSpace($installOmpPrompt) -or $installOmpPrompt.Trim().ToLower() -eq 'y') {
        $terminalType = if ($PSVersionTable.PSEdition -eq "Core") { "PowerShell Core / pwsh" } else { "Windows PowerShell" }
        Write-Host "==> Nhận diện terminal: $terminalType (PSVersion: $($PSVersionTable.PSVersion))." -ForegroundColor Cyan
        if ($SkipInstall) {
            Write-Host "  -> [-SkipInstall] Bo qua cai dat OMP CLI. Tiep tuc cau hinh..." -ForegroundColor DarkGray
        } elseif ($DryRun) {
            Write-Host "  -> [WhatIf] Se chay: irm https://omp.sh/install.ps1 | iex -Binary" -ForegroundColor DarkGray
        } else {
        Write-Host "==> Đang cài đặt OMP chính gốc qua https://omp.sh/install.ps1..." -ForegroundColor Cyan
        try {
            & ([scriptblock]::Create((Invoke-RestMethod -Uri "https://omp.sh/install.ps1" -UseBasicParsing))) -Binary
            Write-Host "==> Cài đặt OMP CLI hoàn tất. Đang cập nhật PATH trong session hiện tại..." -ForegroundColor Green

            # Cập nhật PATH trong phiên làm việc hiện tại
            $candidatePaths = @(
                (Join-Path $env:LOCALAPPDATA "omp"),
                (Join-Path $env:LOCALAPPDATA "Programs\omp"),
                (Join-Path $env:USERPROFILE ".omp\bin"),
                (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links")
            )

            try {
                $userPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)
                $machinePath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
                foreach ($p in ("$userPath;$machinePath" -split ';')) {
                    if (-not [string]::IsNullOrWhiteSpace($p)) {
                        $candidatePaths += $p.Trim()
                    }
                }
            } catch {}

            $pathItems = ($env:PATH -split ';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() }
            foreach ($cand in ($candidatePaths | Select-Object -Unique)) {
                if ((Test-Path $cand) -and ($pathItems -notcontains $cand)) {
                    $env:PATH = "$cand;$env:PATH"
                    $pathItems += $cand
                }
            }

            $ompCmd = Get-Command "omp" -ErrorAction SilentlyContinue
            if ($ompCmd) {
                Write-Host "==> Đã tìm thấy OMP CLI tại: $($ompCmd.Source)" -ForegroundColor Green
            } else {
                Write-Host "[!] Đã chạy installer nhưng chưa nhận diện được 'omp' trong session hiện tại. Bạn có thể cần mở lại terminal sau khi cài đặt." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "[!] Lỗi khi cài đặt OMP CLI: $_" -ForegroundColor Red
        }
        }
    } else {
        Write-Host "[!] Bỏ qua cài đặt OMP CLI. Tiếp tục cấu hình môi trường setup-omp..." -ForegroundColor Yellow
    }
} else {
    Write-Host "==> Đã phát hiện OMP CLI tại: $($ompCmd.Source)" -ForegroundColor Green
}

# 2. Hỏi tương tác cấu hình AI Provider
Write-Host ""
Write-Host "==> Cấu hình kết nối AI Provider..." -ForegroundColor Cyan
$defaultAiUrl = "http://localhost:20128/v1"
if ($env:AI_BASE_URL) { $defaultAiUrl = $env:AI_BASE_URL }
$inputAiUrl = ""
if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
    $inputAiUrl = $defaultAiUrl
} else {
    $inputAiUrl = Read-Host "Nhập AI Base URL [Mặc định: $defaultAiUrl]"
}
$aiBaseUrl = if ([string]::IsNullOrWhiteSpace($inputAiUrl)) { $defaultAiUrl } else { $inputAiUrl.Trim() }

$aiApiKey = ""
if (-not [string]::IsNullOrWhiteSpace($env:AI_API_KEY)) { $aiApiKey = $env:AI_API_KEY.Trim() }
while ([string]::IsNullOrWhiteSpace($aiApiKey)) {
    if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
        throw "Lỗi: Đang chạy ở chế độ non-interactive nhưng AI API Key chưa được cung cấp qua biến môi trường `$env:AI_API_KEY`."
    }
    $inputKey = Read-Host "Nhập AI API Key (Bắt buộc)"
    if (-not [string]::IsNullOrWhiteSpace($inputKey)) {
        $aiApiKey = $inputKey.Trim()
        break
    }
    Write-Host "[!] AI API Key không được để trống. Vui lòng nhập key." -ForegroundColor Yellow
}

# 3. Hỏi tương tác cài đặt Memorix
Write-Host ""
Write-Host "==> Cấu hình tiện ích bổ sung..." -ForegroundColor Cyan
if ($PSBoundParameters.ContainsKey('EnableMemorix')) {
    $enableMemorix = $EnableMemorix.IsPresent
} elseif ($PSBoundParameters.ContainsKey('DisableMemorix')) {
    $enableMemorix = -not $DisableMemorix.IsPresent
} else {
    $memorixCmd = Get-Command "memorix" -ErrorAction SilentlyContinue
    if ($memorixCmd) {
        Write-Host "==> Đã phát hiện Memorix trên hệ thống tại: $($memorixCmd.Source)" -ForegroundColor Green
    }
    $installMemorixPrompt = ""
    if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
        $installMemorixPrompt = "n"
    } else {
        $installMemorixPrompt = Read-Host "Bạn có muốn cài đặt Memorix (MCP & Session Memory) không? [y/N]"
    }
    $enableMemorix = if (-not [string]::IsNullOrWhiteSpace($installMemorixPrompt) -and $installMemorixPrompt.Trim().ToLower() -eq 'y') { $true } else { $false }
}

$env:AI_BASE_URL = $aiBaseUrl
$env:AI_API_KEY = $aiApiKey

$monoZipUrl = "https://github.com/thanhpk6120/setup-agent-code/archive/refs/heads/main.zip"
$subFolder = "setup-omp"
$tempBase = Join-Path ([System.IO.Path]::GetTempPath()) "setup-agent-code"
$zipFile = Join-Path ([System.IO.Path]::GetTempPath()) "setup-agent-code-repo.zip"

# Verify agent binary sau cai (test-safe: bo qua khi DryRun)
if (-not $DryRun) {
    $ac = Get-Command "omp" -ErrorAction SilentlyContinue
    if ($ac) { Write-Host "  -> [OK] Agent binary 'omp' san sang: $($ac.Source)" -ForegroundColor Green }
    else { Write-Warning "[Verify] Chua tim thay binary 'omp' sau cai. Hay mo terminal moi (PATH) roi chay lai." }
} else {
    Write-Host "  -> [WhatIf] Bo qua verify binary 'omp' (DryRun)." -ForegroundColor DarkGray
}

$localBootstrap = Join-Path $PSScriptRoot "bootstrap.ps1"
$extractedRoot = $null

try {
    Write-Host ""
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

    $bootstrapScript = Join-Path $extractedRoot "bootstrap.ps1"
    if (-not (Test-Path $bootstrapScript)) {
        throw "Loi: Khong tim thay bootstrap.ps1 trong goi cai dat."
    }

    # Ghi file .env tạm thời để bootstrap.ps1 có thể nạp (chỉ khi dùng gói tải về; local dùng $env: sẵn có)
    if ($extractedRoot -ne $PSScriptRoot) {
        $envFilePath = Join-Path $extractedRoot ".env"
        $existingMap = @{}
        if (Test-Path $envFilePath) {
            Get-Content $envFilePath | ForEach-Object {
                $l = $_.Trim()
                if ($l -and -not $l.StartsWith("#")) {
                    $i = $l.IndexOf("=")
                    if ($i -gt 0) { $existingMap[$l.Substring(0,$i).Trim()] = $l.Substring($i+1).Trim() }
                }
            }
        }
        $existingMap["AI_BASE_URL"] = $aiBaseUrl
        $existingMap["AI_API_KEY"] = $aiApiKey
        $envLines = @()
        foreach ($k in $existingMap.Keys) { $envLines += "$k=$($existingMap[$k])" }
        Set-Content -Path $envFilePath -Value ($envLines -join "`r`n") -Encoding utf8
    }

    Write-Host "==> Launching bootstrap..." -ForegroundColor Cyan
    $bootstrapParams = @{}
    if ($PSBoundParameters.ContainsKey('Force')) { $bootstrapParams['Force'] = $Force }
    if ($PSBoundParameters.ContainsKey('OverwriteAll')) { $bootstrapParams['OverwriteAll'] = $OverwriteAll }
    if ($PSBoundParameters.ContainsKey('DryRun')) { $bootstrapParams['DryRun'] = $DryRun }
    if ($PSBoundParameters.ContainsKey('SkipInstall')) { $bootstrapParams['SkipInstall'] = $SkipInstall }
    if ($PSBoundParameters.ContainsKey('OmpDir')) { $bootstrapParams['OmpDir'] = $OmpDir }
    if ($enableMemorix) {
        $bootstrapParams['EnableMemorix'] = $true
    } else {
        $bootstrapParams['DisableMemorix'] = $true
    }

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
}
finally {
    if ($zipFile) { Safe-Trash -Path $zipFile }
    # Giu lai thu muc temp co dinh $tempBase de luu .env va cau hinh resume
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host " CAI DAT THANH CONG CHO OMP!" -ForegroundColor Green
Write-Host " Da bao ve va kich hoat hook chan xoa cung (Trash Guard) cho OMP" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Green
