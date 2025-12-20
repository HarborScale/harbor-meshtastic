param (
    [string]$HarborID,
    [string]$ApiKey,
    [string]$Version = "v0.0.3",
    [switch]$Uninstall
)

# --- CONFIG ---
$Repo = "HarborScale/harbor-meshtastic"
$InstallDir = "C:\HarborLighthouse\Plugins"
$BinaryName = "mesh_engine.exe"
$Asset = "mesh_engine_windows_amd64.exe"
$ExePath = Join-Path $InstallDir $BinaryName

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
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $OutputPath
} catch {
    Write-Host "❌ Download Failed: $_" -ForegroundColor Red
    exit 1
}

Unblock-File -Path $OutputPath

# 3. ADD TO SYSTEM PATH (Crucial for Service Visibility)
$CurrentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($CurrentPath -notlike "*$InstallDir*") {
    Write-Host "🔗 Adding to System PATH..." -ForegroundColor Cyan
    $NewPath = "$CurrentPath;$InstallDir"
    [Environment]::SetEnvironmentVariable("Path", $NewPath, "Machine")
    $Env:Path += ";$InstallDir" # Update current session too
}

# 4. REGISTER WITH LIGHTHOUSE
# Note: We now register just the binary name, not full path, because it's in the PATH
if ([string]::IsNullOrEmpty($HarborID) -or [string]::IsNullOrEmpty($ApiKey)) {
    Write-Host "✅ Installation Complete." -ForegroundColor Green
    Write-Host "👇 Run this command to start streaming:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "lighthouse --add `"
    Write-Host "  --name `"Mesh-Gateway`" `"
    Write-Host "  --source exec `"
    Write-Host "  --param command=`"$BinaryName --ttl 3600`" `" 
    Write-Host "  --param timeout_ms=30000 `"
    Write-Host "  --harbor-id `"YOUR_ID`" `"
    Write-Host "  --key `"YOUR_KEY`""
} else {
    Write-Host "🚢 Registering with Lighthouse..."
    lighthouse --add `
      --name "Mesh-Gateway" `
      --source exec `
      --param command="$BinaryName --ttl 3600" `
      --param timeout_ms=30000 `
      --harbor-id "$HarborID" `
      --key "$ApiKey"

    Write-Host "✅ Success! Meshtastic Engine installed." -ForegroundColor Green
}
