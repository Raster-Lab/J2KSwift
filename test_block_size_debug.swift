#!/usr/bin/env swift

import Foundation

// Simple test to understand if there's a pattern with block sizes

let sizes = [8, 16, 24, 32, 48, 64]

for size in sizes {
    let isPowerOf2 = (size & (size - 1)) == 0
    let stripeHeight = 4
    let numStripes = (size + stripeHeight - 1) / stripeHeight
    let lastStripeSize = size % stripeHeight == 0 ? stripeHeight : size % stripeHeight
    
    print("Size: \(size)")
    print("  Power of 2: \(isPowerOf2 ? "YES" : "NO")")
    print("  Num stripes: \(numStripes)")
    print("  Last stripe size: \(lastStripeSize)")
    print("  Total iterations (stripes × width): \(numStripes * size)")
    
    // Check stripe boundaries
    for stripeY in stride(from: 0, to: size, by: stripeHeight) {
        let stripeEnd = min(stripeY + stripeHeight, size)
        if stripeEnd - stripeY != stripeHeight {
            print("  ⚠️  Partial stripe: [\(stripeY)..\(stripeEnd)) = \(stripeEnd - stripeY) rows")
        }
    }
    print()
}

// Test index calculations for boundary conditions
print("=== Index calculation test ===")
for size in [16, 32, 48, 64] {
    print("\nSize \(size)x\(size):")
    let maxIdx = size * size - 1
    
    // Test right edge (x = size - 1)
    let rightX = size - 1
    for y in 0..<size {
        let idx = y * size + rightX
        let hasRight = rightX < size - 1  // Should be false
        if hasRight {
            print("  ERROR: Right edge at (\(rightX), \(y)) thinks it has right neighbor!")
        }
    }
    
    // Test bottom edge (y = size - 1)
    let bottomY = size - 1
    for x in 0..<size {
        let idx = bottomY * size + x
        let hasBottom = bottomY < size - 1  // Should be false
        if hasBottom {
            print("  ERROR: Bottom edge at (\(x), \(bottomY)) thinks it has bottom neighbor!")
        }
    }
    
    print("  Max index: \(maxIdx), Array size: \(size * size)")
}
