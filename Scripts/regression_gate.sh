#!/usr/bin/env bash
# Scripts/regression_gate.sh
#
# CI regression gate for J2KSwift.
# Runs regression benchmarks, generates JSON + Markdown reports,
# and exits non-zero if any quality or size regression is detected.
#
# Usage:
#   ./Scripts/regression_gate.sh [--report-dir DIR] [--release]
#
# Environment:
#   J2K_REGRESSION_REPORTS  — directory for report output (default: regression-reports/)
#
# Exit codes:
#   0  — all checks passed
#   1  — regression detected or test failure

set -euo pipefail

REPORT_DIR="${J2K_REGRESSION_REPORTS:-regression-reports}"
BUILD_CONFIG="debug"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --report-dir)
            REPORT_DIR="$2"
            shift 2
            ;;
        --release)
            BUILD_CONFIG="release"
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

mkdir -p "$REPORT_DIR"
export J2K_REGRESSION_REPORTS="$REPORT_DIR"

echo "=== J2KSwift Regression Gate ==="
echo "Build configuration: $BUILD_CONFIG"
echo "Report directory:    $REPORT_DIR"
echo ""

# Step 1: Build
echo "--- Building ($BUILD_CONFIG) ---"
if ! swift build -c "$BUILD_CONFIG" --target J2KCore --target J2KCodec 2>&1; then
    echo "❌ Build failed"
    exit 1
fi
echo "✓ Build succeeded"
echo ""

# Step 2: Run regression tests
echo "--- Running regression benchmarks ---"
REGRESSION_OUTPUT="$REPORT_DIR/test-output.txt"

# Run with filter; capture exit code
set +e
swift test -c "$BUILD_CONFIG" \
    --filter J2KRegressionBenchmarkTests \
    2>&1 | tee "$REGRESSION_OUTPUT"
TEST_EXIT=$?
set -e

echo ""

# Step 3: Check for regressions
PASSED=true

if [ $TEST_EXIT -ne 0 ]; then
    echo "❌ Regression tests exited with code $TEST_EXIT"
    PASSED=false
fi

# Check for REGRESSION keyword in output
if grep -qi "REGRESSION" "$REGRESSION_OUTPUT" 2>/dev/null; then
    echo "❌ Regression keyword detected in output"
    PASSED=false
fi

# Check for XCTAssert failures
if grep -qE "failed|FAIL" "$REGRESSION_OUTPUT" 2>/dev/null; then
    echo "❌ Test assertion failures detected"
    PASSED=false
fi

# Step 4: Check JSON report if generated
JSON_REPORT="$REPORT_DIR/regression-report.json"
if [ -f "$JSON_REPORT" ]; then
    # Extract 'passed' field from JSON
    if command -v python3 &>/dev/null; then
        JSON_PASSED=$(python3 -c "
import json, sys
with open('$JSON_REPORT') as f:
    data = json.load(f)
print('true' if data.get('passed', False) else 'false')
" 2>/dev/null || echo "unknown")

        if [ "$JSON_PASSED" = "false" ]; then
            echo "❌ JSON report indicates regression"
            PASSED=false
        elif [ "$JSON_PASSED" = "true" ]; then
            echo "✓ JSON report: PASSED"
        fi

        # Print violation count
        VIOLATIONS=$(python3 -c "
import json
with open('$JSON_REPORT') as f:
    data = json.load(f)
print(data.get('violationCount', 0))
" 2>/dev/null || echo "?")
        echo "  Violations: $VIOLATIONS"
    fi
fi

echo ""

# Step 5: Print Markdown summary if available
MD_REPORT="$REPORT_DIR/regression-report.md"
if [ -f "$MD_REPORT" ]; then
    echo "--- Regression Report ---"
    cat "$MD_REPORT"
    echo ""
fi

# Step 6: Final verdict
echo "=== Regression Gate Result ==="
if [ "$PASSED" = true ]; then
    echo "✅ PASSED — no regressions detected"
    exit 0
else
    echo "❌ FAILED — regressions detected"
    echo ""
    echo "Review reports in: $REPORT_DIR/"
    echo "  - regression-report.json"
    echo "  - regression-report.md"
    echo "  - test-output.txt"
    exit 1
fi
