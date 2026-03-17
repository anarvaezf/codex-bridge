$ErrorActionPreference = "Stop"

$DefaultBaseDir = "."
$DefaultInstallFolderName = "codex-bridge"
$DefaultPort = "8787"
$DefaultCodexTimeout = "60000"

function Write-Header {
    Write-Host ""
    Write-Host "🚀 Codex Bridge Installer" -ForegroundColor Magenta
    Write-Host "This installer creates a fresh codex-bridge runtime installation."
    Write-Host ""
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
}

function Write-ErrorAndExit {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
    exit 1
}

function Prompt-WithDefault {
    param(
        [string]$Label,
        [string]$DefaultValue
    )

    Write-Host -NoNewline "➜ $Label " -ForegroundColor Blue
    Write-Host -NoNewline "($DefaultValue)" -ForegroundColor DarkGray
    Write-Host -NoNewline ": "

    $UserInput = Read-Host

    if ([string]::IsNullOrWhiteSpace($UserInput)) {
        return $DefaultValue
    }

    return $UserInput
}

function Expand-Path {
    param(
        [string]$InputPath
    )

    if ($InputPath -eq "~") {
        return $HOME
    }

    if ($InputPath.StartsWith("~/")) {
        return Join-Path $HOME ($InputPath.Substring(2))
    }

    if ([System.IO.Path]::IsPathRooted($InputPath)) {
        return $InputPath
    }

    return Join-Path (Get-Location) $InputPath
}

function Validate-Command {
    param(
        [string]$CommandName,
        [string]$HumanName
    )

    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit "$HumanName is not installed."
    }
}

function Copy-RuntimeFiles {
    param(
        [string]$SourceDir,
        [string]$TargetDir
    )

    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TargetDir "agents") -Force | Out-Null

    Copy-Item (Join-Path $SourceDir "package.json") (Join-Path $TargetDir "package.json") -Force
    Copy-Item (Join-Path $SourceDir "package-lock.json") (Join-Path $TargetDir "package-lock.json") -Force
    Copy-Item (Join-Path $SourceDir "server.min.js") (Join-Path $TargetDir "server.js") -Force

    Copy-Item (Join-Path $SourceDir "agents\*") (Join-Path $TargetDir "agents") -Recurse -Force
}

$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Header

$BaseDirInput = Prompt-WithDefault "Base directory (codex-bridge will be created inside)" $DefaultBaseDir
$BaseDir = Expand-Path $BaseDirInput
$TargetDir = Join-Path $BaseDir $DefaultInstallFolderName

$DefaultAgentsDir = Join-Path $TargetDir "agents"
$DefaultTempWorkspacesDir = Join-Path $TargetDir "temp-workspaces"

Write-Host ""
Write-Info "Source directory: $SourceDir"
Write-Info "Base directory: $BaseDir"
Write-Info "Install directory: $TargetDir"

if (Test-Path $TargetDir) {
    Write-ErrorAndExit "$TargetDir already exists."
}

Validate-Command "node" "Node.js"
Validate-Command "npm" "npm"
Validate-Command "codex" "Codex CLI"

if (-not (Test-Path (Join-Path $SourceDir "server.min.js"))) {
    Write-ErrorAndExit "server.min.js was not found."
    Write-Host "Run 'npm run build' before installing."
    exit 1
}

Write-Info "Checking Codex login..."
$CodexStatus = ""
try {
    $CodexStatus = codex login status 2>&1
} catch {
    $CodexStatus = $_.Exception.Message
}

if ($CodexStatus -notmatch "Logged in") {
    Write-Host "❌ Codex CLI is not logged in." -ForegroundColor Red
    Write-Host "Run: codex login"
    Write-Host ""
    Write-Host "codex login status output:"
    Write-Host $CodexStatus
    exit 1
}

New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null

Write-Info "Copying runtime files..."
Copy-RuntimeFiles -SourceDir $SourceDir -TargetDir $TargetDir

New-Item -ItemType Directory -Path (Join-Path $TargetDir "temp-workspaces") -Force | Out-Null

Write-Host ""
Write-Host "⚙️  Configuration" -ForegroundColor Magenta
Write-Host "Press Enter to accept the default value for each field."
Write-Host ""

$PortValue = Prompt-WithDefault "Port" $DefaultPort

$AgentsDirInput = Prompt-WithDefault "Agents directory" $DefaultAgentsDir
$AgentsDirValue = Expand-Path $AgentsDirInput

$TempWorkspacesDirInput = Prompt-WithDefault "Temporary workspaces directory" $DefaultTempWorkspacesDir
$TempWorkspacesDirValue = Expand-Path $TempWorkspacesDirInput

$TimeoutValue = Prompt-WithDefault "Timeout in milliseconds" $DefaultCodexTimeout

$EnvContent = @"
PORT=$PortValue
CODEX_BRIDGE_ROOT=$TargetDir
AGENTS_DIR=$AgentsDirValue
TEMP_WORKSPACES_DIR=$TempWorkspacesDirValue
CODEX_TIMEOUT=$TimeoutValue
"@

$EnvPath = Join-Path $TargetDir ".env"
$EnvContent | Out-File -FilePath $EnvPath -Encoding utf8

New-Item -ItemType Directory -Path $TempWorkspacesDirValue -Force | Out-Null

Write-Host ""
Write-Success ".env created at:"
Write-Host $EnvPath

Write-Host ""
Write-Info "Installing dependencies..."
Set-Location $TargetDir
npm install

Write-Host ""
Write-Success "Installation complete"
Write-Host ""
Write-Host "Run:" -ForegroundColor White
Write-Host "cd `"$TargetDir`""
Write-Host "npm start"
Write-Host ""
Write-Host "URL:" -ForegroundColor White
Write-Host "http://localhost:$PortValue"