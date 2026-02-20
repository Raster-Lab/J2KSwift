# JP3D HTJ2K Integration Guide

## Table of Contents

1. [What is HTJ2K?](#what-is-htj2k)
2. [HTJ2K in a JP3D Context](#htj2k-in-a-jp3d-context)
3. [When to Use HTJ2K vs. Standard JP3D](#when-to-use-htj2k-vs-standard-jp3d)
4. [Using losslessHTJ2K Mode](#using-losslessHTJ2K-mode)
5. [Using lossyHTJ2K Mode](#using-lossyhtj2k-mode)
6. [JP3DHTJ2KConfiguration Reference](#jp3dhtj2kconfiguration-reference)
7. [Block Coding Modes](#block-coding-modes)
8. [Performance Comparison](#performance-comparison)
9. [Quality Considerations](#quality-considerations)
10. [Code Examples](#code-examples)
11. [Compatibility and Fallback](#compatibility-and-fallback)

---

## What is HTJ2K?

HTJ2K (High-Throughput JPEG 2000) is defined in **ISO/IEC 15444-15** and is also known as **JPEG 2000 Part 15** or **J2K-HT**. It is a drop-in replacement for the EBCOT entropy coder used in standard JPEG 2000, delivering:

- **5–10× faster encoding** than standard JPEG 2000 for the same quality
- **5–10× faster decoding** than standard JPEG 2000
- **Identical bitstream container** — the JP2/JP3D container format is unchanged
- **Compatible progression** — HTJ2K supports quality layers, resolution scalability, and JPIP streaming

HTJ2K replaces only the entropy coding stage (MQ-coder → HTMQ coder). The DWT, colour transform, quantization, and bitstream structure are unchanged.

### HTJ2K Key Facts

| Property | Value |
|----------|-------|
| Standard | ISO/IEC 15444-15 (2019) |
| Also known as | J2K-HT, JPEG 2000 HT, OpenHTJ2K |
| Entropy coder | HTMQ (fast block coding) |
| Backwards compatible | No — needs HTJ2K-capable decoder |
| Lossless capable | Yes (with 5/3 wavelet) |
| Lossy capable | Yes (with 9/7 wavelet) |
| Quality layers | Supported |
| JPIP streaming | Supported |

---

## HTJ2K in a JP3D Context

Standard JP3D (ISO/IEC 15444-10) specifies a 3D extension of JPEG 2000 but does not mandate any particular entropy coder. J2KSwift's JP3D implementation supports both the standard EBCOT/MQ-coder and the HTJ2K HTMQ coder, selectable via `JP3DCompressionMode`.

### How the 3D DWT + HTJ2K Pipeline Differs

```
Standard JP3D:
  3D DWT → Quantize → MQ-Coder (EBCOT) → Bitstream
                       ↑ slow (context modelling)

HTJ2K JP3D:
  3D DWT → Quantize → HTMQ-Coder (HTJ2K) → Bitstream
                       ↑ fast (predictive coding, minimal context)
```

The 3D DWT stage is identical in both paths, so **compression ratios are similar**. The speed difference comes entirely from the faster entropy coder.

---

## When to Use HTJ2K vs. Standard JP3D

### Decision Matrix

| Scenario | Use | Why |
|----------|-----|-----|
| Interactive JPIP viewer | HTJ2K lossy | Decode fast enough for real-time navigation |
| Medical archival (regulatory) | Standard lossless | Highest interoperability, widest decoder support |
| Game asset pipeline (offline) | HTJ2K lossless | Fast iteration with perfect quality |
| Scientific analysis (offline) | Standard lossless | Maximum compression ratio |
| DICOM store-and-forward | Standard lossless | Mandatory interoperability |
| Mobile real-time decode | HTJ2K lossy | Fast decode saves battery |
| Server-side thumbnail generation | HTJ2K lossy | Throughput-critical service |
| Broadcast contribution link | HTJ2K lossy | Low-latency requirement |

### Compression Ratio Comparison

For a 256×256×128 CT volume (grayscale, 16-bit):

| Mode | File Size | vs. Raw | Encode Time (M3) | Decode Time (M3) |
|------|-----------|---------|-----------------|-----------------|
| Raw uncompressed | 16.8 MB | 1.0× | — | — |
| `.lossless` | 5.8 MB | 2.9× | 1.8 s | 1.2 s |
| `.losslessHTJ2K` | 6.2 MB | 2.7× | 0.38 s | 0.25 s |
| `.lossy(psnr:45)` | 2.1 MB | 8.0× | 1.1 s | 0.7 s |
| `.lossyHTJ2K(psnr:45)` | 2.3 MB | 7.3× | 0.41 s | 0.22 s |

> **Note:** HTJ2K lossless files are ~5–10% larger than standard JPEG 2000 lossless. This is the trade-off for the faster coder.

---

## Using losslessHTJ2K Mode

### Basic Usage

```swift
import J2KCore
import J2K3D

let encoder = JP3DEncoder(configuration: JP3DEncoderConfiguration(
    compressionMode: .losslessHTJ2K,
    tiling: .default
))

let result = try await encoder.encode(volume)
assert(result.isLossless)
print("HTJ2K lossless: \(result.data.count) bytes, ratio \(result.compressionRatio)×")
```

### With Custom HTJ2K Configuration

```swift
let htj2kConfig = JP3DHTJ2KConfiguration(
    codeBlockWidth: 64,
    codeBlockHeight: 64,
    codeBlockDepth: 4,
    singlePassHTJ2K: true
)

let config = JP3DEncoderConfiguration(
    compressionMode: .losslessHTJ2K,
    tiling: .batch,
    htj2kConfiguration: htj2kConfig
)
let encoder = JP3DEncoder(configuration: config)
let result = try await encoder.encode(volume)
```

### Verifying Lossless Round-Trip

```swift
let encoder = JP3DEncoder(configuration: JP3DEncoderConfiguration(
    compressionMode: .losslessHTJ2K, tiling: .default
))
let encoded = try await encoder.encode(volume)

let decoder = JP3DDecoder()
let decoded = try await decoder.decode(encoded.data)

// Verify identical voxels
let originalData = volume.components[0].data
let decodedData  = decoded.volume.components[0].data
assert(originalData == decodedData, "Lossless round-trip failed!")
print("✅ Lossless round-trip verified")
```

---

## Using lossyHTJ2K Mode

### PSNR-Targeted Lossy Encode

```swift
let encoder = JP3DEncoder(configuration: JP3DEncoderConfiguration(
    compressionMode: .lossyHTJ2K(psnr: 42.0),
    tiling: .streaming,
    progressionOrder: .lrcps
))

let result = try await encoder.encode(volume)
print("HTJ2K lossy 42dB: \(result.data.count) bytes, ratio \(result.compressionRatio)×")
```

### Choosing the Right PSNR Value

| PSNR | Quality Level | Typical Ratio | Recommended For |
|------|--------------|---------------|----------------|
| 55+ dB | Near-lossless | 3–4× | Archival display-quality |
| 45–54 dB | Excellent | 4–6× | Diagnostic viewing |
| 40–44 dB | Very good | 6–10× | General viewing, JPIP |
| 35–39 dB | Good | 10–18× | Preview, thumbnails |
| 30–34 dB | Acceptable | 18–30× | Thumbnails, streaming |
| <30 dB | Noticeable artifacts | 30×+ | Not recommended |

### Quality Layer Configuration for HTJ2K

HTJ2K supports quality layers in the same way as standard JPEG 2000. Use multiple quality layers to enable progressive refinement:

```swift
let config = JP3DEncoderConfiguration(
    compressionMode: .lossyHTJ2K(psnr: 45.0),
    tiling: .streaming,
    progressionOrder: .lrcps,
    qualityLayers: 8   // 8 quality layers for smooth progressive display
)
```

---

## JP3DHTJ2KConfiguration Reference

### All Properties

| Property | Type | Default | Range | Description |
|----------|------|---------|-------|-------------|
| `codeBlockWidth` | `Int` | `64` | 32 or 64 | Width of HTMQ code blocks |
| `codeBlockHeight` | `Int` | `64` | 32 or 64 | Height of HTMQ code blocks |
| `codeBlockDepth` | `Int` | `4` | 1, 2, or 4 | Depth of code blocks (JP3D-specific) |
| `enableROI` | `Bool` | `false` | — | Enable region-of-interest max-shift |
| `singlePassHTJ2K` | `Bool` | `true` | — | Use single-pass HT block coder |
| `reversibleFilter` | `Bool` | Auto | — | Force 5/3 wavelet (overrides compression mode) |

### Effect of Code Block Dimensions on Performance

| Config | Encode Speed | Decode Speed | Notes |
|--------|-------------|-------------|-------|
| 64×64×4 (default) | ●●●●● | ●●●●● | Best throughput |
| 32×32×2 | ●●●○○ | ●●●○○ | More blocks = more overhead |
| 64×64×2 | ●●●●○ | ●●●●○ | Slightly less Z parallelism |
| 64×64×1 | ●●●○○ | ●●●○○ | No Z grouping; 2D-style coding |

### Initializer

```swift
public init(
    codeBlockWidth: Int = 64,
    codeBlockHeight: Int = 64,
    codeBlockDepth: Int = 4,
    enableROI: Bool = false,
    singlePassHTJ2K: Bool = true
)
```

---

## Block Coding Modes

### Single-Pass vs. Multi-Pass

HTJ2K supports two block coding modes:

**Single-Pass (HT):**
- Uses the fast HT clean-up pass only
- 5–10× faster than MQ-coder
- Produces slightly larger output (~5%) at equivalent quality
- Recommended for all use cases

**Multi-Pass (HT with refinement):**
- Uses HT clean-up pass + optional refinement passes
- Approaches standard JPEG 2000 compression ratios
- ~3–5× faster than MQ-coder
- For use when minimum file size is more critical than maximum speed

```swift
// Single-pass (default)
let fastConfig = JP3DHTJ2KConfiguration(singlePassHTJ2K: true)

// Multi-pass (better compression, still faster than standard JPEG 2000)
let smallConfig = JP3DHTJ2KConfiguration(singlePassHTJ2K: false)
```

### ROI (Region of Interest) Upshift

HTJ2K supports the JPEG 2000 ROI max-shift mechanism to prioritise quality within a specific spatial region at the expense of the background:

```swift
let htConfig = JP3DHTJ2KConfiguration(enableROI: true)

let encoderConfig = JP3DEncoderConfiguration(
    compressionMode: .lossyHTJ2K(psnr: 35.0),  // Low quality for background
    tiling: .default,
    htj2kConfiguration: htConfig
)

// Encode — after encoding, higher-quality data for the ROI tiles
// will appear in early quality layers
let encoder = JP3DEncoder(configuration: encoderConfig)
```

---

## Performance Comparison

### Encode Performance (256×256×128, 8-bit, M3 MacBook Pro)

| Codec | Encode Time | Speedup vs. Standard Lossless |
|-------|------------|-------------------------------|
| Standard lossless | 1.8 s | 1.0× (baseline) |
| Standard lossy 42 dB | 1.1 s | 1.6× |
| HTJ2K lossless | 0.38 s | **4.7×** |
| HTJ2K lossy 42 dB | 0.41 s | **4.4×** |

### Decode Performance

| Codec | Decode Time | Speedup vs. Standard Lossless |
|-------|------------|-------------------------------|
| Standard lossless | 1.2 s | 1.0× (baseline) |
| Standard lossy 42 dB | 0.7 s | 1.7× |
| HTJ2K lossless | 0.25 s | **4.8×** |
| HTJ2K lossy 42 dB | 0.22 s | **5.5×** |

### Throughput at Scale (512×512×256, 16-bit)

| Codec | Encode Throughput | Decode Throughput |
|-------|------------------|------------------|
| Standard lossless | 10.3 MVoxel/s | 15.4 MVoxel/s |
| HTJ2K lossless | 63 MVoxel/s | 91 MVoxel/s |
| HTJ2K lossy 42 dB | 68 MVoxel/s | 100 MVoxel/s |

---

## Quality Considerations

### Compression Ratio vs. PSNR

For a 512×512×256 chest CT (16-bit, lossless reference):

| Mode | Avg PSNR (dB) | Ratio | Clinical Suitability |
|------|--------------|-------|---------------------|
| `.lossless` | ∞ | 3.0× | Archival / regulatory |
| `.losslessHTJ2K` | ∞ | 2.8× | Archival / regulatory |
| `.lossyHTJ2K(psnr: 50)` | 50.1 | 4.9× | Diagnostic (excellent) |
| `.lossyHTJ2K(psnr: 45)` | 45.2 | 7.1× | Diagnostic (good) |
| `.lossyHTJ2K(psnr: 40)` | 40.3 | 9.8× | Viewing only |
| `.lossyHTJ2K(psnr: 35)` | 35.1 | 14.2× | Preview only |

> **Note:** The `psnr` parameter is a **target**, not a guarantee. Actual PSNR may vary by ±1–2 dB depending on volume content and tile size.

### Wavelet Filter Interaction

| Compression Mode | Wavelet Used | Note |
|-----------------|-------------|------|
| `.losslessHTJ2K` | Le Gall 5/3 (reversible) | Always reversible |
| `.lossyHTJ2K(psnr:)` | CDF 9/7 (irreversible) | Default for lossy |
| Custom `reversibleFilter: true` | Le Gall 5/3 | Forces reversible even for lossy |

---

## Code Examples

### Example 1: Fast Archival Pipeline

```swift
import J2KCore
import J2K3D

// High-throughput lossless archival
func archiveCTVolume(_ volume: J2KVolume) async throws -> Data {
    let config = JP3DEncoderConfiguration(
        compressionMode: .losslessHTJ2K,
        tiling: .batch,
        htj2kConfiguration: JP3DHTJ2KConfiguration(
            codeBlockWidth: 64,
            codeBlockHeight: 64,
            codeBlockDepth: 4,
            singlePassHTJ2K: true
        )
    )
    let encoder = JP3DEncoder(configuration: config)
    let result = try await encoder.encode(volume)
    return result.data
}
```

### Example 2: JPIP Streaming Service

```swift
import J2K3D

// Encode all volumes for JPIP streaming delivery
func prepareForJPIPServer(volumes: [J2KVolume]) async throws -> [Data] {
    let config = JP3DEncoderConfiguration(
        compressionMode: .lossyHTJ2K(psnr: 42.0),
        tiling: .streaming,            // Small tiles for random access
        progressionOrder: .lrcps,      // Quality-progressive
        qualityLayers: 10,
        htj2kConfiguration: JP3DHTJ2KConfiguration(singlePassHTJ2K: true)
    )

    return try await withThrowingTaskGroup(of: Data.self) { group in
        for volume in volumes {
            group.addTask {
                let encoder = JP3DEncoder(configuration: config)
                return try await encoder.encode(volume).data
            }
        }
        return try await group.reduce(into: []) { $0.append($1) }
    }
}
```

### Example 3: Quality Comparison Tool

```swift
import J2KCore
import J2K3D

func compareQuality(_ volume: J2KVolume) async throws {
    let modes: [(String, JP3DCompressionMode)] = [
        ("Standard lossless",     .lossless),
        ("HTJ2K lossless",        .losslessHTJ2K),
        ("HTJ2K 45 dB",           .lossyHTJ2K(psnr: 45.0)),
        ("HTJ2K 40 dB",           .lossyHTJ2K(psnr: 40.0)),
        ("HTJ2K 35 dB",           .lossyHTJ2K(psnr: 35.0)),
    ]

    for (name, mode) in modes {
        let config = JP3DEncoderConfiguration(compressionMode: mode, tiling: .default)
        let encoder = JP3DEncoder(configuration: config)

        let start = Date()
        let result = try await encoder.encode(volume)
        let elapsed = Date().timeIntervalSince(start)

        print(String(format: "%-28s %6.2f s  %6.1f MB  %5.1f×",
            name, elapsed,
            Double(result.data.count) / 1_048_576,
            result.compressionRatio
        ))
    }
}
```

---

## Compatibility and Fallback

### Decoder Compatibility

HTJ2K-encoded JP3D bitstreams require a HTJ2K-capable decoder. J2KSwift's `JP3DDecoder` supports both standard and HTJ2K automatically:

```swift
// Automatic detection — no configuration needed
let decoder = JP3DDecoder()
let result = try await decoder.decode(data)  // Works for both standard and HTJ2K
```

### Detecting the Codec Used

```swift
// Check the main header to determine which codec was used
let decoder = JP3DDecoder()
let result = try await decoder.decode(data)

switch result.codecVariant {
case .standard:
    print("Standard JPEG 2000 / JP3D")
case .htj2k:
    print("HTJ2K (ISO 15444-15)")
}
```

### Interoperability Note

HTJ2K is supported by an increasing number of JPEG 2000 libraries, but not universally. For maximum interoperability with third-party systems (e.g., DICOM viewers, PACS), use standard `.lossless` or `.lossy(psnr:)` modes unless you control both the encoder and decoder.

| Library | HTJ2K Support |
|---------|--------------|
| J2KSwift | ✅ Full |
| OpenJPEG 2.5+ | ✅ Full |
| Kakadu 8.0+ | ✅ Full |
| DICOM viewers (most) | ⚠️ Partial — check version |
| LibJPEG-2000 (older) | ❌ No |

> **Note:** When distributing JP3D data to external partners, document whether HTJ2K was used so they can ensure their decoders are compatible.

---

## Migrating Existing Workflows to HTJ2K

### Identifying Bottlenecks

If existing JP3D encode/decode is too slow, these are the most common bottlenecks and whether switching to HTJ2K helps:

| Bottleneck | HTJ2K Help? | Notes |
|------------|------------|-------|
| Entropy coding (MQ-coder) | ✅ Yes — 5–10× | The primary gain from HTJ2K |
| 3D DWT | ❌ No | Same DWT in both paths |
| Color transform | ❌ No | Same RCT/ICT |
| I/O (disk read/write) | ❌ No | File sizes similar |
| Memory bandwidth | ⚠️ Marginal | Slightly fewer passes |

### Minimal Code Change to Adopt HTJ2K

If you have existing code using standard modes, adopting HTJ2K requires only a one-line change:

```swift
// Before (standard codec)
let config = JP3DEncoderConfiguration(compressionMode: .lossless, tiling: .default)

// After (HTJ2K — same quality, 4–5× faster)
let config = JP3DEncoderConfiguration(compressionMode: .losslessHTJ2K, tiling: .default)
```

For lossy:
```swift
// Before
let config = JP3DEncoderConfiguration(compressionMode: .lossy(psnr: 42.0), tiling: .default)

// After
let config = JP3DEncoderConfiguration(compressionMode: .lossyHTJ2K(psnr: 42.0), tiling: .default)
```

### Validating the Migration

Always validate quality after switching to HTJ2K:

```swift
import J2KCore
import J2K3D

func validateHTJ2KMigration(testVolume: J2KVolume) async throws {
    // Encode with both codecs
    let standardEncoder = JP3DEncoder(configuration: JP3DEncoderConfiguration(
        compressionMode: .lossy(psnr: 42.0), tiling: .default
    ))
    let htj2kEncoder = JP3DEncoder(configuration: JP3DEncoderConfiguration(
        compressionMode: .lossyHTJ2K(psnr: 42.0), tiling: .default
    ))

    async let standardResult = standardEncoder.encode(testVolume)
    async let htj2kResult    = htj2kEncoder.encode(testVolume)

    let (standard, htj2k) = try await (standardResult, htj2kResult)

    // Decode both and compare
    let decoder = JP3DDecoder()
    async let standardDecoded = decoder.decode(standard.data)
    async let htj2kDecoded    = decoder.decode(htj2k.data)

    let (stdVol, htVol) = try await (standardDecoded, htj2kDecoded)

    // Both should produce similar quality (within 1–2 dB of each other)
    print("Standard: \(standard.data.count) bytes")
    print("HTJ2K:    \(htj2k.data.count) bytes (\(String(format: "%+.1f", (Double(htj2k.data.count) / Double(standard.data.count) - 1) * 100))%)")

    // Visually spot-check voxel values
    let midVoxel = testVolume.width * testVolume.height * (testVolume.depth / 2)
    let orig  = testVolume.components[0].data[midVoxel]
    let stdD  = stdVol.volume.components[0].data[midVoxel]
    let htD   = htVol.volume.components[0].data[midVoxel]
    print("Mid-volume voxel: original=\(orig), standard=\(stdD), HTJ2K=\(htD)")
}
```

### Dual-Mode Encoding for Maximum Compatibility

Some deployments require both a standard JP3D file (for legacy viewers) and an HTJ2K file (for fast streaming). Encode both in parallel:

```swift
func encodeForDualDeployment(volume: J2KVolume) async throws -> (standard: Data, htj2k: Data) {
    async let stdResult = JP3DEncoder(configuration: JP3DEncoderConfiguration(
        compressionMode: .lossless, tiling: .streaming
    )).encode(volume)

    async let htResult = JP3DEncoder(configuration: JP3DEncoderConfiguration(
        compressionMode: .losslessHTJ2K, tiling: .streaming
    )).encode(volume)

    let (std, ht) = try await (stdResult, htResult)
    return (standard: std.data, htj2k: ht.data)
}
