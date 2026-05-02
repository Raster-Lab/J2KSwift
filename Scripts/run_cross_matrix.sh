#!/usr/bin/env bash
# Cross-codec, cross-backend bit-exactness matrix on the 7 DICOM PGM
# fixtures committed under Tests/Fixtures/CrossCodec/.
#
# For every fixture, exercises the full encode×decode matrix:
#
#   Encoded by      | Decoded by                | Codec mode
#   ----------------+---------------------------+-------------
#   J2KSwift CPU    | J2KSwift CPU              | J2K Part 1 LL
#   J2KSwift CPU    | J2KSwift GPU              | J2K Part 1 LL
#   J2KSwift GPU    | J2KSwift CPU              | J2K Part 1 LL
#   J2KSwift GPU    | J2KSwift GPU              | J2K Part 1 LL
#   J2KSwift CPU    | OpenJPEG                  | J2K Part 1 LL
#   J2KSwift GPU    | OpenJPEG                  | J2K Part 1 LL
#   OpenJPEG        | J2KSwift CPU              | J2K Part 1 LL
#   OpenJPEG        | J2KSwift GPU              | J2K Part 1 LL
#   OpenJPEG        | OpenJPEG (baseline)       | J2K Part 1 LL
#   ---- HTJ2K -------------------------------------------------
#   J2KSwift CPU    | J2KSwift CPU              | HTJ2K LL
#   J2KSwift CPU    | J2KSwift GPU              | HTJ2K LL
#   J2KSwift CPU    | J2KSwift GPU-HT           | HTJ2K LL  (M2-prime)
#   J2KSwift GPU    | J2KSwift CPU              | HTJ2K LL
#   J2KSwift GPU    | J2KSwift GPU              | HTJ2K LL
#   J2KSwift GPU    | J2KSwift GPU-HT           | HTJ2K LL  (M2-prime)
#   J2KSwift CPU    | OpenJPH                   | HTJ2K LL
#   J2KSwift GPU    | OpenJPH                   | HTJ2K LL
#   OpenJPH         | J2KSwift CPU              | HTJ2K LL
#   OpenJPH         | J2KSwift GPU              | HTJ2K LL
#   OpenJPH         | J2KSwift GPU-HT           | HTJ2K LL  (M2-prime)
#   OpenJPH         | OpenJPH (baseline)        | HTJ2K LL
#
# Result is byte-equality of the decoded PGM against the original PGM
# (`yes`), or byte-swap-equality (`swap`, when the cross-codec uses a
# different PGM byte order — see RELEASE_READINESS_REPORT.md).
#
# Usage:
#   scripts/run_cross_matrix.sh                      # run, write CSV to .build/cross_matrix/results.csv
#   scripts/run_cross_matrix.sh --check              # run + diff against Tests/Fixtures/CrossCodec/expected_results.csv; exit 1 if any cell regressed
#   scripts/run_cross_matrix.sh --update-baseline    # run + overwrite expected_results.csv
#
# Required tools (must be on $PATH):
#   - the j2k CLI (built via `swift build -c release --product j2k`)
#   - opj_compress / opj_decompress  (OpenJPEG)
#   - ojph_compress / ojph_expand    (OpenJPH)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$REPO_ROOT/Tests/Fixtures/CrossCodec"
BASELINE_FULL="$FIXTURES/expected_results.csv"
BASELINE_CPU="$FIXTURES/expected_results_cpu.csv"
WORKDIR="$REPO_ROOT/.build/cross_matrix"

J2K="$REPO_ROOT/.build/release/j2k"
OPJ_ENC="$(command -v opj_compress  || true)"
OPJ_DEC="$(command -v opj_decompress || true)"
OJPH_ENC="$(command -v ojph_compress || true)"
OJPH_DEC="$(command -v ojph_expand   || true)"

MODE=run
CPU_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --check)            MODE=check ;;
    --update-baseline)  MODE=update_baseline ;;
    --cpu-only)         CPU_ONLY=1 ;;
    run | "")           MODE=run ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

err() { echo "$@" >&2; }

# ---- environment sanity ---------------------------------------------------
[[ -x "$J2K" ]]       || { err "j2k CLI missing at $J2K — run: swift build -c release --product j2k"; exit 2; }
[[ -n "$OPJ_ENC"  ]]  || { err "opj_compress not on PATH (install openjpeg)"; exit 2; }
[[ -n "$OPJ_DEC"  ]]  || { err "opj_decompress not on PATH (install openjpeg)"; exit 2; }
[[ -n "$OJPH_ENC" ]]  || { err "ojph_compress not on PATH (install openjph)"; exit 2; }
[[ -n "$OJPH_DEC" ]]  || { err "ojph_expand not on PATH (install openjph)"; exit 2; }
[[ -d "$FIXTURES" ]]  || { err "fixtures directory missing: $FIXTURES"; exit 2; }

mkdir -p "$WORKDIR/enc" "$WORKDIR/dec"
CSV="$WORKDIR/results.csv"
BASELINE=$BASELINE_FULL
[[ $CPU_ONLY -eq 1 ]] && BASELINE=$BASELINE_CPU

if [[ $CPU_ONLY -eq 1 ]]; then
  CELLS=(
    jcpu_to_jcpu_p1 jcpu_to_opj_p1 opj_to_jcpu_p1 opj_to_opj_p1
    jcpu_to_jcpu_ht jcpu_to_ojph_ht ojph_to_jcpu_ht ojph_to_ojph_ht
  )
else
  CELLS=(
    jcpu_to_jcpu_p1 jcpu_to_jgpu_p1 jgpu_to_jcpu_p1 jgpu_to_jgpu_p1
    jcpu_to_opj_p1  jgpu_to_opj_p1  opj_to_jcpu_p1  opj_to_jgpu_p1  opj_to_opj_p1
    jcpu_to_jcpu_ht jcpu_to_jgpu_ht jcpu_to_jght_ht jgpu_to_jcpu_ht jgpu_to_jgpu_ht jgpu_to_jght_ht
    jcpu_to_ojph_ht jgpu_to_ojph_ht ojph_to_jcpu_ht ojph_to_jgpu_ht ojph_to_jght_ht ojph_to_ojph_ht
  )
fi

# CSV header
{
  printf 'file,modality,width,height'
  for c in "${CELLS[@]}"; do printf ',%s' "$c"; done
  echo
} > "$CSV"

# Compare PGM PIXEL data only — different decoders inject different
# header comments, and 16-bit PGM has the LE/BE byte-order ambiguity
# documented in RELEASE_READINESS_REPORT.md. Either equality => same
# pixel values, codestream is correct.
cmp_or_no() {
  python3 - "$1" "$2" <<'PY' 2>/dev/null
import sys
def pixels(path):
    with open(path, 'rb') as fp:
        if fp.readline() != b'P5\n': raise SystemExit(2)
        line = fp.readline()
        while line.startswith(b'#'): line = fp.readline()
        fp.readline()  # maxval
        return fp.read()
try:
    a = pixels(sys.argv[1]); b = pixels(sys.argv[2])
    if a == b:
        print('yes')
    elif len(a) == len(b) and len(a) % 2 == 0 and \
         bytes(b for pair in zip(b[1::2], b[0::2]) for b in pair) == a:
        print('swap')
    else:
        print('no')
except Exception:
    print('no')
PY
}

# Per-image dimensions for the CSV.
read_dims() {
  python3 - "$1" <<'PY'
import sys
with open(sys.argv[1], 'rb') as fp:
    fp.readline()
    line = fp.readline()
    while line.startswith(b'#'):
        line = fp.readline()
    w, h = line.split()
print(int(w), int(h))
PY
}

# ---- main loop ------------------------------------------------------------
for pgm in "$FIXTURES"/*.pgm; do
  stem=$(basename "$pgm" .pgm)
  mod=${stem%%_*}
  read W H < <(read_dims "$pgm")
  echo ""
  echo "=== $stem ==="

  # ---- encode side ----
  "$J2K"     encode -i "$pgm" -o "$WORKDIR/enc/${stem}_jcpu_p1.j2k" --lossless --no-gpu --quiet
  "$OPJ_ENC" -i "$pgm" -o "$WORKDIR/enc/${stem}_opj_p1.j2k"  -r 1 >/dev/null 2>&1
  "$J2K"     encode -i "$pgm" -o "$WORKDIR/enc/${stem}_jcpu_ht.j2k" --lossless --htj2k --no-gpu --quiet
  "$OJPH_ENC" -i "$pgm" -o "$WORKDIR/enc/${stem}_ojph_ht.j2c" -reversible true >/dev/null 2>&1
  if [[ $CPU_ONLY -eq 0 ]]; then
    "$J2K" encode -i "$pgm" -o "$WORKDIR/enc/${stem}_jgpu_p1.j2k" --lossless --gpu    --quiet
    "$J2K" encode -i "$pgm" -o "$WORKDIR/enc/${stem}_jgpu_ht.j2k" --lossless --htj2k --gpu    --quiet
  fi

  # ---- decode helpers ----
  decode_j2k() {
    local stream=$1 backend=$2 outpgm=$3
    case "$backend" in
      gpu)   "$J2K" decode -i "$stream" -o "$outpgm" --gpu    --quiet >/dev/null 2>&1 ;;
      gpuht) "$J2K" decode -i "$stream" -o "$outpgm" --gpu-ht --quiet >/dev/null 2>&1 ;;
      *)     "$J2K" decode -i "$stream" -o "$outpgm" --no-gpu --quiet >/dev/null 2>&1 ;;
    esac
  }

  P=$WORKDIR/dec/${stem}; rm -f "${P}"_*.pgm

  # CPU-only cells (always run)
  decode_j2k  "$WORKDIR/enc/${stem}_jcpu_p1.j2k" cpu "${P}_jcpu_to_jcpu_p1.pgm"
  "$OPJ_DEC"  -i "$WORKDIR/enc/${stem}_jcpu_p1.j2k" -o "${P}_jcpu_to_opj_p1.pgm" >/dev/null 2>&1
  decode_j2k  "$WORKDIR/enc/${stem}_opj_p1.j2k"  cpu "${P}_opj_to_jcpu_p1.pgm"
  "$OPJ_DEC"  -i "$WORKDIR/enc/${stem}_opj_p1.j2k" -o "${P}_opj_to_opj_p1.pgm"  >/dev/null 2>&1
  decode_j2k  "$WORKDIR/enc/${stem}_jcpu_ht.j2k" cpu "${P}_jcpu_to_jcpu_ht.pgm"
  "$OJPH_DEC" -i "$WORKDIR/enc/${stem}_jcpu_ht.j2k" -o "${P}_jcpu_to_ojph_ht.pgm" >/dev/null 2>&1
  decode_j2k  "$WORKDIR/enc/${stem}_ojph_ht.j2c" cpu "${P}_ojph_to_jcpu_ht.pgm"
  "$OJPH_DEC" -i "$WORKDIR/enc/${stem}_ojph_ht.j2c" -o "${P}_ojph_to_ojph_ht.pgm" >/dev/null 2>&1

  R_jcpu_to_jcpu_p1=$(cmp_or_no "$pgm" "${P}_jcpu_to_jcpu_p1.pgm")
  R_jcpu_to_opj_p1=$(cmp_or_no  "$pgm" "${P}_jcpu_to_opj_p1.pgm")
  R_opj_to_jcpu_p1=$(cmp_or_no  "$pgm" "${P}_opj_to_jcpu_p1.pgm")
  R_opj_to_opj_p1=$(cmp_or_no   "$pgm" "${P}_opj_to_opj_p1.pgm")
  R_jcpu_to_jcpu_ht=$(cmp_or_no "$pgm" "${P}_jcpu_to_jcpu_ht.pgm")
  R_jcpu_to_ojph_ht=$(cmp_or_no "$pgm" "${P}_jcpu_to_ojph_ht.pgm")
  R_ojph_to_jcpu_ht=$(cmp_or_no "$pgm" "${P}_ojph_to_jcpu_ht.pgm")
  R_ojph_to_ojph_ht=$(cmp_or_no "$pgm" "${P}_ojph_to_ojph_ht.pgm")

  if [[ $CPU_ONLY -eq 1 ]]; then
    echo "$stem,$mod,$W,$H,$R_jcpu_to_jcpu_p1,$R_jcpu_to_opj_p1,$R_opj_to_jcpu_p1,$R_opj_to_opj_p1,$R_jcpu_to_jcpu_ht,$R_jcpu_to_ojph_ht,$R_ojph_to_jcpu_ht,$R_ojph_to_ojph_ht" >> "$CSV"
    printf '  P1: jc/jc=%s | jc/o=%s o/jc=%s o/o=%s\n' \
      "$R_jcpu_to_jcpu_p1" "$R_jcpu_to_opj_p1" "$R_opj_to_jcpu_p1" "$R_opj_to_opj_p1"
    printf '  HT: jc/jc=%s | jc/o=%s o/jc=%s o/o=%s\n' \
      "$R_jcpu_to_jcpu_ht" "$R_jcpu_to_ojph_ht" "$R_ojph_to_jcpu_ht" "$R_ojph_to_ojph_ht"
    continue
  fi

  # Full matrix — also run GPU-side cells.
  decode_j2k  "$WORKDIR/enc/${stem}_jcpu_p1.j2k" gpu "${P}_jcpu_to_jgpu_p1.pgm"
  decode_j2k  "$WORKDIR/enc/${stem}_jgpu_p1.j2k" cpu "${P}_jgpu_to_jcpu_p1.pgm"
  decode_j2k  "$WORKDIR/enc/${stem}_jgpu_p1.j2k" gpu "${P}_jgpu_to_jgpu_p1.pgm"
  "$OPJ_DEC"  -i "$WORKDIR/enc/${stem}_jgpu_p1.j2k" -o "${P}_jgpu_to_opj_p1.pgm" >/dev/null 2>&1
  decode_j2k  "$WORKDIR/enc/${stem}_opj_p1.j2k"  gpu "${P}_opj_to_jgpu_p1.pgm"
  decode_j2k  "$WORKDIR/enc/${stem}_jcpu_ht.j2k" gpu "${P}_jcpu_to_jgpu_ht.pgm"
  decode_j2k  "$WORKDIR/enc/${stem}_jcpu_ht.j2k" gpuht "${P}_jcpu_to_jght_ht.pgm"
  decode_j2k  "$WORKDIR/enc/${stem}_jgpu_ht.j2k" cpu "${P}_jgpu_to_jcpu_ht.pgm"
  decode_j2k  "$WORKDIR/enc/${stem}_jgpu_ht.j2k" gpu "${P}_jgpu_to_jgpu_ht.pgm"
  decode_j2k  "$WORKDIR/enc/${stem}_jgpu_ht.j2k" gpuht "${P}_jgpu_to_jght_ht.pgm"
  "$OJPH_DEC" -i "$WORKDIR/enc/${stem}_jgpu_ht.j2k" -o "${P}_jgpu_to_ojph_ht.pgm" >/dev/null 2>&1
  decode_j2k  "$WORKDIR/enc/${stem}_ojph_ht.j2c" gpu "${P}_ojph_to_jgpu_ht.pgm"
  decode_j2k  "$WORKDIR/enc/${stem}_ojph_ht.j2c" gpuht "${P}_ojph_to_jght_ht.pgm"

  R_jcpu_to_jgpu_p1=$(cmp_or_no "$pgm" "${P}_jcpu_to_jgpu_p1.pgm")
  R_jgpu_to_jcpu_p1=$(cmp_or_no "$pgm" "${P}_jgpu_to_jcpu_p1.pgm")
  R_jgpu_to_jgpu_p1=$(cmp_or_no "$pgm" "${P}_jgpu_to_jgpu_p1.pgm")
  R_jgpu_to_opj_p1=$(cmp_or_no  "$pgm" "${P}_jgpu_to_opj_p1.pgm")
  R_opj_to_jgpu_p1=$(cmp_or_no  "$pgm" "${P}_opj_to_jgpu_p1.pgm")
  R_jcpu_to_jgpu_ht=$(cmp_or_no "$pgm" "${P}_jcpu_to_jgpu_ht.pgm")
  R_jcpu_to_jght_ht=$(cmp_or_no "$pgm" "${P}_jcpu_to_jght_ht.pgm")
  R_jgpu_to_jcpu_ht=$(cmp_or_no "$pgm" "${P}_jgpu_to_jcpu_ht.pgm")
  R_jgpu_to_jgpu_ht=$(cmp_or_no "$pgm" "${P}_jgpu_to_jgpu_ht.pgm")
  R_jgpu_to_jght_ht=$(cmp_or_no "$pgm" "${P}_jgpu_to_jght_ht.pgm")
  R_jgpu_to_ojph_ht=$(cmp_or_no "$pgm" "${P}_jgpu_to_ojph_ht.pgm")
  R_ojph_to_jgpu_ht=$(cmp_or_no "$pgm" "${P}_ojph_to_jgpu_ht.pgm")
  R_ojph_to_jght_ht=$(cmp_or_no "$pgm" "${P}_ojph_to_jght_ht.pgm")

  echo "$stem,$mod,$W,$H,$R_jcpu_to_jcpu_p1,$R_jcpu_to_jgpu_p1,$R_jgpu_to_jcpu_p1,$R_jgpu_to_jgpu_p1,$R_jcpu_to_opj_p1,$R_jgpu_to_opj_p1,$R_opj_to_jcpu_p1,$R_opj_to_jgpu_p1,$R_opj_to_opj_p1,$R_jcpu_to_jcpu_ht,$R_jcpu_to_jgpu_ht,$R_jcpu_to_jght_ht,$R_jgpu_to_jcpu_ht,$R_jgpu_to_jgpu_ht,$R_jgpu_to_jght_ht,$R_jcpu_to_ojph_ht,$R_jgpu_to_ojph_ht,$R_ojph_to_jcpu_ht,$R_ojph_to_jgpu_ht,$R_ojph_to_jght_ht,$R_ojph_to_ojph_ht" >> "$CSV"
  printf '  P1: jc/jc=%s jc/jg=%s jg/jc=%s jg/jg=%s | jc/o=%s jg/o=%s | o/jc=%s o/jg=%s o/o=%s\n' \
    "$R_jcpu_to_jcpu_p1" "$R_jcpu_to_jgpu_p1" "$R_jgpu_to_jcpu_p1" "$R_jgpu_to_jgpu_p1" \
    "$R_jcpu_to_opj_p1"  "$R_jgpu_to_opj_p1"  "$R_opj_to_jcpu_p1"  "$R_opj_to_jgpu_p1" "$R_opj_to_opj_p1"
  printf '  HT: jc/jc=%s jc/jg=%s jc/jh=%s jg/jc=%s jg/jg=%s jg/jh=%s | jc/o=%s jg/o=%s | o/jc=%s o/jg=%s o/jh=%s o/o=%s\n' \
    "$R_jcpu_to_jcpu_ht" "$R_jcpu_to_jgpu_ht" "$R_jcpu_to_jght_ht" "$R_jgpu_to_jcpu_ht" "$R_jgpu_to_jgpu_ht" "$R_jgpu_to_jght_ht" \
    "$R_jcpu_to_ojph_ht" "$R_jgpu_to_ojph_ht" "$R_ojph_to_jcpu_ht" "$R_ojph_to_jgpu_ht" "$R_ojph_to_jght_ht" "$R_ojph_to_ojph_ht"
done

echo ""
echo "=== CSV at $CSV ==="

# ---- mode handling --------------------------------------------------------
case "$MODE" in
  run)
    exit 0
    ;;
  update_baseline)
    cp "$CSV" "$BASELINE"
    echo "baseline updated: $BASELINE"
    exit 0
    ;;
  check)
    if [[ ! -f "$BASELINE" ]]; then
      err "no baseline at $BASELINE — first run with --update-baseline"
      exit 2
    fi
    if diff -q "$BASELINE" "$CSV" >/dev/null; then
      echo ""
      echo "✅ all cells match baseline"
      exit 0
    fi
    echo ""
    echo "❌ regression vs baseline:"
    diff "$BASELINE" "$CSV" || true
    exit 1
    ;;
esac
