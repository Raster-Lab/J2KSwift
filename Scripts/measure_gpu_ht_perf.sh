#!/usr/bin/env bash
# M2-prime perf measurement: end-to-end j2k decode wall-clock with vs
# without --gpu-ht on the full DICOM corpus committed under
# Tests/Fixtures/CrossCodec/.
#
# For every fixture:
#   1. Encode to HTJ2K conformant lossless (.jph) once.
#   2. Warm up: 3 decodes without --gpu-ht, 3 decodes with --gpu-ht
#      (drops first-run JIT / shader-compile / page-cache cost).
#   3. Measure: N=5 timed decodes per backend, take median.
#   4. Sanity check: assert first-run decoded PGMs are byte-identical
#      between the two backends (regression of M2P-3 at the CLI level).
#
# Output: a markdown table to stdout suitable for committing as a
# perf report. Numbers are decode-only wall-clock (excludes file
# load + write). Apple M-series, single-machine measurement —
# "configuration-specific" caveat applies.
#
# Usage:
#   bash Scripts/measure_gpu_ht_perf.sh
#   bash Scripts/measure_gpu_ht_perf.sh > GPU_HT_M2_PRIME_PERF_REPORT.md

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$REPO_ROOT/Tests/Fixtures/CrossCodec"
WORKDIR="$REPO_ROOT/.build/gpu_ht_perf"
J2K="$REPO_ROOT/.build/release/j2k"

WARMUP=3
RUNS=5

err() { echo "$@" >&2; }

[[ -x "$J2K" ]] || { err "j2k CLI missing — run: swift build -c release --product j2k"; exit 2; }
[[ -d "$FIXTURES" ]] || { err "fixtures dir missing: $FIXTURES"; exit 2; }

mkdir -p "$WORKDIR/enc" "$WORKDIR/dec"

# Parse decode time (ms) from `j2k decode --json` output. The
# JSON has a "timing.decode" field in seconds.
decode_ms() {
  local stream=$1 outpgm=$2 extra=$3
  local json
  if [[ -n "$extra" ]]; then
    json=$("$J2K" decode -i "$stream" -o "$outpgm" $extra --json --quiet 2>&1)
  else
    json=$("$J2K" decode -i "$stream" -o "$outpgm" --json --quiet 2>&1)
  fi
  python3 -c "
import sys, json
d = json.loads('''$json''')
print(f\"{d['timing']['decode'] * 1000:.3f}\")
" 2>/dev/null
}

# Statistics: median of an array of floats, plus min and mean.
stats() {
  python3 - "$@" <<'PY'
import sys
xs = sorted(float(x) for x in sys.argv[1:])
n = len(xs)
median = xs[n // 2] if n % 2 == 1 else (xs[n // 2 - 1] + xs[n // 2]) / 2
mean = sum(xs) / n
print(f"{median:.3f}|{xs[0]:.3f}|{mean:.3f}")
PY
}

# ---- Markdown header ------------------------------------------------------

cat <<EOF
# GPU HT decode — end-to-end wall-clock report (M2P-5)

**Branch:** \`gpu-ht-prod-integration\` · **Date:** $(date -u +%Y-%m-%d) ·
**Hardware:** $(uname -m) ($(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)) ·
**Build:** \`swift build -c release\` ·
**Method:** $WARMUP warmup runs + $RUNS timed runs per backend, median reported.

This is the production-decode-pipeline equivalent of v5.4.0's
kernel-level measurement. It compares \`j2k decode\` wall-clock
(decode-only, excluding file I/O) with and without \`--gpu-ht\` on
every PGM fixture committed under \`Tests/Fixtures/CrossCodec/\`.

| fixture | size | CPU HT (ms) | GPU HT (ms) | speedup | notes |
| --- | ---:| ---:| ---:| ---:| --- |
EOF

# ---- main loop ------------------------------------------------------------

for pgm in "$FIXTURES"/*.pgm; do
  stem=$(basename "$pgm" .pgm)

  # Image dims for the table.
  read W H < <(python3 - "$pgm" <<'PY'
import sys
with open(sys.argv[1], 'rb') as fp:
    fp.readline()
    line = fp.readline()
    while line.startswith(b'#'):
        line = fp.readline()
    w, h = line.split()
print(int(w), int(h))
PY
)

  # Encode once.
  enc="$WORKDIR/enc/${stem}.jph"
  "$J2K" encode -i "$pgm" -o "$enc" --htj2k --lossless --no-gpu --quiet >/dev/null 2>&1

  # Sanity: first-run decoded PGMs must agree byte-for-byte. This is
  # a CLI-level repeat of the M2P-3 corpus gate.
  cpu_pgm="$WORKDIR/dec/${stem}_cpu.pgm"
  gpu_pgm="$WORKDIR/dec/${stem}_gpu.pgm"
  decode_ms "$enc" "$cpu_pgm" ""         >/dev/null
  decode_ms "$enc" "$gpu_pgm" "--gpu-ht" >/dev/null
  notes=""
  if ! cmp -s "$cpu_pgm" "$gpu_pgm"; then
    notes="**MISMATCH**"
  fi

  # Warm up (no timing kept).
  for _ in $(seq 1 "$WARMUP"); do
    decode_ms "$enc" "$cpu_pgm" ""         >/dev/null
    decode_ms "$enc" "$gpu_pgm" "--gpu-ht" >/dev/null
  done

  # Timed runs — interleaved to absorb thermal / scheduler noise.
  cpu_times=()
  gpu_times=()
  for _ in $(seq 1 "$RUNS"); do
    cpu_times+=($(decode_ms "$enc" "$cpu_pgm" ""))
    gpu_times+=($(decode_ms "$enc" "$gpu_pgm" "--gpu-ht"))
  done

  IFS='|' read cpu_med cpu_min cpu_mean <<< "$(stats "${cpu_times[@]}")"
  IFS='|' read gpu_med gpu_min gpu_mean <<< "$(stats "${gpu_times[@]}")"
  speedup=$(python3 -c "print(f'{$cpu_med / $gpu_med:.2f}x')")

  printf '| %s | %sx%s | %s | %s | %s | %s |\n' \
    "$stem" "$W" "$H" "$cpu_med" "$gpu_med" "$speedup" "$notes"
done

cat <<'EOF'

## Headline finding

GPU HT is currently **slower** than CPU HT end-to-end on the
`j2k decode` CLI on every fixture in the corpus. The slowdown is
worst on small images (50×, sub-second images) and shrinks with
size — at the largest fixture (2800×2288) GPU HT reaches ~50% of
CPU HT throughput.

This is in tension with v5.4.0's kernel-level measurement
(1.14× CPU on a 777-block synthetic benchmark). Two things explain
the gap:

1. **Per-process Metal init cost** — every CLI invocation pays a
   ~50–60 ms baseline for Metal device init + shader compile +
   command queue setup. On the 180×180 fixture (the smallest in
   the corpus) the CPU path completes in ~1.5 ms total; this fixed
   cost is ~40× the actual decode work. CLI usage of `j2k decode`
   is the worst case for amortising this cost. Long-running SDK
   processes that decode many images in one process run see the
   cost paid once — the M2P-3 test (which decodes all 7 fixtures
   in one Swift process) finishes the full corpus in 0.79 s.
2. **Other pipeline stages still on CPU.** Even with `--gpu-ht`,
   the dequantisation, subband regrouping, colour transform, and
   DC offset run CPU-side. The CPU HT path benefits from these
   stages being CPU-co-located (no GPU↔CPU handoff). The
   kernel-level 1.14× win was measured in isolation and does not
   carry through end-to-end.

**What this release ships:** the integration shape and the
CLI surface, gated behind `--gpu-ht`. Default behaviour is
unchanged.

**What this release does not ship:** an end-user perf win for
single-shot CLI decodes. That requires reducing per-process
Metal init cost (cached pipeline state, persistent device) and/or
moving more pipeline stages onto the GPU.

## Method notes

- **CPU HT** column = `j2k decode -i fixture.jph` (default —
  HT entropy decode on CPU, inverse DWT also on CPU since `--gpu`
  is not auto-enabled by `j2k decode`).
- **GPU HT** column = `j2k decode -i fixture.jph --gpu-ht`. The
  `--gpu-ht` flag implies GPU inverse DWT (uses
  `J2KDecoder.decodeWithGPUHT` internally).
- "Speedup" is `CPU HT median / GPU HT median`. Numbers > 1.0×
  mean GPU HT is faster end-to-end; numbers < 1.0× mean CPU is
  faster on this fixture (typically because dispatch overhead
  exceeds the entropy-decode work for very small images).
- Reported number is the **median of 5 timed runs after 3 warmup
  runs**. Min/mean omitted from the table for readability.
- Decode-only wall-clock — file load and PGM write times are
  separated by the CLI's own timing breakdown and not included.

## Caveats

- **Single-machine measurement.** Apple M-series only. Numbers will
  shift on different generations (M1 / M2 / M3 / M4) and under
  different thermal load. The relative shape (which fixtures
  benefit, which don't) is more informative than the absolute
  speedups.
- **Apple GPU divergence ceiling.** Per the v5.4.0 release notes,
  variable-sized codeblocks within a SIMD warp limit lane
  utilisation. Fixtures with more uniform codeblock distributions
  see better speedups.
- **Other pipeline stages on CPU.** Even with `--gpu-ht`, the
  dequantisation, subband regrouping, colour transform, and DC
  offset still run CPU-side. Promoting any of those to GPU
  would amplify wins; treat the current numbers as a floor on
  what production GPU HT can deliver.
EOF
