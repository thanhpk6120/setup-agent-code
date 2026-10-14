# test-bootstrap.ps1 - Assert-based test for DSH bootstrap script
$ErrorActionPreference = "Stop"

$tempHome = Join-Path $env:TEMP ("dsh-home-test-" + [System.Guid]::NewGuid().ToString("N"))
$tempProfile = Join-Path $env:TEMP ("dsh-profile-test-" + [System.Guid]::NewGuid().ToString("N"))
$tempProfile2 = Join-Path $env:TEMP ("dsh-profile-test2-" + [System.Guid]::NewGuid().ToString("N"))
$tempProfile3 = Join-Path $env:TEMP ("dsh-profile-test3-" + [System.Guid]::NewGuid().ToString("N"))
$tempProfile4 = Join-Path $env:TEMP ("dsh-profile-test4-" + [System.Guid]::NewGuid().ToString("N"))
$tempProfileInteractive = Join-Path $env:TEMP ("dsh-profile-interactive-" + [System.Guid]::NewGuid().ToString("N"))
$tempProfileEbusy = Join-Path $env:TEMP ("dsh-profile-ebusy-" + [System.Guid]::NewGuid().ToString("N"))
$mockEbusyDir = Join-Path $env:TEMP ("dsh-mock-ebusy-" + [System.Guid]::NewGuid().ToString("N"))
$tempProfileVer = Join-Path $env:TEMP ("dsh-profile-ver-" + [System.Guid]::NewGuid().ToString("N"))
$mockVerDir = Join-Path $env:TEMP ("dsh-mock-ver-" + [System.Guid]::NewGuid().ToString("N"))
$tempCredsDir = Join-Path $env:TEMP ("dsh-creds-test-" + [System.Guid]::NewGuid().ToString("N"))
$tempCreds = Join-Path $tempCredsDir ".credentials.yaml"

$env:AI_BASE_URL = "https://mock.provider.com/v1"
$env:AI_API_KEY = "MOCK_AI_API_KEY"
$env:JIRA_URL = "https://mock.jira.com"
$env:JIRA_PERSONAL_TOKEN = "MOCK_JIRA_TOKEN"
$env:CONFLUENCE_URL = "https://mock.conf.com"
$env:CONFLUENCE_PERSONAL_TOKEN = "MOCK_CONF_TOKEN"
$env:CONTEXT7_API_KEY = "MOCK_CONTEXT7_KEY"

# Setup mock environment for gitnexus and context7 to ensure test succeeds in clean environment
$mockNpmDir = Join-Path $env:TEMP ("dsh-mock-npm-" + [System.Guid]::NewGuid().ToString("N"))
$mockContext7Path = Join-Path $mockNpmDir "@upstash\context7-mcp\dist"
New-Item -ItemType Directory -Force -Path $mockContext7Path | Out-Null
Set-Content -Path (Join-Path $mockContext7Path "index.js") -Value "// mock"

$mockBinDir = Join-Path $env:TEMP ("dsh-mock-bin-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $mockBinDir | Out-Null
Set-Content -Path (Join-Path $mockBinDir "gitnexus.cmd") -Value "@echo off`necho gitnexus"
Set-Content -Path (Join-Path $mockBinDir "npm.cmd") -Value "@echo off`nif `"%1`"==`"root`" if `"%2`"==`"-g`" (echo $mockNpmDir& exit /b 0)`nexit /b 0"
$oldPath = $env:Path
$env:Path = "$mockBinDir;$env:Path"

function global:npm {
    param([Parameter(ValueFromRemainingArguments)]$remaining)
    if ($remaining -contains "root" -and $remaining -contains "-g") {
        return $mockNpmDir
    }
    $realNpm = Get-Command npm -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($realNpm) {
        & $realNpm @remaining
    }
}

try {
    # Test 1: DryRun / SkipInstall / Default mode -> Tat ca MCP mac dinh bi tu choi (N)
    Write-Host "Running DSH bootstrap (Test 1: SkipInstall non-interactive, all MCPs skipped) into temp dirs: $tempHome, $tempProfile"
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -DshHome $tempHome -DshProfileDir $tempProfile -CredentialsPath $tempCreds

    $path = Join-Path $tempProfile "cordis.patch.yml"
    if (-not (Test-Path $path)) {
        throw "ASSERTION FAILED: Missing generated file: $path"
    }

    $yamlRaw = Get-Content $path -Raw
    if ($yamlRaw.Contains("serverName: gitnexus") -or $yamlRaw.Contains("serverName: memorix") -or $yamlRaw.Contains("serverName: company-atlassian") -or $yamlRaw.Contains("serverName: context7") -or $yamlRaw.Contains("serverName: cloakbrowser") -or $yamlRaw.Contains("serverName: glab")) {
        throw "ASSERTION FAILED: In default run with SkipInstall, skipped MCP servers should NOT be present in cordis.patch.yml"
    }

    if ($yamlRaw.Contains("__AI_BASE_URL__") -or $yamlRaw.Contains("__JIRA_URL__") -or $yamlRaw.Contains("__GITNEXUS_CONFIG__") -or $yamlRaw.Contains("__CONTEXT7_CONFIG__") -or $yamlRaw.Contains("__CLOAKBROWSER_SCRIPT__")) {
        throw "ASSERTION FAILED: Unresolved placeholders found in cordis.patch.yml"
    }

    if (-not $yamlRaw.Contains("model: claude-sonnet-5")) {
        throw "ASSERTION FAILED: cordis.patch.yml is missing models block"
    }

    if (-not $yamlRaw.Contains("apiKeyEnv: ANTHROPIC_API_KEY")) {
        throw "ASSERTION FAILED: cordis.patch.yml lost apiKeyEnv ANTHROPIC_API_KEY"
    }

    if (-not $yamlRaw.Contains("baseURL: https://mock.provider.com/v1")) {
        throw "ASSERTION FAILED: cordis.patch.yml did not replace AI_BASE_URL correctly"
    }

    if (-not (Test-Path $tempCreds)) {
        throw "ASSERTION FAILED: Missing generated credentials file: $tempCreds"
    }
    $credRaw = Get-Content $tempCreds -Raw
    if (-not $credRaw.Contains("refs:")) {
        throw "ASSERTION FAILED: .credentials.yaml missing refs: block"
    }
    if (-not $credRaw.Contains("ANTHROPIC_API_KEY: MOCK_AI_API_KEY")) {
        throw "ASSERTION FAILED: .credentials.yaml did not inject ANTHROPIC_API_KEY correctly"
    }

    $agentsPath = Join-Path $tempHome "AGENTS.md"
    if (-not (Test-Path $agentsPath)) {
        throw "ASSERTION FAILED: Missing copied file: $agentsPath"
    }

    $skills = Get-ChildItem -Path (Join-Path $tempHome "skills") -Filter "SKILL.md" -Recurse -ErrorAction SilentlyContinue
    if (-not $skills -or $skills.Count -lt 1) {
        throw "ASSERTION FAILED: Missing at least 1 skill SKILL.md under $tempHome/skills"
    }

    # Test 2: Mock pipeline Y/N - Case 1: Tu choi het (pipe n cho 6 MCP prompts)
    Write-Host "`nRunning DSH bootstrap (Test 2: Pipeline Y/N - Refuse all MCPs) into $tempProfile2"
    $psScript = "$PSScriptRoot\bootstrap.ps1"
    $refuseAll = "n`nn`nn`nn`nn`nn`nn`n"
    $refuseAll | pwsh -NoProfile -ExecutionPolicy Bypass -Command @"
        `$env:CI = `$null
        [Environment]::SetEnvironmentVariable('CI', `$null, 'Process')
        `$env:AI_BASE_URL = '$($env:AI_BASE_URL)'
        `$env:AI_API_KEY = '$($env:AI_API_KEY)'
        `$env:Path = '$($env:Path)'
        & '$psScript' -DryRun:`$false -DshHome '$tempHome' -DshProfileDir '$tempProfile2' -CredentialsPath '$tempCreds'
"@

    $path2 = Join-Path $tempProfile2 "cordis.patch.yml"
    if (-not (Test-Path $path2)) {
        throw "ASSERTION FAILED: Missing generated file: $path2"
    }
    $yamlRaw2 = Get-Content $path2 -Raw
    if ($yamlRaw2.Contains("serverName: gitnexus") -or $yamlRaw2.Contains("serverName: memorix") -or $yamlRaw2.Contains("serverName: company-atlassian") -or $yamlRaw2.Contains("serverName: context7") -or $yamlRaw2.Contains("serverName: cloakbrowser") -or $yamlRaw2.Contains("serverName: glab") -or $yamlRaw2.Contains("serverName: agency")) {
        throw "ASSERTION FAILED: cordis.patch.yml should NOT contain any MCP server when user chooses 'n' to all"
    }

    # Test 3: Mock pipeline Y/N - Case 2: Nhan memorix (y) nhung tu choi hook (n), cac MCP con lai tu choi (n)
    # Thu tu prompts trong bootstrap.ps1:
    # 1. MCP 'memorix'? -> y
    # 2. MCP 'company-atlassian'? -> n
    # 3. MCP 'gitnexus'? -> n
    # 4. MCP 'context7'? -> n
    # 5. MCP 'glab'? -> n
    # 6. MCP 'cloakbrowser'? -> n
    # 7. Hook memorix vao DSH? -> n
    Write-Host "`nRunning DSH bootstrap (Test 3: Pipeline Y/N - Accept memorix, refuse hook & other MCPs) into $tempProfile3"
    $acceptMemorixOnly = "y`nn`nn`nn`nn`nn`nn`nn`n"
    $acceptMemorixOnly | pwsh -NoProfile -ExecutionPolicy Bypass -Command @"
        `$env:CI = `$null
        [Environment]::SetEnvironmentVariable('CI', `$null, 'Process')
        `$env:AI_BASE_URL = '$($env:AI_BASE_URL)'
        `$env:AI_API_KEY = '$($env:AI_API_KEY)'
        `$env:Path = '$($env:Path)'
        & '$psScript' -DryRun:`$false -DshHome '$tempHome' -DshProfileDir '$tempProfile3' -CredentialsPath '$tempCreds'
"@

    $path3 = Join-Path $tempProfile3 "cordis.patch.yml"
    if (-not (Test-Path $path3)) {
        throw "ASSERTION FAILED: Missing generated file: $path3"
    }
    $yamlRaw3 = Get-Content $path3 -Raw
    if (-not $yamlRaw3.Contains("serverName: memorix") -or -not $yamlRaw3.Contains("- id: mcp-memorix")) {
        throw "ASSERTION FAILED: cordis.patch.yml should contain memorix when user chose 'y'"
    }
    if ($yamlRaw3.Contains("serverName: gitnexus") -or $yamlRaw3.Contains("serverName: company-atlassian") -or $yamlRaw3.Contains("serverName: context7") -or $yamlRaw3.Contains("serverName: cloakbrowser") -or $yamlRaw3.Contains("serverName: glab") -or $yamlRaw3.Contains("serverName: agency")) {
        throw "ASSERTION FAILED: cordis.patch.yml should NOT contain other MCPs when rejected"
    }
    # Test 4: Mock pipeline Y/N - Case 3: Chap nhan tat ca MCPs (pipe y cho cac MCP + hook + 1 cho o CloakBrowser)
    Write-Host "`nRunning DSH bootstrap (Test 4: Pipeline Y/N - Accept ALL MCPs) into $tempProfile4"
    $acceptAll = "y`ny`ny`ny`ny`ny`ny`ny`n1`n"
    $acceptAll | pwsh -NoProfile -ExecutionPolicy Bypass -Command @"
        `$env:CI = `$null
        [Environment]::SetEnvironmentVariable('CI', `$null, 'Process')
        `$env:AI_BASE_URL = '$($env:AI_BASE_URL)'
        `$env:AI_API_KEY = '$($env:AI_API_KEY)'
        `$env:JIRA_URL = '$($env:JIRA_URL)'
        `$env:JIRA_PERSONAL_TOKEN = '$($env:JIRA_PERSONAL_TOKEN)'
        `$env:CONFLUENCE_URL = '$($env:CONFLUENCE_URL)'
        `$env:CONFLUENCE_PERSONAL_TOKEN = '$($env:CONFLUENCE_PERSONAL_TOKEN)'
        `$env:CONTEXT7_API_KEY = '$($env:CONTEXT7_API_KEY)'
        `$env:Path = '$($env:Path)'
        & '$psScript' -DryRun:`$false -DshHome '$tempHome' -DshProfileDir '$tempProfile4' -CredentialsPath '$tempCreds'
"@
    $path4 = Join-Path $tempProfile4 "cordis.patch.yml"
    if (-not (Test-Path $path4)) {
        throw "ASSERTION FAILED: Missing generated file: $path4"
    }
    $yamlRaw4 = Get-Content $path4 -Raw
    foreach ($srv in @("memorix", "gitnexus", "company-atlassian", "context7", "glab", "cloakbrowser", "agency")) {
        if (-not $yamlRaw4.Contains("serverName: $srv")) {
            throw "ASSERTION FAILED: In Test 4, cordis.patch.yml must contain MCP '$srv'"
        }
    }
    if ($yamlRaw4.Contains("__AI_BASE_URL__") -or $yamlRaw4.Contains("__JIRA_URL__") -or $yamlRaw4.Contains("__GITNEXUS_CONFIG__") -or $yamlRaw4.Contains("__CONTEXT7_CONFIG__") -or $yamlRaw4.Contains("__CLOAKBROWSER_SCRIPT__")) {
        throw "ASSERTION FAILED: In Test 4, unresolved placeholders found in cordis.patch.yml"
    }
    # Test 5: Kiem tra Duplicate Guard va Removal Branch cho Memorix (Cordis + AGENTS.md)
    Write-Host "`nRunning DSH bootstrap (Test 5: Duplicate Guard & Removal Branch for Memorix)" -ForegroundColor Cyan
    $tempHome5 = Join-Path $env:TEMP ("dsh-home-test5-" + [System.Guid]::NewGuid().ToString("N"))
    $tempProfile5 = Join-Path $env:TEMP ("dsh-profile-test5-" + [System.Guid]::NewGuid().ToString("N"))

    # Bước 5.1: Cài đặt với -EnableMemorix
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -EnableMemorix -DshHome $tempHome5 -DshProfileDir $tempProfile5 -CredentialsPath $tempCreds
    $agentsPath5 = Join-Path $tempHome5 "AGENTS.md"
    $cordisPath5 = Join-Path $tempProfile5 "cordis.patch.yml"
    $agentsRaw5 = Get-Content $agentsPath5 -Raw
    $cordisRaw5 = Get-Content $cordisPath5 -Raw
    if (-not $agentsRaw5.Contains("Memorix") -or -not $cordisRaw5.Contains("mcp-memorix")) {
        throw "ASSERTION FAILED: Test 5.1 - Missing memorix in AGENTS.md or cordis.patch.yml"
    }

    # Bước 5.2: Idempotent - chạy lại -EnableMemorix, section Memorix trong AGENTS.md không bị lặp
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -EnableMemorix -DshHome $tempHome5 -DshProfileDir $tempProfile5 -CredentialsPath $tempCreds
    $agentsRaw5b = Get-Content $agentsPath5 -Raw
    $memCount = ([regex]::Matches($agentsRaw5b, "(?m)^#+ Memorix")).Count
    if ($memCount -ne 1) {
        throw "ASSERTION FAILED: Test 5.2 - Memorix section in AGENTS.md duplicated (count=$memCount)"
    }

    # Bước 5.3: Removal - chạy với -DisableMemorix, cordis.patch.yml phải bị gỡ mcp-memorix và AGENTS.md phải bị gỡ section Memorix
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -DisableMemorix -DshHome $tempHome5 -DshProfileDir $tempProfile5 -CredentialsPath $tempCreds
    $agentsRaw5c = Get-Content $agentsPath5 -Raw
    $cordisRaw5c = Get-Content $cordisPath5 -Raw
    if ($cordisRaw5c.Contains("mcp-memorix") -or $cordisRaw5c.Contains("serverName: memorix")) {
        throw "ASSERTION FAILED: Test 5.3 - cordis.patch.yml still contains mcp-memorix under -DisableMemorix"
    }
    if ($agentsRaw5c -match "(?m)^#+ Memorix" -or $agentsRaw5c.Contains("Memorix — Memory Tools")) {
        throw "ASSERTION FAILED: Test 5.3 - AGENTS.md still contains Memorix section under -DisableMemorix"
    }

    # =========================================================================
    # Test 6: Interactive input pipeline: thu tu prompt, wording agency, drive list
    # =========================================================================
    Write-Host "`n[Test 6] Interactive input pipeline: thu tu prompt, wording agency, drive list..." -ForegroundColor Cyan
    $inputs = @(
        'y', # Cai dat MCP memorix
        'y', # Cai dat Hook tich hop Memorix vao DSH (ngay sau memorix)
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
    $idxHook = $procText.IndexOf("[?] Cai dat Hook tich hop Memorix vao DSH? [y/N]")
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

    # 4. Kiem tra cordis.patch.yml sinh ra hop le
    $patchInteractive = Join-Path $tempProfileInteractive "cordis.patch.yml"
    if (-not (Test-Path $patchInteractive)) {
        throw "ASSERTION FAILED: Missing cordis.patch.yml in interactive test"
    }
    $yamlInteractive = Get-Content $patchInteractive -Raw
    if (-not $yamlInteractive.Contains("mcp-memorix") -or -not $yamlInteractive.Contains("mcp-agency") -or -not $yamlInteractive.Contains("mcp-cloakbrowser")) {
        throw "ASSERTION FAILED: cordis.patch.yml missing expected interactive MCPs"
    }
    Write-Host "  -> Interactive pipeline test PASS: Thu tu prompt, wording agency, drive list hop le." -ForegroundColor Green

    # =========================================================================
    # Test 7: Assert npm EBUSY khong abort bootstrap
    # =========================================================================
    Write-Host "`n[Test 7] Assert npm EBUSY khong abort bootstrap..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $mockEbusyDir | Out-Null
    $mockNpmContent = @'
@echo off
set "CMD_ARGS=%*"
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
        $ebusyOutput = & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -Force -EnableMemorix -DshHome $tempHome -DshProfileDir $tempProfileEbusy -CredentialsPath $tempCreds *>&1 | Out-String

        if (-not (Test-Path (Join-Path $tempProfileEbusy "cordis.patch.yml"))) {
            throw "ASSERTION FAILED: bootstrap aborted on npm EBUSY; cordis.patch.yml was not created"
        }
        if ($ebusyOutput -notmatch "EBUSY" -or $ebusyOutput -notmatch "lancedb\.node") {
            throw "ASSERTION FAILED: Warning for EBUSY/lancedb.node was not logged in output: $ebusyOutput"
        }
        Write-Host "  -> EBUSY resilience test PASS: bootstrap tiep tuc thanh cong khi npm install -g gap EBUSY." -ForegroundColor Green
    } finally {
        $env:Path = $prevEnvPath
    }
    # =========================================================================
    # Test 8: Assert memorix version check skip reinstall
    # =========================================================================
    Write-Host "`n[Test 8] Assert memorix version check skip reinstall..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $mockVerDir | Out-Null
    Set-Content -Path (Join-Path $mockVerDir "memorix.cmd") -Value "@echo off`r`nif `"%1`"==`"--version`" (echo 0.2.22& exit /b 0)`r`nexit /b 0"
    $mockNpmContent = @'
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
    Set-Content -Path (Join-Path $mockVerDir "npm.cmd") -Value $mockNpmContent

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
    # Test 9: Assert -EnableAgency khong truyen -AgencyPath (va -AgencyPath "") khong throw
    # =========================================================================
    Write-Host "`n[Test 9] Assert -EnableAgency default AgencyPath khong throw..." -ForegroundColor Cyan
    $tempProfileAgencyDefault = Join-Path $env:TEMP ("dsh-profile-agency-def-" + [System.Guid]::NewGuid().ToString("N"))
    $tempProfileAgencyEmpty = Join-Path $env:TEMP ("dsh-profile-agency-emp-" + [System.Guid]::NewGuid().ToString("N"))

    # Case A: khong truyen -AgencyPath
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -EnableAgency -DshHome $tempHome -DshProfileDir $tempProfileAgencyDefault -CredentialsPath $tempCreds
    $patchDef = Join-Path $tempProfileAgencyDefault "cordis.patch.yml"
    if (-not (Test-Path $patchDef)) {
        throw "ASSERTION FAILED: cordis.patch.yml missing in Test 9 Case A"
    }
    $yamlDef = Get-Content $patchDef -Raw
    if (-not $yamlDef.Contains("mcp-agency")) {
        throw "ASSERTION FAILED: cordis.patch.yml missing mcp-agency in Test 9 Case A"
    }

    # Case B: truyen -AgencyPath "" (chuoi rong phai khong bi ParameterBindingValidationException)
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -EnableAgency -AgencyPath "" -DshHome $tempHome -DshProfileDir $tempProfileAgencyEmpty -CredentialsPath $tempCreds
    $patchEmp = Join-Path $tempProfileAgencyEmpty "cordis.patch.yml"
    if (-not (Test-Path $patchEmp)) {
        throw "ASSERTION FAILED: cordis.patch.yml missing in Test 9 Case B"
    }
    $yamlEmp = Get-Content $patchEmp -Raw
    if (-not $yamlEmp.Contains("mcp-agency")) {
        throw "ASSERTION FAILED: cordis.patch.yml missing mcp-agency in Test 9 Case B"
    }
    Write-Host "  -> AgencyPath resilience test PASS: -EnableAgency khong truyen / truyen rong deu thanh cong." -ForegroundColor Green
    Write-Host "`nAll isolated tests passed successfully!" -ForegroundColor Green
}
finally {
    $env:Path = $oldPath
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
    if (Test-Path Function:npm) { Microsoft.PowerShell.Management\Remove-Item Function:npm -ErrorAction SilentlyContinue }
    Safe-Trash $tempHome
    Safe-Trash $tempProfile
    if ($tempProfile2) { Safe-Trash $tempProfile2 }
    if ($tempProfile3) { Safe-Trash $tempProfile3 }
    if ($tempProfile4) { Safe-Trash $tempProfile4 }
    if ($tempProfileInteractive) { Safe-Trash $tempProfileInteractive }
    if ($tempProfileEbusy) { Safe-Trash $tempProfileEbusy }
    if ($mockEbusyDir) { Safe-Trash $mockEbusyDir }
    if ($tempHome5) { Safe-Trash $tempHome5 }
    if ($tempProfile5) { Safe-Trash $tempProfile5 }
    Safe-Trash $tempCredsDir
    if ($tempProfileVer) { Safe-Trash $tempProfileVer }
    if ($mockVerDir) { Safe-Trash $mockVerDir }
    if ($tempProfileAgencyDefault) { Safe-Trash $tempProfileAgencyDefault }
    if ($tempProfileAgencyEmpty) { Safe-Trash $tempProfileAgencyEmpty }
}
