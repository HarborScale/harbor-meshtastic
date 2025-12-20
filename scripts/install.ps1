param (
    [string]$HarborID,
    [string]$ApiKey,
    [string]$Version = "v0.0.3", # Default version
    [switch]$Uninstall


)

# --- CONFIG ---
$Repo = "HarborScale/harbor-meshtastic"
# We use a safe path with NO SPACES to avoid ExecCollector issues
$InstallDir = "C:\HarborLighthouse\Plugins"
$BinaryName = "mesh_engine.exe"
$Asset = "mesh_engine_windows_amd64.exe"
$ExePath = Join-Path $InstallDir $BinaryName


# --- 🗑️ UNINSTALL MODE (BINARY ONLY) ---
if ($Uninstall) {
    Write-Host "🧹 Removing Meshtastic Engine binary only..." -ForegroundColor Yellow

    if (Test-Path $ExePath) {
        Remove-Item -Path $ExePath -Force
        Write-Host "✅ Binary removed: $ExePath" -ForegroundColor Green
    } else {
        Write-Host "ℹ️  Binary not found (already removed?)" -ForegroundColor DarkGray
    }

    return
}

# 1. CHECK LIGHTHOUSE
if (-not (Get-Command "lighthouse" -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Error: Lighthouse is not installed." -ForegroundColor Red
    Write-Host "👉 Please run: iwr get.harborscale.com | iex"
    exit 1
}

# 2. CREATE DIRECTORY
if (-not (Test-Path $InstallDir)) {
    Write-Host "📂 Creating safe install directory: $InstallDir"
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
}

# 3. DOWNLOAD
$DownloadUrl = "https://github.com/$Repo/releases/download/$Version/$Asset"
$OutputPath = Join-Path $InstallDir $BinaryName

Write-Host "⬇️  Downloading Meshtastic Engine..."
try {
    # Force TLS 1.2 for GitHub compatibility
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $OutputPath
} catch {
    Write-Host "❌ Download Failed: $_" -ForegroundColor Red
    exit 1
}

# Unblock the file (Fix Windows SmartScreen issues)
Unblock-File -Path $OutputPath

# 4. REGISTER WITH LIGHTHOUSE
if ([string]::IsNullOrEmpty($HarborID) -or [string]::IsNullOrEmpty($ApiKey)) {
    Write-Host "✅ Installation Complete." -ForegroundColor Green
    Write-Host "👇 Run this command to start streaming:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "lighthouse --add `"
    Write-Host "  --name `"Mesh-Gateway`" `"
    Write-Host "  --source exec `"
    Write-Host "  --param command=`"$OutputPath --ttl 3600`" `"
    Write-Host "  --param timeout_ms=30000 `"
    Write-Host "  --harbor-id `"YOUR_ID`" `"
    Write-Host "  --key `"YOUR_KEY`""
} else {
    Write-Host "🚢 Registering with Lighthouse..."
    # Note: We use the global 'lighthouse' command here
    lighthouse --add `
      --name "Mesh-Gateway" `
      --source exec `
      --param command="$OutputPath --ttl 3600" `
      --param timeout_ms=30000 `
      --harbor-id "$HarborID" `
      --key "$ApiKey"

    Write-Host "✅ Success! Meshtastic Engine installed at $OutputPath" -ForegroundColor Green
}
