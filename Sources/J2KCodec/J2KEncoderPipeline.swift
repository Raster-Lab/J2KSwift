// J2KEncoderPipeline.swift
// J2KSwift
//
// Encoder pipeline implementation for JPEG 2000 encoding.
//

import Foundation
import J2KCore

// MARK: - Encoding Stage

/// Represents the stages of the JPEG 2000 encoding pipeline.
public enum EncodingStage: String, Sendable, CaseIterable {
    /// Input validation and preprocessing.
    case preprocessing = "Preprocessing"

    /// Color space transformation (RCT or ICT).
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
/// This class uses `@unchecked Sendable` because it manually synchronizes access
/// to mutable state using `NSLock`. All methods acquire the lock before
/// accessing or modifying the internal results array.
final class ParallelResultCollector<T>: @unchecked Sendable {
    private var _results: [T]
    private var _firstError: (any Error)?
    private let lock = NSLock()

    init(capacity: Int = 0) {
        _results = []
        _results.reserveCapacity(capacity)
    }

    func append(contentsOf elements: [T]) {
        lock.lock()
        _results.append(contentsOf: elements)
        lock.unlock()
    }

    func recordError(_ error: any Error) {
        lock.lock()
        if _firstError == nil {
            _firstError = error
        }
        lock.unlock()
    }

    var results: [T] {
        lock.lock()
        defer { lock.unlock() }
        return _results
    }

    var firstError: (any Error)? {
        lock.lock()
        defer { lock.unlock() }
        return _firstError
    }
}

// MARK: - Encoder Pipeline

/// Internal encoding pipeline that connects all JPEG 2000 encoding components.
///
/// The pipeline processes an image through these stages:
/// 1. Preprocessing — validate input, extract component data
/// 2. Color Transform — apply RCT (lossless) or ICT (lossy)
/// 3. Wavelet Transform — multi-level 2D DWT decomposition
/// 4. Quantization — convert coefficients to integer indices
/// 5. Entropy Coding — EBCOT bit-plane coding per code block
/// 6. Rate Control — quality layer formation
/// 7. Codestream Generation — write JPEG 2000 markers and data
struct EncoderPipeline: Sendable {
    let config: J2KEncodingConfiguration

    init(config: J2KEncodingConfiguration) {
        self.config = config
    }

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
        try image.validate()

        // Stage 1: Preprocessing — extract component data as Int32 arrays
        reportProgress(progress, stage: .preprocessing, stageProgress: 0.0)
        let componentData = try extractComponentData(from: image)
        reportProgress(progress, stage: .preprocessing, stageProgress: 1.0)

        // Stage 2: Color Transform
        reportProgress(progress, stage: .colorTransform, stageProgress: 0.0)
        let transformedData = try applyColorTransform(componentData, image: image)
        reportProgress(progress, stage: .colorTransform, stageProgress: 1.0)

        // Stage 3: Wavelet Transform
        reportProgress(progress, stage: .waveletTransform, stageProgress: 0.0)
        let decompositions = try applyWaveletTransform(
            transformedData, width: image.width, height: image.height
        )
        reportProgress(progress, stage: .waveletTransform, stageProgress: 1.0)

        // Stage 4: Quantization
        reportProgress(progress, stage: .quantization, stageProgress: 0.0)
        let quantizedSubbands = try applyQuantization(decompositions)
        reportProgress(progress, stage: .quantization, stageProgress: 1.0)

        // Stage 5: Entropy Coding
        reportProgress(progress, stage: .entropyCoding, stageProgress: 0.0)
        let codeBlocks = try applyEntropyCoding(quantizedSubbands)
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
            image: image, codeBlocks: codeBlocks, layers: layers
        )
        reportProgress(progress, stage: .codestreamGeneration, stageProgress: 1.0)

        return codestream
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

    // MARK: - Stage 2: Color Transform
    
    /// Applies color space transformation (RCT/ICT or Part 2 MCT).
    private func applyColorTransform(
        _ components: [[Int32]], image: J2KImage
    ) throws -> [[Int32]] {
        // Check if MCT is enabled in configuration
        switch config.mctConfiguration.mode {
        case .disabled:
            // Use standard Part 1 color transform
            return try applyStandardColorTransform(components, image: image)
            
        case .arrayBased(let matrix):
            // Use array-based MCT with specified matrix
            return try applyArrayBasedMCT(components, matrix: matrix, image: image)
            
        case .dependency(let depConfig):
            // Use dependency-based MCT
            return try applyDependencyMCT(components, configuration: depConfig, image: image)
            
        case .adaptive(let candidates, let criteria):
            // Select best matrix adaptively based on criteria
            return try applyAdaptiveMCT(components, candidates: candidates, criteria: criteria, image: image)
        }
    }
    
    /// Applies standard Part 1 color transform (RCT/ICT).
    private func applyStandardColorTransform(
        _ components: [[Int32]], image: J2KImage
    ) throws -> [[Int32]] {
        // Color transform only applies to 3+ component images
        guard components.count >= 3 else { return components }

        let mode: J2KColorTransformMode = config.lossless ? .reversible : .irreversible
        let ctConfig = J2KColorTransformConfiguration(mode: mode)
        let transform = J2KColorTransform(configuration: ctConfig)

        let (y, cb, cr) = try transform.forwardRCT(
            red: components[0], green: components[1], blue: components[2]
        )

        var result = [y, cb, cr]
        // Preserve any additional components (alpha, etc.) unchanged
        if components.count > 3 {
            result.append(contentsOf: components[3...])
        }
        return result
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
        image: J2KImage
    ) throws -> [[Int32]] {
        // For now, use a simple heuristic: correlation-based selection
        // In a full implementation, this would evaluate each candidate matrix
        // and select based on the specified criteria
        
        // Default to first candidate if available
        guard let selectedMatrix = candidates.first else {
            // Fall back to standard transform
            return try applyStandardColorTransform(components, image: image)
        }
        
        // Apply the selected matrix
        return try applyArrayBasedMCT(components, matrix: selectedMatrix, image: image)
    }

    // MARK: - Stage 3: Wavelet Transform

    /// Information about a subband within a decomposition.
    struct SubbandInfo: Sendable {
        let componentIndex: Int
        let level: Int
        let subband: J2KSubband
        let coefficients: [Int32]
        let width: Int
        let height: Int
    }

    /// Applies the forward wavelet transform to all components.
    private func applyWaveletTransform(
        _ components: [[Int32]], width: Int, height: Int
    ) throws -> [[SubbandInfo]] {
        // Select filter based on wavelet kernel configuration
        let filter: J2KDWT1D.Filter
        switch config.waveletKernelConfiguration {
        case .standard:
            // Use standard Part 1 wavelets
            filter = config.lossless ? .reversible53 : .irreversible97
        case .arbitrary(let kernel):
            // Use arbitrary kernel for all components
            filter = kernel.toDWTFilter()
        case .perTileComponent:
            // Per-tile-component selection handled below
            filter = config.lossless ? .reversible53 : .irreversible97
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
                    componentFilter = config.lossless ? .reversible53 : .irreversible97
                }
            } else {
                componentFilter = filter
            }

            // Convert 1D array to 2D for DWT (optimized version)
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
                    width: width,
                    height: height
                )]
                allSubbands.append(subbands)
                continue
            }

            let decomposition = try J2KDWT2D.forwardDecomposition(
                image: image2D, levels: levels, filter: componentFilter
            )

            var subbands: [SubbandInfo] = []

            // Collect subbands from each decomposition level
            for levelIdx in 0..<decomposition.levelCount {
                let level = decomposition.levels[levelIdx]
                let decomLevel = levelIdx + 1

                subbands.append(SubbandInfo(
                    componentIndex: compIdx,
                    level: decomLevel,
                    subband: .hl,
                    coefficients: level.hl.flatMap { $0 },
                    width: level.hl.isEmpty ? 0 : level.hl[0].count,
                    height: level.hl.count
                ))
                subbands.append(SubbandInfo(
                    componentIndex: compIdx,
                    level: decomLevel,
                    subband: .lh,
                    coefficients: level.lh.flatMap { $0 },
                    width: level.lh.isEmpty ? 0 : level.lh[0].count,
                    height: level.lh.count
                ))
                subbands.append(SubbandInfo(
                    componentIndex: compIdx,
                    level: decomLevel,
                    subband: .hh,
                    coefficients: level.hh.flatMap { $0 },
                    width: level.hh.isEmpty ? 0 : level.hh[0].count,
                    height: level.hh.count
                ))
            }

            // Add the coarsest LL subband
            let coarsestLL = decomposition.coarsestLL
            subbands.insert(SubbandInfo(
                componentIndex: compIdx,
                level: 0,
                subband: .ll,
                coefficients: coarsestLL.flatMap { $0 },
                width: coarsestLL.isEmpty ? 0 : coarsestLL[0].count,
                height: coarsestLL.count
            ), at: 0)

            allSubbands.append(subbands)
        }

        return allSubbands
    }

    // MARK: - Stage 4: Quantization

    /// Applies quantization to all subbands.
    private func applyQuantization(
        _ componentSubbands: [[SubbandInfo]]
    ) throws -> [[SubbandInfo]] {
        let params: J2KQuantizationParameters = config.lossless
            ? .lossless
            : .fromQuality(config.quality)
        let quantizer = J2KQuantizer(parameters: params)

        var result: [[SubbandInfo]] = []

        for subbands in componentSubbands {
            var quantizedSubbands: [SubbandInfo] = []
            for info in subbands {
                // Use Int32-optimized quantize method to avoid unnecessary conversions
                let quantized = try quantizer.quantize(
                    coefficients: info.coefficients,
                    subband: info.subband,
                    decompositionLevel: info.level,
                    totalLevels: config.decompositionLevels
                )
                quantizedSubbands.append(SubbandInfo(
                    componentIndex: info.componentIndex,
                    level: info.level,
                    subband: info.subband,
                    coefficients: quantized,
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
        let coefficients: [Int32]
        let bitDepth: Int
    }

    /// Applies EBCOT entropy coding to all subbands, producing code blocks.
    private func applyEntropyCoding(
        _ componentSubbands: [[SubbandInfo]]
    ) throws -> [J2KCodeBlock] {
        let cbWidth = config.codeBlockSize.width
        let cbHeight = config.codeBlockSize.height

        // First pass: collect all pending code-blocks with their metadata
        var pendingBlocks: [PendingCodeBlock] = []
        var blockIndex = 0

        for subbands in componentSubbands {
            for info in subbands {
                guard info.width > 0 && info.height > 0 else { continue }

                let blocksX = (info.width + cbWidth - 1) / cbWidth
                let blocksY = (info.height + cbHeight - 1) / cbHeight

                for by in 0..<blocksY {
                    for bx in 0..<blocksX {
                        let blockW = min(cbWidth, info.width - bx * cbWidth)
                        let blockH = min(cbHeight, info.height - by * cbHeight)

                        // Extract code block coefficients
                        var blockCoeffs: [Int32] = []
                        blockCoeffs.reserveCapacity(blockW * blockH)
                        for row in 0..<blockH {
                            let srcRow = by * cbHeight + row
                            let srcStart = srcRow * info.width + bx * cbWidth
                            let srcEnd = srcStart + blockW
                            blockCoeffs.append(contentsOf: info.coefficients[srcStart..<srcEnd])
                        }

                        // Determine bit depth from max coefficient magnitude (SIMD-optimized)
                        let maxMag = Self.maxAbsValue(blockCoeffs)
                        let bitDepth = maxMag > 0 ? Int(log2(Double(maxMag))) + 2 : 1

                        pendingBlocks.append(PendingCodeBlock(
                            index: blockIndex,
                            x: bx * cbWidth,
                            y: by * cbHeight,
                            width: blockW,
                            height: blockH,
                            subband: info.subband,
                            coefficients: blockCoeffs,
                            bitDepth: bitDepth
                        ))
                        blockIndex += 1
                    }
                }
            }
        }

        // Second pass: encode code-blocks (parallel or sequential)
        let useParallel = config.enableParallelCodeBlocks && pendingBlocks.count > 1
        let allCodeBlocks: [J2KCodeBlock]

        if useParallel {
            allCodeBlocks = try encodeCodeBlocksParallel(pendingBlocks)
        } else {
            allCodeBlocks = try encodeCodeBlocksSequential(pendingBlocks)
        }

        return allCodeBlocks
    }

    /// Encodes code-blocks sequentially.
    private func encodeCodeBlocksSequential(
        _ pendingBlocks: [PendingCodeBlock]
    ) throws -> [J2KCodeBlock] {
        let encoder = CodeBlockEncoder()
        var results: [J2KCodeBlock] = []
        results.reserveCapacity(pendingBlocks.count)

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
                data: codeBlock.data,
                passeCount: codeBlock.passeCount,
                zeroBitPlanes: codeBlock.zeroBitPlanes,
                passSegmentLengths: codeBlock.passSegmentLengths
            )

            results.append(codeBlock)
        }

        return results
    }

    /// Encodes code-blocks in parallel using structured concurrency.
    ///
    /// Each code-block is an independent unit of entropy coding with its own
    /// MQ encoder state and context models, making them safe to process in parallel.
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

        DispatchQueue.concurrentPerform(iterations: chunks.count) { chunkIdx in
            let chunk = chunks[chunkIdx]
            let encoder = CodeBlockEncoder()
            var localResults: [(Int, J2KCodeBlock)] = []
            localResults.reserveCapacity(chunk.count)

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
                        data: codeBlock.data,
                        passeCount: codeBlock.passeCount,
                        zeroBitPlanes: codeBlock.zeroBitPlanes,
                        passSegmentLengths: codeBlock.passSegmentLengths
                    )

                    localResults.append((pending.index, codeBlock))
                } catch {
                    collector.recordError(error)
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

        let rateConfig: RateControlConfiguration
        switch config.bitrateMode {
        case .constantBitrate(let bpp):
            rateConfig = .targetBitrate(bpp, layerCount: config.qualityLayers)
        case .constantQuality:
            rateConfig = .constantQuality(config.quality, layerCount: config.qualityLayers)
        case .variableBitrate(_, let maxBpp):
            rateConfig = .targetBitrate(maxBpp, layerCount: config.qualityLayers)
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
        layers: [QualityLayer]
    ) throws -> Data {
        var writer = J2KBitWriter()

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
        try writeCODMarker(&writer)

        // QCD — Quantization Default
        try writeQCDMarker(&writer, image: image)

        // SOT — Start of Tile-part (single tile for now)
        // Collect all tile data first so we know the length
        let tileData = try generateTileData(codeBlocks: codeBlocks, layers: layers)
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

        // Rsiz — Capabilities (0 = Part 1 baseline)
        segment.writeUInt16(0)
        // Xsiz — Image width
        segment.writeUInt32(UInt32(image.width))
        // Ysiz — Image height
        segment.writeUInt32(UInt32(image.height))
        // XOsiz — Horizontal offset (0)
        segment.writeUInt32(0)
        // YOsiz — Vertical offset (0)
        segment.writeUInt32(0)
        // XTsiz — Tile width (image width if no tiling)
        let tileW = config.tileSize.width > 0 ? config.tileSize.width : image.width
        segment.writeUInt32(UInt32(tileW))
        // YTsiz — Tile height (image height if no tiling)
        let tileH = config.tileSize.height > 0 ? config.tileSize.height : image.height
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

        // Ccap (2 bytes per capability pair)
        // First capability: HT block coding support
        // Bit 5 (0x0020) indicates HT block coding is supported
        let ccap1: UInt16 = 0x0020

        // Second capability: Mixed mode support
        // Bit 6 (0x0040) indicates mixed legacy/HT mode is supported
        let ccap2: UInt16 = 0x0040

        segment.writeUInt16(ccap1)
        segment.writeUInt16(ccap2)

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
        let pcpf: UInt16 = config.lossless ? 0 : 1

        segment.writeUInt16(pcpf)

        writer.writeMarkerSegment(J2KMarker.cpf.rawValue, segmentData: segment.data)
    }

    /// Writes the COD marker segment (Coding Style Default).
    private func writeCODMarker(_ writer: inout J2KBitWriter) throws {
        var segment = J2KBitWriter()

        // Scod — Coding style flags
        var scod: UInt8 = 0
        // Bit 0: Precincts defined (0 = default, 1 = user-defined)
        // Bit 1: SOP markers used (0 = no)
        // Bit 2: EPH markers used (0 = no)
        // Bits 3-4: HT set extensions (ISO/IEC 15444-15)
        //   00 = No HT sets
        //   01 = HT set A (set bit 3, clear bit 4)
        //   10 = HT set B
        //   11 = HT sets C and D
        // When HTJ2K mode is enabled, use default HT set A
        if config.useHTJ2K {
            scod |= 0x08 // Set bit 3 (bits 3-4 = 01 for HT set A)
        }
        segment.writeUInt8(scod)

        // SGcod — Progression order
        let progressionByte: UInt8
        switch config.progressionOrder {
        case .lrcp: progressionByte = 0
        case .rlcp: progressionByte = 1
        case .rpcl: progressionByte = 2
        case .pcrl: progressionByte = 3
        case .cprl: progressionByte = 4
        }
        segment.writeUInt8(progressionByte)

        // Number of layers
        segment.writeUInt16(UInt16(config.qualityLayers))

        // Multiple component transform (1 = RCT/ICT, 0 = none)
        segment.writeUInt8(config.lossless ? 1 : (config.quality < 1.0 ? 1 : 0))

        // SPcod — Coding parameters
        // Number of decomposition levels
        segment.writeUInt8(UInt8(config.decompositionLevels))

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
        segment.writeUInt8(config.lossless ? 1 : 0)

        // HT set parameters (ISO/IEC 15444-15) — only when bits 3-4 of Scod are non-zero
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
        segment.writeUInt8(config.lossless ? 1 : 0)

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
    private func writeQCDMarker(_ writer: inout J2KBitWriter, image: J2KImage) throws {
        var segment = J2KBitWriter()

        // Sqcd byte layout: guard bits (bits 5-7) | quantization style (bits 0-4)
        // Guard bits = 2 (standard value)
        let guardBits: UInt8 = 2

        if config.lossless {
            // No quantization (style = 0) for reversible transforms
            let sqcd = (guardBits << 5) | 0x00
            segment.writeUInt8(sqcd)

            // SPqcd: Exponent values for each subband
            // LL subband at coarsest level
            let bitDepth = image.components.first?.bitDepth ?? 8
            let epsilon = UInt8(bitDepth + config.decompositionLevels)
            segment.writeUInt8(epsilon << 3) // Exponent in bits 3-7

            // Detail subbands (HL, LH, HH) at each level
            for level in 0..<config.decompositionLevels {
                let exp = UInt8(bitDepth + config.decompositionLevels - level)
                segment.writeUInt8(exp << 3)
                segment.writeUInt8(exp << 3)
                segment.writeUInt8(exp << 3)
            }
        } else {
            // Scalar expounded quantization (style = 2) for lossy transforms
            let sqcd = (guardBits << 5) | 0x02
            segment.writeUInt8(sqcd)

            // SPqcd: Step size values for each subband (2 bytes each)
            let stepSizes = J2KStepSizeCalculator.calculateAllStepSizes(
                baseStepSize: 1.0 - config.quality,
                totalLevels: config.decompositionLevels,
                reversible: false
            )

            // LL subband
            let llStep = stepSizes["LL_0"] ?? 1.0
            let (llExp, llMant) = J2KStepSizeCalculator.encodeStepSize(llStep)
            segment.writeUInt16(UInt16((llExp & 0x1F) << 11 | (llMant & 0x7FF)))

            // Detail subbands
            if config.decompositionLevels > 0 {
                for level in 1...config.decompositionLevels {
                    for subband in [J2KSubband.hl, .lh, .hh] {
                        let key = "\(subband.rawValue)_\(level)"
                        let step = stepSizes[key] ?? 1.0
                        let (exp, mant) = J2KStepSizeCalculator.encodeStepSize(step)
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

    /// Generates the tile bitstream data from code blocks and layers.
    private func generateTileData(
        codeBlocks: [J2KCodeBlock], layers: [QualityLayer]
    ) throws -> Data {
        var data = Data()

        // Write packet data for each layer
        // For simplicity, write all code block data in a single packet per layer
        let headerWriter = PacketHeaderWriter()

        if layers.isEmpty || codeBlocks.isEmpty {
            // Write an empty packet
            let emptyHeader = PacketHeader(
                layerIndex: 0, resolutionLevel: 0, componentIndex: 0,
                precinctIndex: 0, isEmpty: true
            )
            data.append(try headerWriter.encode(emptyHeader))
        } else {
            // For the first layer, include all code block data
            let inclusions = codeBlocks.map { !$0.data.isEmpty }
            let passes = codeBlocks.map { $0.passeCount }
            let lengths = codeBlocks.map { $0.data.count }

            let header = PacketHeader(
                layerIndex: 0,
                resolutionLevel: 0,
                componentIndex: 0,
                precinctIndex: 0,
                isEmpty: false,
                codeBlockInclusions: inclusions,
                codingPasses: passes,
                dataLengths: lengths
            )

            data.append(try headerWriter.encode(header))

            // Append code block bitstream data
            for block in codeBlocks {
                data.append(block.data)
            }

            // Write empty packets for remaining layers
            for layerIdx in 1..<layers.count {
                let emptyHeader = PacketHeader(
                    layerIndex: layerIdx, resolutionLevel: 0, componentIndex: 0,
                    precinctIndex: 0, isEmpty: true
                )
                data.append(try headerWriter.encode(emptyHeader))
            }
        }

        return data
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
}
