$ErrorActionPreference = "Stop"

$tempDir = Join-Path $env:TEMP ("claude-test-" + [System.Guid]::NewGuid().ToString("N"))
$tempJson = Join-Path $env:TEMP ("claude-test-" + [System.Guid]::NewGuid().ToString("N") + ".json")

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
    if ($claudeMdContentD -notmatch "Memorix — Memory Tools") {
        throw "ASSERTION FAILED: CLAUDE.md should contain Memorix section when -EnableMemorix is specified"
    }
    Write-Host "TEST PASSED: setup-claude-code bootstrap verified." -ForegroundColor Green
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
    Safe-Trash $mockTrashGuardDir
    Remove-Item env:TRASH_GUARD_HOOK_PATH -ErrorAction SilentlyContinue
    Safe-Trash $mockBinDir
    Safe-Trash $mockNpmDir
    Safe-Trash $mockOrcaDir
    Safe-Trash $mockCloakDir
    Remove-Item env:CLOAKBROWSER_DIR -ErrorAction SilentlyContinue
    if ($oldPath) { $env:Path = $oldPath }
}
