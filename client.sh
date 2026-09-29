#!/usr/bin/env bash
set -euo pipefail

VERSION="v1.2.0"
BASE_URL="https://github.com/TunGuard/client/releases/download/${VERSION}"

BINARY_NAME="tun"

die() {
    echo "Error: $*" >&2
    exit 1
}

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || \
    die "sha256sum or shasum is required"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

# ------------------------------------------------------------
# Detect Termux first.
#
# Termux uses:
#   $PREFIX/bin      -> executables
#   $HOME            -> Termux home
#
# Do NOT use ~/.local/bin for Termux.
# ------------------------------------------------------------
if [ -n "${TERMUX_VERSION:-}" ] && [ -n "${PREFIX:-}" ] && [ -d "${PREFIX}/bin" ]; then
    PLATFORM="termux"
    OS="android"
    INSTALL_DIR="${PREFIX}/bin"

# Fallback detection for Termux environments where
# TERMUX_VERSION may not be exported.
elif [ -n "${PREFIX:-}" ] &&
     [ -d "${PREFIX}/bin" ] &&
     [ -d "${PREFIX}/../home" ]; then
    PLATFORM="termux"
    OS="android"
    INSTALL_DIR="${PREFIX}/bin"

# Generic Android (non-Termux).
elif [ -n "${ANDROID_ROOT:-}" ] ||
     { [ -d "/system/bin" ] && [ -d "/system/lib" ]; }; then
    PLATFORM="android"
    OS="android"
    INSTALL_DIR="${HOME}/.local/bin"

# Desktop Linux / macOS.
else
    PLATFORM="desktop"

    case "${OS}" in
        linux|darwin)
            INSTALL_DIR="${HOME}/.local/bin"
            ;;
        *)
            die "Unsupported operating system: ${OS}"
            ;;
    esac
fi

# ------------------------------------------------------------
# Select release asset based on platform + architecture.
# ------------------------------------------------------------
if [ "${PLATFORM}" = "termux" ] || [ "${PLATFORM}" = "android" ]; then

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

URL="${BASE_URL}/${ASSET}"
CHECKSUM_URL="${URL}.sha256"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TMP_BINARY="${TMP_DIR}/${ASSET}"
TMP_CHECKSUM="${TMP_DIR}/${ASSET}.sha256"

echo "Detected:"
echo "  Platform: ${PLATFORM}"
echo "  OS:       ${OS}"
echo "  Arch:     ${ARCH}"
echo "  Asset:    ${ASSET}"
echo "  Install:  ${INSTALL_DIR}"
echo

# ------------------------------------------------------------
# Download binary.
# ------------------------------------------------------------
echo "Downloading ${ASSET}..."
curl -fL --progress-bar "${URL}" -o "${TMP_BINARY}"

# ------------------------------------------------------------
# Download checksum.
# ------------------------------------------------------------
echo "Downloading checksum..."
curl -fLsS "${CHECKSUM_URL}" -o "${TMP_CHECKSUM}"

# ------------------------------------------------------------
# Verify SHA-256.
# ------------------------------------------------------------
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
# Install.
#
# Termux:
#   $PREFIX/bin/tun-v1.2.0
#   $PREFIX/bin/tun -> tun-v1.2.0
#
# Linux/macOS:
#   ~/.local/bin/tun-v1.2.0
#   ~/.local/bin/tun -> tun-v1.2.0
# ------------------------------------------------------------
mkdir -p "${INSTALL_DIR}"

chmod 755 "${TMP_BINARY}"

VERSIONED_BINARY="${INSTALL_DIR}/tun-${VERSION}"
SYMLINK="${INSTALL_DIR}/${BINARY_NAME}"

echo "Installing binary..."

rm -f "${VERSIONED_BINARY}"
cp "${TMP_BINARY}" "${VERSIONED_BINARY}"
chmod 755 "${VERSIONED_BINARY}"

echo "Creating symlink..."

ln -sfn "${VERSIONED_BINARY}" "${SYMLINK}"

echo
echo "Installed TunGuard ${VERSION}"
echo
echo "Platform: ${PLATFORM}"
echo "Binary:   ${VERSIONED_BINARY}"
echo "Symlink:  ${SYMLINK}"
echo

# ------------------------------------------------------------
# Check whether install directory is already in PATH.
# ------------------------------------------------------------
case ":${PATH}:" in
    *:"${INSTALL_DIR}":*)
        echo "PATH: OK"
        ;;

    *)
        echo "WARNING: ${INSTALL_DIR} is not currently in PATH."
        echo

        if [ "${PLATFORM}" = "termux" ]; then
            echo "Termux normally includes \$PREFIX/bin in PATH."
            echo "If 'tun' is not found, run:"
            echo
            echo "  export PATH=\"\$PREFIX/bin:\$PATH\""
        else
            echo "Add this to your shell configuration:"
            echo
            echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        fi

        echo
        ;;
esac

echo "Run:"
echo "  tun --help"
```
