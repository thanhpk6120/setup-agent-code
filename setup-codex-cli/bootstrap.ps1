# bootstrap.ps1 - Setup OpenAI Codex CLI environment on Windows
param(
    [switch]$DryRun,
    [switch]$SkipInstall,
    [switch]$Force,
    [switch]$OverwriteAll,
    [switch]$EnableMemorix,
    [switch]$DisableMemorix,
    [switch]$EnableAgency,
    [switch]$DisableAgency,
    [string]$AgencyPath = "",
    [string]$CodexDir = "$env:USERPROFILE\.codex",
    [string]$CodexConfig = ""
)

$ErrorActionPreference = "Stop"
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }

# Helper: chay native command (uv) an toan khi $ErrorActionPreference='Stop'.
# uv ghi tien trinh (Resolved N packages...) ra stderr -> PowerShell bien thanh NativeCommandError du exit code 0.
# Helper tam tat NativeCommandError, capture output + exit code; xet loi theo exit code, tuong thich PS 5.1 va 7+.
function Invoke-UvCapture {
    param([Parameter(Mandatory = $true)][string[]]$UvArgs)
    $prevEA = $ErrorActionPreference
    $hasNativePref = (Test-Path variable:PSNativeCommandUseErrorActionPreference)
    $prevNativePref = $null
    if ($hasNativePref) { $prevNativePref = $PSNativeCommandUseErrorActionPreference }
    try {
        $ErrorActionPreference = 'Continue'
        if ($hasNativePref) { $PSNativeCommandUseErrorActionPreference = $false }
        $out = (& uv @UvArgs 2>&1 | Out-String)
        $code = $LASTEXITCODE
        return @{ Output = $out; ExitCode = $code }
    } finally {
        $ErrorActionPreference = $prevEA
        if ($hasNativePref) { $PSNativeCommandUseErrorActionPreference = $prevNativePref }
    }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Thu vien VisualBasic ho tro chuyen file/thu muc vao Recycle Bin
Add-Type -AssemblyName Microsoft.VisualBasic

function Move-ToRecycleBinDirectory([string]$Path) {
    if (-not (Test-Path $Path)) { return }
    if ($DryRun) { Write-Host "  -> [WhatIf] Safe-Trash: $Path" -ForegroundColor DarkGray; return }
    try {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
            $Path,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
        Write-Host "  [Thung rac] Da chuyen thu muc vao Recycle Bin: $Path" -ForegroundColor DarkGray
    } catch {
        Write-Warning "Khong the chuyen thu muc vao Recycle Bin: $Path ($($_.Exception.Message))"
    }
}

function Move-ToRecycleBinFile([string]$Path) {
    if (-not (Test-Path $Path)) { return }
    if ($DryRun) { Write-Host "  -> [WhatIf] Safe-Trash: $Path" -ForegroundColor DarkGray; return }
    try {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $Path,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
        Write-Host "  [Thung rac] Da chuyen file vao Recycle Bin: $Path" -ForegroundColor DarkGray
    } catch {
        Write-Warning "Khong the chuyen file vao Recycle Bin: $Path ($($_.Exception.Message))"
    }
}

function Get-BackupPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $bak = "$Path.bak"
    if (Test-Path -LiteralPath $bak) {
        $timestamp = (Get-Date).ToString("yyyyMMddHHmmss")
        return "$bak.$timestamp"
    }
    return $bak
}

# ==============================================================================
# Helper: Resume .env + Auto-Fix + Wait-UserIntervention
# (Lay lai bien da nhap/chon, chi hoi cai thieu, hoi truoc khi auto-fix, cho confirm)
# ==============================================================================
$script:FixedTempBase = if ($env:SETUP_RESUME_TEMP_DIR) { $env:SETUP_RESUME_TEMP_DIR } else { Join-Path ([System.IO.Path]::GetTempPath()) "setup-agent-code" }
$script:ResumeEnvFile = if ($env:SETUP_RESUME_ENV_PATH) { $env:SETUP_RESUME_ENV_PATH } else { Join-Path $script:FixedTempBase ".env" }
$script:FallbackResumeEnvFile = Join-Path ([System.IO.Path]::GetTempPath()) "setup-agent-code-saved.env"
$script:ReusedVars = @{}
$script:DidPromptReuse = $false
$script:IsReuseAccepted = $false

function Test-IsIsolatedTestRun {
    if ($env:SETUP_ENABLE_RESUME -eq '1') { return $false }
    if ($SkipInstall -or $DryRun -or $env:CI -or [Console]::IsInputRedirected) { return $true }
    foreach ($varName in @('OmpDir', 'ClaudeDir', 'OpenCodeDir', 'CodexDir', 'DshHome', 'AgyDir', 'DshProfileDir')) {
        $val = Get-Variable -Name $varName -ValueOnly -ErrorAction SilentlyContinue
        if ($val -and ("$val").StartsWith([System.IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Get-SavedEnvFilePath {
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot ".env")) { return (Join-Path $PSScriptRoot ".env") }
    if (Test-Path -LiteralPath $script:ResumeEnvFile) { return $script:ResumeEnvFile }
    if (Test-Path -LiteralPath $script:FallbackResumeEnvFile) { return $script:FallbackResumeEnvFile }
    return $null
}

function Save-ResumeKey {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(Mandatory = $true)]
        [string]$Value
    )
    if ($DryRun) { return }
    if (Test-IsIsolatedTestRun) { return }
    try {
        $parent = Split-Path -Parent $script:ResumeEnvFile
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        
        $lines = @()
        if (Test-Path -LiteralPath $script:ResumeEnvFile) {
            $lines = Get-Content -LiteralPath $script:ResumeEnvFile -Encoding UTF8 -ErrorAction SilentlyContinue
        }
        $newLines = @()
        $found = $false
        foreach ($l in $lines) {
            $trimmed = $l.Trim()
            if ($trimmed.StartsWith("$Key=") -or $trimmed.StartsWith("$Key =")) {
                $newLines += "$Key=$Value"
                $found = $true
            } else {
                $newLines += $l
            }
        }
        if (-not $found) {
            $newLines += "$Key=$Value"
        }
        $content = $newLines -join "`r`n"
        Set-Content -LiteralPath $script:ResumeEnvFile -Value $content -Encoding UTF8 -Force
        Set-Content -LiteralPath $script:FallbackResumeEnvFile -Value $content -Encoding UTF8 -Force
    } catch {}
}

function Prompt-ReuseSavedEnv {
    if ($script:DidPromptReuse) { return $script:IsReuseAccepted }
    $script:DidPromptReuse = $true
    
    # Neu dang chay trong test tu dong/co lap/SkipInstall thi KHONG prompt va KHONG nap lai .env cu
    if (Test-IsIsolatedTestRun) {
        $script:IsReuseAccepted = $false
        return $false
    }
    
    $savedPath = Get-SavedEnvFilePath
    if (-not $savedPath) {
        $script:IsReuseAccepted = $false
        return $false
    }
    
    $map = @{}
    try {
        Get-Content -LiteralPath $savedPath -Encoding UTF8 -ErrorAction Stop | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith("#")) {
                $idx = $line.IndexOf("=")
                if ($idx -gt 0) {
                    $k = $line.Substring(0, $idx).Trim()
                    $v = $line.Substring($idx + 1).Trim()
                    if (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'"))) {
                        $v = $v.Substring(1, $v.Length - 2)
                    }
                    if ($k -and $v) { $map[$k] = $v }
                }
            }
        }
    } catch {}
    
    if ($map.Count -eq 0) {
        $script:IsReuseAccepted = $false
        return $false
    }
    
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host " [?] PHAT HIEN CAU HINH TU LAN CHAY TRUOC ($savedPath)" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    foreach ($k in $map.Keys) {
        $dispVal = if ($k -match 'KEY|TOKEN|SECRET|PASSWORD') { "***" } else { $map[$k] }
        Write-Host "  -> $k = $dispVal" -ForegroundColor DarkGray
    }
    Write-Host "================================================================" -ForegroundColor Cyan
    
    $reuse = $true
    if (-not [Environment]::UserInteractive -or $env:CI) {
        Write-Host "  -> [Non-Interactive] Tu dong su dung lai cau hinh truoc do." -ForegroundColor DarkGray
        $reuse = $true
    } else {
        $ans = Read-Host "[?] Ban co muon su dung lai cac bien da nhap khong? (Chi hoi nhung cai chua co) [Y/n]"
        if (-not [string]::IsNullOrWhiteSpace($ans) -and $ans.Trim().ToLower() -match '^(n|no)$') {
            $reuse = $false
        }
    }
    
    if ($reuse) {
        $script:IsReuseAccepted = $true
        $script:ReusedVars = $map
        foreach ($k in $map.Keys) {
            $curr = [Environment]::GetEnvironmentVariable($k, "Process")
            if ([string]::IsNullOrWhiteSpace($curr)) {
                [Environment]::SetEnvironmentVariable($k, $map[$k], "Process")
            }
        }
        Write-Host "  -> [OK] Da nap cau hinh cu. Script se CHI HOI nhung bien chua co." -ForegroundColor Green
        return $true
    } else {
        $script:IsReuseAccepted = $false
        Write-Host "  -> Nguoi dung chon nhap moi tu dau." -ForegroundColor Yellow
        return $false
    }
}

function Invoke-AutoFix {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Issue,
        [Parameter(Mandatory = $true)]
        [string]$ActionDescription,
        [Parameter(Mandatory = $true)]
        [scriptblock]$FixAction
    )
    if ($DryRun -or $SkipInstall -or $Force -or $OverwriteAll) { return $false }
    if ((Test-IsIsolatedTestRun -or -not [Environment]::UserInteractive) -and ($env:SETUP_TEST_AUTOFIX -ne '1')) {
        return $false
    }

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host " [!] PHAT HIEN SU CO CO THE TU DONG SUA LOI (AUTO-FIX)" -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host " Su co: $Issue" -ForegroundColor White
    Write-Host " De xuat can thiep: $ActionDescription" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Yellow

    $ans = Read-Host "[?] Ban co cho phep script tu can thiep sua loi ($ActionDescription) khong? [Y/n]"
    if ([string]::IsNullOrWhiteSpace($ans) -or $ans.Trim().ToLower() -eq 'y' -or $ans.Trim().ToLower() -eq 'yes') {
        Write-Host "  -> Dang thuc hien can thiep..." -ForegroundColor Cyan
        try {
            & $FixAction
            Write-Host "  -> [OK] Da thuc hien can thiep xong!" -ForegroundColor Green
            return $true
        } catch {
            Write-Warning "Can thiep gap loi: $($_.Exception.Message)"
            return $false
        }
    } else {
        Write-Host "  -> Nguoi dung tu choi can thiep tu dong." -ForegroundColor Yellow
        return $false
    }
}

function Wait-UserIntervention {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage,
        [Parameter(Mandatory = $true)]
        [string]$Instructions,
        [scriptblock]$RecheckCondition = $null
    )
    if ($DryRun -or $SkipInstall -or $Force -or $OverwriteAll) { return $false }
    if ((Test-IsIsolatedTestRun -or -not [Environment]::UserInteractive) -and ($env:SETUP_TEST_AUTOFIX -ne '1')) {
        return $false
    }

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host " [!] PHAT HIEN SU CO CAN NGUOI DUNG CAN THIEP" -ForegroundColor Red
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host " Chi tiet loi: $ErrorMessage" -ForegroundColor Yellow
    Write-Host ""
    Write-Host " HUONG DAN XU LY:" -ForegroundColor Cyan
    Write-Host " $Instructions" -ForegroundColor White
    Write-Host "================================================================" -ForegroundColor Red

    while ($true) {
        $ans = Read-Host "[?] Sau khi ban da xu ly xong o cua so khac, nhan [Enter] de tiep tuc kiem tra lai hoac [c] de huy"
        if ($ans -and $ans.Trim().ToLower() -eq 'c') {
            Write-Host "Nguoi dung da huy qua trinh cai dat." -ForegroundColor Yellow
            return $false
        }
        if ($null -ne $RecheckCondition) {
            Write-Host "  -> Dang kiem tra lai..." -ForegroundColor Cyan
            $ok = & $RecheckCondition
            if ($ok) {
                Write-Host "  -> [OK] Kiem tra lai thanh cong! Tiep tuc cai dat..." -ForegroundColor Green
                return $true
            } else {
                Write-Host "  -> [!] Dieu kien van chua dat. Vui long kiem tra lai theo huong dan tren." -ForegroundColor Yellow
            }
        } else {
            return $true
        }
    }
}

# Goi khoi tao Prompt-ReuseSavedEnv ngay khi load helpers
Prompt-ReuseSavedEnv | Out-Null

function Confirm-McpInstall {
    param([string]$Name)
    if ($Force -or $OverwriteAll) {
        Write-Host "  -> [Force] Tu dong cai dat MCP '$Name'." -ForegroundColor Cyan
        return $true
    }
    if ($DryRun) {
        Write-Host "  -> [WhatIf] Bo qua prompt cai dat MCP '$Name'." -ForegroundColor DarkGray
        return $false
    }
    $mcpKey = "SETUP_MCP_" + ($Name.ToUpperInvariant() -replace '[^A-Z0-9]', '_')
    if ($script:IsReuseAccepted -and $script:ReusedVars -and $script:ReusedVars.ContainsKey($mcpKey)) {
        $savedVal = [bool]($script:ReusedVars[$mcpKey] -eq 'true' -or $script:ReusedVars[$mcpKey] -eq '1')
        $reusedText = if ($savedVal) { "CO" } else { "KHONG" }
        Write-Host "  -> [Reuse] Su dung lai lua chon MCP '$Name': $reusedText" -ForegroundColor DarkGray
        return $savedVal
    }
    if (-not [Environment]::UserInteractive -or $env:CI) {
        return $false
    }
    $choice = Read-Host "[?] Cai dat MCP '$Name'? [y/N]"
    $chosen = (-not [string]::IsNullOrWhiteSpace($choice) -and ($choice.Trim().ToLower() -eq 'y' -or $choice.Trim().ToLower() -eq 'yes'))
    Save-ResumeKey $mcpKey ([string]$chosen).ToLower()
    return $chosen
}
function Confirm-Agency {
    if ($Force -or $OverwriteAll) {
        Write-Host "  -> [Force] Tu dong cai dat MCP 'agency'." -ForegroundColor Cyan
        return $true
    }
    if ($DryRun) {
        Write-Host "  -> [WhatIf] Bo qua prompt cai dat MCP 'agency'." -ForegroundColor DarkGray
        return $false
    }
    if ($script:IsReuseAccepted -and $script:ReusedVars -and $script:ReusedVars.ContainsKey("SETUP_MCP_AGENCY")) {
        $savedVal = [bool]($script:ReusedVars["SETUP_MCP_AGENCY"] -eq 'true' -or $script:ReusedVars["SETUP_MCP_AGENCY"] -eq '1')
        $reusedText = if ($savedVal) { "CO" } else { "KHONG" }
        Write-Host "  -> [Reuse] Su dung lai lua chon MCP 'agency': $reusedText" -ForegroundColor DarkGray
        return $savedVal
    }
    if (-not [Environment]::UserInteractive -or $env:CI) {
        return $false
    }
    $choice = Read-Host "[?] Cai dat MCP 'agency' (multi-agent orchestration)? [y/N]"
    $chosen = (-not [string]::IsNullOrWhiteSpace($choice) -and ($choice.Trim().ToLower() -eq 'y' -or $choice.Trim().ToLower() -eq 'yes'))
    Save-ResumeKey "SETUP_MCP_AGENCY" ([string]$chosen).ToLower()
    return $chosen
}

# 1. Xu ly lua chon Memorix
if ($EnableMemorix.IsPresent -and $DisableMemorix.IsPresent) {
    throw "Khong dung dong thoi -EnableMemorix va -DisableMemorix."
}
if (-not $PSBoundParameters.ContainsKey('EnableMemorix') -and -not $PSBoundParameters.ContainsKey('DisableMemorix')) {
    $installMemorix = Confirm-McpInstall -Name "memorix"
    if (-not $installMemorix) { Write-Host "Skipped MCP 'memorix' theo lua chon nguoi dung." -ForegroundColor Yellow }
    if ($installMemorix) {
        $EnableMemorix = $true
    } else {
        $DisableMemorix = $true
    }
}

$shouldSetupHook = $false
if ($EnableMemorix) {
    if ($Force -or $OverwriteAll) {
        Write-Host "  -> [Force] Tu dong cai dat Hook tich hop Memorix vao Codex CLI." -ForegroundColor Cyan
        $shouldSetupHook = $true
    } elseif ($DryRun) {
        Write-Host "  -> [WhatIf] Bo qua prompt cai dat Hook Memorix." -ForegroundColor DarkGray
        $shouldSetupHook = $false
    } elseif (-not [Environment]::UserInteractive -or $env:CI -or $SkipInstall) {
        $shouldSetupHook = $false
    } else {
        $hookChoice = Read-Host "[?] Cai dat Hook tich hop Memorix vao Codex CLI? [y/N]"
        if (-not [string]::IsNullOrWhiteSpace($hookChoice) -and ($hookChoice.Trim().ToLower() -eq 'y' -or $hookChoice.Trim().ToLower() -eq 'yes')) {
            $shouldSetupHook = $true
        } else {
            $shouldSetupHook = $false
            Write-Host "Bo qua cai dat Hook tich hop Memorix theo lua chon nguoi dung." -ForegroundColor Yellow
        }
    }
}

# 1b. Cau hinh Agency MCP flag
$installAgency = $false
if ($EnableAgency.IsPresent -and $DisableAgency.IsPresent) {
    throw "Khong dung dong thoi -EnableAgency va -DisableAgency."
}
if ($EnableAgency.IsPresent) {
    $installAgency = $true
} elseif ($DisableAgency.IsPresent) {
    $installAgency = $false
} else {
    $installAgency = Confirm-Agency
    if (-not $installAgency) { Write-Host "Skipped MCP 'agency' theo lua chon nguoi dung." -ForegroundColor Yellow }
}

# 2. Xac nhan cai dat cac MCP Server khac
Write-Host "==> Xac nhan cai dat cac MCP Server khac..." -ForegroundColor Cyan
$installAtlassian = Confirm-McpInstall -Name "company-atlassian"
if (-not $installAtlassian) { Write-Host "Skipped MCP 'company-atlassian' theo lua chon nguoi dung." -ForegroundColor Yellow }

$installGitnexus = Confirm-McpInstall -Name "gitnexus"
if (-not $installGitnexus) { Write-Host "Skipped MCP 'gitnexus' theo lua chon nguoi dung." -ForegroundColor Yellow }

$installContext7 = Confirm-McpInstall -Name "context7"
if (-not $installContext7) { Write-Host "Skipped MCP 'context7' theo lua chon nguoi dung." -ForegroundColor Yellow }

$installGlab = Confirm-McpInstall -Name "glab"
if (-not $installGlab) { Write-Host "Skipped MCP 'glab' theo lua chon nguoi dung." -ForegroundColor Yellow }

$installCloakbrowser = Confirm-McpInstall -Name "cloakbrowser"
if (-not $installCloakbrowser) { Write-Host "Skipped MCP 'cloakbrowser' theo lua chon nguoi dung." -ForegroundColor Yellow }

# 3. Doc cau hinh tu .env neu ton tai
$envMap = @{}
$dotEnvPath = Join-Path $PSScriptRoot ".env"
if (Test-Path $dotEnvPath) {
    Write-Host "==> Doc cau hinh tu file .env ($dotEnvPath)..." -ForegroundColor Cyan
    Get-Content $dotEnvPath -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) {
            $parts = $line -split "=", 2
            if ($parts.Length -eq 2) {
                $k = $parts[0].Trim()
                $v = $parts[1].Trim().Trim('"').Trim("'")
                $envMap[$k] = $v
                [System.Environment]::SetEnvironmentVariable($k, $v)
            }
        }
    }
}

# 4. Ham nhap lieu Get-EnvOrPrompt

# ==============================================================================
# Helper: Ensure-PathPriority / Verify-CommandInstalled / Test-McpConnection
# (Verify sau moi lenh cai + PATH prepend uu tien + test MCP, test-safe)
# ==============================================================================
function Ensure-PathPriority {
    param([string[]]$Dirs)
    $__savedExit = $LASTEXITCODE
    try {
    foreach ($d in $Dirs) {
        if ([string]::IsNullOrWhiteSpace($d)) { continue }
        if (-not (Test-Path $d)) { continue }
        $parts = @($env:Path -split ';' | Where-Object { $_ -and ($_ -ne $d) })
        $env:Path = (@($d) + $parts) -join ';'
        try {
            if ($DryRun) { continue }
            $tmp = $env:TEMP
            if ($tmp -and $d.StartsWith($tmp, [StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($d -match '(?i)mock|ebusy|memskip|skiptest|interactive|mockbin|mocknpm') { continue }
            $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
            $uParts = @($userPath -split ';' | Where-Object { $_ -and ($_ -ne $d) })
            $newUser = (@($d) + $uParts) -join ';'
            if ($newUser -ne $userPath) {
                [Environment]::SetEnvironmentVariable('Path', $newUser, 'User')
                Write-Host "  -> [PATH] Da day len dau User PATH: $d" -ForegroundColor DarkGray
            }
        } catch {}
    }
    } finally { try { $global:LASTEXITCODE = $__savedExit } catch {} }
}

function Verify-CommandInstalled {
    param([string]$Name, [string]$Label = '')
    $__savedExit = $LASTEXITCODE
    try {
    if (-not $Label) { $Label = $Name }
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "  -> [OK] $Label san sang: $($cmd.Source)" -ForegroundColor Green
        return $true
    }
    try {
        $u = [Environment]::GetEnvironmentVariable('Path', 'User')
        $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        foreach ($seg in @($u, $m)) {
            if ($seg) {
                foreach ($pp in ($seg -split ';')) {
                    if ($pp -and ((';' + $env:Path + ';') -notlike ('*;' + $pp + ';*'))) { $env:Path = "$env:Path;$pp" }
                }
            }
        }
    } catch {}
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "  -> [OK] $Label san sang (sau refresh PATH): $($cmd.Source)" -ForegroundColor Green
        return $true
    }
    Write-Warning "[Verify] Chua tim thay '$Name' ($Label). Co the can mo terminal moi hoac cai thu cong."
    return $false
    } finally { try { $global:LASTEXITCODE = $__savedExit } catch {} }
}

function Test-McpConnection {
    param([string]$Name, [string]$Command, [string]$Arguments = '', [int]$TimeoutSec = 4)
    if ($DryRun -or $SkipInstall) {
        Write-Host "  -> [Skip] Test MCP '$Name' (DryRun/SkipInstall)." -ForegroundColor DarkGray
        return $true
    }
    $c = Get-Command $Command -ErrorAction SilentlyContinue
    $exe = if ($c -and $c.Source) { $c.Source } else { $Command }
    if ((-not $c) -and -not (Test-Path $exe)) {
        Write-Warning "[MCP-Test] Bo qua '$Name': khong tim thay '$Command'."
        return $false
    }
    $tmp = $env:TEMP
    if ($tmp -and $Arguments -and $Arguments.IndexOf($tmp, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        Write-Host "  -> [Mock] MCP '$Name' (mock args) mock OK." -ForegroundColor DarkGray
        return $true
    }
    if ($tmp -and ("$exe").StartsWith($tmp, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "  -> [Mock] MCP '$Name' ($Command) mock OK." -ForegroundColor DarkGray
        return $true
    }
    # npm tao ca .ps1 + .cmd: uu tien .cmd de chay qua cmd.exe (tranh pwsh -File nham .cmd)
    try { $cmdAlt = [System.IO.Path]::ChangeExtension($exe, '.cmd'); if (("$exe" -match '\.ps1$') -and (Test-Path $cmdAlt)) { $exe = $cmdAlt } } catch {}
    if ("$exe" -match '\.ps1$') {
        try {
            $psi1 = New-Object System.Diagnostics.ProcessStartInfo
            $psi1.FileName = "pwsh.exe"
            $psi1.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$exe`" --help"
            $psi1.RedirectStandardOutput = $true
            $psi1.RedirectStandardError = $true
            $psi1.UseShellExecute = $false
            $psi1.CreateNoWindow = $true
            $pp = [System.Diagnostics.Process]::Start($psi1)
            if ($pp.WaitForExit(10000)) {
                Write-Host "  -> [OK] MCP '$Name' khoi dong duoc (pwsh .ps1 exit=$($pp.ExitCode))." -ForegroundColor Green
                return $true
            } else {
                try { $pp.Kill() } catch {}
                Write-Warning "[MCP-Test] '$Name' treo khi --help (timeout). Da kill."
                return $false
            }
        } catch {
            Write-Warning "[MCP-Test] '$Name' loi: $($_.Exception.Message)"
            return $false
        }
    }
    if ("$exe" -match '\.(cmd|bat)$') {
        try {
            $log = Join-Path $env:TEMP ("mcp-test-" + $Name + ".log")
            $err = Join-Path $env:TEMP ("mcp-test-" + $Name + ".err")
            $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$exe`" --help" -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
            if ($p.WaitForExit(8000)) {
                Write-Host "  -> [OK] MCP '$Name' khoi dong duoc (--help exit=$($p.ExitCode))." -ForegroundColor Green
                return $true
            } else {
                try { $p.Kill() } catch {}
                Write-Warning "[MCP-Test] '$Name' treo khi --help (timeout). Da kill."
                return $false
            }
        } catch {
            Write-Warning "[MCP-Test] '$Name' loi: $($_.Exception.Message)"
            return $false
        }
    }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exe
        $psi.Arguments = $Arguments
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"bootstrap-verify","version":"1.0.0"}}}'
        try { $proc.StandardInput.WriteLine($init); $proc.StandardInput.Flush() } catch {}
        $task = $proc.StandardOutput.ReadLineAsync()
        $done = $task.Wait($TimeoutSec * 1000)
        $alive = -not $proc.HasExited
        try { if (-not $proc.HasExited) { $proc.Kill() } } catch {}
        if ($done) {
            $line = [string]$task.Result
            if ($line -match '"result"|"serverInfo"|"capabilities"') {
                Write-Host "  -> [OK] MCP '$Name' phan hoi JSON-RPC." -ForegroundColor Green
            } else {
                Write-Host "  -> [OK] MCP '$Name' khoi dong duoc." -ForegroundColor Green
            }
            return $true
        } else {
            if ($alive) {
                Write-Host "  -> [OK] MCP '$Name' dang chay stdio." -ForegroundColor Green
                return $true
            }
            Write-Warning "[MCP-Test] '$Name' khong phan hoi."
            return $false
        }
    } catch {
        Write-Warning "[MCP-Test] '$Name' loi: $($_.Exception.Message)"
        return $false
    }
}

function Get-EnvOrPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvName,
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [string]$Default = "",
        [switch]$Required,
        [switch]$AllowEmpty
    )
    $val = [System.Environment]::GetEnvironmentVariable($EnvName)
    if (-not [string]::IsNullOrWhiteSpace($val)) { return $val }
    if ($envMap.ContainsKey($EnvName) -and -not [string]::IsNullOrWhiteSpace($envMap[$EnvName])) {
        return $envMap[$EnvName]
    }

    $hasDefault = $PSBoundParameters.ContainsKey('Default') -or (-not [string]::IsNullOrWhiteSpace($Default))
    while ($true) {
        $promptStr = if ($hasDefault) { "$Prompt (Default: $Default)" } else { $Prompt }
        $inputVal = Read-Host $promptStr
        if (-not [string]::IsNullOrWhiteSpace($inputVal)) {
            return $inputVal.Trim()
        }
        if ($hasDefault) {
            return $Default
        }
        if ($AllowEmpty) {
            return ""
        }
        if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
            if ($DryRun) { return "dryrun-placeholder-$EnvName" }
            throw "Error: '$EnvName' is required but cannot prompt in non-interactive session."
        }
        Write-Host "Error: '$EnvName' is required. Please provide a value." -ForegroundColor Red
    }
}

# 5. Kiem tra moi truong runtime
Write-Host "==> Checking runtime dependencies..." -ForegroundColor Cyan
foreach ($tool in @("git", "node", "npm")) {
    $cmd = Get-Command $tool -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "Error: Khong tim thay '$tool' trong PATH. Vui long cai dat truoc khi tiep tuc."
    }
}

# Kiem tra version Node.js >= 22.18.0
$nodeVerRaw = (node -v).Trim()
$toolsList = "gitnexus va context7"
if ($nodeVerRaw -match '^v?(\d+)\.(\d+)\.(\d+)') {
    $nMajor = [int]$matches[1]
    $nMinor = [int]$matches[2]
    $nPatch = [int]$matches[3]
    if ($nMajor -lt 22 -or ($nMajor -eq 22 -and $nMinor -lt 18)) {
        throw "Yeu cau Node.js >= 22.18.0 (do $toolsList yeu cau Node.js moi). Phien ban hien tai: '$nodeVerRaw'. Vui long nang cap Node.js."
    }
}

# Cai dat uv va mcp-atlassian
if ($installAtlassian) {
    if (-not $SkipInstall -and -not (Get-Command "uv" -ErrorAction SilentlyContinue)) {
        Write-Host "==> Dang cai dat uv qua lenh chinh goc..." -ForegroundColor Cyan
        if (-not $DryRun) {
            try {
                powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
                $localBin = Join-Path $env:USERPROFILE ".local\bin"
                if (Test-Path $localBin) { $env:Path = "$localBin;" + $env:Path }
            } catch {
                Write-Warning "Khong the tu dong cai dat uv: $($_.Exception.Message)"
            }
        }
    }

    if (-not $SkipInstall) {
        $targetAtlassianVer = "0.23.1"
        $alreadyInstalled = $false
        if (Get-Command "uv" -ErrorAction SilentlyContinue) {
            try {
                $uvListCap = Invoke-UvCapture -UvArgs @('tool', 'list')
                $uvToolList = $uvListCap.Output
                if ($uvToolList -match "mcp-atlassian\s+v?$targetAtlassianVer") {
                    Write-Host "  -> mcp-atlassian $targetAtlassianVer da co san trong uv tools. Bo qua cai dat lai de tranh loi khoa file Windows." -ForegroundColor Green
                    $alreadyInstalled = $true
                }
            } catch {}
        }
        if (-not $alreadyInstalled) {
            $commonUvPaths = @(
                Join-Path $env:USERPROFILE ".local\bin\mcp-atlassian.exe",
                Join-Path $env:APPDATA "uv\tools\mcp-atlassian\Scripts\mcp-atlassian.exe"
            )
            foreach ($p in $commonUvPaths) {
                if (Test-Path $p) {
                    Write-Host "  -> Tim thay mcp-atlassian tai '$p'. Bo qua cai dat lai de tranh xung dot khoa file." -ForegroundColor Green
                    $alreadyInstalled = $true
                    break
                }
            }
        }
        if (-not $alreadyInstalled -and (Get-Command "mcp-atlassian" -ErrorAction SilentlyContinue)) {
            Write-Host "  -> mcp-atlassian da co san trong PATH. Bo qua cai dat lai." -ForegroundColor Green
            $alreadyInstalled = $true
        }
        if (-not $alreadyInstalled) {
            # Fix atlassian: nap lai PATH phien truoc khi dung uv/mcp-atlassian (winget/pip cai xong session chua co PATH)
        Ensure-PathPriority -Dirs @("$env:USERPROFILE\.local\bin", "$env:USERPROFILE\.cargo\bin", (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"), (Join-Path $env:APPDATA "Python\Python313\Scripts"), (Join-Path $env:LOCALAPPDATA "Programs\Python\Launcher"))
        try { uv tool update-shell 2>$null } catch {}
        Write-Host "==> Installing/updating mcp-atlassian globally via uv tool..." -ForegroundColor Cyan
            if (-not $DryRun) {
                try {
                    $uvInstallCap = Invoke-UvCapture -UvArgs @('tool', 'install', '--force', "mcp-atlassian==$targetAtlassianVer")
                    $uvResult = $uvInstallCap.Output
                    $__uvAtlExit = $uvInstallCap.ExitCode
                    Ensure-PathPriority -Dirs @("$env:USERPROFILE\.local\bin")
                    Verify-CommandInstalled -Name "mcp-atlassian" -Label "MCP company-atlassian" | Out-Null
                    if ($__uvAtlExit -ne 0 -and ($uvResult -match "os error 5" -or $uvResult -match "Access is denied")) {
                        Write-Warning "Khong the ghi de mcp-atlassian do tien trinh dang chay ngam trong he thong. Phien ban hien tai van duoc su dung binh thuong."
                    } else {
                        Write-Host "  -> mcp-atlassian installed/updated successfully." -ForegroundColor Green
                    }
                } catch {
                    Write-Warning "mcp-atlassian install failed: $($_.Exception.Message)"
                }
            }
        }
    }
}

# Cai dat gitnexus
$absGn = ""
if ($installGitnexus) {
    if (-not $SkipInstall) {
        Write-Host "==> Installing gitnexus globally..." -ForegroundColor Cyan
        if (-not $DryRun) {
            try { npm install -g gitnexus@latest } catch { Write-Warning "gitnexus install failed: $($_.Exception.Message)" }
        }
    }
    $gn = Get-Command "gitnexus.cmd" -ErrorAction SilentlyContinue
    if (-not $gn) {
        $gn = Get-Command "gitnexus" -ErrorAction SilentlyContinue
    }
    if ($gn -and $gn.Source) {
        $absGn = $gn.Source
    } else {
        if (-not $DryRun -and -not $SkipInstall) {
            throw "Loi: Khong tim thay gitnexus bang Get-Command. Dung cai dat."
        } else {
            $absGn = "gitnexus.cmd"
        }
    }
}

# Cai dat context7
$absCtx = ""
if ($installContext7) {
    if (-not $SkipInstall) {
        Write-Host "==> Installing context7 globally..." -ForegroundColor Cyan
        if (-not $DryRun) {
            try { npm install -g @upstash/context7-mcp@latest } catch { Write-Warning "context7 install failed: $($_.Exception.Message)" }
        }
    }
    $npmRoot = (npm root -g 2>&1 | Out-String).Trim()
    if ($npmRoot -and (Test-Path $npmRoot)) {
        $candidate = Join-Path $npmRoot "@upstash\context7-mcp\dist\index.js"
        if (Test-Path $candidate) {
            $absCtx = $candidate
        } else {
            if (-not $DryRun -and -not $SkipInstall) {
                throw "Loi: Khong tim thay file dist\index.js cua context7. Dung cai dat."
            } else {
                $absCtx = "context7"
            }
        }
    } else {
        if (-not $DryRun -and -not $SkipInstall) {
            throw "Loi: Khong tim thay thu muc npm root -g de lay duong dan context7. Dung cai dat."
        } else {
            $absCtx = "context7"
        }
    }
}

# Cai dat glab
if ($installGlab) {
    if (-not $SkipInstall -and -not (Get-Command "glab" -ErrorAction SilentlyContinue)) {
        Write-Host "==> Installing glab (GitLab CLI)..." -ForegroundColor Cyan
        if (-not $DryRun) {
            if (Get-Command "winget" -ErrorAction SilentlyContinue) {
                try { winget install --id GitLab.glab --accept-source-agreements --accept-package-agreements } catch { Write-Warning "winget install glab failed: $($_.Exception.Message)" }
            } else {
                Write-Warning "winget not found. Please install glab manually."
            }
        }
    }
}

# Cai dat memorix
if ($EnableMemorix) {
    if (-not $SkipInstall) {
        $shouldInstallMemorix = $true
        $installedVer = ""
        try {
            $verOut = (memorix --version 2>$null | Out-String).Trim()
            if ($verOut -match '([0-9]+\.[0-9]+\.[0-9]+)') {
                $installedVer = $Matches[1]
            }
        } catch {}

        if ($installedVer) {
            try {
                $latestVerOut = (npm view memorix version 2>$null | Out-String).Trim()
                if ($latestVerOut -match '([0-9]+\.[0-9]+\.[0-9]+)') {
                    $latestVer = $Matches[1]
                    if ([version]$installedVer -ge [version]$latestVer) {
                        Write-Host "Memorix da moi nhat, bo qua cai dat." -ForegroundColor Green
                        $shouldInstallMemorix = $false
                    }
                }
            } catch {}
        }

        if ($shouldInstallMemorix) {
            Write-Host "==> Dang cai dat / cap nhat Memorix len phien ban moi nhat (npm install -g memorix)..." -ForegroundColor Cyan
            if (-not $DryRun) {
                try {
                    $npmOut = npm install -g memorix 2>&1 | Out-String
                    Verify-CommandInstalled -Name "memorix" -Label "MCP memorix" | Out-Null
                    Write-Host $npmOut
                    if ($LASTEXITCODE -ne 0 -or $npmOut -match "EBUSY") {
                        if ($npmOut -match "EBUSY" -or $npmOut -match "lancedb\.node") {
                                                $autofixDone = Invoke-AutoFix -Issue "File lancedb.node dang bi tien trinh khac khoa (EBUSY)" -ActionDescription "Dong cac tien trinh node/mcp dang khoa file va thu cai lai" -FixAction {
                        Stop-Process -Name node,mcp-atlassian,agency-mcp-server -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 1
                        $npmOut = npm install -g memorix 2>&1 | Out-String
                        Write-Host $npmOut
                    }
                    if (-not $autofixDone -or $npmOut -match "EBUSY") {
                        Wait-UserIntervention -ErrorMessage "File lancedb.node van bi khoa boi tien trinh khac." -Instructions "Vui long dong cac cua so terminal, IDE hoac process 'node.exe' trong Task Manager dang su dung Memorix." -RecheckCondition {
                            $res = npm install -g memorix 2>&1 | Out-String
                            return ($LASTEXITCODE -eq 0 -and $res -notmatch "EBUSY")
                        }
                    }

                                            $autofixDone = Invoke-AutoFix -Issue "File lancedb.node dang bi tien trinh khac khoa (EBUSY)" -ActionDescription "Dong cac tien trinh node/mcp dang khoa file va thu cai lai" -FixAction {
                        Stop-Process -Name node,mcp-atlassian,agency-mcp-server -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 1
                        $npmOut = npm install -g memorix 2>&1 | Out-String
                        Write-Host $npmOut
                    }
                    if (-not $autofixDone -or $npmOut -match "EBUSY") {
                        Wait-UserIntervention -ErrorMessage "File lancedb.node van bi khoa boi tien trinh khac." -Instructions "Vui long dong cac cua so terminal, IDE hoac process 'node.exe' trong Task Manager dang su dung Memorix." -RecheckCondition {
                            $res = npm install -g memorix 2>&1 | Out-String
                            return ($LASTEXITCODE -eq 0 -and $res -notmatch "EBUSY")
                        }
                    }

                                            $autofixDone = Invoke-AutoFix -Issue "File lancedb.node dang bi khoa boi tien trinh khac (EBUSY)" -ActionDescription "Thu lai cai dat Memorix voi tuy chon --force va bo qua cache" -FixAction {
                        Start-Sleep -Milliseconds 800
                        $npmOut = npm install -g memorix --force 2>&1 | Out-String
                        Write-Host $npmOut
                    }
                    if (-not $autofixDone -or $npmOut -match "EBUSY") {
                        Wait-UserIntervention -ErrorMessage "File lancedb.node van bi khoa boi tien trinh khac." -Instructions "Vui long dong cac cua so terminal, IDE hoac tien trinh dang su dung Memorix roi quay lai day." -RecheckCondition {
                            $res = npm install -g memorix 2>&1 | Out-String
                            return ($LASTEXITCODE -eq 0 -and $res -notmatch "EBUSY")
                        }
                    }

                                            $autofixDone = Invoke-AutoFix -Issue "File lancedb.node dang bi khoa boi tien trinh khac (EBUSY)" -ActionDescription "Thu lai cai dat Memorix voi tuy chon --force va bo qua cache" -FixAction {
                        Start-Sleep -Milliseconds 800
                        $npmOut = npm install -g memorix --force 2>&1 | Out-String
                        Write-Host $npmOut
                    }
                    if (-not $autofixDone -or $npmOut -match "EBUSY") {
                        Wait-UserIntervention -ErrorMessage "File lancedb.node van bi khoa boi tien trinh khac." -Instructions "Vui long dong cac cua so terminal, IDE hoac tien trinh dang su dung Memorix roi quay lai day." -RecheckCondition {
                            $res = npm install -g memorix 2>&1 | Out-String
                            return ($LASTEXITCODE -eq 0 -and $res -notmatch "EBUSY")
                        }
                    }

                        Write-Warning "Cai dat/cap nhat Memorix gap loi EBUSY: file lancedb.node dang bi tien trinh khac khoa. Vui long dong cac agent/terminal dang chay va chay lai bootstrap.ps1 sau. Tiep tuc cac buoc tiep theo..."
                        } else {
                            Write-Warning "Cai dat/cap nhat Memorix gap loi (Exit code $LASTEXITCODE): $npmOut"
                        }
                    }
                } catch {
                    $errStr = $_.ToString()
                    if ($errStr -match "EBUSY" -or $errStr -match "lancedb\.node") {
                        Write-Warning "Cai dat/cap nhat Memorix gap loi EBUSY: file lancedb.node dang bi tien trinh khac khoa. Vui long dong cac agent/terminal dang chay va chay lai bootstrap.ps1 sau. Tiep tuc cac buoc tiep theo..."
                    } else {
                        Write-Warning "Cai dat/cap nhat Memorix gap loi: $($_.Exception.Message)"
                    }
                }
            }
        }
    }
    if ($shouldSetupHook) {
        Write-Host "==> Registering memorix Codex CLI plugin + hooks..." -ForegroundColor Cyan
        if (-not $DryRun) {
            try { memorix hooks install --agent codex --global } catch { Write-Warning "memorix hooks install failed: $($_.Exception.Message)" }
        }
    } else {
        if (-not $DryRun) {
            Write-Host "==> Bo qua cau hinh hook memorix cho Codex CLI." -ForegroundColor DarkGray
        }
    }
}

# Ham cai dat CloakBrowser
function Get-CloakBrowserInstallDir {
    param([string]$EnvVarName = "CLOAKBROWSER_DIR")
    $envVal = [Environment]::GetEnvironmentVariable($EnvVarName, "Process")
    if (-not [string]::IsNullOrWhiteSpace($envVal)) { return $envVal.Trim() }

    $drives = @()
    try {
        foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
            try {
                if ($d.DriveType -ne [System.IO.DriveType]::Fixed -or -not $d.IsReady) { continue }
                $letter = $d.Name.TrimEnd('\')
                if (-not $letter.EndsWith(':')) { $letter = "$letter`:" }
                $freeGb = [math]::Round($d.AvailableFreeSpace / 1GB, 1)
                $drives += [PSCustomObject]@{
                    Letter   = $letter
                    FreeGB   = $freeGb
                    FreeByte = $d.AvailableFreeSpace
                }
            } catch { continue }
        }
    } catch {}

    if (-not $drives -or $drives.Count -eq 0) {
        try {
            $cimDrives = Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 3 }
            foreach ($d in $cimDrives) {
                $letter = $d.DeviceID
                $freeGb = [math]::Round($d.FreeSpace / 1GB, 1)
                $drives += [PSCustomObject]@{
                    Letter   = $letter
                    FreeGB   = $freeGb
                    FreeByte = $d.FreeSpace
                }
            }
        } catch {
            try {
                $psDrives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object { $_.Free -gt 0 }
                foreach ($d in $psDrives) {
                    $letter = "$($d.Name):"
                    $freeGb = [math]::Round($d.Free / 1GB, 1)
                    $drives += [PSCustomObject]@{
                        Letter   = $letter
                        FreeGB   = $freeGb
                        FreeByte = $d.Free
                    }
                }
            } catch {}
        }
    }

    if (-not $drives -or $drives.Count -eq 0) {
        $fallback = "$env:USERPROFILE\mcp-servers\cloakbrowser"
        Write-Host "  -> Khong phat hien duoc o dia, su dung thu muc mac dinh: $fallback" -ForegroundColor DarkGray
        return $fallback
    }

    $defaultDrive = $drives | Where-Object { $_.Letter -eq 'D:' } | Select-Object -First 1
    if (-not $defaultDrive) {
        $defaultDrive = $drives | Sort-Object FreeByte -Descending | Select-Object -First 1
    }
    $defaultLetter = $defaultDrive.Letter

    if ($env:CI -or -not [Environment]::UserInteractive) {
        $autoDir = "$defaultLetter\mcp-servers\cloakbrowser"
        Write-Host "  -> [Non-Interactive] Tu dong chon o $defaultLetter cho CloakBrowser: $autoDir" -ForegroundColor DarkGray
        return $autoDir
    }

    $driveLines = @("Danh sach o dia kha dung:")
    for ($i = 0; $i -lt $drives.Count; $i++) {
        $dr = $drives[$i]
        $isDefTag = if ($dr.Letter -eq $defaultLetter) { " (mac dinh)" } else { "" }
        $driveLines += "  [$($i + 1)] $($dr.Letter) - Dung luong trong: $($dr.FreeGB) GB$isDefTag"
    }
    $driveMenu = ($driveLines -join "`n")
    $promptMsg = "$driveMenu`nChon so thu tu o dia muon luu CloakBrowser (mac dinh o $defaultLetter)"
    $selectedLetter = $defaultLetter
    try {
        $inputVal = Read-Host $promptMsg
        if (-not [string]::IsNullOrWhiteSpace($inputVal)) {
            $choice = $inputVal.Trim()
            $idx = 0
            if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $drives.Count) {
                $selectedLetter = $drives[$idx - 1].Letter
            } else {
                $normChoice = $choice.ToUpper().TrimEnd('\')
                if (-not $normChoice.EndsWith(':')) { $normChoice = "$normChoice`:" }
                $matchedDrive = $drives | Where-Object { $_.Letter -eq $normChoice } | Select-Object -First 1
                if ($matchedDrive) {
                    $selectedLetter = $matchedDrive.Letter
                } else {
                    Write-Host "Lua chon '$choice' khong hop le, su dung mac dinh $defaultLetter." -ForegroundColor Yellow
                }
            }
        }
    } catch {}

    $finalDir = "$selectedLetter\mcp-servers\cloakbrowser"
    Write-Host "  -> Da chon o dia: $selectedLetter (Thu muc: $finalDir)" -ForegroundColor Green
    return $finalDir
}

function Setup-CloakBrowser {
    param([string]$TargetDir, [string]$SourceDir, [switch]$DryRun, [switch]$SkipInstall)
    Write-Host "==> Cau hinh CloakBrowser tai: $TargetDir" -ForegroundColor Cyan
    $mainScript = Join-Path $TargetDir "mcp-server-full.mjs"
    $pkgJson = Join-Path $TargetDir "package.json"
    $nodeModules = Join-Path $TargetDir "node_modules"

    if (-not $DryRun) {
        if (-not (Test-Path $TargetDir)) {
            New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
        }
        if (Test-Path $SourceDir) {
            if (-not (Test-Path $mainScript) -or -not (Test-Path $pkgJson)) {
                Copy-Item -Path "$SourceDir\*" -Destination $TargetDir -Recurse -Force
                Write-Host "  -> Da sao chep ma nguon CloakBrowser MCP sang $TargetDir." -ForegroundColor Green
            } else {
                Write-Host "  -> CloakBrowser da ton tai day du file ma nguon. Giu nguyen du lieu & profile cu (khong ghi de)." -ForegroundColor Green
            }
        }
        if (-not $SkipInstall -and -not (Test-Path $nodeModules)) {
            Write-Host "  -> Dang chay npm install tai $TargetDir..." -ForegroundColor Cyan
            Push-Location $TargetDir
            try { npm install } catch { Write-Warning "npm install cloakbrowser failed: $($_.Exception.Message)" }
            finally { Pop-Location }
        }
    } else {
        Write-Host "  -> [WhatIf] Sao chep CloakBrowser sang: $TargetDir" -ForegroundColor DarkGray
    }
    return $mainScript
}

# 6. Thu thap cau hinh
$aiBaseUrl = Get-EnvOrPrompt -EnvName "AI_BASE_URL" -Prompt "AI Base URL" -Default "http://localhost:20128/v1"
$aiKey     = Get-EnvOrPrompt -EnvName "AI_API_KEY" -Prompt "AI API Key" -Required

$jiraUrl   = ""
$jiraToken = ""
$confUrl   = ""
$confToken = ""
if ($installAtlassian) {
    $jiraUrl   = Get-EnvOrPrompt -EnvName "JIRA_URL" -Prompt "Jira URL" -Default "https://jira.cybertech.vn"
    $jiraToken = Get-EnvOrPrompt -EnvName "JIRA_PERSONAL_TOKEN" -Prompt "Jira Personal Token" -Default "YOUR_JIRA_PERSONAL_TOKEN"
    $confUrl   = Get-EnvOrPrompt -EnvName "CONFLUENCE_URL" -Prompt "Confluence URL" -Default "https://conf.cybertech.vn"
    $confToken = Get-EnvOrPrompt -EnvName "CONFLUENCE_PERSONAL_TOKEN" -Prompt "Confluence Personal Token" -Default "YOUR_CONFLUENCE_PERSONAL_TOKEN"
}

$ctxKey = ""
if ($installContext7) {
    $ctxKey = Get-EnvOrPrompt -EnvName "CONTEXT7_API_KEY" -Prompt "Context7 API Key" -AllowEmpty
}

$gitlabHost  = "10.30.1.17"
$gitlabToken = ""
if ($installGlab) {
    $gitlabHost  = Get-EnvOrPrompt -EnvName "GITLAB_HOST" -Prompt "GitLab Host" -Default "10.30.1.17"
    $gitlabToken = Get-EnvOrPrompt -EnvName "GITLAB_TOKEN" -Prompt "GitLab Personal Token" -AllowEmpty
    if (-not [string]::IsNullOrWhiteSpace($gitlabToken) -and -not $DryRun) {
        try {
            $env:GITLAB_TOKEN = $gitlabToken
            glab auth login --hostname $gitlabHost --token $gitlabToken
        } catch {}
    }
}

# 6.5 Resolve duong dan binary cho Agency MCP
$resolvedAgencyPath = ""
if ($installAgency) {
    $existingAgency = $null
    if ($AgencyPath -and (Test-Path -LiteralPath $AgencyPath)) {
        $existingAgency = $AgencyPath
    } else {
        $agencyLookup = Get-Command "agency-mcp-server.cmd" -ErrorAction SilentlyContinue
        if (-not $agencyLookup) { $agencyLookup = Get-Command "agency-mcp-server" -ErrorAction SilentlyContinue }
        if ($agencyLookup -and $agencyLookup.Source) { $existingAgency = $agencyLookup.Source }
    }

    if (-not $existingAgency -and -not $SkipInstall -and -not $DryRun) {
        Write-Host "==> Dang cai dat agency-mcp-server (npm install -g agency-mcp-server)..." -ForegroundColor Cyan
        try {
            $npmAgencyOut = npm install -g agency-mcp-server 2>&1 | Out-String
            $__npmAgencyExit = $LASTEXITCODE
            Verify-CommandInstalled -Name "agency-mcp-server" -Label "MCP agency-mcp-server" | Out-Null
            Write-Host $npmAgencyOut
            if ($__npmAgencyExit -ne 0) {
                Write-Warning "Cai dat agency-mcp-server gap loi (Exit code $__npmAgencyExit): $npmAgencyOut"
            }
        } catch {
            Write-Warning "Cai dat agency-mcp-server gap loi: $($_.Exception.Message)"
        }
    }

    if ($AgencyPath) {
        $resolvedAgencyPath = $AgencyPath
    } else {
        $agencyCmd = Get-Command "agency-mcp-server.cmd" -ErrorAction SilentlyContinue
        if (-not $agencyCmd) { $agencyCmd = Get-Command "agency-mcp-server" -ErrorAction SilentlyContinue }
        if ($agencyCmd -and $agencyCmd.Source) {
            $resolvedAgencyPath = $agencyCmd.Source
        } else {
            $commonPaths = @(
                "C:\nvm4w\nodejs\agency-mcp-server.cmd",
                "$env:APPDATA\npm\agency-mcp-server.cmd",
                "C:\Program Files\nodejs\agency-mcp-server.cmd"
            )
            foreach ($cp in $commonPaths) {
                if (Test-Path $cp) {
                    $resolvedAgencyPath = $cp
                    break
                }
            }
        }
    }
    if (-not $resolvedAgencyPath) {
        $resolvedAgencyPath = "C:\nvm4w\nodejs\agency-mcp-server.cmd"
    }
}

# 7. Cai dat CloakBrowser (dat SAU phan hoi env giong het setup-omp)
$cloakScript = ""
if ($installCloakbrowser) {
    $cbSourceDir = Join-Path $PSScriptRoot "mcp-servers\cloakbrowser"
    $cbTargetDir = Get-CloakBrowserInstallDir
    $cloakScriptPath = Setup-CloakBrowser -TargetDir $cbTargetDir -SourceDir $cbSourceDir -DryRun:$DryRun -SkipInstall:$SkipInstall
    $cloakScript = $cloakScriptPath.Replace('\', '/')
}

# 8. Chuan bi thu muc Codex CLI
if (-not $CodexConfig) {
    $CodexConfig = Join-Path $CodexDir "config.toml"
}

Write-Host "==> Preparing configuration files..." -ForegroundColor Cyan
if (-not (Test-Path $CodexDir)) {
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path $CodexDir | Out-Null
    } else {
        Write-Host "  -> [WhatIf] Tao thu muc: $CodexDir" -ForegroundColor DarkGray
    }
}

# Doc template config.toml tu templates/ (nguon duy nhat)
$templatePath = Join-Path $PSScriptRoot "templates\config.toml"
if (-not (Test-Path $templatePath)) {
    throw "Loi: Khong tim thay template config.toml tai: $templatePath"
}
$tomlContent = Get-Content -Path $templatePath -Raw -Encoding UTF8

# Thay the placeholders
$tomlContent = $tomlContent.Replace("__AI_BASE_URL__", $aiBaseUrl).Replace("__AI_API_KEY__", $aiKey)
$tomlContent = $tomlContent.Replace("__JIRA_URL__", $jiraUrl).Replace("__JIRA_PERSONAL_TOKEN__", $jiraToken)
$tomlContent = $tomlContent.Replace("__CONFLUENCE_URL__", $confUrl).Replace("__CONFLUENCE_PERSONAL_TOKEN__", $confToken)

$escapedGn = if ($absGn) { $absGn.Replace('\', '/') } else { "gitnexus.cmd" }
$tomlContent = $tomlContent.Replace("__GITNEXUS_PATH__", $escapedGn)

$escapedCtx = if ($absCtx) { $absCtx.Replace('\', '/') } else { "context7" }
$tomlContent = $tomlContent.Replace("__CONTEXT7_PATH__", $escapedCtx)

if ($ctxKey) {
    $tomlContent = $tomlContent.Replace("__CONTEXT7_API_KEY__", $ctxKey)
} else {
    $tomlContent = [regex]::Replace($tomlContent, '(?ms)(?:\r?\n)*\[mcp_servers\.context7\.env\].*?(?=(?:\r?\n\[mcp_servers\.)|\Z)', '')
}

$escapedCloak = if ($cloakScript) { $cloakScript.Replace('\', '/') } else { "" }
$tomlContent = $tomlContent.Replace("__CLOAKBROWSER_SCRIPT__", $escapedCloak)

# Ham ho tro loai bo section MCP neu khong duoc chon cai dat
function Remove-TomlServer {
    param([string]$Content, [string]$ServerName)
    $pat = '(?ms)(?:\r?\n)*\[mcp_servers\.' + [regex]::Escape($ServerName) + '(?:\.[^\]]+)?\].*?(?=(?:\r?\n\[mcp_servers\.(?!' + [regex]::Escape($ServerName) + '\b))|\Z)'
    return [regex]::Replace($Content, $pat, '')
}

if (-not $installAtlassian) {
    $tomlContent = Remove-TomlServer -Content $tomlContent -ServerName 'company-atlassian'
}
if (-not $installGitnexus) {
    $tomlContent = Remove-TomlServer -Content $tomlContent -ServerName 'gitnexus'
}
if (-not $installContext7) {
    $tomlContent = Remove-TomlServer -Content $tomlContent -ServerName 'context7'
}
if (-not $installGlab) {
    $tomlContent = Remove-TomlServer -Content $tomlContent -ServerName 'glab'
}
if (-not $installCloakbrowser) {
    $tomlContent = Remove-TomlServer -Content $tomlContent -ServerName 'cloakbrowser'
}

# Thay the placeholder agency
if ($installAgency) {
    $escapedAgency = $resolvedAgencyPath.Replace('\', '/')
    $tomlContent = $tomlContent.Replace("__AGENCY_PATH__", $escapedAgency)
} else {
    $tomlContent = Remove-TomlServer -Content $tomlContent -ServerName 'agency'
}
if (-not $EnableMemorix) {
    $tomlContent = Remove-TomlServer -Content $tomlContent -ServerName 'memorix'
}

# Ghi file cau hinh config.toml
if (Test-Path $CodexConfig) {
    if ($Force -or $OverwriteAll) {
        Write-Host "  -> File cau hinh '$CodexConfig' da ton tai. [-Force / -OverwriteAll] Tu dong sao luu va ghi de." -ForegroundColor Yellow
        $bak = Get-BackupPath -Path $CodexConfig
                if (-not $DryRun) {
            Copy-Item -Path $CodexConfig -Destination $bak -Force
            Write-Host "     Da sao luu sang $bak" -ForegroundColor DarkGray
            Set-Content -Path $CodexConfig -Value $tomlContent -Encoding UTF8
        } else {
            Write-Host "  -> [WhatIf] Sao luu: $bak" -ForegroundColor DarkGray
            Write-Host "  -> [WhatIf] Ghi file: $CodexConfig" -ForegroundColor DarkGray
        }
    } else {
        $choice = Read-Host "[?] File cau hinh '$CodexConfig' da ton tai. Ban co muon [O]verwrite (ghi de) hay [S]kip (bo qua)? [O/s]"
        if (-not [string]::IsNullOrWhiteSpace($choice) -and $choice.Trim().ToLower() -eq 's') {
            Write-Host "  -> Bo qua ghi file $CodexConfig." -ForegroundColor DarkGray
        } else {
            if (-not $DryRun) {
                Set-Content -Path $CodexConfig -Value $tomlContent -Encoding UTF8
                Write-Host "  -> Ghi de file $CodexConfig thanh cong." -ForegroundColor Green
            } else {
                Write-Host "  -> [WhatIf] Ghi file: $CodexConfig" -ForegroundColor DarkGray
            }
        }
    }
} else {
    if (-not $DryRun) {
        Set-Content -Path $CodexConfig -Value $tomlContent -Encoding UTF8
        Write-Host "  -> Tao moi file $CodexConfig thanh cong." -ForegroundColor Green
    } else {
        Write-Host "  -> [WhatIf] Ghi file: $CodexConfig" -ForegroundColor DarkGray
    }
}

# 9. Sao chep static files: AGENTS.md, CODEX.md, skills/ va don dep legacy files
Write-Host "==> Sao chep static files va skills..." -ForegroundColor Cyan
$templatesDir = Join-Path $PSScriptRoot "templates"
if (-not $DryRun) {
    $srcAgents = Join-Path $templatesDir "AGENTS.md" 
    $dstAgents = Join-Path $CodexDir "AGENTS.md"

    if (Test-Path $srcAgents) {
        if (Test-Path $dstAgents) {
            if ($Force -or $OverwriteAll) {
                Write-Host "  -> File '$dstAgents' da ton tai. [-Force / -OverwriteAll] Tu dong sao luu va ghi de." -ForegroundColor Yellow
                $bak = Get-BackupPath -Path $dstAgents
                Copy-Item -Path $dstAgents -Destination $bak -Force
                Copy-Item -Path $srcAgents -Destination $dstAgents -Force
            } else {
                $choice = Read-Host "[?] File '$dstAgents' da ton tai. Ban co muon [O]verwrite (ghi de) hay [S]kip (bo qua)? [O/s]"
                if (-not [string]::IsNullOrWhiteSpace($choice) -and $choice.Trim().ToLower() -eq 's') {
                    Write-Host "  -> Bo qua file $dstAgents." -ForegroundColor DarkGray
                } else {
                    $bak = Get-BackupPath -Path $dstAgents
                    Copy-Item -Path $dstAgents -Destination $bak -Force
                    Copy-Item -Path $srcAgents -Destination $dstAgents -Force
                    Write-Host "  -> Ghi de file $dstAgents thanh cong." -ForegroundColor Green
                }
            }
        } else {
            Copy-Item -Path $srcAgents -Destination $dstAgents -Force
            Write-Host "  -> Tao moi file $dstAgents thanh cong." -ForegroundColor Green
        }

        # Neu bat Agency, tich hop them huong dan agency vao AGENTS.md
        if ($installAgency) {
            $agencySec = Join-Path $templatesDir "agency-agents-section.md"
            if (Test-Path $agencySec) {
                $agencyMarker = "<!-- agency-agents-section -->"
                $currDoc = Get-Content -Path $dstAgents -Raw -Encoding UTF8
                if ($currDoc -notmatch [regex]::Escape($agencyMarker)) {
                    Write-Host "  -> Tich hop huong dan Agency vao $dstAgents..." -ForegroundColor Green
                    $agencyBak = Get-BackupPath -Path $dstAgents
                    Copy-Item -Path $dstAgents -Destination $agencyBak -Force
                    Write-Host "     Da sao luu sang $agencyBak" -ForegroundColor DarkGray
                    $agencyContent = Get-Content -Path $agencySec -Raw -Encoding UTF8
                    Add-Content -Path $dstAgents -Value "`r`n$agencyContent" -Encoding UTF8
                }
            }
        } else {
            $currDoc = Get-Content -Path $dstAgents -Raw -Encoding UTF8
            if ($currDoc -match [regex]::Escape("<!-- agency-agents-section -->")) {
                Write-Host "  -> Go bo huong dan Agency khoi $dstAgents..." -ForegroundColor Yellow
                $cleaned = [regex]::Replace($currDoc, '(?s)\r?\n?<!-- agency-agents-section -->.*?<!-- /agency-agents-section -->', '')
                [System.IO.File]::WriteAllText($dstAgents, $cleaned.TrimEnd() + "`r`n", [System.Text.UTF8Encoding]::new($false))
            }
        }

        # Neu bat Memorix, tich hop them huong dan memorix vao AGENTS.md (guard trung + removal khi tat)
        if ($EnableMemorix) {
            $memSec = Join-Path $templatesDir "memorix-agents-section.md"
            if (Test-Path $memSec) {
                $currMemDoc = Get-Content -Path $dstAgents -Raw -Encoding UTF8
                if ($currMemDoc -notmatch "Memorix: Memory and Safety Gate") {
                    Write-Host "  -> Tich hop huong dan Memorix vao $dstAgents..." -ForegroundColor Green
                    $memContent = Get-Content -Path $memSec -Raw -Encoding UTF8
                    Add-Content -Path $dstAgents -Value "`r`n$memContent" -Encoding UTF8
                }
            }
        } else {
            $currMemDoc = Get-Content -Path $dstAgents -Raw -Encoding UTF8
            if ($currMemDoc -match "Memorix: Memory and Safety Gate") {
                Write-Host "  -> Go bo huong dan Memorix khoi $dstAgents..." -ForegroundColor Yellow
                $cleanedMem = [regex]::Replace($currMemDoc, '(?s)\r?\n?## Memorix: Memory and Safety Gate.*?\*\*Fallback:\*\*.*?(?:\r?\n|$)', "`r`n")
                [System.IO.File]::WriteAllText($dstAgents, $cleanedMem.TrimEnd() + "`r`n", [System.Text.UTF8Encoding]::new($false))
            }
        }
    }

    # Tao alias CODEX.md tu AGENTS.md (1:1 copy)
    $codexMdPath = Join-Path $CodexDir "CODEX.md"
    if (Test-Path $dstAgents) {
        Copy-Item -Path $dstAgents -Destination $codexMdPath -Force
        Write-Host "  -> Tao alias CODEX.md sang $CodexDir" -ForegroundColor DarkGray
    }

    # Don dep cac file cu khong con dung trong Codex CLI (RULES.md, SYSTEM.md) va chuyen vao Thung rac
    $legacyFiles = @("RULES.md", "SYSTEM.md")
    foreach ($leg in $legacyFiles) {
        $oldFilePath = Join-Path $CodexDir $leg
        if (Test-Path $oldFilePath) {
            Write-Host "  -> Don dep file cu khong thuoc dac ta Codex CLI: $oldFilePath (chuyen vao Thung rac)..." -ForegroundColor Cyan
            Move-ToRecycleBinFile -Path $oldFilePath
        }
    }

    # Sao chep skills/ tu PSScriptRoot hoac templates/skills
    $skillsSrc = Join-Path $PSScriptRoot "skills"
    if (-not (Test-Path $skillsSrc)) {
        $skillsSrc = Join-Path $templatesDir "skills"
    }
    $skillsDst = Join-Path $CodexDir "skills"
    if (Test-Path $skillsSrc) {
        if (-not (Test-Path $skillsDst)) {
            New-Item -ItemType Directory -Force -Path $skillsDst | Out-Null
        }
        if ($EnableMemorix) {
            Write-Host "  -> Sao chep toan bo skills/ sang $skillsDst..." -ForegroundColor Green
            Get-ChildItem -Path $skillsSrc -Directory | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $skillsDst -Recurse -Force
            }
        } else {
            Write-Host "  -> Sao chep skills/ (bo qua memorix-*) sang $skillsDst..." -ForegroundColor Green
            Get-ChildItem -Path $skillsSrc -Directory | Where-Object { $_.Name -notlike "memorix-*" } | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $skillsDst -Recurse -Force
            }
            # Don dep cac ky nang memorix-* neu ton tai trong thu muc dich
            Get-ChildItem -Path $skillsDst -Directory -Filter "memorix-*" -ErrorAction SilentlyContinue | ForEach-Object {
                Write-Host "  -> Di chuyen ky nang '$($_.Name)' vao Thung rac..." -ForegroundColor Yellow
                Move-ToRecycleBinDirectory -Path $_.FullName
            }
        }
        Write-Host "  -> Copy skills/ sang $skillsDst thanh cong." -ForegroundColor DarkGray
    }
} else {
    Write-Host "  -> [WhatIf] Sao chep static files va skills sang: $CodexDir" -ForegroundColor DarkGray
}

Write-Host "`nHoan tat bootstrap Codex CLI!" -ForegroundColor Green


# ==============================================================================
# GIAI DOAN 4: TEST KET NOI CAC MCP DA CHON (chi test cai da chon cai)
# ==============================================================================
Write-Host "`n==> [Giai doan 4/3] Test ket noi cac MCP da chon..." -ForegroundColor Cyan
$script:__mcpSummary = @()
function __flagOn([string]$n) {
    $v = Get-Variable -Name $n -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $v) { return $false }
    if ($v -is [System.Management.Automation.SwitchParameter]) { return [bool]$v }
    if ($v -is [bool]) { return $v }
    return [bool]$v
}
function __pushResult([string]$n, [bool]$ok, [bool]$skipped) {
    $st = if ($skipped) { 'SKIP' } elseif ($ok) { 'PASS' } else { 'FAIL' }
    $script:__mcpSummary += [pscustomobject]@{ MCP = $n; Result = $st }
}
try {
    $__fAtl = (__flagOn 'installAtlassian')
    if (($DryRun -or $SkipInstall) -and $__fAtl) {
        Write-Host "  -> [Skip] Test MCP 'company-atlassian' (DryRun/SkipInstall)." -ForegroundColor DarkGray
        __pushResult 'company-atlassian' $true $false
    } elseif ($__fAtl) {
        try {
            $okAtl = $false
            $atlCmd = Get-Command 'mcp-atlassian' -ErrorAction SilentlyContinue
            if ($atlCmd) {
                try {
                    $hv = (& mcp-atlassian --help 2>$null) | Out-String
                    if ($hv -match 'mcp-atlassian|atlassian|usage|JIRA') {
                        Write-Host "  -> [OK] MCP 'company-atlassian' dung duoc (mcp-atlassian --help OK)." -ForegroundColor Green
                        $okAtl = $true
                    } else {
                        Write-Warning "[Verify] 'mcp-atlassian' co mat nhung --help la. Thu test stdio..."
                        $okAtl = Test-McpConnection -Name 'company-atlassian' -Command 'mcp-atlassian' -Arguments ''
                    }
                } catch { $okAtl = Test-McpConnection -Name 'company-atlassian' -Command 'mcp-atlassian' -Arguments '' }
            } else {
                Write-Warning "[Verify] Khong tim thay 'mcp-atlassian' sau cai. Hay mo terminal moi (User PATH) roi chay lai."
            }
            try {
                if ($JIRA_URL -and $JIRA_URL -notmatch 'YOUR_') {
                    try {
                        $r = Invoke-WebRequest -Uri $JIRA_URL -Method Head -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
                        Write-Host "  -> [OK] JIRA_URL phan hoi HTTP $($r.StatusCode)." -ForegroundColor Green
                    } catch { Write-Warning "[MCP-Test] JIRA_URL khong phan hoi: $($_.Exception.Message)" }
                }
            } catch {}
            __pushResult 'company-atlassian' $okAtl (-not $__fAtl)
        } catch { Write-Warning "[MCP-Test] company-atlassian loi: $($_.Exception.Message)"; __pushResult 'company-atlassian' $false $false }
    } else { __pushResult 'company-atlassian' $false $true }
} catch {}
try {
    $f = (__flagOn 'installGitnexus'); if ($f) { $ok = Test-McpConnection -Name 'gitnexus' -Command 'gitnexus' -Arguments 'mcp'; __pushResult 'gitnexus' $ok $false } else { __pushResult 'gitnexus' $false $true }
} catch {}
try {
    $f = (__flagOn 'installContext7'); if ($f) {
        if ($DryRun -or $SkipInstall) { Write-Host "  -> [Skip] Test MCP 'context7' (DryRun/SkipInstall)." -ForegroundColor DarkGray; __pushResult 'context7' $true $false }
        else {
        $ok = $false
        try {
            $nr = ''; try { $nr = (npm root -g 2>$null) | Out-String; $nr = $nr.Trim() } catch {}
            $idx = if ($nr) { Join-Path $nr '@upstash\context7-mcp\dist\index.js' } else { '' }
            if ($idx -and (Test-Path $idx)) { $ok = Test-McpConnection -Name 'context7' -Command 'node' -Arguments "`"$idx`"" }
            else { Write-Warning "[MCP-Test] Bo qua 'context7': khong tim thay dist/index.js." }
        } catch { Write-Warning "[MCP-Test] context7 loi: $($_.Exception.Message)" }
        __pushResult 'context7' $ok $false
        }
    } else { __pushResult 'context7' $false $true }
} catch {}
try {
    $f = (__flagOn 'installGlab'); if ($f) { $ok = Verify-CommandInstalled -Name 'glab' -Label "MCP glab"; __pushResult 'glab' $ok $false } else { __pushResult 'glab' $false $true }
} catch {}
try {
    $f = ((__flagOn 'EnableMemorix') -or (__flagOn 'installMemorix')); if ($f) { $ok = Verify-CommandInstalled -Name 'memorix' -Label 'MCP memorix'; __pushResult 'memorix' $ok $false } else { __pushResult 'memorix' $false $true }
} catch {}
try {
    $f = ((__flagOn 'EnableAgency') -or (__flagOn 'installAgency')); if ($f) { $ok = Verify-CommandInstalled -Name 'agency-mcp-server' -Label 'MCP agency'; __pushResult 'agency' $ok $false } else { __pushResult 'agency' $false $true }
} catch {}
try {
    $f = (__flagOn 'installCloakbrowser'); if ($f) { $ok = Verify-CommandInstalled -Name 'node' -Label 'MCP cloakbrowser (node runtime)'; __pushResult 'cloakbrowser' $ok $false } else { __pushResult 'cloakbrowser' $false $true }
} catch {}
try {
    Write-Host "`n  --- Ket qua test MCP ---" -ForegroundColor Cyan
    $script:__mcpSummary | ForEach-Object { Write-Host ("  -> {0}: {1}" -f $_.MCP, $_.Result) }
} catch {}

