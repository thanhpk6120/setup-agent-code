# test-bootstrap.ps1 - Assert-based test for setup-antigravity-cli bootstrap script
$ErrorActionPreference = "Stop"
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }
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

$tempDir = Join-Path $env:TEMP ("agy-test-" + [System.Guid]::NewGuid().ToString("N"))
$tempDir2 = Join-Path $env:TEMP ("agy-test2-" + [System.Guid]::NewGuid().ToString("N"))
$tempDir3 = Join-Path $env:TEMP ("agy-test3-" + [System.Guid]::NewGuid().ToString("N"))
$tempDirInteractive = Join-Path $env:TEMP ("agy-test-interactive-" + [System.Guid]::NewGuid().ToString("N"))
$tempDirEbusy = Join-Path $env:TEMP ("agy-test-ebusy-" + [System.Guid]::NewGuid().ToString("N"))
$mockEbusyDir = Join-Path $env:TEMP ("agy-mock-ebusy-" + [System.Guid]::NewGuid().ToString("N"))
$mockSkipDir = Join-Path $env:TEMP ("agy-mock-skip-" + [System.Guid]::NewGuid().ToString("N"))
$tempDirSkip = Join-Path $env:TEMP ("agy-test-skip-" + [System.Guid]::NewGuid().ToString("N"))
$mockBinDir = Join-Path $env:TEMP ("agy-mock-bin-" + [System.Guid]::NewGuid().ToString("N"))
$mockNpmDir = Join-Path $env:TEMP ("agy-mock-npm-" + [System.Guid]::NewGuid().ToString("N"))
$hookLog = Join-Path $env:TEMP ("agy-hooklog-" + [System.Guid]::NewGuid().ToString("N"))
$oldPath = $env:Path

try {
    $env:AI_BASE_URL = "https://test.local"
    $env:AI_API_KEY = "test-key-abc"
    $env:AGY_MODEL = "custom/claude-sonnet-5"
    $env:JIRA_URL = "https://test.jira"
    $env:JIRA_PERSONAL_TOKEN = "test-jira-token"
    $env:CONFLUENCE_URL = "https://test.conf"
    $env:CONFLUENCE_PERSONAL_TOKEN = "test-conf-token"
    $env:CONTEXT7_API_KEY = "test-ctx-token"

    # Setup mock environment for gitnexus, agency, npm, memorix
    New-Item -ItemType Directory -Force -Path $mockBinDir | Out-Null
    Set-Content -Path (Join-Path $mockBinDir "gitnexus.cmd") -Value "@echo off`necho gitnexus"
    Set-Content -Path (Join-Path $mockBinDir "agency-mcp-server.cmd") -Value "@echo off`necho agency mock"
    Set-Content -Path (Join-Path $mockBinDir "npm.cmd") -Value "@echo off`necho %* | findstr /i `"root -g`" >nul && echo $mockNpmDir& exit /b 0`nexit /b 0"
    Set-Content -Path (Join-Path $mockBinDir "memorix.cmd") -Value "@echo off`r`necho %* >> `"$hookLog`""
    $env:Path = "$mockBinDir;$env:Path"

    $mockContext7Path = Join-Path $mockNpmDir "@upstash\context7-mcp\dist"
    New-Item -ItemType Directory -Force -Path $mockContext7Path | Out-Null
    Set-Content -Path (Join-Path $mockContext7Path "index.js") -Value "// mock"

    function global:npm {
        param([Parameter(ValueFromRemainingArguments)]$remaining)
        if ($remaining -contains "root" -and $remaining -contains "-g") {
            return $mockNpmDir
        }
        $realNpm = Get-Command npm.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($realNpm) {
            & $realNpm.Source @remaining
        }
    }

    # =========================================================================
    # Test 1: Chay bootstrap voi -SkipInstall (non-interactive, tat ca MCPs bi bo qua)
    # =========================================================================
    Write-Host "`n[Test 1] Chay bootstrap voi -SkipInstall non-interactive..." -ForegroundColor Cyan
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
    if ($settingsJson.mcpServers.PSObject.Properties['gitnexus'] -or $settingsJson.mcpServers.PSObject.Properties['company-atlassian'] -or $settingsJson.mcpServers.PSObject.Properties['agency']) {
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
    # Test 2: Chay bootstrap voi Pipeline Y (dong y tat ca MCP servers + hook ngay sau memorix)
    # =========================================================================
    Write-Host "`n[Test 2] Chay bootstrap voi Pipeline Y (dong y tat ca MCPs + hook)..." -ForegroundColor Cyan
    # Thứ tự: Memorix (y), Hook (y), Agency (y), Atlassian (y), Gitnexus (y), Context7 (y), Glab (y), Cloak (y), Drive (1)
    $acceptAll = "y`ny`ny`ny`ny`ny`ny`ny`n1`n"
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
    # Assert hook Memorix Antigravity da chay voi agent name dung
    $hookContent = if (Test-Path $hookLog) { Get-Content $hookLog -Raw } else { "" }
    if ($hookContent -notmatch 'hooks install --agent antigravity --global') {
        throw "ASSERTION FAILED: memorix hook not called with '--agent antigravity --global'. Got: $hookContent"
    }

    # =========================================================================
    # Test 3: -EnableAgency va -DisableAgency flag & marker AGENTS.md
    # =========================================================================
    Write-Host "`n[Test 3] Test -EnableAgency va -DisableAgency..." -ForegroundColor Cyan
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -EnableAgency -AgyDir $tempDir3
    $settingsObj3 = (Get-Content (Join-Path $tempDir3 "settings.json") -Raw) | ConvertFrom-Json
    if (-not $settingsObj3.mcpServers.agency) {
        throw "ASSERTION FAILED: settings.json missing 'agency' under -EnableAgency"
    }
    $agentsRaw3 = Get-Content (Join-Path $tempDir3 "AGENTS.md") -Raw
    if (-not $agentsRaw3.Contains("<!-- agency-agents-section -->")) {
        throw "ASSERTION FAILED: AGENTS.md missing agency marker under -EnableAgency"
    }

    # Idempotent: chay lai -EnableAgency khong duplicate marker
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -EnableAgency -AgyDir $tempDir3
    $agentsRaw3b = Get-Content (Join-Path $tempDir3 "AGENTS.md") -Raw
    $agencyMarkerCount = ([regex]::Matches($agentsRaw3b, [regex]::Escape("<!-- agency-agents-section -->"))).Count
    if ($agencyMarkerCount -ne 1) {
        throw "ASSERTION FAILED: agency marker duplicated (count=$agencyMarkerCount)"
    }

    # Chay lai voi -DisableAgency: go bo khoi settings va AGENTS.md
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -DisableAgency -AgyDir $tempDir3
    $settingsObj3c = (Get-Content (Join-Path $tempDir3 "settings.json") -Raw) | ConvertFrom-Json
    if ($settingsObj3c.mcpServers.agency) {
        throw "ASSERTION FAILED: settings.json still contains 'agency' under -DisableAgency"
    }
    $agentsRaw3c = Get-Content (Join-Path $tempDir3 "AGENTS.md") -Raw
    if ($agentsRaw3c.Contains("<!-- agency-agents-section -->")) {
        throw "ASSERTION FAILED: AGENTS.md still contains agency marker under -DisableAgency"
    }

    # =========================================================================
    # Test 4: Interactive input pipeline: thu tu prompt, wording agency, drive list
    # =========================================================================
    Write-Host "`n[Test 4] Interactive pipeline: thu tu prompt, wording agency, drive list..." -ForegroundColor Cyan
    $inputs = @(
        'y', # Cai dat MCP memorix
        'y', # Cai dat Hook tich hop Memorix vao Antigravity (ngay sau memorix)
        'y', # Cai dat MCP agency (multi-agent orchestration)
        'n', # Cai dat MCP company-atlassian
        'n', # Cai dat MCP gitnexus
        'n', # Cai dat MCP context7
        'n', # Cai dat MCP glab
        'y', # Cai dat MCP cloakbrowser
        '1'  # Chon so thu tu o dia muon luu CloakBrowser
    )

    $interactiveCmd = "function global:Read-Host { param([string]`$p); Write-Host `$p; return [Console]::ReadLine() }; `$env:CI = ''; `$env:Path = '$mockBinDir;' + `$env:Path; `$env:AI_BASE_URL = 'https://test.local'; `$env:AI_API_KEY = 'k'; `$env:AGY_MODEL = 'custom/claude-sonnet-5'; `$env:JIRA_URL = 'https://test.jira'; `$env:JIRA_PERSONAL_TOKEN = 't'; `$env:CONFLUENCE_URL = 'https://test.conf'; `$env:CONFLUENCE_PERSONAL_TOKEN = 't'; `$env:CONTEXT7_API_KEY = 't'; & '$PSScriptRoot\bootstrap.ps1' -DryRun:`$false -AgyDir '$tempDirInteractive'"

    $procOut = $inputs | pwsh -NoProfile -Command $interactiveCmd 2>&1
    $procText = ($procOut | Out-String)

    # 1. Assert wording agency moi
    if ($procText -notmatch "\[\?\] Cai dat MCP 'agency' \(multi-agent orchestration\)\? \[y/N\]") {
        throw "ASSERTION FAILED: Missing or incorrect agency prompt wording. Output:`n$procText"
    }

    # 2. Assert thu tu: hook ngay sau MCP memorix, truoc agency
    $idxMem = $procText.IndexOf("[?] Cai dat MCP 'memorix'? [y/N]")
    $idxHook = $procText.IndexOf("[?] Cai dat Hook tich hop Memorix vao Antigravity? [y/N]")
    $idxAgency = $procText.IndexOf("[?] Cai dat MCP 'agency' (multi-agent orchestration)? [y/N]")

    if ($idxMem -lt 0) { throw "ASSERTION FAILED: Memorix prompt not found in interactive output" }
    if ($idxHook -lt 0) { throw "ASSERTION FAILED: Memorix hook prompt not found in interactive output" }
    if ($idxAgency -lt 0) { throw "ASSERTION FAILED: Agency prompt not found in interactive output" }

    if (-not ($idxMem -lt $idxHook -and $idxHook -lt $idxAgency)) {
        throw "ASSERTION FAILED: Prompt order violated! Expected: Memorix ($idxMem) < Hook ($idxHook) < Agency ($idxAgency)"
    }

    # 3. Assert drive list co hien thi truoc prompt chon o CloakBrowser
    if ($procText -notmatch "Danh sach o dia kha dung") {
        throw "ASSERTION FAILED: CloakBrowser drive list was not displayed before prompt"
    }
    if ($procText -notmatch "Dung luong trong:") {
        throw "ASSERTION FAILED: CloakBrowser drive list missing free space details"
    }
    if ($procText -notmatch "Da chon o dia:") {
        throw "ASSERTION FAILED: Selected drive log line 'Da chon o dia:' not found"
    }

    # 4. Kiem tra settings.json sinh ra hop le
    $settingsObj4 = (Get-Content (Join-Path $tempDirInteractive "settings.json") -Raw) | ConvertFrom-Json
    if (-not $settingsObj4.mcpServers.memorix) {
        throw "ASSERTION FAILED: Interactive settings.json missing memorix"
    }
    if (-not $settingsObj4.mcpServers.agency) {
        throw "ASSERTION FAILED: Interactive settings.json missing agency"
    }
    if (-not $settingsObj4.mcpServers.cloakbrowser) {
        throw "ASSERTION FAILED: Interactive settings.json missing cloakbrowser"
    }
    if ($settingsObj4.mcpServers.'company-atlassian') {
        throw "ASSERTION FAILED: company-atlassian should have been skipped in interactive test"
    }
    Write-Host "  -> Interactive pipeline test PASS: Thu tu prompt, wording agency, drive list hop le." -ForegroundColor Green

    # =========================================================================
    # Test 5: Assert npm EBUSY khong abort bootstrap
    # =========================================================================
    Write-Host "`n[Test 5] Assert npm EBUSY khong abort bootstrap..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $mockEbusyDir | Out-Null
    $mockNpmContent = @'
@echo off
set "CMD_ARGS=%*"
echo %CMD_ARGS% | findstr /i "view" >nul
if %ERRORLEVEL% equ 0 (
    echo 9.9.9
    exit /b 0
)
echo %CMD_ARGS% | findstr /i "memorix" >nul
if %ERRORLEVEL% equ 0 (
    echo npm error code EBUSY
    echo npm error syscall unlink
    echo npm error path C:\mock\lancedb.node
    exit /b 1
)
exit /b 0
'@
    Set-Content -Path (Join-Path $mockEbusyDir "npm.cmd") -Value $mockNpmContent

    $prevEnvPath = $env:Path
    try {
        $env:Path = "$mockEbusyDir;$prevEnvPath"
        $ebusyOutput = & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -Force -EnableMemorix -AgyDir $tempDirEbusy *>&1 | Out-String

        if (-not (Test-Path (Join-Path $tempDirEbusy "settings.json"))) {
            throw "ASSERTION FAILED: bootstrap aborted on npm EBUSY; settings.json was not created"
        }
        if (-not (Test-Path (Join-Path $tempDirEbusy "keybindings.json"))) {
            throw "ASSERTION FAILED: bootstrap aborted on npm EBUSY; keybindings.json was not created"
        }
        if ($ebusyOutput -notmatch "EBUSY" -or $ebusyOutput -notmatch "lancedb\.node") {
            throw "ASSERTION FAILED: Warning for EBUSY/lancedb.node was not logged in output.`n$ebusyOutput"
        }
        Write-Host "  -> npm EBUSY da duoc xu ly thanh cong (logged warning va tiep tuc hoan tat bootstrap)." -ForegroundColor Green
    } finally {
        $env:Path = $prevEnvPath
    }

    # =========================================================================
    # Test 6: Skip npm install khi Memorix da o ban moi nhat
    # =========================================================================
    Write-Host "`n[Test 6] Skip npm install khi Memorix da o ban moi nhat..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $mockSkipDir | Out-Null
    Set-Content -Path (Join-Path $mockSkipDir "memorix.cmd") -Value "@echo off`necho 1.5.0"
    $skipNpmBat = @'
@echo off
set "CMD_ARGS=%*"
echo %CMD_ARGS% | findstr /i "view memorix version" >nul
if %ERRORLEVEL% equ 0 (
    echo 1.5.0
    exit /b 0
)
echo %CMD_ARGS% | findstr /i "install.*memorix" >nul
if %ERRORLEVEL% equ 0 (
    echo FATAL_CALLED_NPM_INSTALL
    exit /b 1
)
exit /b 0
'@
    Set-Content -Path (Join-Path $mockSkipDir "npm.cmd") -Value $skipNpmBat

    $prevEnvPath2 = $env:Path
    try {
        $env:Path = "$mockSkipDir;$prevEnvPath2"
        $skipOutput = & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -Force -EnableMemorix -AgyDir $tempDirSkip *>&1 | Out-String
        if ($skipOutput -notmatch "da o phien ban moi nhat") {
            throw "ASSERTION FAILED: Bootstrap did not log skip memorix install when version matches. Output:`n$skipOutput"
        }
        if ($skipOutput -match "FATAL_CALLED_NPM_INSTALL") {
            throw "ASSERTION FAILED: npm install was unexpectedly called even though memorix version is up to date"
        }
        Write-Host "  -> Skip npm install khi Memorix da moi nhat: PASS" -ForegroundColor Green
    } finally {
        $env:Path = $prevEnvPath2
    }

    # Test 7: regex go Memorix khong nuot Agency section
    Write-Host "`n[Test 7] Regex go Memorix khong nuot Agency section..." -ForegroundColor Cyan
    $sample = "Header`r`n`r`n## Memorix: Memory and Safety Gate`r`nmem body line`r`n`r`n<!-- agency-agents-section -->`r`n## Using Agency Agents MCP`r`nagency body`r`n<!-- /agency-agents-section -->`r`n"
    $cleaned = [regex]::Replace($sample, '(?s)\r?\n?## Memorix: Memory and Safety Gate.*?<!-- /memorix-section -->', '')
    $cleaned = [regex]::Replace($cleaned, "(?ms)\r?\n## Memorix: Memory and Safety Gate.*?(?=\r?\n(?:## |<!-- )|\z)", "")
    if ($cleaned -match 'Memorix: Memory and Safety Gate') { throw "ASSERTION FAILED: regex go Memorix khong sach" }
    if ($cleaned -notmatch 'Using Agency Agents MCP') { throw "ASSERTION FAILED: regex go Memorix nuot Agency section" }
    Write-Host "  -> Regex Memorix removal test PASS." -ForegroundColor Green

    Write-Host "`n================================================================" -ForegroundColor Green
    Write-Host "   TAT CA CAC BAI TEST CO LAP CHO SETUP-ANTIGRAVITY-CLI DA PASS! " -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
}
finally {
    $env:Path = $oldPath
    if (Test-Path Function:npm) { Microsoft.PowerShell.Management\Remove-Item Function:npm -ErrorAction SilentlyContinue }

    Safe-Trash -Path $tempDir
    Safe-Trash -Path $tempDir2
    Safe-Trash -Path $tempDir3
    Safe-Trash -Path $tempDirInteractive
    Safe-Trash -Path $tempDirEbusy
    Safe-Trash -Path $tempDirSkip
    Safe-Trash -Path $mockEbusyDir
    Safe-Trash -Path $mockSkipDir
    Safe-Trash -Path $mockBinDir
    Safe-Trash -Path $mockNpmDir
    Safe-Trash -Path $hookLog
}
