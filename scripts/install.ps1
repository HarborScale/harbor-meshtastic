# Requires Run as Administrator
param (
    [string]$HarborID,
    [string]$ApiKey,
    [string]$Version = "v0.0.7",
    [switch]$Uninstall
)

# --- CONFIG ---
$Repo = "HarborScale/harbor-meshtastic"
$InstallDir = "C:\HarborLighthouse\Plugins"
$BinaryName = "mesh_engine.exe"
$Asset = "mesh_engine_windows_amd64.exe"
$ExePath = Join-Path $InstallDir $BinaryName

# --- 📢 VERBOSE BANNER ---
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "📦 Harbor Meshtastic Engine Installer" -ForegroundColor Cyan
Write-Host "🔖 Target Version: $Version" -ForegroundColor Gray
Write-Host "📂 Install Path:   $InstallDir" -ForegroundColor Gray
Write-Host "==================================================" -ForegroundColor Cyan

# Check Admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Warning "❌ Error: Please run as Administrator."
    exit 1
}

# --- STOP SERVICE ---
Write-Host "🛑 Stopping 'harbor-lighthouse' service to release file locks..." -ForegroundColor Yellow
Stop-Service "harbor-lighthouse" -ErrorAction SilentlyContinue

# --- 🗑️ UNINSTALL MODE ---
if ($Uninstall) {
    Write-Host "🧹 Uninstalling..." -ForegroundColor Yellow
    if (Test-Path $ExePath) {
        Remove-Item -Path $ExePath -Force
        Write-Host "   - Removed binary file." -ForegroundColor Gray
    }

    # Clean MACHINE Path
    $CurrentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($CurrentPath -like "*$InstallDir*") {
        $NewPathParts = $CurrentPath -split ';' | Where-Object { $_ -ne $InstallDir -and $_ -ne "" }
        $NewPath = $NewPathParts -join ';'
        [Environment]::SetEnvironmentVariable("Path", $NewPath, "Machine")
        Write-Host "   - Removed from System PATH." -ForegroundColor Gray
    }

    # Restart Service
    Write-Host "♻️  Restarting Lighthouse Service..." -ForegroundColor Yellow
    Start-Service "harbor-lighthouse" -ErrorAction SilentlyContinue
    Write-Host "✅ Uninstallation complete." -ForegroundColor Green
    return
}

# 1. SETUP
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    Write-Host "   - Created directory $InstallDir" -ForegroundColor Gray
}

# 2. DOWNLOAD
$DownloadUrl = "https://github.com/$Repo/releases/download/$Version/$Asset"
Write-Host "⬇️  Downloading version $Version..." -ForegroundColor Cyan
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ExePath
    Write-Host "   - Download complete." -ForegroundColor Gray
} catch {
    Write-Host "❌ Download Failed: $_" -ForegroundColor Red
    Write-Host "   - Restoring service before exit..." -ForegroundColor Gray
    Start-Service "harbor-lighthouse" -ErrorAction SilentlyContinue
    exit 1
}
Unblock-File -Path $ExePath

# 3. ADD TO SYSTEM PATH
$CurrentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($CurrentPath -notlike "*$InstallDir*") {
    Write-Host "🔗 Adding to System PATH..." -ForegroundColor Cyan
    $NewPath = "$CurrentPath;$InstallDir"
    [Environment]::SetEnvironmentVariable("Path", $NewPath, "Machine")
    $Env:Path += ";$InstallDir"
} else {
    Write-Host "   - System PATH already configured." -ForegroundColor Gray
}

# 4. REGISTER
if ($HarborID -and $ApiKey) {
    Write-Host "🚢 Registering new configuration with Lighthouse..." -ForegroundColor Cyan
    lighthouse --add `
      --name "Mesh-Gateway" `
      --source exec `
      --param command="$BinaryName --ttl 3600" `
      --param timeout_ms=30000 `
      --harbor-id "$HarborID" `
      --key "$ApiKey"
} else {
    Write-Host "ℹ️  Update mode (No new keys provided). Keeping existing config." -ForegroundColor Gray
}

# 5. RESTART SERVICE
Write-Host "♻️  Restarting Lighthouse Service to apply $Version..." -ForegroundColor Yellow
Start-Service "harbor-lighthouse" -ErrorAction SilentlyContinue

Write-Host "==================================================" -ForegroundColor Green
Write-Host "✅ Success! Version $Version is now active." -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
