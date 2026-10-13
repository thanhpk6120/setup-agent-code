# install.ps1 - One-line interactive installer for setup-codex-cli
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$OverwriteAll,
    [switch]$DryRun,
    [switch]$SkipInstall,
    [switch]$EnableMemorix,
    [switch]$DisableMemorix,
    [string]$CodexDir = "$env:USERPROFILE\.codex"
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
Write-Host "          SETUP-CODEX-CLI INSTALLER - INTERACTIVE SETUP         " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Kiem tra va ho tro cai dat Codex CLI trong PATH
Write-Host "==> Kiem tra Codex CLI trong he thong..." -ForegroundColor Cyan
$codexCmd = Get-Command "codex" -ErrorAction SilentlyContinue
if (-not $codexCmd) {
    Write-Host "[!] Codex CLI chua duoc cai dat trong PATH." -ForegroundColor Yellow
    $installPrompt = ""
    if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
        $installPrompt = "y"
    } else {
        $installPrompt = Read-Host "Codex CLI chua duoc cai dat. Ban co muon cai dat Codex CLI chinh goc ngay bay gio khong? [Y/n]"
    }
    if ([string]::IsNullOrWhiteSpace($installPrompt) -or $installPrompt.Trim().ToLower() -eq 'y') {
        Write-Host "==> Dang cai dat Codex CLI qua npm (npm install -g @openai/codex)..." -ForegroundColor Cyan
        try {
            npm install -g @openai/codex
            Write-Host "==> Cai dat Codex CLI hoan tat. Dang cap nhat PATH trong session hien tai..." -ForegroundColor Green

            $candidatePaths = @(
                (npm prefix -g 2>$null),
                (Join-Path $env:APPDATA "npm"),
                (Join-Path $env:LOCALAPPDATA "Programs\codex"),
                (Join-Path $env:USERPROFILE ".codex\bin")
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

            $codexCmd = Get-Command "codex" -ErrorAction SilentlyContinue
            if ($codexCmd) {
                Write-Host "==> Da tim thay Codex CLI tai: $($codexCmd.Source)" -ForegroundColor Green
            } else {
                Write-Host "[!] Da chay npm install nhung chua nhan dien duoc 'codex' trong session hien tai. Ban co the can mo lai terminal sau khi cai dat." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "[!] Loi khi cai dat Codex CLI: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "[!] Bo qua cai dat Codex CLI. Tiep tuc cau hinh moi truong setup-codex-cli..." -ForegroundColor Yellow
    }
} else {
    Write-Host "==> Da phat hien Codex CLI tai: $($codexCmd.Source)" -ForegroundColor Green
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

# 4. Tai va giai nen setup-codex-cli tu GitHub
$zipUrl = "https://github.com/thanhpk6120/setup-codex-cli/archive/refs/heads/main.zip"
$tempBase = Join-Path $env:TEMP ("codex-install-" + [System.Guid]::NewGuid().ToString("N"))
$zipFile = Join-Path $env:TEMP ("codex-repo-" + [System.Guid]::NewGuid().ToString("N") + ".zip")

try {
    Write-Host ""
    Write-Host "==> Downloading setup-codex-cli package from GitHub..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile -UseBasicParsing

    Write-Host "==> Extracting files..." -ForegroundColor Cyan
    Expand-Archive -Path $zipFile -DestinationPath $tempBase -Force

    $extractedRoot = Join-Path $tempBase "setup-codex-cli-main"
    if (-not (Test-Path $extractedRoot)) {
        $found = Get-ChildItem -Directory $tempBase | Select-Object -First 1
        if ($found) { $extractedRoot = $found.FullName }
    }

    $bootstrapScript = Join-Path $extractedRoot "bootstrap.ps1"
    if (-not (Test-Path $bootstrapScript)) {
        throw "Loi: Khong tim thay bootstrap.ps1 trong goi cai dat."
    }

    $envFilePath = Join-Path $extractedRoot ".env"
    $envContent = @"
AI_BASE_URL=$aiBaseUrl
AI_API_KEY=$aiApiKey
"@
    Set-Content -Path $envFilePath -Value $envContent -Encoding utf8

    Write-Host "==> Launching bootstrap..." -ForegroundColor Cyan
    $bootstrapParams = @{}
    if ($PSBoundParameters.ContainsKey('Force')) { $bootstrapParams['Force'] = $Force }
    if ($PSBoundParameters.ContainsKey('OverwriteAll')) { $bootstrapParams['OverwriteAll'] = $OverwriteAll }
    if ($PSBoundParameters.ContainsKey('DryRun')) { $bootstrapParams['DryRun'] = $DryRun }
    if ($PSBoundParameters.ContainsKey('SkipInstall')) { $bootstrapParams['SkipInstall'] = $SkipInstall }
    if ($PSBoundParameters.ContainsKey('CodexDir')) { $bootstrapParams['CodexDir'] = $CodexDir }
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
    if (Test-Path $tempBase) { Safe-Trash -Path $tempBase }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host " CAI DAT THANH CONG CHO CODEX CLI!" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
