#!/bin/bash

# --- CONFIG ---
REPO="HarborScale/harbor-meshtastic"
INSTALL_DIR="/opt/harbor-lighthouse/plugins"
BINARY_NAME="mesh_engine"
VERSION="v0.0.3"
SYMLINK_PATH="/usr/local/bin/$BINARY_NAME"

# --- 🗑️ UNINSTALL MODE ---
if [ "$1" == "--uninstall" ]; then
    echo "🧹 Removing Meshtastic Engine binary..."
    
    # 1. Remove Files
    sudo rm -f "$INSTALL_DIR/$BINARY_NAME"
    sudo rm -f "$SYMLINK_PATH"
    echo "✅ Binary and Symlink removed."

    # 2. Restart Lighthouse to clear cache/handles
    if systemctl is-active --quiet harbor-lighthouse; then
        echo "♻️  Restarting Lighthouse service..."
        sudo systemctl restart harbor-lighthouse
    fi

    echo "✅ Uninstallation complete."
    exit 0
fi

# 1. CHECK LIGHTHOUSE
if ! command -v lighthouse &> /dev/null; then
    echo "❌ Error: Lighthouse is not installed."
    echo "👉 Run: curl -sL get.harborscale.com | sudo bash"
    exit 1
fi

# 2. DETECT OS/ARCH & SET ASSET
OS=$(uname -s)
ARCH=$(uname -m)

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

# 3. INSTALLATION
echo "📂 Ensuring plugin directory: $INSTALL_DIR"
sudo mkdir -p $INSTALL_DIR

echo "⬇️  Downloading $ASSET..."
LATEST_URL="https://github.com/$REPO/releases/download/${VERSION}/$ASSET"
sudo curl -L -o "$INSTALL_DIR/$BINARY_NAME" "$LATEST_URL"
sudo chmod +x "$INSTALL_DIR/$BINARY_NAME"

# Mac Quarantine Fix
if [ "$OS" == "Darwin" ]; then
    xattr -d com.apple.quarantine "$INSTALL_DIR/$BINARY_NAME" 2>/dev/null || true
fi

# 4. LINK TO PATH (CRITICAL STEP)
echo "🔗 Linking binary to /usr/local/bin..."
sudo ln -sf "$INSTALL_DIR/$BINARY_NAME" "$SYMLINK_PATH"

# 5. REGISTER & RESTART
HARBOR_ID=$1
API_KEY=$2

if [ -z "$HARBOR_ID" ] || [ -z "$API_KEY" ]; then
    echo "✅ Installed to PATH."
    echo "👇 To configure manually:"
    echo "lighthouse --add --name \"Mesh-Gateway\" --source exec --param command=\"$BINARY_NAME --ttl 3600\" --harbor-id \"ID\" --key \"KEY\""
else
    echo "🚢 Registering with Lighthouse..."
    lighthouse --add \
      --name "Mesh-Gateway" \
      --source exec \
      --param command="$BINARY_NAME --ttl 3600" \
      --param timeout_ms=30000 \
      --harbor-id "$HARBOR_ID" \
      --key "$API_KEY"
    
    # Restart is required for the service to see the new PATH/Symlink if it was just created
    echo "♻️  Restarting Lighthouse Service..."
    if [ "$OS" == "Linux" ]; then
        sudo systemctl restart harbor-lighthouse
    else
        # Mac/Manual restart
        echo "⚠️  Please restart your lighthouse service manually to pick up the new PATH."
    fi
    
    echo "✅ Success!"
fi
