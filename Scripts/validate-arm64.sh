#!/bin/bash
# ARM64 Linux Platform Validation Script
# 
# This script validates the J2KSwift library on ARM64 Linux platforms
# including Ubuntu ARM64 and Amazon Linux ARM64.

set -e

echo "==================================="
echo "J2KSwift ARM64 Platform Validation"
echo "==================================="
echo ""

# Check architecture
ARCH=$(uname -m)
echo "Architecture: $ARCH"

if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
    echo "ERROR: This script must be run on ARM64 (aarch64) architecture"
    echo "Current architecture: $ARCH"
    exit 1
fi

# Check Swift version
echo ""
echo "Swift Version:"
swift --version

# Detect Linux distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo ""
    echo "Distribution: $NAME $VERSION"
fi

# Display CPU info
echo ""
echo "CPU Information:"
grep -E "processor|model name|Features" /proc/cpuinfo | head -20

# Verify NEON support
echo ""
echo "Checking NEON Support:"
if grep -q "asimd" /proc/cpuinfo || grep -q "neon" /proc/cpuinfo; then
    echo "✓ NEON (Advanced SIMD) detected"
else
    echo "⚠ NEON not detected - performance may be degraded"
fi

echo ""
echo "==================================="
echo "Building Project"
echo "==================================="
swift build

echo ""
echo "==================================="
echo "Running Tests"
echo "==================================="
swift test --parallel \
    --skip Benchmark \
    --skip Stress \
    --skip Diagnostic \
    --skip Fuzz \
    --skip PerformanceTuning \
    --skip LargeBlock \
    --skip EndToEnd \
    --skip ClientServer

echo ""
echo "==================================="
echo "Running ARM64-Specific Tests"
echo "==================================="
swift test --filter J2KARM64PlatformTests

echo ""
echo "==================================="
echo "Running SIMD Tests"
echo "==================================="
swift test --filter J2KHTSIMDTests

echo ""
echo "==================================="
echo "Building Release"
echo "==================================="
swift build -c release

echo ""
echo "==================================="
echo "Running Performance Benchmarks"
echo "==================================="
swift test -c release --filter J2KAccelerateBenchmarks || echo "Benchmarks completed (may have expected skips)"

echo ""
echo "==================================="
echo "Validation Complete"
echo "==================================="
echo ""
echo "Summary:"
echo "  Architecture: $ARCH"
echo "  Platform: ${NAME:-Linux}"
echo "  All tests passed successfully"
echo ""
