# test-bootstrap.ps1 - Assert-based test for setup-dsh-web bootstrap script
$ErrorActionPreference = "Stop"

$tempHome = Join-Path $env:TEMP ("dsh-web-home-" + [System.Guid]::NewGuid().ToString("N"))
$tempProfile = Join-Path $env:TEMP ("dsh-web-prof-" + [System.Guid]::NewGuid().ToString("N"))
$tempProfile2 = Join-Path $env:TEMP ("dsh-web-prof2-" + [System.Guid]::NewGuid().ToString("N"))
$tempProfileInteractive = Join-Path $env:TEMP ("dsh-web-interactive-" + [System.Guid]::NewGuid().ToString("N"))
$tempProfileEbusy = Join-Path $env:TEMP ("dsh-web-ebusy-" + [System.Guid]::NewGuid().ToString("N"))
$mockEbusyDir = Join-Path $env:TEMP ("dsh-web-mock-ebusy-" + [System.Guid]::NewGuid().ToString("N"))
$tempProfileVer = Join-Path $env:TEMP ("dsh-web-ver-" + [System.Guid]::NewGuid().ToString("N"))
$mockVerDir = Join-Path $env:TEMP ("dsh-web-mock-ver-" + [System.Guid]::NewGuid().ToString("N"))
$tempHomeDup = Join-Path $env:TEMP ("dsh-web-dup-home-" + [System.Guid]::NewGuid().ToString("N"))
$tempProfileDup = Join-Path $env:TEMP ("dsh-web-dup-prof-" + [System.Guid]::NewGuid().ToString("N"))
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
    $hookLog = Join-Path $env:TEMP ("dshweb-hooklog-" + [System.Guid]::NewGuid().ToString("N"))
    Set-Content -Path (Join-Path $mockBinDir "memorix.cmd") -Value "@echo off`r`necho %* >> `"$hookLog`""
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
    $acceptAll = "y`ny`ny`ny`ny`ny`ny`ny`n1`n"
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

    # Assert hook Memorix DSH-web dung agent dsh (KHONG dsh-web)
    $hookContent = if (Test-Path $hookLog) { Get-Content $hookLog -Raw } else { "" }
    if ($hookContent -notmatch 'setup --agent dsh --global') {
        throw "ASSERTION FAILED: memorix hook not called with --agent dsh --global. Got: $hookContent"
    }
    if ($hookContent -match '--agent dsh-web') {
        throw "ASSERTION FAILED: hook used wrong agent dsh-web, must be dsh"
    }

    # Test 3: regex go Memorix khong nuot Agency section
    $sample = "Header`r`n`r`n## Memorix: Memory and Safety Gate`r`nmem body line`r`n`r`n<!-- agency-agents-section -->`r`n## Using Agency Agents MCP`r`nagency body`r`n<!-- /agency-agents-section -->`r`n"
    $cleaned = [regex]::Replace($sample, '(?s)\r?\n?## Memorix: Memory and Safety Gate.*?<!-- /memorix-section -->', '')
    $cleaned = [regex]::Replace($cleaned, "(?ms)\r?\n## Memorix: Memory and Safety Gate.*?(?=\r?\n(?:## |<!-- )|\z)", "")
    if ($cleaned -match 'Memorix: Memory and Safety Gate') { throw "ASSERTION FAILED: regex go Memorix khong sach" }
    if ($cleaned -notmatch 'Using Agency Agents MCP') { throw "ASSERTION FAILED: regex go Memorix nuot Agency section" }

    
    # Test Agency MCP assertions
    Write-Host "--- Test Agency MCP on/off ---" -ForegroundColor Cyan
    $testHomeOn = Join-Path $tempHome "agency-home-on"
    $testProfileOn = Join-Path $tempProfile "agency-profile-on"
    $testCredsOn = Join-Path $tempCredsDir "agency-creds-on.yaml"
    & "$PSScriptRoot\bootstrap.ps1" -SkipInstall -EnableAgency -DshHome $testHomeOn -DshProfileDir $testProfileOn -CredentialsPath $testCredsOn -AgencyPath "C:/nvm4w/nodejs/agency-mcp-server.cmd"
    $cordisOn = Get-Content (Join-Path $testProfileOn "cordis.patch.yml") -Raw
    if ($cordisOn -notmatch 'id:\s*mcp-agency') { throw "Assert failed: mcp-agency missing when -EnableAgency" }
    $agentsOn = Get-Content (Join-Path $testHomeOn "AGENTS.md") -Raw
    if ($agentsOn -notmatch 'Using Agency Agents MCP') { throw "Assert failed: agency marker missing in AGENTS.md" }

    $testHomeOff = Join-Path $tempHome "agency-home-off"
    $testProfileOff = Join-Path $tempProfile "agency-profile-off"
    $testCredsOff = Join-Path $tempCredsDir "agency-creds-off.yaml"
    & "$PSScriptRoot\bootstrap.ps1" -SkipInstall -DisableAgency -DshHome $testHomeOff -DshProfileDir $testProfileOff -CredentialsPath $testCredsOff
    $cordisOff = Get-Content (Join-Path $testProfileOff "cordis.patch.yml") -Raw
    if ($cordisOff -match 'id:\s*mcp-agency') { throw "Assert failed: mcp-agency present when -DisableAgency" }

    # =========================================================================
    # Test 4: Duplicate Guard va Removal Branch cho Memorix
    # =========================================================================
    Write-Host "`nRunning DSH Web bootstrap (Test 4: Duplicate Guard & Removal Branch for Memorix)" -ForegroundColor Cyan
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -EnableMemorix -DshHome $tempHomeDup -DshProfileDir $tempProfileDup -CredentialsPath $tempCreds
    $agentsDup = Get-Content (Join-Path $tempHomeDup "AGENTS.md") -Raw
    $cordisDup = Get-Content (Join-Path $tempProfileDup "cordis.patch.yml") -Raw
    if (-not $agentsDup.Contains("Memorix") -or -not $cordisDup.Contains("mcp-memorix")) {
        throw "ASSERTION FAILED: Test 4.1 - Missing memorix in AGENTS.md or cordis.patch.yml"
    }

    # Idempotent: chay lai
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -EnableMemorix -DshHome $tempHomeDup -DshProfileDir $tempProfileDup -CredentialsPath $tempCreds
    $agentsDup2 = Get-Content (Join-Path $tempHomeDup "AGENTS.md") -Raw
    $memCount = ([regex]::Matches($agentsDup2, "(?m)^#+ Memorix")).Count
    if ($memCount -ne 1) {
        throw "ASSERTION FAILED: Test 4.2 - Memorix section in AGENTS.md duplicated (count=$memCount)"
    }

    # Removal: chay voi -DisableMemorix
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -DisableMemorix -DshHome $tempHomeDup -DshProfileDir $tempProfileDup -CredentialsPath $tempCreds
    $agentsDup3 = Get-Content (Join-Path $tempHomeDup "AGENTS.md") -Raw
    $cordisDup3 = Get-Content (Join-Path $tempProfileDup "cordis.patch.yml") -Raw
    if ($cordisDup3.Contains("mcp-memorix") -or $cordisDup3.Contains("serverName: memorix")) {
        throw "ASSERTION FAILED: Test 4.3 - cordis.patch.yml still contains mcp-memorix under -DisableMemorix"
    }
    if ($agentsDup3 -match "(?m)^#+ Memorix" -or $agentsDup3.Contains("Memorix — Memory Tools")) {
        throw "ASSERTION FAILED: Test 4.3 - AGENTS.md still contains Memorix section under -DisableMemorix"
    }

    # =========================================================================
    # Test 5: Interactive input pipeline: thu tu prompt, wording agency, drive list
    # =========================================================================
    Write-Host "`n[Test 5] Interactive input pipeline: thu tu prompt, wording agency, drive list..." -ForegroundColor Cyan
    $inputs = @(
        'y', # Cai dat MCP memorix
        'y', # Cai dat Hook tich hop Memorix vao DSH Web (ngay sau memorix)
        'y', # Cai dat MCP agency
        'n', # Cai dat MCP company-atlassian
        'n', # Cai dat MCP gitnexus
        'n', # Cai dat MCP context7
        'n', # Cai dat MCP glab
        'y', # Cai dat MCP cloakbrowser
        '1'  # Chon so thu tu o dia muon luu CloakBrowser
    )

    $interactiveCmd = "function global:Read-Host { param([string]`$p); Write-Host `$p; return [Console]::ReadLine() }; `$env:CI = ''; `$env:Path = '$mockBinDir;' + `$env:Path; `$env:AI_BASE_URL = 'https://test.local'; `$env:AI_API_KEY = 'k'; `$env:JIRA_URL = 'https://test.jira'; `$env:JIRA_PERSONAL_TOKEN = 't'; `$env:CONFLUENCE_URL = 'https://test.conf'; `$env:CONFLUENCE_PERSONAL_TOKEN = 't'; `$env:CONTEXT7_API_KEY = 't'; & '$PSScriptRoot\bootstrap.ps1' -DryRun:`$false -DshHome '$tempHome' -DshProfileDir '$tempProfileInteractive' -CredentialsPath '$tempCreds'"

    $procOut = $inputs | pwsh -NoProfile -Command $interactiveCmd 2>&1
    $procText = ($procOut | Out-String)

    # 1. Assert wording agency moi
    if ($procText -notmatch "\[\?\] Cai dat MCP 'agency' \(multi-agent orchestration\)\? \[y/N\]") {
        throw "ASSERTION FAILED: Missing or incorrect agency prompt wording. Output:`n$procText"
    }

    # 2. Assert thu tu: hook ngay sau MCP memorix, truoc agency
    $idxMem = $procText.IndexOf("[?] Cai dat MCP 'memorix'? [y/N]")
    $idxHook = $procText.IndexOf("[?] Cai dat Hook tich hop Memorix vao DSH Web? [y/N]")
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

    # =========================================================================
    # Test 6: Assert npm EBUSY khong abort bootstrap
    # =========================================================================
    Write-Host "`n[Test 6] Assert npm EBUSY khong abort bootstrap..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $mockEbusyDir | Out-Null
    $mockNpmContent = @'
@echo off
echo %* | findstr /i "memorix" >nul && (
    echo npm error code EBUSY
    echo npm error syscall unlink
    echo npm error path C:\mock\lancedb.node
    exit /b 1
)
exit /b 0
'@
    Set-Content -Path (Join-Path $mockEbusyDir "npm.cmd") -Value $mockNpmContent

    $ebusyCmd = "`$env:Path = '$mockEbusyDir;' + `$env:Path; & '$PSScriptRoot\bootstrap.ps1' -DryRun:`$false -Force -EnableMemorix -DshHome '$tempHome' -DshProfileDir '$tempProfileEbusy' -CredentialsPath '$tempCreds'"
    $ebusyOutput = pwsh -NoProfile -ExecutionPolicy Bypass -Command $ebusyCmd 2>&1 | Out-String

    if (-not (Test-Path (Join-Path $tempProfileEbusy "cordis.patch.yml"))) {
        throw "ASSERTION FAILED: bootstrap aborted on npm EBUSY; cordis.patch.yml was not created. Output:`n$ebusyOutput"
    }
    if ($ebusyOutput -notmatch "EBUSY" -or $ebusyOutput -notmatch "lancedb\.node") {
        throw "ASSERTION FAILED: Warning for EBUSY/lancedb.node was not logged in output:`n$ebusyOutput"
    }
    Write-Host "  -> EBUSY resilience test PASS: bootstrap tiep tuc thanh cong khi npm install -g gap EBUSY." -ForegroundColor Green

    # =========================================================================
    # Test 7: Assert memorix version check skip reinstall
    # =========================================================================
    Write-Host "`n[Test 7] Assert memorix version check skip reinstall..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $mockVerDir | Out-Null
    Set-Content -Path (Join-Path $mockVerDir "memorix.cmd") -Value "@echo off`r`nif `"%1`"==`"--version`" (echo 0.2.22& exit /b 0)`r`nexit /b 0"
    $mockNpmVerContent = @'
@echo off
echo %* | findstr /i "view" >nul && (
    echo 0.2.22
    exit /b 0
)
echo %* | findstr /i "install" | findstr /i "memorix" >nul && (
    echo MOCK_NPM_INSTALL_MEMORIX_CALLED
    exit /b 0
)
exit /b 0
'@
    Set-Content -Path (Join-Path $mockVerDir "npm.cmd") -Value $mockNpmVerContent

    $verCmd = "`$env:Path = '$mockVerDir;' + `$env:Path; & '$PSScriptRoot\bootstrap.ps1' -DryRun:`$false -EnableMemorix -DshHome '$tempHome' -DshProfileDir '$tempProfileVer' -CredentialsPath '$tempCreds'"
    $verOutput = pwsh -NoProfile -ExecutionPolicy Bypass -Command $verCmd 2>&1 | Out-String

    if ($verOutput -notmatch "Memorix da o phien ban moi nhat") {
        throw "ASSERTION FAILED: Version check skip message not found in output:`n$verOutput"
    }
    if ($verOutput -match "MOCK_NPM_INSTALL_MEMORIX_CALLED") {
        throw "ASSERTION FAILED: npm install memorix was unexpectedly called when memorix version matches latest. Output:`n$verOutput"
    }
    Write-Host "  -> Version check test PASS: Memorix da moi nhat, da bo qua cai dat lai thanh cong." -ForegroundColor Green
    # =========================================================================
    # Test 8: Assert -EnableAgency khong truyen -AgencyPath (va -AgencyPath "") khong throw
    # =========================================================================
    Write-Host "`n[Test 8] Assert -EnableAgency default AgencyPath khong throw..." -ForegroundColor Cyan
    $tempProfileAgencyDefault = Join-Path $env:TEMP ("dsh-web-agency-def-" + [System.Guid]::NewGuid().ToString("N"))
    $tempProfileAgencyEmpty = Join-Path $env:TEMP ("dsh-web-agency-emp-" + [System.Guid]::NewGuid().ToString("N"))

    # Case A: khong truyen -AgencyPath
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -EnableAgency -DshHome $tempHome -DshProfileDir $tempProfileAgencyDefault -CredentialsPath $tempCreds
    $patchDef = Join-Path $tempProfileAgencyDefault "cordis.patch.yml"
    if (-not (Test-Path $patchDef)) {
        throw "ASSERTION FAILED: cordis.patch.yml missing in Test 8 Case A"
    }
    $yamlDef = Get-Content $patchDef -Raw
    if (-not $yamlDef.Contains("mcp-agency")) {
        throw "ASSERTION FAILED: cordis.patch.yml missing mcp-agency in Test 8 Case A"
    }

    # Case B: truyen -AgencyPath "" (chuoi rong phai khong bi ParameterBindingValidationException)
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -EnableAgency -AgencyPath "" -DshHome $tempHome -DshProfileDir $tempProfileAgencyEmpty -CredentialsPath $tempCreds
    $patchEmp = Join-Path $tempProfileAgencyEmpty "cordis.patch.yml"
    if (-not (Test-Path $patchEmp)) {
        throw "ASSERTION FAILED: cordis.patch.yml missing in Test 8 Case B"
    }
    $yamlEmp = Get-Content $patchEmp -Raw
    if (-not $yamlEmp.Contains("mcp-agency")) {
        throw "ASSERTION FAILED: cordis.patch.yml missing mcp-agency in Test 8 Case B"
    }
    Write-Host "  -> AgencyPath resilience test PASS: -EnableAgency khong truyen / truyen rong deu thanh cong." -ForegroundColor Green
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
    if ($tempProfileInteractive) { Safe-Trash $tempProfileInteractive }
    if ($tempProfileEbusy) { Safe-Trash $tempProfileEbusy }
    if ($mockEbusyDir) { Safe-Trash $mockEbusyDir }
    if ($tempProfileVer) { Safe-Trash $tempProfileVer }
    if ($mockVerDir) { Safe-Trash $mockVerDir }
    if ($tempHomeDup) { Safe-Trash $tempHomeDup }
    if ($tempProfileDup) { Safe-Trash $tempProfileDup }
    if ($tempProfileAgencyDefault) { Safe-Trash $tempProfileAgencyDefault }
    if ($tempProfileAgencyEmpty) { Safe-Trash $tempProfileAgencyEmpty }
    Safe-Trash $tempCredsDir
    Safe-Trash $hookLog
}
