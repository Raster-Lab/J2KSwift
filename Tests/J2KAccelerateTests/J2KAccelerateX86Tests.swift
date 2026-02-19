import XCTest
@testable import J2KAccelerate
@testable import J2KCore

/// Tests for x86-64 specific code paths.
final class J2KAccelerateX86Tests: XCTestCase {
    let x86 = J2KAccelerateX86()
    let tolerance = 1e-6
    
    // MARK: - Availability Tests
    
    /// Tests that x86-64 availability can be checked.
    func testX86Availability() throws {
        #if canImport(Accelerate) && arch(x86_64)
        XCTAssertTrue(J2KAccelerateX86.isAvailable)
        #else
        XCTAssertFalse(J2KAccelerateX86.isAvailable)
        #endif
    }
    
    #if canImport(Accelerate) && arch(x86_64)
    
    // MARK: - CPU Features Tests
    
    /// Tests CPU feature detection.
    func testCPUFeatures() throws {
        let features = J2KAccelerateX86.cpuFeatures()
        
        // x86-64 should have SSE/AVX
        XCTAssertEqual(features["SSE"], true)
        XCTAssertEqual(features["SSE2"], true)
        XCTAssertEqual(features["AVX"], true)
        XCTAssertEqual(features["AVX2"], true)
        
        // Should not have ARM features
        XCTAssertEqual(features["NEON"], false)
        XCTAssertEqual(features["AMX"], false)
    }
    
    // MARK: - Cache Blocking Tests
    
    /// Tests DWT with x86-64 cache blocking.
    func testDWTWithX86CacheBlocking() throws {
        let width = 64
        let height = 64
        let data = [Double](repeating: 1.0, count: width * height)
        
        let result = try x86.dwtWithX86CacheBlocking(
            data: data,
            width: width,
            height: height
        )
        
        XCTAssertEqual(result.count, data.count)
        // Placeholder implementation returns same data
        XCTAssertEqual(result, data)
    }
    
    /// Tests DWT with invalid dimensions.
    func testDWTInvalidDimensions() throws {
        let data = [Double](repeating: 0, count: 10)
        
        XCTAssertThrowsError(try x86.dwtWithX86CacheBlocking(
            data: data,
            width: 4,
            height: 4
        ))
    }
    
    /// Tests DWT with small data.
    func testDWTSmallData() throws {
        let width = 8
        let height = 8
        let data = (0..<64).map { Double($0) }
        
        let result = try x86.dwtWithX86CacheBlocking(
            data: data,
            width: width,
            height: height
        )
        
        XCTAssertEqual(result.count, 64)
    }
    
    // MARK: - AVX Matrix Multiply Tests
    
    /// Tests matrix multiplication with identity.
    func testMatrixMultiplyAVXIdentity() throws {
        let a: [Double] = [1.0, 2.0, 3.0, 4.0] // 2x2
        let identity: [Double] = [1.0, 0.0, 0.0, 1.0] // 2x2
        
        let result = try x86.matrixMultiplyAVX(
            a: a,
            b: identity,
            m: 2,
            n: 2,
            k: 2
        )
        
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result[0], 1.0, accuracy: tolerance)
        XCTAssertEqual(result[1], 2.0, accuracy: tolerance)
        XCTAssertEqual(result[2], 3.0, accuracy: tolerance)
        XCTAssertEqual(result[3], 4.0, accuracy: tolerance)
    }
    
    /// Tests matrix multiplication with scaling.
    func testMatrixMultiplyAVXScaling() throws {
        let a: [Double] = [1.0, 2.0, 3.0, 4.0] // 2x2
        let scale: [Double] = [2.0, 0.0, 0.0, 2.0] // 2x2
        
        let result = try x86.matrixMultiplyAVX(
            a: a,
            b: scale,
            m: 2,
            n: 2,
            k: 2
        )
        
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result[0], 2.0, accuracy: tolerance)
        XCTAssertEqual(result[1], 4.0, accuracy: tolerance)
        XCTAssertEqual(result[2], 6.0, accuracy: tolerance)
        XCTAssertEqual(result[3], 8.0, accuracy: tolerance)
    }
    
    /// Tests matrix multiplication with larger matrices.
    func testMatrixMultiplyAVXLarge() throws {
        let m = 4
        let n = 4
        let k = 4
        
        let a = [Double](repeating: 1.0, count: m * k)
        let b = [Double](repeating: 1.0, count: k * n)
        
        let result = try x86.matrixMultiplyAVX(
            a: a,
            b: b,
            m: m,
            n: n,
            k: k
        )
        
        XCTAssertEqual(result.count, m * n)
        // Each element should be sum of k elements
        for value in result {
            XCTAssertEqual(value, Double(k), accuracy: tolerance)
        }
    }
    
    /// Tests matrix multiplication with invalid dimensions.
    func testMatrixMultiplyAVXInvalidDimensions() throws {
        let a: [Double] = [1.0, 2.0, 3.0] // Wrong size
        let b: [Double] = [1.0, 0.0, 0.0, 1.0]
        
        XCTAssertThrowsError(try x86.matrixMultiplyAVX(
            a: a,
            b: b,
            m: 2,
            n: 2,
            k: 2
        ))
    }
    
    #else
    
    // MARK: - Non-x86-64 Tests
    
    /// Tests that x86-64 functions are not available on other platforms.
    func testX86NotAvailableOnOtherPlatforms() throws {
        XCTAssertFalse(J2KAccelerateX86.isAvailable)
    }
    
    #endif
}
