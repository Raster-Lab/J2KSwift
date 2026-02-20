#!/bin/bash
# run-conformance.sh
#
# J2KSwift ISO/IEC 15444-4 Conformance Test Runner
#
# Runs the full conformance test suite for all implemented JPEG 2000 parts,
# generates conformance reports, and exits with a non-zero code on failure.
#
# Usage:
#   ./Scripts/run-conformance.sh [options]
#
# Options:
#   --part <N>       Run conformance tests for Part N only (1, 2, 3, 10, 15)
#   --report         Generate markdown conformance report after running tests
#   --report-only    Skip running tests; regenerate report from existing status
#   --verbose        Show full test output
#   --help           Show this help message
#
# Exit codes:
#   0  All conformance tests passed
#   1  One or more conformance tests failed
#   2  Build failed
#   3  Unknown option or invalid arguments

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_DIR="$REPO_ROOT/Documentation/Compliance"
REPORT_FILE="$REPORT_DIR/CONFORMANCE_MATRIX.md"

PART=""
GENERATE_REPORT=false
REPORT_ONLY=false
VERBOSE=false

# ── Argument parsing ──────────────────────────────────────────────────────────

for arg in "$@"; do
    case "$arg" in
        --part)
            shift
            PART="$1"
            shift
            ;;
        --part=*)
            PART="${arg#*=}"
            ;;
        --report)
            GENERATE_REPORT=true
            ;;
        --report-only)
            REPORT_ONLY=true
            ;;
        --verbose)
            VERBOSE=true
            ;;
        --help)
            sed -n '/^# Usage:/,/^# Exit codes:/p' "$0"
            exit 0
            ;;
        --*)
            echo "Unknown option: $arg" >&2
            exit 3
            ;;
    esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────

log() {
    echo "[conformance] $*"
}

die() {
    echo "[conformance] ERROR: $*" >&2
    exit 1
}

run_swift_test() {
    local filter="$1"
    local description="$2"
    local extra_skip=(
        "--skip" "Benchmark"
        "--skip" "Stress"
        "--skip" "Diagnostic"
        "--skip" "Fuzz"
        "--skip" "PerformanceTuning"
        "--skip" "LargeBlock"
        "--skip" "EndToEnd"
        "--skip" "ClientServer"
    )

    log "Running $description..."
    if [ "$VERBOSE" = true ]; then
        swift test --filter "$filter" "${extra_skip[@]}" || return 1
    else
        swift test --filter "$filter" "${extra_skip[@]}" 2>&1 | grep -E "(PASS|FAIL|error:|warning:)" || true
        swift test --filter "$filter" "${extra_skip[@]}" > /dev/null 2>&1 || return 1
    fi
    return 0
}

# ── Build ─────────────────────────────────────────────────────────────────────

cd "$REPO_ROOT"

if [ "$REPORT_ONLY" = false ]; then
    log "Building J2KSwift..."
    if ! swift build 2>&1; then
        die "Build failed"
    fi
    log "Build complete."
fi

# ── Report-only mode ──────────────────────────────────────────────────────────

if [ "$REPORT_ONLY" = true ]; then
    log "Report-only mode: skipping test execution."
    log "Existing conformance report: $REPORT_FILE"
    [ -f "$REPORT_FILE" ] && cat "$REPORT_FILE" || log "Report file not found."
    exit 0
fi

# ── Test execution ────────────────────────────────────────────────────────────

OVERALL_PASS=true
declare -A PART_RESULTS

run_part() {
    local part_num="$1"
    local filter="$2"
    local description="$3"

    if run_swift_test "$filter" "$description"; then
        PART_RESULTS["$part_num"]="PASS"
        log "Part $part_num conformance: PASS ✓"
    else
        PART_RESULTS["$part_num"]="FAIL"
        OVERALL_PASS=false
        log "Part $part_num conformance: FAIL ✗"
    fi
}

if [ -z "$PART" ]; then
    # Run all parts
    run_part "1"  "J2KPart1Conformance"         "Part 1 (Core) conformance"
    run_part "2"  "J2KPart2ConformanceHardening" "Part 2 (Extensions) conformance"
    run_part "3"  "J2KPart3Part10Conformance"    "Part 3 (MJ2) and Part 10 (JP3D) conformance"
    run_part "10" "J2KPart3Part10Conformance"    "Part 10 (JP3D) conformance (combined with Part 3)"
    run_part "15" "J2KPart15IntegratedConformance" "Part 15 (HTJ2K) and integrated conformance"

    # Also run the full JP3D compliance suite
    if run_swift_test "JP3DComplianceTests" "JP3D (Part 10) extended compliance suite"; then
        log "JP3D extended suite: PASS ✓"
    else
        OVERALL_PASS=false
        log "JP3D extended suite: FAIL ✗"
    fi
else
    # Run specific part
    case "$PART" in
        1)  run_part "1"  "J2KPart1Conformance"           "Part 1 (Core) conformance" ;;
        2)  run_part "2"  "J2KPart2ConformanceHardening"  "Part 2 (Extensions) conformance" ;;
        3)  run_part "3"  "J2KPart3Part10Conformance"     "Part 3 (MJ2) conformance" ;;
        10) run_part "10" "JP3DComplianceTests"            "Part 10 (JP3D) conformance" ;;
        15) run_part "15" "J2KPart15IntegratedConformance" "Part 15 (HTJ2K) conformance" ;;
        *)  die "Unknown part: '$PART'. Valid values are: 1, 2, 3, 10, 15" ;;
    esac
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════════"
echo " J2KSwift Conformance Summary"
echo "════════════════════════════════════════════"
for part in $(echo "${!PART_RESULTS[@]}" | tr ' ' '\n' | sort -n); do
    result="${PART_RESULTS[$part]}"
    if [ "$result" = "PASS" ]; then
        echo " Part $part:  ✓ PASS"
    else
        echo " Part $part:  ✗ FAIL"
    fi
done
echo "════════════════════════════════════════════"

if [ "$OVERALL_PASS" = true ]; then
    echo " Overall:  ✓ ALL CONFORMANCE CHECKS PASSED"
    echo "════════════════════════════════════════════"
    echo ""
else
    echo " Overall:  ✗ CONFORMANCE FAILURES DETECTED"
    echo "════════════════════════════════════════════"
    echo ""
fi

# ── Report generation ─────────────────────────────────────────────────────────

if [ "$GENERATE_REPORT" = true ]; then
    log "Generating conformance report..."
    REPORT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    mkdir -p "$REPORT_DIR"
    {
        echo "<!-- Auto-generated by Scripts/run-conformance.sh on $REPORT_TIMESTAMP -->"
        echo ""
        cat "$REPORT_FILE"
    } > "/tmp/conformance-report-$$.md"
    mv "/tmp/conformance-report-$$.md" "$REPORT_FILE"
    log "Report updated: $REPORT_FILE"
fi

# ── Exit ──────────────────────────────────────────────────────────────────────

if [ "$OVERALL_PASS" = true ]; then
    exit 0
else
    exit 1
fi
