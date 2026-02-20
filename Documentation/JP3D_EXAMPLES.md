# JP3D Comprehensive Usage Examples

## Table of Contents

1. [Medical Imaging Workflow](#medical-imaging-workflow)
2. [Scientific Visualization](#scientific-visualization)
3. [3D Texture Atlas](#3d-texture-atlas)
4. [Volumetric Streaming](#volumetric-streaming)
5. [ROI Decoding](#roi-decoding)
6. [Thumbnail Generation](#thumbnail-generation)
7. [Batch Processing Pipeline](#batch-processing-pipeline)
8. [HTJ2K Production Pipeline](#htj2k-production-pipeline)
9. [Complete End-to-End Example](#complete-end-to-end-example)
10. [Testing Utilities](#testing-utilities)

---

## Medical Imaging Workflow

### Full CT Scan Archival Pipeline

This example demonstrates a complete DICOM CT archival workflow: read DICOM slices, compress losslessly to JP3D, verify integrity, and save.

```swift
import Foundation
import J2KCore
import J2K3D

/// Represents a single DICOM CT slice loaded from disk.
struct DICOMSlice {
    let width: Int
    let height: Int
    let bitsAllocated: Int
    let pixelData: Data   // little-endian 16-bit signed Hounsfield units
}

/// Converts an array of DICOM slices to a losslessly compressed JP3D volume.
func archiveCTVolume(
    slices: [DICOMSlice],
    outputURL: URL
) async throws {
    guard slices.count >= 2 else {
        throw J2KError.invalidParameter("CT volume requires at least 2 slices")
    }
    guard let first = slices.first else { return }

    // 1. Convert DICOM little-endian pixel data to big-endian for J2K
    var bigEndianData = Data(capacity: first.width * first.height * 2 * slices.count)
    for slice in slices {
        let leData = slice.pixelData
        for i in stride(from: 0, to: leData.count, by: 2) {
            bigEndianData.append(leData[i + 1])  // high byte
            bigEndianData.append(leData[i])      // low byte
        }
    }

    // 2. Build volume component
    let component = J2KVolumeComponent(
        index: 0,
        bitDepth: 16,
        signed: true,        // Hounsfield units are signed
        width: first.width,
        height: first.height,
        depth: slices.count,
        data: bigEndianData
    )
    let volume = J2KVolume(
        width: first.width,
        height: first.height,
        depth: slices.count,
        components: [component]
    )

    // 3. Encode losslessly
    let config = JP3DEncoderConfiguration(
        compressionMode: .lossless,
        tiling: JP3DTilingConfiguration(
            tileWidth: 256,
            tileHeight: 256,
            tileDepth: min(32, slices.count)
        ),
        progressionOrder: .slrcp  // Slice-by-slice for medical access
    )
    let encoder = JP3DEncoder(configuration: config)
    let result = try await encoder.encode(volume)

    print("""
    CT Volume archived:
      Size:   \(result.width)×\(result.height)×\(result.depth)
      Tiles:  \(result.tileCount)
      Ratio:  \(String(format: "%.2f", result.compressionRatio))×
      Output: \(result.data.count / 1024) KB
    """)

    // 4. Write to disk
    try result.data.write(to: outputURL)

    // 5. Verify round-trip integrity
    let decoder = JP3DDecoder()
    let decoded = try await decoder.decode(result.data)
    guard !decoded.isPartial else {
        throw J2KError.internalError("Verification failed: partial decode after lossless encode")
    }
    guard decoded.volume.components[0].data == bigEndianData else {
        throw J2KError.internalError("Verification failed: voxel data mismatch")
    }
    print("✅ Lossless integrity verified")
}

/// Reconstructs individual CT slices from a JP3D archive.
func extractSlices(from jp3dURL: URL) async throws -> [[UInt8]] {
    let data = try Data(contentsOf: jp3dURL)
    let decoder = JP3DDecoder()
    let result = try await decoder.decode(data)

    let volume = result.volume
    let comp = volume.components[0]
    let sliceBytes = comp.width * comp.height * (comp.bitDepth / 8)

    return (0..<comp.depth).map { z in
        let start = z * sliceBytes
        return Array(comp.data[start..<(start + sliceBytes)])
    }
}
```

### Multi-Modal Volume (PET-CT)

```swift
import J2KCore
import J2K3D

/// Encodes a co-registered PET-CT volume with two components:
/// component 0 = CT (16-bit signed), component 1 = PET SUV (16-bit unsigned)
func encodePETCT(
    ctData: Data,
    petData: Data,
    width: Int,
    height: Int,
    depth: Int
) async throws -> JP3DEncoderResult {
    let ctComponent = J2KVolumeComponent(
        index: 0,
        bitDepth: 16,
        signed: true,
        width: width, height: height, depth: depth,
        data: ctData
    )
    let petComponent = J2KVolumeComponent(
        index: 1,
        bitDepth: 16,
        signed: false,
        width: width, height: height, depth: depth,
        data: petData
    )
    let volume = J2KVolume(
        width: width, height: height, depth: depth,
        components: [ctComponent, petComponent]
    )

    // Lossless: both modalities must be preserved exactly
    let encoder = JP3DEncoder(configuration: JP3DEncoderConfiguration(
        compressionMode: .lossless,
        tiling: .default,
        enableColorTransform: false  // Disable colour transform for multi-modal data
    ))
    return try await encoder.encode(volume)
}
```

---

## Scientific Visualization

### Seismic Data Compression

```swift
import Foundation
import J2KCore
import J2K3D

/// Compresses 3D seismic amplitude data (Float32 samples).
struct SeismicVolume {
    let inlines: Int      // ~ X
    let crosslines: Int   // ~ Y
    let samples: Int      // ~ Z (time)
    let data: [Float]     // inlines × crosslines × samples, row-major
}

func compressSeismic(
    seismic: SeismicVolume,
    targetPSNR: Double = 55.0
) async throws -> Data {
    // Convert Float → UInt32 bit-pattern for lossless float encoding
    var rawData = Data(count: seismic.data.count * 4)
    rawData.withUnsafeMutableBytes { ptr in
        seismic.data.withUnsafeBytes { src in
            ptr.copyBytes(from: src)
        }
    }

    let component = J2KVolumeComponent(
        index: 0,
        bitDepth: 32,
        signed: true,
        width: seismic.inlines,
        height: seismic.crosslines,
        depth: seismic.samples,
        data: rawData
    )
    let volume = J2KVolume(
        width: seismic.inlines,
        height: seismic.crosslines,
        depth: seismic.samples,
        components: [component]
    )

    // Use large tile depth to exploit seismic inter-sample correlation
    let config = JP3DEncoderConfiguration(
        compressionMode: .lossy(psnr: targetPSNR),
        tiling: JP3DTilingConfiguration(
            tileWidth: 128,
            tileHeight: 128,
            tileDepth: 64
        ),
        decompositionLevelsXY: 4,
        decompositionLevelsZ: 5  // More Z levels for seismic depth correlation
    )
    let encoder = JP3DEncoder(configuration: config)
    let result = try await encoder.encode(volume)

    print("Seismic compression: \(String(format: "%.1f", result.compressionRatio))× at ~\(targetPSNR) dB PSNR")
    return result.data
}
```

### Simulation Output (Hyperspectral Cube)

```swift
import J2KCore
import J2K3D

/// Encodes a hyperspectral data cube: spatial(X,Y) × spectral(Z bands).
func encodeHyperspectral(
    spatialWidth: Int,
    spatialHeight: Int,
    spectralBands: Int,
    bandData: [[Float]]  // spectralBands arrays, each spatialWidth*spatialHeight floats
) async throws -> Data {
    // Pack all bands into a single component
    var allData = Data()
    for band in bandData {
        var bandBytes = Data(count: band.count * 4)
        bandBytes.withUnsafeMutableBytes { ptr in
            band.withUnsafeBytes { src in ptr.copyBytes(from: src) }
        }
        allData.append(bandBytes)
    }

    let component = J2KVolumeComponent(
        index: 0,
        bitDepth: 32,
        signed: true,
        width: spatialWidth,
        height: spatialHeight,
        depth: spectralBands,
        data: allData
    )
    let volume = J2KVolume(
        width: spatialWidth,
        height: spatialHeight,
        depth: spectralBands,
        components: [component]
    )

    // Cubical tiles exploit equal spatial and spectral correlation
    let tileSize = min(64, spectralBands, spatialWidth, spatialHeight)
    let config = JP3DEncoderConfiguration(
        compressionMode: .lossless,
        tiling: JP3DTilingConfiguration(
            tileWidth: tileSize,
            tileHeight: tileSize,
            tileDepth: tileSize
        )
    )
    return try await JP3DEncoder(configuration: config).encode(volume).data
}
```

---

## 3D Texture Atlas

### Game Engine Texture Volume

```swift
import J2KCore
import J2K3D

/// Encodes a 3D RGBA texture atlas for use in a game engine.
/// Each "layer" is a separate RGBA slice.
func encode3DTextureAtlas(
    width: Int,
    height: Int,
    layers: Int,
    rgbaData: Data   // width * height * layers * 4 bytes, RGBA interleaved
) async throws -> Data {
    // De-interleave RGBA → separate R, G, B, A components
    let pixelsPerLayer = width * height
    let totalPixels = pixelsPerLayer * layers
    var rData = Data(count: totalPixels)
    var gData = Data(count: totalPixels)
    var bData = Data(count: totalPixels)
    var aData = Data(count: totalPixels)

    for i in 0..<totalPixels {
        rData[i] = rgbaData[i * 4 + 0]
        gData[i] = rgbaData[i * 4 + 1]
        bData[i] = rgbaData[i * 4 + 2]
        aData[i] = rgbaData[i * 4 + 3]
    }

    let makeComponent = { (index: Int, data: Data) in
        J2KVolumeComponent(
            index: index,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            depth: layers,
            data: data
        )
    }

    let volume = J2KVolume(
        width: width,
        height: height,
        depth: layers,
        components: [
            makeComponent(0, rData),
            makeComponent(1, gData),
            makeComponent(2, bData),
            makeComponent(3, aData),
        ]
    )

    // Visually lossless for game textures — good quality / small files
    let config = JP3DEncoderConfiguration(
        compressionMode: .lossyHTJ2K(psnr: 45.0),
        tiling: .default,
        enableColorTransform: true
    )
    let result = try await JP3DEncoder(configuration: config).encode(volume)

    print("Texture atlas: \(width)×\(height)×\(layers) RGBA → \(result.compressionRatio)× compression")
    return result.data
}

/// Reconstructs interleaved RGBA from a decoded JP3D texture atlas.
func decodeTextureAtlas(_ jp3dData: Data) async throws -> (Data, Int, Int, Int) {
    let result = try await JP3DDecoder().decode(jp3dData)
    let vol = result.volume
    let totalPixels = vol.width * vol.height * vol.depth

    var rgbaOut = Data(count: totalPixels * 4)
    for i in 0..<totalPixels {
        rgbaOut[i * 4 + 0] = vol.components[0].data[i]
        rgbaOut[i * 4 + 1] = vol.components[1].data[i]
        rgbaOut[i * 4 + 2] = vol.components[2].data[i]
        rgbaOut[i * 4 + 3] = vol.components[3].data[i]
    }
    return (rgbaOut, vol.width, vol.height, vol.depth)
}
```

---

## Volumetric Streaming

### Real-Time Medical Viewer with JPIP

```swift
import Foundation
import J2KCore
import J2K3D
import JPIP

/// A simplified medical volume viewer that streams data over JPIP.
actor MedicalVolumeViewer {
    private let client: JP3DJPIPClient
    private let decoder: JP3DDecoder
    private var session: JPIPSession?
    private var currentVolumeID: String?

    init(serverURL: URL) {
        self.client = JP3DJPIPClient(
            serverURL: serverURL,
            configuration: JPIPClientConfiguration(
                progressionMode: .adaptive,
                cacheCapacityMB: 512,
                maxConcurrentRequests: 4
            )
        )
        self.decoder = JP3DDecoder(configuration: JP3DDecoderConfiguration(
            tolerateTruncation: true
        ))
    }

    func openVolume(id: String) async throws {
        if currentVolumeID != id {
            if session != nil { try await client.disconnect() }
            try await client.connect()
            session = try await client.createSession(volumeID: id)
            currentVolumeID = id
            print("Opened volume: \(id) (\(session!.volumeWidth)×\(session!.volumeHeight)×\(session!.volumeDepth))")
        }
    }

    /// Load a single slice at the given Z index, progressively refining quality.
    func loadSlice(z: Int, progressHandler: @Sendable (J2KVolume, Int) async -> Void) async throws {
        guard let sess = session else { throw JPIPError.noActiveSession }

        let sliceRegion = JP3DRegion(
            x: 0..<sess.volumeWidth,
            y: 0..<sess.volumeHeight,
            z: z..<(z + 1)
        )

        // Progressive quality delivery: layers 1 → 8
        for layer in 1...sess.qualityLayers {
            let streamRegion = JP3DStreamingRegion(
                xRange: sliceRegion.x,
                yRange: sliceRegion.y,
                zRange: sliceRegion.z,
                qualityLayer: layer,
                resolutionLevel: 0
            )
            let data = try await client.requestStreamingRegion(streamRegion)
            let decoded = try await decoder.decode(data, region: sliceRegion)
            await progressHandler(decoded.volume, layer)
        }
    }

    /// Prefetch slices adjacent to the current focus.
    func prefetchAround(z: Int, radius: Int = 5) async throws {
        guard let sess = session else { return }

        let zMin = max(0, z - radius)
        let zMax = min(sess.volumeDepth - 1, z + radius)
        let prefetchRegion = JP3DRegion(
            x: 0..<sess.volumeWidth,
            y: 0..<sess.volumeHeight,
            z: zMin..<(zMax + 1)
        )
        // Low-quality prefetch to populate cache
        _ = try await client.requestRegion(prefetchRegion, quality: 25)
    }
}
```

---

## ROI Decoding

### Anatomy-Specific Region Extraction

```swift
import J2KCore
import J2K3D

/// Named anatomical regions for a head CT (approximate voxel coordinates).
enum AnatomicalRegion {
    case brain
    case leftLung
    case rightLung
    case liver
    case custom(x: Range<Int>, y: Range<Int>, z: Range<Int>)

    func region(in volume: J2KVolume) -> JP3DRegion {
        switch self {
        case .brain:
            return JP3DRegion(
                x: (volume.width/4)..<(3*volume.width/4),
                y: (volume.height/4)..<(3*volume.height/4),
                z: (volume.depth*2/3)..<volume.depth
            )
        case .leftLung:
            return JP3DRegion(
                x: 0..<(volume.width/2),
                y: (volume.height/4)..<(3*volume.height/4),
                z: (volume.depth/3)..<(2*volume.depth/3)
            )
        case .rightLung:
            return JP3DRegion(
                x: (volume.width/2)..<volume.width,
                y: (volume.height/4)..<(3*volume.height/4),
                z: (volume.depth/3)..<(2*volume.depth/3)
            )
        case .liver:
            return JP3DRegion(
                x: (volume.width/4)..<(3*volume.width/4),
                y: (volume.height/4)..<(3*volume.height/4),
                z: (volume.depth/4)..<(volume.depth/2)
            )
        case .custom(let x, let y, let z):
            return JP3DRegion(x: x, y: y, z: z)
        }
    }
}

/// Extracts an anatomical region from a compressed JP3D file.
func extractAnatomicalRegion(
    from jp3dData: Data,
    region: AnatomicalRegion
) async throws -> J2KVolume {
    // First, do a minimal decode to get dimensions
    let decoder = JP3DDecoder(configuration: JP3DDecoderConfiguration(
        resolutionReduction: 3  // 1/8 resolution just for dimensions
    ))
    let dimResult = try await decoder.decode(jp3dData)
    let fullVolume = J2KVolume(
        width: dimResult.volume.width * 8,
        height: dimResult.volume.height * 8,
        depth: dimResult.volume.depth * 8,
        components: dimResult.volume.components
    )

    let roi = region.region(in: fullVolume)
    print("Extracting region: \(roi.x)×\(roi.y)×\(roi.z)")

    // Full-resolution decode of just the region
    let fullDecoder = JP3DDecoder()
    let result = try await fullDecoder.decode(jp3dData, region: roi)
    return result.volume
}
```

### Multi-Resolution ROI Loading

```swift
/// Loads an ROI at increasing resolutions — thumbnail first, then full quality.
func loadROIProgressive(
    jp3dData: Data,
    roi: JP3DRegion,
    onUpdate: @Sendable (J2KVolume, Int) async -> Void
) async throws {
    let maxLevels = 3  // resolution levels: 1/8, 1/4, 1/2, full

    for level in stride(from: maxLevels, through: 0, by: -1) {
        let config = JP3DDecoderConfiguration(resolutionReduction: level)
        let decoder = JP3DDecoder(configuration: config)
        let result = try await decoder.decode(jp3dData, region: roi)
        let scaleFactor = 1 << level
        await onUpdate(result.volume, scaleFactor)
    }
}
```

---

## Thumbnail Generation

### Generating Multiple Thumbnail Resolutions

```swift
import J2KCore
import J2K3D

struct VolumetricThumbnail {
    let volume: J2KVolume
    let resolutionLevel: Int
    let scaleFactor: Int  // 1, 2, 4, 8, ...
}

/// Generates a thumbnail pyramid from a JP3D file — all levels in parallel.
func generateThumbnailPyramid(jp3dData: Data, maxLevels: Int = 3) async throws -> [VolumetricThumbnail] {
    return try await withThrowingTaskGroup(of: VolumetricThumbnail.self) { group in
        for level in 0...maxLevels {
            group.addTask {
                let config = JP3DDecoderConfiguration(resolutionReduction: level)
                let decoder = JP3DDecoder(configuration: config)
                let result = try await decoder.decode(jp3dData)
                return VolumetricThumbnail(
                    volume: result.volume,
                    resolutionLevel: level,
                    scaleFactor: 1 << level
                )
            }
        }
        return try await group.reduce(into: []) { $0.append($1) }
            .sorted { $0.scaleFactor > $1.scaleFactor }
    }
}

/// Generates a single 2D thumbnail by extracting the middle slice at low resolution.
func generateMidSliceThumbnail(jp3dData: Data) async throws -> Data {
    let config = JP3DDecoderConfiguration(resolutionReduction: 2)  // 1/4 resolution
    let decoder = JP3DDecoder(configuration: config)
    let result = try await decoder.decode(jp3dData)

    let vol = result.volume
    let midZ = vol.depth / 2
    let sliceBytes = vol.width * vol.height * (vol.components[0].bitDepth / 8)
    let start = midZ * sliceBytes
    let sliceData = vol.components[0].data[start..<(start + sliceBytes)]

    // Re-encode the 2D slice as standard JPEG 2000 for thumbnail storage
    // (For display, convert to 8-bit PNG using your platform's image framework)
    print("Thumbnail: \(vol.width)×\(vol.height) (Z=\(midZ))")
    return Data(sliceData)
}
```

---

## Batch Processing Pipeline

### Parallel Multi-Volume Encoder

```swift
import Foundation
import J2KCore
import J2K3D

struct BatchEncodeJob {
    let inputURL: URL
    let outputURL: URL
    let width: Int
    let height: Int
    let depth: Int
    let bitDepth: Int
    let signed: Bool
}

struct BatchEncodeResult {
    let job: BatchEncodeJob
    let success: Bool
    let compressionRatio: Double
    let elapsedSeconds: Double
    let error: Error?
}

/// Encodes multiple raw volumes in parallel, bounded by CPU core count.
func batchEncode(
    jobs: [BatchEncodeJob],
    compressionMode: JP3DCompressionMode = .losslessHTJ2K,
    maxConcurrency: Int = ProcessInfo.processInfo.activeProcessorCount
) async -> [BatchEncodeResult] {
    let results = await withTaskGroup(of: BatchEncodeResult.self) { group in
        // Submit jobs in batches to avoid spawning too many tasks
        var submitted = 0

        for job in jobs {
            guard submitted < maxConcurrency else {
                // Wait for a result before submitting more
                break
            }
            group.addTask { await encodeOneJob(job, mode: compressionMode) }
            submitted += 1
        }

        var allResults: [BatchEncodeResult] = []
        for await result in group {
            allResults.append(result)
            // Submit next job if available
            if submitted < jobs.count {
                let nextJob = jobs[submitted]
                group.addTask { await encodeOneJob(nextJob, mode: compressionMode) }
                submitted += 1
            }
        }
        return allResults
    }

    let successful = results.filter { $0.success }.count
    let avgRatio = results.filter { $0.success }.map { $0.compressionRatio }.reduce(0, +)
        / Double(max(1, successful))
    print("Batch complete: \(successful)/\(jobs.count) succeeded, avg ratio \(String(format: "%.2f", avgRatio))×")
    return results
}

private func encodeOneJob(_ job: BatchEncodeJob, mode: JP3DCompressionMode) async -> BatchEncodeResult {
    let start = Date()
    do {
        let rawData = try Data(contentsOf: job.inputURL)
        let component = J2KVolumeComponent(
            index: 0,
            bitDepth: job.bitDepth,
            signed: job.signed,
            width: job.width,
            height: job.height,
            depth: job.depth,
            data: rawData
        )
        let volume = J2KVolume(
            width: job.width,
            height: job.height,
            depth: job.depth,
            components: [component]
        )
        let config = JP3DEncoderConfiguration(compressionMode: mode, tiling: .batch)
        let encoder = JP3DEncoder(configuration: config)
        let result = try await encoder.encode(volume)
        try result.data.write(to: job.outputURL)

        return BatchEncodeResult(
            job: job,
            success: true,
            compressionRatio: result.compressionRatio,
            elapsedSeconds: Date().timeIntervalSince(start),
            error: nil
        )
    } catch {
        return BatchEncodeResult(
            job: job,
            success: false,
            compressionRatio: 0,
            elapsedSeconds: Date().timeIntervalSince(start),
            error: error
        )
    }
}
```

---

## HTJ2K Production Pipeline

### Server-Side Transcoding Service

```swift
import Foundation
import J2KCore
import J2K3D

/// Transcodes existing JP3D files from standard codec to HTJ2K for faster streaming.
actor HTJ2KTranscoder {
    private let inputDirectory: URL
    private let outputDirectory: URL
    private let targetPSNR: Double
    private var processedCount = 0
    private var errorCount = 0

    init(inputDir: URL, outputDir: URL, targetPSNR: Double = 42.0) {
        self.inputDirectory = inputDir
        self.outputDirectory = outputDir
        self.targetPSNR = targetPSNR
    }

    func transcodeAll() async throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: inputDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "jp3" }

        print("Transcoding \(files.count) files to HTJ2K...")

        await withThrowingTaskGroup(of: Void.self) { group in
            for file in files {
                group.addTask { [self] in
                    await transcode(file)
                }
            }
        }

        print("Done: \(processedCount) transcoded, \(errorCount) errors")
    }

    private func transcode(_ inputURL: URL) async {
        do {
            // Decode original
            let inputData = try Data(contentsOf: inputURL)
            let decoder = JP3DDecoder()
            let decoded = try await decoder.decode(inputData)

            // Re-encode with HTJ2K
            let htConfig = JP3DEncoderConfiguration(
                compressionMode: .lossyHTJ2K(psnr: targetPSNR),
                tiling: .streaming,
                progressionOrder: .lrcps,
                qualityLayers: 8,
                htj2kConfiguration: JP3DHTJ2KConfiguration(singlePassHTJ2K: true)
            )
            let encoder = JP3DEncoder(configuration: htConfig)
            let result = try await encoder.encode(decoded.volume)

            let outputURL = outputDirectory
                .appendingPathComponent(inputURL.lastPathComponent)
            try result.data.write(to: outputURL)

            processedCount += 1
            print("  ✅ \(inputURL.lastPathComponent): \(String(format: "%.1f", result.compressionRatio))×")
        } catch {
            errorCount += 1
            print("  ❌ \(inputURL.lastPathComponent): \(error)")
        }
    }
}
```

---

## Complete End-to-End Example

### Full Medical Imaging Pipeline with JPIP Streaming

This example shows a complete round-trip: encode → save → JPIP stream → decode → verify.

```swift
import Foundation
import J2KCore
import J2K3D
import JPIP

// ─────────────────────────────────────────────
// STEP 1: Generate a synthetic CT-like volume
// ─────────────────────────────────────────────

func makeSyntheticCT(width: Int = 256, height: Int = 256, depth: Int = 128) -> J2KVolume {
    let totalVoxels = width * height * depth
    var data = Data(count: totalVoxels * 2)  // 16-bit

    data.withUnsafeMutableBytes { ptr in
        let buf = ptr.bindMemory(to: UInt16.self)
        for z in 0..<depth {
            for y in 0..<height {
                for x in 0..<width {
                    let idx = z * height * width + y * width + x

                    // Simulate: bright spherical object (bone) in air background
                    let cx = Double(width) / 2, cy = Double(height) / 2, cz = Double(depth) / 2
                    let dx = Double(x) - cx, dy = Double(y) - cy, dz = Double(z) - cz
                    let dist = sqrt(dx*dx + dy*dy + dz*dz)
                    let radius = Double(min(width, height, depth)) / 3

                    // Bone HU ≈ 700, air HU ≈ -1000 (shifted to 0-65535 for 16-bit unsigned)
                    let hu: Int = dist < radius ? 1700 : 24  // shifted: bone=1700, air=24
                    buf[idx] = CFSwapInt16HostToBig(UInt16(clamping: hu))
                }
            }
        }
    }

    return J2KVolume(
        width: width, height: height, depth: depth,
        components: [
            J2KVolumeComponent(
                index: 0, bitDepth: 16, signed: false,
                width: width, height: height, depth: depth,
                data: data
            )
        ]
    )
}

// ─────────────────────────────────────────────
// STEP 2: Encode to JP3D
// ─────────────────────────────────────────────

async func encodeVolume(_ volume: J2KVolume) async throws -> JP3DEncoderResult {
    let config = JP3DEncoderConfiguration(
        compressionMode: .lossless,
        tiling: .streaming,
        progressionOrder: .slrcp,
        qualityLayers: 6
    )
    let encoder = JP3DEncoder(configuration: config)
    let result = try await encoder.encode(volume)

    print("""
    Encoded:
      \(result.width)×\(result.height)×\(result.depth) @ \(result.componentCount) component(s)
      \(result.tileCount) tiles
      Ratio: \(String(format: "%.2f", result.compressionRatio))×
      Size:  \(result.data.count / 1024) KB
    """)
    return result
}

// ─────────────────────────────────────────────
// STEP 3: Decode full volume and verify
// ─────────────────────────────────────────────

func decodeAndVerify(encoded: JP3DEncoderResult, original: J2KVolume) async throws {
    let decoder = JP3DDecoder()
    let result = try await decoder.decode(encoded.data)

    print("Decoded: \(result.volume.width)×\(result.volume.height)×\(result.volume.depth)")
    print("Partial: \(result.isPartial)")
    print("Tiles:   \(result.tilesDecoded)/\(result.tilesTotal)")

    if encoded.isLossless {
        let original_data = original.components[0].data
        let decoded_data  = result.volume.components[0].data
        if original_data == decoded_data {
            print("✅ Lossless: all \(original_data.count) bytes match exactly")
        } else {
            print("❌ LOSSLESS MISMATCH — file a bug report!")
        }
    }
}

// ─────────────────────────────────────────────
// STEP 4: ROI decode a central slab
// ─────────────────────────────────────────────

func decodeROI(encoded: JP3DEncoderResult) async throws {
    let slab = JP3DRegion(
        x: 64..<192,
        y: 64..<192,
        z: 48..<80
    )
    let decoder = JP3DDecoder()
    let result = try await decoder.decode(encoded.data, region: slab)

    print("ROI decode: \(result.volume.width)×\(result.volume.height)×\(result.volume.depth)")
    print("ROI tiles:  \(result.tilesDecoded)/\(result.tilesTotal)")
}

// ─────────────────────────────────────────────
// STEP 5: Run the complete pipeline
// ─────────────────────────────────────────────

@main
struct JP3DPipelineDemo {
    static func main() async {
        do {
            print("=== JP3D End-to-End Demo ===\n")

            let volume  = makeSyntheticCT()
            print("Synthetic CT: \(volume.width)×\(volume.height)×\(volume.depth)\n")

            let encoded = try await encodeVolume(volume)
            try await decodeAndVerify(encoded: encoded, original: volume)
            try await decodeROI(encoded: encoded)

            print("\n=== Demo complete ===")
        } catch {
            print("Error: \(error)")
        }
    }
}
```

---

## Testing Utilities

### Synthetic Volume Factories

```swift
import J2KCore

/// Creates a volume filled with a gradient pattern (useful for codec testing).
func makeGradientVolume(w: Int, h: Int, d: Int, bitDepth: Int = 8) -> J2KVolume {
    let bytesPerVoxel = bitDepth / 8
    let maxVal = (1 << bitDepth) - 1
    var data = Data(count: w * h * d * bytesPerVoxel)

    data.withUnsafeMutableBytes { ptr in
        for z in 0..<d {
            for y in 0..<h {
                for x in 0..<w {
                    let idx = (z * h * w + y * w + x) * bytesPerVoxel
                    let value = ((x + y + z) * maxVal) / (w + h + d - 3)
                    if bytesPerVoxel == 1 {
                        ptr[idx] = UInt8(value)
                    } else {
                        ptr[idx]     = UInt8((value >> 8) & 0xFF)  // big-endian
                        ptr[idx + 1] = UInt8(value & 0xFF)
                    }
                }
            }
        }
    }

    return J2KVolume(
        width: w, height: h, depth: d,
        components: [
            J2KVolumeComponent(
                index: 0, bitDepth: bitDepth, signed: false,
                width: w, height: h, depth: d, data: data
            )
        ]
    )
}

/// Computes PSNR between two volumes (per first component).
func computePSNR(original: J2KVolume, decoded: J2KVolume) -> Double {
    let orig = original.components[0].data
    let dec  = decoded.components[0].data
    guard orig.count == dec.count else { return 0 }

    var mse: Double = 0
    for i in 0..<orig.count {
        let diff = Double(Int(orig[i]) - Int(dec[i]))
        mse += diff * diff
    }
    mse /= Double(orig.count)
    if mse == 0 { return Double.infinity }
    let maxVal: Double = 255.0
    return 20.0 * log10(maxVal / sqrt(mse))
}
```
