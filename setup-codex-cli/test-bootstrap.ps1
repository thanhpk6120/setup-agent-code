# test-bootstrap.ps1 - Assert-based test for setup-codex-cli bootstrap script
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

function Safe-Trash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
        $resolved = Convert-Path -LiteralPath $Path
        if ((Get-Item -LiteralPath $resolved) -is [System.IO.DirectoryInfo]) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                $resolved,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
            )
        } else {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                $resolved,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
            )
        }
    } catch {
        Write-Warning "Safe-Trash khong the chuyen vao Recycle Bin: $($_.Exception.Message)"
    }
}

$tempDir = Join-Path $env:TEMP ("codex-test-" + [System.Guid]::NewGuid().ToString("N"))
$tempDir2 = Join-Path $env:TEMP ("codex-test2-" + [System.Guid]::NewGuid().ToString("N"))
$mockBinDir = Join-Path $env:TEMP ("codex-mock-bin-" + [System.Guid]::NewGuid().ToString("N"))
$mockNpmDir = Join-Path $env:TEMP ("codex-mock-npm-" + [System.Guid]::NewGuid().ToString("N"))

$oldPath = $env:Path

try {
    $env:AI_BASE_URL = "https://test.local"
    $env:AI_API_KEY = "test-key-abc"
    $env:JIRA_URL = "https://test.jira"
    $env:JIRA_PERSONAL_TOKEN = "test-jira-token"
    $env:CONFLUENCE_URL = "https://test.conf"
    $env:CONFLUENCE_PERSONAL_TOKEN = "test-conf-token"
    $env:CONTEXT7_API_KEY = "test-ctx-token"

    # Setup mock environment for gitnexus and context7
    New-Item -ItemType Directory -Force -Path $mockBinDir | Out-Null
    Set-Content -Path (Join-Path $mockBinDir "gitnexus.cmd") -Value "@echo off`necho gitnexus"
    Set-Content -Path (Join-Path $mockBinDir "npm.cmd") -Value "@echo off`nif `"%1`"==`"root`" if `"%2`"==`"-g`" (echo $mockNpmDir& exit /b 0)`nexit /b 0"
    $env:Path = "$mockBinDir;$env:Path"

    $mockContext7Path = Join-Path $mockNpmDir "@upstash\context7-mcp\dist"
    New-Item -ItemType Directory -Force -Path $mockContext7Path | Out-Null
    Set-Content -Path (Join-Path $mockContext7Path "index.js") -Value "// mock"

    # =========================================================================
    # Test 1: Chay bootstrap voi -SkipInstall (non-interactive, all MCPs skipped)
    # =========================================================================
    Write-Host "Running Codex CLI bootstrap (Test 1: SkipInstall non-interactive) into: $tempDir"
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -CodexDir $tempDir

    $configFile = Join-Path $tempDir "config.toml"
    if (-not (Test-Path $configFile)) {
        throw "ASSERTION FAILED: Missing generated file: $configFile"
    }

    $tomlContent = Get-Content $configFile -Raw
    if (-not $tomlContent.Contains('base_url = "https://test.local"')) {
        throw "ASSERTION FAILED: base_url mismatch in config.toml"
    }
    if (-not $tomlContent.Contains('api_key = "test-key-abc"')) {
        throw "ASSERTION FAILED: api_key mismatch in config.toml"
    }
    if (-not $tomlContent.Contains('model_provider = "custom"')) {
        throw "ASSERTION FAILED: model_provider custom mismatch in config.toml"
    }
    if (-not $tomlContent.Contains('[model_providers.custom]')) {
        throw "ASSERTION FAILED: [model_providers.custom] missing in config.toml"
    }
    if (-not $tomlContent.Contains('project_doc_fallback_filenames = ["AGENTS.md", "CODEX.md"]')) {
        throw "ASSERTION FAILED: project_doc_fallback_filenames missing in config.toml"
    }

    foreach ($f in @("AGENTS.md", "CODEX.md")) {
        $p = Join-Path $tempDir $f
        if (-not (Test-Path $p)) {
            throw "ASSERTION FAILED: Missing copied static file: $p"
        }
    }
    foreach ($f in @("RULES.md", "SYSTEM.md")) {
        $p = Join-Path $tempDir $f
        if (Test-Path $p) {
            throw "ASSERTION FAILED: Legacy file should not exist: $p"
        }
    }

    $skillsDir = Join-Path $tempDir "skills"
    if (-not (Test-Path $skillsDir)) {
        throw "ASSERTION FAILED: Missing copied skills/ directory: $skillsDir"
    }
    $skillsCount = (Get-ChildItem $skillsDir -Directory).Count
    if ($skillsCount -lt 25) {
        throw "ASSERTION FAILED: Insufficient skills copied: $skillsCount"
    }

    # =========================================================================
    # Test 2: Chay bootstrap voi -Force (Tu dong cai dat tat ca MCP servers)
    # =========================================================================
    Write-Host "`nRunning Codex CLI bootstrap (Test 2: -Force accept all MCPs) into: $tempDir2"
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -CodexDir $tempDir2

    $configFile2 = Join-Path $tempDir2 "config.toml"
    if (-not (Test-Path $configFile2)) {
        throw "ASSERTION FAILED: Missing generated file: $configFile2"
    }

    $tomlContent2 = Get-Content $configFile2 -Raw
    if (-not $tomlContent2.Contains('[mcp_servers.gitnexus]')) {
        throw "ASSERTION FAILED: gitnexus missing in config.toml when -Force"
    }
    if (-not $tomlContent2.Contains('[mcp_servers.company-atlassian]')) {
        throw "ASSERTION FAILED: company-atlassian missing in config.toml when -Force"
    }
    if (-not $tomlContent2.Contains('[mcp_servers.context7]')) {
        throw "ASSERTION FAILED: context7 missing in config.toml when -Force"
    }
    if (-not $tomlContent2.Contains('[mcp_servers.cloakbrowser]')) {
        throw "ASSERTION FAILED: cloakbrowser missing in config.toml when -Force"
    }
    if (-not $tomlContent2.Contains('[mcp_servers.glab]')) {
        throw "ASSERTION FAILED: glab missing in config.toml when -Force"
    }
    if (-not $tomlContent2.Contains('[mcp_servers.memorix]')) {
        throw "ASSERTION FAILED: memorix missing in config.toml when -Force"
    }
    if (-not $tomlContent2.Contains('JIRA_URL = "https://test.jira"')) {
        throw "ASSERTION FAILED: JIRA_URL mismatch in config.toml"
    }
    if (-not $tomlContent2.Contains('CONTEXT7_API_KEY = "test-ctx-token"')) {
        throw "ASSERTION FAILED: CONTEXT7_API_KEY mismatch in config.toml"
    }

    # Kiem tra AGENTS.md va CODEX.md co chua noi dung huong dan memorix khi -Force
    $agentsRaw2 = Get-Content (Join-Path $tempDir2 "AGENTS.md") -Raw
    if (-not $agentsRaw2.Contains("Memorix: Memory and Safety Gate")) {
        throw "ASSERTION FAILED: AGENTS.md missing memorix section under -Force"
    }
    $codexRaw2 = Get-Content (Join-Path $tempDir2 "CODEX.md") -Raw
    if (-not $codexRaw2.Contains("Memorix: Memory and Safety Gate")) {
        throw "ASSERTION FAILED: CODEX.md missing memorix section under -Force"
    }

    # =========================================================================
    # Test 3: Kiem tra templates/ la nguon duy nhat
    # =========================================================================
    $tplConfig = Join-Path "$PSScriptRoot\templates" "config.toml"
    if (-not (Test-Path $tplConfig)) {
        throw "ASSERTION FAILED: templates/config.toml missing"
    }
    $tplConfigRaw = Get-Content $tplConfig -Raw
    if (-not $tplConfigRaw.Contains('[mcp_servers.memorix]')) {
        throw "ASSERTION FAILED: templates/config.toml missing [mcp_servers.memorix]"
    }
    $tplSkills = Join-Path "$PSScriptRoot\templates" "skills"
    if (-not (Test-Path $tplSkills)) {
        throw "ASSERTION FAILED: templates/skills missing"
    }

    
    # =========================================================================
    # Test 4: Kiem tra Agency MCP on/off
    # =========================================================================
    Write-Host "--- Test Agency MCP on/off ---" -ForegroundColor Cyan
    $testAgencyOnDir = Join-Path $tempDir "agency-on"
    & "$PSScriptRoot\bootstrap.ps1" -SkipInstall -EnableAgency -CodexDir $testAgencyOnDir -AgencyPath "C:/nvm4w/nodejs/agency-mcp-server.cmd"
    $tomlOn = Get-Content (Join-Path $testAgencyOnDir "config.toml") -Raw
    if ($tomlOn -notmatch '\[mcp_servers\.agency\]') { throw "Assert failed: agency server missing when -EnableAgency" }
    if ($tomlOn -notmatch 'agency-mcp-server\.cmd') { throw "Assert failed: agency command path missing when -EnableAgency" }
    $agentsOn = Get-Content (Join-Path $testAgencyOnDir "AGENTS.md") -Raw
    if ($agentsOn -notmatch 'Using Agency Agents MCP' -and $agentsOn -notmatch 'agency-agents-section') { throw "Assert failed: agency marker missing in AGENTS.md" }

    $testAgencyOffDir = Join-Path $tempDir "agency-off"
    & "$PSScriptRoot\bootstrap.ps1" -SkipInstall -DisableAgency -CodexDir $testAgencyOffDir
    $tomlOff = Get-Content (Join-Path $testAgencyOffDir "config.toml") -Raw
    if ($tomlOff -match '\[mcp_servers\.agency\]') { throw "Assert failed: agency server present when -DisableAgency" }

    Write-Host "`nAll isolated tests passed successfully for setup-codex-cli!" -ForegroundColor Green
}
finally {
    $env:Path = $oldPath
    Safe-Trash -Path $tempDir
    Safe-Trash -Path $tempDir2
    Safe-Trash -Path $mockBinDir
    Safe-Trash -Path $mockNpmDir
}
