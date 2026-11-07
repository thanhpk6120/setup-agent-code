# install.ps1 - Windows launcher for the setup-agent-code engine.
# All ordering/option logic lives in core/engine.mjs (shared with macOS/Linux).
# NOTE: no [CmdletBinding()] here - it would reserve -Verbose and clash with our -Verbose switch.
param(
    [ValidateSet('all', 'omp', 'claude-code', 'opencode', 'codex-cli', 'dsh', 'antigravity', 'antigravity-cli', 'goose', 'roo', 'roo-code')]
    [string]$Target = 'all',
    [switch]$DryRun,
    [switch]$SkipInstall,
    [switch]$Force,
    [switch]$OverwriteAll,
    [switch]$EnableMemorix,
    [switch]$DisableMemorix,
    [string]$Mcp,
    [string]$Preset,
    [switch]$Yes,
    [switch]$Doctor,
    [switch]$Json,
    [string]$Report,
    [switch]$Strict,
    [switch]$Quiet,
    [switch]$Verbose,
    [string]$EnvFile,
    [switch]$Version,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }

$RepoZipUrl = 'https://github.com/thanhpk6120/setup-agent-code/archive/refs/heads/main.zip'
$RepoGitUrl = 'https://github.com/thanhpk6120/setup-agent-code.git'

function Test-EngineRoot([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return (Test-Path -LiteralPath (Join-Path $Path 'core/engine.mjs'))
}

function Get-EngineRoot {
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $candidates += $PSScriptRoot }
    try { $candidates += (Get-Location).Path } catch {}
    foreach ($candidate in $candidates) {
        if (Test-EngineRoot $candidate) { return $candidate }
        if (Test-EngineRoot (Join-Path $candidate 'setup-agent-code')) { return (Join-Path $candidate 'setup-agent-code') }
    }

    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) 'setup-agent-code'
    $repoDir = Join-Path $tempBase 'repo'
    if (-not (Test-Path $tempBase)) { New-Item -ItemType Directory -Path $tempBase -Force | Out-Null }

    if (Get-Command git -ErrorAction SilentlyContinue) {
        try {
            if (Test-Path (Join-Path $repoDir '.git')) {
                git -C $repoDir fetch --quiet 2>$null
                git -C $repoDir checkout main --quiet 2>$null
                git -C $repoDir pull --quiet 2>$null
            } elseif (-not (Test-EngineRoot $repoDir)) {
                git clone --depth 1 $RepoGitUrl $repoDir --quiet 2>$null
            }
            if (Test-EngineRoot $repoDir) { return $repoDir }
        } catch { }
    }

    Write-Host '==> Tai monorepo setup-agent-code (ZIP)...' -ForegroundColor Cyan
    $zipFile = Join-Path $tempBase 'repo.zip'
    Invoke-WebRequest -Uri $RepoZipUrl -OutFile $zipFile -UseBasicParsing
    $extractDir = Join-Path $tempBase 'zip'
    if (Test-Path $extractDir) {
        Add-Type -AssemblyName Microsoft.VisualBasic
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
            $extractDir,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin,
            [Microsoft.VisualBasic.FileIO.UICancelOption]::ThrowException
        )
    }
    Expand-Archive -LiteralPath $zipFile -DestinationPath $extractDir -Force
    $found = Get-ChildItem -Directory $extractDir | Where-Object { Test-EngineRoot $_.FullName } | Select-Object -First 1
    if (-not $found) { throw 'Khong tim thay core/engine.mjs trong goi tai ve.' }
    return $found.FullName
}

$engineRoot = Get-EngineRoot
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    if ($DryRun -or $Doctor -or $SkipInstall -or $Help -or $Version) {
        throw 'Khong tim thay Node.js >= 22.18.0. Che do nay khong tu cai Node.js; cai dat tai https://nodejs.org roi chay lai.'
    }
    if (-not ($Yes -or $Force)) {
        if (-not [Environment]::UserInteractive -or [Console]::IsInputRedirected) {
            throw 'Khong the hoi xac nhan cai Node.js trong che do khong tuong tac. Cai dat tai https://nodejs.org hoac chay lai voi -Yes / -Force.'
        }
        $answer = Read-Host 'Chua co Node.js. Cho phep cai Node.js LTS bang winget? [y/N]'
        if ($answer -notmatch '^(?i:y|yes)$') {
            throw 'Khong duoc phep cai Node.js. Cai dat tai https://nodejs.org hoac chay lai voi -Yes / -Force.'
        }
    }
    Write-Host '==> Chua co Node.js, thu cai bang winget...' -ForegroundColor Yellow
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id OpenJS.NodeJS.LTS -e --silent --accept-source-agreements --accept-package-agreements | Out-Null
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
        $node = Get-Command node -ErrorAction SilentlyContinue
    }
}
if (-not $node) {
    throw 'Khong tim thay Node.js >= 22.18.0. Cai dat tai https://nodejs.org roi chay lai.'
}

# Map PowerShell switches to the shared engine flags.
$engineArgs = @((Join-Path $engineRoot 'core/engine.mjs'))
if ($PSBoundParameters.ContainsKey('Target')) { $engineArgs += @('--target', $Target) }
elseif (-not [string]::IsNullOrWhiteSpace($env:SETUP_TARGET)) { $engineArgs += @('--target', $env:SETUP_TARGET) }
if ($DryRun) { $engineArgs += '--dry-run' }
if ($SkipInstall) { $engineArgs += '--skip-install' }
if ($Force) { $engineArgs += '--force' }
if ($OverwriteAll) { $engineArgs += '--overwrite-all' }
if ($EnableMemorix) { $engineArgs += '--memorix' }
if ($DisableMemorix) { $engineArgs += '--no-memorix' }
if ($Mcp) { $engineArgs += @('--mcp', $Mcp) }
if ($Preset) { $engineArgs += @('--preset', $Preset) }
if ($Yes) { $engineArgs += '--yes' }
if ($Doctor) { $engineArgs += '--doctor' }
if ($Json) { $engineArgs += '--json' }
if ($Report) { $engineArgs += @('--report', $Report) }
if ($Strict) { $engineArgs += '--strict' }
if ($Quiet) { $engineArgs += '--quiet' }
if ($Verbose) { $engineArgs += '--verbose' }
if ($EnvFile) { $engineArgs += @('--env-file', $EnvFile) }
if ($Version) { $engineArgs += '--version' }
if ($Help) { $engineArgs += '--help' }

& node @engineArgs
exit $LASTEXITCODE
