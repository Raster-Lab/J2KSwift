#!/bin/bash
#
# setup-openjpeg.sh
#
# OpenJPEG Build and Install Script for J2KSwift Interoperability Testing
#
# Downloads, builds, and installs OpenJPEG from source as a test dependency.
# This script is intended for use in CI environments and local development.
#
# Usage:
#   ./Scripts/setup-openjpeg.sh [options]
#
# Options:
#   --version VERSION   OpenJPEG version to build (default: 2.5.0)
#   --prefix DIR        Installation prefix (default: /usr/local)
#   --build-dir DIR     Build directory (default: /tmp/openjpeg-build)
#   --skip-if-present   Skip build if opj_compress is already available
#   --clean             Remove build directory after installation
#   --help              Show this help message
#
# Exit codes:
#   0  Installation successful (or skipped if already present)
#   1  Build or installation failed
#   2  Missing required tools (cmake, make, git)
#   3  Invalid arguments

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default configuration
OPJ_VERSION="2.5.0"
PREFIX="/usr/local"
BUILD_DIR="/tmp/openjpeg-build"
SKIP_IF_PRESENT=false
CLEAN_AFTER=false

# ── Argument parsing ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            OPJ_VERSION="$2"
            shift 2
            ;;
        --version=*)
            OPJ_VERSION="${1#*=}"
            shift
            ;;
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        --prefix=*)
            PREFIX="${1#*=}"
            shift
            ;;
        --build-dir)
            BUILD_DIR="$2"
            shift 2
            ;;
        --build-dir=*)
            BUILD_DIR="${1#*=}"
            shift
            ;;
        --skip-if-present)
            SKIP_IF_PRESENT=true
            shift
            ;;
        --clean)
            CLEAN_AFTER=true
            shift
            ;;
        --help)
            sed -n '/^# Usage:/,/^# Exit codes:/p' "$0"
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            exit 3
            ;;
    esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────

log() {
    echo "[setup-openjpeg] $*"
}

die() {
    echo "[setup-openjpeg] ERROR: $*" >&2
    exit 1
}

# ── Pre-flight checks ────────────────────────────────────────────────────────

if $SKIP_IF_PRESENT; then
    if command -v opj_compress &> /dev/null && command -v opj_decompress &> /dev/null; then
        EXISTING_VERSION=$(opj_compress -h 2>&1 | grep -oP 'version\s+\K[\d.]+' || echo "unknown")
        log "OpenJPEG already installed (version: $EXISTING_VERSION). Skipping build."
        exit 0
    fi
fi

log "Setting up OpenJPEG v${OPJ_VERSION}"
log "  Prefix:    $PREFIX"
log "  Build dir: $BUILD_DIR"

# Check required tools
for tool in cmake make git; do
    if ! command -v "$tool" &> /dev/null; then
        die "Required tool '$tool' not found. Please install it first."
    fi
done

# ── Download ──────────────────────────────────────────────────────────────────

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [[ ! -d "openjpeg" ]]; then
    log "Cloning OpenJPEG repository..."
    git clone --depth 1 --branch "v${OPJ_VERSION}" \
        https://github.com/uclouvain/openjpeg.git || \
    die "Failed to clone OpenJPEG v${OPJ_VERSION}"
else
    log "OpenJPEG source already present."
fi

# ── Build ─────────────────────────────────────────────────────────────────────

cd openjpeg

log "Configuring build..."
mkdir -p build && cd build
cmake .. \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_CODEC=ON \
    -DBUILD_TESTING=OFF \
    -DBUILD_SHARED_LIBS=ON \
    || die "CMake configuration failed."

log "Building OpenJPEG..."
make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)" \
    || die "Build failed."

# ── Install ───────────────────────────────────────────────────────────────────

log "Installing OpenJPEG to $PREFIX..."
if [[ -w "$PREFIX" ]]; then
    make install || die "Installation failed."
else
    sudo make install || die "Installation failed (sudo)."
fi

# ── Verify ────────────────────────────────────────────────────────────────────

log "Verifying installation..."

OPJ_COMPRESS="${PREFIX}/bin/opj_compress"
OPJ_DECOMPRESS="${PREFIX}/bin/opj_decompress"

if [[ ! -x "$OPJ_COMPRESS" ]]; then
    # Try system PATH fallback
    OPJ_COMPRESS=$(command -v opj_compress 2>/dev/null || true)
fi
if [[ ! -x "$OPJ_DECOMPRESS" ]]; then
    OPJ_DECOMPRESS=$(command -v opj_decompress 2>/dev/null || true)
fi

if [[ -x "$OPJ_COMPRESS" ]]; then
    log "  opj_compress:   $OPJ_COMPRESS ✓"
else
    die "opj_compress not found after installation."
fi

if [[ -x "$OPJ_DECOMPRESS" ]]; then
    log "  opj_decompress: $OPJ_DECOMPRESS ✓"
else
    die "opj_decompress not found after installation."
fi

# ── Clean up ──────────────────────────────────────────────────────────────────

if $CLEAN_AFTER; then
    log "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

log ""
log "════════════════════════════════════════════"
log " OpenJPEG v${OPJ_VERSION} Installation Complete"
log "════════════════════════════════════════════"
log " opj_compress:   $OPJ_COMPRESS"
log " opj_decompress: $OPJ_DECOMPRESS"
log "════════════════════════════════════════════"
log ""
log "To run interoperability tests:"
log "  swift test --filter J2KInteroperabilityTests"
log ""

exit 0
