# test-bootstrap.ps1 - Assert-based test for setup-opencode bootstrap script
$ErrorActionPreference = "Stop"
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }
Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

function Safe-Trash-Test {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        if ([System.IO.Directory]::Exists($Path)) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                $Path,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
            )
        } elseif ([System.IO.File]::Exists($Path)) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                $Path,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
            )
        }
    } catch {}
}

$tempDir = Join-Path $env:TEMP ("opencode-test-" + [System.Guid]::NewGuid().ToString("N"))
$tempDir2 = Join-Path $env:TEMP ("opencode-test2-" + [System.Guid]::NewGuid().ToString("N"))
$tempDir3 = Join-Path $env:TEMP ("opencode-test3-" + [System.Guid]::NewGuid().ToString("N"))
$tempDirInteractive = Join-Path $env:TEMP ("opencode-test-interactive-" + [System.Guid]::NewGuid().ToString("N"))
$tempDirEbusy = Join-Path $env:TEMP ("opencode-test-ebusy-" + [System.Guid]::NewGuid().ToString("N"))
$tempDirSkip = Join-Path $env:TEMP ("opencode-test-skip-" + [System.Guid]::NewGuid().ToString("N"))
$mockSkipDir = $null
$mockEbusyDir = $null

try {
    $env:AI_BASE_URL = "https://test.local"
    $env:AI_API_KEY = "test-key-abc"
    $env:JIRA_URL = "https://test.jira"
    $env:JIRA_PERSONAL_TOKEN = "test-jira-token"
    $env:CONFLUENCE_URL = "https://test.conf"
    $env:CONFLUENCE_PERSONAL_TOKEN = "test-conf-token"
    $env:CONTEXT7_API_KEY = "test-ctx-token"

    # Setup mock environment for gitnexus and context7
    $mockBinDir = Join-Path $env:TEMP ("opencode-mock-bin-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $mockBinDir | Out-Null
    Set-Content -Path (Join-Path $mockBinDir "gitnexus.cmd") -Value "@echo off`necho gitnexus"
    Set-Content -Path (Join-Path $mockBinDir "agency-mcp-server.cmd") -Value "@echo off`necho agency"
    Set-Content -Path (Join-Path $mockBinDir "npm.cmd") -Value "@echo off`nif `"%1`"==`"root`" if `"%2`"==`"-g`" (echo $mockNpmDir& exit /b 0)`nexit /b 0"
    $oldPath = $env:Path
    $env:Path = "$mockBinDir;$env:Path"

    $mockNpmDir = Join-Path $env:TEMP ("opencode-mock-npm-" + [System.Guid]::NewGuid().ToString("N"))
    $mockContext7Path = Join-Path $mockNpmDir "@upstash\context7-mcp\dist"
    New-Item -ItemType Directory -Force -Path $mockContext7Path | Out-Null
    Set-Content -Path (Join-Path $mockContext7Path "index.js") -Value "// mock"

    # =========================================================================
    # Test 1: Chay bootstrap voi -SkipInstall (non-interactive, all MCPs skipped)
    # =========================================================================
    Write-Host "Running OpenCode bootstrap (Test 1: SkipInstall non-interactive) into: $tempDir"
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -OpenCodeDir $tempDir

    $configFile = Join-Path $tempDir "opencode.json"
    if (-not (Test-Path $configFile)) {
        throw "ASSERTION FAILED: Missing generated file: $configFile"
    }

    $configObj = Get-Content $configFile -Raw | ConvertFrom-Json
    if ($configObj.provider.custom.apiKey -ne "test-key-abc") {
        throw "ASSERTION FAILED: apiKey mismatch in opencode.json"
    }
    if ($configObj.provider.custom.baseURL -ne "https://test.local") {
        throw "ASSERTION FAILED: baseURL mismatch in opencode.json"
    }

    # Kiem tra permission block chan hard-delete trong opencode.json
    if (-not $configObj.permission -or -not $configObj.permission.bash) {
        throw "ASSERTION FAILED: Missing permission.bash block in opencode.json"
    }
    if ($configObj.permission.bash.'rm *' -ne "deny") {
        throw "ASSERTION FAILED: Missing 'rm *' deny in permission.bash"
    }

    foreach ($f in @("AGENTS.md")) {
        $p = Join-Path $tempDir $f
        if (-not (Test-Path $p)) {
            throw "ASSERTION FAILED: Missing copied static file: $p"
        }
        $content = Get-Content $p -Raw -Encoding UTF8
        if ($content -notmatch "Recycle Bin" -and $content -notmatch "thung rac") {
            throw "ASSERTION FAILED: AGENTS.md missing Trash / Recycle Bin rule"
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
    $skillsCount = (Get-ChildItem -Path $skillsDir -Directory).Count
    if ($skillsCount -lt 25) {
        throw "ASSERTION FAILED: Expected >= 25 skills, got $skillsCount"
    }

    # Kiem tra plugin/hook chan xoa cung
    $pluginFile = Join-Path (Join-Path $tempDir "plugins") "no-hard-delete.js"
    $hookFile = Join-Path (Join-Path $tempDir "hooks") "no-hard-delete.js"
    if (-not (Test-Path $pluginFile) -and -not (Test-Path $hookFile)) {
        throw "ASSERTION FAILED: Missing Trash Guard plugin/hook in $tempDir"
    }

    # Kiem tra agency vang mat khi khong chon cai dat (Test 1)
    if ($configObj.mcp.PSObject.Properties['agency']) {
        throw "ASSERTION FAILED: agency should be absent in mcp block when not enabled"
    }
    $agentsContent1 = Get-Content (Join-Path $tempDir "AGENTS.md") -Raw -Encoding UTF8
    if ($agentsContent1 -match [regex]::Escape("<!-- agency-agents-section -->")) {
        throw "ASSERTION FAILED: AGENTS.md should NOT contain agency section when not enabled"
    }

    # =========================================================================
    # Test 2: Chay bootstrap voi -Force (Tu dong cai dat tat ca 6 MCP servers)
    # =========================================================================
    Write-Host "`nRunning OpenCode bootstrap (Test 2: -Force accept all MCPs) into: $tempDir2"
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -OpenCodeDir $tempDir2

    $configFile2 = Join-Path $tempDir2 "opencode.json"
    if (-not (Test-Path $configFile2)) {
        throw "ASSERTION FAILED: Missing generated file: $configFile2"
    }

    $configObj2 = Get-Content $configFile2 -Raw | ConvertFrom-Json
    if (-not $configObj2.mcp.gitnexus) {
        throw "ASSERTION FAILED: gitnexus missing in mcp block when -Force"
    }
    if ($configObj2.mcp.gitnexus.command[0] -ne "cmd") {
        throw "ASSERTION FAILED: gitnexus command should start with 'cmd'"
    }
    if (-not $configObj2.mcp.'company-atlassian') {
        throw "ASSERTION FAILED: company-atlassian missing in mcp block when -Force"
    }
    if ($configObj2.mcp.'company-atlassian'.command[0] -ne "mcp-atlassian") {
        throw "ASSERTION FAILED: company-atlassian command should be 'mcp-atlassian'"
    }
    if (-not $configObj2.mcp.context7) {
        throw "ASSERTION FAILED: context7 missing in mcp block when -Force"
    }
    if (-not $configObj2.mcp.cloakbrowser) {
        throw "ASSERTION FAILED: cloakbrowser missing in mcp block when -Force"
    }
    if (-not $configObj2.mcp.glab) {
        throw "ASSERTION FAILED: glab missing in mcp block when -Force"
    }
    if (-not $configObj2.mcp.memorix) {
        throw "ASSERTION FAILED: memorix missing in mcp block when -Force"
    }
    if ($configObj2.mcp.memorix.command[0] -ne "memorix") {
        throw "ASSERTION FAILED: memorix command should be 'memorix'"
    }

    # Kiem tra AGENTS.md khi -Force (EnableMemorix) co chua Memorix section
    $agentsFile2 = Join-Path $tempDir2 "AGENTS.md"
    $agentsContent2 = Get-Content $agentsFile2 -Raw -Encoding UTF8
    if ($agentsContent2 -notmatch "Memorix: Memory and Safety Gate") {
        throw "ASSERTION FAILED: AGENTS.md should contain Memorix section when -Force (EnableMemorix)"
    }

    # =========================================================================
    # Test 2b: Assert agency merge shape + instruction marker khi -Force
    # =========================================================================
    if (-not $configObj2.mcp.agency) {
        throw "ASSERTION FAILED: agency missing in mcp block when -Force"
    }
    if ($configObj2.mcp.agency.type -ne "local") {
        throw "ASSERTION FAILED: agency.type should be 'local', got '$($configObj2.mcp.agency.type)'"
    }
    if ($configObj2.mcp.agency.enabled -ne $true) {
        throw "ASSERTION FAILED: agency.enabled should be true"
    }
    if ($configObj2.mcp.agency.timeout -ne 10000) {
        throw "ASSERTION FAILED: agency.timeout should be 10000, got '$($configObj2.mcp.agency.timeout)'"
    }
    if (-not $configObj2.mcp.agency.command -or $configObj2.mcp.agency.command.Count -lt 1) {
        throw "ASSERTION FAILED: agency.command should be a non-empty array"
    }
    if (-not [System.IO.Path]::IsPathRooted([string]$configObj2.mcp.agency.command[0])) {
        throw "ASSERTION FAILED: agency.command[0] should be an absolute path, got '$($configObj2.mcp.agency.command[0])'"
    }
    if ($configObj2.mcp.agency.command[0] -match "__AGENCY_PATH__") {
        throw "ASSERTION FAILED: agency.command[0] placeholder was not resolved"
    }
    $agencyMarker = "<!-- agency-agents-section -->"
    if ($agentsContent2 -notmatch [regex]::Escape($agencyMarker)) {
        throw "ASSERTION FAILED: AGENTS.md should contain agency section when enabled"
    }
    if ($agentsContent2 -notmatch [regex]::Escape("## Using Agency Agents MCP")) {
        throw "ASSERTION FAILED: AGENTS.md should contain '## Using Agency Agents MCP' heading"
    }

    # =========================================================================
    # Test 3: Chay bootstrap voi -DisableAgency (agency vang mat)
    # =========================================================================
    Write-Host "`nRunning OpenCode bootstrap (Test 3: -DisableAgency) into: $tempDir3"
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -DisableAgency -OpenCodeDir $tempDir3

    $configFile3 = Join-Path $tempDir3 "opencode.json"
    if (-not (Test-Path $configFile3)) {
        throw "ASSERTION FAILED: Missing generated file: $configFile3"
    }
    $configObj3 = Get-Content $configFile3 -Raw | ConvertFrom-Json
    if ($configObj3.mcp.PSObject.Properties['agency']) {
        throw "ASSERTION FAILED: agency should be absent in mcp block when -DisableAgency"
    }
    foreach ($legacyMcp in @("company-atlassian", "gitnexus", "context7", "glab", "cloakbrowser", "memorix")) {
        if (-not $configObj3.mcp.PSObject.Properties[$legacyMcp]) {
            throw "ASSERTION FAILED: legacy MCP '$legacyMcp' missing when -DisableAgency"
        }
    }
    $agentsContent3 = Get-Content (Join-Path $tempDir3 "AGENTS.md") -Raw -Encoding UTF8
    if ($agentsContent3 -match [regex]::Escape($agencyMarker)) {
        throw "ASSERTION FAILED: AGENTS.md should NOT contain agency section when -DisableAgency"
    }

    # =========================================================================
    # Test 4: Interactive input pipeline: thu tu prompt, wording agency, drive list
    # =========================================================================
    Write-Host "`n[Test 4] Interactive input pipeline: thu tu prompt, wording agency, drive list..." -ForegroundColor Cyan
    $inputs = @(
        'y', # Cai dat MCP memorix
        'y', # Cai dat Hook tich hop Memorix vao OpenCode (ngay sau memorix)
        'y', # Cai dat MCP agency
        'n', # Cai dat MCP company-atlassian
        'n', # Cai dat MCP gitnexus
        'n', # Cai dat MCP context7
        'n', # Cai dat MCP glab
        'y', # Cai dat MCP cloakbrowser
        '1'  # Chon so thu tu o dia muon luu CloakBrowser
    )

    $interactiveCmd = "function global:Read-Host { param([string]`$p); Write-Host `$p; return [Console]::ReadLine() }; `$env:CI = ''; `$env:CLOAKBROWSER_DIR = ''; `$env:Path = '$mockBinDir;' + `$env:Path; `$env:AI_BASE_URL = 'https://test.local'; `$env:AI_API_KEY = 'k'; `$env:JIRA_URL = 'https://test.jira'; `$env:JIRA_PERSONAL_TOKEN = 't'; `$env:CONFLUENCE_URL = 'https://test.conf'; `$env:CONFLUENCE_PERSONAL_TOKEN = 't'; `$env:CONTEXT7_API_KEY = 't'; & '$PSScriptRoot\bootstrap.ps1' -DryRun:`$false -OpenCodeDir '$tempDirInteractive'"

    $procOut = $inputs | pwsh -NoProfile -Command $interactiveCmd 2>&1
    $procText = ($procOut | Out-String)

    # 1. Assert wording agency moi
    if ($procText -notmatch "\[\?\] Cai dat MCP 'agency' \(multi-agent orchestration\)\? \[y/N\]") {
        throw "ASSERTION FAILED: Missing or incorrect agency prompt wording. Output:`n$procText"
    }

    # 2. Assert thu tu: hook ngay sau MCP memorix, truoc agency
    $idxMem = $procText.IndexOf("[?] Cai dat MCP 'memorix'?")
    $idxHook = $procText.IndexOf("[?] Cai dat Hook tich hop Memorix vao OpenCode?")
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
    # Test 5: EBUSY / lancedb.node resilience: warn va tiep tuc, KHONG throw
    # =========================================================================
    Write-Host "`n[Test 5] Kiem tra EBUSY resilience tren npm install -g memorix..." -ForegroundColor Cyan
    $mockEbusyDir = Join-Path $env:TEMP ("opencode-mock-ebusy-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $mockEbusyDir | Out-Null
    Set-Content -Path (Join-Path $mockEbusyDir "npm.cmd") -Value "@echo off`nif `"%1`"==`"install`" (echo npm error code EBUSY & echo npm error syscall unlink & echo npm error path C:\nvm4w\nodejs\node_modules\memorix\node_modules\@lancedb\vectordb-win32-x64-msvc\lancedb.node & exit /b 1)`nif `"%1`"==`"root`" if `"%2`"==`"-g`" (echo $mockNpmDir& exit /b 0)`nexit /b 0"
    Set-Content -Path (Join-Path $mockEbusyDir "gitnexus.cmd") -Value "@echo off`necho gitnexus"
    Set-Content -Path (Join-Path $mockEbusyDir "memorix.cmd") -Value "@echo off`necho memorix"
    Set-Content -Path (Join-Path $mockEbusyDir "agency-mcp-server.cmd") -Value "@echo off`necho agency"

    $ebusyCmd = "`$env:Path = '$mockEbusyDir;' + `$env:Path; & '$PSScriptRoot\bootstrap.ps1' -DryRun:`$false -Force -EnableMemorix -OpenCodeDir '$tempDirEbusy'"
    $ebusyOut = pwsh -NoProfile -Command $ebusyCmd 2>&1
    $ebusyText = ($ebusyOut | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "ASSERTION FAILED: bootstrap aborted on EBUSY (ExitCode=$LASTEXITCODE). Output:`n$ebusyText"
    }
    if ($ebusyText -notmatch "Cai dat/cap nhat Memorix gap loi EBUSY: file lancedb\.node dang bi tien trinh khac khoa") {
        throw "ASSERTION FAILED: Missing clear EBUSY warning message. Output:`n$ebusyText"
    }
    # =========================================================================
    # Test 6: Skip memorix install when already latest version
    # =========================================================================
    Write-Host "`n[Test 6] Skip memorix install when version is latest..." -ForegroundColor Cyan
    $mockSkipDir = Join-Path $env:TEMP ("opencode-mock-skip-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $mockSkipDir | Out-Null
    Set-Content -Path (Join-Path $mockSkipDir "memorix.cmd") -Value "@echo off`nif `"%1`"==`"--version`" (echo 1.5.0& exit /b 0)`necho memorix"
    Set-Content -Path (Join-Path $mockSkipDir "npm.cmd") -Value "@echo off`nif `"%1`"==`"view`" if `"%2`"==`"memorix`" if `"%3`"==`"version`" (echo 1.5.0& exit /b 0)`nif `"%1`"==`"install`" if `"%3`"==`"memorix`" (echo FAIL_SHOULD_NOT_INSTALL& exit /b 1)`nif `"%1`"==`"root`" if `"%2`"==`"-g`" (echo $mockNpmDir& exit /b 0)`nexit /b 0"
    Set-Content -Path (Join-Path $mockSkipDir "gitnexus.cmd") -Value "@echo off`necho gitnexus"
    Set-Content -Path (Join-Path $mockSkipDir "agency-mcp-server.cmd") -Value "@echo off`necho agency"

    $skipCmd = "`$env:Path = '$mockSkipDir;' + `$env:Path; & '$PSScriptRoot\bootstrap.ps1' -DryRun:`$false -Force -EnableMemorix -OpenCodeDir '$tempDirSkip'"
    $skipOut = pwsh -NoProfile -Command $skipCmd 2>&1
    $skipText = ($skipOut | Out-String)
    if ($skipText -notmatch "Memorix da moi nhat, bo qua cai dat") {
        throw "ASSERTION FAILED: Expected skip message when memorix is latest. Output:`n$skipText"
    }
    if ($skipText -match "FAIL_SHOULD_NOT_INSTALL") {
        throw "ASSERTION FAILED: npm install was called despite memorix being latest. Output:`n$skipText"
    }
    Write-Host "`nAll isolated tests passed successfully for setup-opencode!" -ForegroundColor Green
}
finally {
    $env:Path = $oldPath
    Safe-Trash-Test -Path $tempDir
    Safe-Trash-Test -Path $tempDir2
    Safe-Trash-Test -Path $mockBinDir
    Safe-Trash-Test -Path $tempDir3
    Safe-Trash-Test -Path $tempDirInteractive
    Safe-Trash-Test -Path $tempDirEbusy
    Safe-Trash-Test -Path $tempDirSkip
    if ($mockSkipDir) { Safe-Trash-Test -Path $mockSkipDir }
    if ($mockEbusyDir) { Safe-Trash-Test -Path $mockEbusyDir }
}
