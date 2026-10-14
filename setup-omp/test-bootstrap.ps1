# test-bootstrap.ps1 - Assert-based test for bootstrap script
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

# Cô lập môi trường bằng thư mục tạm ngẫu nhiên
$tempDir = Join-Path $env:TEMP ("omp-test-" + [System.Guid]::NewGuid().ToString("N"))
$tempDir2 = Join-Path $env:TEMP ("omp-test-force-" + [System.Guid]::NewGuid().ToString("N"))
$mockBinDir = Join-Path $env:TEMP ("omp-mock-bin-" + [System.Guid]::NewGuid().ToString("N"))
$mockNpmDir = Join-Path $env:TEMP ("omp-mock-npm-" + [System.Guid]::NewGuid().ToString("N"))
$tempDir3 = Join-Path $env:TEMP ("omp-test-agency-" + [System.Guid]::NewGuid().ToString("N"))

$oldPath = $env:Path

try {
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "         BAT DAU KIEM THU CO LAP SETUP-OMP BOOTSTRAP            " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan

    # Bước 1: Thiết lập biến môi trường kiểm thử
    Write-Host "`n[Buoc 1/5] Thiet lap bien moi truong kiem thu..." -ForegroundColor Cyan
    $env:AI_BASE_URL = "https://test.local"
    $env:AI_API_KEY = "test-key-abc"
    $env:JIRA_URL = "https://test.jira"
    $env:JIRA_PERSONAL_TOKEN = "test-jira-token"
    $env:CONFLUENCE_URL = "https://test.conf"
    $env:CONFLUENCE_PERSONAL_TOKEN = "test-conf-token"
    $env:CONTEXT7_API_KEY = "test-ctx-token"

    # Bước 2: Tạo mock environment cho gitnexus và context7
    Write-Host "`n[Buoc 2/5] Mock moi truong gitnexus va context7 de test co lap hoan toan..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $mockBinDir | Out-Null
    Set-Content -Path (Join-Path $mockBinDir "gitnexus.cmd") -Value "@echo off`necho gitnexus"
    $env:Path = "$mockBinDir;$env:Path"

    $mockContext7Path = Join-Path $mockNpmDir "@upstash\context7-mcp\dist"
    New-Item -ItemType Directory -Force -Path $mockContext7Path | Out-Null
    Set-Content -Path (Join-Path $mockContext7Path "index.js") -Value "// mock"

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

    # =========================================================================
    # Test 1: Chạy bootstrap với -SkipInstall (non-interactive, all MCPs skipped)
    # =========================================================================
    Write-Host "`n[Buoc 3/5] Test 1: Chay bootstrap voi -SkipInstall non-interactive..." -ForegroundColor Cyan
    Write-Host "  -> Dich muc tieu: $tempDir" -ForegroundColor DarkGray
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -OmpDir $tempDir

    # Kiểm tra các file cấu hình được tạo
    Write-Host "  -> Kiem tra 3 file cau hinh: mcp.json, models.yml, config.yml..." -ForegroundColor Cyan
    foreach ($file in @("mcp.json", "models.yml", "config.yml")) {
        $path = Join-Path $tempDir $file
        if (-not (Test-Path $path)) {
            throw "ASSERTION FAILED: Missing generated file: $path"
        }
        $len = (Get-Item $path).Length
        if ($len -le 0) {
            throw "ASSERTION FAILED: Empty file: $path"
        }
    }

    # Kiểm tra models.yml đã thay thế đúng biến môi trường
    $modelsYml = Get-Content (Join-Path $tempDir "models.yml") -Raw
    if (-not $modelsYml.Contains("apiKey: test-key-abc")) {
        throw "ASSERTION FAILED: models.yml did not interpolate AI_API_KEY"
    }

    # Kiểm tra config.yml chứa đầy đủ routing và dynamic shellPath
    $configRaw = Get-Content (Join-Path $tempDir "config.yml") -Raw
    if (-not $configRaw.Contains("agentModelOverrides:") -or -not $configRaw.Contains("autoqaConsent: granted")) {
        throw "ASSERTION FAILED: config.yml missing task routing or dev flags"
    }
    if ($configRaw -notmatch '(?m)^shellPath:\s*.+$') {
        throw "ASSERTION FAILED: config.yml missing valid shellPath line"
    }

    # Kiểm tra các file tĩnh và extension Trash Guard
    Write-Host "  -> Kiem tra static files va Trash Guard extension..." -ForegroundColor Cyan
    foreach ($mdFile in @("AGENTS.md", "RULES.md", "SYSTEM.md")) {
        $path = Join-Path $tempDir $mdFile
        if (-not (Test-Path $path)) {
            throw "ASSERTION FAILED: Missing copied file: $path"
        }
    }
    $skillsDir = Join-Path $tempDir "skills"
    if (-not (Test-Path $skillsDir)) {
        throw "ASSERTION FAILED: Missing copied skills/ directory: $skillsDir"
    }
    $skillFiles = Get-ChildItem -Path $skillsDir -Recurse -Filter "SKILL.md"
    if ($skillFiles.Count -eq 0) {
        throw "ASSERTION FAILED: No SKILL.md found in copied skills/ directory"
    }

    $extFile = Join-Path $tempDir "extensions\no-hard-delete.ts"
    if (-not (Test-Path $extFile)) {
        throw "ASSERTION FAILED: Missing copied extensions/no-hard-delete.ts: $extFile"
    }

    # Kiểm tra mcp.json không chứa URL $schema 404
    $mcpRaw1 = Get-Content (Join-Path $tempDir "mcp.json") -Raw
    if ($mcpRaw1.Contains('"$schema"')) {
        throw "ASSERTION FAILED: mcp.json contains dead 404 `$schema reference"
    }

    # =========================================================================
    # Test 2: Chạy bootstrap THẬT với -Force và -EnableMemorix
    # =========================================================================
    Write-Host "`n[Buoc 4/5] Test 2: Chay bootstrap that voi -Force va -EnableMemorix..." -ForegroundColor Cyan
    Write-Host "  -> Dich muc tieu: $tempDir2" -ForegroundColor DarkGray
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -EnableMemorix -OmpDir $tempDir2

    Write-Host "  -> Kiem tra ket qua Test 2 (-Force / -EnableMemorix)..." -ForegroundColor Cyan
    $mcpRaw2 = Get-Content (Join-Path $tempDir2 "mcp.json") -Raw
    $mcpObj2 = $mcpRaw2 | ConvertFrom-Json

    # Assert mcp.json có block memorix khi -EnableMemorix được bật
    if (-not $mcpObj2.mcpServers.memorix) {
        throw "ASSERTION FAILED: mcp.json missing 'memorix' server under -EnableMemorix"
    }
    if ($mcpObj2.mcpServers.memorix.command -ne "memorix") {
        throw "ASSERTION FAILED: memorix command incorrect"
    }

    # Assert mcp.json có đầy đủ các core servers khác do chạy với -Force
    if (-not $mcpObj2.mcpServers.gitnexus) {
        throw "ASSERTION FAILED: mcp.json missing 'gitnexus' server under -Force"
    }
    if (-not $mcpObj2.mcpServers.'company-atlassian') {
        throw "ASSERTION FAILED: mcp.json missing 'company-atlassian' server under -Force"
    }
    if (-not $mcpObj2.mcpServers.context7) {
        throw "ASSERTION FAILED: mcp.json missing 'context7' server under -Force"
    }

    # Assert không còn bất kỳ placeholder dạng __VAR__ nào sót lại trong mcp.json
    if ($mcpRaw2 -match '__[A-Z0-9_]+__') {
        throw "ASSERTION FAILED: mcp.json still contains unreplaced placeholder: $matches[0]"
    }

    # Assert AGENTS.md được tích hợp section memorix
    $agentsRaw2 = Get-Content (Join-Path $tempDir2 "AGENTS.md") -Raw
    if (-not $agentsRaw2.Contains("Memorix: Memory and Safety Gate")) {
        throw "ASSERTION FAILED: AGENTS.md missing memorix section under -EnableMemorix"
    }

    # =========================================================================
    # Bước 5: Kiểm tra tính nguyên vẹn của templates/mcp.json
    # =========================================================================
    Write-Host "`n[Buoc 5/5] Kiem tra templates/ la nguon duy nhat va day du..." -ForegroundColor Cyan
    $mcpTemplate = Get-Content "$PSScriptRoot\templates\mcp.json" -Raw | ConvertFrom-Json
    if (-not $mcpTemplate.mcpServers.gitnexus -or -not $mcpTemplate.mcpServers.'company-atlassian' -or -not $mcpTemplate.mcpServers.context7 -or -not $mcpTemplate.mcpServers.cloakbrowser -or -not $mcpTemplate.mcpServers.memorix -or -not $mcpTemplate.mcpServers.agency) {
        throw "ASSERTION FAILED: templates/mcp.json missing base MCP definitions"
    }

    # =========================================================================
    # Test 3: Chay bootstrap voi -EnableAgency
    # =========================================================================
    Write-Host "`n[Test 3] Chay bootstrap that voi -EnableAgency..." -ForegroundColor Cyan
    Write-Host "  -> Dich muc tieu: $tempDir3" -ForegroundColor DarkGray
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -EnableAgency -OmpDir $tempDir3

    $mcpRaw3 = Get-Content (Join-Path $tempDir3 "mcp.json") -Raw
    $mcpObj3 = $mcpRaw3 | ConvertFrom-Json
    if (-not $mcpObj3.mcpServers.agency) {
        throw "ASSERTION FAILED: mcp.json missing 'agency' server under -EnableAgency"
    }
    if ($mcpObj3.mcpServers.agency.command -match '__AGENCY_PATH__') {
        throw "ASSERTION FAILED: agency command placeholder was not replaced"
    }
    if ($mcpObj3.mcpServers.agency.args.Count -ne 0) {
        throw "ASSERTION FAILED: agency args must be an empty array"
    }

    $agentsRaw3 = Get-Content (Join-Path $tempDir3 "AGENTS.md") -Raw
    if (-not $agentsRaw3.Contains("<!-- agency-agents-section -->")) {
        throw "ASSERTION FAILED: AGENTS.md missing agency marker under -EnableAgency"
    }
    if (-not $agentsRaw3.Contains("## Using Agency Agents MCP")) {
        throw "ASSERTION FAILED: AGENTS.md missing agency heading under -EnableAgency"
    }

    # Idempotent: chay lai -EnableAgency khong duoc tao marker trung lap
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -EnableAgency -OmpDir $tempDir3
    $agentsRaw3b = Get-Content (Join-Path $tempDir3 "AGENTS.md") -Raw
    $agencyMarkerCount = ([regex]::Matches($agentsRaw3b, [regex]::Escape("<!-- agency-agents-section -->"))).Count
    if ($agencyMarkerCount -ne 1) {
        throw "ASSERTION FAILED: agency marker duplicated (count=$agencyMarkerCount)"
    }

    # =========================================================================
    # Test 4: Chay bootstrap voi -DisableAgency tren cung thu muc
    # =========================================================================
    Write-Host "`n[Test 4] Chay bootstrap that voi -DisableAgency..." -ForegroundColor Cyan
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -Force -DisableAgency -OmpDir $tempDir3

    $mcpObj4 = (Get-Content (Join-Path $tempDir3 "mcp.json") -Raw) | ConvertFrom-Json
    if ($mcpObj4.mcpServers.agency) {
        throw "ASSERTION FAILED: mcp.json still contains 'agency' server under -DisableAgency"
    }
    $agentsRaw4 = Get-Content (Join-Path $tempDir3 "AGENTS.md") -Raw
    if ($agentsRaw4.Contains("<!-- agency-agents-section -->")) {
        throw "ASSERTION FAILED: AGENTS.md still contains agency marker under -DisableAgency"
    }

    # Test 1 da chay non-interactive khong bat agency: xac nhan mac dinh la vang
    $mcpObj1 = (Get-Content (Join-Path $tempDir "mcp.json") -Raw) | ConvertFrom-Json
    if ($mcpObj1.mcpServers.agency) {
        throw "ASSERTION FAILED: mcp.json unexpectedly contains 'agency' without -EnableAgency"
    }

    Write-Host "`n================================================================" -ForegroundColor Green
    Write-Host "   TAT CA CAC BAI TEST CO LAP CHO SETUP-OMP DEU DA PASS!       " -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
}
finally {
    # Dọn dẹp an toàn qua Safe-Trash
    $env:Path = $oldPath
    Safe-Trash -Path $tempDir
    Safe-Trash -Path $tempDir2
    Safe-Trash -Path $mockBinDir
    Safe-Trash -Path $mockNpmDir
    Safe-Trash -Path $tempDir3
}

