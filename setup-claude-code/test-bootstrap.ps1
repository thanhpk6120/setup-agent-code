$ErrorActionPreference = "Stop"
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }

$tempDir = Join-Path $env:TEMP ("claude-test-" + [System.Guid]::NewGuid().ToString("N"))
$tempJson = Join-Path $env:TEMP ("claude-test-" + [System.Guid]::NewGuid().ToString("N") + ".json")
$tempDirInteractive = Join-Path $env:TEMP ("claude-test-interactive-" + [System.Guid]::NewGuid().ToString("N"))
$tempJsonInteractive = Join-Path $env:TEMP ("claude-test-interactive-" + [System.Guid]::NewGuid().ToString("N") + ".json")
$tempDirEbusy = Join-Path $env:TEMP ("claude-test-ebusy-" + [System.Guid]::NewGuid().ToString("N"))
$tempJsonEbusy = Join-Path $env:TEMP ("claude-test-ebusy-" + [System.Guid]::NewGuid().ToString("N") + ".json")
$tempDirSkip = Join-Path $env:TEMP ("claude-test-skip-" + [System.Guid]::NewGuid().ToString("N"))
$tempJsonSkip = Join-Path $env:TEMP ("claude-test-skip-" + [System.Guid]::NewGuid().ToString("N") + ".json")
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
    $env:GITLAB_HOST = "10.30.1.17"
    $env:GITLAB_TOKEN = ""

    $mockBinDir = Join-Path $env:TEMP ("claude-mock-bin-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $mockBinDir | Out-Null
    Set-Content -Path (Join-Path $mockBinDir "gitnexus.cmd") -Value "@echo off`necho gitnexus"
    $oldPath = $env:Path
    $env:Path = "$mockBinDir;$env:Path"
    $mockAgencyPath = Join-Path $mockBinDir "agency-mcp-server.cmd"
    Set-Content -Path $mockAgencyPath -Value "@echo off`necho agency"

    $mockNpmDir = Join-Path $env:TEMP ("claude-mock-npm-" + [System.Guid]::NewGuid().ToString("N"))
    $mockContext7Path = Join-Path $mockNpmDir "@upstash\context7-mcp\dist"
    New-Item -ItemType Directory -Force -Path $mockContext7Path | Out-Null
    Set-Content -Path (Join-Path $mockContext7Path "index.js") -Value "// mock"

    function global:npm { param([Parameter(ValueFromRemainingArguments)]$r) if ($r -contains "root" -and $r -contains "-g") { return $mockNpmDir } }

    $mockOrcaDir = Join-Path $env:TEMP ("claude-orca-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $mockOrcaDir | Out-Null
    $mockOrcaPath = Join-Path $mockOrcaDir "claude-hook.cmd"
    Set-Content -Path $mockOrcaPath -Value "echo orca"
    $mockTrashGuardDir = Join-Path $env:TEMP ("claude-trashguard-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $mockTrashGuardDir | Out-Null
    $mockTrashGuardPath = Join-Path $mockTrashGuardDir "claude-pre-tool.cmd"
    Set-Content -Path $mockTrashGuardPath -Value "@echo off"
    $mockCloakDir = Join-Path $env:TEMP ("claude-cloak-" + [System.Guid]::NewGuid().ToString("N"))
    $env:CLOAKBROWSER_DIR = $mockCloakDir

    Write-Host "Running bootstrap into temp dir (Case A: with orca hook): $tempDir"
    $env:ORCA_HOOK_PATH = $mockOrcaPath
    $env:TRASH_GUARD_HOOK_PATH = $mockTrashGuardPath
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -ClaudeDir $tempDir -ClaudeJson $tempJson

    if (-not (Test-Path $tempJson)) { throw "ASSERTION FAILED: claude json missing" }
    $mcpRaw = Get-Content $tempJson -Raw
    $mcpJson = $mcpRaw | ConvertFrom-Json

    $settingsJson = Join-Path $tempDir "settings.json"
    if (-not (Test-Path $settingsJson)) { throw "ASSERTION FAILED: settings.json missing" }
    $settingsContentRawA = Get-Content $settingsJson -Raw
    if ($settingsContentRawA -notmatch '\.trash-guard') { throw "ASSERTION FAILED: settings.json should contain .trash-guard (Case A)" }
    
    $settingsJsonA = $settingsContentRawA | ConvertFrom-Json
    if (-not $settingsJsonA.hooks.PreToolUse -or $settingsJsonA.hooks.PreToolUse.Count -ne 2) {
        throw "ASSERTION FAILED: settings.json should have 2 PreToolUse hooks for trash-guard (Case A)"
    }
    $preBash = $settingsJsonA.hooks.PreToolUse | Where-Object { $_.matcher -eq 'Bash' }
    $prePwsh = $settingsJsonA.hooks.PreToolUse | Where-Object { $_.matcher -eq 'PowerShell' }
    if (-not $preBash -or -not $prePwsh) { throw "ASSERTION FAILED: Missing Bash or PowerShell matcher in PreToolUse" }
    if ($preBash.hooks[0].timeout -ne 15 -or $prePwsh.hooks[0].timeout -ne 15) { throw "ASSERTION FAILED: PreToolUse timeout should be 15" }

    $copiedHud = Join-Path $tempDir "hud/hud.mjs"
    if (-not (Test-Path $copiedHud)) { throw "ASSERTION FAILED: hud.mjs not copied (Case A)" }
    if (-not $settingsJsonA.statusLine) { throw "ASSERTION FAILED: settings.json should have statusLine (Case A)" }
    if ($settingsJsonA.statusLine.command -notmatch "node .*/hud/hud.mjs") { throw "ASSERTION FAILED: statusLine command does not match expected node path" }

    Write-Host "Running bootstrap into temp dir (Case B: without orca hook): $tempDir"
    $env:ORCA_HOOK_PATH = Join-Path $mockOrcaDir "non-existent-hook.cmd"
    $env:TRASH_GUARD_HOOK_PATH = Join-Path $mockTrashGuardDir "non-existent-pre-tool.cmd"
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -ClaudeDir $tempDir -ClaudeJson $tempJson

    $settingsContentRawB = Get-Content $settingsJson -Raw
    $settingsContentB = $settingsContentRawB | ConvertFrom-Json
    if ($settingsContentRawB -match '\.trash-guard') { throw "ASSERTION FAILED: settings.json should NOT contain .trash-guard (Case B)" }
    if ($settingsContentB.hooks.PreToolUse) { throw "ASSERTION FAILED: settings.json should not have PreToolUse if trash-guard hook is absent (Case B)" }
    if ($settingsContentRawB -match 'memorix.cmd hook') { throw "ASSERTION FAILED: settings.json should NOT contain memorix hook when not enabled (Case B)" }

    Write-Host "Running bootstrap into temp dir (Case C: HUD missing): $tempDir"
    $env:HUD_PATH = "C:\non-existent-hud-path.mjs"
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -ClaudeDir $tempDir -ClaudeJson $tempJson
    
    $settingsContentRawC = Get-Content $settingsJson -Raw
    $settingsContentC = $settingsContentRawC | ConvertFrom-Json
    if ($settingsContentC.statusLine) { throw "ASSERTION FAILED: settings.json should not have statusLine if HUD is absent (Case C)" }
    if ($settingsContentRawC -match 'memorix.cmd hook') { throw "ASSERTION FAILED: settings.json should NOT contain memorix hook when not enabled (Case C)" }
    $env:HUD_PATH = $null
    $claudeTemplate = Get-Content "$PSScriptRoot\templates\claude.json" -Raw | ConvertFrom-Json
    if (-not $claudeTemplate.mcpServers.gitnexus -or -not $claudeTemplate.mcpServers.'company-atlassian' -or -not $claudeTemplate.mcpServers.context7 -or -not $claudeTemplate.mcpServers.glab -or -not $claudeTemplate.mcpServers.cloakbrowser) {
        throw "ASSERTION FAILED: Missing mcp tools in templates/claude.json"
    }

    if ($claudeTemplate.mcpServers.gitnexus.command -ne "cmd") {
        throw "ASSERTION FAILED: gitnexus command should be 'cmd', but was '$($claudeTemplate.mcpServers.gitnexus.command)'"
    }
    if ($claudeTemplate.mcpServers.glab.command -ne "glab") {
        throw "ASSERTION FAILED: glab command should be 'glab', but was '$($claudeTemplate.mcpServers.glab.command)'"
    }
    if ($claudeTemplate.mcpServers.cloakbrowser.command -ne "node") {
        throw "ASSERTION FAILED: cloakbrowser command should be 'node', but was '$($claudeTemplate.mcpServers.cloakbrowser.command)'"
    }
    if ($claudeTemplate.mcpServers.agency.command -ne "__AGENCY_PATH__") {
        throw "ASSERTION FAILED: agency command in template should be '__AGENCY_PATH__'"
    }

    $claudeMd = Join-Path $tempDir "CLAUDE.md"
    if (-not (Test-Path $claudeMd)) { throw "ASSERTION FAILED: CLAUDE.md missing" }
    $claudeMdContent = Get-Content $claudeMd -Raw
    if ($claudeMdContent -notmatch "Pre-flight Task Complexity" -or $claudeMdContent -notmatch "Global Rules") {
        throw "ASSERTION FAILED: CLAUDE.md missing markers from AGENTS.md"
    }

    foreach ($oldFile in @("SYSTEM.md", "AGENTS.md", "RULES.md")) {
        if (Test-Path (Join-Path $tempDir $oldFile)) {
            throw "ASSERTION FAILED: $oldFile should not exist in temp dir"
        }
    }

    $settingsJson = Join-Path $tempDir "settings.json"
    if (-not (Test-Path $settingsJson)) { throw "ASSERTION FAILED: settings.json missing" }
    $settingsContent = Get-Content $settingsJson -Raw | ConvertFrom-Json
    if ($settingsContent.env.ANTHROPIC_BASE_URL -ne "https://test.local") {
        throw "ASSERTION FAILED: settings.json ANTHROPIC_BASE_URL mismatch"
    }

    $skillsDir = Join-Path $tempDir "skills"
    if (-not (Test-Path $skillsDir)) { throw "ASSERTION FAILED: skills/ missing" }
    # Case D: Test xoa legacy files va test EnableMemorix
    Write-Host "Running bootstrap into temp dir (Case D: with legacy files + EnableMemorix): $tempDir"
    foreach ($leg in @("SYSTEM.md", "AGENTS.md", "RULES.md")) {
        Set-Content -Path (Join-Path $tempDir $leg) -Value ("# Legacy " + $leg)
    }
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -EnableMemorix -ClaudeDir $tempDir -ClaudeJson $tempJson

    foreach ($oldFile in @("SYSTEM.md", "AGENTS.md", "RULES.md")) {
        if (Test-Path (Join-Path $tempDir $oldFile)) {
            throw "ASSERTION FAILED: $oldFile should have been cleaned up and moved to Trash"
        }
    }

    $mcpRawD = Get-Content $tempJson -Raw | ConvertFrom-Json
    if (-not $mcpRawD.mcpServers.memorix) {
        throw "ASSERTION FAILED: memorix mcpServer should exist when -EnableMemorix is specified"
    }

    $claudeMdContentD = Get-Content (Join-Path $tempDir "CLAUDE.md") -Raw
    if ($claudeMdContentD -notmatch "Memorix.*Memory Tools") {
        throw "ASSERTION FAILED: CLAUDE.md should contain Memorix section when -EnableMemorix is specified"
    }
    $settingsRawD = Get-Content (Join-Path $tempDir "settings.json") -Raw
    if ($settingsRawD -match 'memorix\.cmd hook') { throw "ASSERTION FAILED: settings.json should NOT contain memorix hook when hook not separately confirmed (Case D)" }
    Write-Host "TEST PASSED: setup-claude-code bootstrap verified." -ForegroundColor Green

    # Case E: EnableAgency -> config co agency + instruction co marker + giu nguyen 5 MCP cu
    Write-Host "Running bootstrap into temp dir (Case E: EnableAgency): $tempDir"
    $tempJsonE = Join-Path $env:TEMP ("claude-test-e-" + [System.Guid]::NewGuid().ToString("N") + ".json")
    $seedJson = @'
{
  "mcpServers": {
    "gitnexus": { "command": "cmd", "args": ["/c", "gitnexus.cmd", "mcp"] },
    "company-atlassian": { "command": "mcp-atlassian", "args": [] },
    "context7": { "command": "node", "args": ["ctx.js"] },
    "glab": { "command": "glab", "args": ["mcp", "serve"] },
    "cloakbrowser": { "command": "node", "args": ["cloak.js"] }
  }
}
'@
    [System.IO.File]::WriteAllText($tempJsonE, $seedJson, [System.Text.UTF8Encoding]::new($false))
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -EnableAgency -AgencyPath $mockAgencyPath -ClaudeDir $tempDir -ClaudeJson $tempJsonE

    $mcpRawE = Get-Content $tempJsonE -Raw | ConvertFrom-Json
    if (-not $mcpRawE.mcpServers.agency) {
        throw "ASSERTION FAILED: agency mcpServer should exist when -EnableAgency is specified"
    }
    if ($mcpRawE.mcpServers.agency.command -ne $mockAgencyPath) {
        throw "ASSERTION FAILED: agency command mismatch: $($mcpRawE.mcpServers.agency.command)"
    }
    if ($mcpRawE.mcpServers.agency.args.Count -ne 0) {
        throw "ASSERTION FAILED: agency args should be empty"
    }
    foreach ($kept in @("gitnexus", "company-atlassian", "context7", "glab", "cloakbrowser")) {
        if (-not $mcpRawE.mcpServers.PSObject.Properties[$kept]) {
            throw "ASSERTION FAILED: existing MCP '$kept' should be preserved when enabling agency"
        }
    }

    $claudeMdE = Get-Content (Join-Path $tempDir "CLAUDE.md") -Raw
    if ($claudeMdE -notmatch "<!-- agency-agents-section -->" -or $claudeMdE -notmatch "agency_search") {
        throw "ASSERTION FAILED: CLAUDE.md should contain agency instruction section when -EnableAgency is specified"
    }

    # Case F: DisableAgency -> config vang agency + instruction sach marker
    Write-Host "Running bootstrap into temp dir (Case F: DisableAgency): $tempDir"
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -DisableAgency -ClaudeDir $tempDir -ClaudeJson $tempJsonE

    $mcpRawF = Get-Content $tempJsonE -Raw | ConvertFrom-Json
    if ($mcpRawF.mcpServers.PSObject.Properties['agency']) {
        throw "ASSERTION FAILED: agency mcpServer should NOT exist when -DisableAgency is specified"
    }
    foreach ($kept in @("gitnexus", "company-atlassian", "context7", "glab", "cloakbrowser")) {
        if (-not $mcpRawF.mcpServers.PSObject.Properties[$kept]) {
            throw "ASSERTION FAILED: existing MCP '$kept' should be preserved when disabling agency"
        }
    }
    $claudeMdF = Get-Content (Join-Path $tempDir "CLAUDE.md") -Raw
    if ($claudeMdF -match "agency-agents-section" -or $claudeMdF -match "agency_search") {
        throw "ASSERTION FAILED: CLAUDE.md should NOT contain agency section when -DisableAgency is specified"
    }
    if ($claudeMdF -notmatch "Pre-flight Task Complexity") {
        throw "ASSERTION FAILED: CLAUDE.md base content should be preserved after removing agency section"
    }

    # Case G: Interactive input pipeline: thu tu prompt, wording agency, drive list
    Write-Host "`nRunning bootstrap Case G (Interactive pipeline: prompts, agency wording, drive list)..."
    $inputs = @(
        'y', # Cai dat MCP memorix
        'y', # Cai dat Hook tich hop Memorix vao Claude Code (ngay sau memorix)
        'y', # Cai dat MCP agency
        'n', # Cai dat MCP company-atlassian
        'n', # Cai dat MCP gitnexus
        'n', # Cai dat MCP context7
        'n', # Cai dat MCP glab
        'y', # Cai dat MCP cloakbrowser
        '1'  # Chon so thu tu o dia muon luu CloakBrowser
    )

    $interactiveCmd = "function global:Read-Host { param([string]`$p); Write-Host `$p; return [Console]::ReadLine() }; `$env:CI = ''; `$env:CLOAKBROWSER_DIR = ''; `$env:Path = '$mockBinDir;' + `$env:Path; `$env:AI_BASE_URL = 'https://test.local'; `$env:AI_API_KEY = 'k'; `$env:JIRA_URL = 'https://test.jira'; `$env:JIRA_PERSONAL_TOKEN = 't'; `$env:CONFLUENCE_URL = 'https://test.conf'; `$env:CONFLUENCE_PERSONAL_TOKEN = 't'; `$env:CONTEXT7_API_KEY = 't'; & '$PSScriptRoot\bootstrap.ps1' -DryRun:`$false -ClaudeDir '$tempDirInteractive' -ClaudeJson '$tempJsonInteractive'"

    $procOut = $inputs | pwsh -NoProfile -Command $interactiveCmd 2>&1
    $procText = ($procOut | Out-String)

    if ($procText -notmatch "\[\?\] Cai dat MCP 'agency' \(multi-agent orchestration\)\? \[y/N\]") {
        throw "ASSERTION FAILED: Missing or incorrect agency prompt wording. Output:`n$procText"
    }

    $idxMem = $procText.IndexOf("[?] Cai dat MCP 'memorix'?")
    $idxHook = $procText.IndexOf("[?] Cai dat Hook tich hop Memorix vao Claude Code?")
    $idxAgency = $procText.IndexOf("[?] Cai dat MCP 'agency' (multi-agent orchestration)?")
    if ($idxMem -lt 0 -or $idxHook -lt 0 -or $idxAgency -lt 0) {
        throw "ASSERTION FAILED: Missing prompts in interactive test. Output:`n$procText"
    }
    if (-not ($idxMem -lt $idxHook -and $idxHook -lt $idxAgency)) {
        throw "ASSERTION FAILED: Hook prompt must immediately follow memorix install prompt and precede agency prompt"
    }

    if ($procText -notmatch "(?s)Danh sach o dia kha dung:.*Chon so thu tu o dia muon luu CloakBrowser") {
        throw "ASSERTION FAILED: CloakBrowser drive menu not directly embedded before prompt. Output:`n$procText"
    }

    # Case H: EBUSY / lancedb.node resilience: warn va tiep tuc, KHONG abort
    Write-Host "`nRunning bootstrap Case H (EBUSY resilience on npm install -g memorix)..."
    $mockEbusyDir = Join-Path $env:TEMP ("claude-mock-ebusy-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $mockEbusyDir | Out-Null
    Set-Content -Path (Join-Path $mockEbusyDir "npm.cmd") -Value "@echo off`nif `"%1`"==`"install`" (echo npm error code EBUSY & echo npm error syscall unlink & echo npm error path C:\nvm4w\nodejs\node_modules\memorix\node_modules\@lancedb\vectordb-win32-x64-msvc\lancedb.node & exit /b 1)`nif `"%1`"==`"root`" if `"%2`"==`"-g`" (echo $mockNpmDir& exit /b 0)`nexit /b 0"
    Set-Content -Path (Join-Path $mockEbusyDir "gitnexus.cmd") -Value "@echo off`necho gitnexus"
    Set-Content -Path (Join-Path $mockEbusyDir "memorix.cmd") -Value "@echo off`necho memorix"
    Set-Content -Path (Join-Path $mockEbusyDir "agency-mcp-server.cmd") -Value "@echo off`necho agency"

    $ebusyCmd = "`$env:Path = '$mockEbusyDir;' + `$env:Path; & '$PSScriptRoot\bootstrap.ps1' -DryRun:`$false -Force -EnableMemorix -ClaudeDir '$tempDirEbusy' -ClaudeJson '$tempJsonEbusy'"
    $ebusyOut = pwsh -NoProfile -Command $ebusyCmd 2>&1
    $ebusyText = ($ebusyOut | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "ASSERTION FAILED: bootstrap aborted on EBUSY (ExitCode=$LASTEXITCODE). Output:`n$ebusyText"
    }
    if ($ebusyText -notmatch "Cai dat/cap nhat Memorix gap loi EBUSY: file lancedb\.node dang bi tien trinh khac khoa") {
        throw "ASSERTION FAILED: Missing clear EBUSY warning message. Output:`n$ebusyText"
    }

    # Case I: Skip memorix install when already latest version
    Write-Host "`nRunning bootstrap Case I (Skip memorix install when version is latest)..."
    $mockSkipDir = Join-Path $env:TEMP ("claude-mock-skip-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $mockSkipDir | Out-Null
    Set-Content -Path (Join-Path $mockSkipDir "memorix.cmd") -Value "@echo off`nif `"%1`"==`"--version`" (echo 1.5.0& exit /b 0)`necho memorix"
    Set-Content -Path (Join-Path $mockSkipDir "npm.cmd") -Value "@echo off`nif `"%1`"==`"view`" if `"%2`"==`"memorix`" if `"%3`"==`"version`" (echo 1.5.0& exit /b 0)`nif `"%1`"==`"install`" if `"%3`"==`"memorix`" (echo FAIL_SHOULD_NOT_INSTALL& exit /b 1)`nif `"%1`"==`"root`" if `"%2`"==`"-g`" (echo $mockNpmDir& exit /b 0)`nexit /b 0"
    Set-Content -Path (Join-Path $mockSkipDir "gitnexus.cmd") -Value "@echo off`necho gitnexus"
    Set-Content -Path (Join-Path $mockSkipDir "agency-mcp-server.cmd") -Value "@echo off`necho agency"

    $skipCmd = "`$env:Path = '$mockSkipDir;' + `$env:Path; & '$PSScriptRoot\bootstrap.ps1' -DryRun:`$false -Force -EnableMemorix -ClaudeDir '$tempDirSkip' -ClaudeJson '$tempJsonSkip'"
    $skipOut = pwsh -NoProfile -Command $skipCmd 2>&1
    $skipText = ($skipOut | Out-String)
    if ($skipText -notmatch "Memorix da moi nhat, bo qua cai dat") {
        throw "ASSERTION FAILED: Expected skip message when memorix is latest. Output:`n$skipText"
    }
    if ($skipText -match "FAIL_SHOULD_NOT_INSTALL") {
        throw "ASSERTION FAILED: npm install was called despite memorix being latest. Output:`n$skipText"
    }
} finally {
    Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
    function Safe-Trash($p) {
        if ($p -and (Test-Path $p)) {
            if (Get-Command "trash" -ErrorAction SilentlyContinue) {
                trash $p
            } else {
                try { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p, 'OnlyErrorDialogs', 'SendToRecycleBin') } catch {}
                try { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, 'OnlyErrorDialogs', 'SendToRecycleBin') } catch {}
            }
        }
    }
    Safe-Trash $tempDir
    Safe-Trash $tempJsonE
    Safe-Trash $mockTrashGuardDir
    Remove-Item env:TRASH_GUARD_HOOK_PATH -ErrorAction SilentlyContinue
    Safe-Trash $mockBinDir
    Safe-Trash $mockNpmDir
    Safe-Trash $mockOrcaDir
    Safe-Trash $mockCloakDir
    Safe-Trash $tempDirInteractive
    Safe-Trash $tempJsonInteractive
    Safe-Trash $tempDirEbusy
    Safe-Trash $tempJsonEbusy
    if ($mockEbusyDir) { Safe-Trash $mockEbusyDir }
    Safe-Trash $tempDirSkip
    Safe-Trash $tempJsonSkip
    if ($mockSkipDir) { Safe-Trash $mockSkipDir }
    Remove-Item env:CLOAKBROWSER_DIR -ErrorAction SilentlyContinue
    if ($oldPath) { $env:Path = $oldPath }
}
