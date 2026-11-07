$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$targets = @('antigravity-cli', 'claude-code', 'codex-cli', 'dsh', 'goose', 'omp', 'opencode', 'roo-code')

function node {
    $global:capturedNodeArgs = @($args)
    $global:LASTEXITCODE = 0
}

foreach ($target in $targets) {
    $shim = Join-Path $root "setup-$target/install.ps1"
    foreach ($case in @(
        @{ Name = 'default'; Expected = @() },
        @{ Name = 'verbose true'; Expected = @('--verbose') },
        @{ Name = 'verbose false'; Expected = @() },
        @{ Name = 'version'; Expected = @('--version') },
        @{ Name = 'combined'; Expected = @('--verbose', '--version') }
    )) {
        $global:capturedNodeArgs = $null
        switch ($case.Name) {
            'default' { & $shim -WarningAction SilentlyContinue }
            'verbose true' { & $shim -Verbose -WarningAction SilentlyContinue }
            'verbose false' { & $shim -Verbose:$false -WarningAction SilentlyContinue }
            'version' { & $shim -Version -WarningAction SilentlyContinue }
            'combined' { & $shim -Verbose -Version -WarningAction SilentlyContinue }
        }
        $expected = @((Join-Path $root 'core/engine.mjs'), '--target', $target) + $case.Expected
        if (($global:capturedNodeArgs | ConvertTo-Json -Compress) -ne ($expected | ConvertTo-Json -Compress)) {
            throw "$target $($case.Name): unexpected node arguments: $($global:capturedNodeArgs | ConvertTo-Json -Compress)"
        }
    }
}
Write-Host "PASS: $(@($targets).Count * 5) mocked shim cases"
