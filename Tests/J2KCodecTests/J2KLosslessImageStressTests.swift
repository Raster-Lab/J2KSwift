import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Stress tests for lossless image round-trips through the real J2K/HTJ2K codec path.
///
/// These cases intentionally use awkward dimensions, adversarial pixel patterns,
/// repeated cycles, and higher bit depths to guard against silent lossless drift.
final class J2KLosslessImageStressTests: XCTestCase {
    private enum PatternKind {
        case gradient
        case checkerboard
        case stripes
        case sawtooth
        case impulse
    }

    private func makeLosslessConfig(useHTJ2K: Bool, decompositionLevels: Int) -> J2KEncodingConfiguration {
        var config = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            decompositionLevels: decompositionLevels,
            qualityLayers: 1,
            useHTJ2K: useHTJ2K
        )
        config.useReversibleFilter = true
        return config
    }

    private func decompositionLevels(for width: Int, _ height: Int) -> Int {
        let minDimension = max(1, min(width, height))
        let levels = Int(log2(Double(minDimension))) - 2
        return max(0, min(5, levels))
    }

    private func make8BitImage(width: Int, height: Int, pattern: PatternKind) -> J2KImage {
        var pixelData = Data(count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let value: UInt8
                switch pattern {
                case .gradient:
                    value = UInt8(((x * 11) + (y * 7)) & 0xFF)
                case .checkerboard:
                    value = ((x / 3 + y / 5).isMultiple(of: 2)) ? 0 : 255
                case .stripes:
                    value = ((x / 2).isMultiple(of: 2)) ? UInt8((y * 9) & 0xFF) : UInt8((255 - y * 5) & 0xFF)
                case .sawtooth:
                    value = UInt8(((x * 29) ^ (y * 17) ^ ((x * y) & 0xFF)) & 0xFF)
                case .impulse:
                    let isImpulse = x == width / 2 || y == height / 2 || x == y || x + y == width - 1
                    value = isImpulse ? 255 : UInt8(((x + y) * 3) & 0x3F)
                }
                pixelData[index] = value
            }
        }

        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            data: pixelData
        )
        return J2KImage(width: width, height: height, components: [component])
    }

    private func makeHighBitDepthImage(width: Int, height: Int, bitDepth: Int) -> J2KImage {
        let maxValue = (1 << bitDepth) - 1
        var pixelData = Data()
        pixelData.reserveCapacity(width * height * 2)

        for y in 0..<height {
            for x in 0..<width {
                let raw = ((x * 97) + (y * 193) + ((x * y) * 17)) & maxValue
                let sample = UInt16(raw)
                var bigEndian = sample.bigEndian
                withUnsafeBytes(of: &bigEndian) { pixelData.append(contentsOf: $0) }
            }
        }

        let component = J2KComponent(
            index: 0,
            bitDepth: bitDepth,
            signed: false,
            width: width,
            height: height,
            data: pixelData
        )
        return J2KImage(width: width, height: height, components: [component])
    }

    private func assertLosslessRoundTrip(
        image: J2KImage,
        useHTJ2K: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let config = makeLosslessConfig(
            useHTJ2K: useHTJ2K,
            decompositionLevels: decompositionLevels(for: image.width, image.height)
        )

        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)
        XCTAssertFalse(encoded.isEmpty, "Encoded lossless codestream should not be empty", file: file, line: line)
        XCTAssertGreaterThanOrEqual(encoded.count, 4, file: file, line: line)
        XCTAssertEqual(encoded[0], 0xFF, file: file, line: line)
        XCTAssertEqual(encoded[1], 0x4F, file: file, line: line)

        let decoded = try await J2KDecoder().decode(encoded)
        XCTAssertEqual(decoded.width, image.width, file: file, line: line)
        XCTAssertEqual(decoded.height, image.height, file: file, line: line)
        XCTAssertEqual(decoded.components.count, image.components.count, file: file, line: line)

        for (original, reconstructed) in zip(image.components, decoded.components) {
            XCTAssertEqual(reconstructed.bitDepth, original.bitDepth, file: file, line: line)
            XCTAssertEqual(reconstructed.data, original.data, "Lossless round-trip must stay bit-exact", file: file, line: line)
        }
    }

    func testLosslessStressLegacyGrayscaleOddDimensionMatrix() async throws {
        let cases: [(Int, Int, PatternKind)] = [
            (33, 31, .gradient),
            (65, 63, .checkerboard),
            (127, 95, .stripes),
            (257, 193, .sawtooth),
            (191, 127, .impulse)
        ]

        for (width, height, pattern) in cases {
            let image = make8BitImage(width: width, height: height, pattern: pattern)
            try await assertLosslessRoundTrip(image: image, useHTJ2K: false)
        }
    }

    func testLosslessStressHTJ2KGrayscalePatternMatrix() async throws {
        let cases: [(Int, Int, PatternKind)] = [
            (37, 53, .gradient),
            (79, 61, .checkerboard),
            (129, 97, .sawtooth),
            (255, 191, .impulse)
        ]

        for (width, height, pattern) in cases {
            let image = make8BitImage(width: width, height: height, pattern: pattern)
            try await assertLosslessRoundTrip(image: image, useHTJ2K: true)
        }
    }

    func testLosslessStressHighBitDepthImagesStayBitExact() async throws {
        let images = [
            makeHighBitDepthImage(width: 61, height: 47, bitDepth: 12),
            makeHighBitDepthImage(width: 73, height: 55, bitDepth: 16)
        ]

        for image in images {
            try await assertLosslessRoundTrip(image: image, useHTJ2K: false)
            try await assertLosslessRoundTrip(image: image, useHTJ2K: true)
        }
    }

    func testLosslessStressSequentialMixedModeCyclesStayExact() async throws {
        for cycle in 0..<12 {
            let width = 48 + ((cycle * 17) % 80)
            let height = 40 + ((cycle * 19) % 72)
            let pattern: PatternKind = switch cycle % 5 {
            case 0: .gradient
            case 1: .checkerboard
            case 2: .stripes
            case 3: .sawtooth
            default: .impulse
            }

            let image = make8BitImage(width: width, height: height, pattern: pattern)
            try await assertLosslessRoundTrip(image: image, useHTJ2K: cycle.isMultiple(of: 2))
        }
    }
}
