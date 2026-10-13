# bootstrap.ps1 - Bootstrap Claude Code environment on fresh machine
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipInstall,
    [switch]$Force,
    [switch]$OverwriteAll,
    [switch]$EnableMemorix,
    [switch]$DisableMemorix,
    [string]$ClaudeDir = "$env:USERPROFILE\.claude",
    [string]$ClaudeJson = "$env:USERPROFILE\.claude.json"
)

$ErrorActionPreference = "Stop"

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

# Doc cau hinh tu .env neu ton tai
$envMap = @{}
$dotEnvPath = Join-Path $PSScriptRoot ".env"
if (Test-Path $dotEnvPath) {
    Write-Host "==> Doc cau hinh tu file .env ($dotEnvPath)..." -ForegroundColor Cyan
    Get-Content $dotEnvPath -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) {
            $parts = $line -split "=", 2
            if ($parts.Count -eq 2) {
                $k = $parts[0].Trim()
                $v = $parts[1].Trim().Trim('"').Trim("'")
                $envMap[$k] = $v
            }
        }
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

Write-Host "==> Checking runtime dependencies..." -ForegroundColor Cyan
foreach ($tool in @("node", "npm", "git")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Missing '$tool' in PATH. Please install it first."
    }
}

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

if ($installAtlassian) {
    # Cai dat uv
    if (-not $SkipInstall -and -not (Get-Command "uv" -ErrorAction SilentlyContinue)) {
        Write-Host "==> 'uv' not found. Installing uv..." -ForegroundColor Cyan
        if (-not $DryRun) {
            $installed = $false
            if (Get-Command "winget" -ErrorAction SilentlyContinue) {
                try { winget install --id=astral-sh.uv -e --silent --accept-source-agreements --accept-package-agreements; $installed = $true } catch {}
            }
            if (-not $installed) {
                try { irm https://astral.sh/uv/install.ps1 | iex; $env:Path = "$env:USERPROFILE\.local\bin;$env:USERPROFILE\.cargo\bin;$env:Path" } catch { Write-Warning "Could not install uv." }
            }
        }
    }

    # Cai dat mcp-atlassian (kiem tra da tang de triet de tranh loi khoa file Windows: os error 5 / Access is denied)
    if (-not $SkipInstall) {
        $targetAtlassianVer = "0.23.1"
        $needAtlassianInstall = $true

        # 1. Kiem tra qua uv tool list
        if (Get-Command "uv" -ErrorAction SilentlyContinue) {
            try {
                $uvTools = (uv tool list 2>&1 | Out-String)
                if ($uvTools -match "mcp-atlassian\s+v?$targetAtlassianVer" -or $uvTools -match "mcp-atlassian") {
                    Write-Host "  -> mcp-atlassian da co san trong uv tools. Bo qua cai dat lai de tranh loi khoa file Windows (Access is denied / os error 5)." -ForegroundColor Green
                    $needAtlassianInstall = $false
                }
            } catch {}
        }

        # 2. Kiem tra qua file thuc thi da ton tai trong AppData hoac PATH
        if ($needAtlassianInstall) {
            $candidateExecutables = @(
                (Join-Path $env:APPDATA "uv\tools\mcp-atlassian\Scripts\mcp-atlassian.exe"),
                "$env:USERPROFILE\.local\bin\mcp-atlassian.exe"
            )
            foreach ($exe in $candidateExecutables) {
                if (Test-Path $exe) {
                    Write-Host "  -> Tim thay mcp-atlassian tai '$exe'. Bo qua cai dat lai de tranh xung dot khoa file." -ForegroundColor Green
                    $needAtlassianInstall = $false
                    break
                }
            }
            if ($needAtlassianInstall -and (Get-Command "mcp-atlassian" -ErrorAction SilentlyContinue)) {
                Write-Host "  -> mcp-atlassian da co san trong PATH. Bo qua cai dat lai." -ForegroundColor Green
                $needAtlassianInstall = $false
            }
        }

        # 3. Chi cai dat neu thuc su chua ton tai
        if ($needAtlassianInstall) {
            Write-Host "==> Dang cai dat mcp-atlassian==$targetAtlassianVer qua uv tool..." -ForegroundColor Cyan
            if (-not $DryRun -and (Get-Command "uv" -ErrorAction SilentlyContinue)) {
                $uvResult = (uv tool install "mcp-atlassian==$targetAtlassianVer" 2>&1 | Out-String)
                if ($LASTEXITCODE -ne 0) {
                    if ($uvResult -match "os error 5" -or $uvResult -match "Access is denied") {
                        Write-Warning "Khong the ghi de mcp-atlassian do tien trinh dang chay ngam trong he thong (Windows File Lock). Phien ban hien tai van se duoc tiep tuc su dung binh thuong."
                    } else {
                        Write-Warning "Cai dat mcp-atlassian: $uvResult"
                    }
                }
            }
        }
    }
}

# Cai dat glab
if ($installGlab) {
    if (-not $SkipInstall -and -not (Get-Command "glab" -ErrorAction SilentlyContinue)) {
        Write-Host "==> Installing glab globally..." -ForegroundColor Cyan
        if (-not $DryRun -and (Get-Command "winget" -ErrorAction SilentlyContinue)) {
            try {
                winget install -e --id GLab.GLab --silent --accept-source-agreements --accept-package-agreements | Out-Null
                if (Test-Path "$env:LOCALAPPDATA\Programs\glab") { $env:Path = "$env:LOCALAPPDATA\Programs\glab;$env:Path" }
            } catch {}
        }
    }
}

# Cai dat / cap nhat memorix (khi $EnableMemorix = $true)
$shouldSetupHook = $false
if ($EnableMemorix) {
    if (-not $SkipInstall) {
        Write-Host "==> Dang cai dat / cap nhat Memorix len phien ban moi nhat (npm install -g memorix)..." -ForegroundColor Cyan
        if (-not $DryRun) {
            try {
                npm install -g memorix
            } catch {
                Write-Warning "Cai dat/cap nhat Memorix gap loi: $($_.Exception.Message)"
            }
        }
    }
    if (-not $DryRun -and [Environment]::UserInteractive -and -not $env:CI -and -not $SkipInstall) {
        $hookChoice = Read-Host "[?] Cai dat Hook tich hop Memorix vao Claude Code? [y/N]"
        if (-not [string]::IsNullOrWhiteSpace($hookChoice) -and ($hookChoice.Trim().ToLower() -eq 'y' -or $hookChoice.Trim().ToLower() -eq 'yes')) {
            $shouldSetupHook = $true
        }
    }
    if ($shouldSetupHook) {
        Write-Host "==> Registering memorix Claude Code plugin + hooks..." -ForegroundColor Cyan
        if (-not $DryRun) {
            try { memorix hooks install --agent claude --global } catch { Write-Warning "memorix hooks install failed: $($_.Exception.Message)" }
        }
    } else {
        if (-not $DryRun) {
            Write-Host "==> Bo qua cau hinh hook memorix cho Claude Code." -ForegroundColor DarkGray
        }
    }
}

# Cai dat gitnexus
$absGn = ""
if ($installGitnexus) {
    if (-not $SkipInstall) {
        Write-Host "==> Installing gitnexus globally..." -ForegroundColor Cyan
        if (-not $DryRun) { npm install -g gitnexus --silent }
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
    if (-not $gnPath) { throw "Loi: Khong tim thay gitnexus." }
    $absGn = $gnPath.Replace('\', '\\')
}
# Cai dat context7
$absCtx2 = ""
if ($installContext7) {
    if (-not $SkipInstall) {
        Write-Host "==> Installing context7 globally..." -ForegroundColor Cyan
        if (-not $DryRun) { npm install -g @upstash/context7-mcp --silent }
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
        } else {
            throw "Loi: Khong tim thay file dist\index.js cua context7. Dung cai dat."
        }
    } else {
        throw "Loi: Khong tim thay thu muc npm root -g de lay duong dan context7. Dung cai dat."
    }
}

# Cau hinh CloakBrowser
function Get-CloakBrowserInstallDir {
    if ($env:CLOAKBROWSER_DIR) { return $env:CLOAKBROWSER_DIR }
    $defaultLetter = "D:"
    if (-not (Test-Path "D:\")) { $defaultLetter = "C:" }
    $drives = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | Sort-Object DeviceID)
    if ($drives.Count -eq 0) {
        try { $drives = @(Get-PSDrive -PSProvider 'FileSystem' | Where-Object { $_.Free -gt 0 } | Sort-Object Name) } catch {}
    }
    if ($drives.Count -le 1) { return "$defaultLetter\mcp-servers\cloakbrowser" }
    if (-not [Environment]::UserInteractive -or [Console]::IsInputRedirected) { return "$defaultLetter\mcp-servers\cloakbrowser" }

    Write-Host ""
    Write-Host "==> Phat hien he thong co nhieu o dia:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $drives.Count; $i++) {
        $d = $drives[$i]
        $devId = if ($d.DeviceID) { $d.DeviceID } else { "$($d.Name):" }
        $volName = if ($d.VolumeName) { " ($($d.VolumeName))" } else { "" }
        $freeVal = if ($d.FreeSpace) { $d.FreeSpace } else { $d.Free }
        $freeGB = [math]::Round(($freeVal / 1GB), 2)
        $sizeGB = if ($d.Size) { [math]::Round(($d.Size / 1GB), 2) } else { "N/A" }
        Write-Host "  [$($i+1)] O $devId$volName | Trong: $freeGB GB / $sizeGB GB"
    }

    $promptMsg = "Chon so thu tu o dia muon luu CloakBrowser (mac dinh o $defaultLetter)"
    try {
        $inputVal = Read-Host $promptMsg
        if (-not [string]::IsNullOrWhiteSpace($inputVal)) {
            $choice = $inputVal.Trim()
            $idx = 0
            if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $drives.Count) {
                $chosen = $drives[$idx - 1]
                $chosenLetter = if ($chosen.DeviceID) { $chosen.DeviceID } else { "$($chosen.Name):" }
                return "$chosenLetter\mcp-servers\cloakbrowser"
            }
        }
    } catch {}
    return "$defaultLetter\mcp-servers\cloakbrowser"
}

function Setup-CloakBrowser {
    param([string]$TargetDir, [string]$SourceDir, [switch]$DryRun, [switch]$SkipInstall)
    Write-Host "==> Cau hinh CloakBrowser tai: $TargetDir" -ForegroundColor Cyan
    if (-not (Test-Path $TargetDir)) {
        if (-not $DryRun) { New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null }
    }

    $mainScript = Join-Path $TargetDir "mcp-server-full.mjs"
    $pkgJson = Join-Path $TargetDir "package.json"
    if ((Test-Path $mainScript) -and (Test-Path $pkgJson)) {
        Write-Host "  -> CloakBrowser da ton tai day du file ma nguon. Giu nguyen du lieu & profile cu (khong ghi de)." -ForegroundColor Green
    } else {
        if (Test-Path $SourceDir) {
            Write-Host "  -> Sao chep ma nguon CloakBrowser tu bo cai vao $TargetDir..." -ForegroundColor DarkGray
            if (-not $DryRun) { Copy-Item -Path "$SourceDir\*" -Destination $TargetDir -Recurse -Force }
        } else {
            Write-Warning "Khong tim thay thu muc ma nguon CloakBrowser tai: $SourceDir"
        }
    }

    if (-not $SkipInstall -and -not $DryRun) {
        $needsNpmInstall = $false
        $nodeModulesDir = Join-Path $TargetDir "node_modules"
        if (-not (Test-Path $nodeModulesDir)) {
            $needsNpmInstall = $true
        } else {
            foreach ($dep in @("@modelcontextprotocol\sdk", "playwright", "dotenv")) {
                if (-not (Test-Path (Join-Path $nodeModulesDir $dep))) {
                    $needsNpmInstall = $true
                    break
                }
            }
        }
        if ($needsNpmInstall) {
            Write-Host "  -> Dang cai dat dependencies cho CloakBrowser (npm install --silent)..." -ForegroundColor DarkGray
            Push-Location $TargetDir
            try { npm install --silent } catch { Write-Warning "npm install tai CloakBrowser gap loi: $($_.Exception.Message)" }
            finally { Pop-Location }
        }
    }
    return $mainScript
}


# Thu thap cau hinh
$aiBaseUrl = Get-EnvOrPrompt -EnvName "AI_BASE_URL" -Prompt "AI Base URL" -Default "http://localhost:20128/v1"
$aiKey = Get-EnvOrPrompt -EnvName "AI_API_KEY" -Prompt "AI API Key" -Required

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

    # Xac thuc glab neu co token
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

$cloakScript = ""
if ($installCloakbrowser) {
    $cbSourceDir = Join-Path $PSScriptRoot "mcp-servers\cloakbrowser"
    $cbTargetDir = Get-CloakBrowserInstallDir
    $cloakScriptPath = Setup-CloakBrowser -TargetDir $cbTargetDir -SourceDir $cbSourceDir -DryRun:$DryRun -SkipInstall:$SkipInstall
    $cloakScript = ($cloakScriptPath).Replace('\', '\\')
}

# Chuan bi duong dan gitnexus
$escapedGitnexus = if ($absGn) { $absGn } elseif ($gn -and $gn.Source) { ($gn.Source).Replace('\', '\\') } else { "" }
# Xu ly claude.json (hoac mcp.json)
$templatesDir = Join-Path $PSScriptRoot "templates"
$claudeTemplatePath = Join-Path $templatesDir "claude.json"
if (-not (Test-Path $claudeTemplatePath)) { $claudeTemplatePath = Join-Path $templatesDir "mcp.json" }

if (Test-Path $claudeTemplatePath) {
    $mcpRaw = Get-Content -Path $claudeTemplatePath -Raw -Encoding UTF8
    $mcpJsonStr = $mcpRaw `
        -replace '__GITNEXUS_PATH__', $escapedGitnexus `
        -replace '__JIRA_URL__', $jiraUrl `
        -replace '__JIRA_PERSONAL_TOKEN__', $jiraToken `
        -replace '__CONFLUENCE_URL__', $confUrl `
        -replace '__CONFLUENCE_PERSONAL_TOKEN__', $confToken `
        -replace '__CONTEXT7_PATH__', $absCtx2 `
        -replace '__CONTEXT7_API_KEY__', $ctxKey `
        -replace '__CLOAKBROWSER_SCRIPT__', $cloakScript
} else {
    # Fallback mcp JSON string
    $mcpJsonStr = @"
{
  "mcpServers": {
    "gitnexus": {
      "command": "cmd",
      "args": ["/c", "$escapedGitnexus", "mcp"]
    },
    "company-atlassian": {
      "command": "uvx",
      "args": ["mcp-atlassian==0.23.1"],
      "env": {
        "JIRA_URL": "$jiraUrl",
        "JIRA_PERSONAL_TOKEN": "$jiraToken",
        "CONFLUENCE_URL": "$confUrl",
        "CONFLUENCE_PERSONAL_TOKEN": "$confToken"
      }
    },
    "context7": {
      "command": "node",
      "args": ["$absCtx2"],
      "env": { "CONTEXT7_API_KEY": "$ctxKey" }
    },
    "glab": {
      "command": "glab",
      "args": ["mcp", "serve"]
    },
    "cloakbrowser": {
      "command": "node",
      "args": ["$cloakScript"]
    }
  }
}
"@
}

$mcpObj = $mcpJsonStr | ConvertFrom-Json
if (-not $mcpObj.mcpServers) {
    $mcpObj | Add-Member -MemberType NoteProperty -Name 'mcpServers' -Value ([PSCustomObject]@{}) -Force
}

# Loc bo cac MCP Server bi tu choi cai dat
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
if ($installContext7 -and [string]::IsNullOrWhiteSpace($ctxKey) -and $mcpObj.mcpServers.context7 -and $mcpObj.mcpServers.context7.PSObject.Properties['env']) {
    $mcpObj.mcpServers.context7.PSObject.Properties.Remove('env')
}

# Xu ly server memorix trong mcpServers
if ($EnableMemorix) {
    $memorixMcp = [PSCustomObject]@{
        command = "memorix"
        args = @("mcp")
    }
    $mcpObj.mcpServers | Add-Member -MemberType NoteProperty -Name 'memorix' -Value $memorixMcp -Force
} else {
    if ($mcpObj.mcpServers.PSObject.Properties['memorix']) {
        $mcpObj.mcpServers.PSObject.Properties.Remove('memorix')
    }
}

if ($DryRun -and [string]::IsNullOrWhiteSpace($aiKey)) {
    $aiKey = "dryrun-placeholder-key"
}
if ($DryRun -and [string]::IsNullOrWhiteSpace($env:ANTHROPIC_API_KEY)) {
    $env:ANTHROPIC_API_KEY = "dryrun-placeholder-key"
}

# Ghi / Merge cau hinh vao $ClaudeJson
Write-Host "==> Xu ly cau hinh $ClaudeJson..." -ForegroundColor Cyan
if (Test-Path $ClaudeJson) {
    $bakJsonPath = Get-BackupPath -Path $ClaudeJson
    if ($isForce) {
        Write-Host "  -> File '$ClaudeJson' da ton tai. [-Force / -OverwriteAll] Tu dong sao luu va ghi de." -ForegroundColor Yellow
        if (-not $DryRun) {
            Copy-Item -Path $ClaudeJson -Destination $bakJsonPath -Force
            Write-Host "     Da sao luu sang $bakJsonPath" -ForegroundColor DarkGray
            $existing = (Get-Content $ClaudeJson -Raw -Encoding UTF8) | ConvertFrom-Json
            if (-not $existing) { $existing = [PSCustomObject]@{} }
            $existing | Add-Member -MemberType NoteProperty -Name 'mcpServers' -Value $mcpObj.mcpServers -Force
            $outJson = $existing | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($ClaudeJson, $outJson, [System.Text.UTF8Encoding]::new($false))
        }
    } else {
        $choice = ""
        if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
            $choice = Read-Host "[?] File '$ClaudeJson' da ton tai. Ban co muon [O]verwrite (ghi de), [M]erge (hop nhat cau hinh cu va moi), hay [S]kip (bo qua)? [O/M/s]"
            $choice = if ($choice) { $choice.Trim() } else { "" }
        } else {
            $choice = "M"
        }

        if ($choice -match '^[mM]$' -or ($choice -eq "" -and (-not [Environment]::UserInteractive -or [Console]::IsInputRedirected))) {
            Write-Host "  -> Dang hop nhat cau hinh MCP vao $ClaudeJson (sao luu sang $bakJsonPath)..." -ForegroundColor Cyan
            if (-not $DryRun) {
                Copy-Item -Path $ClaudeJson -Destination $bakJsonPath -Force
                Write-Host "     Da sao luu sang $bakJsonPath" -ForegroundColor DarkGray
                try {
                    $existing = (Get-Content $ClaudeJson -Raw -Encoding UTF8) | ConvertFrom-Json
                    if (-not $existing) { $existing = [PSCustomObject]@{} }
                    if (-not $existing.PSObject.Properties['mcpServers']) {
                        $existing | Add-Member -MemberType NoteProperty -Name 'mcpServers' -Value ([PSCustomObject]@{}) -Force
                    }
                    foreach ($prop in $mcpObj.mcpServers.PSObject.Properties) {
                        $existing.mcpServers | Add-Member -MemberType NoteProperty -Name $prop.Name -Value $prop.Value -Force
                    }
                    if (-not $EnableMemorix -and $existing.mcpServers.PSObject.Properties['memorix']) {
                        $existing.mcpServers.PSObject.Properties.Remove('memorix')
                    }
                    $outJson = $existing | ConvertTo-Json -Depth 10
                    [System.IO.File]::WriteAllText($ClaudeJson, $outJson, [System.Text.UTF8Encoding]::new($false))
                    Write-Host "     Hop nhat mcpServers thanh cong." -ForegroundColor Green
                } catch {
                    Write-Warning "Loi khi hop nhat cau hinh ${ClaudeJson}: $($_.Exception.Message)"
                }
            } else {
                Write-Host "  -> [WhatIf] Sao luu: $bakJsonPath" -ForegroundColor DarkGray
                Write-Host "  -> [WhatIf] Hop nhat va ghi file: $ClaudeJson" -ForegroundColor DarkGray
            }
        } elseif ($choice -match '^[oO]$') {
            Write-Host "  -> Ghi de mcpServers trong $ClaudeJson (sao luu sang $bakJsonPath)..." -ForegroundColor Green
            if (-not $DryRun) {
                Copy-Item -Path $ClaudeJson -Destination $bakJsonPath -Force
                Write-Host "     Da sao luu sang $bakJsonPath" -ForegroundColor DarkGray
                $existing = (Get-Content $ClaudeJson -Raw -Encoding UTF8) | ConvertFrom-Json
                if (-not $existing) { $existing = [PSCustomObject]@{} }
                $existing | Add-Member -MemberType NoteProperty -Name 'mcpServers' -Value $mcpObj.mcpServers -Force
                $outJson = $existing | ConvertTo-Json -Depth 10
                [System.IO.File]::WriteAllText($ClaudeJson, $outJson, [System.Text.UTF8Encoding]::new($false))
            }
        } else {
            Write-Host "  -> Bo qua $ClaudeJson (giu nguyen file hien tai)." -ForegroundColor Yellow
        }
    }
} else {
    if (-not $DryRun) {
        $rootObj = [PSCustomObject]@{
            mcpServers = $mcpObj.mcpServers
        }
        $outJson = $rootObj | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($ClaudeJson, $outJson, [System.Text.UTF8Encoding]::new($false))
    }
}

# Dam bao cac thu muc ho tro va cai dat Trash Guard
Write-Host "==> Cai dat Trash Guard (bao ve chan xoa cung cho Claude Code)..." -ForegroundColor Cyan
$userProfileFwd = $env:USERPROFILE.Replace('\', '/')
$targetTrashGuard = Join-Path $env:USERPROFILE ".trash-guard"
if (-not $DryRun) {
    if (-not (Test-Path $targetTrashGuard)) {
        if (-not $DryRun) { New-Item -ItemType Directory -Path $targetTrashGuard -Force | Out-Null } else { Write-Host "  -> [WhatIf] Tao thu muc: $targetTrashGuard" -ForegroundColor DarkGray }
    }
    $srcTrashGuard = Join-Path $PSScriptRoot "trash-guard"
    if (Test-Path $srcTrashGuard) {
        Copy-Item -Path "$srcTrashGuard\*" -Destination $targetTrashGuard -Force -Recurse
        Write-Host "  -> Sao chep cac script Trash Guard sang $targetTrashGuard..." -ForegroundColor Green
    }
}
Write-Host "  -> Kich hoat PreToolUse hook trong settings.json de chan cac lenh xoa cung (rm, del, Remove-Item)..." -ForegroundColor Green
Write-Host "  -> Hoan tat kich hoat Trash Guard cho Claude Code." -ForegroundColor Green
if (-not $DryRun) {
    # Don dep tuyet doi PowerShell Profile: Dam bao terminal cua nguoi dung sach se 100%
    $profileCandidates = @(
        "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1",
        "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1",
        "$env:USERPROFILE\Documents\PowerShell\profile.ps1",
        "$env:USERPROFILE\Documents\WindowsPowerShell\profile.ps1"
    )
    foreach ($profPath in $profileCandidates) {
        if (Test-Path $profPath) {
            $profContent = Get-Content -Path $profPath -Raw -Encoding UTF8
            if ($profContent -match "trash-guard") {
                $cleanedProf = ($profContent -split "`r?`n" | Where-Object { $_ -notmatch "trash-guard" }) -join "`r`n"
                [System.IO.File]::WriteAllText($profPath, $cleanedProf.Trim() + "`r`n", [System.Text.UTF8Encoding]::new($false))
                Write-Host "  -> Da go bo hook trash-guard khoi PowerShell Profile ($profPath) de giu terminal sach se 100%." -ForegroundColor Green
            }
        }
    }

    $srcHud = Join-Path $PSScriptRoot "hud"
    $targetHudDir = Join-Path $ClaudeDir "hud"
    if (Test-Path $srcHud) {
        if (-not (Test-Path $targetHudDir)) {
            if (-not $DryRun) { New-Item -ItemType Directory -Path $targetHudDir -Force | Out-Null } else { Write-Host "  -> [WhatIf] Tao thu muc: $targetHudDir" -ForegroundColor DarkGray }
        }
        Copy-Item -Path "$srcHud\*" -Destination $targetHudDir -Force -Recurse
    }
}

$hudSrcFile = Join-Path $PSScriptRoot "hud/hud.mjs"
$hudDestFile = Join-Path $ClaudeDir "hud/hud.mjs"
$hudEffective = $hudDestFile
if ($env:HUD_PATH) { $hudEffective = $env:HUD_PATH }
$hasHud = (Test-Path $hudEffective) -or ((-not $env:HUD_PATH) -and (Test-Path $hudSrcFile))

$claudeDirFwd = $ClaudeDir.Replace('\','/')
$hudCmdJson = "$claudeDirFwd/hud/hud.mjs"
if ($env:HUD_PATH) { $hudCmdJson = $env:HUD_PATH.Replace('\','/') }

$hudStatusLine = ""
if ($hasHud) {
    $hudStatusLine = ",`n  `"statusLine`": {`n    `"type`": `"command`",`n    `"command`": `"node $hudCmdJson`"`n  }"
}

$trashGuardCmd = Join-Path $env:USERPROFILE ".trash-guard/claude-pre-tool.cmd"
if ($env:TRASH_GUARD_HOOK_PATH) { $trashGuardCmd = $env:TRASH_GUARD_HOOK_PATH }
$hasTrashGuard = Test-Path $trashGuardCmd

$orcaHookPath = Join-Path $env:USERPROFILE ".orca/agent-hooks/claude-hook.cmd"
if ($env:ORCA_HOOK_PATH) { $orcaHookPath = $env:ORCA_HOOK_PATH }
$hasOrca = Test-Path $orcaHookPath

# Xay dung hooks cho settings.json
$hooksObj = [ordered]@{}

# SessionStart
$sessionStartHooks = [System.Collections.ArrayList]@()
if ($shouldSetupHook) {
    $sessionStartHooks.Add([ordered]@{
        hooks = @([ordered]@{
            type = "command"
            command = "memorix.cmd hook"
            timeout = 60
        })
    }) | Out-Null
}
if ($hasOrca) {
    $sessionStartHooks.Add([ordered]@{
        hooks = @([ordered]@{
            type = "command"
            command = "$userProfileFwd/.orca/agent-hooks/claude-hook.cmd"
            timeout = 60
        })
    }) | Out-Null
}
if ($sessionStartHooks.Count -gt 0) {
    $hooksObj["SessionStart"] = $sessionStartHooks
}

# PreToolUse
$preToolHooks = [System.Collections.ArrayList]@()
if ($hasTrashGuard) {
    $preToolHooks.Add([ordered]@{
        matcher = "Bash"
        hooks = @([ordered]@{
            type = "command"
            command = "$userProfileFwd/.trash-guard/claude-pre-tool.cmd"
            timeout = 15
        })
    }) | Out-Null
    $preToolHooks.Add([ordered]@{
        matcher = "PowerShell"
        hooks = @([ordered]@{
            type = "command"
            command = "$userProfileFwd/.trash-guard/claude-pre-tool.cmd"
            timeout = 15
        })
    }) | Out-Null
}
if ($preToolHooks.Count -gt 0) {
    $hooksObj["PreToolUse"] = $preToolHooks
}

# PostToolUse
$postToolHooks = [System.Collections.ArrayList]@()
if ($shouldSetupHook) {
    $postToolHooks.Add([ordered]@{
        hooks = @([ordered]@{
            type = "command"
            command = "memorix.cmd hook"
            timeout = 60
        })
    }) | Out-Null
}
if ($hasOrca) {
    $postToolHooks.Add([ordered]@{
        matcher = "*"
        hooks = @([ordered]@{
            type = "command"
            command = "$userProfileFwd/.orca/agent-hooks/claude-hook.cmd"
            timeout = 60
        })
    }) | Out-Null
}
if ($postToolHooks.Count -gt 0) {
    $hooksObj["PostToolUse"] = $postToolHooks
}

if ($shouldSetupHook) {
    $hooksObj["PreCompact"] = @(
        [ordered]@{
            hooks = @([ordered]@{
                type = "command"
                command = "memorix.cmd hook"
                timeout = 60
            })
        }
    )
    $hooksObj["PostCompact"] = @(
        [ordered]@{
            hooks = @([ordered]@{
                type = "command"
                command = "memorix.cmd hook"
                timeout = 60
            })
        }
    )
}

# Stop
$stopHooks = [System.Collections.ArrayList]@()
if ($shouldSetupHook) {
    $stopHooks.Add([ordered]@{
        hooks = @([ordered]@{
            type = "command"
            command = "memorix.cmd hook"
            timeout = 60
        })
    }) | Out-Null
}
if ($hasOrca) {
    $stopHooks.Add([ordered]@{
        hooks = @([ordered]@{
            type = "command"
            command = "$userProfileFwd/.orca/agent-hooks/claude-hook.cmd"
            timeout = 60
        })
    }) | Out-Null
}
if ($stopHooks.Count -gt 0) {
    $hooksObj["Stop"] = $stopHooks
}

# SessionEnd
$sessionEndHooks = [System.Collections.ArrayList]@()
if ($shouldSetupHook) {
    $sessionEndHooks.Add([ordered]@{
        hooks = @([ordered]@{
            type = "command"
            command = "memorix.cmd hook"
            timeout = 60
        })
    }) | Out-Null
}
if ($hasOrca) {
    $sessionEndHooks.Add([ordered]@{
        hooks = @([ordered]@{
            type = "command"
            command = "$userProfileFwd/.orca/agent-hooks/claude-hook.cmd"
            timeout = 60
        })
    }) | Out-Null
}
if ($sessionEndHooks.Count -gt 0) {
    $hooksObj["SessionEnd"] = $sessionEndHooks
}

# Orca optional lifecycle hooks
if ($hasOrca) {
    $hooksObj["UserPromptSubmit"] = @([ordered]@{
        hooks = @([ordered]@{
            type = "command"
            command = "$userProfileFwd/.orca/agent-hooks/claude-hook.cmd"
            timeout = 60
        })
    })
    $hooksObj["StopFailure"] = @([ordered]@{
        hooks = @([ordered]@{
            type = "command"
            command = "$userProfileFwd/.orca/agent-hooks/claude-hook.cmd"
            timeout = 60
        })
    })
    $hooksObj["SubagentStart"] = @([ordered]@{
        hooks = @([ordered]@{
            type = "command"
            command = "$userProfileFwd/.orca/agent-hooks/claude-hook.cmd"
            timeout = 60
        })
    })
    $hooksObj["SubagentStop"] = @([ordered]@{
        hooks = @([ordered]@{
            type = "command"
            command = "$userProfileFwd/.orca/agent-hooks/claude-hook.cmd"
            timeout = 60
        })
    })
    $hooksObj["TeammateIdle"] = @([ordered]@{
        hooks = @([ordered]@{
            type = "command"
            command = "$userProfileFwd/.orca/agent-hooks/claude-hook.cmd"
            timeout = 60
        })
    })
    $hooksObj["PostToolUseFailure"] = @([ordered]@{
        matcher = "*"
        hooks = @([ordered]@{
            type = "command"
            command = "$userProfileFwd/.orca/agent-hooks/claude-hook.cmd"
            timeout = 60
        })
    })
    $hooksObj["PermissionRequest"] = @([ordered]@{
        hooks = @([ordered]@{
            type = "command"
            command = "$userProfileFwd/.orca/agent-hooks/claude-hook.cmd"
            timeout = 60
        })
    })
}

# Cau hinh settings.json
$settingsTemplatePath = Join-Path $templatesDir "settings.json"
$targetSettingsPath = Join-Path $ClaudeDir "settings.json"

if (-not (Test-Path $ClaudeDir)) {
    if (-not $DryRun) { New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null } else { Write-Host "  -> [WhatIf] Tao thu muc: $ClaudeDir" -ForegroundColor DarkGray }
}

$settingsObj = [ordered]@{
    env = [ordered]@{
        ANTHROPIC_BASE_URL = $aiBaseUrl
        ANTHROPIC_AUTH_TOKEN = $aiKey
        ANTHROPIC_DEFAULT_FABLE_MODEL = "claude-fable-5"
        ANTHROPIC_DEFAULT_OPUS_MODEL = "claude-opus-5"
        ANTHROPIC_DEFAULT_SONNET_MODEL = "claude-sonnet-5"
        ANTHROPIC_DEFAULT_HAIKU_MODEL = "claude-haiku-4-5-20251001"
        ANTHROPIC_MODEL = "claude-sonnet-5"
        CLAUDE_CODE_SUBAGENT_MODEL = "sonnet[1m]"
        API_TIMEOUT_MS = "3000000"
        CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS = "1"
        CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS = "1"
        CLAUDE_CODE_NO_FLICKER = "1"
        CLAUDE_CODE_USE_POWERSHELL_TOOL = "1"
        MCP_TIMEOUT = "120000"
        MCP_TOOL_TIMEOUT = "120000"
    }
    permissions = [ordered]@{
        allow = @("Bash", "PowerShell", "Read", "Write", "Edit", "Glob", "Grep", "Task", "WebSearch", "FetchUrl")
        deny = @()
        defaultMode = "bypassPermissions"
    }
    model = "sonnet[1m]"
}

if ($hasHud) {
    $settingsObj["statusLine"] = [ordered]@{
        type = "command"
        command = "node $hudCmdJson"
    }
}
if ($hooksObj.Count -gt 0) {
    $settingsObj["hooks"] = $hooksObj
}

Write-Host "==> Xu ly cau hinh $targetSettingsPath..." -ForegroundColor Cyan
if (Test-Path $targetSettingsPath) {
    $bakSettingsPath = Get-BackupPath -Path $targetSettingsPath
    if ($isForce) {
        Write-Host "  -> File '$targetSettingsPath' da ton tai. [-Force / -OverwriteAll] Tu dong sao luu va ghi de." -ForegroundColor Yellow
        if (-not $DryRun) {
            Copy-Item -Path $targetSettingsPath -Destination $bakSettingsPath -Force
            Write-Host "     Da sao luu sang $bakSettingsPath" -ForegroundColor DarkGray
            $outSettingsJson = $settingsObj | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($targetSettingsPath, $outSettingsJson, [System.Text.UTF8Encoding]::new($false))
        } else {
            Write-Host "  -> [WhatIf] Sao luu: $bakSettingsPath" -ForegroundColor DarkGray
            Write-Host "  -> [WhatIf] Ghi file: $targetSettingsPath" -ForegroundColor DarkGray
        }
    } else {
        $choice = ""
        if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
            $choice = Read-Host "[?] File '$targetSettingsPath' da ton tai. Ban co muon [O]verwrite (ghi de), [M]erge (hop nhat cau hinh cu va moi), hay [S]kip (bo qua)? [O/M/s]"
            $choice = if ($choice) { $choice.Trim() } else { "" }
        } else {
            $choice = "M"
        }

        if ($choice -match '^[mM]$' -or ($choice -eq "" -and (-not [Environment]::UserInteractive -or [Console]::IsInputRedirected))) {
            Write-Host "  -> Dang hop nhat cau hinh $targetSettingsPath (sao luu sang $bakSettingsPath)..." -ForegroundColor Cyan
            if (-not $DryRun) {
                Copy-Item -Path $targetSettingsPath -Destination $bakSettingsPath -Force
                Write-Host "     Da sao luu sang $bakSettingsPath" -ForegroundColor DarkGray
                try {
                    $existingSettings = (Get-Content $targetSettingsPath -Raw -Encoding UTF8) | ConvertFrom-Json
                    if (-not $existingSettings) { $existingSettings = [PSCustomObject]@{} }

                    # Merge env
                    if (-not $existingSettings.PSObject.Properties['env']) {
                        $existingSettings | Add-Member -MemberType NoteProperty -Name 'env' -Value ([PSCustomObject]@{}) -Force
                    }
                    foreach ($k in $settingsObj.env.Keys) {
                        $existingSettings.env | Add-Member -MemberType NoteProperty -Name $k -Value $settingsObj.env[$k] -Force
                    }

                    # Merge permissions
                    if (-not $existingSettings.PSObject.Properties['permissions']) {
                        $existingSettings | Add-Member -MemberType NoteProperty -Name 'permissions' -Value ([PSCustomObject]@{ allow = @(); deny = @(); defaultMode = "bypassPermissions" }) -Force
                    }

                    # StatusLine
                    if ($hasHud) {
                        $existingSettings | Add-Member -MemberType NoteProperty -Name 'statusLine' -Value $settingsObj.statusLine -Force
                    } elseif ($existingSettings.PSObject.Properties['statusLine']) {
                        $existingSettings.PSObject.Properties.Remove('statusLine')
                    }

                    # Hooks
                    $existingSettings | Add-Member -MemberType NoteProperty -Name 'hooks' -Value $hooksObj -Force

                    $existingSettings | Add-Member -MemberType NoteProperty -Name 'model' -Value $settingsObj.model -Force

                    $outMerged = $existingSettings | ConvertTo-Json -Depth 10
                    [System.IO.File]::WriteAllText($targetSettingsPath, $outMerged, [System.Text.UTF8Encoding]::new($false))
                    Write-Host "     Hop nhat settings.json thanh cong." -ForegroundColor Green
                } catch {
                    Write-Warning "Loi khi hop nhat settings.json: $($_.Exception.Message)"
                }
            } else {
                Write-Host "  -> [WhatIf] Sao luu: $bakSettingsPath" -ForegroundColor DarkGray
                Write-Host "  -> [WhatIf] Hop nhat va ghi file: $targetSettingsPath" -ForegroundColor DarkGray
            }
        } elseif ($choice -match '^[oO]$') {
            Write-Host "  -> Ghi de file $targetSettingsPath (da sao luu sang $bakSettingsPath)" -ForegroundColor Green
            if (-not $DryRun) {
                Copy-Item -Path $targetSettingsPath -Destination $bakSettingsPath -Force
                Write-Host "     Da sao luu sang $bakSettingsPath" -ForegroundColor DarkGray
                $outSettingsJson = $settingsObj | ConvertTo-Json -Depth 10
                [System.IO.File]::WriteAllText($targetSettingsPath, $outSettingsJson, [System.Text.UTF8Encoding]::new($false))
            } else {
                Write-Host "  -> [WhatIf] Sao luu: $bakSettingsPath" -ForegroundColor DarkGray
                Write-Host "  -> [WhatIf] Ghi file: $targetSettingsPath" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "  -> Bo qua $targetSettingsPath (giu nguyen file hien tai)." -ForegroundColor Yellow
        }
    }
} else {
    if (-not $DryRun) {
        $outSettingsJson = $settingsObj | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($targetSettingsPath, $outSettingsJson, [System.Text.UTF8Encoding]::new($false))
    } else {
        Write-Host "  -> [WhatIf] Ghi file: $targetSettingsPath" -ForegroundColor DarkGray
    }
}

# Xu ly CLAUDE.md
Write-Host "==> Cap nhat CLAUDE.md tai $ClaudeDir..." -ForegroundColor Cyan
$claudeMdTemplatePath = Join-Path $templatesDir "CLAUDE.md"
$claudeMdContent = ""
if (Test-Path $claudeMdTemplatePath) {
    $claudeMdContent = Get-Content -Path $claudeMdTemplatePath -Raw -Encoding UTF8
} else {
    $claudeMdSrc = Join-Path $PSScriptRoot "CLAUDE.md"
    if (Test-Path $claudeMdSrc) {
        $claudeMdContent = Get-Content -Path $claudeMdSrc -Raw -Encoding UTF8
    }
}

if ($EnableMemorix) {
    $memorixSecPath = Join-Path $templatesDir "memorix-claude-section.md"
    if (Test-Path $memorixSecPath) {
        $memorixSec = Get-Content -Path $memorixSecPath -Raw -Encoding UTF8
        if ($claudeMdContent -notmatch "Memorix — Memory Tools") {
            $claudeMdContent = $claudeMdContent + "`n`n" + $memorixSec
        }
    }
}

$targetClaudeMd = Join-Path $ClaudeDir "CLAUDE.md"
if (Test-Path $targetClaudeMd) {
    $bakClaudeMd = Get-BackupPath -Path $targetClaudeMd
    if ($isForce) {
        if (-not $DryRun) {
            Copy-Item -Path $targetClaudeMd -Destination $bakClaudeMd -Force
            Write-Host "     Da sao luu sang $bakClaudeMd" -ForegroundColor DarkGray
            [System.IO.File]::WriteAllText($targetClaudeMd, $claudeMdContent, [System.Text.UTF8Encoding]::new($false))
        } else {
            Write-Host "  -> [WhatIf] Sao luu: $bakClaudeMd" -ForegroundColor DarkGray
            Write-Host "  -> [WhatIf] Ghi file: $targetClaudeMd" -ForegroundColor DarkGray
        }
    } else {
        $choice = ""
        if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
            $choice = Read-Host "[?] File '$targetClaudeMd' da ton tai. Ban co muon [O]verwrite (ghi de) hay [S]kip (bo qua)? [O/s]"
            $choice = if ($choice) { $choice.Trim() } else { "" }
        } else {
            $choice = "O"
        }
        if ($choice -match '^[oO]$' -or ($choice -eq "" -and (-not [Environment]::UserInteractive -or [Console]::IsInputRedirected))) {
            if (-not $DryRun) {
                Copy-Item -Path $targetClaudeMd -Destination $bakClaudeMd -Force
                Write-Host "     Da sao luu sang $bakClaudeMd" -ForegroundColor DarkGray
                [System.IO.File]::WriteAllText($targetClaudeMd, $claudeMdContent, [System.Text.UTF8Encoding]::new($false))
            } else {
                Write-Host "  -> [WhatIf] Sao luu: $bakClaudeMd" -ForegroundColor DarkGray
                Write-Host "  -> [WhatIf] Ghi file: $targetClaudeMd" -ForegroundColor DarkGray
            }
        }
    }
} else {
    if (-not $DryRun) {
        [System.IO.File]::WriteAllText($targetClaudeMd, $claudeMdContent, [System.Text.UTF8Encoding]::new($false))
    } else {
        Write-Host "  -> [WhatIf] Ghi file: $targetClaudeMd" -ForegroundColor DarkGray
    }
}

# Don dep cac tai lieu cu khong con dung va chuyen vao Thung rac (Recycle Bin)
$legacyFiles = @("SYSTEM.md", "AGENTS.md", "RULES.md")
foreach ($leg in $legacyFiles) {
    $oldFilePath = Join-Path $ClaudeDir $leg
    if (Test-Path $oldFilePath) {
        Write-Host "==> Don dep tai lieu cu: $oldFilePath (chuyen vao Thung rac)..." -ForegroundColor Cyan
        if (-not $DryRun) {
            Move-ToRecycleBinFile -Path $oldFilePath
        }
    }
}

# Xu ly thu muc skills
$srcSkillsDir = Join-Path $templatesDir "skills"
if (-not (Test-Path $srcSkillsDir)) {
    $srcSkillsDir = Join-Path $PSScriptRoot "skills"
}
$targetSkillsDir = Join-Path $ClaudeDir "skills"
if (Test-Path $srcSkillsDir) {
    Write-Host "==> Dong bo skills vao $targetSkillsDir..." -ForegroundColor Cyan
    if (-not (Test-Path $targetSkillsDir)) {
        if (-not $DryRun) { New-Item -ItemType Directory -Path $targetSkillsDir -Force | Out-Null } else { Write-Host "  -> [WhatIf] Tao thu muc: $targetSkillsDir" -ForegroundColor DarkGray }
    }

    $skillFolders = Get-ChildItem -Path $srcSkillsDir -Directory
    foreach ($sf in $skillFolders) {
        $isMemorixSkill = $sf.Name.StartsWith("memorix-")
        if (-not $EnableMemorix -and $isMemorixSkill) {
            continue
        }
        $destSf = Join-Path $targetSkillsDir $sf.Name
        if (-not $DryRun) {
            if (-not (Test-Path $destSf)) {
                New-Item -ItemType Directory -Path $destSf -Force | Out-Null
            }
            Copy-Item -Path "$($sf.FullName)\*" -Destination $destSf -Recurse -Force
        } else {
            Write-Host "  -> [WhatIf] Sao chep skill den: $destSf" -ForegroundColor DarkGray
        }
    }

    # Neu $EnableMemorix = $false: go bo cac thu muc skills memorix-* da ton tai truoc do sang Thung rac
    if (-not $EnableMemorix -and (Test-Path $targetSkillsDir)) {
        $existingMemorixSkills = Get-ChildItem -Path $targetSkillsDir -Directory -Filter "memorix-*"
        foreach ($ems in $existingMemorixSkills) {
            Write-Host "==> Go bo skill memorix cu: $($ems.FullName) (chuyen vao Thung rac)..." -ForegroundColor Cyan
            if (-not $DryRun) {
                Move-ToRecycleBinDirectory -Path $ems.FullName
            }
        }
    }
}

Write-Host "==> Hoan tat thiet lap moi truong Claude Code!" -ForegroundColor Green
