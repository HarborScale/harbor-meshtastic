# Requires Run as Administrator
param (
    [string]$HarborID,
    [string]$ApiKey,
    [string]$Version = "v0.0.4",
    [switch]$Uninstall
)

# --- CONFIG ---
$Repo = "HarborScale/harbor-meshtastic"
$InstallDir = "C:\HarborLighthouse\Plugins"
$BinaryName = "mesh_engine.exe"
$Asset = "mesh_engine_windows_amd64.exe"
$ExePath = Join-Path $InstallDir $BinaryName

# Check Admin (Required for Machine PATH)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Warning "❌ You must run this script as Administrator to update System PATH."
    exit 1
}

# --- 🗑️ UNINSTALL MODE ---
if ($Uninstall) {
    Write-Host "🧹 Removing Meshtastic Engine..." -ForegroundColor Yellow
    if (Test-Path $ExePath) { Remove-Item -Path $ExePath -Force }

    # Clean MACHINE Path
    $CurrentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($CurrentPath -like "*$InstallDir*") {
        $NewPathParts = $CurrentPath -split ';' | Where-Object { $_ -ne $InstallDir -and $_ -ne "" }
        $NewPath = $NewPathParts -join ';'
        [Environment]::SetEnvironmentVariable("Path", $NewPath, "Machine")
        Write-Host "✅ Removed from System PATH." -ForegroundColor Green
    }
    
    # Restart Service to clear handles
    Restart-Service "harbor-lighthouse" -ErrorAction SilentlyContinue
    return
}

# 1. SETUP
if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null }

# 2. DOWNLOAD
$DownloadUrl = "https://github.com/$Repo/releases/download/$Version/$Asset"
Write-Host "⬇️  Downloading..."
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ExePath
} catch {
    Write-Host "❌ Download Failed: $_" -ForegroundColor Red; exit 1
}
Unblock-File -Path $ExePath

# 3. ADD TO SYSTEM PATH (Crucial for Service Visibility)
$CurrentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($CurrentPath -notlike "*$InstallDir*") {
    Write-Host "🔗 Adding to System PATH..." -ForegroundColor Cyan
    $NewPath = "$CurrentPath;$InstallDir"
    [Environment]::SetEnvironmentVariable("Path", $NewPath, "Machine")
    $Env:Path += ";$InstallDir" # Update current session too
}

# 4. REGISTER & RESTART
if ($HarborID -and $ApiKey) {
    Write-Host "🚢 Registering..."
    lighthouse --add `
      --name "Mesh-Gateway" `
      --source exec `
      --param command="$BinaryName --ttl 3600" `
      --param timeout_ms=30000 `
      --harbor-id "$HarborID" `
      --key "$ApiKey"

    Write-Host "♻️  Restarting Lighthouse Service (to apply PATH)..." -ForegroundColor Yellow
    Restart-Service "harbor-lighthouse"
    
    Write-Host "✅ Success! Service is running." -ForegroundColor Green
} else {
    Write-Host "✅ Installed. Run 'lighthouse --add ...' to finish." -ForegroundColor Green
}
