# test-bootstrap.ps1 - Assert-based test for setup-opencode bootstrap script
$ErrorActionPreference = "Stop"
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

    Write-Host "`nAll isolated tests passed successfully for setup-opencode!" -ForegroundColor Green
}
finally {
    $env:Path = $oldPath
    Safe-Trash-Test -Path $tempDir
    Safe-Trash-Test -Path $tempDir2
    Safe-Trash-Test -Path $mockBinDir
    Safe-Trash-Test -Path $mockNpmDir
}
