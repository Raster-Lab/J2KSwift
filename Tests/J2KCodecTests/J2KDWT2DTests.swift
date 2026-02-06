// J2KDWT2DTests.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-06.
//

import XCTest
@testable import J2KCodec
import J2KCore

final class J2KDWT2DTests: XCTestCase {
    
    // MARK: - Basic Functionality Tests
    
    func testForwardTransform2x2() throws {
        // Test smallest possible image
        let image: [[Int32]] = [
            [1, 2],
            [3, 4]
        ]
        
        let result = try J2KDWT2D.forwardTransform(
            image: image,
            filter: .reversible53
        )
        
        // Verify subband sizes
        XCTAssertEqual(result.ll.count, 1, "LL height should be 1")
        XCTAssertEqual(result.ll[0].count, 1, "LL width should be 1")
        XCTAssertEqual(result.lh.count, 1, "LH height should be 1")
        XCTAssertEqual(result.lh[0].count, 1, "LH width should be 1")
        XCTAssertEqual(result.hl.count, 1, "HL height should be 1")
        XCTAssertEqual(result.hl[0].count, 1, "HL width should be 1")
        XCTAssertEqual(result.hh.count, 1, "HH height should be 1")
        XCTAssertEqual(result.hh[0].count, 1, "HH width should be 1")
    }
    
    func testForwardTransform4x4() throws {
        // Test 4x4 image
        let image: [[Int32]] = [
            [1, 2, 3, 4],
            [5, 6, 7, 8],
            [9, 10, 11, 12],
            [13, 14, 15, 16]
        ]
        
        let result = try J2KDWT2D.forwardTransform(
            image: image,
            filter: .reversible53
        )
        
        // Verify subband sizes (4x4 -> 2x2 subbands)
        XCTAssertEqual(result.ll.count, 2, "LL height should be 2")
        XCTAssertEqual(result.ll[0].count, 2, "LL width should be 2")
        XCTAssertEqual(result.lh.count, 2, "LH height should be 2")
        XCTAssertEqual(result.hl.count, 2, "HL height should be 2")
        XCTAssertEqual(result.hh.count, 2, "HH height should be 2")
    }
    
    func testPerfectReconstruction4x4() throws {
        // Test perfect reconstruction with 4x4 image
        let original: [[Int32]] = [
            [1, 2, 3, 4],
            [5, 6, 7, 8],
            [9, 10, 11, 12],
            [13, 14, 15, 16]
        ]
        
        let result = try J2KDWT2D.forwardTransform(
            image: original,
            filter: .reversible53
        )
        
        let reconstructed = try J2KDWT2D.inverseTransform(
            ll: result.ll,
            lh: result.lh,
            hl: result.hl,
            hh: result.hh,
            filter: .reversible53
        )
        
        // Verify perfect reconstruction
        XCTAssertEqual(reconstructed.count, original.count)
        for (i, row) in reconstructed.enumerated() {
            XCTAssertEqual(row, original[i], "Row \(i) not reconstructed correctly")
        }
    }
    
    func testPerfectReconstruction8x8() throws {
        // Test with 8x8 image
        var image: [[Int32]] = []
        for i in 0..<8 {
            var row: [Int32] = []
            for j in 0..<8 {
                row.append(Int32(i * 8 + j + 1))
            }
            image.append(row)
        }
        
        let result = try J2KDWT2D.forwardTransform(
            image: image,
            filter: .reversible53
        )
        
        let reconstructed = try J2KDWT2D.inverseTransform(
            ll: result.ll,
            lh: result.lh,
            hl: result.hl,
            hh: result.hh,
            filter: .reversible53
        )
        
        XCTAssertEqual(reconstructed, image, "8x8 image not reconstructed correctly")
    }
    
    // MARK: - Multi-Level Decomposition Tests
    
    func testMultiLevelDecomposition2Levels() throws {
        // Test 2-level decomposition with 8x8 image
        var image: [[Int32]] = []
        for i in 0..<8 {
            var row: [Int32] = []
            for j in 0..<8 {
                row.append(Int32(i * 8 + j + 1))
            }
            image.append(row)
        }
        
        let decomposition = try J2KDWT2D.forwardDecomposition(
            image: image,
            levels: 2,
            filter: .reversible53
        )
        
        // Verify we have 2 levels
        XCTAssertEqual(decomposition.levelCount, 2)
        
        // Level 0: 8x8 -> 4x4 subbands
        XCTAssertEqual(decomposition.levels[0].ll.count, 4)
        XCTAssertEqual(decomposition.levels[0].ll[0].count, 4)
        
        // Level 1: 4x4 -> 2x2 subbands
        XCTAssertEqual(decomposition.levels[1].ll.count, 2)
        XCTAssertEqual(decomposition.levels[1].ll[0].count, 2)
        
        // Coarsest LL should be from level 1
        XCTAssertEqual(decomposition.coarsestLL, decomposition.levels[1].ll)
    }
    
    func testMultiLevelDecomposition3Levels() throws {
        // Test 3-level decomposition with 16x16 image
        var image: [[Int32]] = []
        for i in 0..<16 {
            var row: [Int32] = []
            for j in 0..<16 {
                row.append(Int32(i * 16 + j + 1))
            }
            image.append(row)
        }
        
        let decomposition = try J2KDWT2D.forwardDecomposition(
            image: image,
            levels: 3,
            filter: .reversible53
        )
        
        XCTAssertEqual(decomposition.levelCount, 3)
        
        // Verify sizes at each level
        XCTAssertEqual(decomposition.levels[0].width, 8)  // 16 -> 8
        XCTAssertEqual(decomposition.levels[1].width, 4)  // 8 -> 4
        XCTAssertEqual(decomposition.levels[2].width, 2)  // 4 -> 2
    }
    
    func testMultiLevelPerfectReconstruction() throws {
        // Test perfect reconstruction through multiple levels
        var original: [[Int32]] = []
        for i in 0..<16 {
            var row: [Int32] = []
            for j in 0..<16 {
                row.append(Int32(i * 16 + j + 1))
            }
            original.append(row)
        }
        
        let decomposition = try J2KDWT2D.forwardDecomposition(
            image: original,
            levels: 3,
            filter: .reversible53
        )
        
        let reconstructed = try J2KDWT2D.inverseDecomposition(
            decomposition: decomposition,
            filter: .reversible53
        )
        
        XCTAssertEqual(reconstructed, original, "Multi-level decomposition failed reconstruction")
    }
    
    // MARK: - Edge Cases
    
    func testOddDimensions() throws {
        // Test with odd dimensions
        let image: [[Int32]] = [
            [1, 2, 3],
            [4, 5, 6],
            [7, 8, 9]
        ]
        
        let result = try J2KDWT2D.forwardTransform(
            image: image,
            filter: .reversible53
        )
        
        // For odd dimensions, LL should be ceiling of size/2
        XCTAssertEqual(result.ll.count, 2)  // ceil(3/2) = 2
        XCTAssertEqual(result.ll[0].count, 2)
        
        // Test reconstruction
        let reconstructed = try J2KDWT2D.inverseTransform(
            ll: result.ll,
            lh: result.lh,
            hl: result.hl,
            hh: result.hh,
            filter: .reversible53
        )
        
        XCTAssertEqual(reconstructed, image)
    }
    
    func testRectangularImage() throws {
        // Test with non-square image
        let image: [[Int32]] = [
            [1, 2, 3, 4, 5, 6],
            [7, 8, 9, 10, 11, 12],
            [13, 14, 15, 16, 17, 18],
            [19, 20, 21, 22, 23, 24]
        ]
        
        let result = try J2KDWT2D.forwardTransform(
            image: image,
            filter: .reversible53
        )
        
        // Verify sizes (4x6 -> 2x3 subbands)
        XCTAssertEqual(result.ll.count, 2)
        XCTAssertEqual(result.ll[0].count, 3)
        
        let reconstructed = try J2KDWT2D.inverseTransform(
            ll: result.ll,
            lh: result.lh,
            hl: result.hl,
            hh: result.hh,
            filter: .reversible53
        )
        
        XCTAssertEqual(reconstructed, image)
    }
    
    func testConstantImage() throws {
        // Test with constant value image
        let image: [[Int32]] = Array(repeating: Array(repeating: Int32(42), count: 8), count: 8)
        
        let result = try J2KDWT2D.forwardTransform(
            image: image,
            filter: .reversible53
        )
        
        // For constant image, high-frequency subbands should be near zero
        let lhSum = result.lh.flatMap { $0 }.reduce(0, { abs($0) + abs($1) })
        let hlSum = result.hl.flatMap { $0 }.reduce(0, { abs($0) + abs($1) })
        let hhSum = result.hh.flatMap { $0 }.reduce(0, { abs($0) + abs($1) })
        
        XCTAssertEqual(lhSum, 0, "LH should be zero for constant image")
        XCTAssertEqual(hlSum, 0, "HL should be zero for constant image")
        XCTAssertEqual(hhSum, 0, "HH should be zero for constant image")
        
        let reconstructed = try J2KDWT2D.inverseTransform(
            ll: result.ll,
            lh: result.lh,
            hl: result.hl,
            hh: result.hh,
            filter: .reversible53
        )
        
        XCTAssertEqual(reconstructed, image)
    }
    
    func testRandomData() throws {
        // Test with random data
        var rng = SeededRandomNumberGenerator(seed: 42)
        
        for _ in 0..<5 {
            let height = Int.random(in: 4...32, using: &rng)
            let width = Int.random(in: 4...32, using: &rng)
            
            var image: [[Int32]] = []
            for _ in 0..<height {
                var row: [Int32] = []
                for _ in 0..<width {
                    row.append(Int32.random(in: -100...100, using: &rng))
                }
                image.append(row)
            }
            
            let result = try J2KDWT2D.forwardTransform(
                image: image,
                filter: .reversible53
            )
            
            let reconstructed = try J2KDWT2D.inverseTransform(
                ll: result.ll,
                lh: result.lh,
                hl: result.hl,
                hh: result.hh,
                filter: .reversible53
            )
            
            XCTAssertEqual(reconstructed, image, "Random \(height)x\(width) image not reconstructed")
        }
    }
    
    // MARK: - 9/7 Filter Tests
    
    func testForwardTransform97_4x4() throws {
        // Test 9/7 filter with 4x4 image
        let image: [[Double]] = [
            [1.0, 2.0, 3.0, 4.0],
            [5.0, 6.0, 7.0, 8.0],
            [9.0, 10.0, 11.0, 12.0],
            [13.0, 14.0, 15.0, 16.0]
        ]
        
        let result = try J2KDWT2D.forwardTransform97(image: image)
        
        // Verify subband sizes
        XCTAssertEqual(result.ll.count, 2)
        XCTAssertEqual(result.ll[0].count, 2)
        XCTAssertEqual(result.lh.count, 2)
        XCTAssertEqual(result.hl.count, 2)
        XCTAssertEqual(result.hh.count, 2)
    }
    
    func testNearPerfectReconstruction97() throws {
        // Test near-perfect reconstruction with 9/7 filter
        let image: [[Double]] = [
            [1.0, 2.0, 3.0, 4.0],
            [5.0, 6.0, 7.0, 8.0],
            [9.0, 10.0, 11.0, 12.0],
            [13.0, 14.0, 15.0, 16.0]
        ]
        
        let result = try J2KDWT2D.forwardTransform97(image: image)
        
        let reconstructed = try J2KDWT2D.inverseTransform97(
            ll: result.ll,
            lh: result.lh,
            hl: result.hl,
            hh: result.hh
        )
        
        // Verify near-perfect reconstruction (within floating-point error)
        XCTAssertEqual(reconstructed.count, image.count)
        for (i, row) in reconstructed.enumerated() {
            XCTAssertEqual(row.count, image[i].count)
            for (j, value) in row.enumerated() {
                XCTAssertEqual(value, image[i][j], accuracy: 1e-6,
                             "Value at (\(i),\(j)) not reconstructed accurately")
            }
        }
    }
    
    func testReconstruction97_8x8() throws {
        // Test 9/7 filter with 8x8 image
        var image: [[Double]] = []
        for i in 0..<8 {
            var row: [Double] = []
            for j in 0..<8 {
                row.append(Double(i * 8 + j + 1))
            }
            image.append(row)
        }
        
        let result = try J2KDWT2D.forwardTransform97(image: image)
        let reconstructed = try J2KDWT2D.inverseTransform97(
            ll: result.ll,
            lh: result.lh,
            hl: result.hl,
            hh: result.hh
        )
        
        // Check reconstruction error
        var maxError = 0.0
        for i in 0..<8 {
            for j in 0..<8 {
                let error = abs(reconstructed[i][j] - image[i][j])
                maxError = max(maxError, error)
            }
        }
        
        XCTAssertLessThan(maxError, 1e-6, "9/7 reconstruction error too large: \(maxError)")
    }
    
    // MARK: - Error Handling Tests
    
    func testEmptyImageError() {
        // Test that empty image throws error
        let image: [[Int32]] = []
        
        XCTAssertThrowsError(
            try J2KDWT2D.forwardTransform(image: image, filter: .reversible53)
        ) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }
    
    func testTooSmallImageError() {
        // Test that 1x1 image throws error
        let image: [[Int32]] = [[1]]
        
        XCTAssertThrowsError(
            try J2KDWT2D.forwardTransform(image: image, filter: .reversible53)
        ) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }
    
    func testInconsistentRowLengthsError() {
        // Test that inconsistent row lengths throw error
        let image: [[Int32]] = [
            [1, 2, 3],
            [4, 5],  // Wrong length
            [7, 8, 9]
        ]
        
        XCTAssertThrowsError(
            try J2KDWT2D.forwardTransform(image: image, filter: .reversible53)
        ) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }
    
    func testInvalidMultiLevelError() {
        // Test that 0 levels throws error
        let image: [[Int32]] = [[1, 2], [3, 4]]
        
        XCTAssertThrowsError(
            try J2KDWT2D.forwardDecomposition(image: image, levels: 0, filter: .reversible53)
        ) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }
    
    func testTooManyLevelsError() {
        // Test that too many levels for image size throws error
        let image: [[Int32]] = [[1, 2], [3, 4]]  // 2x2 image
        
        // Should fail at level 2 (would need to decompose 1x1 image)
        XCTAssertThrowsError(
            try J2KDWT2D.forwardDecomposition(image: image, levels: 2, filter: .reversible53)
        ) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }
    
    func testEmptySubbandsError() {
        // Test that empty subbands throw error in inverse transform
        let ll: [[Int32]] = []
        let lh: [[Int32]] = [[1]]
        let hl: [[Int32]] = [[1]]
        let hh: [[Int32]] = [[1]]
        
        XCTAssertThrowsError(
            try J2KDWT2D.inverseTransform(ll: ll, lh: lh, hl: hl, hh: hh, filter: .reversible53)
        ) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }
    
    func testIncompatibleSubbandsError() {
        // Test that incompatible subband sizes throw error
        let ll: [[Int32]] = [[1, 2], [3, 4]]
        let lh: [[Int32]] = [[1]]  // Wrong size
        let hl: [[Int32]] = [[1, 2], [3, 4]]
        let hh: [[Int32]] = [[1, 2], [3, 4]]
        
        XCTAssertThrowsError(
            try J2KDWT2D.inverseTransform(ll: ll, lh: lh, hl: hl, hh: hh, filter: .reversible53)
        ) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }
    
    // MARK: - Performance Tests
    
    // Performance tests temporarily disabled due to test infrastructure issues
    // They can be re-enabled when running manually for profiling
    
    /*
    func testPerformanceForward8x8() throws {
        var image: [[Int32]] = []
        for i in 0..<8 {
            var row: [Int32] = []
            for j in 0..<8 {
                row.append(Int32(i * 8 + j))
            }
            image.append(row)
        }
        
        measure {
            for _ in 0..<100 {
                _ = try? J2KDWT2D.forwardTransform(image: image, filter: .reversible53)
            }
        }
    }
    
    func testPerformanceRoundTrip16x16() throws {
        var image: [[Int32]] = []
        for i in 0..<16 {
            var row: [Int32] = []
            for j in 0..<16 {
                row.append(Int32(i * 16 + j))
            }
            image.append(row)
        }
        
        measure {
            for _ in 0..<100 {
                if let result = try? J2KDWT2D.forwardTransform(image: image, filter: .reversible53) {
                    _ = try? J2KDWT2D.inverseTransform(
                        ll: result.ll, lh: result.lh, hl: result.hl, hh: result.hh,
                        filter: .reversible53
                    )
                }
            }
        }
    }
    
    func testPerformanceMultiLevel32x32() throws {
        var image: [[Int32]] = []
        for i in 0..<32 {
            var row: [Int32] = []
            for j in 0..<32 {
                row.append(Int32(i * 32 + j))
            }
            image.append(row)
        }
        
        measure {
            for _ in 0..<50 {
                if let decomposition = try? J2KDWT2D.forwardDecomposition(
                    image: image, levels: 3, filter: .reversible53
                ) {
                    _ = try? J2KDWT2D.inverseDecomposition(
                        decomposition: decomposition,
                        filter: .reversible53
                    )
                }
            }
        }
    }
    
    func testPerformance97_16x16() throws {
        var image: [[Double]] = []
        for i in 0..<16 {
            var row: [Double] = []
            for j in 0..<16 {
                row.append(Double(i * 16 + j))
            }
            image.append(row)
        }
        
        measure {
            for _ in 0..<100 {
                if let result = try? J2KDWT2D.forwardTransform97(image: image) {
                    _ = try? J2KDWT2D.inverseTransform97(
                        ll: result.ll, lh: result.lh, hl: result.hl, hh: result.hh
                    )
                }
            }
        }
    }
    */
    
    // MARK: - Boundary Extension Tests
    
    func testBoundaryExtensionSymmetric() throws {
        let image: [[Int32]] = [
            [1, 2, 3, 4],
            [5, 6, 7, 8],
            [9, 10, 11, 12],
            [13, 14, 15, 16]
        ]
        
        let result = try J2KDWT2D.forwardTransform(
            image: image,
            filter: .reversible53,
            boundaryExtension: .symmetric
        )
        
        let reconstructed = try J2KDWT2D.inverseTransform(
            ll: result.ll, lh: result.lh, hl: result.hl, hh: result.hh,
            filter: .reversible53,
            boundaryExtension: .symmetric
        )
        
        XCTAssertEqual(reconstructed, image)
    }
    
    func testBoundaryExtensionPeriodic() throws {
        let image: [[Int32]] = [
            [1, 2, 3, 4],
            [5, 6, 7, 8],
            [9, 10, 11, 12],
            [13, 14, 15, 16]
        ]
        
        let result = try J2KDWT2D.forwardTransform(
            image: image,
            filter: .reversible53,
            boundaryExtension: .periodic
        )
        
        let reconstructed = try J2KDWT2D.inverseTransform(
            ll: result.ll, lh: result.lh, hl: result.hl, hh: result.hh,
            filter: .reversible53,
            boundaryExtension: .periodic
        )
        
        XCTAssertEqual(reconstructed, image)
    }
    
    func testBoundaryExtensionZeroPadding() throws {
        let image: [[Int32]] = [
            [1, 2, 3, 4],
            [5, 6, 7, 8],
            [9, 10, 11, 12],
            [13, 14, 15, 16]
        ]
        
        let result = try J2KDWT2D.forwardTransform(
            image: image,
            filter: .reversible53,
            boundaryExtension: .zeroPadding
        )
        
        let reconstructed = try J2KDWT2D.inverseTransform(
            ll: result.ll, lh: result.lh, hl: result.hl, hh: result.hh,
            filter: .reversible53,
            boundaryExtension: .zeroPadding
        )
        
        XCTAssertEqual(reconstructed, image)
    }
}
