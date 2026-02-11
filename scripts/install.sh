#!/bin/bash

# --- CONFIG ---
REPO="HarborScale/harbor-meshtastic"
INSTALL_DIR="/opt/harbor-lighthouse/plugins"
BINARY_NAME="mesh_engine"
VERSION="v0.0.7"
SYMLINK_PATH="/usr/local/bin/$BINARY_NAME"

# --- 📢 VERBOSE BANNER ---
echo "=================================================="
echo "📦 Harbor Meshtastic Engine Installer"
echo "🔖 Target Version: $VERSION"
echo "📂 Install Path:   $INSTALL_DIR"
echo "=================================================="

# --- 🗑️ UNINSTALL MODE ---
if [ "$1" == "--uninstall" ]; then
    echo "🧹 Uninstalling..."

    # 1. Remove Files
    if [ -f "$INSTALL_DIR/$BINARY_NAME" ]; then
        sudo rm -f "$INSTALL_DIR/$BINARY_NAME"
        echo "   - Removed binary file."
    fi
    if [ -L "$SYMLINK_PATH" ]; then
        sudo rm -f "$SYMLINK_PATH"
        echo "   - Removed symlink."
    fi

    # 2. Restart Lighthouse
    if systemctl is-active --quiet harbor-lighthouse; then
        echo "♻️  Restarting Lighthouse to flush cache..."
        sudo systemctl restart harbor-lighthouse
    fi

    echo "✅ Uninstallation complete."
    exit 0
fi

# 1. CHECK LIGHTHOUSE
echo "🔍 Checking for Lighthouse..."
if ! command -v lighthouse &> /dev/null; then
    echo "❌ Error: Lighthouse is not installed."
    echo "👉 Run: curl -sL get.harborscale.com | sudo bash"
    exit 1
fi
echo "   - Lighthouse found."

# 2. DETECT OS/ARCH
OS=$(uname -s)
ARCH=$(uname -m)
echo "🖥️  Detected System: $OS ($ARCH)"

if [ "$OS" == "Linux" ]; then
    if [ "$ARCH" == "x86_64" ]; then ASSET="mesh_engine_linux_amd64"
    elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then ASSET="mesh_engine_linux_arm64"
    else echo "❌ Unsupported Architecture: $ARCH"; exit 1; fi
elif [ "$OS" == "Darwin" ]; then
    if [ "$ARCH" == "arm64" ]; then ASSET="mesh_engine_darwin_arm64"
    else ASSET="mesh_engine_darwin_amd64"; fi
else
    echo "❌ Unsupported OS: $OS"; exit 1
fi
echo "   - Selected Asset: $ASSET"

# 3. INSTALLATION
echo "📂 Ensuring plugin directory exists..."
sudo mkdir -p $INSTALL_DIR

echo "⬇️  Downloading version $VERSION..."
LATEST_URL="https://github.com/$REPO/releases/download/${VERSION}/$ASSET"
# We use -f to fail silently on server errors so we can catch them
if sudo curl -L -f -o "$INSTALL_DIR/$BINARY_NAME" "$LATEST_URL"; then
    echo "   - Download complete."
else
    echo "❌ Download Failed! Check your internet or if version $VERSION exists."
    exit 1
fi

sudo chmod +x "$INSTALL_DIR/$BINARY_NAME"

# Mac Quarantine Fix
if [ "$OS" == "Darwin" ]; then
    xattr -d com.apple.quarantine "$INSTALL_DIR/$BINARY_NAME" 2>/dev/null || true
fi

# 4. LINK TO PATH
echo "🔗 Linking binary to $SYMLINK_PATH..."
sudo ln -sf "$INSTALL_DIR/$BINARY_NAME" "$SYMLINK_PATH"

# 5. REGISTER (Optional)
HARBOR_ID=$1
API_KEY=$2

if [ -n "$HARBOR_ID" ] && [ -n "$API_KEY" ]; then
    echo "🚢 Registering with Lighthouse..."
    lighthouse --add \
      --name "Mesh-Gateway" \
      --source exec \
      --param command="$BINARY_NAME --ttl 3600" \
      --param timeout_ms=30000 \
      --harbor-id "$HARBOR_ID" \
      --key "$API_KEY"
else
    echo "ℹ️  Update mode (No new keys provided)."
    echo "   - Keeping existing configuration."
fi

# 6. RESTART SERVICE
echo "♻️  Restarting Lighthouse Service to apply changes..."
if [ "$OS" == "Linux" ]; then
    sudo systemctl restart harbor-lighthouse || echo "⚠️  Service not running, skipping restart."
else
    echo "⚠️  (MacOS) Please restart your lighthouse service manually."
fi

echo "=================================================="
echo "✅ Success! Version $VERSION is now active."
echo "=================================================="
