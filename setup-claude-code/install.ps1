# install.ps1 - One-line interactive installer for setup-claude-code
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$OverwriteAll,
    [switch]$DryRun,
    [switch]$SkipInstall,
    [switch]$EnableMemorix,
    [switch]$DisableMemorix,
    [string]$ClaudeDir = "$env:USERPROFILE\.claude"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "       SETUP-CLAUDE-CODE INSTALLER - INTERACTIVE SETUP          " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Kiểm tra Claude Code CLI trong PATH
Write-Host "==> Kiểm tra Claude Code CLI trong hệ thống..." -ForegroundColor Cyan
$claudeCmd = Get-Command "claude" -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Host "[!] Claude Code CLI chưa được cài đặt trong PATH." -ForegroundColor Yellow
    $installClaudePrompt = Read-Host "Claude Code CLI chưa được cài đặt. Bạn có muốn cài đặt Claude Code chính gốc ngay bây giờ không? [Y/n]"
    if ([string]::IsNullOrWhiteSpace($installClaudePrompt) -or $installClaudePrompt.Trim().ToLower() -eq 'y') {
        # Nhận diện terminal
        $terminalType = if ($PSVersionTable.PSEdition -eq "Core") {
            "PowerShell Core (pwsh)"
        } elseif ($env:WT_SESSION) {
            "Windows Terminal ($($PSVersionTable.PSEdition))"
        } elseif ($PSVersionTable.PSVersion) {
            "Windows PowerShell"
        } else {
            "CMD / Standard Console"
        }
        Write-Host "==> Nhận diện terminal: $terminalType (PSVersion: $($PSVersionTable.PSVersion))." -ForegroundColor Cyan

        Write-Host "==> Đang cài đặt Claude Code chính thức..." -ForegroundColor Cyan
        $claudeInstalled = $false
        try {
            Write-Host "  -> Đang chạy installer chính thức của Anthropic (https://storage.googleapis.com/claude-code-dist/install.ps1)..." -ForegroundColor Cyan
            & ([scriptblock]::Create((Invoke-RestMethod -Uri "https://storage.googleapis.com/claude-code-dist/install.ps1" -UseBasicParsing)))
            $claudeInstalled = $true
        } catch {
            Write-Host "  [!] Installer chính thức gặp lỗi: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "  -> Thử cài đặt qua npm: npm install -g @anthropic-ai/claude-code..." -ForegroundColor Cyan
            if (Get-Command "npm" -ErrorAction SilentlyContinue) {
                npm install -g @anthropic-ai/claude-code
                $claudeInstalled = ($LASTEXITCODE -eq 0)
            } else {
                Write-Warning "Không tìm thấy npm trên hệ thống để cài đặt fallback."
            }
        }
        # Nạp lại $env:PATH trong session hiện tại
        Write-Host "==> Đang nạp lại biến môi trường PATH trong session hiện tại..." -ForegroundColor Cyan
        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        $npmPrefix = ""
        try {
            $npmPrefix = (npm config get prefix 2>$null).Trim()
        } catch {}

        $searchPaths = @(
            "$env:APPDATA\npm",
            "$env:LOCALAPPDATA\npm",
            $npmPrefix,
            "$env:USERPROFILE\.local\bin"
        )
        $allPaths = (@($searchPaths) + ($userPath -split ';') + ($machinePath -split ';') + ($env:PATH -split ';')) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) } |
            Select-Object -Unique
        $env:PATH = ($allPaths -join ';')

        $claudeCheck = Get-Command "claude" -ErrorAction SilentlyContinue
        if ($claudeCheck) {
            Write-Host "==> Đã nhận diện lệnh 'claude' tại: $($claudeCheck.Source)" -ForegroundColor Green
        } else {
            Write-Warning "Lệnh 'claude' chưa nhận diện được ngay qua Get-Command. Bạn có thể cần mở lại terminal sau khi cài đặt hoàn tất."
        }
    } else {
        Write-Host "[-] Đã bỏ qua cài đặt Claude Code CLI theo lựa chọn của người dùng." -ForegroundColor Yellow
    }
} else {
    Write-Host "==> Đã phát hiện Claude Code CLI tại: $($claudeCmd.Source)" -ForegroundColor Green
}

# 2. Luồng hỏi tương tác cấu hình AI Provider
Write-Host ""
Write-Host "==> Cấu hình kết nối AI Provider..." -ForegroundColor Cyan
$defaultAiUrl = "http://localhost:20128/v1"
$inputAiUrl = Read-Host "Nhập AI Base URL [Mặc định: $defaultAiUrl]"
$aiBaseUrl = if ([string]::IsNullOrWhiteSpace($inputAiUrl)) { $defaultAiUrl } else { $inputAiUrl.Trim() }

# AI_API_KEY: Mặc định không có, bắt buộc nhập
$aiApiKey = ""
while ([string]::IsNullOrWhiteSpace($aiApiKey)) {
    if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
        if (-not [string]::IsNullOrWhiteSpace($env:AI_API_KEY)) {
            $aiApiKey = $env:AI_API_KEY.Trim()
            break
        }
        throw "Lỗi: Đang chạy ở chế độ non-interactive nhưng AI API Key chưa được cung cấp qua biến môi trường `$env:AI_API_KEY`."
    }
    $inputKey = Read-Host "Nhập AI API Key (Bắt buộc)"
    if (-not [string]::IsNullOrWhiteSpace($inputKey)) {
        $aiApiKey = $inputKey.Trim()
        break
    }
    Write-Host "Lỗi: AI API Key là bắt buộc, không được để trống. Vui lòng nhập lại!" -ForegroundColor Red
}

# 3. Hỏi tương tác cài đặt Memorix
Write-Host ""
Write-Host "==> Cấu hình tiện ích bổ sung..." -ForegroundColor Cyan
if ($PSBoundParameters.ContainsKey('EnableMemorix')) {
    $enableMemorixVal = $EnableMemorix.IsPresent
} elseif ($PSBoundParameters.ContainsKey('DisableMemorix')) {
    $enableMemorixVal = -not $DisableMemorix.IsPresent
} else {
    $memorixCmd = Get-Command "memorix" -ErrorAction SilentlyContinue
    if ($memorixCmd) {
        Write-Host "==> Đã phát hiện Memorix trên hệ thống tại: $($memorixCmd.Source)" -ForegroundColor Green
    }
    $memorixPrompt = Read-Host "Bạn có muốn cài đặt Memorix (MCP & Session Memory) không? [y/N]"
    if (-not [string]::IsNullOrWhiteSpace($memorixPrompt) -and $memorixPrompt.Trim().ToLower() -eq 'y') {
        $enableMemorixVal = $true
        Write-Host "==> Đã kích hoạt cài đặt Memorix." -ForegroundColor Green
    } else {
        $enableMemorixVal = $false
        Write-Host "==> Bỏ qua cài đặt Memorix (mặc định)." -ForegroundColor Yellow
    }
}

# 4. Thiết lập biến môi trường phiên làm việc
$env:AI_BASE_URL = $aiBaseUrl
$env:AI_API_KEY = $aiApiKey

# Chuẩn bị nội dung file .env tạm thời
$envContent = @"
AI_BASE_URL=$aiBaseUrl
AI_API_KEY=$aiApiKey
"@

$zipUrl = "https://github.com/thanhpk6120/setup-claude-code/archive/refs/heads/main.zip"
$tempBase = Join-Path $env:TEMP ("claude-code-install-" + [System.Guid]::NewGuid().ToString("N"))
$zipFile = Join-Path $env:TEMP ("claude-code-repo-" + [System.Guid]::NewGuid().ToString("N") + ".zip")

try {
    # Tạo thư mục tạm
    New-Item -ItemType Directory -Path $tempBase -Force | Out-Null

    # Lưu file .env tạm thời tại thư mục gốc tạm
    $tempEnvPath = Join-Path $tempBase ".env"
    Set-Content -Path $tempEnvPath -Value $envContent -Encoding UTF8

    Write-Host "==> Đang tải gói setup-claude-code từ GitHub..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile -UseBasicParsing

    Write-Host "==> Đang giải nén tập tin..." -ForegroundColor Cyan
    Expand-Archive -Path $zipFile -DestinationPath $tempBase -Force

    $extractedRoot = Join-Path $tempBase "setup-claude-code-main"
    if (-not (Test-Path $extractedRoot)) {
        $found = Get-ChildItem -Directory $tempBase | Where-Object { $_.Name -ne "setup-claude-code-main" } | Select-Object -First 1
        if ($found) { $extractedRoot = $found.FullName }
    }

    if (-not (Test-Path $extractedRoot)) {
        throw "Lỗi: Không tìm thấy thư mục package đã giải nén trong $tempBase."
    }

    # Sao chép file .env tạm thời vào thư mục mã nguồn giải nén để bootstrap.ps1 đọc
    $extractedEnvPath = Join-Path $extractedRoot ".env"
    Copy-Item -Path $tempEnvPath -Destination $extractedEnvPath -Force

    $bootstrapScript = Join-Path $extractedRoot "bootstrap.ps1"
    if (-not (Test-Path $bootstrapScript)) {
        throw "Lỗi: Không tìm thấy bootstrap.ps1 trong gói cài đặt tại: $bootstrapScript"
    }
    # Chuẩn bị tham số gọi bootstrap.ps1
    $bootstrapParams = @{}
    if ($DryRun) { $bootstrapParams["DryRun"] = $true }
    if ($SkipInstall) { $bootstrapParams["SkipInstall"] = $true }
    if ($Force) { $bootstrapParams["Force"] = $true }
    if ($OverwriteAll) { $bootstrapParams["OverwriteAll"] = $true }
    if ($ClaudeDir) { $bootstrapParams["ClaudeDir"] = $ClaudeDir }
    if ($enableMemorixVal) {
        $bootstrapParams["EnableMemorix"] = $true
    } else {
        $bootstrapParams["DisableMemorix"] = $true
    }

    Write-Host "==> Đang khởi chạy bootstrap.ps1 với các tham số đã chọn..." -ForegroundColor Cyan
    $paramList = @()
    foreach ($key in $bootstrapParams.Keys) {
        if ($bootstrapParams[$key] -eq $true) {
            $paramList += "-$key"
        } else {
            $paramList += "-$key", "$($bootstrapParams[$key])"
        }
    }

    $psExe = Join-Path $PSHOME "pwsh.exe"
    if (-not (Test-Path $psExe)) { $psExe = Join-Path $PSHOME "powershell.exe" }
    if (-not (Test-Path $psExe)) { $psExe = "powershell" }

    $argsArray = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $bootstrapScript) + $paramList
    & $psExe $argsArray
    if ($LASTEXITCODE -ne 0) { throw "bootstrap.ps1 failed with exit code $LASTEXITCODE." }
} finally {
    Write-Host "==> Dọn dẹp tài nguyên tạm thời vào Thùng rác (Recycle Bin)..." -ForegroundColor Cyan
    Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

    if (Test-Path $zipFile) {
        try {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                $zipFile,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
            )
        } catch {
            Write-Warning "Không thể chuyển file zip tạm vào Thùng rác: $($_.Exception.Message)"
        }
    }

    if (Test-Path $tempBase) {
        try {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                $tempBase,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
            )
        } catch {
            Write-Warning "Không thể chuyển thư mục tạm vào Thùng rác: $($_.Exception.Message)"
        }
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host " CAI DAT THANH CONG CHO CLAUDE CODE!" -ForegroundColor Green
Write-Host " Da bao ve va kich hoat hook chan xoa cung (Trash Guard) cho Claude Code" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Green
