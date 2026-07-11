#!/usr/bin/env bash
#
# Release-mode, bit-exact DBT decoder regression with bounded child lifetime.
# The watchdog creates a dedicated process group for every decoder invocation
# and hard-kills the complete group on timeout, so Swift helper processes cannot
# survive a failed run. The watchdog deliberately sends one group-wide SIGKILL:
# a TERM/grace/KILL sequence can race with process-group ID reuse after TERM.

set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUT_DIR="/tmp"
OUTPUT_DIR=""
TIMEOUT_SECONDS=10
MAX_MILLISECONDS=5000
BINARY=""

usage() {
    printf '%s\n' \
        "Usage: Scripts/verify-dbt-decoder.sh [options]" \
        "  --input-dir DIR       Contains dbt_frame*.j2k and matching .pgm files" \
        "  --output-dir DIR      Preserve decoded outputs here (default: secure /tmp dir)" \
        "  --binary PATH         Use an existing release j2k binary" \
        "  --timeout-seconds N   Hard per-sample process-group timeout (default: 10)" \
        "  --max-milliseconds N  Per-sample elapsed-time bound (default: 5000)"
}

while (($#)); do
    case "$1" in
    --input-dir)
        INPUT_DIR="$2"
        shift 2
        ;;
    --output-dir)
        OUTPUT_DIR="$2"
        shift 2
        ;;
    --binary)
        BINARY="$2"
        shift 2
        ;;
    --timeout-seconds)
        TIMEOUT_SECONDS="$2"
        shift 2
        ;;
    --max-milliseconds)
        MAX_MILLISECONDS="$2"
        shift 2
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        printf 'error: unknown option: %s\n' "$1" >&2
        usage >&2
        exit 2
        ;;
    esac
done

if [[ -z "$BINARY" ]]; then
    swift build --package-path "$ROOT" -c release --product j2k
    BINARY="$ROOT/.build/release/j2k"
fi

if [[ ! -x "$BINARY" ]]; then
    printf 'error: j2k binary is not executable\n' >&2
    exit 2
fi

if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="$(mktemp -d -t j2k-dbt-regression.XXXXXX)"
else
    mkdir -p "$OUTPUT_DIR"
fi

shopt -s nullglob
codestreams=("$INPUT_DIR"/dbt_frame*.j2k)
shopt -u nullglob
if ((${#codestreams[@]} == 0)); then
    printf 'error: no dbt_frame*.j2k fixtures found\n' >&2
    exit 2
fi

passed=0
for input in "${codestreams[@]}"; do
    name="$(basename "$input" .j2k)"
    reference="$INPUT_DIR/$name.pgm"
    output="$OUTPUT_DIR/$name.pgm"
    log="$OUTPUT_DIR/$name.log"

    if [[ ! -f "$reference" ]]; then
        printf 'FAIL sample=%s reason=missing-reference\n' "$name" >&2
        exit 1
    fi

    printf 'START sample=%s\n' "$name"
    set +e
    ruby -e '
      limit = Float(ARGV.shift)
      log_path = ARGV.shift
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      log = File.open(log_path, "w", 0o600)
      pid = Process.spawn(*ARGV, pgroup: true, out: log, err: [:child, :out])
      loop do
        if Process.waitpid(pid, Process::WNOHANG)
          code = $?.exitstatus || 1
          elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
          log.puts("WATCHDOG_RESULT elapsed_ms=#{elapsed} exit=#{code}")
          log.close
          exit(code)
        end
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started >= limit
          begin Process.kill("KILL", -pid); rescue Errno::ESRCH; end
          begin Process.waitpid(pid); rescue Errno::ECHILD; end
          elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
          log.puts("WATCHDOG_TIMEOUT elapsed_ms=#{elapsed}")
          log.close
          exit(124)
        end
        sleep(0.02)
      end
    ' "$TIMEOUT_SECONDS" "$log" "$BINARY" decode -i "$input" -o "$output"
    rc=$?
    set -e

    if ((rc != 0)); then
        printf 'FAIL sample=%s reason=decoder-exit exit=%d\n' "$name" "$rc" >&2
        tail -n 5 "$log" >&2
        exit 1
    fi

    elapsed_ms="$(sed -n 's/^WATCHDOG_RESULT elapsed_ms=\([0-9][0-9]*\).*/\1/p' "$log" | tail -n 1)"
    if [[ -z "$elapsed_ms" ]] || ((elapsed_ms > MAX_MILLISECONDS)); then
        printf 'FAIL sample=%s reason=performance-bound elapsed_ms=%s bound_ms=%s\n' \
            "$name" "${elapsed_ms:-unknown}" "$MAX_MILLISECONDS" >&2
        exit 1
    fi

    if ! cmp -s "$reference" "$output"; then
        printf 'FAIL sample=%s reason=pixel-mismatch\n' "$name" >&2
        exit 1
    fi

    printf 'PASS sample=%s elapsed_ms=%s bit_exact=yes\n' "$name" "$elapsed_ms"
    passed=$((passed + 1))
done

printf 'PASS total=%d output_dir=%s\n' "$passed" "$OUTPUT_DIR"
