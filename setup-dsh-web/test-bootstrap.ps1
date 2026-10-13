# test-bootstrap.ps1 - Assert-based test for setup-dsh-web bootstrap script
$ErrorActionPreference = "Stop"

$tempHome = Join-Path $env:TEMP ("dsh-web-home-" + [System.Guid]::NewGuid().ToString("N"))
$tempProfile = Join-Path $env:TEMP ("dsh-web-prof-" + [System.Guid]::NewGuid().ToString("N"))
$tempProfile2 = Join-Path $env:TEMP ("dsh-web-prof2-" + [System.Guid]::NewGuid().ToString("N"))
$tempCredsDir = Join-Path $env:TEMP ("dsh-web-cred-" + [System.Guid]::NewGuid().ToString("N"))
$tempCreds = Join-Path $tempCredsDir ".credentials.yaml"

try {
    $env:AI_BASE_URL = "https://mock.provider.com/v1"
    $env:AI_API_KEY = "MOCK_AI_API_KEY"
    $env:DSH_HOST = "0.0.0.0"
    $env:DSH_PORT = "9090"
    $env:DSH_PUBLIC_URL = "https://agent.example.com"
    $env:DSH_TRUSTED_HOSTS = "agent.example.com,localhost"
    $env:DSH_TOOLS_MODE = "all"
    $env:JIRA_URL = "https://mock.jira.com"
    $env:JIRA_PERSONAL_TOKEN = "MOCK_JIRA_TOKEN"
    $env:CONFLUENCE_URL = "https://mock.conf.com"
    $env:CONFLUENCE_PERSONAL_TOKEN = "MOCK_CONF_TOKEN"
    $env:CONTEXT7_API_KEY = "MOCK_CONTEXT7_KEY"

    # Setup mock environment for gitnexus and context7
    $mockBinDir = Join-Path $env:TEMP ("dsh-web-bin-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $mockBinDir | Out-Null
    Set-Content -Path (Join-Path $mockBinDir "gitnexus.cmd") -Value "@echo off`necho gitnexus"
    $oldPath = $env:Path
    $env:Path = "$mockBinDir;$env:Path"

    $mockNpmDir = Join-Path $env:TEMP ("dsh-web-npm-" + [System.Guid]::NewGuid().ToString("N"))
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
    Write-Host "Running DSH Web bootstrap (Test 1: SkipInstall non-interactive) into: $tempProfile"
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -DshHome $tempHome -DshProfileDir $tempProfile -CredentialsPath $tempCreds

    $patchPath = Join-Path $tempProfile "cordis.patch.yml"
    if (-not (Test-Path $patchPath)) { throw "ASSERTION FAILED: Missing cordis.patch.yml: $patchPath" }

    $yamlRaw = Get-Content $patchPath -Raw
    # Assert Web Profile elements
    if (-not $yamlRaw.Contains('host: "0.0.0.0"')) {
        throw "ASSERTION FAILED: cordis.patch.yml missing host 0.0.0.0"
    }
    if (-not $yamlRaw.Contains('port: 9090')) {
        throw "ASSERTION FAILED: cordis.patch.yml missing port 9090"
    }
    if (-not $yamlRaw.Contains('publicUrl: "https://agent.example.com"')) {
        throw "ASSERTION FAILED: cordis.patch.yml missing publicUrl"
    }
    if (-not $yamlRaw.Contains('openBrowser: false')) {
        throw "ASSERTION FAILED: cordis.patch.yml should have openBrowser: false"
    }
    if (-not $yamlRaw.Contains('printUrl: true')) {
        throw "ASSERTION FAILED: cordis.patch.yml should have printUrl: true"
    }
    if (-not $yamlRaw.Contains('trustedHosts: ["agent.example.com", "localhost"]')) {
        throw "ASSERTION FAILED: cordis.patch.yml missing trustedHosts list"
    }
    if (-not $yamlRaw.Contains('id: session-query-sqlite')) {
        throw "ASSERTION FAILED: cordis.patch.yml missing session-query-sqlite block"
    }
    if (-not $yamlRaw.Contains('mode: "all"')) {
        throw "ASSERTION FAILED: cordis.patch.yml missing tools mode: all"
    }
    if (-not $yamlRaw.Contains('baseURL: https://mock.provider.com/v1')) {
        throw "ASSERTION FAILED: cordis.patch.yml did not interpolate AI_BASE_URL"
    }

    # KHONG duoc co desktop telemetry hay desktop UI presets
    if ($yamlRaw.Contains("ui-theme") -or $yamlRaw.Contains("ui-chat")) {
        throw "ASSERTION FAILED: cordis.patch.yml in web runner should not contain desktop UI presets"
    }

    # In SkipInstall, MCP servers should be stripped
    if ($yamlRaw.Contains("serverName: gitnexus") -or $yamlRaw.Contains("serverName: company-atlassian")) {
        throw "ASSERTION FAILED: Skipped MCP servers should not be present in cordis.patch.yml"
    }

    # Assert credentials.yaml
    if (-not (Test-Path $tempCreds)) { throw "ASSERTION FAILED: Missing credentials file: $tempCreds" }
    $credRaw = Get-Content $tempCreds -Raw
    if (-not $credRaw.Contains("ANTHROPIC_API_KEY: MOCK_AI_API_KEY")) {
        throw "ASSERTION FAILED: .credentials.yaml did not inject ANTHROPIC_API_KEY"
    }

    # Assert AGENTS.md & skills
    $agentsPath = Join-Path $tempHome "AGENTS.md"
    if (-not (Test-Path $agentsPath)) { throw "ASSERTION FAILED: Missing copied AGENTS.md" }

    $skillsDir = Join-Path $tempHome "skills"
    if (-not (Test-Path $skillsDir)) { throw "ASSERTION FAILED: Missing copied skills/ directory" }
    $skillFiles = Get-ChildItem -Path $skillsDir -Recurse -Filter "SKILL.md"
    if ($skillFiles.Count -eq 0) { throw "ASSERTION FAILED: No SKILL.md found under skills/" }

    # =========================================================================
    # Test 2: Chay bootstrap voi Pipeline Y (dong y tat ca MCP servers)
    # =========================================================================
    Write-Host "`nRunning DSH Web bootstrap (Test 2: Pipeline Y - Accept MCPs) into: $tempProfile2"
    $acceptAll = "n`ny`ny`ny`ny`ny`ny`n"
    $psScript = "$PSScriptRoot\bootstrap.ps1"
    $cmd = @"
        `$env:CI = `$null
        [Environment]::SetEnvironmentVariable('CI', `$null, 'Process')
        `$env:AI_BASE_URL = '$($env:AI_BASE_URL)'
        `$env:AI_API_KEY = '$($env:AI_API_KEY)'
        `$env:DSH_HOST = '127.0.0.1'
        `$env:DSH_PORT = '8080'
        `$env:DSH_PUBLIC_URL = 'http://localhost:8080'
        `$env:DSH_TRUSTED_HOSTS = 'localhost,127.0.0.1'
        `$env:DSH_TOOLS_MODE = 'all'
        `$env:JIRA_URL = '$($env:JIRA_URL)'
        `$env:JIRA_PERSONAL_TOKEN = '$($env:JIRA_PERSONAL_TOKEN)'
        `$env:CONFLUENCE_URL = '$($env:CONFLUENCE_URL)'
        `$env:CONFLUENCE_PERSONAL_TOKEN = '$($env:CONFLUENCE_PERSONAL_TOKEN)'
        `$env:CONTEXT7_API_KEY = '$($env:CONTEXT7_API_KEY)'
        `$env:Path = '$($env:Path)'

        function global:npm {
            param([Parameter(ValueFromRemainingArguments)]`$remaining)
            if (`$remaining -contains "root" -and `$remaining -contains "-g") {
                return '$mockNpmDir'
            }
        }

        & '$psScript' -DryRun:`$false -DshHome '$tempHome' -DshProfileDir '$tempProfile2' -CredentialsPath '$tempCreds'
"@
    $acceptAll | pwsh -NoProfile -ExecutionPolicy Bypass -Command $cmd

    $patchPath2 = Join-Path $tempProfile2 "cordis.patch.yml"
    if (-not (Test-Path $patchPath2)) { throw "ASSERTION FAILED: Missing cordis.patch.yml in Test 2" }
    $yamlRaw2 = Get-Content $patchPath2 -Raw

    if (-not $yamlRaw2.Contains("serverName: company-atlassian")) {
        throw "ASSERTION FAILED: company-atlassian should be configured in Test 2"
    }
    if (-not $yamlRaw2.Contains("serverName: gitnexus")) {
        throw "ASSERTION FAILED: gitnexus should be configured in Test 2"
    }

    
    # Test Agency MCP assertions
    Write-Host "--- Test Agency MCP on/off ---" -ForegroundColor Cyan
    $testHomeOn = Join-Path $tempHome "agency-home-on"
    $testProfileOn = Join-Path $tempProfile "agency-profile-on"
    $testCredsOn = Join-Path $tempCredsDir "agency-creds-on.yaml"
    & "$PSScriptRoot\bootstrap.ps1" -SkipInstall -EnableAgency -DshHome $testHomeOn -DshProfileDir $testProfileOn -CredentialsPath $testCredsOn -AgencyPath "C:/nvm4w/nodejs/agency-mcp-server.cmd"
    $cordisOn = Get-Content (Join-Path $testProfileOn "cordis.patch.yml") -Raw
    if ($cordisOn -notmatch 'id:\s*mcp-agency') { throw "Assert failed: mcp-agency missing when -EnableAgency" }
    $agentsOn = Get-Content (Join-Path $testHomeOn "AGENTS.md") -Raw
    if ($agentsOn -notmatch 'Sử dụng Agency Agents MCP') { throw "Assert failed: agency marker missing in AGENTS.md" }

    $testHomeOff = Join-Path $tempHome "agency-home-off"
    $testProfileOff = Join-Path $tempProfile "agency-profile-off"
    $testCredsOff = Join-Path $tempCredsDir "agency-creds-off.yaml"
    & "$PSScriptRoot\bootstrap.ps1" -SkipInstall -DisableAgency -DshHome $testHomeOff -DshProfileDir $testProfileOff -CredentialsPath $testCredsOff
    $cordisOff = Get-Content (Join-Path $testProfileOff "cordis.patch.yml") -Raw
    if ($cordisOff -match 'id:\s*mcp-agency') { throw "Assert failed: mcp-agency present when -DisableAgency" }

    Write-Host "`n[OK] All isolated tests for setup-dsh-web passed successfully!" -ForegroundColor Green
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
    Safe-Trash $tempHome
    Safe-Trash $tempProfile
    Safe-Trash $tempProfile2
    Safe-Trash $tempCredsDir
}
