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

# 5. Chay truc tiep bootstrap.ps1 noi bo
$bootstrapPath = Join-Path $PSScriptRoot "bootstrap.ps1"
if (-not (Test-Path $bootstrapPath)) {
    throw "Khong tim thay bootstrap.ps1 tai: $bootstrapPath"
}

$splat = @{
    AgyDir = $AgyDir
}
if ($Force) { $splat['Force'] = $true }
if ($OverwriteAll) { $splat['OverwriteAll'] = $true }
if ($DryRun) { $splat['DryRun'] = $true }
if ($SkipInstall) { $splat['SkipInstall'] = $true }
if ($enableMemorix) { $splat['EnableMemorix'] = $true } else { $splat['DisableMemorix'] = $true }

& $bootstrapPath @splat
