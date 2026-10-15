# install.ps1 - One-line interactive installer for setup-antigravity-cli
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$OverwriteAll,
    [switch]$DryRun,
    [switch]$SkipInstall,
    [switch]$EnableMemorix,
    [switch]$DisableMemorix,
    [string]$AgyDir = "$env:USERPROFILE\.gemini\antigravity-cli"
)

$ErrorActionPreference = "Stop"
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
Write-Host "       SETUP-ANTIGRAVITY-CLI INSTALLER - INTERACTIVE SETUP      " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Kiem tra Antigravity CLI (agy) trong PATH
Write-Host "==> Kiem tra Antigravity CLI trong he thong..." -ForegroundColor Cyan
$agyCmd = Get-Command "agy" -ErrorAction SilentlyContinue
if (-not $agyCmd) {
    $agyCmd = Get-Command "antigravity" -ErrorAction SilentlyContinue
}
if (-not $agyCmd) {
    Write-Host "[!] Antigravity CLI (agy) chua duoc cai dat trong PATH." -ForegroundColor Yellow
    if ($SkipInstall) {
        Write-Host "  -> [-SkipInstall] Bo qua cai dat Antigravity CLI. Tiep tuc cau hinh..." -ForegroundColor DarkGray
    } elseif ($DryRun) {
        Write-Host "  -> [WhatIf] Se chay: irm https://antigravity.google/cli/install.ps1 | iex" -ForegroundColor DarkGray
    } else {
        $agyPrompt = ''
        if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) { $agyPrompt = 'y' } else { $agyPrompt = Read-Host "Antigravity CLI chua duoc cai dat. Ban co muon cai dat Antigravity CLI chinh goc ngay bay gio khong? [Y/n]" }
        if ([string]::IsNullOrWhiteSpace($agyPrompt) -or $agyPrompt.Trim().ToLower() -eq 'y') {
            Write-Host '==> Dang cai dat Antigravity CLI chinh goc (https://antigravity.google/cli/install.ps1)...' -ForegroundColor Cyan
            try {
                & ([scriptblock]::Create((Invoke-RestMethod -Uri 'https://antigravity.google/cli/install.ps1' -UseBasicParsing)))
                Write-Host '==> Cai dat Antigravity CLI hoan tat. Dang cap nhat PATH trong session hien tai...' -ForegroundColor Green
                $agyCands = @((Join-Path $env:LOCALAPPDATA 'agy/bin'), (Join-Path $env:LOCALAPPDATA 'Programs/antigravity'), (Join-Path $env:USERPROFILE '.antigravity/bin'))
                try {
                    $uP = [Environment]::GetEnvironmentVariable('Path','User'); $mP = [Environment]::GetEnvironmentVariable('Path','Machine')
                    foreach ($pp in (("$uP;$mP" -split ';'))) { if (-not [string]::IsNullOrWhiteSpace($pp)) { $agyCands += $pp.Trim() } }
                } catch {}
                $cur = ($env:PATH -split ';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() }
                foreach ($c in ($agyCands | Select-Object -Unique)) { if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path $c) -and ($cur -notcontains $c)) { $env:PATH = "$c;$env:PATH"; Write-Host "  -> Da them vao PATH session: $c" -ForegroundColor DarkGray } }
                $agyCmd = Get-Command 'agy' -ErrorAction SilentlyContinue
                if (-not $agyCmd) { $agyCmd = Get-Command 'antigravity' -ErrorAction SilentlyContinue }
                if ($agyCmd) { Write-Host "==> Da nhan dien Antigravity CLI tai: $($agyCmd.Source)" -ForegroundColor Green } else { Write-Warning "Chua nhan dien duoc 'agy'. Co the can mo lai terminal." }
            } catch { Write-Warning "Cai dat Antigravity CLI gap loi: $($_.Exception.Message)" }
        } else { Write-Host '[-] Da bo qua cai dat Antigravity CLI theo lua chon cua nguoi dung.' -ForegroundColor Yellow }
    }
} else {
    Write-Host "==> Da phat hien Antigravity CLI tai: $($agyCmd.Source)" -ForegroundColor Green
}

# Nap bien moi truong tu .env hoac templates/.env.example
$dotEnv = Join-Path $PSScriptRoot ".env"
$templateEnv = Join-Path $PSScriptRoot "templates\.env.example"
$targetEnvFile = if (Test-Path $dotEnv) { $dotEnv } elseif (Test-Path $templateEnv) { $templateEnv } else { "" }
if ($targetEnvFile) {
    Get-Content $targetEnvFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) {
            $idx = $line.IndexOf("=")
            if ($idx -gt 0) {
                $key = $line.Substring(0, $idx).Trim()
                $val = $line.Substring($idx + 1).Trim().Trim('"').Trim("'")
                if (-not [string]::IsNullOrWhiteSpace($key) -and -not [string]::IsNullOrWhiteSpace($val)) {
                    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($key, "Process"))) {
                        [Environment]::SetEnvironmentVariable($key, $val, "Process")
                    }
                }
            }
        }
    }
}

# 2. Hoi tuong tac cau hinh AI Provider
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
        throw "Loi: AI_API_KEY bat buoc phai co gia tri nhung session hien tai la non-interactive."
    }
    $aiApiKey = Read-Host "Nhap AI API Key (Bat buoc)"
    if (-not [string]::IsNullOrWhiteSpace($aiApiKey)) {
        $aiApiKey = $aiApiKey.Trim()
    }
}

# 3. Cau hinh Model Antigravity
$defaultModel = "custom/claude-sonnet-5"
if ($env:AGY_MODEL) { $defaultModel = $env:AGY_MODEL }
$inputModel = ""
if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
    $inputModel = $defaultModel
} else {
    $inputModel = Read-Host "Nhap Antigravity Model [Mac dinh: $defaultModel]"
}
$agyModel = if ([string]::IsNullOrWhiteSpace($inputModel)) { $defaultModel } else { $inputModel.Trim() }

# 4. Cau hinh Memorix
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
$env:AGY_MODEL = $agyModel

# 5. Uu tien bootstrap local, fallback monorepo zip + subfolder
$monoZipUrl = 'https://github.com/thanhpk6120/setup-agent-code/archive/refs/heads/main.zip'
$subFolder = 'setup-antigravity-cli'
$localBootstrap = Join-Path $PSScriptRoot 'bootstrap.ps1'
$bootstrapRoot = $null
$tempBase = $null
$zipFile = $null
try {
    if (Test-Path $localBootstrap) {
        $bootstrapRoot = $PSScriptRoot
        Write-Host "==> Dung bootstrap local: $localBootstrap" -ForegroundColor DarkGray
    } else {
        $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) "setup-agent-code"
        $zipFile = Join-Path ([System.IO.Path]::GetTempPath()) "setup-agent-code-repo.zip"
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
        
        $bootstrapRoot = Join-Path $repoDir $subFolder
        if (-not (Test-Path (Join-Path $bootstrapRoot "bootstrap.ps1"))) {
            $found = Get-ChildItem -Directory $repoDir -Recurse | Where-Object { $_.Name -eq $subFolder -and (Test-Path (Join-Path $_.FullName "bootstrap.ps1")) } | Select-Object -First 1
            if ($found) { $bootstrapRoot = $found.FullName }
            else { throw "Khong tim thay bootstrap.ps1 cua $subFolder trong thu muc $repoDir." }
        }
    }
    $bootstrapPath = Join-Path $bootstrapRoot 'bootstrap.ps1'

    $splat = @{
        AgyDir = $AgyDir
    }
    if ($Force) { $splat['Force'] = $true }
    if ($OverwriteAll) { $splat['OverwriteAll'] = $true }
    if ($DryRun) { $splat['DryRun'] = $true }
    if ($SkipInstall) { $splat['SkipInstall'] = $true }
    if ($enableMemorix) { $splat['EnableMemorix'] = $true } else { $splat['DisableMemorix'] = $true }

    & $bootstrapPath @splat
} finally {
    if ($zipFile) { Safe-Trash -Path $zipFile }
    # Giu lai thu muc temp co dinh $tempBase de luu .env va cau hinh resume
}

# Verify agent binary sau cai (test-safe: bo qua khi DryRun)
if (-not $DryRun) {
    $ac = Get-Command "agy" -ErrorAction SilentlyContinue
    if ($ac) { Write-Host "  -> [OK] Agent binary 'agy' san sang: $($ac.Source)" -ForegroundColor Green }
    else { Write-Warning "[Verify] Chua tim thay binary 'agy' sau cai. Hay mo terminal moi (PATH) roi chay lai." }
} else {
    Write-Host "  -> [WhatIf] Bo qua verify binary 'agy' (DryRun)." -ForegroundColor DarkGray
}

