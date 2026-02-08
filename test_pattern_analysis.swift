#!/usr/bin/env swift

import Foundation

// Test the exact patterns from the tests
print("=== testCodeBlockBypassRoundTrip pattern (PASSES) ===")
let size1 = 32
var maxVal1: Int32 = 0
for i in 0..<(size1 * size1) {
    let sign: Int32 = (i % 2 == 0) ? 1 : -1
    let val = abs(sign * Int32((i * 13) % 2000))
    maxVal1 = max(maxVal1, val)
}
print("Max magnitude: \(maxVal1)")
print("Bit width needed: \(maxVal1.bitWidth - maxVal1.leadingZeroBitCount)")
print("Is power of 2: \((maxVal1 & (maxVal1 - 1)) == 0)")

print("\n=== testProgressiveBlockSizes pattern (FAILS) ===")
let size2 = 32
var maxVal2: Int32 = 0
var powerOf2Count = 0
var magnitudes: [Int32] = []
for i in 0..<(size2 * size2) {
    let sign: Int32 = (i % 5 == 0) ? -1 : 1
    let val = abs(sign * Int32((i * 17) % 2048))
    maxVal2 = max(maxVal2, val)
    magnitudes.append(val)
    if val > 0 && (val & (val - 1)) == 0 {
        powerOf2Count += 1
    }
}
print("Max magnitude: \(maxVal2)")
print("Bit width needed: \(maxVal2.bitWidth - maxVal2.leadingZeroBitCount)")
print("Is power of 2: \((maxVal2 & (maxVal2 - 1)) == 0)")
print("Count of power-of-2 magnitudes: \(powerOf2Count) out of \(size2 * size2)")

// Check specific problem values
let problemValues: [Int32] = [2048, 1024, 512, 256, 128, 64, 32]
for pv in problemValues {
    let count = magnitudes.filter { $0 == pv }.count
    if count > 0 {
        print("  Found \(count) occurrences of \(pv) (power of 2)")
    }
}

// Test log2 calculation with the actual max magnitude
print("\nlog2(\(maxVal2)) = \(log2(Double(maxVal2)))")
print("Int(log2(\(maxVal2))) = \(Int(log2(Double(maxVal2))))")
print("Int(log2(\(maxVal2))) + 1 = \(Int(log2(Double(maxVal2))) + 1)")
print("Expected (bitWidth - leadingZeros): \(maxVal2.bitWidth - maxVal2.leadingZeroBitCount)")
