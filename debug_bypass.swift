#!/usr/bin/env swift

import Foundation
@testable import J2KCodec

// Minimal test to debug bypass mode
let encoder = CodeBlockEncoder()
let decoder = CodeBlockDecoder()

let width = 4
let height = 4
let bitDepth = 12
let options = CodingOptions(bypassEnabled: true, bypassThreshold: 3)

// Create simple test pattern
var original = [Int32](repeating: 0, count: width * height)
for i in 0..<original.count {
    // Simple pattern that will use bypass mode
    original[i] = Int32(i * 100)  // Values: 0, 100, 200, 300, ..., 1500
}

print("Original coefficients:")
print(original)
print("")

do {
    // Encode
    let codeBlock = try encoder.encode(
        coefficients: original,
        width: width,
        height: height,
        subband: .ll,
        bitDepth: bitDepth,
        options: options
    )
    
    print("Encoded successfully")
    print("Data length: \(codeBlock.data.count) bytes")
    print("")
    
    // Decode
    let decoded = try decoder.decode(
        codeBlock: codeBlock,
        bitDepth: bitDepth,
        options: options
    )
    
    print("Decoded coefficients:")
    print(decoded)
    print("")
    
    // Compare
    var errors = 0
    for i in 0..<original.count {
        if original[i] != decoded[i] {
            print("ERROR at index \(i): expected \(original[i]), got \(decoded[i]), diff = \(decoded[i] - original[i])")
            errors += 1
        }
    }
    
    if errors == 0 {
        print("✓ Perfect round-trip!")
    } else {
        print("✗ Found \(errors) errors")
    }
    
} catch {
    print("Error: \(error)")
}
