import Foundation
import J2KCodec
import J2KCore

// Minimal reproduction case for 32x32 block bug

let encoder = CodeBlockEncoder()
let decoder = CodeBlockDecoder()

let size = 32
let bitDepth = 12
let options = CodingOptions.fastEncoding

var original = [Int32](repeating: 0, count: size * size)
for i in 0..<original.count {
    let sign: Int32 = (i % 5 == 0) ? -1 : 1
    original[i] = sign * Int32((i * 17) % 2048)
}

print("=== Encoding \(size)x\(size) block ===")
print("Options: bypassEnabled=\(options.bypassEnabled), bypassThreshold=\(options.bypassThreshold)")
print("First 10 coefficients: \(Array(original.prefix(10)))")

do {
    let codeBlock = try encoder.encode(
        coefficients: original,
        width: size,
        height: size,
        subband: .ll,
        bitDepth: bitDepth,
        options: options
    )
    
    print("Encoded \(codeBlock.data.count) bytes")
    print("numZeroBitPlanes: \(codeBlock.numZeroBitPlanes)")
    print("First 20 bytes: \(codeBlock.data.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " "))")
    
    print("\n=== Decoding ===")
    let decoded = try decoder.decode(
        codeBlock: codeBlock,
        bitDepth: bitDepth,
        options: options
    )
    
    print("Decoded \(decoded.count) coefficients")
    print("First 10 decoded: \(Array(decoded.prefix(10)))")
    
    // Check for mismatches
    var mismatches = 0
    var firstMismatch: (Int, Int32, Int32)?
    for i in 0..<original.count {
        if decoded[i] != original[i] {
            mismatches += 1
            if firstMismatch == nil {
                firstMismatch = (i, original[i], decoded[i])
            }
        }
    }
    
    print("\n=== Results ===")
    print("Mismatches: \(mismatches) out of \(original.count)")
    if let (idx, expected, got) = firstMismatch {
        let row = idx / size
        let col = idx % size
        print("First mismatch at index \(idx) [\(row),\(col)]:")
        print("  Expected: \(expected)")
        print("  Got: \(got)")
        print("  Difference: \(got - expected)")
    }
    
    if mismatches == 0 {
        print("✅ TEST PASSED")
    } else {
        print("❌ TEST FAILED")
    }
    
} catch {
    print("ERROR: \(error)")
}
