[CmdletBinding()]
param(
    [string]$StorageDir,
    [string]$Cli,
    [string]$Profile,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$NoCleanSkills,
    [switch]$Json,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    throw 'Node.js >= 20 is required to run setup-agent-team-ide.'
}

$argsList = @()
if ($Help) { $argsList += '--help' }
if ($StorageDir) { $argsList += @('--storage-dir', $StorageDir) }
if ($Cli) { $argsList += @('--cli', $Cli) }
if ($Profile) { $argsList += @('--profile', $Profile) }
if ($DryRun) { $argsList += '--dry-run' }
if ($Force) { $argsList += '--force' }
if ($NoCleanSkills) { $argsList += '--no-clean-skills' }
if ($Json) { $argsList += '--json' }

$scriptPath = Join-Path $PSScriptRoot 'setup.mjs'
& node $scriptPath @argsList
exit $LASTEXITCODE
