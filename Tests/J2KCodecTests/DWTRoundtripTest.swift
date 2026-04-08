import XCTest
@testable import J2KCodec
@testable import J2KCore

final class DWTRoundtripTest: XCTestCase {
    
    /// Test that the DWT round-trip is lossless for 5/3 reversible wavelet
    func testDWTRoundtrip5Level() throws {
        let w = 128, h = 128
        var image = [[Int32]]()
        for y in 0..<h {
            var row = [Int32]()
            for x in 0..<w {
                let cx = abs(x - 64), cy = abs(y - 64)
                let dist = min(255, Int(sqrt(Double(cx * cx + cy * cy)) * 3.0))
                let pixel = 255 - dist
                row.append(Int32(pixel) - 128)  // Level shift
            }
            image.append(row)
        }
        
        // Forward multi-level DWT
        let decomp = try J2KDWT2D.forwardDecomposition(
            image: image, levels: 5, filter: .reversible53
        )
        
        // Inverse multi-level DWT (standard path)
        let reconstructed = try J2KDWT2D.inverseDecomposition(decomposition: decomp, filter: .reversible53)
        
        // Compare
        var maxErr = 0
        var errCount = 0
        for y in 0..<h {
            for x in 0..<w {
                let err = abs(Int(image[y][x]) - Int(reconstructed[y][x]))
                if err > maxErr {
                    maxErr = err
                    print("  Err at (\(x),\(y)): orig=\(image[y][x]) recon=\(reconstructed[y][x])")
                }
                if err > 0 { errCount += 1 }
            }
        }
        print("DWT 5-level roundtrip (standard): maxErr=\(maxErr), errCount=\(errCount)/\(w*h)")
        XCTAssertEqual(maxErr, 0, "5/3 DWT roundtrip must be lossless")
    }
    
    /// Test the OPTIMIZED DWT inverse path (used by the actual decoder)
    func testDWTRoundtrip5LevelOptimized() throws {
        let w = 128, h = 128
        var image = [[Int32]]()
        for y in 0..<h {
            var row = [Int32]()
            for x in 0..<w {
                let cx = abs(x - 64), cy = abs(y - 64)
                let dist = min(255, Int(sqrt(Double(cx * cx + cy * cy)) * 3.0))
                let pixel = 255 - dist
                row.append(Int32(pixel) - 128)
            }
            image.append(row)
        }
        
        // Forward multi-level DWT
        let decomp = try J2KDWT2D.forwardDecomposition(
            image: image, levels: 5, filter: .reversible53
        )
        
        // Inverse using the OPTIMIZED path (same as decoder pipeline)
        let optimizer = J2KDWT2DOptimizer()
        var currentLL = decomp.coarsestLL
        
        for level in (0..<decomp.levelCount).reversed() {
            let result = decomp.levels[level]
            currentLL = try optimizer.inverseTransform2DOptimized(
                ll: currentLL,
                lh: result.lh,
                hl: result.hl,
                hh: result.hh,
                boundaryExtension: .symmetric
            )
        }
        
        var maxErr = 0
        var errCount = 0
        for y in 0..<h {
            for x in 0..<w {
                let err = abs(Int(image[y][x]) - Int(currentLL[y][x]))
                if err > maxErr {
                    maxErr = err
                    print("  OptErr at (\(x),\(y)): orig=\(image[y][x]) recon=\(currentLL[y][x])")
                }
                if err > 0 { errCount += 1 }
            }
        }
        print("DWT 5-level roundtrip (optimized): maxErr=\(maxErr), errCount=\(errCount)/\(w*h)")
        XCTAssertEqual(maxErr, 0, "Optimized 5/3 DWT roundtrip must be lossless")
    }
    
    func testDWTRoundtrip1Level() throws {
        let w = 16, h = 16
        var image = [[Int32]]()
        for y in 0..<h {
            var row = [Int32]()
            for x in 0..<w {
                let pixel = (x * 17 + y * 31 + 42) & 0xFF
                row.append(Int32(pixel) - 128)
            }
            image.append(row)
        }
        
        let decomp = try J2KDWT2D.forwardDecomposition(
            image: image, levels: 1, filter: .reversible53
        )
        let reconstructed = try J2KDWT2D.inverseDecomposition(decomposition: decomp, filter: .reversible53)
        
        var maxErr = 0
        for y in 0..<h {
            for x in 0..<w {
                let err = abs(Int(image[y][x]) - Int(reconstructed[y][x]))
                maxErr = max(maxErr, err)
            }
        }
        print("DWT 1-level roundtrip: maxErr=\(maxErr)")
        XCTAssertEqual(maxErr, 0, "5/3 DWT 1-level roundtrip must be lossless")
    }
    
    func testDWTRoundtripOddDimensions() throws {
        let w = 13, h = 17
        var image = [[Int32]]()
        for y in 0..<h {
            var row = [Int32]()
            for x in 0..<w {
                let pixel = (x * 20 + y * 15) % 256
                row.append(Int32(pixel) - 128)
            }
            image.append(row)
        }
        
        let decomp = try J2KDWT2D.forwardDecomposition(
            image: image, levels: 2, filter: .reversible53
        )
        let reconstructed = try J2KDWT2D.inverseDecomposition(decomposition: decomp, filter: .reversible53)
        
        var maxErr = 0
        var errCount = 0
        for y in 0..<h {
            for x in 0..<w {
                let err = abs(Int(image[y][x]) - Int(reconstructed[y][x]))
                if err > maxErr {
                    maxErr = err
                    print("  Err at (\(x),\(y)): orig=\(image[y][x]) recon=\(reconstructed[y][x])")
                }
                if err > 0 { errCount += 1 }
            }
        }
        print("DWT 2-level 13x17 roundtrip: maxErr=\(maxErr), errCount=\(errCount)/\(w*h)")
        XCTAssertEqual(maxErr, 0, "5/3 DWT odd-dimension roundtrip must be lossless")
    }
}
