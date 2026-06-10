#!/usr/bin/env bash
#
# run-full-regression.sh — reliable full-suite regression runner for J2KSwift.
#
# WHY THIS EXISTS
# ===============
# History: a single full `swift test -c release` used to stop partway.
# The v10.9 regression (2026-05-20) attributed this to a cumulative GPU
# "deadlock" and this script worked around it with PROCESS ISOLATION —
# one `swift test` process per target, with `J2KMetalTests` split per
# suite — plus a per-run watchdog.
#
# WS2 root-cause (2026-05-21) found there was NO deadlock. The two real
# causes were: (1) three genuinely-hanging `J2KMetalHTDispatchProbe`
# tests — deleted in v10.9; and (2) a SIGSEGV in
# `ValidationReportGenerator.textReport` (a `%s` format specifier fed a
# Swift String — read as a bogus C pointer and `strlen`'d). A crashed
# xctest process stops emitting output, which looked identical to a
# hang. With (1) deleted and (2) fixed, a single full `swift test`
# completes — verified 6148 tests / 0 failures.
#
# This script is kept as a defensive harness: process isolation still
# gives a clean per-target PASS/FAIL/CRASH/HANG table, the watchdog
# still guards against any future hang, and `run_filtered` now detects
# SIGSEGV/fatalError crashes explicitly (a crash emits no
# "Test Case ... failed" line, so failure-count parsing alone would
# silently mis-record a crash as a pass — that is how WS2's crash went
# unnoticed in the v10.9 sweep). The `J2KMetalTests` per-suite split is
# now optional — that target completes fine in one process — but is
# retained so a regression that reintroduces a hang stays contained.
#
# USAGE
# =====
#   Scripts/run-full-regression.sh                # all 16 test targets
#   Scripts/run-full-regression.sh J2KCoreTests   # only the named target(s)
#   REGRESSION_TIMEOUT=600 Scripts/run-full-regression.sh   # per-run cap (s)
#
# Output: a per-target / per-suite PASS / FAIL / HANG table, the full
# list of failing test cases, per-run logs under a temp dir, and an
# exit code (0 = all clean, 1 = any failure or hang).
#
set -u
cd "$(dirname "$0")/.."

TIMEOUT="${REGRESSION_TIMEOUT:-900}"      # seconds per target / per suite
POLL=5
LOGDIR="${TMPDIR:-/tmp}/j2kswift-regression-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOGDIR"
: > "$LOGDIR/failed-tests.txt"

ALL_TARGETS="J2KCoreTests J2KCodecTests J2KFileFormatTests \
J2KMetalTests JPIPTests J2KCLITests JP3DTests \
J2KComplianceTests J2KTestAppTests \
J2KDaemonTests J2KDaemonClientTests"
SPLIT_TARGET="J2KMetalTests"   # run per-suite (hangs cumulatively within itself)

TARGETS="$*"
[ -z "$TARGETS" ] && TARGETS="$ALL_TARGETS"

total_exec=0 total_fail=0 total_skip=0 hang_count=0 crash_count=0
SUMMARY_FILE="$LOGDIR/summary.txt"; : > "$SUMMARY_FILE"

# run_filtered <label> <filter-expr> — one watchdog'd `swift test` run.
# Sets globals: R_VERDICT (PASS|FAIL|HANG|NOTESTS), R_N, R_F, R_S.
run_filtered() {
  local label="$1" filter="$2"
  local log="$LOGDIR/${label}.log"
  swift test -c release --filter "$filter" > "$log" 2>&1 &
  local pid=$! elapsed=0
  while kill -0 "$pid" 2>/dev/null && [ "$elapsed" -lt "$TIMEOUT" ]; do
    sleep "$POLL"; elapsed=$((elapsed + POLL))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null; pkill -9 xctest 2>/dev/null; sleep 1
    R_VERDICT=HANG; R_N=0; R_F=0; R_S=0
    return
  fi
  wait "$pid" 2>/dev/null
  # `swift test` exit code is unreliable here (a post-run
  # `--test-bundle-path` quirk makes it 1 even on full pass), so parse
  # the XCTest summary instead. `swift test` prints one
  # "Executed N tests, with S skipped and F failures" line per suite
  # PLUS two roll-up lines (the bundle total and "Selected tests");
  # the LAST such line is the grand total — parse only that one.
  local summ
  summ=$(grep -hE 'Executed [0-9]+ test' "$log" 2>/dev/null | tail -1)
  R_N=$(printf '%s' "$summ" | grep -oE 'Executed [0-9]+' | grep -oE '[0-9]+'); R_N=${R_N:-0}
  R_F=$(printf '%s' "$summ" | grep -oE '[0-9]+ failure'  | grep -oE '[0-9]+'); R_F=${R_F:-0}
  R_S=$(printf '%s' "$summ" | grep -oE '[0-9]+ test[s]? skipped' | grep -oE '[0-9]+'); R_S=${R_S:-0}
  grep -hE "^Test Case .* failed \(" "$log" 2>/dev/null \
    | sed -E "s/^Test Case '-?\[?([^]']+)\]?' failed.*/\1/" \
    >> "$LOGDIR/failed-tests.txt"
  # A SIGSEGV / fatalError aborts the xctest process — it produces NO
  # "Test Case ... failed" line, so failure-count parsing alone would
  # mis-record a crash as a pass. Detect the crash signature explicitly
  # and surface the last test that started (the likely culprit).
  if grep -qE 'Exited with unexpected signal|^Fatal error:|^Crashed:|Thread [0-9]+ Crashed' "$log" 2>/dev/null; then
    R_VERDICT=CRASH
    local lasttest
    lasttest=$(grep -hE "^Test Case .* started" "$log" 2>/dev/null | tail -1 \
      | sed -E "s/^Test Case '-?\[?([^]']+)\]?' started.*/\1/")
    echo "CRASH after: ${lasttest:-(unknown)}" >> "$LOGDIR/failed-tests.txt"
    return
  fi
  if [ "$R_N" -eq 0 ]; then R_VERDICT=NOTESTS
  elif [ "$R_F" -gt 0 ]; then R_VERDICT=FAIL
  else R_VERDICT=PASS; fi
}

tally() {  # <label>  (uses R_VERDICT/R_N/R_F/R_S)
  local label="$1"
  case "$R_VERDICT" in
    PASS)    total_exec=$((total_exec + R_N)); total_skip=$((total_skip + R_S))
             echo "  [PASS] $label — $R_N run, 0 failed, $R_S skipped" >> "$SUMMARY_FILE";;
    FAIL)    total_exec=$((total_exec + R_N)); total_fail=$((total_fail + R_F)); total_skip=$((total_skip + R_S))
             echo "  [FAIL] $label — $R_N run, $R_F FAILED, $R_S skipped" >> "$SUMMARY_FILE";;
    CRASH)   crash_count=$((crash_count + 1))
             echo "  [CRASH] $label — process aborted (SIGSEGV / fatalError)" >> "$SUMMARY_FILE";;
    HANG)    hang_count=$((hang_count + 1))
             echo "  [HANG] $label — killed after ${TIMEOUT}s" >> "$SUMMARY_FILE";;
    NOTESTS) echo "  [----] $label — no tests / no matches" >> "$SUMMARY_FILE";;
  esac
}

echo "=== J2KSwift full regression — $(date '+%Y-%m-%d %H:%M:%S') ==="
echo "Logs: $LOGDIR    per-run timeout: ${TIMEOUT}s"
echo

for target in $TARGETS; do
  if [ "$target" = "$SPLIT_TARGET" ]; then
    echo "[$target] GPU-heavy — running per-suite (process isolation)..."
    suites=$(grep -rhoE '(final )?class [A-Za-z0-9_]+[[:space:]]*:[[:space:]]*XCTestCase' \
               "Tests/$target/" 2>/dev/null \
             | sed -E 's/.*class ([A-Za-z0-9_]+).*/\1/' | sort -u)
    if [ -z "$suites" ]; then
      run_filtered "$target" "$target"; tally "$target"
      printf '  %-44s %s\n' "$target" "$R_VERDICT $R_N/$R_F/$R_S"
    else
      for suite in $suites; do
        run_filtered "${target}.${suite}" "$suite"; tally "${target}/${suite}"
        printf '    %-44s %s\n' "$suite" "$R_VERDICT ($R_N run, $R_F failed)"
      done
    fi
  else
    run_filtered "$target" "$target"; tally "$target"
    printf '  %-30s %s\n' "$target" "$R_VERDICT ($R_N run, $R_F failed)"
  fi
done

echo
echo "=== SUMMARY ==="
cat "$SUMMARY_FILE"
echo
echo "Totals: $total_exec executed · $total_fail failed · $total_skip skipped · $crash_count crashed · $hang_count hung run(s)"
if [ -s "$LOGDIR/failed-tests.txt" ]; then
  echo
  echo "Failing / crashing test cases:"
  sort -u "$LOGDIR/failed-tests.txt" | sed 's/^/  /'
fi
echo
if [ "$total_fail" -eq 0 ] && [ "$hang_count" -eq 0 ] && [ "$crash_count" -eq 0 ]; then
  echo "RESULT: CLEAN"; exit 0
else
  echo "RESULT: $total_fail failure(s), $crash_count crash(es), $hang_count hung run(s) — see $LOGDIR"; exit 1
fi
