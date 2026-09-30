#!/usr/bin/env bash
set -euo pipefail

VERSION="v1.2.0"
BASE_URL="https://github.com/TunGuard/client/releases/download/${VERSION}"

BINARY_NAME="tun"

die() {
    echo "Error: $*" >&2
    exit 1
}

# ------------------------------------------------------------
# Requirements
# ------------------------------------------------------------

command -v curl >/dev/null 2>&1 || die "curl is required"

command -v sha256sum >/dev/null 2>&1 ||
command -v shasum >/dev/null 2>&1 ||
    die "sha256sum or shasum is required"

# ------------------------------------------------------------
# Detect operating system and architecture
# ------------------------------------------------------------

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

PLATFORM=""
INSTALL_DIR=""

# ------------------------------------------------------------
# Detect Termux first.
#
# Termux:
#   $PREFIX/bin
#   $HOME
# ------------------------------------------------------------

if [ -n "${TERMUX_VERSION:-}" ] &&
   [ -n "${PREFIX:-}" ] &&
   [ -d "${PREFIX}/bin" ]; then

    PLATFORM="termux"
    OS="android"
    INSTALL_DIR="${PREFIX}/bin"

# ------------------------------------------------------------
# Fallback Termux detection.
# ------------------------------------------------------------

elif [ -n "${PREFIX:-}" ] &&
     [ -d "${PREFIX}/bin" ] &&
     [ -d "${PREFIX}/../home" ]; then

    PLATFORM="termux"
    OS="android"
    INSTALL_DIR="${PREFIX}/bin"

# ------------------------------------------------------------
# Generic Android.
# ------------------------------------------------------------

elif [ -n "${ANDROID_ROOT:-}" ] ||
     { [ -d "/system/bin" ] && [ -d "/system/lib" ]; }; then

    PLATFORM="android"
    OS="android"
    INSTALL_DIR="${HOME}/.local/bin"

# ------------------------------------------------------------
# Windows / Git Bash / MSYS / MinGW.
# ------------------------------------------------------------

elif [[ "${OS}" == "mingw"* ]] ||
     [[ "${OS}" == "msys"* ]] ||
     [[ "${OS}" == "cygwin"* ]]; then

    PLATFORM="windows"
    OS="windows"

    if [ -n "${USERPROFILE:-}" ]; then
        INSTALL_DIR="${USERPROFILE}/.tunguard/bin"
    else
        INSTALL_DIR="${HOME}/.tunguard/bin"
    fi

# ------------------------------------------------------------
# Linux / macOS.
# ------------------------------------------------------------

else

    PLATFORM="desktop"

    case "${OS}" in

        linux)
            # Linux TunGuard runs as a system daemon.
            INSTALL_DIR="/usr/local/bin"
            ;;

        darwin)
            INSTALL_DIR="${HOME}/.local/bin"
            ;;

        *)
            die "Unsupported operating system: ${OS}"
            ;;

    esac

fi

# ------------------------------------------------------------
# Linux requires root because the service is system-wide.
# ------------------------------------------------------------

if [ "${PLATFORM}" = "desktop" ] &&
   [ "${OS}" = "linux" ] &&
   [ "$(id -u)" -ne 0 ]; then

    die "Linux installation must be run as root. Try: sudo bash install.sh"

fi

# ------------------------------------------------------------
# Select release asset.
# ------------------------------------------------------------

if [ "${PLATFORM}" = "termux" ] ||
   [ "${PLATFORM}" = "android" ]; then

    case "${ARCH}" in

        aarch64|arm64)
            ASSET="tun_android_arm64-v8a"
            ;;

        armv7l|armv7|arm)
            ASSET="tun_android_armeabi-v7a"
            ;;

        x86_64|amd64)
            ASSET="tun_android_x86_64"
            ;;

        *)
            die "Unsupported Android/Termux architecture: ${ARCH}"
            ;;

    esac

elif [ "${PLATFORM}" = "windows" ]; then

    case "${ARCH}" in

        x86_64|amd64)
            ASSET="tun_windows_x86_64.exe"
            ;;

        arm64|aarch64)
            ASSET="tun_windows_arm64.exe"
            ;;

        *)
            die "Unsupported Windows architecture: ${ARCH}"
            ;;

    esac

else

    case "${OS}:${ARCH}" in

        linux:x86_64|linux:amd64)
            ASSET="tun_linux_x86_64"
            ;;

        linux:aarch64|linux:arm64)
            ASSET="tun_linux_arm64"
            ;;

        darwin:arm64)
            ASSET="tun_macos_arm64"
            ;;

        darwin:x86_64|darwin:amd64)
            ASSET="tun_macos_x86_64"
            ;;

        *)
            die "Unsupported platform: OS=${OS}, architecture=${ARCH}"
            ;;

    esac

fi

# ------------------------------------------------------------
# Release URLs
# ------------------------------------------------------------

URL="${BASE_URL}/${ASSET}"
CHECKSUM_URL="${URL}.sha256"

TMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "${TMP_DIR}"
}

trap cleanup EXIT

TMP_BINARY="${TMP_DIR}/${ASSET}"
TMP_CHECKSUM="${TMP_DIR}/${ASSET}.sha256"

echo
echo "TunGuard ${VERSION}"
echo "----------------------------------------"
echo "Platform: ${PLATFORM}"
echo "OS:       ${OS}"
echo "Arch:     ${ARCH}"
echo "Asset:    ${ASSET}"
echo "Install:  ${INSTALL_DIR}"
echo

# ------------------------------------------------------------
# Download binary
# ------------------------------------------------------------

echo "Downloading ${ASSET}..."

curl -fL --progress-bar \
    "${URL}" \
    -o "${TMP_BINARY}"

# ------------------------------------------------------------
# Download checksum
# ------------------------------------------------------------

echo
echo "Downloading checksum..."

curl -fLsS \
    "${CHECKSUM_URL}" \
    -o "${TMP_CHECKSUM}"

# ------------------------------------------------------------
# Verify SHA-256
# ------------------------------------------------------------

echo
echo "Verifying SHA-256..."

EXPECTED="$(awk '{print $1}' "${TMP_CHECKSUM}")"

if [ -z "${EXPECTED}" ]; then
    die "Could not read expected SHA-256 checksum"
fi

if command -v sha256sum >/dev/null 2>&1; then

    ACTUAL="$(sha256sum "${TMP_BINARY}" | awk '{print $1}')"

else

    ACTUAL="$(shasum -a 256 "${TMP_BINARY}" | awk '{print $1}')"

fi

if [ "${EXPECTED}" != "${ACTUAL}" ]; then

    die "SHA-256 verification failed!
Expected: ${EXPECTED}
Actual:   ${ACTUAL}"

fi

echo "Checksum OK."

# ------------------------------------------------------------
# Install directory
# ------------------------------------------------------------

mkdir -p "${INSTALL_DIR}"

# ------------------------------------------------------------
# Binary paths
# ------------------------------------------------------------

if [ "${PLATFORM}" = "windows" ]; then

    VERSIONED_BINARY="${INSTALL_DIR}/tun-${VERSION}.exe"
    SYMLINK="${INSTALL_DIR}/tun.exe"

else

    VERSIONED_BINARY="${INSTALL_DIR}/tun-${VERSION}"
    SYMLINK="${INSTALL_DIR}/${BINARY_NAME}"

fi

# ------------------------------------------------------------
# Install binary
# ------------------------------------------------------------

echo
echo "Installing TunGuard..."

rm -f "${VERSIONED_BINARY}"

cp "${TMP_BINARY}" "${VERSIONED_BINARY}"

if [ "${PLATFORM}" != "windows" ]; then
    chmod 755 "${VERSIONED_BINARY}"
fi

# ------------------------------------------------------------
# Create/update executable link
#
# Windows does not use the Unix symlink approach here.
# ------------------------------------------------------------

if [ "${PLATFORM}" = "windows" ]; then

    cat > "${SYMLINK}.cmd" <<EOF
@echo off
"${VERSIONED_BINARY}" %*
EOF

    WINDOWS_COMMAND="${SYMLINK}.cmd"

else

    ln -sfn "${VERSIONED_BINARY}" "${SYMLINK}"

fi

echo "Binary installed."

# ============================================================
# Linux systemd service
# ============================================================

setup_linux_service() {

    command -v systemctl >/dev/null 2>&1 ||
        die "systemctl is required to configure the Linux service"

    SERVICE_FILE="/etc/systemd/system/tun.service"

    echo
    echo "Configuring Linux system service..."

    # --------------------------------------------------------
    # Create systemd service
    # --------------------------------------------------------

    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=TunGuard Client
Documentation=https://tunguard.github.io/docs/guides/client/
Wants=network-online.target
After=network-online.target

[Service]
Type=simple

ExecStart=${SYMLINK}

Restart=always
RestartSec=5

# Allow TunGuard time to shut down cleanly.
TimeoutStopSec=10

# Never permanently disable the service because of
# repeated crashes.
StartLimitIntervalSec=0

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "${SERVICE_FILE}"

    # --------------------------------------------------------
    # Reload systemd configuration
    # --------------------------------------------------------

    echo "Reloading systemd..."

    systemctl daemon-reload

    # --------------------------------------------------------
    # Enable service for boot
    # --------------------------------------------------------

    echo "Enabling tun.service..."

    systemctl enable tun.service

    # --------------------------------------------------------
    # Stop currently running instance if present.
    # --------------------------------------------------------

    echo "Stopping previous TunGuard instance..."

    systemctl stop tun.service 2>/dev/null || true

    # --------------------------------------------------------
    # Start current version
    # --------------------------------------------------------

    echo "Starting TunGuard..."

    systemctl start tun.service

    # --------------------------------------------------------
    # Verify service started
    # --------------------------------------------------------

    sleep 1

    if ! systemctl is-active --quiet tun.service; then

        echo
        echo "TunGuard failed to start."
        echo
        echo "Service status:"
        systemctl status tun.service --no-pager || true

        echo
        echo "Recent logs:"
        journalctl -u tun.service -n 30 --no-pager || true

        exit 1

    fi

    echo
    echo "Linux system service configured successfully."
    echo
    echo "TunGuard will:"
    echo "  - start automatically after reboot"
    echo "  - restart automatically if it exits"
    echo "  - run without a logged-in user"
    echo "  - restart 5 seconds after an unexpected exit"
    echo
    echo "Service:"
    echo "  systemctl status tun"
    echo
    echo "Start:"
    echo "  systemctl start tun"
    echo
    echo "Stop:"
    echo "  systemctl stop tun"
    echo
    echo "Restart:"
    echo "  systemctl restart tun"
    echo
    echo "Logs:"
    echo "  journalctl -u tun -f"
}

# ============================================================
# Termux startup
#
# Requires Termux:Boot to be installed.
# ============================================================

setup_termux_boot() {

    BOOT_DIR="${HOME}/.termux/boot"
    BOOT_SCRIPT="${BOOT_DIR}/tun"

    mkdir -p "${BOOT_DIR}"

    cat > "${BOOT_SCRIPT}" <<EOF
#!/data/data/com.termux/files/usr/bin/sh

sleep 5

exec "${SYMLINK}" >> "\${HOME}/tunguard.log" 2>&1
EOF

    chmod 755 "${BOOT_SCRIPT}"

    echo
    echo "Configuring Termux startup..."

    echo
    echo "Termux startup script:"
    echo "  ${BOOT_SCRIPT}"

    echo
    echo "TunGuard will start automatically when Termux:Boot launches."

    echo
    echo "Termux log:"
    echo "  ${HOME}/tunguard.log"

    echo
    echo "Important:"
    echo "Install the Termux:Boot Android app and allow Termux"
    echo "to run in the background."

}

# ============================================================
# macOS launchd service
# ============================================================

setup_macos_service() {

    PLIST_DIR="${HOME}/Library/LaunchAgents"
    PLIST_FILE="${PLIST_DIR}/com.tunguard.client.plist"

    mkdir -p "${PLIST_DIR}"

    cat > "${PLIST_FILE}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC
 "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">

<plist version="1.0">
<dict>

    <key>Label</key>
    <string>com.tunguard.client</string>

    <key>ProgramArguments</key>
    <array>
        <string>${SYMLINK}</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>${HOME}/tunguard.log</string>

    <key>StandardErrorPath</key>
    <string>${HOME}/tunguard-error.log</string>

</dict>
</plist>
EOF

    echo
    echo "Configuring macOS startup..."

    launchctl bootout \
        "gui/$(id -u)" \
        "${PLIST_FILE}" \
        2>/dev/null || true

    launchctl bootstrap \
        "gui/$(id -u)" \
        "${PLIST_FILE}"

    echo
    echo "macOS startup service enabled."

    echo
    echo "Service:"
    echo "  launchctl print gui/$(id -u)/com.tunguard.client"

    echo
    echo "Logs:"
    echo "  ${HOME}/tunguard.log"
    echo "  ${HOME}/tunguard-error.log"
}

# ============================================================
# Windows Scheduled Task
#
# Intended for Git Bash / MSYS environments.
# ============================================================

setup_windows_startup() {

    command -v schtasks.exe >/dev/null 2>&1 ||
        die "schtasks.exe was not found"

    command -v cygpath >/dev/null 2>&1 ||
        die "cygpath is required for Windows startup configuration"

    WINDOWS_BINARY="$(cygpath -w "${VERSIONED_BINARY}")"

    TASK_NAME="TunGuard"

    echo
    echo "Configuring Windows startup..."

    # --------------------------------------------------------
    # Remove previous task
    # --------------------------------------------------------

    schtasks.exe /Delete \
        /TN "${TASK_NAME}" \
        /F >/dev/null 2>&1 || true

    # --------------------------------------------------------
    # Create startup task
    # --------------------------------------------------------

    schtasks.exe /Create \
        /TN "${TASK_NAME}" \
        /TR "\"${WINDOWS_BINARY}\"" \
        /SC ONSTART \
        /RU SYSTEM \
        /RL HIGHEST \
        /F >/dev/null

    echo
    echo "Windows startup task created."

    echo
    echo "TunGuard will start automatically when Windows starts."

    echo
    echo "Task:"
    echo "  ${TASK_NAME}"

    echo
    echo "Manual task control:"
    echo "  schtasks.exe /Run /TN \"${TASK_NAME}\""
    echo "  schtasks.exe /End /TN \"${TASK_NAME}\""
}

# ============================================================
# Android without Termux
# ============================================================

setup_android() {

    echo
    echo "Android environment detected."

    echo
    echo "TunGuard was installed at:"
    echo "  ${VERSIONED_BINARY}"

    echo
    echo "Automatic boot startup is not configured because"
    echo "this is not a Termux environment."

}

# ============================================================
# Configure startup according to platform
# ============================================================

case "${PLATFORM}" in

    desktop)

        case "${OS}" in

            linux)
                setup_linux_service
                ;;

            darwin)
                setup_macos_service
                ;;

            *)
                die "Unsupported desktop operating system: ${OS}"
                ;;

        esac

        ;;

    termux)

        setup_termux_boot
        ;;

    android)

        setup_android
        ;;

    windows)

        setup_windows_startup
        ;;

    *)

        die "Unsupported platform: ${PLATFORM}"
        ;;

esac

# ============================================================
# PATH check
# ============================================================

echo
echo "Checking PATH..."

case ":${PATH}:" in

    *:"${INSTALL_DIR}":*)

        echo "PATH: OK"
        ;;

    *)

        echo "WARNING: ${INSTALL_DIR} is not currently in PATH."

        echo

        case "${PLATFORM}" in

            termux)

                echo "Termux normally includes:"
                echo "  \$PREFIX/bin"
                ;;

            windows)

                echo "Add this directory to your Windows PATH:"
                echo "  ${INSTALL_DIR}"
                ;;

            android)

                echo "Android binary location:"
                echo "  ${INSTALL_DIR}"
                ;;

            desktop)

                if [ "${OS}" = "linux" ]; then
                    echo "/usr/local/bin is normally already in PATH."
                else
                    echo "Add this to your shell configuration:"
                    echo
                    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
                fi
                ;;

        esac

        ;;

esac

# ============================================================
# Final output
# ============================================================

echo
echo "----------------------------------------"
echo "TunGuard ${VERSION} installed successfully."
echo "----------------------------------------"
echo
echo "Platform:"
echo "  ${PLATFORM}"
echo
echo "Binary:"
echo "  ${VERSIONED_BINARY}"

if [ "${PLATFORM}" = "windows" ]; then

    echo
    echo "Command:"
    echo "  ${WINDOWS_COMMAND}"

else

    echo
    echo "Command:"
    echo "  ${SYMLINK}"

fi

echo

case "${PLATFORM}" in

    desktop)

        if [ "${OS}" = "linux" ]; then

            echo "Startup:"
            echo "  systemd enabled"
            echo
            echo "Service:"
            echo "  tun.service"
            echo
            echo "Status:"
            echo "  systemctl status tun"

        elif [ "${OS}" = "darwin" ]; then

            echo "Startup:"
            echo "  launchd enabled"

        fi

        ;;

    termux)

        echo "Startup:"
        echo "  Termux:Boot configured"
        ;;

    windows)

        echo "Startup:"
        echo "  Windows Task Scheduler configured"
        ;;

    android)

        echo "Startup:"
        echo "  Manual startup required"
        ;;

esac

echo
echo "TunGuard is ready."
