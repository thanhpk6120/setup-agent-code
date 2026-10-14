# bootstrap.ps1 - Setup DeepSeek Harness Web Runner environment on Windows
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipInstall,
    [switch]$EnableAgency,
    [switch]$DisableAgency,
    [string]$AgencyPath = "",
    [switch]$Force,
    [switch]$OverwriteAll,
    [switch]$EnableMemorix,
    [switch]$DisableMemorix,
    [string]$DshHome = "$env:USERPROFILE\.dsh",
    [string]$DshProfileDir = "$env:APPDATA\dsh-desktop\harness\profiles\web-runner",
    [string]$CredentialsPath = "$env:APPDATA\dsh-desktop\harness\.credentials.yaml"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

function Safe-Trash {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ($DryRun) {
        Write-Host "  -> [WhatIf] Safe-Trash: $Path" -ForegroundColor DarkGray
        return
    }
    if (Get-Command "trash" -ErrorAction SilentlyContinue) {
        trash $Path
        return
    }
    try {
        if ([System.IO.Directory]::Exists($Path)) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($Path, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
        } elseif ([System.IO.File]::Exists($Path)) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($Path, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
        }
    } catch {
        Write-Warning "Khong the di chuyen '$Path' vao Thung rac: $($_.Exception.Message)"
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
} elseif ($DisableMemorix.IsPresent) {
    $installMemorix = $false
    Write-Host "Skipped MCP 'memorix' theo lua chon nguoi dung." -ForegroundColor Yellow
} else {
    $installMemorix = $EnableMemorix.IsPresent
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

$installAgency = $false
if ($EnableAgency.IsPresent -and $DisableAgency.IsPresent) {
    throw "Khong dung dong thoi -EnableAgency va -DisableAgency."
}
if ($EnableAgency) {
    $installAgency = $true
} elseif ($DisableAgency) {
    $installAgency = $false
} else {
    $installAgency = Confirm-McpInstall -Name "agency"
    if (-not $installAgency) { Write-Host "Skipped MCP 'agency' theo lua chon nguoi dung." -ForegroundColor Yellow }
}

$isForce = $Force.IsPresent -or $OverwriteAll.IsPresent

# 3. Load .env (neu khong co se tham chieu templates/.env.example)
function Load-Env {
    param([string]$EnvPath = (Join-Path $PSScriptRoot ".env"))
    if (Test-Path $EnvPath) {
        Write-Host "  -> Nap bien moi truong tu $EnvPath..." -ForegroundColor Cyan
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
    } else {
        $templateEnv = Join-Path $PSScriptRoot "templates\.env.example"
        if (Test-Path $templateEnv) {
            Write-Host "  -> File .env chua tao, tham chieu gia tri mac dinh tu $templateEnv..." -ForegroundColor DarkGray
            Get-Content $templateEnv | ForEach-Object {
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
                            if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($key, "Process"))) {
                                [Environment]::SetEnvironmentVariable($key, $val, "Process")
                            }
                        }
                    }
                }
            }
        }
    }
}
Load-Env

# 4. Ham nhap lieu Get-EnvOrPrompt
function Get-EnvOrPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvName,
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [string]$Default,
        [switch]$AllowEmpty,
        [switch]$Required
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
        if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
            if ($Required) {
                throw "Error: '$EnvName' is required but cannot prompt in non-interactive session."
            }
            return ""
        }
        Write-Host "Error: '$EnvName' is required. Please provide a value." -ForegroundColor Red
    }
}

# 5. Kiem tra moi truong runtime
Write-Host "==> Kiem tra moi truong runtime..." -ForegroundColor Cyan
foreach ($tool in @("node", "npm", "git")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Loi: Khong tim thay '$tool' trong PATH. Vui long cai dat truoc."
    }
}

# 6. Cai dat cac MCP server theo lua chon
if ($EnableMemorix) {
    if (-not $SkipInstall) {
        Write-Host "==> Installing/updating Memorix globally..." -ForegroundColor Cyan
        if (-not $DryRun) {
            try { npm install -g memorix } catch { Write-Warning "Cai dat Memorix gap loi: $($_.Exception.Message)" }
        }
    }
    $shouldSetupHook = $false
    if (-not $DryRun -and [Environment]::UserInteractive -and -not $env:CI -and -not $SkipInstall) {
        $hookChoice = Read-Host "[?] Cai dat Hook tich hop Memorix vao DSH Web? [y/N]"
        if (-not [string]::IsNullOrWhiteSpace($hookChoice) -and ($hookChoice.Trim().ToLower() -eq 'y' -or $hookChoice.Trim().ToLower() -eq 'yes')) {
            $shouldSetupHook = $true
        }
    }
    if ($shouldSetupHook) {
        Write-Host "==> Configuring memorix hook for dsh..." -ForegroundColor Cyan
        $npmPrefix = ""
        try { $npmPrefix = (npm prefix -g 2>$null | Out-String).Trim() } catch {}
        if ($npmPrefix -and (Test-Path $npmPrefix) -and ($env:Path -notlike "*$npmPrefix*")) {
            $env:Path = "$npmPrefix;$env:Path"
        }
        if (-not $DryRun) {
            try { memorix setup --agent dsh --global } catch { Write-Warning "Khong the chay hook 'memorix setup --agent dsh --global': $($_.Exception.Message)" }
        }
    } else {
        if (-not $DryRun) {
            Write-Host "==> Bo qua cau hinh hook memorix cho DSH Web." -ForegroundColor DarkGray
        }
    }
}

$targetAtlassianVer = "0.23.1"
if ($installAtlassian) {
    if (-not $SkipInstall) {
        $alreadyInstalled = $false
        if (Get-Command "uv" -ErrorAction SilentlyContinue) {
            try {
                $uvToolList = (uv tool list 2>$null | Out-String)
                if ($uvToolList -match "mcp-atlassian\s+v?$targetAtlassianVer") {
                    Write-Host "  -> mcp-atlassian $targetAtlassianVer da co san trong uv tools." -ForegroundColor Green
                    $alreadyInstalled = $true
                }
            } catch {}
        }
        if (-not $alreadyInstalled -and (Get-Command "mcp-atlassian" -ErrorAction SilentlyContinue)) {
            $alreadyInstalled = $true
        }
        if (-not $alreadyInstalled) {
            Write-Host "==> Installing/updating mcp-atlassian globally via uv tool..." -ForegroundColor Cyan
            if (-not $DryRun) {
                try { uv tool install --force "mcp-atlassian==$targetAtlassianVer" } catch { Write-Warning "uv tool install mcp-atlassian failed: $($_.Exception.Message)" }
            }
        }
    }
}

$gitnexusConfig = ""
if ($installGitnexus) {
    if (-not $SkipInstall) {
        Write-Host "==> Installing/updating gitnexus globally..." -ForegroundColor Cyan
        if (-not $DryRun) {
            try { npm install -g gitnexus } catch { Write-Warning "Cai dat gitnexus gap loi: $($_.Exception.Message)" }
        }
    }
    $gn = Get-Command "gitnexus.cmd" -ErrorAction SilentlyContinue
    if (-not $gn) { $gn = Get-Command "gitnexus" -ErrorAction SilentlyContinue }
    $gnPath = if ($gn -and $gn.Source) { $gn.Source } else { "" }
    if ($gnPath -and $gnPath.EndsWith(".cmd", [System.StringComparison]::OrdinalIgnoreCase)) {
        $escaped = ($gnPath).Replace('\', '\\')
        $gitnexusConfig = @"
    command: cmd
    args:
      - /c
      - "$escaped"
      - mcp
"@
    } elseif ($gnPath -and $gnPath.EndsWith(".ps1", [System.StringComparison]::OrdinalIgnoreCase)) {
        $escaped = ($gnPath).Replace('\', '\\')
        $gitnexusConfig = @"
    command: powershell
    args:
      - -ExecutionPolicy
      - Bypass
      - -File
      - "$escaped"
      - mcp
"@
    } else {
        $gitnexusConfig = @"
    command: gitnexus
    args:
      - mcp
"@
    }
}

$context7Config = ""
if ($installContext7) {
    if (-not $SkipInstall) {
        Write-Host "==> Installing @upstash/context7-mcp globally..." -ForegroundColor Cyan
        if (-not $DryRun) {
            try { npm install -g @upstash/context7-mcp } catch { Write-Warning "Cai dat context7 gap loi: $($_.Exception.Message)" }
        }
    }
    $npmRoot = ""
    try { $npmRoot = (npm root -g 2>$null | Out-String).Trim() } catch {}
    $ctxJs = ""
    if ($npmRoot) {
        $candidate = Join-Path $npmRoot "@upstash\context7-mcp\dist\index.js"
        if (Test-Path $candidate) { $ctxJs = $candidate }
    }
    $escapedCtx = if ($ctxJs) { $ctxJs.Replace('\', '\\') } else { "index.js" }
    $context7Config = @"
    command: node
    args:
      - "$escapedCtx"
"@
}

function Get-CloakBrowserInstallDir {
    param([string]$EnvVarName = "CLOAKBROWSER_DIR")
    $envVal = [Environment]::GetEnvironmentVariable($EnvVarName, "Process")
    if (-not [string]::IsNullOrWhiteSpace($envVal)) { return $envVal.Trim() }
    return "$env:USERPROFILE\mcp-servers\cloakbrowser"
}

function Setup-CloakBrowser {
    param(
        [Parameter(Mandatory = $true)][string]$TargetDir,
        [Parameter(Mandatory = $true)][string]$SourceDir,
        [switch]$DryRun,
        [switch]$SkipInstall
    )
    $mainScript = Join-Path $TargetDir "mcp-server-full.mjs"
    if (-not $DryRun) {
        if (-not (Test-Path $TargetDir)) { if (-not $DryRun) { New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null } else { Write-Host "  -> [WhatIf] Tao thu muc: $TargetDir" -ForegroundColor DarkGray } }
        if (Test-Path $SourceDir) {
            if (-not $DryRun) { Copy-Item -Path "$SourceDir\*" -Destination $TargetDir -Recurse -Force } else { Write-Host "  -> [WhatIf] Sao chep CloakBrowser sang: $TargetDir" -ForegroundColor DarkGray }
        }
        $nodeModules = Join-Path $TargetDir "node_modules"
        if (-not $SkipInstall -and -not (Test-Path $nodeModules)) {
            Write-Host "  -> Dang chay npm install tai $TargetDir..." -ForegroundColor Cyan
            Push-Location $TargetDir
            try { npm install } catch { Write-Warning "npm install cloakbrowser failed: $($_.Exception.Message)" }
            finally { Pop-Location }
        }
    }
    return $mainScript
}

$cloakScript = ""
if ($installCloakbrowser) {
    $cbSourceDir = Join-Path $PSScriptRoot "mcp-servers\cloakbrowser"
    if (-not (Test-Path $cbSourceDir)) {
        $cbSourceDir = Join-Path (Split-Path $PSScriptRoot -Parent) "setup-omp\mcp-servers\cloakbrowser"
    }
    $cbTargetDir = Get-CloakBrowserInstallDir
    $cloakScriptPath = Setup-CloakBrowser -TargetDir $cbTargetDir -SourceDir $cbSourceDir -DryRun:$DryRun -SkipInstall:$SkipInstall
    $cloakScript = $cloakScriptPath.Replace('\', '\\')
}

# 7. Thu thap bien cau hinh web va AI Provider
$dshHost       = Get-EnvOrPrompt -EnvName "DSH_HOST" -Prompt "DSH Web Host" -Default "127.0.0.1"
$dshPort       = Get-EnvOrPrompt -EnvName "DSH_PORT" -Prompt "DSH Web Port" -Default "8080"
$dshPublicUrl  = Get-EnvOrPrompt -EnvName "DSH_PUBLIC_URL" -Prompt "DSH Public URL" -Default "http://localhost:$dshPort"
$dshTrusted    = Get-EnvOrPrompt -EnvName "DSH_TRUSTED_HOSTS" -Prompt "DSH Trusted Hosts (comma-separated)" -Default "localhost,127.0.0.1"
$dshToolsMode  = Get-EnvOrPrompt -EnvName "DSH_TOOLS_MODE" -Prompt "DSH Tools Mode" -Default "all"

$aiBaseUrl     = Get-EnvOrPrompt -EnvName "AI_BASE_URL" -Prompt "AI Base URL" -Default "http://localhost:20128/v1"
$aiKey         = Get-EnvOrPrompt -EnvName "AI_API_KEY" -Prompt "AI API Key" -Required

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

# 8. Chuan bi template cordis.patch.yml
$trustedList = ($dshTrusted -split ',' | ForEach-Object { '"' + $_.Trim() + '"' }) -join ', '
$cordisTemplatePath = Join-Path $PSScriptRoot "templates\cordis.patch.yml"
$cordisTemplate = Get-Content -Path $cordisTemplatePath -Raw -Encoding UTF8

$cordisTemplate = $cordisTemplate `
    -replace '__DSH_HOST__', $dshHost `
    -replace '__DSH_PORT__', $dshPort `
    -replace '__DSH_PUBLIC_URL__', $dshPublicUrl `
    -replace '__DSH_TRUSTED_HOSTS_YAML__', $trustedList `
    -replace '__DSH_TOOLS_MODE__', $dshToolsMode `
    -replace '__AI_BASE_URL__', $aiBaseUrl

# Memorix Block
if ($installMemorix) {
    $memorixBlock = @"
- id: mcp-memorix
  name: "@deepseek-ai/dsh-mcp-client"
  config:
    serverName: memorix
    transport: stdio
    command: memorix
    args:
      - serve
      - --mode
      - lite
"@
    $cordisTemplate = $cordisTemplate -replace '__MEMORIX_CONFIG__', $memorixBlock
} else {
    $cordisTemplate = $cordisTemplate -replace '__MEMORIX_CONFIG__', ''
}

# Gitnexus Block
if ($installGitnexus) {
    $cordisTemplate = $cordisTemplate -replace '__GITNEXUS_CONFIG__', $gitnexusConfig.TrimEnd()
}

# Context7 Block
if ($installContext7) {
    if ($ctxKey) {
        $context7Config += @"
`n    env:
      CONTEXT7_API_KEY: $ctxKey
"@
    }
    $cordisTemplate = $cordisTemplate -replace '__CONTEXT7_CONFIG__', $context7Config.TrimEnd()
}

if ($installAtlassian) {
    $cordisTemplate = $cordisTemplate `
        -replace '__JIRA_URL__', $jiraUrl `
        -replace '__JIRA_PERSONAL_TOKEN__', $jiraToken `
        -replace '__CONFLUENCE_URL__', $confUrl `
        -replace '__CONFLUENCE_PERSONAL_TOKEN__', $confToken
}

if ($installCloakbrowser) {
    $cordisTemplate = $cordisTemplate -replace '__CLOAKBROWSER_SCRIPT__', $cloakScript
}

# Resolve duong dan binary cho Agency MCP
$resolvedAgencyPath = ""
if ($installAgency) {
    if ($AgencyPath) {
        $resolvedAgencyPath = $AgencyPath
    } else {
        $agencyCmd = Get-Command "agency-mcp-server" -ErrorAction SilentlyContinue
        if ($agencyCmd) {
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
if ($installAgency) {
    $escapedAgency = $resolvedAgencyPath.Replace('\', '/')
    $cordisTemplate = $cordisTemplate -replace '__AGENCY_PATH__', $escapedAgency
}

# Loc bo cac block MCP bi tu choi
function Remove-CordisBlock {
    param([string]$Yaml, [string]$Id)
    $pattern = "(?ms)^-\s+id:\s+" + [regex]::Escape($Id) + "\r?\n.*?(?=(?:^-\s+id:|\Z))"
    return [regex]::Replace($Yaml, $pattern, '')
}

if (-not $installGitnexus) { $cordisTemplate = Remove-CordisBlock -Yaml $cordisTemplate -Id "mcp-gitnexus" }
if (-not $installAtlassian) { $cordisTemplate = Remove-CordisBlock -Yaml $cordisTemplate -Id "mcp-company-atlassian" }
if (-not $installContext7) { $cordisTemplate = Remove-CordisBlock -Yaml $cordisTemplate -Id "mcp-context7" }
if (-not $installGlab) { $cordisTemplate = Remove-CordisBlock -Yaml $cordisTemplate -Id "mcp-glab" }
if (-not $installCloakbrowser) { $cordisTemplate = Remove-CordisBlock -Yaml $cordisTemplate -Id "mcp-cloakbrowser" }
if (-not $installAgency) { $cordisTemplate = Remove-CordisBlock -Yaml $cordisTemplate -Id "mcp-agency" }

# 9. Tao credentials yaml
$credentialsYaml = @"
version: 1
refs:
  ANTHROPIC_API_KEY: $aiKey
apiKey: $aiKey
"@

# 10. Merge YAML logic
function Merge-CordisPatchYaml {
    param(
        [Parameter(Mandatory = $true)][string]$ExistingContent,
        [Parameter(Mandatory = $true)][string]$NewContent
    )
    $pattern = '(?m)^-\s+id:\s+([^\r\n]+)'
    $splitExisting = [System.Text.RegularExpressions.Regex]::Split($ExistingContent, $pattern)
    $splitNew      = [System.Text.RegularExpressions.Regex]::Split($NewContent, $pattern)

    $orderedIds = [System.Collections.Generic.List[string]]::new()
    $blocks = @{}

    for ($i = 1; $i -lt $splitExisting.Count; $i += 2) {
        $id = $splitExisting[$i].Trim()
        $body = $splitExisting[$i + 1]
        $orderedIds.Add($id)
        $blocks[$id] = "- id: $id$body"
    }

    for ($i = 1; $i -lt $splitNew.Count; $i += 2) {
        $id = $splitNew[$i].Trim()
        $body = $splitNew[$i + 1]
        if (-not $orderedIds.Contains($id)) {
            $orderedIds.Add($id)
        }
        $blocks[$id] = "- id: $id$body"
    }

    $header = $splitNew[0]
    $merged = $header.TrimEnd() + "`n"
    foreach ($id in $orderedIds) {
        $merged += $blocks[$id].TrimEnd() + "`n"
    }
    return $merged
}

function Write-ConfigFileWithConflictResolution {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$Content,
        [switch]$IsMcpYaml,
        [switch]$DryRun,
        [switch]$Force
    )
    $parentDir = Split-Path $TargetPath -Parent
    if (-not (Test-Path $parentDir)) {
        if (-not $DryRun) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null } else { Write-Host "  -> [WhatIf] Tao thu muc: $parentDir" -ForegroundColor DarkGray }
    }

    if (-not (Test-Path $TargetPath)) {
        Write-Host "  -> Tao moi: $TargetPath" -ForegroundColor Green
        if (-not $DryRun) {
            [System.IO.File]::WriteAllText($TargetPath, $Content, [System.Text.UTF8Encoding]::new($false))
        } else {
            Write-Host "  -> [WhatIf] Ghi file: $TargetPath" -ForegroundColor DarkGray
        }
        return
    }

        if ($Force) {
        Write-Host "  -> Ghi de (--Force): $TargetPath" -ForegroundColor Green
        if (-not $DryRun) {
            Copy-Item -Path $TargetPath -Destination $bak -Force
            Write-Host "     Da sao luu sang $bak" -ForegroundColor DarkGray
            [System.IO.File]::WriteAllText($TargetPath, $Content, [System.Text.UTF8Encoding]::new($false))
        } else {
            Write-Host "  -> [WhatIf] Sao luu: $bak" -ForegroundColor DarkGray
            Write-Host "  -> [WhatIf] Ghi file: $TargetPath" -ForegroundColor DarkGray
        }
        return
    }

    if ($IsMcpYaml) {
        $existing = Get-Content $TargetPath -Raw
        $merged = Merge-CordisPatchYaml -ExistingContent $existing -NewContent $Content
        Write-Host "  -> Hop nhat cau hinh vao: $TargetPath" -ForegroundColor Green
                if (-not $DryRun) {
            Copy-Item -Path $TargetPath -Destination $bak -Force
            Write-Host "     Da sao luu sang $bak" -ForegroundColor DarkGray
            [System.IO.File]::WriteAllText($TargetPath, $merged, [System.Text.UTF8Encoding]::new($false))
        } else {
            Write-Host "  -> [WhatIf] Sao luu: $bak" -ForegroundColor DarkGray
            Write-Host "  -> [WhatIf] Hop nhat va ghi file: $TargetPath" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  -> Bo qua $TargetPath (da ton tai)" -ForegroundColor Yellow
    }
}

# 11. Ghi file cau hinh
Write-Host "==> Ghi file cau hinh profile web..." -ForegroundColor Cyan
$cordisPatchPath = Join-Path $DshProfileDir "cordis.patch.yml"
Write-ConfigFileWithConflictResolution -TargetPath $cordisPatchPath -Content $cordisTemplate -IsMcpYaml -DryRun:$DryRun -Force:$isForce
Write-ConfigFileWithConflictResolution -TargetPath $CredentialsPath -Content $credentialsYaml -DryRun:$DryRun -Force:$isForce

# 12. Sao chep AGENTS.md va skills
Write-Host "==> Sao chep AGENTS.md va skills/..." -ForegroundColor Cyan
$sourceAgents = Join-Path $PSScriptRoot "templates\AGENTS.md"
$targetAgents = Join-Path $DshHome "AGENTS.md"
if (Test-Path $sourceAgents) {
    if (Test-Path $targetAgents) {
        $bakAg = Get-BackupPath -Path $targetAgents
                if ($isForce) {
            Write-Host "  -> File '$targetAgents' da ton tai. [-Force / -OverwriteAll] Tu dong sao luu va ghi de." -ForegroundColor Yellow
            if (-not $DryRun) {
                Copy-Item -Path $targetAgents -Destination $bakAg -Force
                Write-Host "     Da sao luu sang $bakAg" -ForegroundColor DarkGray
                Copy-Item -Path $sourceAgents -Destination $targetAgents -Force
            } else {
                Write-Host "  -> [WhatIf] Sao luu: $bakAg" -ForegroundColor DarkGray
                Write-Host "  -> [WhatIf] Sao chep den: $targetAgents" -ForegroundColor DarkGray
            }
        } else {
            $choice = Read-Host "[?] File '$targetAgents' da ton tai. Ban co muon [O]verwrite hay [S]kip? [O/s]"
            if (-not [string]::IsNullOrWhiteSpace($choice) -and $choice.Trim().ToLower() -eq 's') {
                Write-Host "  -> Bo qua file $targetAgents." -ForegroundColor DarkGray
            } else {
                            if (-not $DryRun) {
                    Copy-Item -Path $targetAgents -Destination $bakAg -Force
                    Write-Host "     Da sao luu sang $bakAg" -ForegroundColor DarkGray
                    Copy-Item -Path $sourceAgents -Destination $targetAgents -Force
                } else {
                    Write-Host "  -> [WhatIf] Sao luu: $bakAg" -ForegroundColor DarkGray
                    Write-Host "  -> [WhatIf] Sao chep den: $targetAgents" -ForegroundColor DarkGray
                }
                Write-Host "  -> Ghi de file $targetAgents thanh cong." -ForegroundColor Green
            }
        }
        } else {
        Write-Host "  -> Tao moi file $targetAgents thanh cong." -ForegroundColor Green
        $parent = Split-Path $targetAgents -Parent
        if (-not (Test-Path $parent)) {
            if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $parent | Out-Null } else { Write-Host "  -> [WhatIf] Tao thu muc: $parent" -ForegroundColor DarkGray }
        }
        if (-not $DryRun) {
            Copy-Item -Path $sourceAgents -Destination $targetAgents -Force
        } else {
            Write-Host "  -> [WhatIf] Sao chep den: $targetAgents" -ForegroundColor DarkGray
        }
    }
}
# Tich hop / go bo huong dan Agency trong AGENTS.md
$agencySectionPath = Join-Path $PSScriptRoot "templates\agency-agents-section.md"
if ((-not $DryRun) -and (Test-Path $targetAgents) -and (Test-Path $agencySectionPath)) {
    $agencyMarker = "<!-- agency-agents-section -->"
    $agencyHeading = "## Using Agency Agents MCP"
    $currentAgents = Get-Content -Path $targetAgents -Raw -Encoding UTF8
    if ($installAgency) {
        if ($currentAgents -notmatch [regex]::Escape($agencyMarker) -and $currentAgents -notmatch [regex]::Escape($agencyHeading)) {
            Write-Host "  -> Tich hop huong dan Agency vao $targetAgents..." -ForegroundColor Green
            $agencySectionContent = Get-Content -Path $agencySectionPath -Raw -Encoding UTF8
            Add-Content -Path $targetAgents -Value ("`r`n" + $agencySectionContent) -Encoding UTF8
        }
    } else {
        if ($currentAgents -match [regex]::Escape($agencyMarker) -or $currentAgents -match [regex]::Escape($agencyHeading) -or $currentAgents -match "## Agency: Multi-Agent Orchestration" -or $currentAgents -match "Su dung Agency Agents MCP") {
            Write-Host "  -> Go bo huong dan Agency khoi $targetAgents..." -ForegroundColor Yellow
            $cleaned = [regex]::Replace($currentAgents, '(?s)\r?\n?<!-- agency-agents-section -->.*?<!-- /agency-agents-section -->', '')
            $cleaned = [regex]::Replace($cleaned, "(?ms)\r?\n## (?:Using Agency Agents MCP|Agency: Multi-Agent Orchestration|Su dung Agency Agents MCP).*\z", "")
            [System.IO.File]::WriteAllText($targetAgents, $cleaned.TrimEnd() + "`r`n", [System.Text.UTF8Encoding]::new($false))
        }
    }
}

# Tich hop / go bo huong dan Memorix trong AGENTS.md (copy y tu OMP)
$memSectionPath = Join-Path $PSScriptRoot "templates\memorix-agents-section.md"
if ((-not $DryRun) -and (Test-Path $targetAgents) -and (Test-Path $memSectionPath)) {
    $memMarker = "Memorix: Memory and Safety Gate"
    $currentAgents = Get-Content -Path $targetAgents -Raw -Encoding UTF8
    if ($installMemorix) {
        if ($currentAgents -notmatch [regex]::Escape($memMarker)) {
            Write-Host "  -> Tich hop huong dan Memorix vao $targetAgents..." -ForegroundColor Green
            $memSectionContent = Get-Content -Path $memSectionPath -Raw -Encoding UTF8
            Add-Content -Path $targetAgents -Value ("`r`n" + $memSectionContent) -Encoding UTF8
        }
    } else {
        if ($currentAgents -match [regex]::Escape($memMarker)) {
            Write-Host "  -> Go bo huong dan Memorix khoi $targetAgents..." -ForegroundColor Yellow
            $cleaned = [regex]::Replace($currentAgents, '(?s)\r?\n?## Memorix: Memory and Safety Gate.*?<!-- /memorix-section -->', '')
            $cleaned = [regex]::Replace($cleaned, "(?ms)\r?\n## Memorix: Memory and Safety Gate.*?(?=\r?\n(?:## |<!-- )|\z)", "")
            [System.IO.File]::WriteAllText($targetAgents, $cleaned.TrimEnd() + "`r`n", [System.Text.UTF8Encoding]::new($false))
        }
    }
}

$sourceSkillsDir = Join-Path $PSScriptRoot "skills"
if (-not (Test-Path $sourceSkillsDir)) {
    $sourceSkillsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "setup-omp\skills"
}
$targetSkillsDir = Join-Path $DshHome "skills"
if (Test-Path $sourceSkillsDir) {
    Write-Host "  -> Cap nhat skills/ tai $targetSkillsDir..." -ForegroundColor Green
    if (-not $DryRun) {
        if (-not (Test-Path $targetSkillsDir)) { if (-not $DryRun) { New-Item -ItemType Directory -Path $targetSkillsDir -Force | Out-Null } else { Write-Host "  -> [WhatIf] Tao thu muc: $targetSkillsDir" -ForegroundColor DarkGray } }
        if ($EnableMemorix) {
            Get-ChildItem -Path $sourceSkillsDir -Directory | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $targetSkillsDir -Recurse -Force
            }
        } else {
            Get-ChildItem -Path $sourceSkillsDir -Directory | Where-Object { $_.Name -notlike "memorix-*" } | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $targetSkillsDir -Recurse -Force
            }
            Get-ChildItem -Path $targetSkillsDir -Directory -Filter "memorix-*" -ErrorAction SilentlyContinue | ForEach-Object {
                Safe-Trash $_.FullName
            }
        }
    }
}

Write-Host "`n[OK] Bootstrap DSH Web Runner hoan tat thanh cong!" -ForegroundColor Green
