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
$tempDirInteractive = Join-Path $env:TEMP ("codex-test-interactive-" + [System.Guid]::NewGuid().ToString("N"))
$tempDirEbusy = Join-Path $env:TEMP ("codex-test-ebusy-" + [System.Guid]::NewGuid().ToString("N"))
$tempDirSkip = Join-Path $env:TEMP ("codex-test-skip-" + [System.Guid]::NewGuid().ToString("N"))
$mockSkipDir = $null
$mockEbusyDir = $null

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

    # =========================================================================
    # Test 5: Interactive input pipeline: thu tu prompt, wording agency, drive list
    # =========================================================================
    Write-Host "`n[Test 5] Interactive input pipeline: thu tu prompt, wording agency, drive list..." -ForegroundColor Cyan
    $inputs = @(
        'y', # Cai dat MCP memorix
        'y', # Cai dat Hook tich hop Memorix vao Codex CLI (ngay sau memorix)
        'y', # Cai dat MCP agency
        'n', # Cai dat MCP company-atlassian
        'n', # Cai dat MCP gitnexus
        'n', # Cai dat MCP context7
        'n', # Cai dat MCP glab
        'y', # Cai dat MCP cloakbrowser
        '1'  # Chon so thu tu o dia muon luu CloakBrowser
    )

    $interactiveCmd = "function global:Read-Host { param([string]`$p); Write-Host `$p; return [Console]::ReadLine() }; `$env:CI = ''; `$env:CLOAKBROWSER_DIR = ''; `$env:Path = '$mockBinDir;' + `$env:Path; `$env:AI_BASE_URL = 'https://test.local'; `$env:AI_API_KEY = 'k'; `$env:JIRA_URL = 'https://test.jira'; `$env:JIRA_PERSONAL_TOKEN = 't'; `$env:CONFLUENCE_URL = 'https://test.conf'; `$env:CONFLUENCE_PERSONAL_TOKEN = 't'; `$env:CONTEXT7_API_KEY = 't'; & '$PSScriptRoot\bootstrap.ps1' -DryRun:`$false -CodexDir '$tempDirInteractive'"

    $procOut = $inputs | pwsh -NoProfile -Command $interactiveCmd 2>&1
    $procText = ($procOut | Out-String)

    # 1. Assert wording agency moi
    if ($procText -notmatch "\[\?\] Cai dat MCP 'agency' \(multi-agent orchestration\)\? \[y/N\]") {
        throw "ASSERTION FAILED: Missing or incorrect agency prompt wording. Output:`n$procText"
    }

    # 2. Assert thu tu: hook ngay sau MCP memorix, truoc agency
    $idxMem = $procText.IndexOf("[?] Cai dat MCP 'memorix'?")
    $idxHook = $procText.IndexOf("[?] Cai dat Hook tich hop Memorix vao Codex CLI?")
    $idxAgency = $procText.IndexOf("[?] Cai dat MCP 'agency' (multi-agent orchestration)?")
    if ($idxMem -lt 0 -or $idxHook -lt 0 -or $idxAgency -lt 0) {
        throw "ASSERTION FAILED: Missing prompts in interactive test. Output:`n$procText"
    }
    if (-not ($idxMem -lt $idxHook -and $idxHook -lt $idxAgency)) {
        throw "ASSERTION FAILED: Hook prompt must immediately follow memorix install prompt and precede agency prompt"
    }

    # 3. Assert danh sach o dia CloakBrowser
    if ($procText -notmatch "(?s)Danh sach o dia kha dung:.*Chon so thu tu o dia muon luu CloakBrowser") {
        throw "ASSERTION FAILED: CloakBrowser drive selection prompt missing or incorrect. Output:`n$procText"
    }

    # =========================================================================
    # Test 6: EBUSY / lancedb.node resilience: warn va tiep tuc, KHONG throw
    # =========================================================================
    Write-Host "`n[Test 6] Kiem tra EBUSY resilience tren npm install -g memorix..." -ForegroundColor Cyan
    $mockEbusyDir = Join-Path $env:TEMP ("codex-mock-ebusy-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $mockEbusyDir | Out-Null
    Set-Content -Path (Join-Path $mockEbusyDir "npm.cmd") -Value "@echo off`nif `"%1`"==`"install`" (echo npm error code EBUSY & echo npm error syscall unlink & echo npm error path C:\nvm4w\nodejs\node_modules\memorix\node_modules\@lancedb\vectordb-win32-x64-msvc\lancedb.node & exit /b 1)`nif `"%1`"==`"root`" if `"%2`"==`"-g`" (echo $mockNpmDir& exit /b 0)`nexit /b 0"
    Set-Content -Path (Join-Path $mockEbusyDir "gitnexus.cmd") -Value "@echo off`necho gitnexus"
    Set-Content -Path (Join-Path $mockEbusyDir "memorix.cmd") -Value "@echo off`necho memorix"
    Set-Content -Path (Join-Path $mockEbusyDir "agency-mcp-server.cmd") -Value "@echo off`necho agency"

    $ebusyCmd = "`$env:Path = '$mockEbusyDir;' + `$env:Path; & '$PSScriptRoot\bootstrap.ps1' -DryRun:`$false -Force -EnableMemorix -CodexDir '$tempDirEbusy'"
    $ebusyOut = pwsh -NoProfile -Command $ebusyCmd 2>&1
    $ebusyText = ($ebusyOut | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "ASSERTION FAILED: bootstrap aborted on EBUSY (ExitCode=$LASTEXITCODE). Output:`n$ebusyText"
    }
    if ($ebusyText -notmatch "Cai dat/cap nhat Memorix gap loi EBUSY: file lancedb\.node dang bi tien trinh khac khoa") {
        throw "ASSERTION FAILED: Missing clear EBUSY warning message. Output:`n$ebusyText"
    }
    # =========================================================================
    # Test 7: Skip memorix install when already latest version
    # =========================================================================
    Write-Host "`n[Test 7] Skip memorix install when version is latest..." -ForegroundColor Cyan
    $mockSkipDir = Join-Path $env:TEMP ("codex-mock-skip-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $mockSkipDir | Out-Null
    Set-Content -Path (Join-Path $mockSkipDir "memorix.cmd") -Value "@echo off`nif `"%1`"==`"--version`" (echo 1.5.0& exit /b 0)`necho memorix"
    Set-Content -Path (Join-Path $mockSkipDir "npm.cmd") -Value "@echo off`nif `"%1`"==`"view`" if `"%2`"==`"memorix`" if `"%3`"==`"version`" (echo 1.5.0& exit /b 0)`nif `"%1`"==`"install`" if `"%3`"==`"memorix`" (echo FAIL_SHOULD_NOT_INSTALL& exit /b 1)`nif `"%1`"==`"root`" if `"%2`"==`"-g`" (echo $mockNpmDir& exit /b 0)`nexit /b 0"
    Set-Content -Path (Join-Path $mockSkipDir "gitnexus.cmd") -Value "@echo off`necho gitnexus"
    Set-Content -Path (Join-Path $mockSkipDir "agency-mcp-server.cmd") -Value "@echo off`necho agency"

    $skipCmd = "`$env:Path = '$mockSkipDir;' + `$env:Path; & '$PSScriptRoot\bootstrap.ps1' -DryRun:`$false -Force -EnableMemorix -CodexDir '$tempDirSkip'"
    $skipOut = pwsh -NoProfile -Command $skipCmd 2>&1
    $skipText = ($skipOut | Out-String)
    if ($skipText -notmatch "Memorix da moi nhat, bo qua cai dat") {
        throw "ASSERTION FAILED: Expected skip message when memorix is latest. Output:`n$skipText"
    }
    if ($skipText -match "FAIL_SHOULD_NOT_INSTALL") {
        throw "ASSERTION FAILED: npm install was called despite memorix being latest. Output:`n$skipText"
    }
    Write-Host "`nAll isolated tests passed successfully for setup-codex-cli!" -ForegroundColor Green
}
finally {
    $env:Path = $oldPath
    Safe-Trash -Path $tempDir
    Safe-Trash -Path $tempDir2
    Safe-Trash -Path $mockBinDir
    Safe-Trash -Path $mockNpmDir
    Safe-Trash -Path $tempDirInteractive
    Safe-Trash -Path $tempDirEbusy
    if ($mockEbusyDir) { Safe-Trash -Path $mockEbusyDir }
    Safe-Trash -Path $tempDirSkip
    if ($mockSkipDir) { Safe-Trash -Path $mockSkipDir }
}
