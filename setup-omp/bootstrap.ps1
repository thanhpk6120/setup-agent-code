# bootstrap.ps1 - Bootstrap .omp environment on fresh machine
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipInstall,
    [switch]$Force,
    [switch]$OverwriteAll,
    [switch]$EnableMemorix,
    [switch]$DisableMemorix,
    [switch]$EnableAgency,
    [switch]$DisableAgency,
    [string]$AgencyPath = "C:\nvm4w\nodejs\agency-mcp-server.cmd",
    [string]$OmpDir = "$env:USERPROFILE\.omp\agent"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

# ==============================================================================
# Helper: Safe-Trash (Di chuyển an toàn vào Recycle Bin)
# ==============================================================================
function Safe-Trash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ($DryRun) {
        Write-Host "  -> [WhatIf] Safe-Trash: $Path" -ForegroundColor DarkGray
        return
    }
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
        Write-Host "  -> [Trash] Da di chuyen vao Recycle Bin: $Path" -ForegroundColor DarkGray
    } catch {
        Write-Warning "Khong the di chuyen vao Recycle Bin bang VisualBasic FileIO: $($_.Exception.Message)"
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
    if (-not [Environment]::UserInteractive -or $env:CI) {
        return $false
    }
    $choice = Read-Host "[?] Cai dat MCP '$Name'? [y/N]"
    if (-not [string]::IsNullOrWhiteSpace($choice) -and ($choice.Trim().ToLower() -eq 'y' -or $choice.Trim().ToLower() -eq 'yes')) {
        return $true
    }
    return $false
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
    if (-not [Environment]::UserInteractive -or $env:CI) {
        return $false
    }
    $choice = Read-Host "[?] Cai dat MCP 'agency' (multi-agent orchestration)? [y/N]"
    if (-not [string]::IsNullOrWhiteSpace($choice) -and ($choice.Trim().ToLower() -eq 'y' -or $choice.Trim().ToLower() -eq 'yes')) {
        return $true
    }
    return $false
}


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
        [string]$Default,
        [switch]$AllowEmpty
    )
    $val = [Environment]::GetEnvironmentVariable($EnvName, "Process")
    if (-not [string]::IsNullOrWhiteSpace($val)) { return $val }

    $hasDefault = $PSBoundParameters.ContainsKey('Default')
    while ($true) {
        $promptStr = $Prompt
        if ($hasDefault) { $promptStr = "$Prompt (Default: $Default)" }
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
        if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive -or $env:CI) {
            throw "Error: '$EnvName' is required but cannot prompt in non-interactive session."
        }
        Write-Host "Error: '$EnvName' is required. Please provide a value." -ForegroundColor Red
    }
}

function Load-Env {
    param([string]$EnvPath = (Join-Path $PSScriptRoot ".env"))
    if (Test-Path $EnvPath) {
        Write-Host "  -> Loading environment from $EnvPath..." -ForegroundColor Cyan
        Get-Content $EnvPath | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith("#")) {
                $idx = $line.IndexOf("=")
                if ($idx -gt 0) {
                    $key = $line.Substring(0, $idx).Trim()
                    $val = $line.Substring($idx + 1).Trim()
                    if (($val.StartsWith('"') -and $val.EndsWith('"')) -or ($val.StartsWith("'") -and $val.EndsWith("'"))) {
                        $val = $val.Substring(1, $val.Length - 2)
                    }
                    if (-not [string]::IsNullOrWhiteSpace($key) -and -not [string]::IsNullOrWhiteSpace($val)) {
                        [Environment]::SetEnvironmentVariable($key, $val, "Process")
                    }
                }
            }
        }
    }
}

# ==============================================================================
# GIAI ĐOẠN 1: HỎI THÔNG TIN VÀ CẤU HÌNH (PROMPTS & ENV GATHERING)
# ==============================================================================
Write-Host "==> [Giai doan 1/3] Thu thap thong tin cau hinh..." -ForegroundColor Cyan
Load-Env

# 1.1 Cau hinh Memorix flag
if ($EnableMemorix.IsPresent -and $DisableMemorix.IsPresent) {
    throw "Khong dung dong thoi -EnableMemorix va -DisableMemorix."
}
if (-not $PSBoundParameters.ContainsKey('EnableMemorix') -and -not $PSBoundParameters.ContainsKey('DisableMemorix')) {
    $EnableMemorix = Confirm-McpInstall -Name "memorix"
    if (-not $EnableMemorix) { Write-Host "Skipped MCP 'memorix' theo lua chon nguoi dung." -ForegroundColor Yellow }
} elseif ($DisableMemorix.IsPresent) {
    $EnableMemorix = $false
    Write-Host "Skipped MCP 'memorix' theo lua chon nguoi dung." -ForegroundColor Yellow
} else {
    $EnableMemorix = $EnableMemorix.IsPresent
}

$shouldSetupHook = $false
if ($EnableMemorix) {
    if ($Force -or $OverwriteAll) {
        Write-Host "  -> [Force] Tu dong cai dat Hook tich hop Memorix vao OMP." -ForegroundColor Cyan
        $shouldSetupHook = $true
    } elseif ($DryRun) {
        Write-Host "  -> [WhatIf] Bo qua prompt cai dat Hook Memorix." -ForegroundColor DarkGray
        $shouldSetupHook = $false
    } elseif (-not [Environment]::UserInteractive -or $env:CI -or $SkipInstall) {
        $shouldSetupHook = $false
    } else {
        $hookChoice = Read-Host "[?] Cai dat Hook tich hop Memorix vao OMP? [y/N]"
        if (-not [string]::IsNullOrWhiteSpace($hookChoice) -and ($hookChoice.Trim().ToLower() -eq 'y' -or $hookChoice.Trim().ToLower() -eq 'yes')) {
            $shouldSetupHook = $true
        } else {
            $shouldSetupHook = $false
            Write-Host "Bo qua cai dat Hook tich hop Memorix theo lua chon nguoi dung." -ForegroundColor Yellow
        }
    }
}

# 1.1b Cau hinh Agency MCP flag
if ($EnableAgency.IsPresent -and $DisableAgency.IsPresent) {
    throw "Khong dung dong thoi -EnableAgency va -DisableAgency."
}
if (-not $PSBoundParameters.ContainsKey('EnableAgency') -and -not $PSBoundParameters.ContainsKey('DisableAgency')) {
    $EnableAgency = Confirm-Agency
    if (-not $EnableAgency) { Write-Host "Skipped MCP 'agency' theo lua chon nguoi dung." -ForegroundColor Yellow }
} elseif ($DisableAgency.IsPresent) {
    $EnableAgency = $false
    Write-Host "Skipped MCP 'agency' theo lua chon nguoi dung." -ForegroundColor Yellow
} else {
    $EnableAgency = $EnableAgency.IsPresent
}

# 1.2 Xac nhan cai dat cac MCP servers
Write-Host "==> Xac nhan cai dat cac MCP Server..." -ForegroundColor Cyan
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

# 1.3 Thu thap bien moi truong bat buoc va tuy chon
$aiBaseUrl = Get-EnvOrPrompt -EnvName "AI_BASE_URL" -Prompt "AI Base URL" -Default "http://localhost:20128/v1"
$aiKey     = Get-EnvOrPrompt -EnvName "AI_API_KEY" -Prompt "AI API Key"

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
}

$isForce = $Force.IsPresent -or $OverwriteAll.IsPresent

# ==============================================================================
# GIAI ĐOẠN 2: KIỂM TRA MÔI TRƯỜNG & PREREQUISITES (PREREQUISITE CHECK)
# ==============================================================================
Write-Host "==> [Giai doan 2/3] Kiem tra moi truong va tien quyet..." -ForegroundColor Cyan

foreach ($tool in @("node", "npm", "git")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Missing '$tool' in PATH. Please install it first."
    }
}

# MCP tools (context7, gitnexus) require Node >= 22.18.0
$nodeVerRaw = (node -v 2>$null | Out-String).Trim()
try {
    $nodeVer = [version]($nodeVerRaw.TrimStart('v'))
} catch {
    throw "Khong the xac dinh version cua Node.js: '$nodeVerRaw'"
}
if ($nodeVer -lt [version]"22.18.0") {
    $toolsList = "gitnexus, context7"
    if ($EnableMemorix) { $toolsList = "memorix, gitnexus, context7" }
    throw "Yeu cau Node.js >= 22.18.0 (do $toolsList yeu cau Node.js moi). Phien ban hien tai: '$nodeVerRaw'. Vui long nang cap Node.js."
}
Write-Host "  -> Node.js version hop le: $nodeVerRaw (>= 22.18.0)" -ForegroundColor Green

# ==============================================================================
# GIAI ĐOẠN 3: TRIỂN KHAI & CÀI ĐẶT (DEPLOY & RUNTIME SETUP)
# ==============================================================================
Write-Host "==> [Giai doan 3/3] Trien khai cai dat va cau hinh OMP..." -ForegroundColor Cyan

# 3.1 Cài đặt Atlassian MCP qua uv tool
if ($installAtlassian) {
    if (-not $SkipInstall -and -not (Get-Command "uv" -ErrorAction SilentlyContinue)) {
        Write-Host "==> 'uv' not found. Installing uv..." -ForegroundColor Cyan
        if (-not $DryRun) {
            $installed = $false
            if (Get-Command "pip" -ErrorAction SilentlyContinue) {
                try {
                    pip install uv --quiet
                    $installed = $true
                } catch {}
            }
            if (-not $installed -and (Get-Command "winget" -ErrorAction SilentlyContinue)) {
                try {
                    winget install --id=astral-sh.uv -e --silent --accept-source-agreements --accept-package-agreements
                    $installed = $true
                } catch {}
            }
            if (-not $installed) {
                try {
                    irm https://astral.sh/uv/install.ps1 | iex
                    $env:Path = "$env:USERPROFILE\.local\bin;$env:USERPROFILE\.cargo\bin;$env:Path"
                    Ensure-PathPriority -Dirs @("$env:USERPROFILE\.local\bin", "$env:USERPROFILE\.cargo\bin")
                } catch {
                    Write-Warning "Could not install uv automatically. Please install it manually: https://docs.astral.sh/uv/"
                }
            }
        }
    }
    if (-not $SkipInstall) {
        # Fix atlassian: nap lai PATH phien truoc khi dung uv/mcp-atlassian (winget/pip cai xong session chua co PATH)
        Ensure-PathPriority -Dirs @("$env:USERPROFILE\.local\bin", "$env:USERPROFILE\.cargo\bin", (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"), (Join-Path $env:APPDATA "Python\Python313\Scripts"), (Join-Path $env:LOCALAPPDATA "Programs\Python\Launcher"))
        try { uv tool update-shell 2>$null } catch {}
        Write-Host "==> Installing/updating mcp-atlassian globally via uv tool..." -ForegroundColor Cyan
        if (-not $DryRun) {
            $mcpAtlCmd = Get-Command "mcp-atlassian" -ErrorAction SilentlyContinue
            $isInstalled = $false
            if ($mcpAtlCmd) {
                try {
                    $verOut = (& mcp-atlassian --version 2>$null) | Out-String
                    if ($verOut -match "0\.23\.1") {
                        Write-Host "  -> mcp-atlassian 0.23.1 da san sang. Bo qua cai lai." -ForegroundColor Green
                        $isInstalled = $true
                    }
                } catch {}
            }
            if (-not $isInstalled) {
                if (Get-Command "uv" -ErrorAction SilentlyContinue) {
                    try {
                        uv tool install mcp-atlassian==0.23.1 --upgrade
                        Ensure-PathPriority -Dirs @("$env:USERPROFILE\.local\bin")
                        Verify-CommandInstalled -Name "mcp-atlassian" -Label "MCP company-atlassian" | Out-Null
                    } catch {
                        Write-Warning "Khong the cap nhat mcp-atlassian: $($_.Exception.Message)"
                    }
                } else {
                    Write-Warning "'uv' is not available. Please install 'mcp-atlassian' manually: uv tool install mcp-atlassian==0.23.1"
                }
            }
        }
    }
}

# 3.2 Cài đặt gitnexus
$absGn = ""
$gitnexusArgsJson = '"/c", "", "mcp"'
if ($installGitnexus) {
    if (-not $SkipInstall) {
        Write-Host "==> Installing gitnexus globally..." -ForegroundColor Cyan
        if (-not $DryRun) {
            npm install -g gitnexus --silent
            Verify-CommandInstalled -Name "gitnexus" -Label "MCP gitnexus" | Out-Null
        }
    }

    $gn = Get-Command "gitnexus.cmd" -ErrorAction SilentlyContinue
    if (-not $gn) {
        $gn = Get-Command "gitnexus" -ErrorAction SilentlyContinue
    }
    $gnPath = if ($gn -and $gn.Source) { $gn.Source } else { "" }
    if ($gnPath -and $gnPath.EndsWith(".ps1", [System.StringComparison]::OrdinalIgnoreCase)) {
        $cmdCandidate = [System.IO.Path]::ChangeExtension($gnPath, ".cmd")
        if (Test-Path $cmdCandidate) {
            $gnPath = $cmdCandidate
        }
    }
    if ($gnPath) {
        $absGn = $gnPath.Replace('\', '\\')
        $gitnexusArgsJson = '"/c", "' + $absGn + '", "mcp"'
    } else {
        throw "Loi: Khong tim thay gitnexus bang Get-Command. Dung cai dat."
    }
}

# 3.3 Cài đặt context7
$context7Command = '"node"'
$absCtx2 = ""
$context7ArgsJson = '""'
if ($installContext7) {
    if (-not $SkipInstall) {
        Write-Host "==> Installing context7 globally..." -ForegroundColor Cyan
        if (-not $DryRun) {
            npm install -g @upstash/context7-mcp --silent
        }
    }

    $npmRoot2 = ""
    try {
        $npmRoot2 = (npm root -g 2>$null) | Out-String
        $npmRoot2 = $npmRoot2.Trim()
    } catch {}

    if ($npmRoot2) {
        $ctxP2 = Join-Path $npmRoot2 "@upstash\context7-mcp\dist\index.js"
        if (Test-Path $ctxP2) {
            $absCtx2 = ($ctxP2).Replace('\', '\\')
            $context7ArgsJson = '"' + $absCtx2 + '"'
        } else {
            throw "Loi: Khong tim thay file dist\index.js cua context7. Dung cai dat."
        }
    } else {
        throw "Loi: Khong tim thay thu muc npm root -g de lay duong dan context7. Dung cai dat."
    }
}

# 3.4 Cài đặt glab
if ($installGlab) {
    if (-not $SkipInstall -and -not (Get-Command "glab" -ErrorAction SilentlyContinue)) {
        Write-Host "==> Installing glab (GitLab CLI) globally..." -ForegroundColor Cyan
        if (-not $DryRun) {
            if (Get-Command "winget" -ErrorAction SilentlyContinue) {
                try {
                    winget install -e --id GLab.GLab --silent --accept-source-agreements --accept-package-agreements | Out-Null
                    $glabProg = "$env:LOCALAPPDATA\Programs\glab"
                    if (Test-Path $glabProg) {
                        $env:Path = "$glabProg;$env:Path"
                        Ensure-PathPriority -Dirs @($glabProg)
                        Verify-CommandInstalled -Name "glab" -Label "MCP glab" | Out-Null
                    }
                } catch {
                    Write-Warning "Failed to install glab via winget: $($_.Exception.Message)"
                }
            } else {
                Write-Warning "'winget' is not available. Please install glab manually."
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($gitlabToken) -and -not $DryRun) {
        Write-Host "==> Configuring GitLab authentication for host '$gitlabHost'..." -ForegroundColor Cyan
        $proto = "https"
        if ($gitlabHost -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' -or $gitlabHost -match ':80') { $proto = "http" }
        $glabCmd = "glab"
        if (Get-Command "glab" -ErrorAction SilentlyContinue) { $glabCmd = "glab" } elseif (Test-Path "$env:LOCALAPPDATA\Programs\glab\glab.exe") { $glabCmd = "$env:LOCALAPPDATA\Programs\glab\glab.exe" }
        try {
            & $glabCmd config set api_protocol $proto -g --host $gitlabHost 2>$null
            $tokenSec = $gitlabToken.Trim()
            & $glabCmd auth login --hostname $gitlabHost --token $tokenSec 2>$null
            Write-Host "  -> Logged in to GitLab ($gitlabHost) successfully." -ForegroundColor Green
        } catch {
            Write-Warning "Could not configure glab auth automatically: $($_.Exception.Message)"
        }
    }
}

# 3.5 Cài đặt Memorix nếu chọn
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
                        Write-Host "Memorix da o phien ban moi nhat ($installedVer), bo qua cai dat." -ForegroundColor Green
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
        Write-Host "==> Configuring memorix hook for omp..." -ForegroundColor Cyan
        $npmPrefix = ""
        try { $npmPrefix = (npm prefix -g 2>$null | Out-String).Trim() } catch {}
        if ($npmPrefix -and (Test-Path $npmPrefix) -and ($env:Path -notlike "*$npmPrefix*")) {
            $env:Path = "$npmPrefix;$env:Path"
        }
        try {
            memorix setup --agent omp --global
        } catch {
            Write-Warning "Khong the chay hook 'memorix setup --agent omp --global': $($_.Exception.Message)"
        }
    } else {
        if (-not $DryRun) {
            Write-Host "==> Bo qua cau hinh hook memorix cho omp." -ForegroundColor DarkGray
        }
    }
}

# 3.6 Cấu hình CloakBrowser
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
    if (-not (Test-Path $TargetDir)) {
        if (-not $DryRun) { New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null } else { Write-Host "  -> [WhatIf] Tao thu muc: $TargetDir" -ForegroundColor DarkGray }
    }

    $mainScript = Join-Path $TargetDir "mcp-server-full.mjs"
    $pkgJson = Join-Path $TargetDir "package.json"
    if ((Test-Path $mainScript) -and (Test-Path $pkgJson)) {
        Write-Host "  -> CloakBrowser da ton tai day du file ma nguon. Giu nguyen du lieu cu." -ForegroundColor Green
    } else {
        Write-Host "  -> Copy ma nguon CloakBrowser sang $TargetDir..." -ForegroundColor Green
        if (-not $DryRun -and (Test-Path $SourceDir)) {
            Copy-Item -Path "$SourceDir\*" -Destination $TargetDir -Recurse -Force
        } else {
            Write-Host "  -> [WhatIf] Sao chep CloakBrowser sang: $TargetDir" -ForegroundColor DarkGray
        }
    }

    $nodeModules = Join-Path $TargetDir "node_modules"
    if (-not $SkipInstall -and -not (Test-Path $nodeModules)) {
        Write-Host "  -> Dang chay 'npm install' cho CloakBrowser..." -ForegroundColor Cyan
        if (-not $DryRun) {
            Push-Location $TargetDir
            try { npm install --omit=dev --silent } catch { Write-Warning "npm install cho CloakBrowser gap loi: $($_.Exception.Message)" } finally { Pop-Location }
        }
    }
    return $mainScript
}

$escapedCloakScript = ""
if ($installCloakbrowser) {
    $cbSourceDir = Join-Path $PSScriptRoot "mcp-servers\cloakbrowser"
    $cbTargetDir = Get-CloakBrowserInstallDir
    $cloakScriptPath = Setup-CloakBrowser -TargetDir $cbTargetDir -SourceDir $cbSourceDir -DryRun:$DryRun -SkipInstall:$SkipInstall
    $escapedCloakScript = ($cloakScriptPath).Replace('\', '\\')
}

# 3.7 Cài đặt Trash Guard
function Setup-TrashGuard {
    param(
        [string]$OmpDir = "$env:USERPROFILE\.omp\agent",
        [switch]$DryRun,
        [switch]$SkipInstall
    )
    Write-Host "==> Cai dat Trash Guard (bao ve chan xoa cung cho OMP)..." -ForegroundColor Cyan

    $ompTargetDirs = @(
        (Join-Path $OmpDir "extensions"),
        (Join-Path "$env:USERPROFILE\.omp" "extensions")
    ) | Select-Object -Unique

    $srcExt = Join-Path $PSScriptRoot "extensions\no-hard-delete.ts"
    if (Test-Path $srcExt) {
        foreach ($extDir in $ompTargetDirs) {
            if (-not (Test-Path $extDir)) {
                if (-not $DryRun) { New-Item -ItemType Directory -Path $extDir -Force | Out-Null } else { Write-Host "  -> [WhatIf] Tao thu muc: $extDir" -ForegroundColor DarkGray }
            }
            $targetExt = Join-Path $extDir "no-hard-delete.ts"
            Write-Host "  -> Cai dat OMP extension sang $targetExt..." -ForegroundColor Green
            if (-not $DryRun) {
                Copy-Item -Path $srcExt -Destination $targetExt -Force
            } else {
                Write-Host "  -> [WhatIf] Sao chep extension sang: $targetExt" -ForegroundColor DarkGray
            }
        }
    }
    Write-Host "  -> Hoan tat kich hoat Trash Guard cho OMP." -ForegroundColor Green
}

# 3.7b Cài đặt agency-mcp-server nếu chọn
if ($EnableAgency) {
    $existingAgency = $null
    if (Test-Path -LiteralPath $AgencyPath) {
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
}

# 3.8 Chuẩn bị thư mục đích OMP
Write-Host "==> Ensuring directory $OmpDir exists..." -ForegroundColor Cyan
if (-not $DryRun) {
    New-Item -ItemType Directory -Force -Path $OmpDir | Out-Null
} else {
    Write-Host "  -> [WhatIf] Tao thu muc: $OmpDir" -ForegroundColor DarkGray
}

$templatesDir = Join-Path $PSScriptRoot "templates"

# Đọc config.yml từ templates/
$configTemplateContent = Get-Content -Path (Join-Path $templatesDir "config.yml") -Raw -Encoding UTF8
$detectedBash = "C:\Program Files\Git\bin\bash.exe"
$gitCmd = Get-Command "git" -ErrorAction SilentlyContinue
if ($gitCmd) {
    $gitDir = Split-Path (Split-Path $gitCmd.Source -Parent) -Parent
    $candidate = Join-Path $gitDir "bin\bash.exe"
    if (Test-Path $candidate) {
        $detectedBash = $candidate
    }
}
$configContent = $configTemplateContent
if ($configContent -match '(?m)^shellPath:') {
    $configContent = [regex]::Replace($configContent, '(?m)^shellPath:\s*.*$', "shellPath: $detectedBash")
}

# Đọc models.yml từ templates/
$modelsTemplateContent = Get-Content -Path (Join-Path $templatesDir "models.yml") -Raw -Encoding UTF8
$modelsContent = $modelsTemplateContent.Replace("__AI_BASE_URL__", $aiBaseUrl).Replace("__AI_API_KEY__", $aiKey)

# Đọc mcp.json từ templates/
$mcpTemplateContent = Get-Content -Path (Join-Path $templatesDir "mcp.json") -Raw -Encoding UTF8
$mcpJson = $mcpTemplateContent.Replace("__JIRA_URL__", $jiraUrl).Replace("__JIRA_PERSONAL_TOKEN__", $jiraToken).Replace("__CONFLUENCE_URL__", $confUrl).Replace("__CONFLUENCE_PERSONAL_TOKEN__", $confToken).Replace("__CLOAKBROWSER_SCRIPT__", $escapedCloakScript)

if ($mcpJson.Contains("__AGENCY_PATH__")) {
    $agencyCmd = $AgencyPath
    if ($EnableAgency) {
        $resolvedAgency = $null
        if (Test-Path -LiteralPath $AgencyPath) {
            $resolvedAgency = $AgencyPath
        } else {
            $foundAgency = Get-Command "agency-mcp-server.cmd" -ErrorAction SilentlyContinue
            if (-not $foundAgency) { $foundAgency = Get-Command "agency-mcp-server" -ErrorAction SilentlyContinue }
            if ($foundAgency -and $foundAgency.Source) {
                $resolvedAgency = $foundAgency.Source
            } else {
                try {
                    $npmPrefix = (npm prefix -g 2>$null | Out-String).Trim()
                    if ($npmPrefix -and (Test-Path $npmPrefix)) {
                        $cand1 = Join-Path $npmPrefix "agency-mcp-server.cmd"
                        $cand2 = Join-Path $npmPrefix "agency-mcp-server"
                        if (Test-Path -LiteralPath $cand1) { $resolvedAgency = $cand1 }
                        elseif (Test-Path -LiteralPath $cand2) { $resolvedAgency = $cand2 }
                    }
                } catch {}
            }
        }

        if ($resolvedAgency) {
            $agencyCmd = $resolvedAgency
        } else {
            Write-Warning "Khong tim thay 'agency-mcp-server'; su dung duong dan mac dinh: $AgencyPath"
        }
    }
    $escapedAgency = $agencyCmd.Replace('\', '\\')
    $mcpJson = $mcpJson.Replace("__AGENCY_PATH__", $escapedAgency)
}
    if ($mcpJson.Contains("__GITNEXUS_PATH__")) {
    $mcpJson = $mcpJson.Replace("__GITNEXUS_PATH__", $absGn)
}
if ($mcpJson.Contains("__GITNEXUS_ARGS__")) {
    $mcpJson = $mcpJson.Replace("__GITNEXUS_ARGS__", $gitnexusArgsJson)
}
if ($mcpJson.Contains("__CONTEXT7_PATH__")) {
    $mcpJson = $mcpJson.Replace("__CONTEXT7_PATH__", $absCtx2)
}
if ($mcpJson.Contains("__CONTEXT7_CMD__")) {
    $mcpJson = $mcpJson.Replace("__CONTEXT7_CMD__", $context7Command)
}
if ($mcpJson.Contains("__CONTEXT7_ARGS__")) {
    $mcpJson = $mcpJson.Replace("__CONTEXT7_ARGS__", $context7ArgsJson)
}
if ($ctxKey) {
    $mcpJson = $mcpJson.Replace("__CONTEXT7_API_KEY__", $ctxKey)
} else {
    # Chế độ anonymous: gỡ bỏ block env để không truyền placeholder trống
    $mcpJson = $mcpJson -replace ',\s*"env":\s*\{\s*"CONTEXT7_API_KEY":\s*"__CONTEXT7_API_KEY__"\s*\}', ''
}

try {
    $mcpObj = $mcpJson | ConvertFrom-Json
    if ($mcpObj -and $mcpObj.mcpServers) {
        if (-not $installAtlassian -and $mcpObj.mcpServers.PSObject.Properties['company-atlassian']) {
            $mcpObj.mcpServers.PSObject.Properties.Remove('company-atlassian')
        }
        if (-not $installGitnexus -and $mcpObj.mcpServers.PSObject.Properties['gitnexus']) {
            $mcpObj.mcpServers.PSObject.Properties.Remove('gitnexus')
        }
        if (-not $installContext7 -and $mcpObj.mcpServers.PSObject.Properties['context7']) {
            $mcpObj.mcpServers.PSObject.Properties.Remove('context7')
        }
        if (-not $installGlab -and $mcpObj.mcpServers.PSObject.Properties['glab']) {
            $mcpObj.mcpServers.PSObject.Properties.Remove('glab')
        }
        if (-not $installCloakbrowser -and $mcpObj.mcpServers.PSObject.Properties['cloakbrowser']) {
            $mcpObj.mcpServers.PSObject.Properties.Remove('cloakbrowser')
        }
        if ($EnableMemorix) {
            if (-not $mcpObj.mcpServers.PSObject.Properties['memorix']) {
                $mcpObj.mcpServers | Add-Member -MemberType NoteProperty -Name "memorix" -Value ([PSCustomObject]@{
                    command = "memorix"
                    args    = @("serve", "--mode", "lite")
                })
            }
        } else {
            if ($mcpObj.mcpServers.PSObject.Properties['memorix']) {
                $mcpObj.mcpServers.PSObject.Properties.Remove('memorix')
            }
        }
        if ($EnableAgency) {
            if (-not $mcpObj.mcpServers.PSObject.Properties['agency']) {
                $mcpObj.mcpServers | Add-Member -MemberType NoteProperty -Name "agency" -Value ([PSCustomObject]@{
                    command = $agencyCmd
                    args    = @()
                })
            }
        } else {
            if ($mcpObj.mcpServers.PSObject.Properties['agency']) {
                $mcpObj.mcpServers.PSObject.Properties.Remove('agency')
            }
        }
        $mcpJson = $mcpObj | ConvertTo-Json -Depth 10
    }
} catch {
    Write-Warning "Khong the cap nhat cau hinh mcp.json: $($_.Exception.Message)"
}

# 3.9 Ghi cấu hình với cơ chế sao lưu .bak, Overwrite, Merge, Skip
$files = [ordered]@{
    "mcp.json"   = $mcpJson
    "models.yml" = $modelsContent
    "config.yml" = $configContent
}

foreach ($entry in $files.GetEnumerator()) {
    $targetFileName = $entry.Key
    $templateContent = $entry.Value
    $targetPath = Join-Path $OmpDir $targetFileName

    if (Test-Path $targetPath) {
        $bakPath = Get-BackupPath -Path $targetPath
        if ($targetFileName -eq "mcp.json") {
            if ($isForce) {
                Write-Host "  -> File cau hinh '$targetFileName' da ton tai. [-Force / -OverwriteAll] Tu dong sao luu va ghi de." -ForegroundColor Yellow
                if (-not $DryRun) {
                    Copy-Item -Path $targetPath -Destination $bakPath -Force
                    Write-Host "     Da sao luu sang $bakPath" -ForegroundColor DarkGray
                    Set-Content -Path $targetPath -Value $templateContent -Encoding UTF8
                } else {
                    Write-Host "  -> [WhatIf] Sao luu: $bakPath" -ForegroundColor DarkGray
                    Write-Host "  -> [WhatIf] Ghi file: $targetPath" -ForegroundColor DarkGray
                }
            } else {
                $choice = Read-Host "[?] File cau hinh 'mcp.json' da ton tai. Ban co muon [O]verwrite (ghi de), [M]erge (hop nhat server cu va moi), hay [S]kip (bo qua)? [O/M/s]"
                $choice = if ($choice) { $choice.Trim() } else { "" }
                if ($choice -match '^[mM]$') {
                    Write-Host "  -> Dang hop nhat $targetFileName (sao luu sang $bakPath)..." -ForegroundColor Cyan
                    if (-not $DryRun) {
                        Copy-Item -Path $targetPath -Destination $bakPath -Force
                        Write-Host "     Da sao luu sang $bakPath" -ForegroundColor DarkGray
                        try {
                            $existingJson = Get-Content -Path $targetPath -Raw -Encoding UTF8 | ConvertFrom-Json
                            $newJson = $templateContent | ConvertFrom-Json
                            if (-not $existingJson.PSObject.Properties['mcpServers']) {
                                $existingJson | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value ([PSCustomObject]@{})
                            }
                            if ($newJson -and $newJson.mcpServers) {
                                foreach ($prop in $newJson.mcpServers.PSObject.Properties) {
                                    if (-not $existingJson.mcpServers.PSObject.Properties[$prop.Name]) {
                                        $existingJson.mcpServers | Add-Member -MemberType NoteProperty -Name $prop.Name -Value $prop.Value
                                    }
                                }
                            }
                            $mergedJsonStr = $existingJson | ConvertTo-Json -Depth 10
                            Set-Content -Path $targetPath -Value $mergedJsonStr -Encoding UTF8
                            Write-Host "  -> Da hop nhat $targetFileName thanh cong." -ForegroundColor Green
                        } catch {
                            Write-Warning "Khong the hop nhat JSON: $($_.Exception.Message). Tien hanh ghi de bang template."
                            Set-Content -Path $targetPath -Value $templateContent -Encoding UTF8
                        }
                    }
                } elseif ($choice -match '^[oO]$') {
                    Write-Host "  -> Ghi de file $targetFileName (da sao luu sang $bakPath)" -ForegroundColor Green
                    if (-not $DryRun) {
                        Copy-Item -Path $targetPath -Destination $bakPath -Force
                        Write-Host "     Da sao luu sang $bakPath" -ForegroundColor DarkGray
                        Set-Content -Path $targetPath -Value $templateContent -Encoding UTF8
                    } else {
                    Write-Host "  -> [WhatIf] Sao luu: $bakPath" -ForegroundColor DarkGray
                    Write-Host "  -> [WhatIf] Ghi file: $targetPath" -ForegroundColor DarkGray
                }
                } else {
                    Write-Host "  -> Bo qua $targetFileName (giu nguyen file hien tai)." -ForegroundColor Yellow
                }
            }
        } else {
            # File YAML (config.yml, models.yml)
            if ($isForce) {
                Write-Host "  -> File cau hinh '$targetFileName' da ton tai. [-Force / -OverwriteAll] Tu dong sao luu va ghi de." -ForegroundColor Yellow
                if (-not $DryRun) {
                    Copy-Item -Path $targetPath -Destination $bakPath -Force
                    Write-Host "     Da sao luu sang $bakPath" -ForegroundColor DarkGray
                    Set-Content -Path $targetPath -Value $templateContent -Encoding UTF8
                } else {
                    Write-Host "  -> [WhatIf] Sao luu: $bakPath" -ForegroundColor DarkGray
                    Write-Host "  -> [WhatIf] Ghi file: $targetPath" -ForegroundColor DarkGray
                }
            } else {
                $choice = Read-Host "[?] File cau hinh '$targetFileName' da ton tai. Ban co muon [O]verwrite (ghi de) hay [S]kip (bo qua)? [O/s]"
                $choice = if ($choice) { $choice.Trim() } else { "" }
                if ($choice -match '^[oO]$') {
                    Write-Host "  -> Ghi de file $targetFileName (da sao luu sang $bakPath)" -ForegroundColor Green
                    if (-not $DryRun) {
                        Copy-Item -Path $targetPath -Destination $bakPath -Force
                        Write-Host "     Da sao luu sang $bakPath" -ForegroundColor DarkGray
                        Set-Content -Path $targetPath -Value $templateContent -Encoding UTF8
                    } else {
                    Write-Host "  -> [WhatIf] Sao luu: $bakPath" -ForegroundColor DarkGray
                    Write-Host "  -> [WhatIf] Ghi file: $targetPath" -ForegroundColor DarkGray
                }
                } else {
                    Write-Host "  -> Bo qua $targetFileName (giu nguyen file hien tai)." -ForegroundColor Yellow
                }
            }
        }
    } else {
        Write-Host "  -> Creating $targetPath" -ForegroundColor Green
        if (-not $DryRun) {
            Set-Content -Path $targetPath -Value $templateContent -Encoding UTF8
        } else {
            Write-Host "  -> [WhatIf] Ghi file: $targetPath" -ForegroundColor DarkGray
        }
    }
}

# 3.10 Copy static files (AGENTS.md, RULES.md, SYSTEM.md) và skills/
Write-Host "==> Copying static files and skills..." -ForegroundColor Cyan
foreach ($mdFile in @("AGENTS.md", "RULES.md", "SYSTEM.md")) {
    $srcPath = Join-Path $templatesDir $mdFile
    if (-not (Test-Path $srcPath)) {
        $srcPath = Join-Path $PSScriptRoot $mdFile
    }
    $targetPath = Join-Path $OmpDir $mdFile
    if (-not (Test-Path $srcPath)) { continue }

    if (Test-Path $targetPath) {
        $bak = Get-BackupPath -Path $targetPath
        if ($Force -or $OverwriteAll) {
            Write-Host "  -> File '$targetPath' da ton tai. [-Force / -OverwriteAll] Tu dong sao luu va ghi de." -ForegroundColor Yellow
            if (-not $DryRun) {
                Copy-Item -Path $targetPath -Destination $bak -Force
                Write-Host "     Da sao luu sang $bak" -ForegroundColor DarkGray
                Copy-Item -Path $srcPath -Destination $targetPath -Force
            } else {
                Write-Host "  -> [WhatIf] Sao luu: $bak" -ForegroundColor DarkGray
                Write-Host "  -> [WhatIf] Sao chep den: $targetPath" -ForegroundColor DarkGray
            }
        } else {
            $choice = Read-Host "[?] File '$targetPath' da ton tai. Ban co muon [O]verwrite (ghi de) hay [S]kip (bo qua)? [O/s]"
            if (-not [string]::IsNullOrWhiteSpace($choice) -and $choice.Trim().ToLower() -eq 's') {
                Write-Host "  -> Bo qua file $targetPath." -ForegroundColor DarkGray
            } else {
            if (-not $DryRun) {
                Copy-Item -Path $targetPath -Destination $bak -Force
                Write-Host "     Da sao luu sang $bak" -ForegroundColor DarkGray
                Copy-Item -Path $srcPath -Destination $targetPath -Force
                Write-Host "  -> Ghi de file $targetPath thanh cong." -ForegroundColor Green
            } else {
                Write-Host "  -> [WhatIf] Sao luu: $bak" -ForegroundColor DarkGray
                Write-Host "  -> [WhatIf] Sao chep den: $targetPath" -ForegroundColor DarkGray
            }
            }
        }
    } else {
        Write-Host "  -> Tao moi file $targetPath thanh cong." -ForegroundColor Green
        if (-not $DryRun) {
            Copy-Item -Path $srcPath -Destination $targetPath -Force
        } else {
            Write-Host "  -> [WhatIf] Sao chep den: $targetPath" -ForegroundColor DarkGray
        }
    }
}

$targetAgentsPath = Join-Path $OmpDir "AGENTS.md"
if ($EnableMemorix) {
    $memSectionPath = Join-Path $templatesDir "memorix-agents-section.md"
    if (Test-Path $memSectionPath) {
        Write-Host "  -> Tich hop huong dan Memorix vao $targetAgentsPath..." -ForegroundColor Green
        if (-not $DryRun -and (Test-Path $targetAgentsPath)) {
            $currentAgents = Get-Content -Path $targetAgentsPath -Raw -Encoding UTF8
            $memHeading = "## Memorix: Memory and Safety Gate"
            if ($currentAgents -notmatch [regex]::Escape($memHeading) -and $currentAgents -notmatch "(?m)^## Memorix") {
                $memSectionContent = Get-Content -Path $memSectionPath -Raw -Encoding UTF8
                Add-Content -Path $targetAgentsPath -Value "`r`n$memSectionContent" -Encoding UTF8
            }
        } else {
            Write-Host "  -> [WhatIf] Ghi them vao: $targetAgentsPath" -ForegroundColor DarkGray
        }
    }
} else {
    if (-not $DryRun -and (Test-Path $targetAgentsPath)) {
        $currentAgents = Get-Content -Path $targetAgentsPath -Raw -Encoding UTF8
        $memHeading = "## Memorix: Memory and Safety Gate"
        if ($currentAgents -match [regex]::Escape($memHeading) -or $currentAgents -match "(?m)^## Memorix") {
            Write-Host "  -> Go bo huong dan Memorix khoi $targetAgentsPath..." -ForegroundColor Yellow
            $cleaned = [regex]::Replace($currentAgents, '(?ms)\r?\n## Memorix: Memory and Safety Gate.*?(?=(?:\r?\n<!-- agency-agents-section -->|\r?\n## Using Agency Agents MCP|\z))', '')
            [System.IO.File]::WriteAllText($targetAgentsPath, $cleaned.TrimEnd() + "`r`n", [System.Text.UTF8Encoding]::new($false))
        }
    }
}

$agencySectionPath = Join-Path $templatesDir "agency-agents-section.md"
$agencyMarkerStart = "<!-- agency-agents-section -->"
$agencyMarkerEnd = "<!-- /agency-agents-section -->"
if ($EnableAgency) {
    if (Test-Path $agencySectionPath) {
        Write-Host "  -> Tich hop huong dan Agency vao $targetAgentsPath..." -ForegroundColor Green
        if (-not $DryRun -and (Test-Path $targetAgentsPath)) {
            $agentsContent = Get-Content -Path $targetAgentsPath -Raw -Encoding UTF8
            if (-not $agentsContent.Contains($agencyMarkerStart)) {
                $agencySectionContent = Get-Content -Path $agencySectionPath -Raw -Encoding UTF8
                Add-Content -Path $targetAgentsPath -Value "`r`n$agencySectionContent" -Encoding UTF8
            }
        } else {
            Write-Host "  -> [WhatIf] Ghi them vao: $targetAgentsPath" -ForegroundColor DarkGray
        }
    }
} else {
    if (-not $DryRun -and (Test-Path $targetAgentsPath)) {
        $agentsContent = Get-Content -Path $targetAgentsPath -Raw -Encoding UTF8
        if ($agentsContent.Contains($agencyMarkerStart)) {
            $agencyPattern = '(?s)\r?\n?' + [regex]::Escape($agencyMarkerStart) + '.*?' + [regex]::Escape($agencyMarkerEnd)
            $agentsContent = [regex]::Replace($agentsContent, $agencyPattern, '')
            Set-Content -Path $targetAgentsPath -Value $agentsContent -Encoding UTF8
            Write-Host "  -> Da go bo huong dan Agency khoi $targetAgentsPath." -ForegroundColor Green
        }
    }
}

$srcSkills = Join-Path $templatesDir "skills"
if (-not (Test-Path $srcSkills)) {
    $srcSkills = Join-Path $PSScriptRoot "skills"
}
$targetSkills = Join-Path $OmpDir "skills"
if (Test-Path $srcSkills) {
    if (-not (Test-Path $targetSkills)) {
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force -Path $targetSkills | Out-Null
        } else {
            Write-Host "  -> [WhatIf] Tao thu muc: $targetSkills" -ForegroundColor DarkGray
        }
    }

    if ($EnableMemorix) {
        Write-Host "  -> Copying toan bo skills/ (bao gom memorix) sang $targetSkills (overwrite)" -ForegroundColor Green
        if (-not $DryRun) {
            Get-ChildItem -Path $srcSkills -Directory | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $targetSkills -Recurse -Force
            }
        } else {
            Write-Host "  -> [WhatIf] Sao chep skills den: $targetSkills" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  -> Copying skills/ (bo qua memorix-*) sang $targetSkills (overwrite)" -ForegroundColor Green
        if (-not $DryRun) {
            Get-ChildItem -Path $srcSkills -Directory | Where-Object { $_.Name -notlike "memorix-*" } | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $targetSkills -Recurse -Force
            }
        } else {
            Write-Host "  -> [WhatIf] Sao chep skills den: $targetSkills" -ForegroundColor DarkGray
        }

        # Dọn dẹp các kỹ năng memorix-* bằng Safe-Trash (Recycle Bin)
        if (Test-Path $targetSkills) {
            $existingMemorixSkills = Get-ChildItem -Path $targetSkills -Directory -Filter "memorix-*" -ErrorAction SilentlyContinue
            foreach ($memSkill in $existingMemorixSkills) {
                Write-Host "  -> Di chuyen ky nang '$($memSkill.Name)' vao Thung rac (Recycle Bin)..." -ForegroundColor Yellow
                if (-not $DryRun) {
                    Safe-Trash -Path $memSkill.FullName
                }
            }
        }
    }
}

# 3.11 Kích hoạt Trash Guard Protection cho OMP
Setup-TrashGuard -OmpDir $OmpDir -DryRun:$DryRun -SkipInstall:$SkipInstall

Write-Host "`nBootstrap finished. Set required environment variables if using Jira or Router:" -ForegroundColor Green
Write-Host '  $env:AI_API_KEY = "..."'
Write-Host '  $env:JIRA_PERSONAL_TOKEN = "..."'
Write-Host '  $env:CONFLUENCE_PERSONAL_TOKEN = "..."'
Write-Host '  $env:CONTEXT7_API_KEY = "..." (optional, higher rate limits)'
Write-Host '  gitnexus index empty? run: gitnexus analyze'


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

