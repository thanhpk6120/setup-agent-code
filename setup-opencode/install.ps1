# install.ps1 - One-line interactive installer for setup-opencode
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$OverwriteAll,
    [switch]$DryRun,
    [switch]$SkipInstall,
    [switch]$EnableMemorix,
    [switch]$DisableMemorix,
    [string]$OpenCodeDir = "$env:USERPROFILE\.config\opencode"
)

$ErrorActionPreference = "Stop"
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

function Safe-Trash {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (Get-Command "trash" -ErrorAction SilentlyContinue) {
        trash $Path
        return
    }
    try {
        if ([System.IO.Directory]::Exists($Path)) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($Path, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
        } elseif ([System.IO.File]::Exists($Path)) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($Path, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
        }
    } catch {
        Write-Warning "Khong the di chuyen '$Path' vao Thung rac: $($_.Exception.Message)"
    }
}

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "          SETUP-OPENCODE INSTALLER - INTERACTIVE SETUP          " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Kiem tra va ho tro cai dat OpenCode CLI trong PATH
Write-Host "==> Kiem tra OpenCode CLI trong he thong..." -ForegroundColor Cyan
$opencodeCmd = Get-Command "opencode" -ErrorAction SilentlyContinue
if (-not $opencodeCmd) {
    Write-Host "[!] OpenCode CLI chua duoc cai dat trong PATH." -ForegroundColor Yellow
    $installPrompt = ""
    if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
        $installPrompt = "y"
    } else {
        $installPrompt = Read-Host "OpenCode CLI chua duoc cai dat. Ban co muon cai dat OpenCode chinh goc ngay bay gio khong? [Y/n]"
    }
    if ([string]::IsNullOrWhiteSpace($installPrompt) -or $installPrompt.Trim().ToLower() -eq 'y') {
        if ($SkipInstall) {
            Write-Host "  -> [-SkipInstall] Bo qua cai dat OpenCode CLI. Tiep tuc cau hinh..." -ForegroundColor DarkGray
        } elseif ($DryRun) {
            Write-Host "  -> [WhatIf] Se chay: npm install -g opencode-ai" -ForegroundColor DarkGray
        } else {
        Write-Host "==> Dang cai dat OpenCode CLI qua npm (npm install -g opencode-ai)..." -ForegroundColor Cyan
        try {
            npm install -g opencode-ai
            Write-Host "==> Cai dat OpenCode CLI hoan tat. Dang cap nhat PATH trong session hien tai..." -ForegroundColor Green

            $candidatePaths = @(
                (npm prefix -g 2>$null),
                (Join-Path $env:APPDATA "npm"),
                (Join-Path $env:LOCALAPPDATA "Programs\opencode"),
                (Join-Path $env:USERPROFILE ".opencode\bin")
            )
            try {
                $userPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)
                $machinePath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
                foreach ($p in ("$userPath;$machinePath" -split ';')) {
                    if (-not [string]::IsNullOrWhiteSpace($p)) { $candidatePaths += $p.Trim() }
                }
            } catch {}

            $pathItems = ($env:PATH -split ';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() }
            foreach ($cand in ($candidatePaths | Select-Object -Unique)) {
                if (-not [string]::IsNullOrWhiteSpace($cand) -and (Test-Path $cand) -and ($pathItems -notcontains $cand)) {
                    $env:PATH = "$cand;$env:PATH"
                    $pathItems += $cand
                }
            }

            $opencodeCmd = Get-Command "opencode" -ErrorAction SilentlyContinue
            if ($opencodeCmd) {
                Write-Host "==> Da tim thay OpenCode CLI tai: $($opencodeCmd.Source)" -ForegroundColor Green
            } else {
                Write-Host "[!] Da chay npm install nhung chua nhan dien duoc 'opencode' trong session hien tai. Ban co the can mo lai terminal sau khi cai dat." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "[!] Loi khi cai dat OpenCode CLI: $_" -ForegroundColor Red
        }
        }
    } else {
        Write-Host "[!] Bo qua cai dat OpenCode CLI. Tiep tuc cau hinh moi truong setup-opencode..." -ForegroundColor Yellow
    }
} else {
    Write-Host "==> Da phat hien OpenCode CLI tai: $($opencodeCmd.Source)" -ForegroundColor Green
}

# 2. Cau hinh ket noi AI Provider
Write-Host ""
Write-Host "==> Cau hinh ket noi AI Provider..." -ForegroundColor Cyan
$defaultAiUrl = "http://localhost:20128/v1"
if ($env:AI_BASE_URL) { $defaultAiUrl = $env:AI_BASE_URL }
$inputAiUrl = ""
if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
    $inputAiUrl = $defaultAiUrl
} else {
    $inputAiUrl = Read-Host "Nhap AI Base URL [Mac dinh: $defaultAiUrl]"
}
$aiBaseUrl = if ([string]::IsNullOrWhiteSpace($inputAiUrl)) { $defaultAiUrl } else { $inputAiUrl.Trim() }

$aiApiKey = ""
if (-not [string]::IsNullOrWhiteSpace($env:AI_API_KEY)) { $aiApiKey = $env:AI_API_KEY.Trim() }
while ([string]::IsNullOrWhiteSpace($aiApiKey)) {
    if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
        throw "Loi: Dang chay o che do non-interactive nhung AI API Key chua duoc cung cap qua bien moi truong `$env:AI_API_KEY`."
    }
    $inputKey = Read-Host "Nhap AI API Key (Bat buoc)"
    if (-not [string]::IsNullOrWhiteSpace($inputKey)) {
        $aiApiKey = $inputKey.Trim()
        break
    }
    Write-Host "[!] AI API Key khong duoc de trong. Vui long nhap key." -ForegroundColor Yellow
}

# 3. Cau hinh tien ich bo sung (Memorix)
Write-Host ""
Write-Host "==> Cau hinh tien ich bo sung..." -ForegroundColor Cyan
if ($PSBoundParameters.ContainsKey('EnableMemorix')) {
    $enableMemorix = $EnableMemorix.IsPresent
} elseif ($PSBoundParameters.ContainsKey('DisableMemorix')) {
    $enableMemorix = -not $DisableMemorix.IsPresent
} else {
    $memorixCmd = Get-Command "memorix" -ErrorAction SilentlyContinue
    if ($memorixCmd) {
        Write-Host "==> Da phat hien Memorix tren he thong tai: $($memorixCmd.Source)" -ForegroundColor Green
    }
    $installMemorixPrompt = ""
    if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
        $installMemorixPrompt = "n"
    } else {
        $installMemorixPrompt = Read-Host "Ban co muon cai dat Memorix (MCP & Session Memory) khong? [y/N]"
    }
    $enableMemorix = if (-not [string]::IsNullOrWhiteSpace($installMemorixPrompt) -and $installMemorixPrompt.Trim().ToLower() -eq 'y') { $true } else { $false }
}

$env:AI_BASE_URL = $aiBaseUrl
$env:AI_API_KEY = $aiApiKey

# 4. Dung bootstrap local neu co, fallback monorepo zip + subfolder setup-opencode
$RepoZipUrl = "https://github.com/thanhpk6120/setup-agent-code/archive/refs/heads/main.zip"
$SubFolder = "setup-opencode"
$tempBase = Join-Path ([System.IO.Path]::GetTempPath()) "setup-agent-code"
$zipFile = Join-Path ([System.IO.Path]::GetTempPath()) "setup-agent-code-repo.zip"

try {
    
# Verify agent binary sau cai (test-safe: bo qua khi DryRun)
if (-not $DryRun) {
    $ac = Get-Command "opencode" -ErrorAction SilentlyContinue
    if ($ac) { Write-Host "  -> [OK] Agent binary 'opencode' san sang: $($ac.Source)" -ForegroundColor Green }
    else { Write-Warning "[Verify] Chua tim thay binary 'opencode' sau cai. Hay mo terminal moi (PATH) roi chay lai." }
} else {
    Write-Host "  -> [WhatIf] Bo qua verify binary 'opencode' (DryRun)." -ForegroundColor DarkGray
}

$localBootstrap = Join-Path $PSScriptRoot "bootstrap.ps1"
    if (Test-Path $localBootstrap) {
        $extractedRoot = $PSScriptRoot
        Write-Host "==> Dung bootstrap local: $localBootstrap" -ForegroundColor DarkGray
    } else {
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
                    $useGitClone = (Test-Path (Join-Path $repoDir (Join-Path "setup-opencode" "bootstrap.ps1")))
                } else {
                    Write-Host "==> Clone monorepo ve thu muc temp co dinh: $repoDir..." -ForegroundColor Cyan
                    git clone --depth 1 https://github.com/thanhpk6120/setup-agent-code.git $repoDir --quiet 2>$null
                    if ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $repoDir (Join-Path "setup-opencode" "bootstrap.ps1")))) {
                        $useGitClone = $true
                    }
                }
            } catch { $useGitClone = $false }
        }
        
        if (-not $useGitClone) {
            Write-Host "==> Khong thay bootstrap local. Tai monorepo setup-agent-code qua ZIP..." -ForegroundColor Cyan
            $monoZipUrl = "https://github.com/thanhpk6120/setup-agent-code/archive/refs/heads/main.zip"
            Invoke-WebRequest -Uri $monoZipUrl -OutFile $zipFile -UseBasicParsing
            Write-Host "==> Giai nen goi cai dat..." -ForegroundColor Cyan
            if (-not (Test-Path $repoDir)) { New-Item -ItemType Directory -Path $repoDir -Force | Out-Null }
            Expand-Archive -Path $zipFile -DestinationPath $repoDir -Force
            $foundRoot = Join-Path $repoDir "setup-agent-code-main"
            if (-not (Test-Path $foundRoot)) {
                $item = Get-ChildItem -Directory $repoDir | Where-Object { Test-Path (Join-Path $_.FullName (Join-Path "setup-opencode" "bootstrap.ps1")) } | Select-Object -First 1
                if ($item) { $foundRoot = $item.FullName } else { $foundRoot = $repoDir }
            }
            $repoDir = $foundRoot
        }
        
        $extractedRoot = Join-Path $repoDir "setup-opencode"
        if (-not (Test-Path (Join-Path $extractedRoot "bootstrap.ps1"))) {
            $found = Get-ChildItem -Directory $repoDir -Recurse | Where-Object { $_.Name -eq "setup-opencode" -and (Test-Path (Join-Path $_.FullName "bootstrap.ps1")) } | Select-Object -First 1
            if ($found) { $extractedRoot = $found.FullName }
            else { throw "Khong tim thay bootstrap.ps1 cua setup-opencode trong thu muc $repoDir." }
        }
    }
    $bootstrapScript = Join-Path $extractedRoot "bootstrap.ps1"
    if (-not (Test-Path $bootstrapScript)) {
        throw "Loi: Khong tim thay bootstrap.ps1 trong goi cai dat."
    }

    $envFilePath = Join-Path $extractedRoot ".env"
    $isLocalSource = ($extractedRoot -eq $PSScriptRoot)
    $envContent = @"
AI_BASE_URL=$aiBaseUrl
AI_API_KEY=$aiApiKey
"@
    if (-not $isLocalSource) { Set-Content -Path $envFilePath -Value $envContent -Encoding utf8 }

    Write-Host "==> Launching bootstrap..." -ForegroundColor Cyan
    $bootstrapParams = @{}
    if ($PSBoundParameters.ContainsKey('Force')) { $bootstrapParams['Force'] = $Force }
    if ($PSBoundParameters.ContainsKey('OverwriteAll')) { $bootstrapParams['OverwriteAll'] = $OverwriteAll }
    if ($PSBoundParameters.ContainsKey('DryRun')) { $bootstrapParams['DryRun'] = $DryRun }
    if ($PSBoundParameters.ContainsKey('SkipInstall')) { $bootstrapParams['SkipInstall'] = $SkipInstall }
    if ($PSBoundParameters.ContainsKey('OpenCodeDir')) { $bootstrapParams['OpenCodeDir'] = $OpenCodeDir }
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
    if ($LASTEXITCODE -ne 0) { throw "bootstrap.ps1 that bai voi ma loi exit code $LASTEXITCODE." }
}
finally {
    if (Test-Path $zipFile) { Safe-Trash -Path $zipFile }
    # Giu lai thu muc temp co dinh de luu .env
        # # Giu lai thu muc temp co dinh de luu .env
        # # Giu lai thu muc temp co dinh $tempBase de luu .env va cau hinh resume
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host " CAI DAT THANH CONG CHO OPENCODE!" -ForegroundColor Green
Write-Host " Da bao ve va kich hoat hook chan xoa cung (Trash Guard) cho OpenCode" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Green

