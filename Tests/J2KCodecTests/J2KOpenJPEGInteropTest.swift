import XCTest
@testable import J2KCodec
@testable import J2KCore
import Foundation

/// End-to-end interoperability test: encode with J2KSwift, decode with OpenJPEG,
/// and verify pixel-perfect (lossless) or bounded-error (lossy) reconstruction.
///
/// These tests produce actual .j2k files and shell out to `opj_decompress`
/// to confirm that external decoders accept our codestream.
final class J2KOpenJPEGInteropTest: XCTestCase {

    private let opjDecompress = "/opt/homebrew/bin/opj_decompress"
    private let outputDir = "/tmp/j2k_interop_test"

    override func setUp() {
        super.setUp()
        try? FileManager.default.createDirectory(
            atPath: outputDir,
            withIntermediateDirectories: true)
    }

    // MARK: - Helper: encode, save, decode with OpenJPEG, compare

    /// Encode a single-component grayscale image, write to disk, decode with
    /// OpenJPEG, read back the raw PGM, and compare pixel values.
    ///
    /// - Returns: (maxError, meanError) pair.
    @discardableResult
    private func encodeAndVerify(
        name: String,
        pixelData: Data,
        width: Int,
        height: Int,
        lossless: Bool,
        decompositionLevels: Int,
        codeBlockSize: (width: Int, height: Int) = (32, 32)
    ) async throws -> (maxError: Int, meanError: Double) {

        // 1. Build J2KImage
        let comp = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: width, height: height, data: pixelData)
        let image = J2KImage(width: width, height: height, components: [comp])

        // 2. Encode
        let config = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: lossless,
            decompositionLevels: decompositionLevels,
            codeBlockSize: codeBlockSize)
        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)

        // Basic codestream validation
        XCTAssertEqual(encoded[0], 0xFF, "\(name): SOC[0]")
        XCTAssertEqual(encoded[1], 0x4F, "\(name): SOC[1]")
        XCTAssertEqual(encoded[encoded.count - 2], 0xFF, "\(name): EOC[-2]")
        XCTAssertEqual(encoded[encoded.count - 1], 0xD9, "\(name): EOC[-1]")

        // 3. Write .j2k
        let j2kPath = "\(outputDir)/\(name).j2k"
        try encoded.write(to: URL(fileURLWithPath: j2kPath))
        print("[\(name)] wrote \(encoded.count) bytes → \(j2kPath)")

        // 4. Self round-trip
        let selfDecoded = try await DecoderPipeline().decode(encoded)
        XCTAssertEqual(selfDecoded.width, width, "\(name): self-decode width")
        XCTAssertEqual(selfDecoded.height, height, "\(name): self-decode height")

        if lossless {
            let selfData = selfDecoded.components[0].data
            var selfMax = 0
            for i in 0..<pixelData.count {
                let err = abs(Int(pixelData[i]) - Int(selfData[i]))
                selfMax = max(selfMax, err)
            }
            if selfMax > 0 {
                print("[\(name)] SELF round-trip maxErr=\(selfMax)")
                print("[\(name)] orig first 16: \(Array(pixelData.prefix(16)))")
                print("[\(name)] dec  first 16: \(Array(selfData.prefix(16)))")
            }
            XCTAssertEqual(selfMax, 0, "\(name): self round-trip should be lossless, maxErr=\(selfMax)")
        }

        // 5. OpenJPEG decode
        guard FileManager.default.fileExists(atPath: opjDecompress) else {
            print("[\(name)] SKIP OpenJPEG verification (opj_decompress not found)")
            return (0, 0.0)
        }

        let pgmPath = "\(outputDir)/\(name).pgm"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: opjDecompress)
        proc.arguments = ["-i", j2kPath, "-o", pgmPath]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()

        XCTAssertEqual(proc.terminationStatus, 0,
            "\(name): opj_decompress exit code \(proc.terminationStatus)")

        guard proc.terminationStatus == 0 else {
            let stderr = String(data: (proc.standardError as! Pipe).fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTFail("\(name): opj_decompress failed: \(stderr)")
            return (-1, -1)
        }

        // 6. Read PGM and compare
        let pgmData = try Data(contentsOf: URL(fileURLWithPath: pgmPath))
        let pixels = parsePGM(data: pgmData)
        XCTAssertEqual(pixels.count, width * height,
            "\(name): PGM pixel count mismatch: \(pixels.count) vs \(width * height)")

        var maxErr = 0
        var sumErr: Double = 0
        for i in 0..<min(pixelData.count, pixels.count) {
            let err = abs(Int(pixelData[i]) - Int(pixels[i]))
            maxErr = max(maxErr, err)
            sumErr += Double(err)
        }
        let meanErr = sumErr / Double(pixelData.count)

        print("[\(name)] OpenJPEG decode OK — maxErr=\(maxErr) meanErr=\(String(format: "%.3f", meanErr))")
        return (maxErr, meanErr)
    }

    /// Parse a raw PGM (P5) file and return the pixel bytes.
    private func parsePGM(data: Data) -> [UInt8] {
        // PGM P5 format:
        // P5\n[#comment\n]*<width> <height>\n<maxval>\n<binary data>
        var offset = 0
        let bytes = Array(data)

        func readLine() -> String? {
            guard offset < bytes.count else { return nil }
            var line = ""
            while offset < bytes.count {
                let ch = bytes[offset]
                offset += 1
                if ch == 0x0A { break } // \n
                line.append(Character(UnicodeScalar(ch)))
            }
            return line
        }

        // Read magic
        guard let magic = readLine(), magic == "P5" else { return [] }

        // Read header lines, skipping comments
        var headerLines: [String] = []
        while headerLines.count < 2 {
            guard let line = readLine() else { return [] }
            if line.hasPrefix("#") { continue }
            headerLines.append(line)
        }

        // headerLines[0] = "width height", headerLines[1] = "maxval"
        // Binary pixel data starts at current offset
        return Array(bytes[offset...])
    }

    // MARK: - Test Cases

    /// Constant image: all pixels = 200. Simplest possible test (no DWT).
    func testConstant200_NoDWT() async throws {
        let w = 8, h = 8
        let pixels = Data(repeating: 200, count: w * h)
        let (maxErr, _) = try await encodeAndVerify(
            name: "const200_nodwt", pixelData: pixels,
            width: w, height: h, lossless: true, decompositionLevels: 0)
        XCTAssertEqual(maxErr, 0, "Lossless constant image must be exact")
    }

    /// Horizontal gradient 8x8 (10, 20, ..., 80 repeating). No DWT.
    func testGradient8x8_NoDWT() async throws {
        let w = 8, h = 8
        var pixels = Data(count: w * h)
        for i in 0..<(w * h) {
            pixels[i] = UInt8(10 + (i % 8) * 10)
        }
        let (maxErr, _) = try await encodeAndVerify(
            name: "gradient8_nodwt", pixelData: pixels,
            width: w, height: h, lossless: true, decompositionLevels: 0)
        XCTAssertEqual(maxErr, 0, "Lossless gradient must be exact")
    }

    /// Random-ish pattern 16x16 with 1-level DWT.
    func testPattern16x16_1LevelDWT() async throws {
        let w = 16, h = 16
        var pixels = Data(count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                pixels[y * w + x] = UInt8((x * 17 + y * 31 + 42) & 0xFF)
            }
        }
        let (maxErr, _) = try await encodeAndVerify(
            name: "pattern16_1dwt", pixelData: pixels,
            width: w, height: h, lossless: true, decompositionLevels: 1)
        XCTAssertEqual(maxErr, 0, "Lossless 1-level DWT must be exact")
    }

    /// Larger gradient 32x32 with 2-level DWT.
    func testGradient32x32_2LevelDWT() async throws {
        let w = 32, h = 32
        var pixels = Data(count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                pixels[y * w + x] = UInt8((x * 8 + y * 4) & 0xFF)
            }
        }
        let (maxErr, _) = try await encodeAndVerify(
            name: "gradient32_2dwt", pixelData: pixels,
            width: w, height: h, lossless: true, decompositionLevels: 2)
        XCTAssertEqual(maxErr, 0, "Lossless 2-level DWT must be exact")
    }

    /// 64x64 natural-like content with 3-level DWT.
    func testNatural64x64_3LevelDWT() async throws {
        let w = 64, h = 64
        var pixels = Data(count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                // Simulate natural image texture with smooth gradients + noise
                let base = (x * 4 + y * 3) & 0xFF
                let noise = ((x * 7 + y * 13 + x * y) >> 2) & 0x1F
                pixels[y * w + x] = UInt8(min(255, base + noise))
            }
        }
        let (maxErr, _) = try await encodeAndVerify(
            name: "natural64_3dwt", pixelData: pixels,
            width: w, height: h, lossless: true, decompositionLevels: 3)
        XCTAssertEqual(maxErr, 0, "Lossless 3-level DWT must be exact")
    }

    /// 128x128 with 5-level DWT (matches the blackbuck.j2k configuration).
    func testLarger128x128_5LevelDWT() async throws {
        let w = 128, h = 128
        var pixels = Data(count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let cx = abs(x - 64), cy = abs(y - 64)
                let dist = min(255, Int(sqrt(Double(cx * cx + cy * cy)) * 3.0))
                pixels[y * w + x] = UInt8(255 - dist)
            }
        }
        let (maxErr, _) = try await encodeAndVerify(
            name: "radial128_5dwt", pixelData: pixels,
            width: w, height: h, lossless: true, decompositionLevels: 5)
        XCTAssertEqual(maxErr, 0, "Lossless 5-level DWT must be exact")
    }

    /// Non-power-of-2 dimensions: 13x17 with 2-level DWT.
    func testOddDimensions13x17() async throws {
        let w = 13, h = 17
        var pixels = Data(count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                pixels[y * w + x] = UInt8((x * 20 + y * 15) % 256)
            }
        }
        let (maxErr, _) = try await encodeAndVerify(
            name: "odd13x17_2dwt", pixelData: pixels,
            width: w, height: h, lossless: true, decompositionLevels: 2)
        XCTAssertEqual(maxErr, 0, "Lossless odd-dimension must be exact")
    }

    /// All-black image (edge case: all zeros after level shift).
    func testAllBlack() async throws {
        let w = 16, h = 16
        let pixels = Data(repeating: 0, count: w * h)
        let (maxErr, _) = try await encodeAndVerify(
            name: "black16", pixelData: pixels,
            width: w, height: h, lossless: true, decompositionLevels: 1)
        XCTAssertEqual(maxErr, 0, "Lossless all-black must be exact")
    }

    /// All-white image (edge case: all 127 after level shift).
    func testAllWhite() async throws {
        let w = 16, h = 16
        let pixels = Data(repeating: 255, count: w * h)
        let (maxErr, _) = try await encodeAndVerify(
            name: "white16", pixelData: pixels,
            width: w, height: h, lossless: true, decompositionLevels: 1)
        XCTAssertEqual(maxErr, 0, "Lossless all-white must be exact")
    }

    /// Decode an OPJ-encoded file with our decoder to verify decoder correctness.
    func testDecodeOPJReference() async throws {
        let w = 8, h = 8
        var origPixels = Data(count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                origPixels[y * w + x] = UInt8(min(255, x * 32 + y * 16))
            }
        }

        // Create PGM and encode with OpenJPEG
        let pgmPath = "\(outputDir)/simple8_for_decode.pgm"
        var pgmData = Data("P5\n\(w) \(h)\n255\n".utf8)
        pgmData.append(origPixels)
        try pgmData.write(to: URL(fileURLWithPath: pgmPath))

        let j2kPath = "\(outputDir)/simple8_opj_encoded.j2k"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/opj_compress")
        proc.arguments = ["-i", pgmPath, "-o", j2kPath, "-r", "1", "-n", "2", "-b", "32,32"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            XCTFail("opj_compress failed")
            return
        }

        // Decode with our decoder
        let j2kData = try Data(contentsOf: URL(fileURLWithPath: j2kPath))
        let decoded = try await DecoderPipeline().decode(j2kData)
        XCTAssertEqual(decoded.width, w)
        XCTAssertEqual(decoded.height, h)

        let decodedPixels = decoded.components[0].data
        var maxErr = 0
        var errInfo = ""
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let err = abs(Int(origPixels[i]) - Int(decodedPixels[i]))
                if err > maxErr {
                    maxErr = err
                    errInfo = "at (\(x),\(y)): orig=\(origPixels[i]) decoded=\(decodedPixels[i])"
                }
            }
        }
        
        if maxErr > 0 {
            print("[decodeOPJ] maxErr=\(maxErr) \(errInfo)")
            print("[decodeOPJ] original: \(Array(origPixels.prefix(16)))")
            print("[decodeOPJ] decoded:  \(Array(decodedPixels.prefix(16)))")
        }
        
        // Also encode with our encoder and decode to compare
        let comp = J2KComponent(index: 0, bitDepth: 8, signed: false,
                                width: w, height: h, data: origPixels)
        let image = J2KImage(width: w, height: h, components: [comp])
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 1, codeBlockSize: (32, 32))
        let ourEncoded = try await J2KEncoder(encodingConfiguration: config).encode(image)
        
        // Decode our encoding with OPJ
        let ourJ2kPath = "\(outputDir)/simple8_ours.j2k"
        try ourEncoded.write(to: URL(fileURLWithPath: ourJ2kPath))
        
        let proc2 = Process()
        proc2.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/opj_decompress")
        proc2.arguments = ["-i", ourJ2kPath, "-o", "\(outputDir)/simple8_ours_decoded.pgm"]
        proc2.standardOutput = Pipe()
        proc2.standardError = Pipe()
        try proc2.run()
        proc2.waitUntilExit()
        
        if proc2.terminationStatus == 0 {
            let pgm = try Data(contentsOf: URL(fileURLWithPath: "\(outputDir)/simple8_ours_decoded.pgm"))
            let decoded2 = parsePGM(data: pgm)
            var maxErr2 = 0
            for i in 0..<min(origPixels.count, decoded2.count) {
                let err = abs(Int(origPixels[i]) - Int(decoded2[i]))
                maxErr2 = max(maxErr2, err)
            }
            print("[ourEncode→OPJdecode] maxErr=\(maxErr2)")
        }
        
        // Compare file sizes
        print("[sizes] OPJ=\(j2kData.count) OURS=\(ourEncoded.count)")
        
        XCTAssertEqual(maxErr, 0, "Our decoder should decode OPJ's output losslessly, maxErr=\(maxErr)")
    }

    /// Decode OPJ-encoded odd-dimension (13x17) file with our decoder.
    func testDecodeOPJOddDimension() async throws {
        let w = 13, h = 17
        var origPixels = Data(count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                origPixels[y * w + x] = UInt8((x * 20 + y * 15) % 256)
            }
        }

        // Use previously generated OPJ file
        let j2kPath = "\(outputDir)/odd13x17_opj.j2k"
        guard FileManager.default.fileExists(atPath: j2kPath) else {
            // Generate it if not present
            let pgmPath = "\(outputDir)/odd13x17_for_decode.pgm"
            var pgmData = Data("P5\n\(w) \(h)\n255\n".utf8)
            pgmData.append(origPixels)
            try pgmData.write(to: URL(fileURLWithPath: pgmPath))
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/opj_compress")
            proc.arguments = ["-i", pgmPath, "-o", j2kPath, "-r", "1", "-n", "3", "-b", "32,32"]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                XCTFail("opj_compress failed")
                return
            }
            return  // re-run test after generating
        }

        let j2kData = try Data(contentsOf: URL(fileURLWithPath: j2kPath))
        let decoded = try await DecoderPipeline().decode(j2kData)
        XCTAssertEqual(decoded.width, w)
        XCTAssertEqual(decoded.height, h)

        let decodedPixels = decoded.components[0].data
        var maxErr = 0
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let err = abs(Int(origPixels[i]) - Int(decodedPixels[i]))
                maxErr = max(maxErr, err)
            }
        }
        XCTAssertEqual(maxErr, 0, "Our decoder should decode OPJ's odd-dim output losslessly, maxErr=\(maxErr)")
    }

    // MARK: - Multi-Component (RGB) Tests

    /// Simple 8x8 constant RGB image test to verify multi-component encoding.
    func testSimpleRGB_8x8() async throws {
        let w = 8, h = 8
        let size = w * h
        let red = Data(repeating: 100, count: size)
        let green = Data(repeating: 50, count: size)
        let blue = Data(repeating: 200, count: size)
        try await encodeAndVerifyRGB(name: "simple_rgb_8x8", red: red, green: green, blue: blue,
                               width: w, height: h, decompositionLevels: 1)
    }

    /// 8x8 VARIED RGB (non-constant data).
    func testVariedRGB_8x8_1DWT() async throws {
        let w = 8, h = 8
        let size = w * h
        var red = Data(count: size), green = Data(count: size), blue = Data(count: size)
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x
            red[i] = UInt8((x * 32 + y * 16) & 0xFF)
            green[i] = UInt8((x * 24 + y * 20 + 30) & 0xFF)
            blue[i] = UInt8((x * 16 + y * 28 + 80) & 0xFF)
        }}
        try await encodeAndVerifyRGB(name: "varied_rgb_8_1dwt", red: red, green: green, blue: blue,
                               width: w, height: h, decompositionLevels: 1)
    }

    /// 32x32 varied RGB image with 2-level DWT.
    func testVariedRGB_32x32_2DWT() async throws {
        let w = 32, h = 32
        let size = w * h
        var red = Data(count: size), green = Data(count: size), blue = Data(count: size)
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x
            red[i] = UInt8((x * 8 + y * 3) & 0xFF)
            green[i] = UInt8((x * 5 + y * 7 + 50) & 0xFF)
            blue[i] = UInt8((x * 3 + y * 11 + 100) & 0xFF)
        }}
        try await encodeAndVerifyRGB(name: "varied_rgb_32_2dwt", red: red, green: green, blue: blue,
                               width: w, height: h, decompositionLevels: 2)
    }

    /// 16x16 varied RGB image with 1-level DWT (test if 1 DWT level works).
    func testVariedRGB_16x16_1DWT() async throws {
        let w = 16, h = 16
        let size = w * h
        var red = Data(count: size), green = Data(count: size), blue = Data(count: size)
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x
            red[i] = UInt8((x * 17 + y * 5) & 0xFF)
            green[i] = UInt8((x * 11 + y * 9 + 30) & 0xFF)
            blue[i] = UInt8((x * 7 + y * 13 + 80) & 0xFF)
        }}
        try await encodeAndVerifyRGB(name: "varied_rgb_16_1dwt", red: red, green: green, blue: blue,
                               width: w, height: h, decompositionLevels: 1)
    }

    /// 32x32 varied RGB image with 1-level DWT (test if it's size or level).
    func testVariedRGB_32x32_1DWT() async throws {
        let w = 32, h = 32
        let size = w * h
        var red = Data(count: size), green = Data(count: size), blue = Data(count: size)
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x
            red[i] = UInt8((x * 8 + y * 3) & 0xFF)
            green[i] = UInt8((x * 5 + y * 7 + 50) & 0xFF)
            blue[i] = UInt8((x * 3 + y * 11 + 100) & 0xFF)
        }}
        try await encodeAndVerifyRGB(name: "varied_rgb_32_1dwt", red: red, green: green, blue: blue,
                               width: w, height: h, decompositionLevels: 1)
    }

    /// 64x64 varied RGB image with 3-level DWT.
    func testVariedRGB_64x64_3DWT() async throws {
        let w = 64, h = 64
        let size = w * h
        var red = Data(count: size), green = Data(count: size), blue = Data(count: size)
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x
            red[i] = UInt8((x * 4 + y * 2) & 0xFF)
            green[i] = UInt8((x * 3 + y * 5 + 30) & 0xFF)
            blue[i] = UInt8((x * 2 + y * 6 + 90) & 0xFF)
        }}
        try await encodeAndVerifyRGB(name: "varied_rgb_64_3dwt", red: red, green: green, blue: blue,
                               width: w, height: h, decompositionLevels: 3)
    }

    /// 128x128 varied RGB image with 5-level DWT.
    func testVariedRGB_128x128_5DWT() async throws {
        let w = 128, h = 128
        let size = w * h
        var red = Data(count: size), green = Data(count: size), blue = Data(count: size)
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x
            red[i] = UInt8((x * 2 + y * 1) & 0xFF)
            green[i] = UInt8((x * 1 + y * 3 + 20) & 0xFF)
            blue[i] = UInt8((x * 3 + y * 2 + 80) & 0xFF)
        }}
        try await encodeAndVerifyRGB(name: "varied_rgb_128_5dwt", red: red, green: green, blue: blue,
                               width: w, height: h, decompositionLevels: 5)
    }

    /// Helper to encode and verify RGB image with OpenJPEG.
    @discardableResult
    private func encodeAndVerifyRGB(
        name: String,
        red: Data, green: Data, blue: Data,
        width w: Int, height h: Int,
        decompositionLevels: Int
    ) async throws -> Int {
        let size = w * h
        let compR = J2KComponent(index: 0, bitDepth: 8, signed: false, width: w, height: h, data: red)
        let compG = J2KComponent(index: 1, bitDepth: 8, signed: false, width: w, height: h, data: green)
        let compB = J2KComponent(index: 2, bitDepth: 8, signed: false, width: w, height: h, data: blue)
        let image = J2KImage(width: w, height: h, components: [compR, compG, compB])

        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: decompositionLevels, codeBlockSize: (32, 32))
        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)
        print("[\(name)] Encoded \(encoded.count) bytes")

        // Self round-trip
        let decoded = try await DecoderPipeline().decode(encoded)
        XCTAssertEqual(decoded.width, w)
        XCTAssertEqual(decoded.height, h)
        XCTAssertEqual(decoded.components.count, 3)
        for c in 0..<3 {
            let orig = [red, green, blue][c]
            let dec = decoded.components[c].data
            var maxErr = 0
            for i in 0..<size { maxErr = max(maxErr, abs(Int(orig[i]) - Int(dec[i]))) }
            XCTAssertEqual(maxErr, 0, "[\(name)] Self round-trip C\(c) must be exact, maxErr=\(maxErr)")
        }

        // OpenJPEG decode
        let j2kPath = "\(outputDir)/\(name).j2k"
        try encoded.write(to: URL(fileURLWithPath: j2kPath))

        guard FileManager.default.fileExists(atPath: opjDecompress) else { return 0 }

        let ppmPath = "\(outputDir)/\(name).ppm"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: opjDecompress)
        proc.arguments = ["-i", j2kPath, "-o", ppmPath]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()

        XCTAssertEqual(proc.terminationStatus, 0, "[\(name)] opj_decompress failed")
        guard proc.terminationStatus == 0 else { return -1 }

        let ppmData = try Data(contentsOf: URL(fileURLWithPath: ppmPath))
        let (ppmPixels, _, _) = parsePPM(data: ppmData)

        var maxErr = 0
        var errInfo = ""
        for i in 0..<size {
            let ppmOff = i * 3
            let errR = abs(Int(red[i]) - Int(ppmPixels[ppmOff]))
            let errG = abs(Int(green[i]) - Int(ppmPixels[ppmOff + 1]))
            let errB = abs(Int(blue[i]) - Int(ppmPixels[ppmOff + 2]))
            let err = max(errR, max(errG, errB))
            if err > maxErr {
                maxErr = err
                errInfo = "at pixel \(i): orig=(\(red[i]),\(green[i]),\(blue[i])) decoded=(\(ppmPixels[ppmOff]),\(ppmPixels[ppmOff+1]),\(ppmPixels[ppmOff+2]))"
            }
        }
        print("[\(name)] OpenJPEG maxErr=\(maxErr) \(errInfo)")
        XCTAssertEqual(maxErr, 0, "[\(name)] Lossless RGB must be exact, maxErr=\(maxErr) \(errInfo)")
        return maxErr
    }

    /// Helper to parse a 24-bit BMP file into planar R, G, B component data.
    /// Returns (redData, greenData, blueData, width, height) or nil on failure.
    private func parseBMP(at path: String) -> (Data, Data, Data, Int, Int)? {
        guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        guard fileData.count > 54 else { return nil }

        // BMP header
        let magic = fileData[0..<2]
        guard magic[0] == 0x42 && magic[1] == 0x4D else { return nil } // "BM"

        let pixelOffset = Int(fileData[10]) | (Int(fileData[11]) << 8) |
                          (Int(fileData[12]) << 16) | (Int(fileData[13]) << 24)
        let width = Int(fileData[18]) | (Int(fileData[19]) << 8) |
                    (Int(fileData[20]) << 16) | (Int(fileData[21]) << 24)
        var height = Int(fileData[22]) | (Int(fileData[23]) << 8) |
                     (Int(fileData[24]) << 16) | (Int(fileData[25]) << 24)
        let bpp = Int(fileData[28]) | (Int(fileData[29]) << 8)
        guard bpp == 24 else { return nil } // Only support 24-bit BMP

        let topDown = height < 0
        if topDown { height = -height }

        let rowStride = ((width * 3 + 3) / 4) * 4 // BMP rows are 4-byte aligned
        let pixelCount = width * height
        var red = Data(count: pixelCount)
        var green = Data(count: pixelCount)
        var blue = Data(count: pixelCount)

        for y in 0..<height {
            let srcRow = topDown ? y : (height - 1 - y)
            let rowOffset = pixelOffset + srcRow * rowStride
            for x in 0..<width {
                let px = rowOffset + x * 3
                guard px + 2 < fileData.count else { continue }
                let dstIdx = y * width + x
                blue[dstIdx] = fileData[px]     // BMP is BGR
                green[dstIdx] = fileData[px + 1]
                red[dstIdx] = fileData[px + 2]
            }
        }

        return (red, green, blue, width, height)
    }

    /// Encode blackbuck.bmp (512x512 RGB) to J2K and verify with OpenJPEG.
    func testBlackbuckBMP_RGB_Lossless() async throws {
        // Find blackbuck.bmp in the test resources
        let bmpPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("resources/blackbuck.bmp").path

        guard FileManager.default.fileExists(atPath: bmpPath) else {
            XCTFail("blackbuck.bmp not found at \(bmpPath)")
            return
        }

        guard let (red, green, blue, w, h) = parseBMP(at: bmpPath) else {
            XCTFail("Failed to parse blackbuck.bmp")
            return
        }

        print("[blackbuck] Loaded \(w)x\(h) RGB image")

        // Build J2KImage with 3 components
        let compR = J2KComponent(index: 0, bitDepth: 8, signed: false,
                                 width: w, height: h, data: red)
        let compG = J2KComponent(index: 1, bitDepth: 8, signed: false,
                                 width: w, height: h, data: green)
        let compB = J2KComponent(index: 2, bitDepth: 8, signed: false,
                                 width: w, height: h, data: blue)
        let image = J2KImage(width: w, height: h, components: [compR, compG, compB])

        // Encode lossless with 5-level DWT
        let config = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            decompositionLevels: 5,
            codeBlockSize: (32, 32))
        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)

        // Basic codestream checks
        XCTAssertEqual(encoded[0], 0xFF, "SOC[0]")
        XCTAssertEqual(encoded[1], 0x4F, "SOC[1]")
        XCTAssertEqual(encoded[encoded.count - 2], 0xFF, "EOC[-2]")
        XCTAssertEqual(encoded[encoded.count - 1], 0xD9, "EOC[-1]")
        print("[blackbuck] Encoded to \(encoded.count) bytes")

        // Write J2K
        let j2kPath = "\(outputDir)/blackbuck.j2k"
        try encoded.write(to: URL(fileURLWithPath: j2kPath))

        // Self round-trip first
        let selfDecoded = try await DecoderPipeline().decode(encoded)
        XCTAssertEqual(selfDecoded.width, w, "Self-decode width")
        XCTAssertEqual(selfDecoded.height, h, "Self-decode height")
        XCTAssertEqual(selfDecoded.components.count, 3, "Self-decode components")

        var selfMaxErr = 0
        for c in 0..<3 {
            let orig = [red, green, blue][c]
            let dec = selfDecoded.components[c].data
            for i in 0..<orig.count {
                let err = abs(Int(orig[i]) - Int(dec[i]))
                selfMaxErr = max(selfMaxErr, err)
            }
        }
        print("[blackbuck] Self round-trip maxErr=\(selfMaxErr)")
        XCTAssertEqual(selfMaxErr, 0, "Lossless self round-trip must be exact")

        // OpenJPEG decode
        guard FileManager.default.fileExists(atPath: opjDecompress) else {
            print("[blackbuck] SKIP OpenJPEG verification (opj_decompress not found)")
            return
        }

        // Decode to PPM (multi-component output)
        let ppmPath = "\(outputDir)/blackbuck.ppm"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: opjDecompress)
        proc.arguments = ["-i", j2kPath, "-o", ppmPath]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()

        let stderrData = (proc.standardError as! Pipe).fileHandleForReading.readDataToEndOfFile()
        let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""
        if proc.terminationStatus != 0 {
            print("[blackbuck] opj_decompress stderr: \(stderrStr)")
        }
        XCTAssertEqual(proc.terminationStatus, 0,
            "opj_decompress exit code \(proc.terminationStatus): \(stderrStr)")

        guard proc.terminationStatus == 0 else { return }

        // Parse PPM (P6 format: RGB binary)
        let ppmData = try Data(contentsOf: URL(fileURLWithPath: ppmPath))
        let (ppmPixels, ppmW, ppmH) = parsePPM(data: ppmData)
        XCTAssertEqual(ppmW, w, "PPM width")
        XCTAssertEqual(ppmH, h, "PPM height")
        XCTAssertEqual(ppmPixels.count, w * h * 3, "PPM pixel count")

        // Compare R, G, B channels
        var maxErr = 0
        var errInfo = ""
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let ppmOff = i * 3
                let origR = Int(red[i]), origG = Int(green[i]), origB = Int(blue[i])
                let decR = Int(ppmPixels[ppmOff])
                let decG = Int(ppmPixels[ppmOff + 1])
                let decB = Int(ppmPixels[ppmOff + 2])
                let errR = abs(origR - decR)
                let errG = abs(origG - decG)
                let errB = abs(origB - decB)
                let err = max(errR, max(errG, errB))
                if err > maxErr {
                    maxErr = err
                    errInfo = "at (\(x),\(y)): orig=(\(origR),\(origG),\(origB)) decoded=(\(decR),\(decG),\(decB))"
                }
            }
        }
        print("[blackbuck] OpenJPEG decode maxErr=\(maxErr) \(errInfo)")
        XCTAssertEqual(maxErr, 0, "Lossless RGB must be exact, maxErr=\(maxErr) \(errInfo)")
    }

    /// Parse a PPM (P6) file and return (pixels, width, height).
    /// Pixels are interleaved RGB.
    private func parsePPM(data: Data) -> ([UInt8], Int, Int) {
        var offset = 0
        let bytes = Array(data)

        func readLine() -> String? {
            guard offset < bytes.count else { return nil }
            var line = ""
            while offset < bytes.count {
                let ch = bytes[offset]
                offset += 1
                if ch == 0x0A { break }
                line.append(Character(UnicodeScalar(ch)))
            }
            return line
        }

        guard let magic = readLine(), magic == "P6" else { return ([], 0, 0) }

        var headerLines: [String] = []
        while headerLines.count < 2 {
            guard let line = readLine() else { return ([], 0, 0) }
            if line.hasPrefix("#") { continue }
            headerLines.append(line)
        }

        let dims = headerLines[0].split(separator: " ")
        guard dims.count >= 2,
              let w = Int(dims[0]),
              let h = Int(dims[1]) else { return ([], 0, 0) }

        return (Array(bytes[offset...]), w, h)
    }

    // MARK: - Lossy (9/7 Irreversible) Interop Tests

    /// Constant 200 image with lossy 9/7 DWT — OPJ must decode to ~200.
    func testLossy_Constant200_5LevelDWT() async throws {
        let w = 64, h = 64
        let pixels = Data(repeating: 200, count: w * h)
        let (maxErr, meanErr) = try await encodeAndVerify(
            name: "lossy_const200_5dwt", pixelData: pixels,
            width: w, height: h, lossless: false, decompositionLevels: 5)
        XCTAssertLessThanOrEqual(maxErr, 2,
            "Lossy constant image should reconstruct within 2, got maxErr=\(maxErr)")
        XCTAssertLessThan(meanErr, 1.0,
            "Lossy constant image mean error should be < 1")
    }

    /// Gradient image with lossy 9/7 DWT — OPJ must decode reasonably.
    func testLossy_Gradient256_5LevelDWT() async throws {
        let w = 256, h = 256
        var pixels = Data(count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                pixels[y * w + x] = UInt8(x % 256)
            }
        }
        let (maxErr, meanErr) = try await encodeAndVerify(
            name: "lossy_gradient256_5dwt", pixelData: pixels,
            width: w, height: h, lossless: false, decompositionLevels: 5)
        XCTAssertLessThanOrEqual(maxErr, 20,
            "Lossy gradient maxErr should be ≤ 20, got \(maxErr)")
        XCTAssertLessThan(meanErr, 5.0,
            "Lossy gradient mean error should be < 5")
    }

    /// Small checkerboard with lossy 9/7 DWT — tests high frequency content.
    func testLossy_Checkerboard64_3LevelDWT() async throws {
        let w = 64, h = 64
        var pixels = Data(count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                pixels[y * w + x] = ((x + y) % 2 == 0) ? 255 : 0
            }
        }
        let (maxErr, _) = try await encodeAndVerify(
            name: "lossy_checker64_3dwt", pixelData: pixels,
            width: w, height: h, lossless: false, decompositionLevels: 3)
        // Checkerboard is hardest for wavelet — allow more error
        XCTAssertLessThanOrEqual(maxErr, 50,
            "Lossy checkerboard maxErr should be ≤ 50, got \(maxErr)")
    }

    /// Medium natural-like pattern with lossy 9/7 DWT.
    func testLossy_Natural128_5LevelDWT() async throws {
        let w = 128, h = 128
        var pixels = Data(count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let val = Int(sin(Double(x) / 10.0) * 50 + cos(Double(y) / 8.0) * 40 + 128)
                pixels[y * w + x] = UInt8(clamping: val)
            }
        }
        let (maxErr, meanErr) = try await encodeAndVerify(
            name: "lossy_natural128_5dwt", pixelData: pixels,
            width: w, height: h, lossless: false, decompositionLevels: 5)
        XCTAssertLessThanOrEqual(maxErr, 100,
            "Lossy natural image maxErr should be ≤ 100, got \(maxErr)")
        XCTAssertLessThan(meanErr, 40.0,
            "Lossy natural image mean error should be < 40")
    }
}
