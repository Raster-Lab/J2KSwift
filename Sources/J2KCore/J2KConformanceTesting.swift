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
