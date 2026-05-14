#!/usr/bin/env bash
#
# run_canonical_bench.sh
#
# One-command runner for the canonical warm cross-codec benchmark across
# all three measurement modes (in-proc + sustained + isolated). Produces
# three host-labeled JSON files in Documentation/Benchmarks/data/, suitable
# for cross-host comparison via compare_hosts.py.
#
# Usage:
#   Scripts/benchmarks/run_canonical_bench.sh
#
# Output filenames:
#   benchmark-results-<host-model>-<j2k-version>-warm-inproc-<YYYYMMDD>.json
#   benchmark-results-<host-model>-<j2k-version>-warm-sustained-<YYYYMMDD>.json
#   benchmark-results-<host-model>-<j2k-version>-warm-isolated-<YYYYMMDD>.json
#
# Required: Kakadu, OpenJPH, Grok installed locally; j2kd daemon installed
# (`j2k daemon-install --force` if not).

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# -------- Host + version detection -------------------------------------
HOST_MODEL="$(sysctl -n hw.model 2>/dev/null | tr -d ',' || echo Unknown)"
DATE_TAG="$(date +%Y%m%d)"

echo "=== J2KSwift canonical bench runner ==="
echo "Host model: $HOST_MODEL"
echo "Date tag:   $DATE_TAG"
echo

# -------- Build release binary -----------------------------------------
echo "[1/5] Building release binary..."
swift build -c release 2>&1 | tail -3

# -------- Daemon setup -------------------------------------------------
echo "[2/5] Ensuring j2kd daemon is installed and reachable..."
if ! .build/release/j2k daemon-status > /dev/null 2>&1; then
    echo "  Installing daemon..."
    .build/release/j2k daemon-install --force
fi
.build/release/j2k daemon-status

# -------- Pick j2k version (after build so this matches the binary we're benching)
J2K_VERSION="$(.build/release/j2k --version | awk '{print $NF}')"
echo "J2K version: $J2K_VERSION"
echo

OUT_DIR="Documentation/Benchmarks/data"
mkdir -p "$OUT_DIR"

OUT_INPROC="$OUT_DIR/benchmark-results-$HOST_MODEL-$J2K_VERSION-warm-inproc-$DATE_TAG.json"
OUT_SUSTAINED="$OUT_DIR/benchmark-results-$HOST_MODEL-$J2K_VERSION-warm-sustained-$DATE_TAG.json"
OUT_ISOLATED="$OUT_DIR/benchmark-results-$HOST_MODEL-$J2K_VERSION-warm-isolated-$DATE_TAG.json"

# -------- Run all three modes ------------------------------------------
echo "[3/5] Running IN-PROC mode -> $OUT_INPROC"
python3 -u Scripts/benchmarks/cross_codec_warm_bench.py \
    --in-proc --runs 7 --warmups 2 --output "$OUT_INPROC" > /tmp/bench-inproc.log 2>&1
echo "  done: $(grep -E '^- PGM (en|de)code' /tmp/bench-inproc.log | head -2)"

echo "[4/5] Running SUSTAINED mode -> $OUT_SUSTAINED"
python3 -u Scripts/benchmarks/cross_codec_warm_bench.py \
    --runs 7 --warmups 2 --output "$OUT_SUSTAINED" > /tmp/bench-sustained.log 2>&1
echo "  done: $(grep -E '^- PGM (en|de)code' /tmp/bench-sustained.log | head -2)"

echo "[5/5] Running ISOLATED mode -> $OUT_ISOLATED"
python3 -u Scripts/benchmarks/cross_codec_warm_bench.py \
    --isolated --runs 7 --warmups 2 --output "$OUT_ISOLATED" > /tmp/bench-isolated.log 2>&1
echo "  done: $(grep -E '^- PGM (en|de)code' /tmp/bench-isolated.log | head -2)"

echo
echo "=== All three modes complete ==="
echo
echo "Artefacts:"
ls -la "$OUT_INPROC" "$OUT_SUSTAINED" "$OUT_ISOLATED"
echo
echo "Next step: copy these JSONs back to the comparison machine and run:"
echo "  python3 Scripts/benchmarks/compare_hosts.py \\"
echo "      $OUT_INPROC <other-host-inproc.json> \\"
echo "      --output Documentation/Benchmarks/CROSS_HOST_REPORT.md"
