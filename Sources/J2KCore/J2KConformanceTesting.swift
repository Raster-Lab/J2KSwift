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

// MARK: - HTJ2K Test Vector Generator

/// Generates synthetic test vectors for HTJ2K conformance testing.
///
/// This generator creates test codestreams and reference images for validating
/// HTJ2K encoders and decoders. Test vectors include various patterns and edge
/// cases to ensure comprehensive coverage.
public struct HTJ2KTestVectorGenerator: Sendable {
    
    /// Types of test patterns that can be generated.
    public enum TestPattern: Sendable {
        /// Solid color pattern (all pixels same value).
        case solid(value: Int32)
        
        /// Gradient pattern (linear ramp from 0 to max value).
        case gradient
        
        /// Checkerboard pattern (alternating black and white squares).
        case checkerboard(squareSize: Int)
        
        /// Random noise pattern.
        case randomNoise(seed: UInt64)
        
        /// Frequency sweep pattern (sinusoidal with increasing frequency).
        case frequencySweep
        
        /// Edge pattern (sharp transitions to test high-frequency coding).
        case edges
    }
    
    /// Configuration for test vector generation.
    public struct Configuration: Sendable {
        /// Image width in pixels.
        public let width: Int
        
        /// Image height in pixels.
        public let height: Int
        
        /// Number of components (1 for grayscale, 3 for RGB).
        public let components: Int
        
        /// Bit depth per component.
        public let bitDepth: Int
        
        /// Test pattern to generate.
        public let pattern: TestPattern
        
        /// Whether to use lossless compression.
        public let lossless: Bool
        
        /// Quality factor for lossy compression (0.0-1.0).
        public let quality: Double
        
        /// Whether to use HTJ2K or legacy coding.
        public let useHTJ2K: Bool
        
        /// Creates a new test vector configuration.
        public init(
            width: Int,
            height: Int,
            components: Int,
            bitDepth: Int,
            pattern: TestPattern,
            lossless: Bool = true,
            quality: Double = 1.0,
            useHTJ2K: Bool = true
        ) {
            self.width = width
            self.height = height
            self.components = components
            self.bitDepth = bitDepth
            self.pattern = pattern
            self.lossless = lossless
            self.quality = quality
            self.useHTJ2K = useHTJ2K
        }
    }
    
    /// Generates a test image based on the specified pattern.
    ///
    /// - Parameters:
    ///   - config: Configuration specifying the test pattern and image parameters.
    /// - Returns: Array of pixel values for the test image.
    public static func generateImage(config: Configuration) -> [Int32] {
        let pixelCount = config.width * config.height * config.components
        var pixels = [Int32](repeating: 0, count: pixelCount)
        let maxValue = Int32((1 << config.bitDepth) - 1)
        
        switch config.pattern {
        case .solid(let value):
            pixels = [Int32](repeating: min(value, maxValue), count: pixelCount)
            
        case .gradient:
            for y in 0..<config.height {
                for x in 0..<config.width {
                    let value = Int32((Double(x + y) / Double(config.width + config.height)) * Double(maxValue))
                    for c in 0..<config.components {
                        let index = (y * config.width + x) * config.components + c
                        pixels[index] = value
                    }
                }
            }
            
        case .checkerboard(let squareSize):
            for y in 0..<config.height {
                for x in 0..<config.width {
                    let checkX = (x / squareSize) % 2
                    let checkY = (y / squareSize) % 2
                    let value: Int32 = (checkX + checkY) % 2 == 0 ? 0 : maxValue
                    for c in 0..<config.components {
                        let index = (y * config.width + x) * config.components + c
                        pixels[index] = value
                    }
                }
            }
            
        case .randomNoise(let seed):
            var rng = SeededRandomNumberGenerator(seed: seed)
            for i in 0..<pixelCount {
                pixels[i] = Int32.random(in: 0...maxValue, using: &rng)
            }
            
        case .frequencySweep:
            for y in 0..<config.height {
                for x in 0..<config.width {
                    let freq = Double(x) / Double(config.width) * 10.0
                    let phase = Double(y) / Double(config.height) * 2.0 * .pi
                    let sine = sin(freq * phase)
                    let value = Int32((sine + 1.0) / 2.0 * Double(maxValue))
                    for c in 0..<config.components {
                        let index = (y * config.width + x) * config.components + c
                        pixels[index] = value
                    }
                }
            }
            
        case .edges:
            for y in 0..<config.height {
                for x in 0..<config.width {
                    let isEdge = (x % 8 == 0) || (y % 8 == 0)
                    let value: Int32 = isEdge ? maxValue : 0
                    for c in 0..<config.components {
                        let index = (y * config.width + x) * config.components + c
                        pixels[index] = value
                    }
                }
            }
        }
        
        return pixels
    }
    
    /// Creates a test vector with the specified configuration.
    ///
    /// - Parameters:
    ///   - name: Name of the test vector.
    ///   - description: Description of what the test validates.
    ///   - config: Configuration for the test vector.
    /// - Returns: A complete test vector with reference image.
    public static func createTestVector(
        name: String,
        description: String,
        config: Configuration
    ) -> J2KTestVector {
        let referenceImage = generateImage(config: config)
        
        return J2KTestVector(
            name: name,
            description: description,
            codestream: Data(), // Codestream should be generated by encoding the reference image
            referenceImage: referenceImage,
            width: config.width,
            height: config.height,
            components: config.components,
            bitDepth: config.bitDepth,
            maxAllowableError: config.lossless ? 0 : 2,
            shouldSucceed: true
        )
    }
}

// MARK: - Seeded Random Number Generator

/// A simple seeded random number generator for reproducible test data.
private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed
    }
    
    mutating func next() -> UInt64 {
        // Linear congruential generator
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

// MARK: - HTJ2K Conformance Test Harness

/// Comprehensive test harness for validating HTJ2K implementations.
///
/// This harness extends the basic conformance validator with HTJ2K-specific
/// validation rules and test scenarios as specified in ISO/IEC 15444-15.
public struct HTJ2KConformanceTestHarness: Sendable {
    
    /// HTJ2K-specific validation rules.
    public struct ValidationRules: Sendable {
        /// Whether to validate CAP marker presence.
        public let requireCAPMarker: Bool
        
        /// Whether to validate CPF marker presence.
        public let requireCPFMarker: Bool
        
        /// Whether to validate HT set parameters in COD/COC markers.
        public let validateHTSetParameters: Bool
        
        /// Whether to validate mixed-mode codestreams (HT + legacy blocks).
        public let allowMixedMode: Bool
        
        /// Maximum allowable encoding/decoding time in seconds.
        public let maxProcessingTime: Double?
        
        /// Creates new validation rules.
        public init(
            requireCAPMarker: Bool = true,
            requireCPFMarker: Bool = true,
            validateHTSetParameters: Bool = true,
            allowMixedMode: Bool = false,
            maxProcessingTime: Double? = nil
        ) {
            self.requireCAPMarker = requireCAPMarker
            self.requireCPFMarker = requireCPFMarker
            self.validateHTSetParameters = validateHTSetParameters
            self.allowMixedMode = allowMixedMode
            self.maxProcessingTime = maxProcessingTime
        }
    }
    
    /// Result of HTJ2K-specific validation.
    public struct HTValidationResult: Sendable {
        /// Basic conformance test result.
        public let conformanceResult: J2KConformanceValidator.TestResult
        
        /// Whether CAP marker was found (if required).
        public let hasCAPMarker: Bool?
        
        /// Whether CPF marker was found (if required).
        public let hasCPFMarker: Bool?
        
        /// Whether HT set parameters were valid (if validated).
        public let validHTSetParameters: Bool?
        
        /// Whether mixed-mode coding was detected.
        public let isMixedMode: Bool?
        
        /// Processing time in seconds.
        public let processingTime: Double?
        
        /// Additional validation errors specific to HTJ2K.
        public let htValidationErrors: [String]
        
        /// Overall pass/fail status.
        public var passed: Bool {
            conformanceResult.passed && htValidationErrors.isEmpty
        }
    }
    
    /// The validation rules to apply.
    public let rules: ValidationRules
    
    /// Creates a new HTJ2K conformance test harness.
    ///
    /// - Parameter rules: Validation rules to apply.
    public init(rules: ValidationRules = ValidationRules()) {
        self.rules = rules
    }
    
    /// Validates HTJ2K codestream structure.
    ///
    /// This performs basic marker validation without full decoding.
    ///
    /// - Parameter codestream: The HTJ2K codestream data.
    /// - Returns: Validation errors, if any.
    public func validateCodestreamStructure(_ codestream: Data) -> [String] {
        var errors: [String] = []
        
        // Check minimum size
        guard codestream.count >= 2 else {
            errors.append("Codestream too short")
            return errors
        }
        
        // Check for JPEG 2000 SOC marker (0xFF4F)
        if codestream.count >= 2 {
            let soc = (UInt16(codestream[0]) << 8) | UInt16(codestream[1])
            if soc != 0xFF4F {
                errors.append("Missing or invalid SOC marker")
            }
        }
        
        // Scan for required markers
        var hasCAP = false
        var hasCPF = false
        var hasCOD = false
        
        var offset = 2  // Skip SOC
        while offset + 2 <= codestream.count {
            let marker = (UInt16(codestream[offset]) << 8) | UInt16(codestream[offset + 1])
            offset += 2
            
            // Check marker length
            guard offset + 2 <= codestream.count else { break }
            let length = (Int(codestream[offset]) << 8) | Int(codestream[offset + 1])
            
            switch marker {
            case 0xFF50:  // CAP
                hasCAP = true
            case 0xFF59:  // CPF
                hasCPF = true
            case 0xFF52:  // COD
                hasCOD = true
            case 0xFF93:  // SOD (start of data)
                // Stop scanning at SOD
                offset = codestream.count
            default:
                break
            }
            
            offset += length
        }
        
        if rules.requireCAPMarker && !hasCAP {
            errors.append("Missing required CAP marker for HTJ2K")
        }
        
        if rules.requireCPFMarker && !hasCPF {
            errors.append("Missing required CPF marker for HTJ2K")
        }
        
        if !hasCOD {
            errors.append("Missing required COD marker")
        }
        
        return errors
    }
    
    /// Validates a decoded image with HTJ2K-specific checks.
    ///
    /// - Parameters:
    ///   - decoded: The decoded image data.
    ///   - vector: The test vector with reference data.
    ///   - codestream: The encoded codestream (for marker validation).
    ///   - processingTime: Time taken to encode/decode (optional).
    /// - Returns: HTJ2K validation result.
    public func validate(
        decoded: [Int32],
        against vector: J2KTestVector,
        codestream: Data,
        processingTime: Double? = nil
    ) -> HTValidationResult {
        // First, perform standard conformance validation
        let conformanceResult = J2KConformanceValidator.validate(
            decoded: decoded,
            against: vector
        )
        
        // Then perform HTJ2K-specific validation
        let structureErrors = validateCodestreamStructure(codestream)
        
        // Check processing time if specified
        var timeErrors: [String] = []
        if let maxTime = rules.maxProcessingTime,
           let actualTime = processingTime,
           actualTime > maxTime {
            timeErrors.append("Processing time \(actualTime)s exceeds maximum \(maxTime)s")
        }
        
        // For now, we'll set these to nil since we need actual marker parsing
        // A full implementation would parse the codestream to extract these
        let hasCAPMarker: Bool? = nil
        let hasCPFMarker: Bool? = nil
        let validHTSetParameters: Bool? = nil
        let isMixedMode: Bool? = nil
        
        return HTValidationResult(
            conformanceResult: conformanceResult,
            hasCAPMarker: hasCAPMarker,
            hasCPFMarker: hasCPFMarker,
            validHTSetParameters: validHTSetParameters,
            isMixedMode: isMixedMode,
            processingTime: processingTime,
            htValidationErrors: structureErrors + timeErrors
        )
    }
    
    /// Generates a comprehensive report for multiple HTJ2K validation results.
    ///
    /// - Parameter results: Array of validation results.
    /// - Returns: Formatted report string.
    public static func generateReport(results: [HTValidationResult]) -> String {
        var report = "HTJ2K Conformance Test Report\n"
        report += "==============================\n\n"
        
        let passCount = results.filter { $0.passed }.count
        let totalCount = results.count
        let passRate = totalCount > 0 ? Double(passCount) / Double(totalCount) * 100.0 : 0.0
        
        report += "Summary: \(passCount)/\(totalCount) tests passed (\(String(format: "%.1f", passRate))%)\n\n"
        
        // Detailed results
        for (index, result) in results.enumerated() {
            let status = result.passed ? "✓ PASS" : "✗ FAIL"
            report += "Test \(index + 1): \(status)\n"
            report += "  Name: \(result.conformanceResult.vector.name)\n"
            
            if let mae = result.conformanceResult.mae {
                report += "  MAE: \(mae)\n"
            }
            if let psnr = result.conformanceResult.psnr {
                report += "  PSNR: \(String(format: "%.2f", psnr)) dB\n"
            }
            if let time = result.processingTime {
                report += "  Processing Time: \(String(format: "%.3f", time))s\n"
            }
            
            if !result.htValidationErrors.isEmpty {
                report += "  HTJ2K Validation Errors:\n"
                for error in result.htValidationErrors {
                    report += "    - \(error)\n"
                }
            }
            
            if let errorMsg = result.conformanceResult.errorMessage {
                report += "  Error: \(errorMsg)\n"
            }
            
            report += "\n"
        }
        
        return report
    }
    
    /// Creates a standard set of HTJ2K test vectors for basic conformance testing.
    ///
    /// - Returns: Array of test vectors covering common scenarios.
    public static func createStandardTestVectors() -> [J2KTestVector] {
        var vectors: [J2KTestVector] = []
        
        // 1. Lossless grayscale
        let losslessGrayConfig = HTJ2KTestVectorGenerator.Configuration(
            width: 64,
            height: 64,
            components: 1,
            bitDepth: 8,
            pattern: .checkerboard(squareSize: 8),
            lossless: true,
            useHTJ2K: true
        )
        vectors.append(HTJ2KTestVectorGenerator.createTestVector(
            name: "htj2k_lossless_gray_64x64",
            description: "Lossless HTJ2K encoding of 64×64 grayscale checkerboard",
            config: losslessGrayConfig
        ))
        
        // 2. Lossy RGB
        let lossyRGBConfig = HTJ2KTestVectorGenerator.Configuration(
            width: 128,
            height: 128,
            components: 3,
            bitDepth: 8,
            pattern: .gradient,
            lossless: false,
            quality: 0.9,
            useHTJ2K: true
        )
        vectors.append(HTJ2KTestVectorGenerator.createTestVector(
            name: "htj2k_lossy_rgb_128x128",
            description: "Lossy HTJ2K encoding of 128×128 RGB gradient",
            config: lossyRGBConfig
        ))
        
        // 3. High-frequency edges
        let edgesConfig = HTJ2KTestVectorGenerator.Configuration(
            width: 32,
            height: 32,
            components: 1,
            bitDepth: 8,
            pattern: .edges,
            lossless: true,
            useHTJ2K: true
        )
        vectors.append(HTJ2KTestVectorGenerator.createTestVector(
            name: "htj2k_edges_32x32",
            description: "HTJ2K encoding of high-frequency edge pattern",
            config: edgesConfig
        ))
        
        // 4. Random noise
        let noiseConfig = HTJ2KTestVectorGenerator.Configuration(
            width: 64,
            height: 64,
            components: 1,
            bitDepth: 8,
            pattern: .randomNoise(seed: 42),
            lossless: false,
            quality: 0.8,
            useHTJ2K: true
        )
        vectors.append(HTJ2KTestVectorGenerator.createTestVector(
            name: "htj2k_noise_64x64",
            description: "HTJ2K encoding of random noise pattern",
            config: noiseConfig
        ))
        
        // 5. Solid color (trivial case)
        let solidConfig = HTJ2KTestVectorGenerator.Configuration(
            width: 16,
            height: 16,
            components: 1,
            bitDepth: 8,
            pattern: .solid(value: 128),
            lossless: true,
            useHTJ2K: true
        )
        vectors.append(HTJ2KTestVectorGenerator.createTestVector(
            name: "htj2k_solid_16x16",
            description: "HTJ2K encoding of solid gray pattern",
            config: solidConfig
        ))
        
        return vectors
    }
}

// MARK: - HTJ2K Test Vector Parser

/// Parser for HTJ2K test vector data files.
///
/// This parser reads test vector files in a simple text format that specifies
/// image parameters, test patterns, and expected results. This allows external
/// test data to be loaded for conformance testing.
///
/// ## File Format
///
/// Test vector files use a simple key-value format:
///
/// ```
/// NAME: test_name
/// DESCRIPTION: Test description
/// WIDTH: 64
/// HEIGHT: 64
/// COMPONENTS: 1
/// BITDEPTH: 8
/// PATTERN: checkerboard(8)
/// LOSSLESS: true
/// HTJ2K: true
/// ```
public struct HTJ2KTestVectorParser: Sendable {
    
    /// Errors that can occur during parsing.
    public enum ParseError: Error, Sendable {
        /// Required field is missing.
        case missingField(String)
        
        /// Invalid value for a field.
        case invalidValue(field: String, value: String)
        
        /// Unknown pattern type.
        case unknownPattern(String)
        
        /// File format error.
        case formatError(String)
    }
    
    /// Parses a test vector from a text string.
    ///
    /// - Parameter text: The test vector specification as text.
    /// - Returns: A configured test vector.
    /// - Throws: `ParseError` if parsing fails.
    public static func parse(_ text: String) throws -> J2KTestVector {
        var fields: [String: String] = [:]
        
        // Parse key-value pairs
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            // Split on first colon
            guard let colonIndex = trimmed.firstIndex(of: ":") else {
                continue
            }
            
            let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces).uppercased()
            let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }
        
        // Extract required fields
        guard let name = fields["NAME"] else {
            throw ParseError.missingField("NAME")
        }
        
        guard let description = fields["DESCRIPTION"] else {
            throw ParseError.missingField("DESCRIPTION")
        }
        
        guard let widthStr = fields["WIDTH"],
              let width = Int(widthStr) else {
            throw ParseError.invalidValue(field: "WIDTH", value: fields["WIDTH"] ?? "")
        }
        
        guard let heightStr = fields["HEIGHT"],
              let height = Int(heightStr) else {
            throw ParseError.invalidValue(field: "HEIGHT", value: fields["HEIGHT"] ?? "")
        }
        
        guard let componentsStr = fields["COMPONENTS"],
              let components = Int(componentsStr) else {
            throw ParseError.invalidValue(field: "COMPONENTS", value: fields["COMPONENTS"] ?? "")
        }
        
        guard let bitDepthStr = fields["BITDEPTH"],
              let bitDepth = Int(bitDepthStr) else {
            throw ParseError.invalidValue(field: "BITDEPTH", value: fields["BITDEPTH"] ?? "")
        }
        
        guard let patternStr = fields["PATTERN"] else {
            throw ParseError.missingField("PATTERN")
        }
        
        // Parse pattern
        let pattern = try parsePattern(patternStr)
        
        // Parse optional fields
        let lossless = fields["LOSSLESS"]?.lowercased() == "true"
        let quality = Double(fields["QUALITY"] ?? "1.0") ?? 1.0
        let useHTJ2K = fields["HTJ2K"]?.lowercased() == "true"
        
        // Generate test vector
        let config = HTJ2KTestVectorGenerator.Configuration(
            width: width,
            height: height,
            components: components,
            bitDepth: bitDepth,
            pattern: pattern,
            lossless: lossless,
            quality: quality,
            useHTJ2K: useHTJ2K
        )
        
        return HTJ2KTestVectorGenerator.createTestVector(
            name: name,
            description: description,
            config: config
        )
    }
    
    /// Parses a pattern specification string.
    ///
    /// - Parameter patternStr: Pattern specification (e.g., "solid(128)", "checkerboard(8)").
    /// - Returns: The corresponding test pattern.
    /// - Throws: `ParseError.unknownPattern` if the pattern is not recognized.
    private static func parsePattern(_ patternStr: String) throws -> HTJ2KTestVectorGenerator.TestPattern {
        let trimmed = patternStr.trimmingCharacters(in: .whitespaces).lowercased()
        
        // Pattern with argument
        if let openParen = trimmed.firstIndex(of: "("),
           let closeParen = trimmed.lastIndex(of: ")") {
            let patternName = String(trimmed[..<openParen])
            let argStr = String(trimmed[trimmed.index(after: openParen)..<closeParen])
            
            switch patternName {
            case "solid":
                guard let value = Int32(argStr) else {
                    throw ParseError.invalidValue(field: "PATTERN", value: patternStr)
                }
                return .solid(value: value)
                
            case "checkerboard":
                guard let size = Int(argStr) else {
                    throw ParseError.invalidValue(field: "PATTERN", value: patternStr)
                }
                return .checkerboard(squareSize: size)
                
            case "randomnoise", "random":
                guard let seed = UInt64(argStr) else {
                    throw ParseError.invalidValue(field: "PATTERN", value: patternStr)
                }
                return .randomNoise(seed: seed)
                
            default:
                throw ParseError.unknownPattern(patternName)
            }
        }
        
        // Pattern without argument
        switch trimmed {
        case "gradient":
            return .gradient
        case "frequencysweep", "frequency":
            return .frequencySweep
        case "edges":
            return .edges
        default:
            throw ParseError.unknownPattern(trimmed)
        }
    }
    
    /// Parses multiple test vectors from a file-like string.
    ///
    /// Test vectors are separated by lines containing only "---".
    ///
    /// - Parameter text: The text containing multiple test vectors.
    /// - Returns: Array of parsed test vectors.
    /// - Throws: `ParseError` if any test vector fails to parse.
    public static func parseMultiple(_ text: String) throws -> [J2KTestVector] {
        let sections = text.components(separatedBy: "\n---\n")
        var vectors: [J2KTestVector] = []
        
        for section in sections {
            let trimmed = section.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                try vectors.append(parse(trimmed))
            }
        }
        
        return vectors
    }
    
    /// Validates a test vector specification without generating the full vector.
    ///
    /// - Parameter text: The test vector specification.
    /// - Returns: `true` if the specification is valid.
    public static func validate(_ text: String) -> Bool {
        do {
            _ = try parse(text)
            return true
        } catch {
            return false
        }
    }
}
