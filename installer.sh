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

TMP_JSON="$(mktemp)"
curl -fsSL "https://api.github.com/repos/${BINARY_REPO}/releases/latest" -o "$TMP_JSON"
VERSION=$(grep -m1 '"tag_name"' "$TMP_JSON" | cut -d '"' -f4)
rm -f "$TMP_JSON"

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

    # The web dashboard is disabled by default. Let the user opt in.
    WEB_ENABLED="no"
    if [ -t 0 ]; then
        echo
        read -p "Enable the web dashboard? [y/N] " -n 1 -r WEB_REPLY </dev/tty
        echo
    fi
    if [[ $WEB_REPLY =~ ^[Yy]$ ]]; then
        WEB_ENABLED="yes"
    fi

    SSH_ENABLED="no"
    if [ -t 0 ]; then
        read -p "Enable the SSH gateway (jump host)? [y/N] " -n 1 -r SSH_REPLY </dev/tty
        echo
    fi
    if [[ $SSH_REPLY =~ ^[Yy]$ ]]; then
        SSH_ENABLED="yes"
    fi

    EXEC_ARGS=""
    if [ "$WEB_ENABLED" = "yes" ]; then
        EXEC_ARGS="$EXEC_ARGS -web"
    fi
    if [ "$SSH_ENABLED" = "yes" ]; then
        EXEC_ARGS="$EXEC_ARGS -ssh"
    fi
    EXEC_ARGS="${EXEC_ARGS# }"

    SERVICE_DESC="TunGuard - Userspace WireGuard Engine"
    if [ "$WEB_ENABLED" = "yes" ]; then
        SERVICE_DESC="$SERVICE_DESC with Web UI"
    fi
    if [ "$SSH_ENABLED" = "yes" ]; then
        SERVICE_DESC="$SERVICE_DESC & SSH Gateway"
    fi

    WEB_ENV=""
    if [ "$WEB_ENABLED" = "yes" ]; then
        WEB_ENV="Environment=WEB_USERNAME=admin
Environment=WEB_PASSWORD=tanguard"
    fi

    SSH_ENV=""
    if [ "$SSH_ENABLED" = "yes" ]; then
        SSH_ENV="Environment=SSH_USER=tanguard
Environment=SSH_PASSWORD=tanguard"
    fi

    $SUDO tee "$SERVICE_PATH" > /dev/null <<SERVICEEOF
[Unit]
Description=$SERVICE_DESC
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/tanguard${EXEC_ARGS:+ $EXEC_ARGS}
WorkingDirectory=/var/lib/tanguard
Restart=always
RestartSec=5
Environment=DATA_DIR=/var/lib/tanguard
Environment=WG_LISTEN_PORT=13231
Environment=WG_ADDRESS=10.100.0.1/24
Environment=API_LISTEN=:9000
$WEB_ENV
$SSH_ENV
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
if [ "$WEB_ENABLED" = "yes" ]; then
    echo "  Web UI:   http://yourserver:9000"
    echo "  Login:    admin / tanguard"
else
    echo "  The web dashboard is disabled by default."
    echo "  To enable it, add -web to ExecStart in $SERVICE_PATH, then:"
    echo "    sudo systemctl daemon-reload && sudo systemctl restart tanguard"
fi
echo "  Config:   edit $SERVICE_PATH"
echo
echo "Need help? https://github.com/TunGuard/tanguard-binary"
