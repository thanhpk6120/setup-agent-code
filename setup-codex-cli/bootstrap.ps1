# Deprecated shim. The real installer is ../install.ps1 (single engine, all agents).
# This file only forwards to the shared engine so old commands keep working.
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)

$ErrorActionPreference = 'Stop'
$target = 'codex-cli'
$root = Split-Path -Parent $PSScriptRoot
Write-Warning "setup/codex-cli is deprecated: use `"$root\install.ps1 -Target $target`" instead."

# Legacy per-agent parameters are accepted and ignored (they are resolved from the manifest now).
$legacyWithValue = @('-OmpDir', '-ClaudeDir', '-ClaudeJson', '-OpenCodeDir', '-OpenCodeConfig', '-CodexDir', '-CodexConfig', '-DshHome', '-DshProfileDir', '-CredentialsPath', '-AgyDir', '-AgySettings', '-AgyKeybindings')
$engineArgs = @('--target', $target)
for ($i = 0; $i -lt $Rest.Count; $i++) {
    $item = $Rest[$i]
    if ($legacyWithValue -contains $item) { $i++; continue }
    if ($item -match '^-(Mcp|Preset|EnvFile)$') {
        $map = @{ Mcp = '--mcp'; Preset = '--preset'; EnvFile = '--env-file' }
        $engineArgs += $map[$item.Substring(1)]
        continue
    }
    if ($item -match '^-(DryRun|SkipInstall|Force|OverwriteAll|EnableMemorix|DisableMemorix|Yes|Doctor|Json|Strict|Quiet|Verbose|Help)$') {
        $map = @{
            DryRun = '--dry-run'; SkipInstall = '--skip-install'; Force = '--force'; OverwriteAll = '--overwrite-all'
            EnableMemorix = '--memorix'; DisableMemorix = '--no-memorix'
            Yes = '--yes'; Doctor = '--doctor'; Json = '--json'; Strict = '--strict'; Quiet = '--quiet'; Verbose = '--verbose'; Help = '--help'
        }
        $engineArgs += $map[$item.Substring(1)]
        continue
    }
    $engineArgs += $item
}

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { throw 'Khong tim thay Node.js >= 22.18.0 (can cho installer).' }
& node (Join-Path $root 'core/engine.mjs') @engineArgs
exit $LASTEXITCODE
