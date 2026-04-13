//
// J2KEncoderPipeline.swift
// J2KSwift
//
// J2KEncoderPipeline.swift
// J2KSwift
//
// Encoder pipeline implementation for JPEG 2000 encoding.
//

import Foundation
import J2KCore
import J2KMetal
import Synchronization

#if canImport(Accelerate)
import Accelerate
#endif

// MARK: - Encoding Stage

/// Represents the stages of the JPEG 2000 encoding pipeline.
public enum EncodingStage: String, Sendable, CaseIterable {
    /// Input validation and preprocessing.
    case preprocessing = "Preprocessing"

    /// Colour space transformation (RCT or ICT).
    case colorTransform = "Color Transform"

    /// Discrete wavelet transform (forward).
    case waveletTransform = "Wavelet Transform"

    /// Quantization of wavelet coefficients.
    case quantization = "Quantization"

    /// Entropy coding (EBCOT bit-plane coding).
    case entropyCoding = "Entropy Coding"

    /// Rate control and quality layer formation.
    case rateControl = "Rate Control"

    /// Codestream generation with markers.
    case codestreamGeneration = "Codestream Generation"
}

// MARK: - Progress Update

/// Reports progress during encoding.
public struct EncoderProgressUpdate: Sendable {
    /// The current encoding stage.
    public let stage: EncodingStage

    /// Progress within the current stage (0.0 to 1.0).
    public let progress: Double

    /// Overall encoding progress (0.0 to 1.0).
    public let overallProgress: Double
}

// MARK: - Parallel Result Collector

/// Thread-safe result collector for parallel code-block encoding.
///
/// Uses `Mutex` from the `Synchronization` module for lock-based
/// synchronisation, replacing the previous `@unchecked Sendable` + `NSLock`
/// pattern. The `Mutex` guarantees exclusive access to mutable state
/// and is unconditionally `Sendable`.
final class ParallelResultCollector<T: Sendable>: Sendable {
    private let _results: Mutex<[T]>
    private let _firstError: Mutex<(any Error)?>

    init(capacity: Int = 0) {
        var initial: [T] = []
        initial.reserveCapacity(capacity)
        _results = Mutex(initial)
        _firstError = Mutex(nil)
    }

    func append(contentsOf elements: [T]) {
        _results.withLock { $0.append(contentsOf: elements) }
    }

    func recordError(_ error: any Error) {
        _firstError.withLock { state in
            if state == nil {
                state = error
            }
        }
    }

    var results: [T] {
        _results.withLock { Array($0) }
    }

    var firstError: (any Error)? {
        _firstError.withLock { $0 }
    }
}

// MARK: - Encoder Pipeline

/// Internal encoding pipeline that connects all JPEG 2000 encoding components.
///
/// The pipeline processes an image through these stages:
/// 1. Preprocessing — validate input, extract component data
/// 2. Colour Transform — apply RCT (lossless) or ICT (lossy)
/// 3. Wavelet Transform — multi-level 2D DWT decomposition
/// 4. Quantization — convert coefficients to integer indices
/// 5. Entropy Coding — EBCOT bit-plane coding per code block
/// 6. Rate Control — quality layer formation
/// 7. Codestream Generation — write JPEG 2000 markers and data
struct EncoderPipeline: Sendable {
    let config: J2KEncodingConfiguration

    // MARK: - Main Encode

    /// Encodes an image through the full JPEG 2000 pipeline.
    ///
    /// - Parameters:
    ///   - image: The image to encode.
    ///   - progress: Optional progress callback.
    /// - Returns: The encoded JPEG 2000 codestream data.
    /// - Throws: ``J2KError`` if encoding fails.
    func encode(
        _ image: J2KImage,
        progress: ((EncoderProgressUpdate) -> Void)? = nil
    ) throws -> Data {
        let profiling = ProcessInfo.processInfo.environment["J2K_PROFILE"] != nil
        var stageStart = CFAbsoluteTimeGetCurrent()

        try image.validate()

        // Stage 1: Preprocessing — extract component data as Int32 arrays
        reportProgress(progress, stage: .preprocessing, stageProgress: 0.0)
        var componentData = try extractComponentData(from: image)
        reportProgress(progress, stage: .preprocessing, stageProgress: 1.0)

        // DC level shift: for unsigned components, subtract 2^(bitDepth-1) to
        // center values around zero, as required by ISO 15444-1 Annex F.
        for (compIdx, component) in image.components.enumerated() {
            if !component.signed {
                let dcOffset = Int32(1 << (component.bitDepth - 1))
                componentData[compIdx].withUnsafeMutableBufferPointer { buf in
                    for i in 0..<buf.count {
                        buf[i] &-= dcOffset
                    }
                }
            }
        }

        if profiling {
            let t = CFAbsoluteTimeGetCurrent()
            print("  PROFILE preprocess: \(String(format: "%.4f", t - stageStart))s")
            stageStart = t
        }

        // Stage 2: Colour Transform
        reportProgress(progress, stage: .colorTransform, stageProgress: 0.0)
        let (transformedData, transformedDoubleData) = try applyColorTransform(componentData, image: image)
        reportProgress(progress, stage: .colorTransform, stageProgress: 1.0)

        if profiling {
            let t = CFAbsoluteTimeGetCurrent()
            print("  PROFILE colorXform: \(String(format: "%.4f", t - stageStart))s")
            stageStart = t
        }

        // Stage 3: Wavelet Transform
        reportProgress(progress, stage: .waveletTransform, stageProgress: 0.0)
        let (decompositions, actualDecompositionLevels) = try applyWaveletTransform(
            transformedData, doubleComponents: transformedDoubleData,
            width: image.width, height: image.height
        )
        reportProgress(progress, stage: .waveletTransform, stageProgress: 1.0)

        if profiling {
            let t = CFAbsoluteTimeGetCurrent()
            print("  PROFILE dwt: \(String(format: "%.4f", t - stageStart))s")
            stageStart = t
        }

        // Stage 4: Quantization
        reportProgress(progress, stage: .quantization, stageProgress: 0.0)
        let quantizedSubbands = try applyQuantization(decompositions)
        reportProgress(progress, stage: .quantization, stageProgress: 1.0)

        if profiling {
            let t = CFAbsoluteTimeGetCurrent()
            print("  PROFILE quantize: \(String(format: "%.4f", t - stageStart))s")
            stageStart = t
        }

        // Stage 5: Entropy Coding
        reportProgress(progress, stage: .entropyCoding, stageProgress: 0.0)
        let codeBlocks = try applyEntropyCoding(quantizedSubbands, image: image)
        reportProgress(progress, stage: .entropyCoding, stageProgress: 1.0)

        if profiling {
            let t = CFAbsoluteTimeGetCurrent()
            print("  PROFILE entropy: \(String(format: "%.4f", t - stageStart))s")
            stageStart = t
        }

        // Stage 6: Rate Control
        reportProgress(progress, stage: .rateControl, stageProgress: 0.0)
        // totalPixels is the number of spatial locations (W × H).
        // bpp (bits per pixel) already accounts for all components —
        // e.g. 1.2 bpp for RGB means 1.2 total bits per spatial location.
        // The PCRD budget is: targetBytes = bpp × totalPixels / 8.
        let layers = try applyRateControl(
            codeBlocks: codeBlocks, totalPixels: image.width * image.height
        )
        reportProgress(progress, stage: .rateControl, stageProgress: 1.0)

        if profiling {
            let t = CFAbsoluteTimeGetCurrent()
            print("  PROFILE rateCtrl: \(String(format: "%.4f", t - stageStart))s")
            stageStart = t
        }

        // Stage 7: Codestream Generation
        reportProgress(progress, stage: .codestreamGeneration, stageProgress: 0.0)
        let codestream = try generateCodestream(
            image: image, codeBlocks: codeBlocks, layers: layers,
            actualDecompositionLevels: actualDecompositionLevels
        )
        reportProgress(progress, stage: .codestreamGeneration, stageProgress: 1.0)

        if profiling {
            let t = CFAbsoluteTimeGetCurrent()
            print("  PROFILE codestream: \(String(format: "%.4f", t - stageStart))s")
        }

        return codestream
    }

    // MARK: - GPU-Accelerated Encode

    /// Encodes an image through the GPU-accelerated JPEG 2000 pipeline.
    ///
    /// Uses Metal GPU acceleration for the CDF 9/7 wavelet transform and colour
    /// transform stages when available. Falls back to CPU implementations when
    /// Metal is unavailable (e.g. Linux, CI servers without GPU).
    ///
    /// HTJ2K block coding (when `config.useHTJ2K` is true) always runs on CPU
    /// using the FBCOT algorithm with SIMD-accelerated significance extraction.
    ///
    /// - Parameters:
    ///   - image: The image to encode.
    ///   - progress: Optional progress callback.
    /// - Returns: The encoded JPEG 2000 codestream data.
    /// - Throws: ``J2KError`` if encoding fails.
    func encodeGPU(
        _ image: J2KImage,
        progress: ((EncoderProgressUpdate) -> Void)? = nil
    ) async throws -> Data {
        try image.validate()

        // Stage 1: Preprocessing
        reportProgress(progress, stage: .preprocessing, stageProgress: 0.0)
        var componentData = try extractComponentData(from: image)
        reportProgress(progress, stage: .preprocessing, stageProgress: 1.0)

        for (compIdx, component) in image.components.enumerated() {
            if !component.signed {
                let dcOffset = Int32(1 << (component.bitDepth - 1))
                componentData[compIdx].withUnsafeMutableBufferPointer { buf in
                    for i in 0..<buf.count {
                        buf[i] &-= dcOffset
                    }
                }
            }
        }

        // Stage 2: GPU Colour Transform
        reportProgress(progress, stage: .colorTransform, stageProgress: 0.0)
        let (transformedData, transformedDoubleData) = try await applyColorTransformGPU(componentData, image: image)
        reportProgress(progress, stage: .colorTransform, stageProgress: 1.0)

        // Stage 3: GPU Wavelet Transform
        reportProgress(progress, stage: .waveletTransform, stageProgress: 0.0)
        let (decompositions, actualDecompositionLevels) = try await applyWaveletTransformGPU(
            transformedData, doubleComponents: transformedDoubleData,
            width: image.width, height: image.height
        )
        reportProgress(progress, stage: .waveletTransform, stageProgress: 1.0)

        // Stage 4: Quantization
        reportProgress(progress, stage: .quantization, stageProgress: 0.0)
        let quantizedSubbands = try applyQuantization(decompositions)
        reportProgress(progress, stage: .quantization, stageProgress: 1.0)

        // Stage 5: Entropy Coding
        reportProgress(progress, stage: .entropyCoding, stageProgress: 0.0)
        let codeBlocks = try applyEntropyCoding(quantizedSubbands, image: image)
        reportProgress(progress, stage: .entropyCoding, stageProgress: 1.0)

        // Stage 6: Rate Control
        reportProgress(progress, stage: .rateControl, stageProgress: 0.0)
        let layers = try applyRateControl(
            codeBlocks: codeBlocks, totalPixels: image.width * image.height
        )
        reportProgress(progress, stage: .rateControl, stageProgress: 1.0)

        // Stage 7: Codestream Generation
        reportProgress(progress, stage: .codestreamGeneration, stageProgress: 0.0)
        let codestream = try generateCodestream(
            image: image, codeBlocks: codeBlocks, layers: layers,
            actualDecompositionLevels: actualDecompositionLevels
        )
        reportProgress(progress, stage: .codestreamGeneration, stageProgress: 1.0)

        return codestream
    }

    /// GPU-accelerated wavelet transform using Metal.
    ///
    /// Uses Metal GPU for both CDF 9/7 irreversible and Le Gall 5/3 reversible wavelet transforms.
    /// Falls back to CPU when Metal is unavailable or for custom/arbitrary wavelet kernels.
    private func applyWaveletTransformGPU(
        _ components: [[Int32]], doubleComponents: [[Double]]? = nil,
        width: Int, height: Int
    ) async throws -> ([[SubbandInfo]], Int) {
        // Fall back to CPU for custom wavelet kernels only
        if case .arbitrary = config.waveletKernelConfiguration {
            return try applyWaveletTransform(components, doubleComponents: doubleComponents,
                                              width: width, height: height)
        }
        if case .perTileComponent = config.waveletKernelConfiguration {
            return try applyWaveletTransform(components, doubleComponents: doubleComponents,
                                              width: width, height: height)
        }

        let maxLevels = max(0, Int(log2(Double(min(width, height)))) - 1)
        let levels = min(config.decompositionLevels, maxLevels)

        guard levels >= 1 else {
            return try applyWaveletTransform(components, doubleComponents: doubleComponents,
                                              width: width, height: height)
        }

        // Fall back to CPU when Metal GPU is not available (e.g. Linux, CI servers)
        guard J2KMetalDWT.isAvailable else {
            return try applyWaveletTransform(components, doubleComponents: doubleComponents,
                                              width: width, height: height)
        }

        // Fall back to CPU for small images where GPU dispatch overhead exceeds compute benefit.
        // For HTJ2K mode, DWT is a small fraction of total time — raise threshold to
        // avoid GPU overhead dominating. For legacy EBCOT, GPU helps at smaller sizes
        // because DWT is a larger fraction of the pipeline.
        let pixelCount = width * height
        let gpuThreshold = config.useHTJ2K ? (1024 * 1024) : (256 * 256)
        guard pixelCount >= gpuThreshold else {
            return try applyWaveletTransform(components, doubleComponents: doubleComponents,
                                              width: width, height: height)
        }

        // Select filter based on configuration
        let metalFilter: J2KMetalDWTFilter = config.useReversibleFilter ? .reversible53 : .irreversible97

        // Create Metal DWT for GPU forward transform
        let metalDWT = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: metalFilter, decompositionLevels: levels
        ))
        try await metalDWT.initialize()

        var allSubbands: [[SubbandInfo]] = []

        for (compIdx, compData) in components.enumerated() {
            // Convert to Float for Metal DWT using vDSP when available
            let flatFloat: [Float]
            if let dc = doubleComponents, compIdx < dc.count {
                flatFloat = vDSPConvert.doublesToFloats(dc[compIdx])
            } else {
                flatFloat = vDSPConvert.int32sToFloats(compData)
            }

            let decomposition = try await metalDWT.forwardMultiLevel(
                data: flatFloat, width: width, height: height,
                levels: levels, backend: J2KMetalDWTBackend.auto
            )

            var subbands: [SubbandInfo] = []

            for (levelIdx, level) in decomposition.levels.enumerated() {
                let decomLevel = levelIdx + 1
                let hlWidth = level.originalWidth - level.llWidth
                let lhHeight = level.originalHeight - level.llHeight

                subbands.append(SubbandInfo(
                    componentIndex: compIdx, level: decomLevel, subband: .hl,
                    coefficients: vDSPConvert.floatsToInt32s(level.hl),
                    doubleCoefficients: nil,
                    width: hlWidth, height: level.llHeight,
                    floatCoefficients: level.hl
                ))
                subbands.append(SubbandInfo(
                    componentIndex: compIdx, level: decomLevel, subband: .lh,
                    coefficients: vDSPConvert.floatsToInt32s(level.lh),
                    doubleCoefficients: nil,
                    width: level.llWidth, height: lhHeight,
                    floatCoefficients: level.lh
                ))
                subbands.append(SubbandInfo(
                    componentIndex: compIdx, level: decomLevel, subband: .hh,
                    coefficients: vDSPConvert.floatsToInt32s(level.hh),
                    doubleCoefficients: nil,
                    width: hlWidth, height: lhHeight,
                    floatCoefficients: level.hh
                ))
            }

            subbands.insert(SubbandInfo(
                componentIndex: compIdx, level: 0, subband: .ll,
                coefficients: vDSPConvert.floatsToInt32s(decomposition.approximation),
                doubleCoefficients: nil,
                width: decomposition.approximationWidth,
                height: decomposition.approximationHeight,
                floatCoefficients: decomposition.approximation
            ), at: 0)

            allSubbands.append(subbands)
        }

        return (allSubbands, levels)
    }

    /// GPU-accelerated colour transform using Metal.
    ///
    /// Uses Metal GPU for ICT/RCT colour transforms on 3+ component images.
    /// Falls back to CPU for non-standard MCT modes.
    private func applyColorTransformGPU(
        _ components: [[Int32]], image: J2KImage, tileIndex: Int = 0
    ) async throws -> ([[Int32]], [[Double]]?) {
        // Fall back to CPU for non-standard MCT modes
        if config.mctConfiguration.perTileMCT[tileIndex] != nil {
            return try applyColorTransform(components, image: image, tileIndex: tileIndex)
        }
        switch config.mctConfiguration.mode {
        case .arrayBased, .dependency, .adaptive:
            return try applyColorTransform(components, image: image, tileIndex: tileIndex)
        case .disabled:
            break
        }

        // Standard Part 1 colour transform — use GPU for 3+ components
        guard components.count >= 3 else { return (components, nil) }

        // Check if Metal is available
        guard J2KMetalColorTransform.isAvailable else {
            return try applyColorTransform(components, image: image, tileIndex: tileIndex)
        }

        let transformType: J2KMetalColorTransformType = config.useReversibleFilter ? .rct : .ict
        let metalConfig = J2KMetalColorTransformConfiguration(transformType: transformType)
        let metalCT = J2KMetalColorTransform(configuration: metalConfig)
        try await metalCT.initialize()

        // Convert Int32 to Float for Metal
        let redFloat = vDSPConvert.int32sToFloats(components[0])
        let greenFloat = vDSPConvert.int32sToFloats(components[1])
        let blueFloat = vDSPConvert.int32sToFloats(components[2])

        let result = try await metalCT.forwardTransform(
            red: redFloat, green: greenFloat, blue: blueFloat, backend: .auto
        )

        // Convert back to Int32 and optionally Double
        let y = vDSPConvert.floatsToInt32s(result.component0)
        let cb = vDSPConvert.floatsToInt32s(result.component1)
        let cr = vDSPConvert.floatsToInt32s(result.component2)

        var intResult = [y, cb, cr]
        if components.count > 3 {
            intResult.append(contentsOf: components[3...])
        }

        var doubleResult: [[Double]]? = nil
        if !config.useReversibleFilter {
            // Keep double-precision ICT output for 9/7 DWT path
            var dbl: [[Double]] = [
                vDSPConvert.floatsToDoubles(result.component0),
                vDSPConvert.floatsToDoubles(result.component1),
                vDSPConvert.floatsToDoubles(result.component2)
            ]
            if components.count > 3 {
                dbl.append(contentsOf: components[3...].map { $0.map { Double($0) } })
            }
            doubleResult = dbl
        }

        return (intResult, doubleResult)
    }

    // MARK: - Stage 1: Preprocessing

    /// Extracts component data from the image as arrays of Int32 values.
    private func extractComponentData(from image: J2KImage) throws -> [[Int32]] {
        var result: [[Int32]] = []

        for component in image.components {
            let pixelCount = component.width * component.height
            var pixels = [Int32](repeating: 0, count: pixelCount)

            let data = component.data
            if component.bitDepth <= 8 {
                let byteCount = min(data.count, pixelCount)
                data.withUnsafeBytes { buffer in
                    guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return
                    }
                    for i in 0..<byteCount {
                        if component.signed {
                            pixels[i] = Int32(Int8(bitPattern: ptr[i]))
                        } else {
                            pixels[i] = Int32(ptr[i])
                        }
                    }
                }
            } else if component.bitDepth <= 16 {
                let sampleCount = min(data.count / 2, pixelCount)
                data.withUnsafeBytes { buffer in
                    guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return
                    }
                    for i in 0..<sampleCount {
                        let value = UInt16(ptr[i * 2]) << 8 | UInt16(ptr[i * 2 + 1])
                        if component.signed {
                            pixels[i] = Int32(Int16(bitPattern: value))
                        } else {
                            pixels[i] = Int32(value)
                        }
                    }
                }
            }

            result.append(pixels)
        }

        return result
    }

    // MARK: - Stage 2: Colour Transform

    /// Applies colour space transformation (RCT/ICT or Part 2 MCT).
    ///
    /// - Parameters:
    ///   - components: The component data.
    ///   - image: The source image.
    ///   - tileIndex: The tile index (default: 0 for non-tiled images).
    /// - Returns: Transformed component data as Int32 and optionally as Double (for ICT lossy path).
    private func applyColorTransform(
        _ components: [[Int32]], image: J2KImage, tileIndex: Int = 0
    ) throws -> ([[Int32]], [[Double]]?) {
        // Check for per-tile MCT override first
        if let tileMatrix = config.mctConfiguration.perTileMCT[tileIndex] {
            return (try applyArrayBasedMCT(components, matrix: tileMatrix, image: image), nil)
        }

        // Check if MCT is enabled in configuration
        switch config.mctConfiguration.mode {
        case .disabled:
            // Use standard Part 1 colour transform
            return try applyStandardColorTransform(components, image: image)

        case .arrayBased(let matrix):
            // Use array-based MCT with specified matrix
            return (try applyArrayBasedMCT(components, matrix: matrix, image: image), nil)

        case .dependency(let depConfig):
            // Use dependency-based MCT
            return (try applyDependencyMCT(components, configuration: depConfig, image: image), nil)

        case let .adaptive(candidates, criteria):
            // Select best matrix adaptively based on criteria
            return try applyAdaptiveMCT(
                components, candidates: candidates,
                criteria: criteria, image: image,
                tileIndex: tileIndex)
        }
    }

    /// Applies standard Part 1 colour transform (RCT/ICT).
    private func applyStandardColorTransform(
        _ components: [[Int32]], image: J2KImage
    ) throws -> ([[Int32]], [[Double]]?) {
        // Colour transform only applies to 3+ component images
        guard components.count >= 3 else { return (components, nil) }

        let mode: J2KColorTransformMode = config.useReversibleFilter ? .reversible : .irreversible
        let ctConfig = J2KColorTransformConfiguration(mode: mode)
        let transform = J2KColorTransform(configuration: ctConfig)

        let y: [Int32]
        let cb: [Int32]
        let cr: [Int32]
        var doubleResult: [[Double]]? = nil

        if config.useReversibleFilter {
            // Use RCT (integer-based, perfectly reversible)
            (y, cb, cr) = try transform.forwardRCT(
                red: components[0], green: components[1], blue: components[2]
            )
        } else {
            // Use ICT (floating-point, irreversible) for lossy mode
            let redD = vDSPConvert.int32sToDoubles(components[0])
            let greenD = vDSPConvert.int32sToDoubles(components[1])
            let blueD = vDSPConvert.int32sToDoubles(components[2])
            let (yD, cbD, crD) = try transform.forwardICT(
                red: redD, green: greenD, blue: blueD
            )
            y = vDSPConvert.doublesToInt32s(yD)
            cb = vDSPConvert.doublesToInt32s(cbD)
            cr = vDSPConvert.doublesToInt32s(crD)
            // Keep double-precision ICT output for 9/7 DWT path
            var dbl = [yD, cbD, crD]
            if components.count > 3 {
                dbl.append(contentsOf: components[3...].map { vDSPConvert.int32sToDoubles($0) })
            }
            doubleResult = dbl
        }

        var result = [y, cb, cr]
        // Preserve any additional components (alpha, etc.) unchanged
        if components.count > 3 {
            result.append(contentsOf: components[3...])
        }
        return (result, doubleResult)
    }

    /// Applies array-based MCT using a transformation matrix.
    private func applyArrayBasedMCT(
        _ components: [[Int32]], matrix: J2KMCTMatrix, image: J2KImage
    ) throws -> [[Int32]] {
        guard components.count == matrix.size else {
            throw J2KError.invalidParameter(
                "Component count (\(components.count)) must match matrix size (\(matrix.size)) for MCT"
            )
        }

        // Convert Int32 to Double for MCT
        let doubleComponents = components.map { component in
            component.map { Double($0) }
        }

        // Apply MCT
        let mctConfig = J2KMCTConfiguration(type: .arrayBased, matrix: matrix)
        let mct = J2KMCT(configuration: mctConfig)
        let transformed = try mct.forwardTransform(components: doubleComponents, matrix: matrix)

        // Convert back to Int32
        return transformed.map { component in
            component.map { Int32($0.rounded()) }
        }
    }

    /// Applies dependency-based MCT.
    private func applyDependencyMCT(
        _ components: [[Int32]], configuration: J2KMCTDependencyConfiguration, image: J2KImage
    ) throws -> [[Int32]] {
        // Convert Int32 to Double for dependency transform
        let doubleComponents = components.map { component in
            component.map { Double($0) }
        }

        // Apply dependency transform
        let transformer = J2KMCTDependencyTransform()
        let transformed: [[Double]]

        switch configuration.transform {
        case .chain(let chain):
            transformed = try transformer.forwardTransform(components: doubleComponents, chain: chain)

        case .hierarchical(let hierarchical):
            transformed = try transformer.forwardHierarchicalTransform(
                components: doubleComponents,
                transform: hierarchical
            )
        }

        // Convert back to Int32
        return transformed.map { component in
            component.map { Int32($0.rounded()) }
        }
    }

    /// Applies adaptive MCT by selecting the best matrix based on criteria.
    private func applyAdaptiveMCT(
        _ components: [[Int32]],
        candidates: [J2KMCTMatrix],
        criteria: J2KMCTEncodingConfiguration.AdaptiveSelectionCriteria,
        image: J2KImage,
        tileIndex: Int = 0
    ) throws -> ([[Int32]], [[Double]]?) {
        // For now, use a simple heuristic: correlation-based selection
        // In a full implementation, this would evaluate each candidate matrix
        // and select based on the specified criteria

        // TODO: Implement proper adaptive selection based on:
        // - correlation: Analyse component correlation
        // - rateDistortion: Evaluate R-D performance of each candidate
        // - compressionEfficiency: Compare compression ratios

        // Default to first candidate if available
        guard let selectedMatrix = candidates.first else {
            // Fall back to standard transform
            return try applyStandardColorTransform(components, image: image)
        }

        // Apply the selected matrix
        return (try applyArrayBasedMCT(components, matrix: selectedMatrix, image: image), nil)
    }

    // MARK: - Stage 3: Wavelet Transform

    /// Information about a subband within a decomposition.
    struct SubbandInfo: Sendable {
        let componentIndex: Int
        let level: Int
        let subband: J2KSubband
        let coefficients: [Int32]
        /// Raw Double DWT coefficients for the 9/7 irreversible path.
        /// When non-nil, quantization uses these instead of `coefficients`
        /// to avoid precision loss from premature Int32 rounding.
        let doubleCoefficients: [Double]?
        /// Raw Float DWT coefficients from the GPU path.
        /// When non-nil, quantization uses these directly to avoid the
        /// Float→Double conversion overhead. Takes priority over `doubleCoefficients`.
        let floatCoefficients: [Float]?
        let width: Int
        let height: Int

        init(
            componentIndex: Int, level: Int, subband: J2KSubband,
            coefficients: [Int32], doubleCoefficients: [Double]?,
            width: Int, height: Int,
            floatCoefficients: [Float]? = nil
        ) {
            self.componentIndex = componentIndex
            self.level = level
            self.subband = subband
            self.coefficients = coefficients
            self.doubleCoefficients = doubleCoefficients
            self.floatCoefficients = floatCoefficients
            self.width = width
            self.height = height
        }
    }

    /// Applies the forward wavelet transform to all components.
    ///
    /// - Returns: A tuple of (subbands per component, actual decomposition levels used).
    private func applyWaveletTransform(
        _ components: [[Int32]], doubleComponents: [[Double]]? = nil,
        width: Int, height: Int
    ) throws -> ([[SubbandInfo]], Int) {
        // Select filter based on wavelet kernel configuration
        let filter: J2KDWT1D.Filter
        switch config.waveletKernelConfiguration {
        case .standard:
            // Use standard Part 1 wavelets
            filter = config.useReversibleFilter ? .reversible53 : .irreversible97
        case .arbitrary(let kernel):
            // Use arbitrary kernel for all components
            filter = kernel.toDWTFilter()
        case .perTileComponent:
            // Per-tile-component selection handled below
            filter = config.useReversibleFilter ? .reversible53 : .irreversible97
        }

        // Clamp decomposition levels to what the image dimensions can support
        let maxLevels = max(0, Int(log2(Double(min(width, height)))) - 1)
        let levels = min(config.decompositionLevels, maxLevels)

        var allSubbands: [[SubbandInfo]] = []

        for (compIdx, compData) in components.enumerated() {
            // Select filter for this component (if per-tile-component is enabled)
            let componentFilter: J2KDWT1D.Filter
            if case .perTileComponent(let kernelMap) = config.waveletKernelConfiguration {
                // For now, assume tile index 0 for non-tiled images
                // TODO: Add proper tile support
                let key = J2KWaveletKernelConfiguration.TileComponentKey(tileIndex: 0, componentIndex: compIdx)
                if let kernel = kernelMap[key] {
                    componentFilter = kernel.toDWTFilter()
                } else {
                    // Fall back to standard filter
                    componentFilter = config.useReversibleFilter ? .reversible53 : .irreversible97
                }
            } else {
                componentFilter = filter
            }

            // Convert 1D array to 2D for DWT (optimised version)
            var image2D: [[Int32]] = []
            image2D.reserveCapacity(height)
            for row in 0..<height {
                let rowStart = row * width
                let rowEnd = rowStart + width
                image2D.append(Array(compData[rowStart..<rowEnd]))
            }

            // If no decomposition, treat entire image as LL subband
            guard levels >= 1 else {
                let subbands = [SubbandInfo(
                    componentIndex: compIdx,
                    level: 0,
                    subband: .ll,
                    coefficients: compData,
                    doubleCoefficients: nil,
                    width: width,
                    height: height
                )]
                allSubbands.append(subbands)
                continue
            }

            // For 9/7 irreversible wavelet, use Double-precision forward DWT to
            // avoid accumulated rounding error from Int32 truncation at each level.
            // For 5/3 reversible, use Int32 (exact integer arithmetic).
            var subbands: [SubbandInfo] = []

            let use97DoublePrecision: Bool
            if case .irreversible97 = componentFilter {
                use97DoublePrecision = true
            } else {
                use97DoublePrecision = false
            }

            // Determine if we can use the accelerated flat-buffer DWT path.
            // The accelerated path avoids [[Double]]/[[Int32]] array-of-arrays
            // overhead and uses vDSP on Apple platforms.
            let useAcceleratedPath: Bool
            switch componentFilter {
            case .irreversible97, .reversible53:
                useAcceleratedPath = true
            case .custom:
                useAcceleratedPath = false
            }

            if use97DoublePrecision && useAcceleratedPath {
                // Accelerated Double-precision CDF 9/7 path.
                let flatDouble: [Double]
                if let dc = doubleComponents, compIdx < dc.count {
                    flatDouble = dc[compIdx]
                } else {
                    flatDouble = vDSPConvert.int32sToDoubles(compData)
                }

                let decomposition = AcceleratedDWT2D.forwardDecomposition(
                    data: flatDouble, width: width, height: height, levels: levels
                )

                for (levelIdx, level) in decomposition.levels.enumerated() {
                    let decomLevel = levelIdx + 1

                    subbands.append(SubbandInfo(
                        componentIndex: compIdx,
                        level: decomLevel,
                        subband: .hl,
                        coefficients: vDSPConvert.doublesToInt32s(level.hl),
                        doubleCoefficients: level.hl,
                        width: level.hlW,
                        height: level.hlH
                    ))
                    subbands.append(SubbandInfo(
                        componentIndex: compIdx,
                        level: decomLevel,
                        subband: .lh,
                        coefficients: vDSPConvert.doublesToInt32s(level.lh),
                        doubleCoefficients: level.lh,
                        width: level.lhW,
                        height: level.lhH
                    ))
                    subbands.append(SubbandInfo(
                        componentIndex: compIdx,
                        level: decomLevel,
                        subband: .hh,
                        coefficients: vDSPConvert.doublesToInt32s(level.hh),
                        doubleCoefficients: level.hh,
                        width: level.hhW,
                        height: level.hhH
                    ))
                }

                subbands.insert(SubbandInfo(
                    componentIndex: compIdx,
                    level: 0,
                    subband: .ll,
                    coefficients: vDSPConvert.doublesToInt32s(decomposition.coarsestLL),
                    doubleCoefficients: decomposition.coarsestLL,
                    width: decomposition.llW,
                    height: decomposition.llH
                ), at: 0)

            } else if !use97DoublePrecision && useAcceleratedPath {
                // Accelerated Int32 Le Gall 5/3 path.
                let decomposition = AcceleratedDWT2D.forwardDecomposition53(
                    data: compData, width: width, height: height, levels: levels
                )

                for (levelIdx, level) in decomposition.levels.enumerated() {
                    let decomLevel = levelIdx + 1

                    subbands.append(SubbandInfo(
                        componentIndex: compIdx,
                        level: decomLevel,
                        subband: .hl,
                        coefficients: level.hl,
                        doubleCoefficients: nil,
                        width: level.hlW,
                        height: level.hlH
                    ))
                    subbands.append(SubbandInfo(
                        componentIndex: compIdx,
                        level: decomLevel,
                        subband: .lh,
                        coefficients: level.lh,
                        doubleCoefficients: nil,
                        width: level.lhW,
                        height: level.lhH
                    ))
                    subbands.append(SubbandInfo(
                        componentIndex: compIdx,
                        level: decomLevel,
                        subband: .hh,
                        coefficients: level.hh,
                        doubleCoefficients: nil,
                        width: level.hhW,
                        height: level.hhH
                    ))
                }

                subbands.insert(SubbandInfo(
                    componentIndex: compIdx,
                    level: 0,
                    subband: .ll,
                    coefficients: decomposition.coarsestLL,
                    doubleCoefficients: nil,
                    width: decomposition.llW,
                    height: decomposition.llH
                ), at: 0)

            } else if use97DoublePrecision {
                // Fallback: original [[Double]] path for custom filters
                let doubleImage: [[Double]]
                if let dc = doubleComponents, compIdx < dc.count {
                    var img2D: [[Double]] = []
                    img2D.reserveCapacity(height)
                    for row in 0..<height {
                        let rowStart = row * width
                        let rowEnd = rowStart + width
                        img2D.append(Array(dc[compIdx][rowStart..<rowEnd]))
                    }
                    doubleImage = img2D
                } else {
                    doubleImage = image2D.map { $0.map { Double($0) } }
                }
                let decomposition = try J2KDWT2D.forwardDecompositionDouble(
                    image: doubleImage, levels: levels, filter: componentFilter
                )

                for levelIdx in 0..<decomposition.levelCount {
                    let level = decomposition.levels[levelIdx]
                    let decomLevel = levelIdx + 1

                    let hlFlat = level.hl.flatMap { $0 }
                    subbands.append(SubbandInfo(
                        componentIndex: compIdx,
                        level: decomLevel,
                        subband: .hl,
                        coefficients: vDSPConvert.doublesToInt32s(hlFlat),
                        doubleCoefficients: hlFlat,
                        width: level.hl.isEmpty ? 0 : level.hl[0].count,
                        height: level.hl.count
                    ))
                    let lhFlat = level.lh.flatMap { $0 }
                    subbands.append(SubbandInfo(
                        componentIndex: compIdx,
                        level: decomLevel,
                        subband: .lh,
                        coefficients: vDSPConvert.doublesToInt32s(lhFlat),
                        doubleCoefficients: lhFlat,
                        width: level.lh.isEmpty ? 0 : level.lh[0].count,
                        height: level.lh.count
                    ))
                    let hhFlat = level.hh.flatMap { $0 }
                    subbands.append(SubbandInfo(
                        componentIndex: compIdx,
                        level: decomLevel,
                        subband: .hh,
                        coefficients: vDSPConvert.doublesToInt32s(hhFlat),
                        doubleCoefficients: hhFlat,
                        width: level.hh.isEmpty ? 0 : level.hh[0].count,
                        height: level.hh.count
                    ))
                }

                let coarsestLL = decomposition.coarsestLL
                let llFlat = coarsestLL.flatMap { $0 }
                subbands.insert(SubbandInfo(
                    componentIndex: compIdx,
                    level: 0,
                    subband: .ll,
                    coefficients: vDSPConvert.doublesToInt32s(llFlat),
                    doubleCoefficients: llFlat,
                    width: coarsestLL.isEmpty ? 0 : coarsestLL[0].count,
                    height: coarsestLL.count
                ), at: 0)
            } else {
                // Fallback: original Int32 path for custom filters
                let decomposition = try J2KDWT2D.forwardDecomposition(
                    image: image2D, levels: levels, filter: componentFilter
                )

                for levelIdx in 0..<decomposition.levelCount {
                    let level = decomposition.levels[levelIdx]
                    let decomLevel = levelIdx + 1

                    subbands.append(SubbandInfo(
                        componentIndex: compIdx,
                        level: decomLevel,
                        subband: .hl,
                        coefficients: level.hl.flatMap { $0 },
                        doubleCoefficients: nil,
                        width: level.hl.isEmpty ? 0 : level.hl[0].count,
                        height: level.hl.count
                    ))
                    subbands.append(SubbandInfo(
                        componentIndex: compIdx,
                        level: decomLevel,
                        subband: .lh,
                        coefficients: level.lh.flatMap { $0 },
                        doubleCoefficients: nil,
                        width: level.lh.isEmpty ? 0 : level.lh[0].count,
                        height: level.lh.count
                    ))
                    subbands.append(SubbandInfo(
                        componentIndex: compIdx,
                        level: decomLevel,
                        subband: .hh,
                        coefficients: level.hh.flatMap { $0 },
                        doubleCoefficients: nil,
                        width: level.hh.isEmpty ? 0 : level.hh[0].count,
                        height: level.hh.count
                    ))
                }

                let coarsestLL = decomposition.coarsestLL
                subbands.insert(SubbandInfo(
                    componentIndex: compIdx,
                    level: 0,
                    subband: .ll,
                    coefficients: coarsestLL.flatMap { $0 },
                    doubleCoefficients: nil,
                    width: coarsestLL.isEmpty ? 0 : coarsestLL[0].count,
                    height: coarsestLL.count
                ), at: 0)
            }

            allSubbands.append(subbands)
        }

        return (allSubbands, levels)
    }

    // MARK: - Stage 4: Quantization

    /// Applies quantization to all subbands.
    private func applyQuantization(
        _ componentSubbands: [[SubbandInfo]]
    ) throws -> [[SubbandInfo]] {
        let params: J2KQuantizationParameters = config.useReversibleFilter
            ? .lossless
            : .fromQuality(config.quality)
        let quantizer = J2KQuantizer(parameters: params)

        var result: [[SubbandInfo]] = []

        for subbands in componentSubbands {
            var quantizedSubbands: [SubbandInfo] = []
            for info in subbands {
                let quantized: [Int32]
                if let floatCoeffs = info.floatCoefficients {
                    // Use Float-precision path for GPU DWT output — avoids Float→Double conversion
                    quantized = try quantizer.quantize(
                        coefficients: floatCoeffs,
                        subband: info.subband,
                        decompositionLevel: info.level,
                        totalLevels: config.decompositionLevels
                    )
                } else if let doubleCoeffs = info.doubleCoefficients {
                    // Use Double-precision path for 9/7 irreversible to preserve fractional precision
                    quantized = try quantizer.quantize(
                        coefficients: doubleCoeffs,
                        subband: info.subband,
                        decompositionLevel: info.level,
                        totalLevels: config.decompositionLevels
                    )
                } else {
                    // Use Int32-optimised quantize method for reversible 5/3
                    quantized = try quantizer.quantize(
                        coefficients: info.coefficients,
                        subband: info.subband,
                        decompositionLevel: info.level,
                        totalLevels: config.decompositionLevels
                    )
                }

                quantizedSubbands.append(SubbandInfo(
                    componentIndex: info.componentIndex,
                    level: info.level,
                    subband: info.subband,
                    coefficients: quantized,
                    doubleCoefficients: nil,
                    width: info.width,
                    height: info.height
                ))
            }
            result.append(quantizedSubbands)
        }

        return result
    }

    // MARK: - Stage 5: Entropy Coding

    /// Describes a pending code-block to be encoded.
    private struct PendingCodeBlock: Sendable {
        let index: Int
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let subband: J2KSubband
        let componentIndex: Int
        let resolutionLevel: Int
        let coefficients: [Int32]
        let bitDepth: Int
        let coefficientSquaredSum: Double
        let bitPlanePopulation: [Int]
    }

    /// Lightweight block descriptor for deferred-extraction HTJ2K encoding.
    ///
    /// Stores a CoW reference to the subband coefficient array plus extraction
    /// coordinates, deferring the per-block memcpy to the parallel encoding loop.
    private struct DeferredCodeBlock: Sendable {
        let index: Int
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let subband: J2KSubband
        let componentIndex: Int
        let resolutionLevel: Int
        let bitDepth: Int
        /// CoW reference to the subband's full coefficient array.
        let subbandCoefficients: [Int32]
        /// Width of the subband (row stride in elements).
        let subbandWidth: Int
        /// Origin of this block within the subband.
        let originX: Int
        let originY: Int
    }

    /// Applies entropy coding to all subbands, producing code blocks.
    ///
    /// When `config.useHTJ2K` is true, uses a fused extract-and-encode path
    /// that defers coefficient extraction to the parallel encoding loop,
    /// eliminating the sequential first pass. Otherwise uses legacy EBCOT
    /// bit-plane coding per ISO/IEC 15444-1.
    private func applyEntropyCoding(
        _ componentSubbands: [[SubbandInfo]],
        image: J2KImage
    ) throws -> [J2KCodeBlock] {
        let profiling = ProcessInfo.processInfo.environment["J2K_PROFILE"] != nil
        let entropyStart = CFAbsoluteTimeGetCurrent()

        let cbWidth = config.codeBlockSize.width
        let cbHeight = config.codeBlockSize.height

        // Determine decomposition levels actually used
        let actualLevels = componentSubbands.first.map { subbands -> Int in
            return subbands.count > 1 ? (subbands.count - 1) / 3 : 0
        } ?? config.decompositionLevels

        // Guard bits and range bits for Kb computation (must match QCD marker)
        let quantExt = J2KPart2QuantizationExtensions(configuration: config)
        let guardBits = Int(quantExt.extendedGuardBits)

        // HTJ2K fast path: build lightweight descriptors and fuse coefficient
        // extraction into the parallel encoding loop to eliminate the sequential
        // first pass.
        if config.useHTJ2K {
            return try applyEntropyCodingHTJ2KFused(
                componentSubbands, image: image,
                actualLevels: actualLevels, guardBits: guardBits,
                cbWidth: cbWidth, cbHeight: cbHeight, profiling: profiling,
                entropyStart: entropyStart
            )
        }

        // Legacy EBCOT path: sequential extraction then parallel encoding.

        // First pass: collect all pending code-blocks with their metadata
        var pendingBlocks: [PendingCodeBlock] = []
        var blockIndex = 0

        for subbands in componentSubbands {
            for info in subbands {
                guard info.width > 0 && info.height > 0 else { continue }

                // Use actual component bit depth instead of hardcoded 8
                let imageBitDepth = image.components[info.componentIndex].bitDepth

                // Compute JPEG 2000 resolution level:
                // Resolution 0 = LL subband only
                // Resolution r (1..NL) = detail subbands at decomposition level (NL - r + 1)
                let resolutionLevel: Int
                if info.subband == .ll {
                    resolutionLevel = 0
                } else {
                    resolutionLevel = actualLevels - info.level + 1
                }

                // Compute band-level Kb = ε_b + G from QCD parameters.
                // This must match what we write in the QCD marker.
                let bandKb: Int
                if config.useReversibleFilter {
                    let gainExponent: Int
                    switch info.subband {
                    case .ll: gainExponent = 0
                    case .hl, .lh: gainExponent = 1
                    case .hh: gainExponent = 2
                    }
                    let epsilon = imageBitDepth + gainExponent
                    bandKb = epsilon + guardBits - 1  // Kb = εb + Gb - 1
                } else {
                    // Lossy (9/7 irreversible): Kb = ε_b + G where ε_b from step size
                    // Must use subband gains {LL=0, HL=1, LH=1, HH=2} for Rb,
                    // matching OPJ encoder convention. OPJ decoder uses gain=0
                    // (BUG_WEIRD_TWO_INVK) with two_invK in inverse DWT.
                    let subbandGain: Int
                    switch info.subband {
                    case .ll: subbandGain = 0
                    case .hl, .lh: subbandGain = 1
                    case .hh: subbandGain = 2
                    }
                    let rangeBits = imageBitDepth + subbandGain
                    let params = J2KQuantizationParameters.fromQuality(config.quality)
                    let step = J2KStepSizeCalculator.calculateStepSize(
                        baseStepSize: params.baseStepSize,
                        subband: info.subband,
                        decompositionLevel: info.level,
                        totalLevels: actualLevels,
                        reversible: false
                    )
                    let (epsilon, _) = Self.encodeJ2KStepSize(step, rangeBits: rangeBits)
                    bandKb = epsilon + guardBits - 1  // Kb = εb + Gb - 1
                }

                let blocksX = (info.width + cbWidth - 1) / cbWidth
                let blocksY = (info.height + cbHeight - 1) / cbHeight

                for by in 0..<blocksY {
                    for bx in 0..<blocksX {
                        let blockW = min(cbWidth, info.width - bx * cbWidth)
                        let blockH = min(cbHeight, info.height - by * cbHeight)

                        // Extract code block coefficients via direct memcpy
                        let blockSize = blockW * blockH
                        var blockCoeffs = [Int32](unsafeUninitializedCapacity: blockSize) { buf, count in
                            info.coefficients.withUnsafeBufferPointer { src in
                                for row in 0..<blockH {
                                    let srcRow = by * cbHeight + row
                                    let srcStart = srcRow * info.width + bx * cbWidth
                                    memcpy(
                                        buf.baseAddress! + row * blockW,
                                        src.baseAddress! + srcStart,
                                        blockW * MemoryLayout<Int32>.size
                                    )
                                }
                                count = blockSize
                            }
                        }

                        // TEMP DEBUG: dump quantized coefficients
                        if ProcessInfo.processInfo.environment["J2K_DUMP_COEFFS"] != nil {
                            print("EBCOT_INPUT: subband=\(info.subband) comp=\(info.componentIndex) res=\(resolutionLevel) bx=\(bx) by=\(by) w=\(blockW) h=\(blockH) Kb=\(bandKb) coeffs=\(blockCoeffs)")
                        }

                        // Compute distortion statistics for rate control.
                        // For lossless mode, rate control includes all data — skip
                        // the expensive squared-sum and bit-plane population scans.
                        let sqSum: Double
                        let bpPop: [Int]
                        if config.lossless {
                            sqSum = 0
                            bpPop = []
                        } else {
                            #if canImport(Accelerate)
                            if blockCoeffs.count >= 16 {
                                var absD = vDSPConvert.int32sToDoubles(blockCoeffs)
                                vDSP_vabsD(absD, 1, &absD, 1, vDSP_Length(absD.count))
                                var dotResult: Double = 0
                                vDSP_dotprD(absD, 1, absD, 1, &dotResult, vDSP_Length(absD.count))
                                sqSum = dotResult
                            } else {
                                var sq: Double = 0
                                for c in blockCoeffs {
                                    let mag = Double(abs(c))
                                    sq += mag * mag
                                }
                                sqSum = sq
                            }
                            #else
                            do {
                                var sq: Double = 0
                                for c in blockCoeffs {
                                    let mag = Double(abs(c))
                                    sq += mag * mag
                                }
                                sqSum = sq
                            }
                            #endif

                            let totalBitPlanes = bandKb
                            var pop = [Int](repeating: 0, count: totalBitPlanes)
                            for c in blockCoeffs {
                                let mag = UInt32(abs(c))
                                if mag > 0 {
                                    let msb = 31 - mag.leadingZeroBitCount
                                    if msb < totalBitPlanes {
                                        pop[msb] += 1
                                    }
                                }
                            }
                            bpPop = pop
                        }

                        pendingBlocks.append(PendingCodeBlock(
                            index: blockIndex,
                            x: bx * cbWidth,
                            y: by * cbHeight,
                            width: blockW,
                            height: blockH,
                            subband: info.subband,
                            componentIndex: info.componentIndex,
                            resolutionLevel: resolutionLevel,
                            coefficients: blockCoeffs,
                            bitDepth: bandKb,
                            coefficientSquaredSum: sqSum,
                            bitPlanePopulation: bpPop
                        ))
                        blockIndex += 1
                    }
                }
            }
        }

        if profiling {
            let extractEnd = CFAbsoluteTimeGetCurrent()
            print("    PROFILE entropy-extract: \(pendingBlocks.count) blocks in \(String(format: "%.4f", extractEnd - entropyStart))s")
        }

        // Second pass: encode code-blocks (parallel or sequential)
        let useParallel = config.enableParallelCodeBlocks && pendingBlocks.count > 1
        let allCodeBlocks: [J2KCodeBlock]

        let encodeStart = CFAbsoluteTimeGetCurrent()
        if useParallel {
            allCodeBlocks = try encodeCodeBlocksParallel(pendingBlocks)
        } else {
            allCodeBlocks = try encodeCodeBlocksSequential(pendingBlocks)
        }

        if profiling {
            let encodeEnd = CFAbsoluteTimeGetCurrent()
            print("    PROFILE entropy-encode: \(String(format: "%.4f", encodeEnd - encodeStart))s (parallel=\(useParallel))")
        }

        return allCodeBlocks
    }

    // MARK: - HTJ2K Fused Extract-and-Encode

    /// HTJ2K fast path: builds lightweight block descriptors in a single sequential
    /// scan, then performs coefficient extraction + HT encoding in a parallel loop.
    ///
    /// Compared to the legacy two-pass approach (extract all, then encode all),
    /// this eliminates:
    /// - Sequential per-block coefficient array allocations (~4MB for 1024×1024)
    /// - The `pendingBlocks` array holding all coefficient arrays simultaneously
    /// - A full sequential pass over all subbands
    private func applyEntropyCodingHTJ2KFused(
        _ componentSubbands: [[SubbandInfo]],
        image: J2KImage,
        actualLevels: Int,
        guardBits: Int,
        cbWidth: Int,
        cbHeight: Int,
        profiling: Bool,
        entropyStart: CFAbsoluteTime
    ) throws -> [J2KCodeBlock] {
        // Build lightweight block descriptors (no coefficient copy).
        var deferred: [DeferredCodeBlock] = []
        var blockIndex = 0

        for subbands in componentSubbands {
            for info in subbands {
                guard info.width > 0 && info.height > 0 else { continue }
                let imageBitDepth = image.components[info.componentIndex].bitDepth
                let resolutionLevel: Int
                if info.subband == .ll {
                    resolutionLevel = 0
                } else {
                    resolutionLevel = actualLevels - info.level + 1
                }

                let bandKb: Int
                if config.useReversibleFilter {
                    let gainExponent: Int
                    switch info.subband {
                    case .ll: gainExponent = 0
                    case .hl, .lh: gainExponent = 1
                    case .hh: gainExponent = 2
                    }
                    bandKb = imageBitDepth + gainExponent + guardBits - 1
                } else {
                    let subbandGain: Int
                    switch info.subband {
                    case .ll: subbandGain = 0
                    case .hl, .lh: subbandGain = 1
                    case .hh: subbandGain = 2
                    }
                    let rangeBits = imageBitDepth + subbandGain
                    let params = J2KQuantizationParameters.fromQuality(config.quality)
                    let step = J2KStepSizeCalculator.calculateStepSize(
                        baseStepSize: params.baseStepSize,
                        subband: info.subband,
                        decompositionLevel: info.level,
                        totalLevels: actualLevels,
                        reversible: false
                    )
                    let (epsilon, _) = Self.encodeJ2KStepSize(step, rangeBits: rangeBits)
                    bandKb = epsilon + guardBits - 1
                }

                let blocksX = (info.width + cbWidth - 1) / cbWidth
                let blocksY = (info.height + cbHeight - 1) / cbHeight

                deferred.reserveCapacity(deferred.count + blocksX * blocksY)
                for by in 0..<blocksY {
                    for bx in 0..<blocksX {
                        let blockW = min(cbWidth, info.width - bx * cbWidth)
                        let blockH = min(cbHeight, info.height - by * cbHeight)

                        deferred.append(DeferredCodeBlock(
                            index: blockIndex,
                            x: bx * cbWidth,
                            y: by * cbHeight,
                            width: blockW,
                            height: blockH,
                            subband: info.subband,
                            componentIndex: info.componentIndex,
                            resolutionLevel: resolutionLevel,
                            bitDepth: bandKb,
                            subbandCoefficients: info.coefficients,
                            subbandWidth: info.width,
                            originX: bx * cbWidth,
                            originY: by * cbHeight
                        ))
                        blockIndex += 1
                    }
                }
            }
        }

        if profiling {
            let t = CFAbsoluteTimeGetCurrent()
            print("    PROFILE htj2k-descriptors: \(deferred.count) blocks in \(String(format: "%.4f", t - entropyStart))s")
        }

        // Parallel encode with fused coefficient extraction.
        let totalBlocks = deferred.count
        guard totalBlocks > 0 else { return [] }

        let maxConcurrency = config.maxThreads > 0 ? config.maxThreads : ProcessInfo.processInfo.processorCount
        // Only use parallel dispatch when there are enough blocks to amortize
        // the GCD overhead and per-chunk buffer allocations. For small images
        // with ≤2× the core count of blocks, the sequential path (single set
        // of reusable allocations) is faster.
        let parallelThreshold = max(4, maxConcurrency * 2)
        let useParallel = config.enableParallelCodeBlocks && totalBlocks >= parallelThreshold

        let encodeStart = CFAbsoluteTimeGetCurrent()
        let allCodeBlocks: [J2KCodeBlock]

        if useParallel {
            let collector = ParallelResultCollector<(Int, J2KCodeBlock)>(capacity: totalBlocks)

            let chunkSize = max(1, totalBlocks / maxConcurrency)
            let chunks = stride(from: 0, to: totalBlocks, by: chunkSize).map { start in
                let end = min(start + chunkSize, totalBlocks)
                return start..<end
            }

            let maxBlockSize = cbWidth * cbHeight
            let isLossless = config.lossless

            DispatchQueue.concurrentPerform(iterations: chunks.count) { chunkIdx in
                let range = chunks[chunkIdx]
                var localResults: [(Int, J2KCodeBlock)] = []
                localResults.reserveCapacity(range.count)

                // Per-chunk reusable resources
                var coeffsBuffer = [Int32](repeating: 0, count: maxBlockSize)
                var absMags = [Int32](repeating: 0, count: maxBlockSize)
                var sigPacked = [UInt64](repeating: 0, count: (maxBlockSize + 63) / 64)
                let maxRefBytes = max(4, (maxBlockSize * 2 + 7) / 8)
                var sigPropWriter = HTFastBitWriter(capacity: maxRefBytes)
                var magRefWriter = HTFastBitWriter(capacity: maxRefBytes)
                // Pre-allocated HT coders (reset per block, avoiding per-block allocation)
                var mel = HTMELCoder(capacity: max(16, maxBlockSize / 4))
                var vlc = HTVLCCoder(capacity: max(16, maxBlockSize / 2))
                var magsgn = HTMagSgnCoder(capacity: max(16, maxBlockSize * 10 / 8))

                for i in range {
                    let d = deferred[i]

                    // Extract coefficients into reusable buffer
                    let blockSize = d.width * d.height
                    d.subbandCoefficients.withUnsafeBufferPointer { src in
                        coeffsBuffer.withUnsafeMutableBufferPointer { dst in
                            for row in 0..<d.height {
                                let srcStart = (d.originY + row) * d.subbandWidth + d.originX
                                memcpy(
                                    dst.baseAddress! + row * d.width,
                                    src.baseAddress! + srcStart,
                                    d.width * MemoryLayout<Int32>.size
                                )
                            }
                        }
                    }

                    // Compute distortion stats for lossy mode
                    var sqSum: Double = 0
                    var bpPop: [Int] = []
                    if !isLossless {
                        #if canImport(Accelerate)
                        if blockSize >= 16 {
                            coeffsBuffer.withUnsafeBufferPointer { ptr in
                                var absD = [Double](unsafeUninitializedCapacity: blockSize) { buf, count in
                                    vDSP_vflt32D(ptr.baseAddress!, 1, buf.baseAddress!, 1, vDSP_Length(blockSize))
                                    count = blockSize
                                }
                                vDSP_vabsD(absD, 1, &absD, 1, vDSP_Length(blockSize))
                                var dotResult: Double = 0
                                vDSP_dotprD(absD, 1, absD, 1, &dotResult, vDSP_Length(blockSize))
                                sqSum = dotResult
                            }
                        } else {
                            for j in 0..<blockSize { sqSum += Double(coeffsBuffer[j]) * Double(coeffsBuffer[j]) }
                        }
                        #else
                        for j in 0..<blockSize {
                            let v = Double(abs(coeffsBuffer[j]))
                            sqSum += v * v
                        }
                        #endif

                        let totalBitPlanes = d.bitDepth
                        bpPop = [Int](repeating: 0, count: totalBitPlanes)
                        for j in 0..<blockSize {
                            let mag = UInt32(abs(coeffsBuffer[j]))
                            if mag > 0 {
                                let msb = 31 - mag.leadingZeroBitCount
                                if msb < totalBitPlanes { bpPop[msb] += 1 }
                            }
                        }
                    }

                    // For full-size blocks (the common case), pass coeffsBuffer
                    // directly — CoW means no copy since encode only reads.
                    // For edge blocks (blockSize < maxBlockSize), extract only
                    // the needed elements since encodeCleanupReusing validates
                    // that coefficients.count == width * height.
                    let blockCoeffs: [Int32]
                    if blockSize == maxBlockSize {
                        blockCoeffs = coeffsBuffer
                    } else {
                        blockCoeffs = Array(coeffsBuffer[0..<blockSize])
                    }

                    let pending = PendingCodeBlock(
                        index: d.index, x: d.x, y: d.y,
                        width: d.width, height: d.height,
                        subband: d.subband,
                        componentIndex: d.componentIndex,
                        resolutionLevel: d.resolutionLevel,
                        coefficients: blockCoeffs,
                        bitDepth: d.bitDepth,
                        coefficientSquaredSum: sqSum,
                        bitPlanePopulation: bpPop
                    )

                    do {
                        let codeBlock = try self.encodeCodeBlockHTJ2KFast(
                            pending,
                            absMags: &absMags,
                            sigPacked: &sigPacked,
                            sigPropWriter: &sigPropWriter,
                            magRefWriter: &magRefWriter,
                            mel: &mel,
                            vlc: &vlc,
                            magsgn: &magsgn
                        )
                        localResults.append((d.index, codeBlock))
                    } catch {
                        collector.recordError(error)
                    }
                }

                collector.append(contentsOf: localResults)
            }

            if let error = collector.firstError { throw error }
            allCodeBlocks = collector.results.sorted { $0.0 < $1.0 }.map { $0.1 }
        } else {
            // Sequential path
            var results: [J2KCodeBlock] = []
            results.reserveCapacity(totalBlocks)

            let maxBlockSize = cbWidth * cbHeight
            var coeffsBuffer = [Int32](repeating: 0, count: maxBlockSize)
            var absMags = [Int32](repeating: 0, count: maxBlockSize)
            var sigPacked = [UInt64](repeating: 0, count: (maxBlockSize + 63) / 64)
            let maxRefBytes = max(4, (maxBlockSize * 2 + 7) / 8)
            var sigPropWriter = HTFastBitWriter(capacity: maxRefBytes)
            var magRefWriter = HTFastBitWriter(capacity: maxRefBytes)
            var mel = HTMELCoder(capacity: max(16, maxBlockSize / 4))
            var vlc = HTVLCCoder(capacity: max(16, maxBlockSize / 2))
            var magsgn = HTMagSgnCoder(capacity: max(16, maxBlockSize * 10 / 8))

            let isLossless = config.lossless
            for d in deferred {
                let blockSize = d.width * d.height
                d.subbandCoefficients.withUnsafeBufferPointer { src in
                    coeffsBuffer.withUnsafeMutableBufferPointer { dst in
                        for row in 0..<d.height {
                            let srcStart = (d.originY + row) * d.subbandWidth + d.originX
                            memcpy(
                                dst.baseAddress! + row * d.width,
                                src.baseAddress! + srcStart,
                                d.width * MemoryLayout<Int32>.size
                            )
                        }
                    }
                }

                // Compute distortion stats for lossy rate control
                var sqSum: Double = 0
                var bpPop: [Int] = []
                if !isLossless {
                    #if canImport(Accelerate)
                    if blockSize >= 16 {
                        coeffsBuffer.withUnsafeBufferPointer { ptr in
                            var absD = [Double](unsafeUninitializedCapacity: blockSize) { buf, count in
                                vDSP_vflt32D(ptr.baseAddress!, 1, buf.baseAddress!, 1, vDSP_Length(blockSize))
                                count = blockSize
                            }
                            vDSP_vabsD(absD, 1, &absD, 1, vDSP_Length(blockSize))
                            var dotResult: Double = 0
                            vDSP_dotprD(absD, 1, absD, 1, &dotResult, vDSP_Length(blockSize))
                            sqSum = dotResult
                        }
                    } else {
                        for j in 0..<blockSize { sqSum += Double(coeffsBuffer[j]) * Double(coeffsBuffer[j]) }
                    }
                    #else
                    for j in 0..<blockSize {
                        let v = Double(abs(coeffsBuffer[j]))
                        sqSum += v * v
                    }
                    #endif

                    let totalBitPlanes = d.bitDepth
                    bpPop = [Int](repeating: 0, count: totalBitPlanes)
                    for j in 0..<blockSize {
                        let mag = UInt32(abs(coeffsBuffer[j]))
                        if mag > 0 {
                            let msb = 31 - mag.leadingZeroBitCount
                            if msb < totalBitPlanes { bpPop[msb] += 1 }
                        }
                    }
                }

                let blockCoeffs: [Int32]
                if blockSize == maxBlockSize {
                    blockCoeffs = coeffsBuffer
                } else {
                    blockCoeffs = Array(coeffsBuffer[0..<blockSize])
                }

                let pending = PendingCodeBlock(
                    index: d.index, x: d.x, y: d.y,
                    width: d.width, height: d.height,
                    subband: d.subband,
                    componentIndex: d.componentIndex,
                    resolutionLevel: d.resolutionLevel,
                    coefficients: blockCoeffs,
                    bitDepth: d.bitDepth,
                    coefficientSquaredSum: sqSum,
                    bitPlanePopulation: bpPop
                )

                let codeBlock = try encodeCodeBlockHTJ2KFast(
                    pending,
                    absMags: &absMags,
                    sigPacked: &sigPacked,
                    sigPropWriter: &sigPropWriter,
                    magRefWriter: &magRefWriter,
                    mel: &mel,
                    vlc: &vlc,
                    magsgn: &magsgn
                )
                results.append(codeBlock)
            }
            allCodeBlocks = results
        }

        if profiling {
            let encodeEnd = CFAbsoluteTimeGetCurrent()
            print("    PROFILE htj2k-encode: \(String(format: "%.4f", encodeEnd - encodeStart))s (parallel=\(useParallel), blocks=\(totalBlocks))")
        }

        return allCodeBlocks
    }

    /// Encodes code-blocks sequentially.
    ///
    /// Dispatches to HTJ2K FBCOT block coding when `config.useHTJ2K` is true,
    /// otherwise uses legacy EBCOT bit-plane coding.
    private func encodeCodeBlocksSequential(
        _ pendingBlocks: [PendingCodeBlock]
    ) throws -> [J2KCodeBlock] {
        var results: [J2KCodeBlock] = []
        results.reserveCapacity(pendingBlocks.count)

        if config.useHTJ2K {
            // HTJ2K fast path: pre-allocate reusable arrays + writers
            let maxBlockSize = config.codeBlockSize.width * config.codeBlockSize.height
            var absMags = [Int32](repeating: 0, count: maxBlockSize)
            var sigPacked = [UInt64](repeating: 0, count: (maxBlockSize + 63) / 64)
            let maxRefBytes = max(4, (maxBlockSize * 2 + 7) / 8)
            var sigPropWriter = HTFastBitWriter(capacity: maxRefBytes)
            var magRefWriter = HTFastBitWriter(capacity: maxRefBytes)
            var mel = HTMELCoder(capacity: max(16, maxBlockSize / 4))
            var vlc = HTVLCCoder(capacity: max(16, maxBlockSize / 2))
            var magsgn = HTMagSgnCoder(capacity: max(16, maxBlockSize * 10 / 8))

            for pending in pendingBlocks {
                let codeBlock = try encodeCodeBlockHTJ2KFast(
                    pending,
                    absMags: &absMags,
                    sigPacked: &sigPacked,
                    sigPropWriter: &sigPropWriter,
                    magRefWriter: &magRefWriter,
                    mel: &mel,
                    vlc: &vlc,
                    magsgn: &magsgn
                )
                results.append(codeBlock)
            }
        } else {
            // Legacy path: use EBCOT bit-plane coding
            let encoder = CodeBlockEncoder()
            for pending in pendingBlocks {
                var codeBlock = try encoder.encode(
                    coefficients: pending.coefficients,
                    width: pending.width,
                    height: pending.height,
                    subband: pending.subband,
                    bitDepth: pending.bitDepth
                )

                codeBlock = J2KCodeBlock(
                    index: pending.index,
                    x: pending.x,
                    y: pending.y,
                    width: pending.width,
                    height: pending.height,
                    subband: codeBlock.subband,
                    componentIndex: pending.componentIndex,
                    resolutionLevel: pending.resolutionLevel,
                    data: codeBlock.data,
                    passeCount: codeBlock.passeCount,
                    zeroBitPlanes: codeBlock.zeroBitPlanes,
                    passSegmentLengths: codeBlock.passSegmentLengths,
                    cumulativePassBytes: codeBlock.cumulativePassBytes,
                    coefficientSquaredSum: pending.coefficientSquaredSum,
                    bitPlanePopulation: pending.bitPlanePopulation,
                    cumulativePassDistortion: codeBlock.cumulativePassDistortion,
                    perPassSnapshotData: codeBlock.perPassSnapshotData,
                    mqCheckpoints: codeBlock.mqCheckpoints,
                    rawMQOutput: codeBlock.rawMQOutput
                )

                results.append(codeBlock)
            }
        }

        return results
    }

    /// Encodes code-blocks in parallel using structured concurrency.
    ///
    /// Each code-block is an independent unit of entropy coding with its own
    /// MQ encoder state and context models (EBCOT) or MEL/VLC/MagSgn state (HTJ2K),
    /// making them safe to process in parallel.
    ///
    /// Dispatches to HTJ2K FBCOT block coding when `config.useHTJ2K` is true,
    /// otherwise uses legacy EBCOT bit-plane coding.
    private func encodeCodeBlocksParallel(
        _ pendingBlocks: [PendingCodeBlock]
    ) throws -> [J2KCodeBlock] {
        let maxConcurrency = config.maxThreads > 0 ? config.maxThreads : ProcessInfo.processInfo.processorCount
        let totalBlocks = pendingBlocks.count

        // Thread-safe result collector
        let collector = ParallelResultCollector<(Int, J2KCodeBlock)>(capacity: totalBlocks)

        // Determine chunk size for balanced workload
        let chunkSize = max(1, totalBlocks / maxConcurrency)
        let chunks = stride(from: 0, to: totalBlocks, by: chunkSize).map { start in
            let end = min(start + chunkSize, totalBlocks)
            return Array(pendingBlocks[start..<end])
        }

        let useHT = config.useHTJ2K
        let cbW = config.codeBlockSize.width
        let cbH = config.codeBlockSize.height

        DispatchQueue.concurrentPerform(iterations: chunks.count) { chunkIdx in
            let chunk = chunks[chunkIdx]
            var localResults: [(Int, J2KCodeBlock)] = []
            localResults.reserveCapacity(chunk.count)

            if useHT {
                // HTJ2K fast path: pre-allocate reusable arrays and writers per chunk
                // to eliminate per-block heap allocations. The arrays are reused
                // across all blocks in this chunk (same thread).
                let maxBlockSize = cbW * cbH
                var absMags = [Int32](repeating: 0, count: maxBlockSize)
                var sigPacked = [UInt64](repeating: 0, count: (maxBlockSize + 63) / 64)
                let maxRefBytes = max(4, (maxBlockSize * 2 + 7) / 8)
                var sigPropWriter = HTFastBitWriter(capacity: maxRefBytes)
                var magRefWriter = HTFastBitWriter(capacity: maxRefBytes)
                var mel = HTMELCoder(capacity: max(16, maxBlockSize / 4))
                var vlc = HTVLCCoder(capacity: max(16, maxBlockSize / 2))
                var magsgn = HTMagSgnCoder(capacity: max(16, maxBlockSize * 10 / 8))

                for pending in chunk {
                    do {
                        let codeBlock = try self.encodeCodeBlockHTJ2KFast(
                            pending,
                            absMags: &absMags,
                            sigPacked: &sigPacked,
                            sigPropWriter: &sigPropWriter,
                            magRefWriter: &magRefWriter,
                            mel: &mel,
                            vlc: &vlc,
                            magsgn: &magsgn
                        )
                        localResults.append((pending.index, codeBlock))
                    } catch {
                        collector.recordError(error)
                    }
                }
            } else {
                // Legacy path: use EBCOT bit-plane coding
                let encoder = CodeBlockEncoder()
                for pending in chunk {
                    do {
                        var codeBlock = try encoder.encode(
                            coefficients: pending.coefficients,
                            width: pending.width,
                            height: pending.height,
                            subband: pending.subband,
                            bitDepth: pending.bitDepth
                        )

                        codeBlock = J2KCodeBlock(
                            index: pending.index,
                            x: pending.x,
                            y: pending.y,
                            width: pending.width,
                            height: pending.height,
                            subband: codeBlock.subband,
                            componentIndex: pending.componentIndex,
                            resolutionLevel: pending.resolutionLevel,
                            data: codeBlock.data,
                            passeCount: codeBlock.passeCount,
                            zeroBitPlanes: codeBlock.zeroBitPlanes,
                            passSegmentLengths: codeBlock.passSegmentLengths,
                            cumulativePassBytes: codeBlock.cumulativePassBytes,
                            coefficientSquaredSum: pending.coefficientSquaredSum,
                            bitPlanePopulation: pending.bitPlanePopulation,
                            cumulativePassDistortion: codeBlock.cumulativePassDistortion,
                            perPassSnapshotData: codeBlock.perPassSnapshotData,
                            mqCheckpoints: codeBlock.mqCheckpoints,
                            rawMQOutput: codeBlock.rawMQOutput
                        )

                        localResults.append((pending.index, codeBlock))
                    } catch {
                        collector.recordError(error)
                    }
                }
            }

            collector.append(contentsOf: localResults)
        }

        // Propagate any encoding errors
        if let error = collector.firstError {
            throw error
        }

        // Sort by original index to maintain order
        return collector.results.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    // MARK: - HTJ2K Block Encoding

    /// Encodes a single code-block using HTJ2K FBCOT block coding.
    ///
    /// Converts the pipeline's Int32 coefficients to the HTBlockEncoder's Int interface,
    /// runs the HT cleanup + refinement passes, and wraps the result in a `J2KCodeBlock`
    /// that is compatible with the rest of the encoding pipeline (rate control, Tier-2,
    /// codestream generation).
    ///
    /// - Parameter pending: The pending code-block with coefficients and metadata.
    /// - Returns: A `J2KCodeBlock` with HT-encoded data.
    /// - Throws: ``J2KError/encodingError(_:)`` if HT encoding fails.
    private func encodeCodeBlockHTJ2K(_ pending: PendingCodeBlock) throws -> J2KCodeBlock {
        let htEncoder = HTBlockEncoder(
            width: pending.width,
            height: pending.height,
            subband: pending.subband
        )

        // Determine the most significant bit-plane directly from Int32 coefficients
        // using the existing SIMD-optimized helper (no intermediate array allocation).
        let maxMag = Int(Self.maxAbsValue(pending.coefficients))

        // Early termination: trivial block with no significant coefficients
        guard maxMag > 0 else {
            let emptyData = Data()
            return J2KCodeBlock(
                index: pending.index,
                x: pending.x,
                y: pending.y,
                width: pending.width,
                height: pending.height,
                subband: pending.subband,
                componentIndex: pending.componentIndex,
                resolutionLevel: pending.resolutionLevel,
                data: emptyData,
                passeCount: 0,
                zeroBitPlanes: pending.bitDepth,
                passSegmentLengths: [],
                cumulativePassBytes: [],
                coefficientSquaredSum: pending.coefficientSquaredSum,
                bitPlanePopulation: pending.bitPlanePopulation
            )
        }

        let topBitPlane = Int.bitWidth - maxMag.leadingZeroBitCount - 1

        // Encode cleanup pass directly from Int32 coefficients (no copy).
        // The Int32 overload also returns significance state and absolute
        // magnitudes, avoiding redundant recomputation.
        let cleanupResult = try htEncoder.encodeCleanup(
            coefficients: pending.coefficients,
            bitPlane: topBitPlane
        )
        let cleanupBlock = cleanupResult.block
        var sigPacked = cleanupResult.sigPacked
        let absMags = cleanupResult.absMags

        // Encode refinement passes (SigProp + MagRef) for lower bit-planes.
        // Cap at a configurable maximum to avoid encoding bit-planes that rate
        // control will truncate anyway. Each pair adds ~2× block size in output
        // with diminishing quality contribution.
        let count = pending.width * pending.height

        // Encode refinement passes (SigProp + MagRef) for all remaining bit-planes.
        // PCRD rate control will truncate unnecessary passes for lossy encoding;
        // for lossless encoding, all bit-planes are required for exact reconstruction.
        // Uses fused SigProp+MagRef scan — single pass per bit-plane instead of two
        // separate scans, updating the packed significance bitfield in-place.
        //
        // For lossy mode, cap refinement bit-planes: rate control will discard
        // the deepest planes anyway, so encoding them wastes CPU time. The cap
        // is derived from the target bitrate:
        //   bpp ≥ 2  → encode all planes (high quality)
        //   bpp ≈ 1  → skip last 2 planes
        //   bpp ≤ 0.5 → skip last 4 planes
        // For constant quality, map quality → effective cap.
        let maxRefinementPlanes: Int
        if config.lossless {
            maxRefinementPlanes = topBitPlane  // encode all
        } else {
            // Generate all refinement planes and let PCRD handle truncation.
            maxRefinementPlanes = topBitPlane
        }

        let lowestRefinementPlane = max(0, topBitPlane - maxRefinementPlanes)
        let numRefinementPlanes = max(0, topBitPlane - lowestRefinementPlane)

        // Pre-allocate allPassData with estimated capacity to minimize Data
        // reallocation during refinement pass appending.
        let estimatedRefinementSize = numRefinementPlanes * max(4, (count * 3 + 7) / 8)
        var allPassData = cleanupBlock.codedData
        allPassData.reserveCapacity(allPassData.count + estimatedRefinementSize)
        var totalPasses = 1  // cleanup pass
        var passSegmentLengths = [cleanupBlock.codedData.count]
        var cumulativePassBytes = [cleanupBlock.codedData.count]

        // Use direct-output refinement: appends encoded bytes directly to
        // allPassData, avoiding intermediate Data creation per pass.
        for bp in stride(from: topBitPlane - 1, through: lowestRefinementPlane, by: -1) {
            let (sigPropBytes, magRefBytes) = htEncoder.encodeFusedRefinementDirect(
                coefficients: pending.coefficients,
                absMags: absMags,
                sigPacked: &sigPacked,
                bitPlane: bp,
                output: &allPassData
            )

            totalPasses += 1
            passSegmentLengths.append(sigPropBytes)
            cumulativePassBytes.append(allPassData.count - magRefBytes)

            totalPasses += 1
            passSegmentLengths.append(magRefBytes)
            cumulativePassBytes.append(allPassData.count)
        }

        let zeroBitPlanes = max(0, pending.bitDepth - topBitPlane - 1)

        return J2KCodeBlock(
            index: pending.index,
            x: pending.x,
            y: pending.y,
            width: pending.width,
            height: pending.height,
            subband: pending.subband,
            componentIndex: pending.componentIndex,
            resolutionLevel: pending.resolutionLevel,
            data: allPassData,
            passeCount: totalPasses,
            zeroBitPlanes: zeroBitPlanes,
            passSegmentLengths: passSegmentLengths,
            cumulativePassBytes: cumulativePassBytes,
            coefficientSquaredSum: pending.coefficientSquaredSum,
            bitPlanePopulation: pending.bitPlanePopulation
        )
    }

    // MARK: - HTJ2K Fast Block Encoding (Reusing Allocations)

    /// Encodes a single code-block using HTJ2K FBCOT block coding with pre-allocated
    /// scratch arrays and reusable writers.
    ///
    /// This is the fast path called from `encodeCodeBlocksParallel`. It eliminates
    /// per-block allocation of `absMags`, `sigPacked`, and per-refinement-pass
    /// writer allocations by reusing caller-provided buffers.
    ///
    /// - Parameters:
    ///   - pending: The pending code-block with coefficients and metadata.
    ///   - absMags: Pre-allocated absolute magnitude array (reused across blocks).
    ///   - sigPacked: Pre-allocated significance bitfield (reused across blocks).
    ///   - sigPropWriter: Pre-allocated SigProp writer (reused across refinement passes).
    ///   - magRefWriter: Pre-allocated MagRef writer (reused across refinement passes).
    ///   - mel: Pre-allocated MEL coder (reset and reused per block).
    ///   - vlc: Pre-allocated VLC coder (reset and reused per block).
    ///   - magsgn: Pre-allocated MagSgn coder (reset and reused per block).
    /// - Returns: A `J2KCodeBlock` with HT-encoded data.
    /// - Throws: ``J2KError/encodingError(_:)`` if HT encoding fails.
    private func encodeCodeBlockHTJ2KFast(
        _ pending: PendingCodeBlock,
        absMags: inout [Int32],
        sigPacked: inout [UInt64],
        sigPropWriter: inout HTFastBitWriter,
        magRefWriter: inout HTFastBitWriter,
        mel: inout HTMELCoder,
        vlc: inout HTVLCCoder,
        magsgn: inout HTMagSgnCoder
    ) throws -> J2KCodeBlock {
        let htEncoder = HTBlockEncoder(
            width: pending.width,
            height: pending.height,
            subband: pending.subband
        )

        let maxMag = Int(Self.maxAbsValue(pending.coefficients))

        guard maxMag > 0 else {
            return J2KCodeBlock(
                index: pending.index,
                x: pending.x,
                y: pending.y,
                width: pending.width,
                height: pending.height,
                subband: pending.subband,
                componentIndex: pending.componentIndex,
                resolutionLevel: pending.resolutionLevel,
                data: Data(),
                passeCount: 0,
                zeroBitPlanes: pending.bitDepth,
                passSegmentLengths: [],
                cumulativePassBytes: [],
                coefficientSquaredSum: pending.coefficientSquaredSum,
                bitPlanePopulation: pending.bitPlanePopulation
            )
        }

        let topBitPlane = Int.bitWidth - maxMag.leadingZeroBitCount - 1

        // Clear sigPacked for this block (only the used portion)
        let count = pending.width * pending.height
        let sigWords = (count + 63) / 64
        for i in 0..<sigWords {
            sigPacked[i] = 0
        }

        // Cleanup pass using pre-allocated arrays and coders
        let cleanupBlock = try htEncoder.encodeCleanupFullyReusing(
            coefficients: pending.coefficients,
            bitPlane: topBitPlane,
            absMags: &absMags,
            sigPacked: &sigPacked,
            mel: &mel,
            vlc: &vlc,
            magsgn: &magsgn
        )

        // Refinement passes with reusable writers
        let maxRefinementPlanes: Int
        if config.lossless {
            maxRefinementPlanes = topBitPlane
        } else {
            // Generate all refinement planes and let PCRD handle truncation.
            maxRefinementPlanes = topBitPlane
        }

        let lowestRefinementPlane = max(0, topBitPlane - maxRefinementPlanes)
        let numRefinementPlanes = max(0, topBitPlane - lowestRefinementPlane)

        let estimatedRefinementSize = numRefinementPlanes * max(4, (count * 3 + 7) / 8)
        var allPassData = cleanupBlock.codedData
        allPassData.reserveCapacity(allPassData.count + estimatedRefinementSize)
        var totalPasses = 1
        var passSegmentLengths = [cleanupBlock.codedData.count]
        var cumulativePassBytes = [cleanupBlock.codedData.count]

        // --- Actual per-pass distortion tracking for HTJ2K ---
        // Track per-coefficient reconstruction to compute accurate R-D slopes.
        // The cleanup pass gives EXACT magnitudes for significant coefficients
        // (all bits via MagSgn), unlike standard EBCOT which only gives the MSB.
        // SigProp-discovered coefficients start with just their significance bit
        // and are refined by subsequent MagRef passes.
        var cumulativePassDistortion: [Double]
        // Per-coefficient reconstruction magnitude (absolute value).
        // Cleanup-significant: exact magnitude (all bits known).
        // SigProp-significant: only the significance bit initially, refined by MagRef.
        var reconMag: [Int32]?
        if !config.lossless {
            reconMag = [Int32](repeating: 0, count: count)
            // After cleanup: significant coefficients have exact values
            var distReduction: Double = 0
            for i in 0..<count {
                let original = Double(pending.coefficients[i])
                if (sigPacked[i >> 6] >> (i & 63)) & 1 != 0 {
                    // Significant: reconstructed = original (exact from cleanup)
                    reconMag![i] = abs(pending.coefficients[i])
                    distReduction += original * original  // error went from original² to 0
                }
            }
            cumulativePassDistortion = [distReduction]
        } else {
            reconMag = nil
            cumulativePassDistortion = []
        }

        let maxRefBytes = max(4, (count * 2 + 7) / 8)
        for bp in stride(from: topBitPlane - 1, through: lowestRefinementPlane, by: -1) {
            // Reset writers for this bit-plane (reuses existing buffer allocation)
            sigPropWriter.reset(capacity: maxRefBytes)
            magRefWriter.reset(capacity: maxRefBytes)

            // Save pre-SigProp significance for distortion tracking
            let preSigPacked = sigPacked

            let (sigPropBytes, magRefBytes) = htEncoder.encodeFusedRefinementReusing(
                coefficients: pending.coefficients,
                absMags: absMags,
                sigPacked: &sigPacked,
                bitPlane: bp,
                output: &allPassData,
                sigPropWriter: &sigPropWriter,
                magRefWriter: &magRefWriter
            )

            totalPasses += 1
            passSegmentLengths.append(sigPropBytes)
            cumulativePassBytes.append(allPassData.count - magRefBytes)

            // SigProp distortion: newly significant coefficients at this bit plane
            // get reconstruction = sign*(1 << bp), reducing their error.
            if !config.lossless {
                var distReduction = cumulativePassDistortion.last ?? 0
                let sigBitVal = Int32(1 << bp)
                for i in 0..<count {
                    let wasSignificant = (preSigPacked[i >> 6] >> (i & 63)) & 1 != 0
                    let isSignificant = (sigPacked[i >> 6] >> (i & 63)) & 1 != 0
                    if isSignificant && !wasSignificant {
                        let original = Double(pending.coefficients[i])
                        let recon = Double(pending.coefficients[i] >= 0 ? sigBitVal : -sigBitVal)
                        distReduction += original * original - (original - recon) * (original - recon)
                        reconMag![i] = sigBitVal
                    }
                }
                cumulativePassDistortion.append(distReduction)
            }

            totalPasses += 1
            passSegmentLengths.append(magRefBytes)
            cumulativePassBytes.append(allPassData.count)

            // MagRef distortion: for pre-SigProp significant coefficients, MagRef
            // refines bit `bp`. Cleanup-significant coefficients already have exact
            // values (all bits from MagSgn), so their MagRef is redundant (0 change).
            // SigProp-significant coefficients from HIGHER planes get bit `bp` added,
            // improving their reconstruction.
            if !config.lossless {
                var distReduction = cumulativePassDistortion.last ?? 0
                let bpBit = Int32(1 << bp)
                for i in 0..<count {
                    let wasPreSigProp = (preSigPacked[i >> 6] >> (i & 63)) & 1 != 0
                    guard wasPreSigProp else { continue }
                    let origMag = abs(pending.coefficients[i])
                    let oldRecon = reconMag![i]
                    // If reconstruction already equals the original (cleanup-significant
                    // coefficients), MagRef adds nothing.
                    if oldRecon == origMag { continue }
                    // MagRef reveals bit `bp` of the magnitude
                    let bit = (origMag >> bp) & 1
                    let newRecon = bit != 0 ? (oldRecon | bpBit) : oldRecon
                    if newRecon != oldRecon {
                        let original = Double(pending.coefficients[i])
                        let sign: Double = pending.coefficients[i] >= 0 ? 1.0 : -1.0
                        let oldErr = original - sign * Double(oldRecon)
                        let newErr = original - sign * Double(newRecon)
                        distReduction += oldErr * oldErr - newErr * newErr
                        reconMag![i] = newRecon
                    }
                }
                cumulativePassDistortion.append(distReduction)
            }
        }

        let zeroBitPlanes = max(0, pending.bitDepth - topBitPlane - 1)

        return J2KCodeBlock(
            index: pending.index,
            x: pending.x,
            y: pending.y,
            width: pending.width,
            height: pending.height,
            subband: pending.subband,
            componentIndex: pending.componentIndex,
            resolutionLevel: pending.resolutionLevel,
            data: allPassData,
            passeCount: totalPasses,
            zeroBitPlanes: zeroBitPlanes,
            passSegmentLengths: passSegmentLengths,
            cumulativePassBytes: cumulativePassBytes,
            coefficientSquaredSum: pending.coefficientSquaredSum,
            bitPlanePopulation: pending.bitPlanePopulation,
            cumulativePassDistortion: cumulativePassDistortion
        )
    }

    // MARK: - SIMD Helpers

    /// Computes the maximum absolute value in an array using SIMD operations.
    ///
    /// Processes 4 elements at a time using SIMD4 vectors for improved throughput
    /// on coefficient arrays during bit depth computation.
    ///
    /// - Parameter values: The array of Int32 values.
    /// - Returns: The maximum absolute value in the array.
    static func maxAbsValue(_ values: [Int32]) -> Int32 {
        guard !values.isEmpty else { return 0 }

        return values.withUnsafeBufferPointer { ptr in
            let base = ptr.baseAddress!
            let count = ptr.count
            let simdCount = count / 4

            var maxVec = SIMD4<Int32>.zero

            for i in 0..<simdCount {
                let offset = i * 4
                let v = SIMD4<Int32>(
                    base[offset],
                    base[offset + 1],
                    base[offset + 2],
                    base[offset + 3]
                )
                // Compute absolute values: abs(v) = v < 0 ? -v : v
                let negative = v .< SIMD4<Int32>.zero
                let absV = v.replacing(with: SIMD4<Int32>.zero &- v, where: negative)
                maxVec = pointwiseMax(maxVec, absV)
            }

            // Reduce SIMD4 to scalar max
            var result = Swift.max(
                Swift.max(maxVec[0], maxVec[1]),
                Swift.max(maxVec[2], maxVec[3])
            )

            // Handle remainder
            let remStart = simdCount * 4
            for i in remStart..<count {
                result = Swift.max(result, abs(base[i]))
            }

            return result
        }
    }

    // MARK: - Stage 6: Rate Control

    /// Applies rate control and quality layer formation.
    private func applyRateControl(
        codeBlocks: [J2KCodeBlock], totalPixels: Int
    ) throws -> [QualityLayer] {
        guard !codeBlocks.isEmpty else {
            return [QualityLayer(index: 0)]
        }

        // Fast path: lossless mode — include all passes from every block.
        // Skip J2KRateControl instantiation and dictionary creation entirely.
        if config.lossless {
            var contributions = [Int: Int](minimumCapacity: codeBlocks.count)
            for cb in codeBlocks where cb.passeCount > 0 {
                contributions[cb.index] = cb.passeCount
            }
            return [QualityLayer(index: 0, targetRate: nil,
                                 codeBlockContributions: contributions)]
        }

        let rateConfig: RateControlConfiguration
        let ppbp = config.useHTJ2K ? 2 : 3
        switch config.bitrateMode {
        case .constantBitrate(let bpp):
            rateConfig = RateControlConfiguration(
                mode: .targetBitrate(bpp),
                layerCount: config.qualityLayers,
                useReversibleFilter: config.useReversibleFilter,
                passesPerBitPlane: ppbp
            )
        case .constantQuality:
            rateConfig = RateControlConfiguration(
                mode: .constantQuality(max(0.0, min(1.0, config.quality))),
                layerCount: config.qualityLayers,
                useReversibleFilter: config.useReversibleFilter,
                passesPerBitPlane: ppbp
            )
        case .variableBitrate(_, let maxBpp):
            rateConfig = RateControlConfiguration(
                mode: .targetBitrate(maxBpp),
                layerCount: config.qualityLayers,
                useReversibleFilter: config.useReversibleFilter,
                passesPerBitPlane: ppbp
            )
        case .lossless:
            rateConfig = .lossless
        }

        let rateControl = J2KRateControl(configuration: rateConfig)
        return try rateControl.optimizeLayers(codeBlocks: codeBlocks, totalPixels: totalPixels)
    }

    // MARK: - Stage 7: Codestream Generation

    /// Generates a JPEG 2000 codestream with proper markers.
    private func generateCodestream(
        image: J2KImage,
        codeBlocks: [J2KCodeBlock],
        layers: [QualityLayer],
        actualDecompositionLevels: Int
    ) throws -> Data {
        // Pre-size buffer based on total code block data + marker/header overhead
        let totalBytes = codeBlocks.reduce(0) { $0 + $1.data.count }
        var writer = J2KBitWriter(capacity: totalBytes + totalBytes / 8 + 2048)

        // SOC — Start of Codestream
        writer.writeMarker(J2KMarker.soc.rawValue)

        // SIZ — Image and Tile Size
        try writeSIZMarker(&writer, image: image)

        // CAP — Extended Capabilities (HTJ2K Part 15)
        // CPF — Corresponding Profile (HTJ2K Part 15)
        // These markers must appear before COD when HTJ2K is enabled
        if config.useHTJ2K {
            try writeCAPMarker(&writer)
            try writeCPFMarker(&writer)
        }

        // COD — Coding Style Default
        try writeCODMarker(&writer, image: image, decompositionLevels: actualDecompositionLevels)

        // QCD — Quantization Default
        try writeQCDMarker(&writer, image: image, decompositionLevels: actualDecompositionLevels)

        // SOT — Start of Tile-part (single tile for now)
        // Collect all tile data first so we know the length
        let tileData = try generateTileData(
            codeBlocks: codeBlocks, layers: layers,
            decompositionLevels: actualDecompositionLevels,
            componentCount: image.components.count
        )
        try writeSOTMarker(&writer, tileIndex: 0, tilePartLength: tileData.count)

        // SOD — Start of Data
        writer.writeMarker(J2KMarker.sod.rawValue)

        // Tile bitstream data
        writer.writeBytes(tileData)

        // EOC — End of Codestream
        writer.writeMarker(J2KMarker.eoc.rawValue)

        return writer.data
    }

    /// Writes the SIZ marker segment (Image and Tile Size).
    private func writeSIZMarker(_ writer: inout J2KBitWriter, image: J2KImage) throws {
        var segment = J2KBitWriter()

        // Rsiz — Capabilities
        // Compute Part 2 capabilities from configuration
        let capabilities = J2KPart2Capabilities(configuration: config)
        segment.writeUInt16(capabilities.rsizValue)
        // Xsiz — Image width
        segment.writeUInt32(UInt32(image.width))
        // Ysiz — Image height
        segment.writeUInt32(UInt32(image.height))
        // XOsiz — Horizontal offset (0)
        segment.writeUInt32(0)
        // YOsiz — Vertical offset (0)
        segment.writeUInt32(0)
        // XTsiz — Tile width (image width for single-tile mode)
        // Note: Multi-tile encoding is not yet supported; always use full image
        // dimensions to ensure the single SOT/SOD pair covers the entire image.
        let tileW = image.width
        segment.writeUInt32(UInt32(tileW))
        // YTsiz — Tile height (image height for single-tile mode)
        let tileH = image.height
        segment.writeUInt32(UInt32(tileH))
        // XTOsiz — Tile offset X (0)
        segment.writeUInt32(0)
        // YTOsiz — Tile offset Y (0)
        segment.writeUInt32(0)
        // Csiz — Number of components
        segment.writeUInt16(UInt16(image.components.count))

        // Per-component parameters
        for component in image.components {
            // Ssiz — Bit depth (bit 7 = signed flag, bits 0-6 = depth - 1)
            let ssiz = UInt8((component.signed ? 0x80 : 0x00) | ((component.bitDepth - 1) & 0x7F))
            segment.writeUInt8(ssiz)
            // XRsiz — Horizontal subsampling
            segment.writeUInt8(UInt8(component.subsamplingX))
            // YRsiz — Vertical subsampling
            segment.writeUInt8(UInt8(component.subsamplingY))
        }

        writer.writeMarkerSegment(J2KMarker.siz.rawValue, segmentData: segment.data)
    }

    /// Writes the CAP marker segment (Extended Capabilities) for HTJ2K.
    ///
    /// The CAP marker signals HTJ2K support and capabilities to the decoder.
    /// Format per ISO/IEC 15444-15:
    /// - Pcap (4 bytes): Part capabilities (bit 17 set for Part 15)
    /// - Ccap (2 × N bytes): Capability pairs (HT support flags)
    private func writeCAPMarker(_ writer: inout J2KBitWriter) throws {
        var segment = J2KBitWriter()

        // Pcap (4 bytes): Part capabilities
        // Bit 17 (0x00020000) indicates Part 15 (HTJ2K) support
        let pcap: UInt32 = 0x00020000
        segment.writeUInt32(pcap)

        // Ccap15 (2 bytes): one word per set Pcap bit.
        // Bit 5 (0x0020) indicates HT block coding (Part 15).
        let ccap15: UInt16 = 0x0020
        segment.writeUInt16(ccap15)

        writer.writeMarkerSegment(J2KMarker.cap.rawValue, segmentData: segment.data)
    }

    /// Writes the CPF marker segment (Corresponding Profile) for HTJ2K.
    ///
    /// The CPF marker specifies the HTJ2K profile used for encoding.
    /// Format per ISO/IEC 15444-15:
    /// - Pcpf (2 bytes): Profile capabilities
    ///   - 0: Part 15 reversible (5/3 wavelet, lossless)
    ///   - 1: Part 15 irreversible (9/7 wavelet, lossy)
    ///
    /// Note: Broadcast profile (value 2) is defined in the standard but not yet implemented.
    private func writeCPFMarker(_ writer: inout J2KBitWriter) throws {
        var segment = J2KBitWriter()

        // Pcpf (2 bytes): Profile selection
        // Select profile based on compression mode
        let pcpf: UInt16 = config.useReversibleFilter ? 0 : 1

        segment.writeUInt16(pcpf)

        writer.writeMarkerSegment(J2KMarker.cpf.rawValue, segmentData: segment.data)
    }

    /// Writes the COD marker segment (Coding Style Default).
    private func writeCODMarker(_ writer: inout J2KBitWriter, image: J2KImage, decompositionLevels: Int) throws {
        var segment = J2KBitWriter()

        // Scod — Coding style flags
        // Bit 0: Default precinct sizes specified
        // Bit 1: SOP markers
        // Bit 2: EPH markers
        // Bits 3-7: reserved (must be 0)
        let scod: UInt8 = 0
        segment.writeUInt8(scod)

        // SGcod — Progression order: always LRCP (0) for compatibility
        segment.writeUInt8(0)

        // Number of layers: use 1 for simple correct encoding
        segment.writeUInt16(1)

        // Multiple component transform (1 = RCT/ICT, 0 = none)
        // MCT is applied whenever the encoder performs a colour transform (3+ components)
        let useMCT: Bool = image.components.count >= 3
        segment.writeUInt8(useMCT ? 1 : 0)

        // SPcod — Coding parameters
        // Number of decomposition levels
        segment.writeUInt8(UInt8(decompositionLevels))

        // Code-block width exponent (offset by 2)
        let cbWidthExp = Int(log2(Double(config.codeBlockSize.width)))
        segment.writeUInt8(UInt8(cbWidthExp - 2))

        // Code-block height exponent (offset by 2)
        let cbHeightExp = Int(log2(Double(config.codeBlockSize.height)))
        segment.writeUInt8(UInt8(cbHeightExp - 2))

        // Code-block style
        // Bit 0: Selective arithmetic coding bypass
        // Bit 1: Reset context probabilities
        // Bit 2: Termination on each coding pass
        // Bit 3: Vertically causal context
        // Bit 4: Predictable termination
        // Bit 5: Segmentation symbols
        // Bit 6: HT block coding (1 = HTJ2K, 0 = legacy EBCOT)
        var codeBlockStyle: UInt8 = 0
        if config.useHTJ2K {
            codeBlockStyle |= 0x40 // Set bit 6 for HTJ2K mode
        }
        segment.writeUInt8(codeBlockStyle)

        // Wavelet transform type (0 = 9/7 irreversible, 1 = 5/3 reversible)
        segment.writeUInt8(config.useReversibleFilter ? 1 : 0)

        writer.writeMarkerSegment(J2KMarker.cod.rawValue, segmentData: segment.data)
    }

    /// Writes the COC marker segment (Coding Style Component).
    ///
    /// The COC marker allows per-component coding parameters that override
    /// the default COD parameters for a specific component. This is optional
    /// and only written when component-specific parameters are needed.
    ///
    /// - Parameters:
    ///   - writer: The bit writer to write to.
    ///   - componentIndex: The component index (0-based).
    ///   - componentCount: Total number of components.
    private func writeCOCMarker(
        _ writer: inout J2KBitWriter,
        componentIndex: Int,
        componentCount: Int
    ) throws {
        var segment = J2KBitWriter()

        // Ccoc — Component index
        if componentCount < 257 {
            // 1 byte for component index if < 257 components
            segment.writeUInt8(UInt8(componentIndex))
        } else {
            // 2 bytes for component index if >= 257 components
            segment.writeUInt16(UInt16(componentIndex))
        }

        // Scoc — Coding style for this component
        // Same structure as COD's SPcod

        // Number of decomposition levels
        segment.writeUInt8(UInt8(config.decompositionLevels))

        // Code-block width exponent (offset by 2)
        let cbWidthExp = Int(log2(Double(config.codeBlockSize.width)))
        segment.writeUInt8(UInt8(cbWidthExp - 2))

        // Code-block height exponent (offset by 2)
        let cbHeightExp = Int(log2(Double(config.codeBlockSize.height)))
        segment.writeUInt8(UInt8(cbHeightExp - 2))

        // Code-block style (with HT bit if HTJ2K is enabled)
        var codeBlockStyle: UInt8 = 0
        if config.useHTJ2K {
            codeBlockStyle |= 0x40 // Set bit 6 for HTJ2K mode
        }
        segment.writeUInt8(codeBlockStyle)

        // Wavelet transform type (0 = 9/7 irreversible, 1 = 5/3 reversible)
        segment.writeUInt8(config.useReversibleFilter ? 1 : 0)

        // HT set parameters (ISO/IEC 15444-15) — only when HTJ2K is enabled
        if config.useHTJ2K {
            // For HT set A (default), write the HT set configuration byte
            // Bits 0-3: Reserved (set to 0)
            // Bit 4: Lossless flag (0 = lossy, 1 = lossless)
            // Bits 5-7: Reserved (set to 0)
            var htSetConfig: UInt8 = 0
            if config.lossless {
                htSetConfig |= 0x10 // Set bit 4 for lossless mode
            }
            segment.writeUInt8(htSetConfig)
        }

        writer.writeMarkerSegment(J2KMarker.coc.rawValue, segmentData: segment.data)
    }

    /// Writes the QCD marker segment (Quantization Default).
    private func writeQCDMarker(_ writer: inout J2KBitWriter, image: J2KImage, decompositionLevels: Int) throws {
        var segment = J2KBitWriter()

        // Sqcd byte layout: guard bits (bits 5-7) | quantization style (bits 0-4)
        // Use extended guard bits from Part 2 configuration if applicable
        let quantExt = J2KPart2QuantizationExtensions(configuration: config)

        if config.useReversibleFilter {
            // No quantization (style = 0) for reversible transforms
            let sqcd = quantExt.encodeSqcd(quantizationStyle: 0x00)
            segment.writeUInt8(sqcd)

            // SPqcd: Exponent values for each subband
            // Per JPEG 2000 (ISO 15444-1 Table E.1), for the reversible 5/3 filter:
            //   epsilon_b = R_I + G_b  where R_I = bit depth, G_b = subband gain exponent
            //   LL: G=0, HL/LH: G=1, HH: G=2
            let bitDepth = image.components.first?.bitDepth ?? 8

            // LL subband at coarsest level
            let epsilonLL = UInt8(bitDepth)
            segment.writeUInt8(epsilonLL << 3) // Exponent in bits 3-7

            // Detail subbands (HL, LH, HH) at each level (from coarsest to finest)
            for _ in 0..<decompositionLevels {
                let epsilonHL = UInt8(bitDepth + 1) // G_HL = 1
                let epsilonLH = UInt8(bitDepth + 1) // G_LH = 1
                let epsilonHH = UInt8(bitDepth + 2) // G_HH = 2
                segment.writeUInt8(epsilonHL << 3)
                segment.writeUInt8(epsilonLH << 3)
                segment.writeUInt8(epsilonHH << 3)
            }
        } else {
            // Scalar expounded quantization (style = 2) for lossy transforms
            let sqcd = quantExt.encodeSqcd(quantizationStyle: 0x02)
            segment.writeUInt8(sqcd)

            // Compute step sizes using the SAME parameters as the actual quantizer
            // in Stage 4 (applyQuantization), so the QCD marker matches encoding.
            let params: J2KQuantizationParameters = .fromQuality(config.quality)
            let bitDepth = image.components.first?.bitDepth ?? 8
            let guardBits = Int(quantExt.extendedGuardBits) // Must match Sqcd guard bits
            // R_b = image bit depth + subband gain (ISO 15444-1 Eq. E.4)
            // Guard bits are NOT part of R_b — they only affect M_b (Eq. E.2)
            // Subband gain G_b: LL=0, HL/LH=1, HH=2
            let baseRangeBits = bitDepth

            // SPqcd: Step size values for each subband (2 bytes each)
            // Per ISO 15444-1 Eq. E.3:
            //   Δ_b = 2^(R_b - ε_b) × (1 + μ_b / 2^11)
            // We solve for (ε_b, μ_b) given the actual step Δ_b:
            //   ε_b = R_b - floor(log2(Δ_b))
            //   μ_b = round((Δ_b / 2^(R_b - ε_b) - 1) × 2^11)

            // LL subband (quantizer uses decompositionLevel=0 for LL, gain=0)
            let llStep = J2KStepSizeCalculator.calculateStepSize(
                baseStepSize: params.baseStepSize,
                subband: .ll,
                decompositionLevel: 0,
                totalLevels: decompositionLevels,
                reversible: false
            )
            let llRangeBits = baseRangeBits + 0 // G_LL = 0
            let (llExp, llMant) = Self.encodeJ2KStepSize(llStep, rangeBits: llRangeBits)
            segment.writeUInt16(UInt16((llExp & 0x1F) << 11 | (llMant & 0x7FF)))

            // Detail subbands: QCD lists from coarsest to finest.
            // In the encoder, the quantizer uses decompositionLevel = decomLevel
            // where decomLevel=1 is finest detail and decomLevel=NL is coarsest.
            // QCD order: coarsest first → iterate NL down to 1.
            if decompositionLevels > 0 {
                for level in (1...decompositionLevels).reversed() {
                    for subband in [J2KSubband.hl, .lh, .hh] {
                        let step = J2KStepSizeCalculator.calculateStepSize(
                            baseStepSize: params.baseStepSize,
                            subband: subband,
                            decompositionLevel: level,
                            totalLevels: decompositionLevels,
                            reversible: false
                        )
                        // Include subband gain in R_b as required by ISO 15444-1
                        // Eq. E.4: R_b = I + G_b where G_b is subband gain exponent.
                        // OpenJPEG's decoder uses gain=0 internally but compensates
                        // with adjusted DWT normalization (two_invK), so the net
                        // result is the same either way for OPJ decoding. Our own
                        // decoder expects the standard gains.
                        let subbandGain: Int
                        switch subband {
                        case .ll: subbandGain = 0
                        case .hl, .lh: subbandGain = 1
                        case .hh: subbandGain = 2
                        }
                        let rangeBits = baseRangeBits + subbandGain
                        let (exp, mant) = Self.encodeJ2KStepSize(step, rangeBits: rangeBits)
                        segment.writeUInt16(UInt16((exp & 0x1F) << 11 | (mant & 0x7FF)))
                    }
                }
            }
        }

        writer.writeMarkerSegment(J2KMarker.qcd.rawValue, segmentData: segment.data)
    }

    /// Writes the SOT marker segment (Start of Tile-part).
    private func writeSOTMarker(
        _ writer: inout J2KBitWriter, tileIndex: Int, tilePartLength: Int
    ) throws {
        var segment = J2KBitWriter()

        // Isot — Tile index
        segment.writeUInt16(UInt16(tileIndex))
        // Psot — Length of tile-part (includes SOT marker + segment + SOD + data)
        // SOT marker (2) + length (2) + segment (8) + SOD marker (2) + data
        let totalLength = 2 + 2 + 8 + 2 + tilePartLength
        segment.writeUInt32(UInt32(totalLength))
        // TPsot — Tile-part index (0 = first part)
        segment.writeUInt8(0)
        // TNsot — Number of tile-parts (1 = single part)
        segment.writeUInt8(1)

        writer.writeMarkerSegment(J2KMarker.sot.rawValue, segmentData: segment.data)
    }

    /// Applies rate control layer truncation to code blocks.
    ///
    /// For each code block, the quality layer specifies how many coding passes
    /// to include. Blocks not in the layer are excluded entirely. Blocks with
    /// fewer passes than encoded are truncated using per-pass byte boundaries.
    ///
    /// After PCRD layer truncation, a global rate envelope is applied to ensure
    /// the total output does not exceed the target bitrate derived from the
    /// quality parameter.
    private func applyLayerTruncation(
        codeBlocks: [J2KCodeBlock], layers: [QualityLayer]
    ) -> [J2KCodeBlock] {
        // Fast path: lossless mode — all passes are included, no truncation needed.
        if config.lossless {
            return codeBlocks
        }

        // Step 1: Apply PCRD layer truncation if available.
        // Merge contributions from ALL layers — each layer's contributions
        // only contains blocks updated in that layer, so we need to take
        // the maximum pass count across all layers for each block.
        var truncated: [J2KCodeBlock]
        var mergedContributions = [Int: Int]()
        for layer in layers {
            for (blockIdx, passes) in layer.codeBlockContributions {
                mergedContributions[blockIdx] = max(
                    mergedContributions[blockIdx] ?? 0, passes
                )
            }
        }
        if !mergedContributions.isEmpty {
            // Cache environment check outside hot loop
            let dumpPasses = ProcessInfo.processInfo.environment["J2K_DUMP_PASSES"] != nil
            truncated = codeBlocks.map { block in
                let maxPasses = mergedContributions[block.index]
                if dumpPasses {
                    print("TRUNCATION: block=\(block.index) passes=\(block.passeCount) layer_maxPasses=\(String(describing: maxPasses)) data=\(block.data.count)")
                }
                // Blocks not selected by PCRD should contribute zero data
                guard let maxPasses = maxPasses, maxPasses > 0 else {
                    return J2KCodeBlock(
                        index: block.index,
                        x: block.x, y: block.y,
                        width: block.width, height: block.height,
                        subband: block.subband,
                        componentIndex: block.componentIndex,
                        resolutionLevel: block.resolutionLevel,
                        data: Data(),
                        passeCount: 0,
                        zeroBitPlanes: block.zeroBitPlanes
                    )
                }
                // If PCRD assigned all passes, no truncation needed
                guard maxPasses < block.passeCount,
                      block.passeCount > 0 else {
                    return block
                }

                // Reconstruct the properly terminated data at the truncation
                // point. Prefer lightweight checkpoint reconstruction (O(1)
                // per block) over stored snapshot data.
                let truncatedData: Data
                if !block.mqCheckpoints.isEmpty && maxPasses <= block.mqCheckpoints.count {
                    // Reconstruct from checkpoint + shared raw MQ output
                    let cp = block.mqCheckpoints[maxPasses - 1]
                    truncatedData = MQEncoder.reconstructFromCheckpoint(cp, rawOutput: block.rawMQOutput)
                } else if !block.perPassSnapshotData.isEmpty && maxPasses <= block.perPassSnapshotData.count {
                    truncatedData = block.perPassSnapshotData[maxPasses - 1]
                } else {
                    let truncatedLength: Int
                    if !block.cumulativePassBytes.isEmpty && maxPasses <= block.cumulativePassBytes.count {
                        truncatedLength = min(block.cumulativePassBytes[maxPasses - 1], block.data.count)
                    } else if !block.passSegmentLengths.isEmpty && maxPasses <= block.passSegmentLengths.count {
                        truncatedLength = block.passSegmentLengths.prefix(maxPasses).reduce(0, +)
                    } else {
                        truncatedLength = Int(Double(block.data.count) * Double(maxPasses) / Double(block.passeCount))
                    }
                    let safeLength = min(max(0, truncatedLength), block.data.count)
                    truncatedData = block.data.prefix(safeLength)
                }

                return J2KCodeBlock(
                    index: block.index,
                    x: block.x, y: block.y,
                    width: block.width, height: block.height,
                    subband: block.subband,
                    componentIndex: block.componentIndex,
                    resolutionLevel: block.resolutionLevel,
                    data: truncatedData,
                    passeCount: maxPasses,
                    zeroBitPlanes: block.zeroBitPlanes,
                    passSegmentLengths: block.passSegmentLengths.isEmpty
                        ? [] : Array(block.passSegmentLengths.prefix(maxPasses)),
                    cumulativePassBytes: block.cumulativePassBytes.isEmpty
                        ? [] : Array(block.cumulativePassBytes.prefix(maxPasses))
                )
            }
        } else {
            truncated = codeBlocks
        }

        // Step 2: Global rate envelope — only apply when PCRD layer truncation
        // was NOT applied. When PCRD has already optimized the allocation,
        // a secondary heuristic truncation degrades quality.
        if !config.lossless, case .constantQuality = config.bitrateMode,
           mergedContributions.isEmpty {
            let quality = config.quality
            guard quality < 1.0 else { return truncated }

            // Target bits per pixel: quadratic mapping matching J2KRateControl
            let bpp = 0.1 + 7.9 * pow(quality, 1.5)
            // bpp already accounts for all components. Estimate spatial
            // pixel count by dividing total code block samples by components.
            let componentCount = max(1, Set(truncated.map { $0.componentIndex }).count)
            let codeBlockPixels = truncated.reduce(0) { $0 + $1.width * $1.height }
            let imagePixels = codeBlockPixels / componentCount
            let targetBytes = Int(bpp * Double(imagePixels) / 8.0)
            let actualBytes = truncated.reduce(0) { $0 + $1.data.count }

            guard actualBytes > targetBytes, targetBytes > 0 else { return truncated }

            // Resolution-aware truncation: distribute truncation more
            // uniformly across resolution levels. LL (res 0) gets light
            // protection but NOT full immunity, while higher-frequency
            // subbands get proportionally more truncation.
            // This prevents the previous issue of destroying all edge detail
            // while leaving LL completely untouched.
            let maxRes = truncated.map { $0.resolutionLevel }.max() ?? 0
            let bytesToRemove = actualBytes - targetBytes

            // Calculate how much each resolution level contributes
            struct ResInfo {
                var bytes: Int = 0
                var weight: Double = 0.0  // truncation aggressiveness
            }
            var resInfos = [Int: ResInfo]()
            for block in truncated where block.data.count > 0 {
                let res = block.resolutionLevel
                resInfos[res, default: ResInfo()].bytes += block.data.count
                // Uniform truncation weight with mild LL protection:
                // LL (res 0) = 0.3, mid res = 0.6-0.8, highest res = 1.0
                // This distributes truncation more evenly for better quality
                resInfos[res, default: ResInfo()].weight = maxRes > 0
                    ? 0.3 + 0.7 * Double(res) / Double(maxRes) : 1.0
            }

            // Compute weighted total for distributing truncation
            let weightedTotal = resInfos.reduce(0.0) { $0 + $1.value.weight * Double($1.value.bytes) }
            guard weightedTotal > 0 else { return truncated }

            // Per-resolution truncation ratio
            var resTruncRatio = [Int: Double]()
            for (res, info) in resInfos {
                let share = info.weight * Double(info.bytes) / weightedTotal
                let bytesFromThisRes = Double(bytesToRemove) * share
                resTruncRatio[res] = max(0.0, 1.0 - bytesFromThisRes / Double(info.bytes))
            }

            truncated = truncated.map { block in
                guard block.data.count > 0, block.passeCount > 0 else { return block }

                let ratio = resTruncRatio[block.resolutionLevel] ?? 1.0
                guard ratio < 1.0 else { return block }

                // Determine truncated pass count and data length
                let newPasses = max(1, Int(ceil(Double(block.passeCount) * ratio)))
                let newLength: Int
                if !block.cumulativePassBytes.isEmpty && newPasses <= block.cumulativePassBytes.count {
                    newLength = min(block.cumulativePassBytes[newPasses - 1], block.data.count)
                } else {
                    newLength = max(1, Int(Double(block.data.count) * ratio))
                }
                let safeLength = min(newLength, block.data.count)

                return J2KCodeBlock(
                    index: block.index,
                    x: block.x, y: block.y,
                    width: block.width, height: block.height,
                    subband: block.subband,
                    componentIndex: block.componentIndex,
                    resolutionLevel: block.resolutionLevel,
                    data: block.data.prefix(safeLength),
                    passeCount: min(newPasses, block.passeCount),
                    zeroBitPlanes: block.zeroBitPlanes,
                    passSegmentLengths: block.passSegmentLengths.isEmpty
                        ? [] : Array(block.passSegmentLengths.prefix(newPasses)),
                    cumulativePassBytes: block.cumulativePassBytes.isEmpty
                        ? [] : Array(block.cumulativePassBytes.prefix(newPasses))
                )
            }
        }

        return truncated
    }

    /// Generates the tile bitstream data from code blocks and layers.
    ///
    /// Uses LRCP progression: Layer → Resolution → Component → Precinct.
    /// Each packet uses raw bit packet headers per ISO/IEC 15444-1 Annex B.
    private func generateTileData(
        codeBlocks: [J2KCodeBlock], layers: [QualityLayer],
        decompositionLevels: Int, componentCount: Int
    ) throws -> Data {
        let profiling = ProcessInfo.processInfo.environment["J2K_PROFILE"] != nil
        // Pre-size data buffer based on total code block data
        let totalBlockBytes = codeBlocks.reduce(0) { $0 + $1.data.count }
        var data = Data()
        data.reserveCapacity(totalBlockBytes + totalBlockBytes / 8 + 1024)

        // Apply rate control truncation: truncate code blocks per the quality layer
        var truncStart: CFAbsoluteTime = 0
        if profiling { truncStart = CFAbsoluteTimeGetCurrent() }
        let effectiveBlocks = applyLayerTruncation(codeBlocks: codeBlocks, layers: layers)
        if profiling {
            let t = CFAbsoluteTimeGetCurrent()
            print("      PROFILE truncation: \(String(format: "%.4f", t - truncStart))s")
        }

        // Group code blocks by (resolutionLevel, componentIndex, subband)
        struct BandKey: Hashable {
            let res: Int; let comp: Int; let subband: J2KSubband
        }
        var blocksByBand: [BandKey: [J2KCodeBlock]] = [:]
        for block in effectiveBlocks {
            let key = BandKey(res: block.resolutionLevel, comp: block.componentIndex, subband: block.subband)
            blocksByBand[key, default: []].append(block)
        }

        // Use actual decomposition levels and component count from the pipeline,
        // not from code blocks, to ensure every expected packet is emitted even
        // when subbands contain all-zero code blocks.
        let numResolutions = decompositionLevels + 1
        let numComponents = componentCount
        let cbWidth = config.codeBlockSize.width
        let cbHeight = config.codeBlockSize.height

        // LRCP: 1 layer, iterate Resolution → Component
        for resLevel in 0..<numResolutions {
            for compIdx in 0..<numComponents {
                // Sub-bands for this resolution
                let subbands: [J2KSubband] = resLevel == 0 ? [.ll] : [.hl, .lh, .hh]

                var bandBlocksList: [[J2KCodeBlock]] = []
                for sb in subbands {
                    let key = BandKey(res: resLevel, comp: compIdx, subband: sb)
                    bandBlocksList.append(blocksByBand[key] ?? [])
                }

                let packetData = try encodePacket(
                    bandBlocks: bandBlocksList,
                    codeBlockWidth: cbWidth,
                    codeBlockHeight: cbHeight
                )
                data.append(packetData)
            }
        }

        return data
    }

    /// Encodes a single JPEG 2000 packet with ISO/IEC 15444-1 compliant packet header.
    ///
    /// Per ISO/IEC 15444-1 Annex B.10, inclusion and zero bit-plane information
    /// are encoded using tag trees. Code-block order within each band follows
    /// raster (row-major) scan order.
    ///
    /// - Parameters:
    ///   - bandBlocks: Array of code-block arrays, one per sub-band.
    ///   - codeBlockWidth: Nominal code-block width.
    ///   - codeBlockHeight: Nominal code-block height.
    private func encodePacket(
        bandBlocks: [[J2KCodeBlock]],
        codeBlockWidth: Int,
        codeBlockHeight: Int
    ) throws -> Data {
        var writer = J2KBitWriter()
        // Enable JPEG 2000 byte stuffing for packet headers (ISO 15444-1 B.10.1)
        writer.setByteStuffing(true)

        // Check if any code block across all bands has data
        let anyIncluded = bandBlocks.contains { band in
            band.contains { !$0.data.isEmpty && $0.passeCount > 0 }
        }

        if !anyIncluded {
            writer.writeBit(false) // empty packet
            writer.alignToByte()
            return writer.data
        }

        // Non-empty packet
        writer.writeBit(true)

        // Collect included blocks in band order for appending data later
        var allIncludedBlocks: [J2KCodeBlock] = []

        // Process each band completely before moving to next
        for band in bandBlocks {
            guard !band.isEmpty else { continue }

            // Compute code-block grid dimensions for this band
            let blocksX = band.map { $0.x / codeBlockWidth }.max()! + 1
            let blocksY = band.map { $0.y / codeBlockHeight }.max()! + 1

            // Create inclusion tag tree: value = 0 (included at layer 0), 999 (not included)
            var inclusionTree = J2KTagTree(width: blocksX, height: blocksY)
            // Create zero bit-plane tag tree
            var zbpTree = J2KTagTree(width: blocksX, height: blocksY)

            // Set tag tree values
            for (idx, block) in band.enumerated() {
                let included = !block.data.isEmpty && block.passeCount > 0
                inclusionTree.setValue(leafIndex: idx, value: included ? 0 : 999)
                zbpTree.setValue(leafIndex: idx, value: Int32(block.zeroBitPlanes))
            }

            // Encode each code-block in raster order
            for (idx, block) in band.enumerated() {
                let included = !block.data.isEmpty && block.passeCount > 0

                // 1. Inclusion: tag tree encode for layer 0 (threshold = 1)
                inclusionTree.encode(writer: &writer, leafIndex: idx, threshold: 1)

                guard included else { continue }

                // 2. Zero bit-planes: tag tree encode (encode exact value P)
                zbpTree.encode(writer: &writer, leafIndex: idx, threshold: Int32(block.zeroBitPlanes) + 1)

                // 3. Number of coding passes per ISO 15444-1 Table B.4
                let passes = block.passeCount
                if passes == 1 {
                    // 0
                    writer.writeBit(false)
                } else if passes == 2 {
                    // 10
                    writer.writeBit(true); writer.writeBit(false)
                } else if passes <= 5 {
                    // 11 + 2-bit value (passes - 3)
                    writer.writeBit(true); writer.writeBit(true)
                    let val = passes - 3
                    writer.writeBit(val & 0x02 != 0)
                    writer.writeBit(val & 0x01 != 0)
                } else if passes <= 36 {
                    // 1111 + 5-bit value (passes - 6) per ISO 15444-1 Table B.4
                    writer.writeBit(true); writer.writeBit(true)
                    writer.writeBit(true); writer.writeBit(true)
                    try writer.writeBits(UInt32(passes - 6), count: 5)
                } else {
                    // 1111 + 11111 + 7-bit value (passes - 37) per ISO 15444-1 Table B.4
                    writer.writeBit(true); writer.writeBit(true)
                    writer.writeBit(true); writer.writeBit(true)
                    try writer.writeBits(31, count: 5)
                    try writer.writeBits(UInt32(passes - 37), count: 7)
                }

                // 4. Data length per ISO 15444-1 B.10.7
                // Total bits = Lblock + floor(log2(numpasses))
                let length = block.data.count
                let passLog = passes > 1 ? (Int.bitWidth - passes.leadingZeroBitCount - 1) : 0
                var lblock = 3
                var totalBits = lblock + passLog
                let bitsNeeded = length > 0 ? (Int.bitWidth - length.leadingZeroBitCount) : 1
                while totalBits < bitsNeeded {
                    writer.writeBit(true)
                    lblock += 1
                    totalBits = lblock + passLog
                }
                writer.writeBit(false)
                if totalBits > 0 {
                    try writer.writeBits(UInt32(length), count: totalBits)
                }
                allIncludedBlocks.append(block)
            }
        }

        // Pad to byte boundary
        writer.alignToByte()

        var packetData = writer.data

        // Append code-block bitstream data in band order
        for block in allIncludedBlocks {
            packetData.append(block.data)
        }

        return packetData
    }

    // MARK: - Progress Reporting

    private func reportProgress(
        _ callback: ((EncoderProgressUpdate) -> Void)?,
        stage: EncodingStage,
        stageProgress: Double
    ) {
        guard let callback = callback else { return }
        let stages = EncodingStage.allCases
        guard let stageIndex = stages.firstIndex(of: stage) else { return }
        let stageWeight = 1.0 / Double(stages.count)
        let overall = Double(stageIndex) * stageWeight + stageProgress * stageWeight
        callback(EncoderProgressUpdate(
            stage: stage,
            progress: stageProgress,
            overallProgress: min(overall, 1.0)
        ))
    }

    // MARK: - JPEG 2000 Step Size Encoding

    /// Encodes a quantization step size as a JPEG 2000 (ε_b, μ_b) pair.
    ///
    /// Per ISO/IEC 15444-1 Eq. E.3, the decoder reconstructs the step as:
    /// ```
    ///   Δ_b = 2^(R_b - ε_b) × (1 + μ_b / 2^11)
    /// ```
    /// Given the actual step `Δ_b` and `R_b` (rangeBits = bitDepth + guardBits),
    /// we solve:
    /// ```
    ///   ε_b = R_b - floor(log2(Δ_b))
    ///   μ_b = round((Δ_b / 2^(R_b - ε_b) - 1) × 2048)
    /// ```
    ///
    /// - Parameters:
    ///   - step: The actual quantization step size used during encoding.
    ///   - rangeBits: R_b = image bit depth + guard bits.
    /// - Returns: Tuple of (exponent, mantissa) for the QCD marker.
    static func encodeJ2KStepSize(_ step: Double, rangeBits: Int) -> (exponent: Int, mantissa: Int) {
        guard step > 0 else { return (0, 0) }

        // floor(log2(step)) gives the power-of-2 part
        let log2Step = Foundation.log2(step)
        let floorLog2 = Int(Foundation.floor(log2Step))

        // ε_b = R_b - floorLog2
        let exponent = rangeBits - floorLog2
        let clampedExponent = max(0, min(31, exponent))

        // Reconstruct what 2^(R_b - ε_b) would be with clamped exponent
        let basePow = Foundation.pow(2.0, Double(rangeBits - clampedExponent))

        // μ_b = round((step / basePow - 1) × 2048)
        let mantissa: Int
        if basePow > 0 {
            let normalized = step / basePow
            mantissa = max(0, min(2047, Int((normalized - 1.0) * 2048.0 + 0.5)))
        } else {
            mantissa = 0
        }

        return (clampedExponent, mantissa)
    }
}

// MARK: - vDSP-Accelerated Type Conversions

/// Vectorised type conversion helpers using Accelerate/vDSP when available.
///
/// These replace scalar `map { Float($0) }` / `map { Int32($0) }` conversions
/// with vDSP vector operations that are 2–4× faster for large arrays.
/// Falls back to scalar conversion on non-Apple platforms.
enum vDSPConvert: Sendable {
    /// Converts `[Int32]` to `[Float]` using vDSP.
    @inline(__always)
    static func int32sToFloats(_ input: [Int32]) -> [Float] {
        #if canImport(Accelerate)
        var output = [Float](repeating: 0, count: input.count)
        input.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                vDSP_vflt32(
                    UnsafePointer<Int32>(src.baseAddress!), 1,
                    dst.baseAddress!, 1,
                    vDSP_Length(input.count)
                )
            }
        }
        return output
        #else
        return input.map { Float($0) }
        #endif
    }

    /// Converts `[Double]` to `[Float]` using vDSP.
    @inline(__always)
    static func doublesToFloats(_ input: [Double]) -> [Float] {
        #if canImport(Accelerate)
        var output = [Float](repeating: 0, count: input.count)
        input.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                vDSP_vdpsp(src.baseAddress!, 1, dst.baseAddress!, 1, vDSP_Length(input.count))
            }
        }
        return output
        #else
        return input.map { Float($0) }
        #endif
    }

    /// Converts `[Float]` to `[Double]` using vDSP.
    @inline(__always)
    static func floatsToDoubles(_ input: [Float]) -> [Double] {
        #if canImport(Accelerate)
        var output = [Double](repeating: 0, count: input.count)
        input.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                vDSP_vspdp(src.baseAddress!, 1, dst.baseAddress!, 1, vDSP_Length(input.count))
            }
        }
        return output
        #else
        return input.map { Double($0) }
        #endif
    }

    /// Converts `[Float]` to `[Int32]` with rounding using vDSP.
    @inline(__always)
    static func floatsToInt32s(_ input: [Float]) -> [Int32] {
        #if canImport(Accelerate)
        var output = [Int32](repeating: 0, count: input.count)
        input.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                vDSP_vfixr32(src.baseAddress!, 1, dst.baseAddress!, 1, vDSP_Length(input.count))
            }
        }
        return output
        #else
        return input.map { Int32($0.rounded()) }
        #endif
    }

    /// Converts `[Int32]` to `[Double]` using vDSP.
    @inline(__always)
    static func int32sToDoubles(_ input: [Int32]) -> [Double] {
        #if canImport(Accelerate)
        var output = [Double](repeating: 0, count: input.count)
        input.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                vDSP_vflt32D(
                    UnsafePointer<Int32>(src.baseAddress!), 1,
                    dst.baseAddress!, 1,
                    vDSP_Length(input.count)
                )
            }
        }
        return output
        #else
        return input.map { Double($0) }
        #endif
    }

    /// Converts `[Double]` to `[Int32]` with rounding using vDSP.
    @inline(__always)
    static func doublesToInt32s(_ input: [Double]) -> [Int32] {
        #if canImport(Accelerate)
        var output = [Int32](repeating: 0, count: input.count)
        input.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                vDSP_vfixr32D(src.baseAddress!, 1, dst.baseAddress!, 1, vDSP_Length(input.count))
            }
        }
        return output
        #else
        return input.map { Int32($0.rounded()) }
        #endif
    }
}
