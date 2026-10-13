# install.ps1 - One-line interactive installer for setup-dsh-web (DSH Web Runner)
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$OverwriteAll,
    [switch]$DryRun,
    [switch]$SkipInstall,
    [switch]$EnableMemorix,
    [switch]$DisableMemorix,
    [string]$DshHome = "$env:USERPROFILE\.dsh",
    [string]$DshProfileDir = "$env:APPDATA\dsh-desktop\harness\profiles\web-runner",
    [string]$CredentialsPath = "$env:APPDATA\dsh-desktop\harness\.credentials.yaml"
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
Write-Host "         SETUP-DSH-WEB INSTALLER - INTERACTIVE SETUP            " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Kiem tra moi truong runtime (Node.js, Git)
Write-Host "==> Kiem tra runtime..." -ForegroundColor Cyan
foreach ($tool in @("node", "git")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Loi: Khong tim thay '$tool' trong PATH. Vui long cai dat truoc."
    }
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


# 2. Cau hinh host/port/publicUrl
Write-Host ""
Write-Host "==> Cau hinh mang cho DSH Web Runner..." -ForegroundColor Cyan
$defaultHost = "127.0.0.1"
if ($env:DSH_HOST) { $defaultHost = $env:DSH_HOST }
$inputHost = if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) { $defaultHost } else { Read-Host "Nhap DSH Host [Mac dinh: $defaultHost]" }
$dshHost = if ([string]::IsNullOrWhiteSpace($inputHost)) { $defaultHost } else { $inputHost.Trim() }

$defaultPort = "8080"
if ($env:DSH_PORT) { $defaultPort = $env:DSH_PORT }
$inputPort = if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) { $defaultPort } else { Read-Host "Nhap DSH Port [Mac dinh: $defaultPort]" }
$dshPort = if ([string]::IsNullOrWhiteSpace($inputPort)) { $defaultPort } else { $inputPort.Trim() }

$defaultPublicUrl = "http://localhost:$dshPort"
if ($env:DSH_PUBLIC_URL) { $defaultPublicUrl = $env:DSH_PUBLIC_URL }
$inputPublicUrl = if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) { $defaultPublicUrl } else { Read-Host "Nhap DSH Public URL [Mac dinh: $defaultPublicUrl]" }
$dshPublicUrl = if ([string]::IsNullOrWhiteSpace($inputPublicUrl)) { $defaultPublicUrl } else { $inputPublicUrl.Trim() }

# 3. Cau hinh AI Provider
Write-Host ""
Write-Host "==> Cau hinh ket noi AI Provider..." -ForegroundColor Cyan
$defaultAiUrl = "http://localhost:20128/v1"
if ($env:AI_BASE_URL) { $defaultAiUrl = $env:AI_BASE_URL }
$inputAiUrl = if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) { $defaultAiUrl } else { Read-Host "Nhap AI Base URL [Mac dinh: $defaultAiUrl]" }
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

$env:DSH_HOST = $dshHost
$env:DSH_PORT = $dshPort
$env:DSH_PUBLIC_URL = $dshPublicUrl
$env:AI_BASE_URL = $aiBaseUrl
$env:AI_API_KEY = $aiApiKey

# 5. Chay truc tiep bootstrap.ps1
$bootstrapPath = Join-Path $PSScriptRoot "bootstrap.ps1"
if (-not (Test-Path $bootstrapPath)) {
    throw "Khong tim thay bootstrap.ps1 tai: $bootstrapPath"
}

$splat = @{
    DshHome = $DshHome
    DshProfileDir = $DshProfileDir
    CredentialsPath = $CredentialsPath
}
if ($Force) { $splat['Force'] = $true }
if ($OverwriteAll) { $splat['OverwriteAll'] = $true }
if ($DryRun) { $splat['DryRun'] = $true }
if ($SkipInstall) { $splat['SkipInstall'] = $true }
if ($enableMemorix) { $splat['EnableMemorix'] = $true } else { $splat['DisableMemorix'] = $true }

& $bootstrapPath @splat
