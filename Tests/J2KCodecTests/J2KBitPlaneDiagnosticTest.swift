import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Comprehensive diagnostic test for bit-plane encoder/decoder synchronization bug.
///
/// This test creates minimal reproducible cases with detailed logging to identify
/// the exact point where encoder and decoder diverge.
final class J2KBitPlaneDiagnosticTest: XCTestCase {
    
    /// Test with the smallest possible block that might show the issue
    func testMinimalBlock8x8() throws {
        print("\n=== Testing 8x8 Minimal Block ===")
        try runDiagnosticTest(size: 8, pattern: .dense2048)
    }
    
    /// Test 16x16 block
    func testMinimalBlock16x16() throws {
        print("\n=== Testing 16x16 Block ===")
        try runDiagnosticTest(size: 16, pattern: .dense2048)
    }
    
    /// Test 32x32 block (known to sometimes fail)
    func testMinimalBlock32x32() throws {
        print("\n=== Testing 32x32 Block (Known Issue) ===")
        try runDiagnosticTest(size: 32, pattern: .dense2048)
    }
    
    /// Test 64x64 block (known to fail)
    func testMinimalBlock64x64() throws {
        print("\n=== Testing 64x64 Block (Known Failure) ===")
        try runDiagnosticTest(size: 64, pattern: .dense2048)
    }
    
    /// Test various patterns to identify which triggers the bug
    func testVariousPatterns32x32() throws {
        print("\n=== Testing 32x32 with Various Patterns ===")
        
        for pattern in CoefficientPattern.allCases {
            print("\nPattern: \(pattern)")
            do {
                try runDiagnosticTest(size: 32, pattern: pattern, assertOnFailure: false)
            } catch {
                print("  ❌ FAILED: \(error)")
            }
        }
    }
    
    // MARK: - Helper Types
    
    enum CoefficientPattern: String, CaseIterable {
        case dense2048 = "Dense (i*17 % 2048)"
        case sparse1999 = "Sparse (i*13 % 2000)"
        case sequential = "Sequential (i % 256)"
        case alternating = "Alternating (i % 2 ? i : 0)"
        case powerOfTwo = "Power of 2 (1 << (i % 11))"
        case constant = "Constant (1024)"
        case zeros = "All zeros"
        
        func generate(count: Int) -> [Int32] {
            switch self {
            case .dense2048:
                return (0..<count).map { i in
                    let sign: Int32 = (i % 5 == 0) ? -1 : 1
                    return sign * Int32((i * 17) % 2048)
                }
            case .sparse1999:
                return (0..<count).map { i in
                    let sign: Int32 = (i % 7 == 0) ? -1 : 1
                    return sign * Int32((i * 13) % 2000)
                }
            case .sequential:
                return (0..<count).map { Int32($0 % 256) }
            case .alternating:
                return (0..<count).map { i in
                    i % 2 == 0 ? Int32(i) : 0
                }
            case .powerOfTwo:
                return (0..<count).map { i in
                    Int32(1 << (i % 11))
                }
            case .constant:
                return [Int32](repeating: 1024, count: count)
            case .zeros:
                return [Int32](repeating: 0, count: count)
            }
        }
    }
    
    // MARK: - Core Test Logic
    
    func runDiagnosticTest(
        size: Int,
        pattern: CoefficientPattern,
        assertOnFailure: Bool = true
    ) throws {
        let bitDepth = 12
        let options = CodingOptions.fastEncoding
        
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        // Generate test pattern
        let original = pattern.generate(count: size * size)
        
        print("Block size: \(size)x\(size)")
        print("Pattern: \(pattern.rawValue)")
        print("Coefficient count: \(original.count)")
        print("Non-zero coefficients: \(original.filter { $0 != 0 }.count)")
        print("Max magnitude: \(original.map { abs($0) }.max() ?? 0)")
        
        // Encode
        let startEncode = Date()
        let codeBlock = try encoder.encode(
            coefficients: original,
            width: size,
            height: size,
            subband: .ll,
            bitDepth: bitDepth,
            options: options
        )
        let encodeTime = Date().timeIntervalSince(startEncode)
        
        print("Encoded data size: \(codeBlock.data.count) bytes")
        print("Encode time: \(String(format: "%.3f", encodeTime * 1000))ms")
        print("Number of passes: \(codeBlock.passeCount)")
        
        // Decode
        let startDecode = Date()
        let decoded = try decoder.decode(
            codeBlock: codeBlock,
            bitDepth: bitDepth,
            options: options
        )
        let decodeTime = Date().timeIntervalSince(startDecode)
        
        print("Decode time: \(String(format: "%.3f", decodeTime * 1000))ms")
        
        // Analyze differences
        let analysis = analyzeDifferences(original: original, decoded: decoded, size: size)
        
        print("Mismatches: \(analysis.mismatchCount) out of \(original.count) (\(analysis.mismatchPercentage)%)")
        
        if analysis.mismatchCount > 0 {
            print("First mismatch at [\(analysis.firstMismatch!.row),\(analysis.firstMismatch!.col)]:")
            print("  Expected: \(analysis.firstMismatch!.expected)")
            print("  Got:      \(analysis.firstMismatch!.decoded)")
            print("  Diff:     \(analysis.firstMismatch!.diff)")
            
            // Show distribution of errors
            print("\nError distribution:")
            for (magnitude, count) in analysis.errorDistribution.sorted(by: { $0.key < $1.key }).prefix(10) {
                print("  Magnitude \(magnitude): \(count) errors")
            }
            
            // Show spatial distribution (first/last errors)
            if let last = analysis.lastMismatch {
                print("\nLast mismatch at [\(last.row),\(last.col)]:")
                print("  Expected: \(last.expected)")
                print("  Got:      \(last.decoded)")
            }
        }
        
        // Assert if requested
        if assertOnFailure {
            XCTAssertEqual(analysis.mismatchCount, 0,
                          "Block \(size)x\(size) with pattern '\(pattern.rawValue)' should decode perfectly")
        }
    }
    
    // MARK: - Analysis Helpers
    
    struct DifferenceAnalysis {
        let mismatchCount: Int
        let mismatchPercentage: String
        let firstMismatch: Mismatch?
        let lastMismatch: Mismatch?
        let errorDistribution: [Int32: Int]  // magnitude -> count
        
        struct Mismatch {
            let index: Int
            let row: Int
            let col: Int
            let expected: Int32
            let decoded: Int32
            let diff: Int32
        }
    }
    
    func analyzeDifferences(
        original: [Int32],
        decoded: [Int32],
        size: Int
    ) -> DifferenceAnalysis {
        var mismatchCount = 0
        var firstMismatch: DifferenceAnalysis.Mismatch?
        var lastMismatch: DifferenceAnalysis.Mismatch?
        var errorDistribution: [Int32: Int] = [:]
        
        for i in 0..<original.count {
            if decoded[i] != original[i] {
                mismatchCount += 1
                
                let row = i / size
                let col = i % size
                let diff = decoded[i] - original[i]
                let magnitude = abs(diff)
                
                let mismatch = DifferenceAnalysis.Mismatch(
                    index: i,
                    row: row,
                    col: col,
                    expected: original[i],
                    decoded: decoded[i],
                    diff: diff
                )
                
                if firstMismatch == nil {
                    firstMismatch = mismatch
                }
                lastMismatch = mismatch
                
                errorDistribution[magnitude, default: 0] += 1
            }
        }
        
        let percentage = original.count > 0
            ? String(format: "%.2f", Double(mismatchCount) * 100.0 / Double(original.count))
            : "0.00"
        
        return DifferenceAnalysis(
            mismatchCount: mismatchCount,
            mismatchPercentage: percentage,
            firstMismatch: firstMismatch,
            lastMismatch: lastMismatch,
            errorDistribution: errorDistribution
        )
    }
}
