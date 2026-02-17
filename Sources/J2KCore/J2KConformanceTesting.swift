/// # JPEG 2000 Conformance Testing Framework
///
/// This framework provides tools for validating J2KSwift against the ISO/IEC 15444-4
/// conformance test suite and other reference implementations.
///
/// ## Topics
///
/// ### Test Validators
/// - ``J2KConformanceValidator``
/// - ``J2KErrorMetrics``
///
/// ### Test Vectors
/// - ``J2KTestVector``
/// - ``J2KReferenceCodestream``

import Foundation

// MARK: - Error Metrics

/// Calculates error metrics for comparing decoded images.
///
/// Implements standard image quality metrics used in JPEG 2000 conformance testing.
public struct J2KErrorMetrics: Sendable {
    
    /// Calculates Mean Squared Error (MSE) between two images.
    ///
    /// MSE is the average of the squared differences between corresponding pixels.
    ///
    /// - Parameters:
    ///   - reference: The reference image data.
    ///   - test: The test image data to compare.
    /// - Returns: The MSE value, or `nil` if images have different sizes.
    public static func meanSquaredError(
        reference: [Int32],
        test: [Int32]
    ) -> Double? {
        guard reference.count == test.count else {
            return nil
        }
        
        guard !reference.isEmpty else {
            return 0.0
        }
        
        var sum: Double = 0.0
        for i in 0..<reference.count {
            let diff = Double(reference[i] - test[i])
            sum += diff * diff
        }
        
        return sum / Double(reference.count)
    }
    
    /// Calculates Peak Signal-to-Noise Ratio (PSNR) between two images.
    ///
    /// PSNR is expressed in decibels (dB) and measures the ratio between
    /// the maximum possible signal power and the power of corrupting noise.
    ///
    /// - Parameters:
    ///   - reference: The reference image data.
    ///   - test: The test image data to compare.
    ///   - bitDepth: The bit depth of the image (default: 8).
    /// - Returns: The PSNR value in dB, or `nil` if calculation fails.
    public static func peakSignalToNoiseRatio(
        reference: [Int32],
        test: [Int32],
        bitDepth: Int = 8
    ) -> Double? {
        guard let mse = meanSquaredError(reference: reference, test: test) else {
            return nil
        }
        
        // If MSE is 0, images are identical (infinite PSNR)
        guard mse > 0 else {
            return Double.infinity
        }
        
        let maxValue = Double((1 << bitDepth) - 1)
        return 10.0 * log10((maxValue * maxValue) / mse)
    }
    
    /// Calculates Maximum Absolute Error (MAE) between two images.
    ///
    /// MAE is the maximum absolute difference between any two corresponding pixels.
    ///
    /// - Parameters:
    ///   - reference: The reference image data.
    ///   - test: The test image data to compare.
    /// - Returns: The MAE value, or `nil` if images have different sizes.
    public static func maximumAbsoluteError(
        reference: [Int32],
        test: [Int32]
    ) -> Int32? {
        guard reference.count == test.count else {
            return nil
        }
        
        guard !reference.isEmpty else {
            return 0
        }
        
        var maxError: Int32 = 0
        for i in 0..<reference.count {
            let error = abs(reference[i] - test[i])
            if error > maxError {
                maxError = error
            }
        }
        
        return maxError
    }
    
    /// Checks if two images are within an acceptable error tolerance.
    ///
    /// - Parameters:
    ///   - reference: The reference image data.
    ///   - test: The test image data to compare.
    ///   - maxError: Maximum allowable absolute error per pixel.
    /// - Returns: `true` if all pixels are within tolerance, `false` otherwise.
    public static func withinTolerance(
        reference: [Int32],
        test: [Int32],
        maxError: Int32
    ) -> Bool {
        guard let mae = maximumAbsoluteError(reference: reference, test: test) else {
            return false
        }
        return mae <= maxError
    }
}

// MARK: - Test Vector

/// Represents a JPEG 2000 test vector for conformance testing.
///
/// Test vectors consist of encoded codestreams and corresponding reference
/// decoded images, along with metadata about expected behavior.
public struct J2KTestVector: Sendable {
    /// The name of the test vector.
    public let name: String
    
    /// Description of what this test vector validates.
    public let description: String
    
    /// The encoded JPEG 2000 codestream.
    public let codestream: Data
    
    /// The expected decoded image data (if available).
    public let referenceImage: [Int32]?
    
    /// Expected image dimensions.
    public let width: Int
    public let height: Int
    
    /// Expected number of components.
    public let components: Int
    
    /// Expected bit depth per component.
    public let bitDepth: Int
    
    /// Maximum allowable error for conformance.
    ///
    /// Different conformance classes allow different error tolerances.
    /// - Lossless: 0
    /// - Lossy: typically 1-2 for near-lossless
    public let maxAllowableError: Int32
    
    /// Whether this test should decode successfully.
    ///
    /// Some test vectors are designed to test error handling for
    /// malformed or unsupported codestreams.
    public let shouldSucceed: Bool
    
    /// Creates a new test vector.
    public init(
        name: String,
        description: String,
        codestream: Data,
        referenceImage: [Int32]? = nil,
        width: Int,
        height: Int,
        components: Int,
        bitDepth: Int,
        maxAllowableError: Int32 = 0,
        shouldSucceed: Bool = true
    ) {
        self.name = name
        self.description = description
        self.codestream = codestream
        self.referenceImage = referenceImage
        self.width = width
        self.height = height
        self.components = components
        self.bitDepth = bitDepth
        self.maxAllowableError = maxAllowableError
        self.shouldSucceed = shouldSucceed
    }
}

// MARK: - Conformance Validator

/// Validates JPEG 2000 implementations against conformance requirements.
///
/// This validator checks that encoded/decoded images meet the error tolerances
/// specified in ISO/IEC 15444-4.
public struct J2KConformanceValidator: Sendable {
    
    /// Results from a conformance test.
    public struct TestResult: Sendable {
        /// The test vector that was run.
        public let vector: J2KTestVector
        
        /// Whether the test passed.
        public let passed: Bool
        
        /// Error message if the test failed.
        public let errorMessage: String?
        
        /// Calculated MSE (if applicable).
        public let mse: Double?
        
        /// Calculated PSNR (if applicable).
        public let psnr: Double?
        
        /// Calculated MAE (if applicable).
        public let mae: Int32?
    }
    
    /// Validates a decoded image against a test vector.
    ///
    /// - Parameters:
    ///   - decoded: The decoded image data.
    ///   - vector: The test vector with reference data.
    /// - Returns: The test result.
    public static func validate(
        decoded: [Int32],
        against vector: J2KTestVector
    ) -> TestResult {
        guard let referenceImage = vector.referenceImage else {
            return TestResult(
                vector: vector,
                passed: false,
                errorMessage: "No reference image available for validation",
                mse: nil,
                psnr: nil,
                mae: nil
            )
        }
        
        // Check size
        let expectedSize = vector.width * vector.height * vector.components
        guard decoded.count == expectedSize else {
            return TestResult(
                vector: vector,
                passed: false,
                errorMessage: "Size mismatch: expected \(expectedSize), got \(decoded.count)",
                mse: nil,
                psnr: nil,
                mae: nil
            )
        }
        
        // Calculate error metrics
        let mse = J2KErrorMetrics.meanSquaredError(reference: referenceImage, test: decoded)
        let psnr = J2KErrorMetrics.peakSignalToNoiseRatio(
            reference: referenceImage,
            test: decoded,
            bitDepth: vector.bitDepth
        )
        let mae = J2KErrorMetrics.maximumAbsoluteError(reference: referenceImage, test: decoded)
        
        guard let mae = mae else {
            return TestResult(
                vector: vector,
                passed: false,
                errorMessage: "Failed to calculate error metrics",
                mse: mse,
                psnr: psnr,
                mae: nil
            )
        }
        
        // Check against tolerance
        let passed = mae <= vector.maxAllowableError
        let errorMessage = passed ? nil : "MAE (\(mae)) exceeds maximum allowable error (\(vector.maxAllowableError))"
        
        return TestResult(
            vector: vector,
            passed: passed,
            errorMessage: errorMessage,
            mse: mse,
            psnr: psnr,
            mae: mae
        )
    }
    
    /// Runs a suite of conformance tests.
    ///
    /// - Parameter vectors: The test vectors to run.
    /// - Returns: Array of test results.
    public static func runTestSuite(
        vectors: [J2KTestVector],
        decoder: (Data) throws -> [Int32]
    ) -> [TestResult] {
        var results: [TestResult] = []
        
        for vector in vectors {
            do {
                let decoded = try decoder(vector.codestream)
                let result = validate(decoded: decoded, against: vector)
                results.append(result)
            } catch {
                results.append(TestResult(
                    vector: vector,
                    passed: !vector.shouldSucceed,
                    errorMessage: vector.shouldSucceed ? "Decoding failed: \(error)" : nil,
                    mse: nil,
                    psnr: nil,
                    mae: nil
                ))
            }
        }
        
        return results
    }
    
    /// Generates a conformance report.
    ///
    /// - Parameter results: The test results.
    /// - Returns: A formatted string report.
    public static func generateReport(results: [TestResult]) -> String {
        var report = "JPEG 2000 Conformance Test Report\n"
        report += String(repeating: "=", count: 50) + "\n\n"
        
        let passed = results.filter { $0.passed }.count
        let total = results.count
        let percentage = total > 0 ? Double(passed) / Double(total) * 100.0 : 0.0
        
        report += "Summary: \(passed)/\(total) tests passed (\(String(format: "%.1f", percentage))%)\n\n"
        
        // Failed tests
        let failures = results.filter { !$0.passed }
        if !failures.isEmpty {
            report += "Failed Tests:\n"
            report += String(repeating: "-", count: 50) + "\n"
            for result in failures {
                report += "  \(result.vector.name): \(result.errorMessage ?? "Unknown error")\n"
                if let mae = result.mae {
                    report += "    MAE: \(mae) (max allowed: \(result.vector.maxAllowableError))\n"
                }
                if let psnr = result.psnr {
                    report += "    PSNR: \(String(format: "%.2f", psnr)) dB\n"
                }
            }
            report += "\n"
        }
        
        return report
    }
}

// MARK: - ISO Test Suite Loader

/// Loads and manages ISO/IEC 15444-4 conformance test vectors.
///
/// This loader supports importing test vectors from external ISO test suite files
/// when the official test suite has been acquired. It also provides built-in
/// synthetic test vectors based on the ISO/IEC 15444-4 specification for
/// validation without the official test suite.
///
/// ## Usage
///
/// ```swift
/// // Load from directory
/// let loader = J2KISOTestSuiteLoader()
/// let vectors = try loader.loadTestVectors(from: "/path/to/iso-test-suite")
///
/// // Use built-in synthetic vectors
/// let syntheticVectors = J2KISOTestSuiteLoader.syntheticTestVectors()
/// ```
public struct J2KISOTestSuiteLoader: Sendable {
    
    /// ISO conformance class for categorizing test vectors.
    public enum ConformanceClass: String, Sendable, CaseIterable {
        /// Profile 0: Baseline JPEG 2000 features.
        case profile0 = "Profile-0"
        /// Profile 1: Extended features including ROI and multiple tile parts.
        case profile1 = "Profile-1"
        /// HTJ2K: High Throughput JPEG 2000 (ISO/IEC 15444-15).
        case htj2k = "HTJ2K"
    }
    
    /// Wavelet filter type used in conformance testing.
    public enum WaveletFilter: String, Sendable {
        /// Reversible 5/3 wavelet filter for lossless compression.
        case reversible5_3 = "5/3"
        /// Irreversible 9/7 wavelet filter for lossy compression.
        case irreversible9_7 = "9/7"
    }
    
    /// Represents metadata for an ISO test case.
    public struct ISOTestCase: Sendable {
        /// Unique identifier for the test case.
        public let identifier: String
        /// Conformance class this test belongs to.
        public let conformanceClass: ConformanceClass
        /// Description of the test case.
        public let description: String
        /// Wavelet filter used.
        public let waveletFilter: WaveletFilter
        /// Number of components.
        public let components: Int
        /// Bit depth per component.
        public let bitDepth: Int
        /// Image width.
        public let width: Int
        /// Image height.
        public let height: Int
        /// Maximum allowable error per ISO spec.
        public let maxAllowableError: Int32
        /// Whether lossless decoding is expected.
        public let isLossless: Bool
        
        /// Creates a new ISO test case.
        public init(
            identifier: String,
            conformanceClass: ConformanceClass,
            description: String,
            waveletFilter: WaveletFilter,
            components: Int,
            bitDepth: Int,
            width: Int,
            height: Int,
            maxAllowableError: Int32,
            isLossless: Bool
        ) {
            self.identifier = identifier
            self.conformanceClass = conformanceClass
            self.description = description
            self.waveletFilter = waveletFilter
            self.components = components
            self.bitDepth = bitDepth
            self.width = width
            self.height = height
            self.maxAllowableError = maxAllowableError
            self.isLossless = isLossless
        }
    }
    
    /// Creates a new ISO test suite loader.
    public init() {}
    
    /// Loads test vectors from an ISO test suite directory.
    ///
    /// Expects the directory to contain `.j2k` or `.j2c` codestream files
    /// and corresponding `.raw` or `.pgm` reference image files.
    ///
    /// - Parameter path: Path to the ISO test suite directory.
    /// - Returns: Array of test vectors loaded from the directory.
    /// - Throws: Error if the directory cannot be read.
    public func loadTestVectors(from path: String) throws -> [J2KTestVector] {
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)
        
        guard fileManager.fileExists(atPath: path) else {
            throw J2KError.invalidParameter("ISO test suite directory not found: \(path)")
        }
        
        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        )
        
        let codestreamFiles = contents.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "j2k" || ext == "j2c" || ext == "jp2"
        }
        
        var vectors: [J2KTestVector] = []
        
        for codestreamFile in codestreamFiles {
            let name = codestreamFile.deletingPathExtension().lastPathComponent
            let codestream = try Data(contentsOf: codestreamFile)
            
            // Look for corresponding reference image
            let referenceImage = loadReferenceImage(
                named: name,
                in: url
            )
            
            // Parse test case metadata from filename if possible
            let testCase = parseTestCaseMetadata(from: name)
            
            let vector = J2KTestVector(
                name: name,
                description: testCase?.description ?? "ISO test vector: \(name)",
                codestream: codestream,
                referenceImage: referenceImage?.pixels,
                width: referenceImage?.width ?? testCase?.width ?? 0,
                height: referenceImage?.height ?? testCase?.height ?? 0,
                components: referenceImage?.components ?? testCase?.components ?? 1,
                bitDepth: testCase?.bitDepth ?? 8,
                maxAllowableError: testCase?.maxAllowableError ?? 0
            )
            vectors.append(vector)
        }
        
        return vectors
    }
    
    /// Checks if the ISO test suite is available at the given path.
    ///
    /// - Parameter path: Path to check for the ISO test suite.
    /// - Returns: `true` if the test suite directory exists and contains test files.
    public func isTestSuiteAvailable(at path: String) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else { return false }
        
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else {
            return false
        }
        
        return contents.contains { name in
            let ext = (name as NSString).pathExtension.lowercased()
            return ext == "j2k" || ext == "j2c" || ext == "jp2"
        }
    }
    
    /// Returns the catalog of ISO/IEC 15444-4 test cases.
    ///
    /// This catalog describes the expected test cases from the official ISO test suite.
    /// Each entry specifies the expected image properties and error tolerances.
    ///
    /// - Returns: Array of ISO test case descriptors.
    public static func isoTestCaseCatalog() -> [ISOTestCase] {
        return [
            // Profile 0 - Baseline Lossless Tests
            ISOTestCase(
                identifier: "p0_01",
                conformanceClass: .profile0,
                description: "Profile-0 lossless grayscale 8-bit",
                waveletFilter: .reversible5_3,
                components: 1, bitDepth: 8,
                width: 256, height: 256,
                maxAllowableError: 0, isLossless: true
            ),
            ISOTestCase(
                identifier: "p0_02",
                conformanceClass: .profile0,
                description: "Profile-0 lossless RGB 8-bit",
                waveletFilter: .reversible5_3,
                components: 3, bitDepth: 8,
                width: 256, height: 256,
                maxAllowableError: 0, isLossless: true
            ),
            ISOTestCase(
                identifier: "p0_03",
                conformanceClass: .profile0,
                description: "Profile-0 lossy grayscale 8-bit",
                waveletFilter: .irreversible9_7,
                components: 1, bitDepth: 8,
                width: 256, height: 256,
                maxAllowableError: 4, isLossless: false
            ),
            ISOTestCase(
                identifier: "p0_04",
                conformanceClass: .profile0,
                description: "Profile-0 lossy RGB 8-bit",
                waveletFilter: .irreversible9_7,
                components: 3, bitDepth: 8,
                width: 256, height: 256,
                maxAllowableError: 4, isLossless: false
            ),
            ISOTestCase(
                identifier: "p0_05",
                conformanceClass: .profile0,
                description: "Profile-0 lossless grayscale 12-bit",
                waveletFilter: .reversible5_3,
                components: 1, bitDepth: 12,
                width: 128, height: 128,
                maxAllowableError: 0, isLossless: true
            ),
            ISOTestCase(
                identifier: "p0_06",
                conformanceClass: .profile0,
                description: "Profile-0 lossless grayscale 16-bit",
                waveletFilter: .reversible5_3,
                components: 1, bitDepth: 16,
                width: 64, height: 64,
                maxAllowableError: 0, isLossless: true
            ),
            // Profile 1 - Extended Tests
            ISOTestCase(
                identifier: "p1_01",
                conformanceClass: .profile1,
                description: "Profile-1 tiled lossless grayscale",
                waveletFilter: .reversible5_3,
                components: 1, bitDepth: 8,
                width: 256, height: 256,
                maxAllowableError: 0, isLossless: true
            ),
            ISOTestCase(
                identifier: "p1_02",
                conformanceClass: .profile1,
                description: "Profile-1 multi-component lossy",
                waveletFilter: .irreversible9_7,
                components: 4, bitDepth: 8,
                width: 128, height: 128,
                maxAllowableError: 4, isLossless: false
            ),
            // HTJ2K Tests
            ISOTestCase(
                identifier: "htj2k_01",
                conformanceClass: .htj2k,
                description: "HTJ2K lossless grayscale 8-bit",
                waveletFilter: .reversible5_3,
                components: 1, bitDepth: 8,
                width: 256, height: 256,
                maxAllowableError: 0, isLossless: true
            ),
            ISOTestCase(
                identifier: "htj2k_02",
                conformanceClass: .htj2k,
                description: "HTJ2K lossy RGB 8-bit",
                waveletFilter: .irreversible9_7,
                components: 3, bitDepth: 8,
                width: 256, height: 256,
                maxAllowableError: 4, isLossless: false
            ),
        ]
    }
    
    /// Generates synthetic test vectors based on ISO/IEC 15444-4 specifications.
    ///
    /// These vectors simulate the characteristics of official ISO test cases
    /// using generated test images. They validate the same conformance criteria
    /// without requiring the official test suite.
    ///
    /// - Returns: Array of synthetic test vectors.
    public static func syntheticTestVectors() -> [J2KTestVector] {
        var vectors: [J2KTestVector] = []
        
        for testCase in isoTestCaseCatalog() {
            let pixelCount = testCase.width * testCase.height * testCase.components
            let referenceImage = generateTestImage(
                width: testCase.width,
                height: testCase.height,
                components: testCase.components,
                bitDepth: testCase.bitDepth
            )
            
            let vector = J2KTestVector(
                name: testCase.identifier,
                description: testCase.description,
                codestream: Data(),  // Will be generated by encoder during test
                referenceImage: referenceImage,
                width: testCase.width,
                height: testCase.height,
                components: testCase.components,
                bitDepth: testCase.bitDepth,
                maxAllowableError: testCase.maxAllowableError
            )
            vectors.append(vector)
        }
        
        return vectors
    }
    
    /// Generates a deterministic test image for conformance testing.
    ///
    /// Creates a gradient pattern that exercises the full dynamic range
    /// and provides a repeatable test stimulus.
    ///
    /// - Parameters:
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - components: Number of image components.
    ///   - bitDepth: Bit depth per component.
    /// - Returns: Array of Int32 pixel values.
    public static func generateTestImage(
        width: Int,
        height: Int,
        components: Int,
        bitDepth: Int
    ) -> [Int32] {
        let maxValue = Int32((1 << bitDepth) - 1)
        var pixels = [Int32]()
        pixels.reserveCapacity(width * height * components)
        
        for c in 0..<components {
            for y in 0..<height {
                for x in 0..<width {
                    // Generate a deterministic gradient pattern
                    let normalizedX = Double(x) / Double(max(1, width - 1))
                    let normalizedY = Double(y) / Double(max(1, height - 1))
                    
                    // Different pattern per component for diversity
                    let value: Double
                    switch c % 3 {
                    case 0:
                        value = normalizedX * Double(maxValue)
                    case 1:
                        value = normalizedY * Double(maxValue)
                    default:
                        value = (normalizedX + normalizedY) / 2.0 * Double(maxValue)
                    }
                    
                    pixels.append(Int32(min(Double(maxValue), max(0, value))))
                }
            }
        }
        
        return pixels
    }
    
    // MARK: - Private Helpers
    
    /// Reference image data loaded from file.
    private struct ReferenceImageData {
        let pixels: [Int32]
        let width: Int
        let height: Int
        let components: Int
    }
    
    /// Loads a reference image from the test suite directory.
    private func loadReferenceImage(
        named name: String,
        in directory: URL
    ) -> ReferenceImageData? {
        // Try common reference image formats
        let extensions = ["raw", "pgm", "ppm", "rawl"]
        
        for ext in extensions {
            let url = directory.appendingPathComponent("\(name).\(ext)")
            guard let data = try? Data(contentsOf: url) else { continue }
            
            if ext == "pgm" || ext == "ppm" {
                return parsePNMImage(data: data)
            } else {
                // Raw format - need metadata to interpret
                return nil
            }
        }
        
        return nil
    }
    
    /// Parses a PNM (PGM/PPM) format image.
    private func parsePNMImage(data: Data) -> ReferenceImageData? {
        guard data.count > 3 else { return nil }
        
        let bytes = [UInt8](data)
        guard bytes[0] == 0x50 else { return nil } // 'P'
        
        let isPGM = bytes[1] == 0x35  // 'P5' = binary PGM
        let isPPM = bytes[1] == 0x36  // 'P6' = binary PPM
        guard isPGM || isPPM else { return nil }
        
        // Parse header (simplified)
        var offset = 2
        
        // Skip whitespace and comments
        func skipWhitespaceAndComments() {
            while offset < bytes.count {
                if bytes[offset] == 0x23 { // '#'
                    while offset < bytes.count && bytes[offset] != 0x0A { offset += 1 }
                }
                if offset < bytes.count && (bytes[offset] == 0x20 || bytes[offset] == 0x0A || bytes[offset] == 0x0D || bytes[offset] == 0x09) {
                    offset += 1
                } else {
                    break
                }
            }
        }
        
        func readNumber() -> Int? {
            skipWhitespaceAndComments()
            var num = 0
            var found = false
            while offset < bytes.count && bytes[offset] >= 0x30 && bytes[offset] <= 0x39 {
                num = num * 10 + Int(bytes[offset] - 0x30)
                offset += 1
                found = true
            }
            return found ? num : nil
        }
        
        guard let width = readNumber(),
              let height = readNumber(),
              let maxVal = readNumber() else {
            return nil
        }
        
        // Skip single whitespace after maxVal
        offset += 1
        
        let components = isPPM ? 3 : 1
        let bytesPerPixel = maxVal > 255 ? 2 : 1
        let expectedBytes = width * height * components * bytesPerPixel
        
        guard offset + expectedBytes <= data.count else { return nil }
        
        var pixels = [Int32]()
        pixels.reserveCapacity(width * height * components)
        
        for i in 0..<(width * height * components) {
            if bytesPerPixel == 2 {
                let high = Int32(bytes[offset + i * 2])
                let low = Int32(bytes[offset + i * 2 + 1])
                pixels.append((high << 8) | low)
            } else {
                pixels.append(Int32(bytes[offset + i]))
            }
        }
        
        return ReferenceImageData(
            pixels: pixels,
            width: width,
            height: height,
            components: components
        )
    }
    
    /// Parses test case metadata from a filename.
    private func parseTestCaseMetadata(from name: String) -> ISOTestCase? {
        let catalog = Self.isoTestCaseCatalog()
        return catalog.first { $0.identifier == name }
    }
}

// MARK: - Platform Information

/// Provides platform detection and capability reporting for cross-platform validation.
///
/// This utility helps identify the current platform and available features,
/// enabling platform-aware testing and graceful degradation.
public struct J2KPlatformInfo: Sendable {
    
    /// The operating system family.
    public enum OperatingSystem: String, Sendable {
        case macOS = "macOS"
        case iOS = "iOS"
        case tvOS = "tvOS"
        case watchOS = "watchOS"
        case visionOS = "visionOS"
        case linux = "Linux"
        case windows = "Windows"
        case unknown = "Unknown"
    }
    
    /// The CPU architecture.
    public enum Architecture: String, Sendable {
        case arm64 = "arm64"
        case x86_64 = "x86_64"
        case arm = "arm"
        case i386 = "i386"
        case unknown = "Unknown"
    }
    
    /// Returns the current operating system.
    public static var currentOS: OperatingSystem {
        #if os(macOS)
        return .macOS
        #elseif os(iOS)
        return .iOS
        #elseif os(tvOS)
        return .tvOS
        #elseif os(watchOS)
        return .watchOS
        #elseif os(visionOS)
        return .visionOS
        #elseif os(Linux)
        return .linux
        #elseif os(Windows)
        return .windows
        #else
        return .unknown
        #endif
    }
    
    /// Returns the current CPU architecture.
    public static var currentArchitecture: Architecture {
        #if arch(arm64)
        return .arm64
        #elseif arch(x86_64)
        return .x86_64
        #elseif arch(arm)
        return .arm
        #elseif arch(i386)
        return .i386
        #else
        return .unknown
        #endif
    }
    
    /// Whether hardware-accelerated operations are available.
    public static var hasHardwareAcceleration: Bool {
        #if canImport(Accelerate)
        return true
        #else
        return false
        #endif
    }
    
    /// Whether the platform is an Apple platform.
    public static var isApplePlatform: Bool {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        return true
        #else
        return false
        #endif
    }
    
    /// Returns a summary of the current platform capabilities.
    ///
    /// - Returns: A formatted string describing the platform.
    public static func platformSummary() -> String {
        var summary = "J2KSwift Platform Info\n"
        summary += "  OS: \(currentOS.rawValue)\n"
        summary += "  Architecture: \(currentArchitecture.rawValue)\n"
        summary += "  Apple Platform: \(isApplePlatform)\n"
        summary += "  Hardware Acceleration: \(hasHardwareAcceleration)\n"
        summary += "  Pointer Size: \(MemoryLayout<Int>.size * 8)-bit\n"
        summary += "  Byte Order: \(isLittleEndian ? "Little Endian" : "Big Endian")\n"
        return summary
    }
    
    /// Whether the platform uses little-endian byte order.
    public static var isLittleEndian: Bool {
        let value: UInt16 = 0x0001
        return withUnsafeBytes(of: value) { $0[0] == 1 }
    }
    
    /// The pointer size in bytes on the current platform.
    public static var pointerSize: Int {
        return MemoryLayout<Int>.size
    }
}
