# test-bootstrap.ps1 - Assert-based test for setup-antigravity-cli bootstrap script
$ErrorActionPreference = "Stop"

$tempDir = Join-Path $env:TEMP ("agy-test-" + [System.Guid]::NewGuid().ToString("N"))
$tempDir2 = Join-Path $env:TEMP ("agy-test2-" + [System.Guid]::NewGuid().ToString("N"))

try {
    $env:AI_BASE_URL = "https://test.local"
    $env:AI_API_KEY = "test-key-abc"
    $env:AGY_MODEL = "custom/claude-sonnet-5"
    $env:JIRA_URL = "https://test.jira"
    $env:JIRA_PERSONAL_TOKEN = "test-jira-token"
    $env:CONFLUENCE_URL = "https://test.conf"
    $env:CONFLUENCE_PERSONAL_TOKEN = "test-conf-token"
    $env:CONTEXT7_API_KEY = "test-ctx-token"

    # Setup mock environment for gitnexus and context7
    $mockBinDir = Join-Path $env:TEMP ("agy-mock-bin-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $mockBinDir | Out-Null
    Set-Content -Path (Join-Path $mockBinDir "gitnexus.cmd") -Value "@echo off`necho gitnexus"
    Set-Content -Path (Join-Path $mockBinDir "npm.cmd") -Value "@echo off`necho %* | findstr /i `"root -g`" >nul && echo $mockNpmDir& exit /b 0`nexit /b 0"
    $oldPath = $env:Path
    $env:Path = "$mockBinDir;$env:Path"

    $mockNpmDir = Join-Path $env:TEMP ("agy-mock-npm-" + [System.Guid]::NewGuid().ToString("N"))
    $mockContext7Path = Join-Path $mockNpmDir "@upstash\context7-mcp\dist"
    New-Item -ItemType Directory -Force -Path $mockContext7Path | Out-Null
    Set-Content -Path (Join-Path $mockContext7Path "index.js") -Value "// mock"

    function global:npm {
        param([Parameter(ValueFromRemainingArguments)]$remaining)
        if ($remaining -contains "root" -and $remaining -contains "-g") {
            return $mockNpmDir
        }
    }

    # =========================================================================
    # Test 1: Chay bootstrap voi -SkipInstall (non-interactive, tat ca MCPs bi bo qua)
    # =========================================================================
    Write-Host "Running Antigravity bootstrap (Test 1: SkipInstall non-interactive) into: $tempDir"
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -AgyDir $tempDir

    # Assert settings.json & keybindings.json
    $settingsPath = Join-Path $tempDir "settings.json"
    $keybindingsPath = Join-Path $tempDir "keybindings.json"
    if (-not (Test-Path $settingsPath)) { throw "ASSERTION FAILED: Missing settings.json: $settingsPath" }
    if (-not (Test-Path $keybindingsPath)) { throw "ASSERTION FAILED: Missing keybindings.json: $keybindingsPath" }

    $settingsRaw = Get-Content $settingsPath -Raw
    $settingsJson = $settingsRaw | ConvertFrom-Json
    if ($settingsJson.model -ne "custom/claude-sonnet-5") {
        throw "ASSERTION FAILED: settings.json did not interpolate AGY_MODEL"
    }
    if ($settingsJson.toolPermission.default -ne "request-review") {
        throw "ASSERTION FAILED: settings.json missing toolPermission default request-review"
    }
    if (-not $settingsJson.artifactReviewPolicy) {
        throw "ASSERTION FAILED: settings.json missing artifactReviewPolicy"
    }
    if (-not $settingsJson.sandbox) {
        throw "ASSERTION FAILED: settings.json missing sandbox"
    }
    if (-not $settingsJson.telemetry) {
        throw "ASSERTION FAILED: settings.json missing telemetry"
    }
    if (-not $settingsRaw.Contains("PreToolUse")) {
        throw "ASSERTION FAILED: settings.json missing PreToolUse hooks"
    }

    # Test 1 skipped MCPs
    $settingsJson = $settingsRaw | ConvertFrom-Json
    if ($settingsJson.mcpServers.PSObject.Properties['gitnexus'] -or $settingsJson.mcpServers.PSObject.Properties['company-atlassian']) {
        throw "ASSERTION FAILED: In SkipInstall, skipped MCP servers should not be present"
    }

    # Assert static files
    $agentsPath = Join-Path $tempDir "AGENTS.md"
    if (-not (Test-Path $agentsPath)) { throw "ASSERTION FAILED: Missing copied AGENTS.md" }

    $skillsDir = Join-Path $tempDir "skills"
    if (-not (Test-Path $skillsDir)) { throw "ASSERTION FAILED: Missing copied skills/ directory" }
    $skillFiles = Get-ChildItem -Path $skillsDir -Recurse -Filter "SKILL.md"
    if ($skillFiles.Count -eq 0) { throw "ASSERTION FAILED: No SKILL.md found under skills/" }

    $hooksDir = Join-Path $tempDir "hooks"
    if (-not (Test-Path (Join-Path $hooksDir "trash-guard.ps1"))) {
        throw "ASSERTION FAILED: Missing hooks/trash-guard.ps1"
    }
    if (-not (Test-Path (Join-Path $hooksDir "antigravity-pre-tool.ps1"))) {
        throw "ASSERTION FAILED: Missing hooks/antigravity-pre-tool.ps1"
    }

    # =========================================================================
    # Test 2: Chay bootstrap voi Pipeline Y (dong y tat ca MCP servers)
    # =========================================================================
    Write-Host "`nRunning Antigravity bootstrap (Test 2: Pipeline Y - Accept MCPs) into: $tempDir2"
    $acceptAll = "n`ny`ny`ny`ny`ny`ny`n"
    $psScript = "$PSScriptRoot\bootstrap.ps1"
    $cmd = @"
        `$env:CI = `$null
        [Environment]::SetEnvironmentVariable('CI', `$null, 'Process')
        `$env:AI_BASE_URL = '$($env:AI_BASE_URL)'
        `$env:AI_API_KEY = '$($env:AI_API_KEY)'
        `$env:AGY_MODEL = '$($env:AGY_MODEL)'
        `$env:JIRA_URL = '$($env:JIRA_URL)'
        `$env:JIRA_PERSONAL_TOKEN = '$($env:JIRA_PERSONAL_TOKEN)'
        `$env:CONFLUENCE_URL = '$($env:CONFLUENCE_URL)'
        `$env:CONFLUENCE_PERSONAL_TOKEN = '$($env:CONFLUENCE_PERSONAL_TOKEN)'
        `$env:CONTEXT7_API_KEY = '$($env:CONTEXT7_API_KEY)'
        `$env:Path = '$($env:Path)'



        & '$psScript' -DryRun:`$false -AgyDir '$tempDir2'
"@
    $shellExe = if (Get-Command "pwsh" -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
    $acceptAll | & $shellExe -NoProfile -ExecutionPolicy Bypass -Command $cmd

    $settingsPath2 = Join-Path $tempDir2 "settings.json"
    if (-not (Test-Path $settingsPath2)) { throw "ASSERTION FAILED: Missing settings.json in Test 2" }
    $settingsRaw2 = Get-Content $settingsPath2 -Raw
    $settingsJson2 = $settingsRaw2 | ConvertFrom-Json

    if (-not $settingsJson2.mcpServers.PSObject.Properties['company-atlassian']) {
        throw "ASSERTION FAILED: company-atlassian should be configured in Test 2"
    }
    if (-not $settingsJson2.mcpServers.PSObject.Properties['gitnexus']) {
        throw "ASSERTION FAILED: gitnexus should be configured in Test 2"
    }
    if (-not $settingsJson2.mcpServers.PSObject.Properties['agency']) {
        throw "ASSERTION FAILED: agency should be configured in Test 2"
    }
    Write-Host "`n[OK] All isolated tests for setup-antigravity-cli passed successfully!" -ForegroundColor Green
}
finally {
    $env:Path = $oldPath
    if (Test-Path Function:npm) { Microsoft.PowerShell.Management\Remove-Item Function:npm -ErrorAction SilentlyContinue }

    Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
    function Safe-Trash($p) {
        if ($p -and (Test-Path $p)) {
            if (Get-Command "trash" -ErrorAction SilentlyContinue) {
                trash $p
            } else {
                try { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin) } catch {}
                try { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin) } catch {}
            }
        }
    }

    Safe-Trash $mockBinDir
    Safe-Trash $mockNpmDir
    Safe-Trash $tempDir
    Safe-Trash $tempDir2
}
