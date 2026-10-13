# install.ps1 - Unified dispatcher cho setup-agent-code (root)
# Dieu phoi cai dat chung cho tat ca agent CLI, KHONG sua logic ben trong cac setup con.
# Chi doc $env:SETUP_TARGET va tham so -Target de chon dispatch sang setup-<target>/bootstrap.ps1.
[CmdletBinding()]
param(
    [ValidateSet('all', 'omp', 'claude-code', 'opencode', 'antigravity', 'codex-cli', 'dsh', 'antigravity-cli', 'dsh-web')]
    [string]$Target = 'all',
    [switch]$DryRun,
    [switch]$SkipInstall,
    [switch]$Force,
    [switch]$OverwriteAll,
    [switch]$EnableMemorix,
    [switch]$DisableMemorix
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$AllowedTargets = @('all', 'omp', 'claude-code', 'opencode', 'antigravity', 'codex-cli', 'dsh', 'antigravity-cli', 'dsh-web')
$OrderedTargets = @('omp', 'claude-code', 'opencode', 'codex-cli', 'dsh', 'antigravity-cli', 'dsh-web')
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
        $tempBase = Join-Path $tempParent ('setup-agent-code-' + [System.Guid]::NewGuid().ToString('N'))
        $zipFile = Join-Path $tempParent ('setup-agent-code-' + [System.Guid]::NewGuid().ToString('N') + '.zip')
        Write-Host '==> Khong thay setup con local. Tai monorepo setup-agent-code tu GitHub...' -ForegroundColor Cyan
        Write-Host "    URL: $RepoZipUrl" -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $RepoZipUrl -OutFile $zipFile -UseBasicParsing
        Write-Host '==> Giai nen goi cai dat...' -ForegroundColor Cyan
        Expand-Archive -Path $zipFile -DestinationPath $tempBase -Force
        $extractedRoot = Join-Path $tempBase 'setup-agent-code-main'
        if (-not (Test-Path $extractedRoot)) {
            $found = Get-ChildItem -Directory $tempBase | Select-Object -First 1
            if ($found) { $extractedRoot = $found.FullName }
        }
        if (-not (Test-Path (Join-Path $extractedRoot 'setup-omp/bootstrap.ps1'))) {
            throw 'Loi: Khong tim thay setup-omp/bootstrap.ps1 trong goi tai ve.'
        }
        $repoRoot = $extractedRoot
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
        if ($tempBase -and (Test-Path $tempBase)) { Move-ToRecycleBinSafe -Path $tempBase }
    }
}
