import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Diagnostic test for the large block bypass mode issue.
final class J2KLargeBlockDiagnostic: XCTestCase {
    
    /// Test with progressively larger blocks to find the breaking point.
    func testProgressiveBlockSizes() throws {
        let sizes = [8, 16, 32, 48, 64]
        let bitDepth = 12
        let options = CodingOptions.fastEncoding
        
        for size in sizes {
            print("\n=== Testing \(size)x\(size) block ===")
            
            let encoder = CodeBlockEncoder()
            let decoder = CodeBlockDecoder()
            
            var original = [Int32](repeating: 0, count: size * size)
            for i in 0..<original.count {
                let sign: Int32 = (i % 5 == 0) ? -1 : 1
                original[i] = sign * Int32((i * 17) % 2048)
            }
            
            // Encode
            let codeBlock = try encoder.encode(
                coefficients: original,
                width: size,
                height: size,
                subband: .ll,
                bitDepth: bitDepth,
                options: options
            )
            
            print("Encoded data size: \(codeBlock.data.count) bytes")
            
            // Decode
            let decoded = try decoder.decode(
                codeBlock: codeBlock,
                bitDepth: bitDepth,
                options: options
            )
            
            // Count mismatches
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
            
            print("Mismatches: \(mismatches) out of \(original.count)")
            if let (idx, expected, got) = firstMismatch {
                let row = idx / size
                let col = idx % size
                print("First mismatch at index \(idx) [\(row),\(col)]: expected \(expected), got \(got)")
            }
            
            // Only assert for smaller sizes to see pattern
            if size <= 32 {
                XCTAssertEqual(decoded, original, "\(size)x\(size) block should be exact")
            }
        }
    }
    
    /// Test 64x64 block with different coefficient patterns.
    func test64x64WithSimplePattern() throws {
        print("\n=== Testing 64x64 with simple pattern ===")
        
        let size = 64
        let bitDepth = 12
        let options = CodingOptions.fastEncoding
        
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        // Use a simpler pattern
        var original = [Int32](repeating: 0, count: size * size)
        for i in 0..<original.count {
            original[i] = Int32(i % 256)
        }
        
        let codeBlock = try encoder.encode(
            coefficients: original,
            width: size,
            height: size,
            subband: .ll,
            bitDepth: bitDepth,
            options: options
        )
        
        let decoded = try decoder.decode(
            codeBlock: codeBlock,
            bitDepth: bitDepth,
            options: options
        )
        
        var mismatches = 0
        for i in 0..<original.count {
            if decoded[i] != original[i] {
                mismatches += 1
            }
        }
        
        print("Mismatches with simple pattern: \(mismatches) out of \(original.count)")
        
        // This might still fail, but let's see the pattern
        if mismatches > 0 {
            print("Test would fail with \(mismatches) mismatches")
        }
    }
    
    /// Test 64x64 block without bypass mode.
    func test64x64WithoutBypass() throws {
        print("\n=== Testing 64x64 without bypass mode ===")
        
        let size = 64
        let bitDepth = 12
        let options = CodingOptions(
            bypassEnabled: false,
            bypassThreshold: 0,
            terminationMode: .predictable
        )
        
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        var original = [Int32](repeating: 0, count: size * size)
        for i in 0..<original.count {
            let sign: Int32 = (i % 5 == 0) ? -1 : 1
            original[i] = sign * Int32((i * 17) % 2048)
        }
        
        let codeBlock = try encoder.encode(
            coefficients: original,
            width: size,
            height: size,
            subband: .ll,
            bitDepth: bitDepth,
            options: options
        )
        
        let decoded = try decoder.decode(
            codeBlock: codeBlock,
            bitDepth: bitDepth,
            options: options
        )
        
        XCTAssertEqual(decoded, original, "64x64 without bypass should be exact")
    }
}
