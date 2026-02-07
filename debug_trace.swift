import Foundation

// This script traces the encoding/decoding process

let width = 4
let height = 4

// Original data
var original = [Int32](repeating: 0, count: width * height)
original[0] = 100    // Binary: 01100100 (7 bits)
original[5] = -50    // Binary: 00110010 (6 bits) + sign
original[10] = 25    // Binary: 00011001 (5 bits)

// Trace bit-planes
// Position 0: 100 = 01100100 => bits: 0,1,1,0,0,1,0,0 (MSB to LSB)
// Position 5: -50 = 00110010 (magnitude) => bits: 0,0,1,1,0,0,1,0 (MSB to LSB)
// Position 10: 25 = 00011001 => bits: 0,0,0,1,1,0,0,1 (MSB to LSB)

print("Coefficient analysis:")
print("Position 0 (value=100): binary=\(String(format: "%08b", abs(original[0])))")
print("Position 5 (value=-50): binary=\(String(format: "%08b", abs(original[5])))")
print("Position 10 (value=25): binary=\(String(format: "%08b", abs(original[10])))")

// Analysis of bit-plane 4 (bitMask = 0x10 = 16)
print("\nBit-plane 4 (bitMask=0x10):")
print("Position 0: (100 & 16) = \((100 & 16) != 0 ? 1 : 0)")
print("Position 5: (50 & 16) = \((50 & 16) != 0 ? 1 : 0)")
print("Position 10: (25 & 16) = \((25 & 16) != 0 ? 1 : 0)")

// Position 3 neighbors in bit-plane 4
print("\nPosition 3 neighbors:")
print("- Left (2): index=2, value=0")
print("- Right (4): index=4, value=0")
print("- Top: none")
print("- Bottom (7): index=7, value=0")
print("Diagonal: none")
print("Position 3 should have NO significant neighbors")

// Look at grid layout
print("\nGrid layout:")
for y in 0..<height {
    for x in 0..<width {
        let idx = y * width + x
        let val = original[idx]
        if val != 0 {
            print("[\(y)][x] = \(val) (index \(idx))")
        }
    }
}

print("\nKey question: Why is position 3 getting a significance bit in the decoder?")
print("If column 3 is eligible for RLC, it should skip all coefficients.")
print("If it's not eligible, then position 3 should get a significance bit.")
