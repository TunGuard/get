#!/usr/bin/env bash

set -euo pipefail

BINARY_REPO="TunGuard/tanguard-binary"
INSTALL_PATH="/usr/local/bin/tanguard"
SERVICE_PATH="/etc/systemd/system/tanguard.service"
DATA_DIR="/var/lib/tanguard"

# Determine whether sudo is needed
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# Check dependencies
command -v curl >/dev/null 2>&1 || {
    echo "Error: curl is required."
    exit 1
}

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$OS" in
    linux) ;;
    *)
        echo "Unsupported operating system: $OS"
        exit 1
        ;;
esac

case "$ARCH" in
    x86_64)
        FILE="tanguard-linux-amd64"
        ;;
    aarch64|arm64)
        FILE="tanguard-linux-arm64"
        ;;
    i386|i686)
        FILE="tanguard-linux-386"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo "Fetching latest release..."

VERSION=$(curl -fsSL "https://api.github.com/repos/${BINARY_REPO}/releases/latest" \
    | grep -m1 '"tag_name"' \
    | cut -d '"' -f4 || true)

if [ -z "$VERSION" ]; then
    echo "Failed to determine the latest release."
    exit 1
fi

DOWNLOAD_URL="https://github.com/${BINARY_REPO}/releases/download/${VERSION}/${FILE}"

TMP_FILE="$(mktemp)"

echo "Downloading ${FILE} (${VERSION})..."

curl -fL "$DOWNLOAD_URL" -o "$TMP_FILE"

$SUDO install -m 755 "$TMP_FILE" "$INSTALL_PATH"

rm -f "$TMP_FILE"

echo
echo "✓ TunGuard installed successfully!"
echo "Version : $VERSION"
echo "Binary  : $INSTALL_PATH"

# Ask about systemd service (read from /dev/tty to work with pipe installs)
echo
REPLY=y
if [ -t 0 ]; then
    read -p "Set up as a systemd service? [Y/n] " -n 1 -r REPLY </dev/tty
    echo
fi
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    $SUDO mkdir -p "$DATA_DIR"

    $SUDO tee "$SERVICE_PATH" > /dev/null <<'SERVICEEOF'
[Unit]
Description=TunGuard - Userspace WireGuard Engine with Web UI & SSH Gateway
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/tanguard -web -ssh
WorkingDirectory=/var/lib/tanguard
Restart=always
RestartSec=5
Environment=DATA_DIR=/var/lib/tanguard
Environment=WG_LISTEN_PORT=13231
Environment=WG_ADDRESS=10.100.0.1/24
Environment=API_LISTEN=:9000
Environment=WEB_USERNAME=admin
Environment=WEB_PASSWORD=tanguard
Environment=SSH_USER=tanguard
Environment=SSH_PASSWORD=tanguard

NoNewPrivileges=false
ProtectSystem=false

[Install]
WantedBy=multi-user.target
SERVICEEOF

    $SUDO systemctl daemon-reload
    $SUDO systemctl enable tanguard
    $SUDO systemctl start tanguard

    echo
    echo "✓ systemd service installed and started!"
    echo
    $SUDO systemctl status tanguard --no-pager
fi

echo
echo "Quick start:"
echo "  Web UI:   http://yourserver:9000"
echo "  Login:    admin / tanguard"
echo "  Config:   edit /etc/systemd/system/tanguard.service"
echo
echo "Need help? https://github.com/TunGuard/tanguard-binary"
