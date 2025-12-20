#!/bin/bash

# --- CONFIG ---
REPO="HarborScale/harbor-meshtastic"
INSTALL_DIR="/opt/harbor-lighthouse/plugins"
BINARY_NAME="mesh_engine"
VERSION="v0.0.3"
SYMLINK_PATH="/usr/local/bin/$BINARY_NAME"

# --- 🗑️ UNINSTALL MODE (BINARY ONLY) ---
if [ "$1" == "--uninstall" ]; then
    echo "🧹 Removing Meshtastic Engine binary..."

    INSTALL_PATH="$INSTALL_DIR/$BINARY_NAME"

    # 1. Remove the binary file
    if [ -f "$INSTALL_PATH" ]; then
        sudo rm -f "$INSTALL_PATH"
        echo "✅ Binary removed from $INSTALL_PATH"
    fi
    
    # 2. Remove the Symlink (Clean up PATH)
    if [ -L "$SYMLINK_PATH" ]; then
        sudo rm -f "$SYMLINK_PATH"
        echo "✅ Symlink removed from $SYMLINK_PATH"
    fi

    echo "✅ Uninstallation complete."
    exit 0
fi

# 1. CHECK LIGHTHOUSE
if ! command -v lighthouse &> /dev/null; then
    echo "❌ Error: Lighthouse is not installed."
    echo "👉 Please run: curl -sL get.harborscale.com | sudo bash"
    exit 1
fi

# 2. DETECT OS & ARCH
OS=$(uname -s)
ARCH=$(uname -m)

if [ "$OS" == "Linux" ]; then
    if [ "$ARCH" == "x86_64" ]; then
        ASSET="mesh_engine_linux_amd64"
    elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
        ASSET="mesh_engine_linux_arm64"
    else
        echo "❌ Unsupported Architecture: $ARCH"
        exit 1
    fi
elif [ "$OS" == "Darwin" ]; then
    # Mac Support (Apple Silicon & Intel)
    if [ "$ARCH" == "arm64" ]; then
        ASSET="mesh_engine_darwin_arm64"
    else
        ASSET="mesh_engine_darwin_amd64"
    fi
else
    echo "❌ Unsupported OS: $OS"
    exit 1
fi

# 3. GET LATEST URL
LATEST_URL="https://github.com/$REPO/releases/download/${VERSION}/$ASSET"

# 4. INSTALLATION
echo "📂 Creating plugin directory: $INSTALL_DIR"
if [ ! -d "$INSTALL_DIR" ]; then
    sudo mkdir -p $INSTALL_DIR
    sudo chown $(id -u):$(id -g) $INSTALL_DIR
fi

echo "⬇️  Downloading $ASSET..."
curl -L -o "$INSTALL_DIR/$BINARY_NAME" "$LATEST_URL"
chmod +x "$INSTALL_DIR/$BINARY_NAME"

# Remove Apple Quarantine if on Mac
if [ "$OS" == "Darwin" ]; then
    xattr -d com.apple.quarantine "$INSTALL_DIR/$BINARY_NAME" 2>/dev/null || true
fi

# --- NEW: ADD TO PATH (Symlink) ---
echo "🔗 Linking binary to PATH..."
# We force (-f) the link in case it already exists or updates
if sudo ln -sf "$INSTALL_DIR/$BINARY_NAME" "$SYMLINK_PATH"; then
    echo "✅ $BINARY_NAME is now available globally."
else
    echo "⚠️  Could not create symlink. You may need to run this with sudo."
fi

# 5. REGISTER WITH LIGHTHOUSE
HARBOR_ID=$1
API_KEY=$2

if [ -z "$HARBOR_ID" ] || [ -z "$API_KEY" ]; then
    echo "✅ Installation Complete."
    echo "👇 Run this command manually to finish setup:"
    echo ""
    echo "lighthouse --add \\"
    echo "  --name \"Mesh-Gateway\" \\"
    echo "  --source exec \\"
    echo "  --param command=\"$BINARY_NAME --ttl 3600\" \\" # Note: Changed to use global bin name
    echo "  --param timeout_ms=30000 \\"
    echo "  --harbor-id \"YOUR_ID\" \\"
    echo "  --key \"YOUR_KEY\""
else
    echo "🚢 Registering with Lighthouse..."
    lighthouse --add \
      --name "Mesh-Gateway" \
      --source exec \
      --param command="$BINARY_NAME --ttl 3600" \
      --param timeout_ms=30000 \
      --harbor-id "$HARBOR_ID" \
      --key "$API_KEY"

    echo "✅ Success! Meshtastic Engine installed and running."
fi
