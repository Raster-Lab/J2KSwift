#!/usr/bin/env bash
#
# build_metallib.sh — regenerate Sources/J2KMetal/default.metallib
# from Sources/J2KMetal/J2KShaders.metal.
#
# Required when J2KShaders.metal changes. The bundled metallib is
# loaded at runtime by `device.makeDefaultLibrary(bundle: .module)`
# and skips the ~50 ms MSL source-compile cost the v5.5.0 perf
# report flagged. If the metallib is stale or missing, the runtime
# falls back to source-compiling J2KMetalShaderSource.kernelSource.
#
# Requires the Metal Toolchain. Install with:
#   xcodebuild -downloadComponent MetalToolchain
#
# Usage:
#   Scripts/build_metallib.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Sources/J2KMetal/J2KShaders.metal"
OUT="$ROOT/Sources/J2KMetal/default.metallib"
TMP_AIR="$(mktemp -t J2KShaders.air.XXXXXX)"

if [ ! -f "$SRC" ]; then
    echo "error: source file not found: $SRC" >&2
    exit 1
fi

if ! xcrun -sdk macosx metal --version >/dev/null 2>&1; then
    echo "error: Metal Toolchain not installed." >&2
    echo "       run: xcodebuild -downloadComponent MetalToolchain" >&2
    exit 1
fi

echo "Compiling $SRC -> $TMP_AIR"
xcrun -sdk macosx metal -c "$SRC" -o "$TMP_AIR"

echo "Linking $TMP_AIR -> $OUT"
xcrun -sdk macosx metallib "$TMP_AIR" -o "$OUT"

rm -f "$TMP_AIR"

echo "Done. $OUT $(wc -c < "$OUT" | tr -d ' ') bytes."
echo "Commit the regenerated metallib alongside any J2KShaders.metal changes."
