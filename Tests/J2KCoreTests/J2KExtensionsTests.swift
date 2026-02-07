import XCTest
@testable import J2KCore

/// Tests for utility extensions in J2KCore.
final class J2KExtensionsTests: XCTestCase {
    
    // MARK: - Data Extensions Tests
    
    func testReadBigEndianUInt16() {
        var data = Data()
        data.append(0x12)
        data.append(0x34)
        
        let value = data.readBigEndianUInt16(at: 0)
        XCTAssertEqual(value, 0x1234)
    }
    
    func testReadBigEndianUInt16InsufficientData() {
        let data = Data([0x12])
        
        let value = data.readBigEndianUInt16(at: 0)
        XCTAssertNil(value)
    }
    
    func testReadBigEndianUInt16OutOfBounds() {
        let data = Data([0x12, 0x34])
        
        let value = data.readBigEndianUInt16(at: 10)
        XCTAssertNil(value)
    }
    
    func testReadBigEndianUInt32() {
        var data = Data()
        data.append(0x12)
        data.append(0x34)
        data.append(0x56)
        data.append(0x78)
        
        let value = data.readBigEndianUInt32(at: 0)
        XCTAssertEqual(value, 0x12345678)
    }
    
    func testReadBigEndianUInt32InsufficientData() {
        let data = Data([0x12, 0x34, 0x56])
        
        let value = data.readBigEndianUInt32(at: 0)
        XCTAssertNil(value)
    }
    
    func testAppendBigEndianUInt16() {
        var data = Data()
        data.appendBigEndianUInt16(0x1234)
        
        XCTAssertEqual(data.count, 2)
        XCTAssertEqual(data[0], 0x12)
        XCTAssertEqual(data[1], 0x34)
    }
    
    func testAppendBigEndianUInt32() {
        var data = Data()
        data.appendBigEndianUInt32(0x12345678)
        
        XCTAssertEqual(data.count, 4)
        XCTAssertEqual(data[0], 0x12)
        XCTAssertEqual(data[1], 0x34)
        XCTAssertEqual(data[2], 0x56)
        XCTAssertEqual(data[3], 0x78)
    }
    
    func testRoundTripUInt16() {
        var data = Data()
        data.appendBigEndianUInt16(0xABCD)
        
        let value = data.readBigEndianUInt16(at: 0)
        XCTAssertEqual(value, 0xABCD)
    }
    
    func testRoundTripUInt32() {
        var data = Data()
        data.appendBigEndianUInt32(0xDEADBEEF)
        
        let value = data.readBigEndianUInt32(at: 0)
        XCTAssertEqual(value, 0xDEADBEEF)
    }
    
    // MARK: - Array Int Extensions Tests
    
    func testIntArrayMean() {
        let array = [1, 2, 3, 4, 5]
        XCTAssertEqual(array.mean, 3.0, accuracy: 0.001)
    }
    
    func testIntArrayMeanEmpty() {
        let array: [Int] = []
        XCTAssertEqual(array.mean, 0.0)
    }
    
    func testIntArrayVariance() {
        let array = [2, 4, 4, 4, 5, 5, 7, 9]
        // Mean = 5, Variance = 4
        XCTAssertEqual(array.variance, 4.0, accuracy: 0.001)
    }
    
    func testIntArrayStandardDeviation() {
        let array = [2, 4, 4, 4, 5, 5, 7, 9]
        // Standard deviation = 2
        XCTAssertEqual(array.standardDeviation, 2.0, accuracy: 0.001)
    }
    
    // MARK: - Array Double Extensions Tests
    
    func testDoubleArrayMean() {
        let array = [1.0, 2.0, 3.0, 4.0, 5.0]
        XCTAssertEqual(array.mean, 3.0, accuracy: 0.001)
    }
    
    func testDoubleArrayMeanEmpty() {
        let array: [Double] = []
        XCTAssertEqual(array.mean, 0.0)
    }
    
    func testDoubleArrayVariance() {
        let array = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]
        XCTAssertEqual(array.variance, 4.0, accuracy: 0.001)
    }
    
    func testDoubleArrayStandardDeviation() {
        let array = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]
        XCTAssertEqual(array.standardDeviation, 2.0, accuracy: 0.001)
    }
    
    func testDoubleArrayNormalized() {
        let array = [0.0, 5.0, 10.0]
        let normalized = array.normalized()
        
        XCTAssertEqual(normalized.count, 3)
        XCTAssertEqual(normalized[0], 0.0, accuracy: 0.001)
        XCTAssertEqual(normalized[1], 0.5, accuracy: 0.001)
        XCTAssertEqual(normalized[2], 1.0, accuracy: 0.001)
    }
    
    func testDoubleArrayNormalizedEmpty() {
        let array: [Double] = []
        let normalized = array.normalized()
        XCTAssertTrue(normalized.isEmpty)
    }
    
    func testDoubleArrayNormalizedConstant() {
        let array = [5.0, 5.0, 5.0]
        let normalized = array.normalized()
        
        XCTAssertEqual(normalized.count, 3)
        for value in normalized {
            XCTAssertEqual(value, 0.5, accuracy: 0.001)
        }
    }
    
    func testDoubleArrayNormalizedNegativeValues() {
        let array = [-10.0, 0.0, 10.0]
        let normalized = array.normalized()
        
        XCTAssertEqual(normalized.count, 3)
        XCTAssertEqual(normalized[0], 0.0, accuracy: 0.001)
        XCTAssertEqual(normalized[1], 0.5, accuracy: 0.001)
        XCTAssertEqual(normalized[2], 1.0, accuracy: 0.001)
    }
}
