#!/bin/bash
#
# setup-jp3d-openjpeg.sh
#
# OpenJPEG JP3D (Part 10) Build Script for J2KSwift Cross-Codec Benchmarks
#
# OpenJPEG removed its JP3D (`openjp3d` / `opj_jp3d_compress` /
# `opj_jp3d_decompress`) tree after v2.0.1; it is not in current Homebrew
# packages. This script checks out the v2.0.1 tag and builds only the
# JP3D tools into a J2KSwift-local prefix so the head-to-head
# benchmark (`Scripts/jp3d_beat_openjpeg.sh`) can shell out to a known
# reference implementation.
#
# Usage:
#   ./Scripts/setup-jp3d-openjpeg.sh [options]
#
# Options:
#   --prefix DIR        Install prefix (default: $HOME/.j2kswift-tools/jp3d)
#   --build-dir DIR     Build dir (default: /tmp/openjpeg-jp3d-build)
#   --skip-if-present   No-op if the binaries already exist under --prefix
#   --clean             Remove build dir after install
#   --help              Show this help
#
# Exit codes:
#   0  Binaries present (built or already installed)
#   1  Build or install failed
#   2  Missing required tool (cmake / git / make)
#   3  Invalid arguments

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PREFIX="$HOME/.j2kswift-tools/jp3d"
BUILD_DIR="/tmp/openjpeg-jp3d-build"
SKIP_IF_PRESENT=false
CLEAN_AFTER=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)       PREFIX="$2"; shift 2 ;;
        --prefix=*)     PREFIX="${1#*=}"; shift ;;
        --build-dir)    BUILD_DIR="$2"; shift 2 ;;
        --build-dir=*)  BUILD_DIR="${1#*=}"; shift ;;
        --skip-if-present) SKIP_IF_PRESENT=true; shift ;;
        --clean)        CLEAN_AFTER=true; shift ;;
        --help)         sed -n '/^# Usage:/,/^# Exit codes:/p' "$0"; exit 0 ;;
        *)              echo "Error: Unknown option: $1" >&2; exit 3 ;;
    esac
done

log() { echo "[setup-jp3d-openjpeg] $*"; }
die() { echo "[setup-jp3d-openjpeg] ERROR: $*" >&2; exit 1; }

COMPRESS_BIN="$PREFIX/bin/opj_jp3d_compress"
DECOMPRESS_BIN="$PREFIX/bin/opj_jp3d_decompress"

if $SKIP_IF_PRESENT && [[ -x "$COMPRESS_BIN" && -x "$DECOMPRESS_BIN" ]]; then
    log "JP3D tools already present at $PREFIX/bin — skipping build."
    exit 0
fi

for tool in cmake git make; do
    command -v "$tool" >/dev/null || die "missing required tool: $tool (brew install $tool)"
done

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

SRC_DIR="$BUILD_DIR/src"
if [[ ! -d "$SRC_DIR/.git" ]]; then
    log "Cloning OpenJPEG v2.0.1 (last release with JP3D)..."
    rm -rf "$SRC_DIR"
    git clone --depth 1 --branch version.2.0.1 \
        https://github.com/uclouvain/openjpeg.git "$SRC_DIR" \
        || die "clone failed"
else
    log "OpenJPEG source already present at $SRC_DIR"
fi

mkdir -p "$BUILD_DIR/build"
cd "$BUILD_DIR/build"

log "Configuring build (JP3D only, static libs)..."
cmake "$SRC_DIR" \
    -DBUILD_JP3D=ON \
    -DBUILD_CODEC=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_C_FLAGS="-O3 -Wno-error -Wno-incompatible-pointer-types -Wno-implicit-function-declaration -Wno-int-conversion" \
    > /tmp/jp3d-cmake.log 2>&1 \
    || { tail -40 /tmp/jp3d-cmake.log; die "cmake configure failed"; }

log "Building opj_jp3d_compress and opj_jp3d_decompress..."
cmake --build . --target opj_jp3d_compress opj_jp3d_decompress \
    -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 2)" \
    > /tmp/jp3d-build.log 2>&1 \
    || { tail -40 /tmp/jp3d-build.log; die "build failed"; }

mkdir -p "$PREFIX/bin"
cp bin/opj_jp3d_compress   "$COMPRESS_BIN"
cp bin/opj_jp3d_decompress "$DECOMPRESS_BIN"

[[ -x "$COMPRESS_BIN"   ]] || die "opj_jp3d_compress not installed"
[[ -x "$DECOMPRESS_BIN" ]] || die "opj_jp3d_decompress not installed"

if $CLEAN_AFTER; then
    log "Cleaning $BUILD_DIR..."
    rm -rf "$BUILD_DIR"
fi

log ""
log "════════════════════════════════════════════════════"
log " OpenJPEG JP3D (v2.0.1) tools installed"
log "════════════════════════════════════════════════════"
log " opj_jp3d_compress:   $COMPRESS_BIN"
log " opj_jp3d_decompress: $DECOMPRESS_BIN"
log "════════════════════════════════════════════════════"
log ""
log "Add to PATH or reference directly from benchmarks:"
log "  export PATH=\"$PREFIX/bin:\$PATH\""
log ""

exit 0
