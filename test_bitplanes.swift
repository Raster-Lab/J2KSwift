import Foundation

let magnitudes: [UInt32] = [100, 0, 0, 0, 0, 50, 0, 0, 0, 0, 25, 0, 0, 0, 0, 10]

print("Bit analysis:")
for (i, val) in magnitudes.enumerated() {
    if val > 0 {
        print("Position \(i): value=\(val), binary=\(String(format: "%08b", val))")
        let bits = 32 - val.leadingZeroBitCount - 1
        print("  Highest bit: \(bits)")
        for bit in (0...bits).reversed() {
            let mask = UInt32(1) << bit
            print("    Bit \(bit) (mask 0x\(String(format: "%02X", mask))): \((val & mask) != 0 ? 1 : 0)")
        }
    }
}

print("\nBit-plane processing order:")
print("Maximum value: 100")
print("Highest bit-plane: 6 (bit 6 = 64)")
print("Processing from bit 6 down to bit 0")

// Check bit patterns
print("\nKey insight:")
print("Position 0: 100 = 0b01100100")
print("Position 5: 50 = 0b00110010")
print("Position 10: 25 = 0b00011001")
print("Position 15: 10 = 0b00001010")

print("\nBit-plane 4 (0x10 = 16):")
print("Position 0: (100 & 16) = \((100 & 16)) → \((100 & 16) != 0 ? 1 : 0)")
print("Position 5: (50 & 16) = \((50 & 16)) → \((50 & 16) != 0 ? 1 : 0)")
print("Position 10: (25 & 16) = \((25 & 16)) → \((25 & 16) != 0 ? 1 : 0)")
print("Position 15: (10 & 16) = \((10 & 16)) → \((10 & 16) != 0 ? 1 : 0)")

