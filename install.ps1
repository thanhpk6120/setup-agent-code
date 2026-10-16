# install.ps1 - Unified dispatcher cho setup-agent-code (root)
# Dieu phoi cai dat chung cho tat ca agent CLI, KHONG sua logic ben trong cac setup con.
# Chi doc $env:SETUP_TARGET va tham so -Target de chon dispatch sang setup-<target>/bootstrap.ps1.
[CmdletBinding()]
param(
    [ValidateSet('all', 'omp', 'claude-code', 'opencode', 'antigravity', 'codex-cli', 'dsh', 'antigravity-cli')]
    [string]$Target = 'all',
    [switch]$DryRun,
    [switch]$SkipInstall,
    [switch]$Force,
    [switch]$OverwriteAll,
    [switch]$EnableMemorix,
    [switch]$DisableMemorix
)

$ErrorActionPreference = 'Stop'

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

$AllowedTargets = @('all', 'omp', 'claude-code', 'opencode', 'antigravity', 'codex-cli', 'dsh', 'antigravity-cli')
$OrderedTargets = @('omp', 'claude-code', 'opencode', 'codex-cli', 'dsh', 'antigravity-cli')
$RepoZipUrl = 'https://github.com/thanhpk6120/setup-agent-code/archive/refs/heads/main.zip'

# 1. Giai quyet target: -Target uu tien, sau do $env:SETUP_TARGET (phuc vu online irm|iex), mac dinh 'all'.
$resolvedTarget = $Target
if (-not $PSBoundParameters.ContainsKey('Target')) {
    $envTarget = $env:SETUP_TARGET
    if (-not [string]::IsNullOrWhiteSpace($envTarget)) {
        $resolvedTarget = $envTarget.Trim().ToLowerInvariant() -replace '_', '-'
    }
} else {
    $resolvedTarget = $resolvedTarget.Trim().ToLowerInvariant() -replace '_', '-'
}
if ($resolvedTarget -eq 'antigravity') { $resolvedTarget = 'antigravity-cli' }
if ([string]::IsNullOrWhiteSpace($resolvedTarget)) { $resolvedTarget = 'all' }
if ($AllowedTargets -notcontains $resolvedTarget) {
    throw "Target khong hop le: '$resolvedTarget'. Hop le: $($AllowedTargets -join ', '). Hoac set `$env:SETUP_TARGET theo bang trong README."
}

if ($EnableMemorix.IsPresent -and $DisableMemorix.IsPresent) {
    throw 'Khong dung dong thoi -EnableMemorix va -DisableMemorix.'
}

$dispatchList = @()
if ($resolvedTarget -eq 'all') {
    $dispatchList = $OrderedTargets
} else {
    $dispatchList = @($resolvedTarget)
}

# 2. Xac dinh repo root: dung ban local neu co setup-*/bootstrap.ps1, neu khong thi tai zip monorepo.
function Get-LocalRepoRoot {
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $candidates += $PSScriptRoot }
    try { $candidates += (Get-Location).Path } catch {}
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if (Test-Path (Join-Path $candidate 'setup-omp/bootstrap.ps1')) { return $candidate }
        if (Test-Path (Join-Path $candidate 'setup-agent-code/setup-omp/bootstrap.ps1')) {
            return (Join-Path $candidate 'setup-agent-code')
        }
    }
    return $null
}

function Move-ToRecycleBinSafe([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path $Path)) { return }
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
        $item = Get-Item $Path -ErrorAction Stop
        if ($item.PSIsContainer) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                $Path,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
            )
        } else {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                $Path,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
            )
        }
        Write-Host "  [Thung rac] Da chuyen tam file vao Recycle Bin: $Path" -ForegroundColor DarkGray
    } catch {
        Write-Warning "Khong the chuyen vao Recycle Bin: $Path ($($_.Exception.Message))"
    }
}

$repoRoot = Get-LocalRepoRoot
$tempBase = $null
$zipFile = $null
$downloaded = $false

try {
    if ($null -eq $repoRoot) {
        $tempParent = $env:TEMP
        if ([string]::IsNullOrWhiteSpace($tempParent)) { $tempParent = [System.IO.Path]::GetTempPath() }
        # Thu muc temp co dinh: chua repo va file .env de tai su dung giua cac lan chay
        $tempBase = Join-Path $tempParent 'setup-agent-code'
        $repoDir = Join-Path $tempBase 'repo'
        $zipFile = Join-Path $tempParent 'setup-agent-code-repo.zip'
        if (-not (Test-Path $tempBase)) { New-Item -ItemType Directory -Path $tempBase -Force | Out-Null }
        
        $gitCmd = Get-Command "git" -ErrorAction SilentlyContinue
        $useGitClone = $false
        if ($gitCmd) {
            try {
                if (Test-Path (Join-Path $repoDir ".git")) {
                    Write-Host "==> Thu muc temp co dinh da ton tai: $repoDir. Cap nhat code moi nhat (git pull)..." -ForegroundColor Cyan
                    git -C $repoDir fetch --quiet 2>$null
                    git -C $repoDir checkout main --quiet 2>$null
                    git -C $repoDir pull --quiet 2>$null
                    $useGitClone = (Test-Path (Join-Path $repoDir 'setup-omp/bootstrap.ps1'))
                } else {
                    Write-Host "==> Clone monorepo ve thu muc temp co dinh: $repoDir..." -ForegroundColor Cyan
                    git clone --depth 1 https://github.com/thanhpk6120/setup-agent-code.git $repoDir --quiet 2>$null
                    if ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $repoDir 'setup-omp/bootstrap.ps1'))) {
                        $useGitClone = $true
                    }
                }
            } catch { $useGitClone = $false }
        }
        
        if (-not $useGitClone) {
            Write-Host '==> Tai monorepo setup-agent-code qua ZIP tu GitHub ve thu muc temp co dinh...' -ForegroundColor Cyan
            Write-Host "    URL: $RepoZipUrl" -ForegroundColor DarkGray
            Invoke-WebRequest -Uri $RepoZipUrl -OutFile $zipFile -UseBasicParsing
            Write-Host '==> Giai nen goi cai dat vao thu muc temp co dinh...' -ForegroundColor Cyan
            if (-not (Test-Path $repoDir)) { New-Item -ItemType Directory -Path $repoDir -Force | Out-Null }
            Expand-Archive -Path $zipFile -DestinationPath $repoDir -Force
            $extractedRoot = Join-Path $repoDir 'setup-agent-code-main'
            if (-not (Test-Path $extractedRoot)) {
                $found = Get-ChildItem -Directory $repoDir | Where-Object { Test-Path (Join-Path $_.FullName 'setup-omp/bootstrap.ps1') } | Select-Object -First 1
                if ($found) { $extractedRoot = $found.FullName }
            }
            if (-not $extractedRoot -or -not (Test-Path (Join-Path $extractedRoot 'setup-omp/bootstrap.ps1'))) {
                if (Test-Path (Join-Path $repoDir 'setup-omp/bootstrap.ps1')) { $extractedRoot = $repoDir }
                else { throw 'Loi: Khong tim thay setup-omp/bootstrap.ps1 trong goi tai ve.' }
            }
            $repoDir = $extractedRoot
        }
        
        # Bao ve va dong bo file .env giua tempBase va repoDir
        $envInTemp = Join-Path $tempBase ".env"
        $envInRepo = Join-Path $repoDir ".env"
        if ((Test-Path $envInTemp) -and -not (Test-Path $envInRepo)) {
            Copy-Item -LiteralPath $envInTemp -Destination $envInRepo -Force
        }
        
        $repoRoot = $repoDir
        $downloaded = $true
    } else {
        Write-Host "==> Dung ma nguon local: $repoRoot" -ForegroundColor DarkGray
    }

    Write-Host '================================================================' -ForegroundColor Cyan
    Write-Host "          SETUP-AGENT-CODE DISPATCHER - TARGET: $resolvedTarget" -ForegroundColor Cyan
    Write-Host '================================================================' -ForegroundColor Cyan

    $psExe = Join-Path $PSHOME 'pwsh.exe'
    if (-not (Test-Path $psExe)) { $psExe = Join-Path $PSHOME 'powershell.exe' }
    if (-not (Test-Path $psExe)) { $psExe = 'powershell' }

    $index = 0
    $total = $dispatchList.Count
    $skipped = @()
    foreach ($t in $dispatchList) {
        $index++
        $dirName = "setup-$t"
        $bootstrapScript = Join-Path $repoRoot "$dirName/bootstrap.ps1"
        Write-Host ''
        Write-Host '----------------------------------------------------------------' -ForegroundColor Cyan
        Write-Host " [$index/$total] TARGET: $t -- $dirName/bootstrap.ps1" -ForegroundColor Cyan
        Write-Host '----------------------------------------------------------------' -ForegroundColor Cyan
        $bootstrapParams = @{}
        if ($PSBoundParameters.ContainsKey('DryRun')) { $bootstrapParams['DryRun'] = $DryRun }
        if ($PSBoundParameters.ContainsKey('SkipInstall')) { $bootstrapParams['SkipInstall'] = $SkipInstall }
        if ($PSBoundParameters.ContainsKey('Force')) { $bootstrapParams['Force'] = $Force }
        if ($PSBoundParameters.ContainsKey('OverwriteAll')) { $bootstrapParams['OverwriteAll'] = $OverwriteAll }
        if ($PSBoundParameters.ContainsKey('EnableMemorix')) { $bootstrapParams['EnableMemorix'] = $EnableMemorix }
        if ($PSBoundParameters.ContainsKey('DisableMemorix')) { $bootstrapParams['DisableMemorix'] = $DisableMemorix }
        $paramList = @()
        foreach ($key in $bootstrapParams.Keys) {
            if ($bootstrapParams[$key] -eq $true) {
                $paramList += "-$key"
            } else {
                $paramList += "-$key", "$($bootstrapParams[$key])"
            }
        }
        $displayArgs = if ($paramList.Count -gt 0) { ' ' + ($paramList -join ' ') } else { '' }

        if (-not (Test-Path $bootstrapScript)) {
            if ($DryRun) {
                Write-Host " [DryRun] Would dispatch target '$t': $bootstrapScript$displayArgs (placeholder, chua co bootstrap.ps1 -- se bo qua)." -ForegroundColor Yellow
            }
            Write-Warning "Bo qua target '$t': khong tim thay $dirName/bootstrap.ps1 (placeholder, chua co logic)."
            $skipped += $t
            continue
        }

        if ($DryRun -and [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('AI_API_KEY', 'Process'))) {
            $env:AI_API_KEY = 'dryrun-key'
            Write-Host " [DryRun] Dat fallback `$env:AI_API_KEY='dryrun-key' de bootstrap con chay -DryRun khong throw." -ForegroundColor DarkGray
        }

        Write-Host "==> Dispatch: $bootstrapScript$displayArgs" -ForegroundColor Cyan
        $argsArray = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $bootstrapScript) + $paramList
        & $psExe $argsArray
        if ($LASTEXITCODE -ne 0) { throw "$dirName/bootstrap.ps1 that bai voi exit code $LASTEXITCODE (target '$t')." }
        Write-Host "==> Hoan thanh target '$t'." -ForegroundColor Green
    }

    Write-Host ''
    Write-Host '================================================================' -ForegroundColor Green
    Write-Host " HOAN THANH DISPATCH TARGET: $resolvedTarget" -ForegroundColor Green
    if ($skipped.Count -gt 0) {
        Write-Host (" Bo qua placeholder (chua co bootstrap): " + ($skipped -join ', ')) -ForegroundColor Yellow
    }
    Write-Host '================================================================' -ForegroundColor Green
} finally {
    if ($downloaded) {
        if ($zipFile -and (Test-Path $zipFile)) { Move-ToRecycleBinSafe -Path $zipFile }
        # Giu lai thu muc temp co dinh $tempBase de luu .env va cau hinh resume cho lan chay sau
        # if ($tempBase -and (Test-Path $tempBase)) { Move-ToRecycleBinSafe -Path $tempBase }
    }
}
