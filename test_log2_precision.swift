#!/usr/bin/env swift

import Foundation

// Test log2 precision for power-of-2 values
let testValues: [Int32] = [32, 64, 128, 256, 512, 1024, 2048]

for value in testValues {
    let log2Result = log2(Double(value))
    let truncated = Int(log2Result)
    let activeBitPlanes = truncated + 1
    let expectedBitPlanes = value.bitWidth - value.leadingZeroBitCount
    
    print("Value: \(value)")
    print("  log2(\(value)) = \(log2Result)")
    print("  Int(log2) = \(truncated)")
    print("  activeBitPlanes = \(activeBitPlanes)")
    print("  expectedBitPlanes = \(expectedBitPlanes)")
    print("  MATCH: \(activeBitPlanes == expectedBitPlanes ? "✅" : "❌")")
    print()
}

// Test with the exact coefficient pattern from failing tests
print("=== Test with actual pattern from tests ===")
let size = 64
for i in 0..<(size * size) {
    let sign: Int32 = (i % 5 == 0) ? -1 : 1
    let value = abs(sign * Int32((i * 17) % 2048))
    
    if value > 0 {
        let log2Result = log2(Double(value))
        let truncated = Int(log2Result)
        let activeBitPlanes = truncated + 1
        let expectedBitPlanes = value.bitWidth - value.leadingZeroBitCount
        
        if activeBitPlanes != expectedBitPlanes {
            print("MISMATCH at index \(i): value=\(value), log2=\(log2Result), got=\(activeBitPlanes), expected=\(expectedBitPlanes)")
        }
    }
}

print("\nDone!")
