# JP3D Troubleshooting Guide

## Table of Contents

1. [Build Issues](#build-issues)
2. [Runtime Errors — Volume Validation](#runtime-errors--volume-validation)
3. [Runtime Errors — Encoding Failures](#runtime-errors--encoding-failures)
4. [Decoding Issues](#decoding-issues)
5. [JPIP Connectivity Issues](#jpip-connectivity-issues)
6. [Metal / GPU Issues](#metal--gpu-issues)
7. [Linux-Specific Issues](#linux-specific-issues)
8. [Performance Issues](#performance-issues)
9. [Memory and Crash Issues](#memory-and-crash-issues)
10. [Lossless Verification Failures](#lossless-verification-failures)
11. [FAQ](#faq)

---

## Build Issues

### `no module named 'J2K3D'`

**Symptom:**
```
error: no module named 'J2K3D'
```

**Causes and fixes:**

1. Missing product in `Package.swift`:
```swift
// Add to your target's dependencies:
.product(name: "J2K3D", package: "J2KSwift")
```

2. Wrong Swift package version — `J2K3D` requires J2KSwift 1.9.0+:
```swift
.package(url: "https://github.com/Raster-Lab/J2KSwift.git", from: "1.9.0")
```

3. Package cache stale — run `swift package resolve` or in Xcode: **File → Packages → Reset Package Caches**.

---

### `actor isolation' errors in Swift 6`

**Symptom:**
```
error: sending 'volume' risks causing data races
```

**Cause:** Passing a `J2KVolume` from a non-isolated context into a `JP3DEncoder` method.

**Fix:** Ensure the volume is created and captured in a safe manner:
```swift
// Bad: volume may be captured from non-isolated context
@MainActor func encodeOnMain() async throws {
    let volume = makeVolume()  // @MainActor
    let result = try await encoder.encode(volume)  // ⚠️ warning
}

// Good: isolate within a Task
func encode() async throws {
    let volume = makeVolume()  // nonisolated
    let result = try await encoder.encode(volume)  // ✅ safe — J2KVolume is Sendable
}
```

`J2KVolume` conforms to `Sendable`, so the fix is usually to ensure the variable is not `@MainActor`-isolated at the call site.

---

### `JP3DHTJ2KConfiguration: cannot find type`

**Symptom:**
```
error: cannot find type 'JP3DHTJ2KConfiguration' in scope
```

**Fix:** `JP3DHTJ2KConfiguration` is in the `J2K3D` module. Ensure your import is `import J2K3D`, not just `import J2KCore`.

---

### Compile error on `withThrowingTaskGroup` with `JP3DEncoderResult`

**Symptom:**
```
error: type 'JP3DEncoderResult' does not conform to 'Sendable'
```

This should not occur in J2KSwift 1.9.0+ as `JP3DEncoderResult` is `Sendable`. If you see this:

1. Ensure you are using J2KSwift 1.9.0 or later.
2. Run `swift package update` and `swift package resolve`.

---

## Runtime Errors — Volume Validation

### `J2KError.invalidParameter("component data size")`

**Full message:** `"component data size mismatch: expected X bytes, got Y bytes"`

**Cause:** The `data` property of a `J2KVolumeComponent` has the wrong length.

**Fix:** Verify the data length:
```swift
let expectedBytes = width * height * depth * (bitDepth / 8)
precondition(
    data.count == expectedBytes,
    "data.count \(data.count) ≠ expected \(expectedBytes)"
)
```

**Common mistakes:**

| Mistake | Example |
|---------|---------|
| Forgot to account for `depth` | `data.count = width * height` instead of `width * height * depth` |
| Wrong `bitDepth` | Using `bitDepth: 8` for 16-bit DICOM data |
| Missing final slice | Off-by-one in slice count |
| Stride/padding in source | Source data has row padding that must be stripped |

---

### `J2KError.invalidParameter("depth < 2")`

**Cause:** `J2KVolume` has `depth == 1`. JP3D requires at least 2 slices.

**Fix:**
- If you have a single slice, use `J2KEncoder` from `J2KCodec` instead of `JP3DEncoder`.
- If you have a 2-slice minimum, this is a data issue — verify your slice source.

---

### `J2KError.invalidParameter("component count mismatch")`

**Cause:** Multiple components have inconsistent `width`, `height`, or `depth` values.

**Fix:** All components must have identical dimensions matching the parent `J2KVolume`:
```swift
// All three components must have the same dimensions
let r = J2KVolumeComponent(index: 0, ..., width: 512, height: 512, depth: 128, ...)
let g = J2KVolumeComponent(index: 1, ..., width: 512, height: 512, depth: 128, ...)  // ✅
let b = J2KVolumeComponent(index: 2, ..., width: 256, height: 256, depth: 128, ...)  // ❌ different dimensions
```

---

### `J2KError.invalidParameter("tiling")`

**Full message:** `"tileDepth 64 exceeds volume depth 32"`

**Cause:** A tile dimension is larger than the corresponding volume dimension.

**Fix:** Use a tiling preset or clamp tile dimensions:
```swift
let tileDepth = min(16, volume.depth)
let tiling = JP3DTilingConfiguration(
    tileWidth: 256,
    tileHeight: 256,
    tileDepth: tileDepth
)
```

---

## Runtime Errors — Encoding Failures

### `J2KError.internalError("codec: unsupported bit depth")`

**Cause:** The combination of `bitDepth` and compression mode is not supported.

**Supported combinations:**

| `bitDepth` | `.lossless` | `.lossy(psnr:)` | `.losslessHTJ2K` | `.lossyHTJ2K` |
|-----------|------------|----------------|-----------------|--------------|
| 8 | ✅ | ✅ | ✅ | ✅ |
| 10 | ✅ | ✅ | ✅ | ✅ |
| 12 | ✅ | ✅ | ✅ | ✅ |
| 16 | ✅ | ✅ | ✅ | ✅ |
| 32 | ✅ | ⚠️ Experimental | ✅ | ⚠️ Experimental |

---

### `J2KError.outOfMemory`

**Cause:** The encoder ran out of memory during tile processing.

**Fixes:**

1. Switch to smaller tiling:
```swift
// Before
let config = JP3DEncoderConfiguration(compressionMode: .lossless, tiling: .batch)

// After
let config = JP3DEncoderConfiguration(compressionMode: .lossless, tiling: .streaming)
```

2. Reduce concurrent workers:
```swift
let config = JP3DEncoderConfiguration(
    compressionMode: .lossless,
    tiling: .default,
    maxConcurrentTileWorkers: 2   // Reduce from default (all cores)
)
```

3. For very large volumes, encode in sub-regions:
```swift
// Partition into manageable sub-volumes
for z in stride(from: 0, to: volume.depth, by: 64) {
    let region = JP3DRegion(
        x: 0..<volume.width,
        y: 0..<volume.height,
        z: z..<min(z + 64, volume.depth)
    )
    let partial = try await encoder.encode(volume, region: region)
    // ... stitch results
}
```

---

### Encoding Produces Zero-Length Data

**Cause:** A rare edge case where all voxels have the same value (e.g., empty volume).

**Fix:** This is a known limitation for degenerate inputs. Add a check:
```swift
// Verify volume has non-trivial content before encoding
let uniqueBytes = Set(volume.components[0].data)
guard uniqueBytes.count > 1 else {
    // Handle trivial volume specially
    print("Warning: uniform volume — consider special-casing this")
}
```

---

## Decoding Issues

### `result.isPartial == true` — Unexpected Partial Decode

**Causes:**
1. Truncated input data (network interruption, incomplete file write)
2. Corrupted tile-part headers
3. `JP3DDecoderConfiguration.tolerateTruncation` is true and data is incomplete

**Diagnosis:**
```swift
let result = try await decoder.decode(data)
if result.isPartial {
    print("Tiles decoded: \(result.tilesDecoded)/\(result.tilesTotal)")
    result.warnings.forEach { print("Warning: \($0)") }
}
```

**Fix:**
- Verify data integrity before decoding (check file size, checksum)
- If using JPIP streaming, ensure the full response was received
- If partial results are expected (progressive streaming), this is normal

---

### Decoded Volume Has Wrong Dimensions

**Symptom:** `decoded.volume.width`, `.height`, or `.depth` differ from the original.

**Cause:** A non-zero `resolutionReduction` in `JP3DDecoderConfiguration`:
```swift
// If you set resolutionReduction: 1, dimensions are halved
let config = JP3DDecoderConfiguration(resolutionReduction: 1)
// decoded.volume.width == originalWidth / 2
```

**Fix:** Set `resolutionReduction: 0` for full-resolution decode.

---

### Decoded Data Contains NaN or Inf Voxel Values

**Cause:** Lossy decode of a floating-point component where the quantization step size was set too aggressively.

**Fix:** Use a higher PSNR target for float volumes (>= 50 dB):
```swift
let config = JP3DEncoderConfiguration(
    compressionMode: .lossy(psnr: 55.0),  // Higher quality for float data
    tiling: .default
)
```

---

### `J2KError.invalidParameter("not a JP3D bitstream")`

**Cause:** Trying to decode a 2D J2K/JP2 file with `JP3DDecoder`.

**Fix:**
```swift
// Detect format first
if JP3DDecoder.canDecode(data) {
    let result = try await JP3DDecoder().decode(data)
} else {
    let result = try await J2KDecoder().decode(data)
}
```

---

## JPIP Connectivity Issues

### `JPIPError.volumeNotFound`

**Cause:** The `volumeID` passed to `createSession(volumeID:)` does not exist on the server.

**Fix:** Verify the volume ID is correct. Volume IDs are case-sensitive and server-specific.

---

### `JPIPError.sessionExpired`

**Cause:** JPIP sessions time out after inactivity. The default server timeout varies (typically 30–120 seconds).

**Fix:**
```swift
do {
    let data = try await client.requestRegion(region)
} catch JPIPError.sessionExpired {
    // Reconnect and retry
    try await client.disconnect()
    try await client.connect()
    session = try await client.createSession(volumeID: currentVolumeID)
    let data = try await client.requestRegion(region)
}
```

Enable automatic reconnect to handle this transparently:
```swift
let config = JPIPClientConfiguration(
    enableAutoReconnect: true,
    maxReconnectAttempts: 3
)
```

---

### `JPIPError.networkError` on TLS/HTTPS

**Symptom:** TLS handshake fails when connecting to `jpips://` server.

**Causes and fixes:**

| Cause | Fix |
|-------|-----|
| Self-signed server certificate | Add to app's trusted certificates or use `.trustAll` (dev only) |
| Outdated TLS version | Server must support TLS 1.2+ |
| Certificate hostname mismatch | Ensure serverURL hostname matches certificate CN/SAN |
| Proxy interference | Configure proxy in `JPIPClientConfiguration` |

```swift
// Development only — do not use in production
let config = JPIPClientConfiguration(
    tlsConfiguration: .trustAll  // ⚠️ INSECURE — dev/testing only
)
```

---

### Slow JPIP Streaming Performance

**Diagnosis checklist:**

1. Check tile size — streaming requires small tiles:
```swift
// Verify server-side tile configuration
let session = try await client.createSession(volumeID: id)
print("Server tile size: \(session.tileWidth)×\(session.tileHeight)×\(session.tileDepth)")
// For streaming, want ≤ 128×128×8
```

2. Check cache hit rate:
```swift
let stats = await client.cacheStatistics
print("Cache hit rate: \(stats.hitRate)")  // Should be > 0.5 for repeat access
```

3. Enable HTTP/2:
```swift
let config = JPIPClientConfiguration(httpVersion: .http2)
```

---

## Metal / GPU Issues

### Metal Unavailable Warning

**Symptom:**
```
⚠️ Metal not available — falling back to software path
```

**Common causes:**

| Cause | Platform | Fix |
|-------|----------|-----|
| Running in simulator | iOS/macOS | Use physical device for Metal |
| GPU access denied by sandbox | macOS | Add `com.apple.security.device.gpu` entitlement |
| MTLDevice not available | tvOS | Metal available; check device |
| Metal shader library not found | All | File a bug report — library should be bundled |

**Checking Metal status:**
```swift
import J2K3D

let caps = JP3DEncoder.capabilities
print("Metal available: \(caps.metalAvailable)")
if let reason = caps.metalUnavailableReason {
    print("Reason: \(reason)")
}
```

---

### `MTLError outOfMemory` During Encoding

**Symptom:** Metal runs out of GPU memory for large tile sizes.

**Fix:** Switch to smaller tiling or force software path:
```swift
// Option 1: Smaller tiles
let config = JP3DEncoderConfiguration(
    compressionMode: .lossless,
    tiling: .streaming  // 128×128×8 — much lower GPU memory
)

// Option 2: Force software (avoids GPU memory constraint)
let config = JP3DEncoderConfiguration(
    compressionMode: .lossless,
    tiling: .batch,
    accelerationPolicy: .accelerateOnly  // Use Accelerate, not Metal
)
```

---

### GPU Encoding Produces Different Results from CPU

**Expected:** Results should be numerically identical (lossless) or within floating-point rounding (lossy).

**If lossless GPU ≠ CPU output:** This is a bug. File a bug report including:
1. Platform (macOS/iOS version, GPU model)
2. `JP3DEncoder.version`
3. Volume dimensions and bit depth
4. Configuration used

---

## Linux-Specific Issues

### `swift build` Fails with Undefined Symbols

**Symptom:**
```
error: undefined symbol: _vDSP_conv
```

**Cause:** `J2KAccelerate` is being imported on Linux, where the Accelerate framework is not available.

**Fix:** Remove `J2KAccelerate` from your Linux target dependencies in `Package.swift`:
```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "J2KCore", package: "J2KSwift"),
        .product(name: "J2K3D", package: "J2KSwift"),
        // Do NOT include J2KAccelerate or J2KMetal on Linux
    ]
)
```

Or use conditional compilation:
```swift
#if canImport(Accelerate)
import J2KAccelerate
#endif
```

---

### Slow Encode on Linux

**Cause:** Linux uses the pure Swift SIMD path (no Accelerate, no Metal). This is expected — see [Performance Guide](JP3D_PERFORMANCE.md) for Linux benchmarks.

**Mitigation:**
- Always build in release mode: `swift build -c release`
- Use HTJ2K: significantly faster even without Accelerate
- Increase CPU parallelism: Linux supports more concurrent tile workers

```bash
# Build in release mode for maximum performance
swift build -c release
```

---

## Performance Issues

### Encoder Is Slow — Not Using All Cores

**Diagnosis:**
```swift
// Check how many workers are actually being used
let config = JP3DEncoderConfiguration(
    compressionMode: .lossless,
    tiling: .default,
    collectTimingStatistics: true
)
let encoder = JP3DEncoder(configuration: config)
_ = try await encoder.encode(volume)
let stats = await encoder.lastEncodingStatistics
print("Workers used: \(stats.peakConcurrentWorkers)")
print("Tile count:   \(stats.tileCount)")
```

**Common causes:**

| Cause | Fix |
|-------|-----|
| Too few tiles for cores | Use smaller tile size or larger volume |
| `maxConcurrentTileWorkers: 1` | Increase or remove limit |
| Volume too small | JP3D parallelism needs ≥ 8 tiles ideally |
| Debug build | Use `swift build -c release` |

---

### Compression Ratio Lower Than Expected

**Causes and typical ratios:**

| Issue | Expected Ratio | Actual | Fix |
|-------|---------------|--------|-----|
| Random/noise data | 1.0–1.5× | ~1.0× | Expected — noise is incompressible |
| Single-tile volume | 3×+ | 2–2.5× | Use more tiles to exploit inter-slice redundancy |
| Very small volume (<64³) | 3×+ | <2× | Small volumes have high header overhead |
| Wrong bit depth | 3×+ | <2× | Ensure `bitDepth` matches actual data range |

---

## Memory and Crash Issues

### EXC_BAD_ACCESS on Large Volume

**Likely cause:** Memory-mapped `Data` accessed after the mapped file was moved or deleted.

**Fix:**
```swift
// Load into memory, don't rely on mapping for encoding
let data = try Data(contentsOf: url)  // Loaded into RAM (safer for encoding)
// NOT: Data(contentsOf: url, options: .alwaysMapped)  // Risky if file changes
```

### Stack Overflow on Deep DWT

**Cause:** The DWT uses recursion; very deep decomposition levels can overflow the stack.

**Fix:** Reduce decomposition levels:
```swift
let config = JP3DEncoderConfiguration(
    compressionMode: .lossless,
    tiling: .default,
    decompositionLevelsXY: 3,  // Reduce from default 5
    decompositionLevelsZ: 2    // Reduce from default 3
)
```

---

## Lossless Verification Failures

### Lossless Round-Trip Produces Different Data

**Symptoms:**
- `decodedComponent.data != originalComponent.data` after lossless encode/decode
- PSNR is not infinite for `.lossless` or `.losslessHTJ2K`

**Diagnostic steps:**

1. Verify `result.isLossless == true` after encoding
2. Verify `decodedResult.isPartial == false`
3. Check that `signed` matches your data:
```swift
// If your DICOM data has signed voxels but you set signed: false,
// the colour transform may corrupt data
let component = J2KVolumeComponent(
    index: 0,
    bitDepth: 16,
    signed: true,   // ← MUST match actual data signedness
    ...
)
```

4. Check for byte-order issues (big-endian vs. little-endian input):
```swift
// JP3D expects big-endian multi-byte voxels
// If your source is little-endian 16-bit:
let leData: Data = ...  // little-endian source
var beData = Data(count: leData.count)
for i in stride(from: 0, to: leData.count, by: 2) {
    beData[i]     = leData[i + 1]  // swap bytes
    beData[i + 1] = leData[i]
}
```

---

## FAQ

**Q: Can JP3DDecoder decode a standard 2D J2K file?**
A: No. Use `J2KDecoder` from `J2KCodec` for 2D J2K/JP2 files. Use `JP3DDecoder.canDecode(_:)` to distinguish formats.

---

**Q: Does JP3D support floating-point voxels?**
A: Yes — use `bitDepth: 32` with `signed: true`. Lossless encoding of float data is supported. Lossy float encoding is experimental in 1.9.x.

---

**Q: How do I encode a volume larger than available RAM?**
A: Encode in region slabs and concatenate the results, or use a streaming-capable server pipeline. The tile-based design limits peak memory to one tile at a time, but the full volume must be accessible via `J2KVolumeComponent.data`.

---

**Q: Is JP3D compatible with DICOM JP2 lossless?**
A: JP3D produces a separate file type (`.jp3`/`.j3k`). It is not a drop-in replacement for DICOM per-frame J2K. Use standard `.lossless` encoding and verify with your DICOM system.

---

**Q: Why is my HTJ2K file larger than standard JPEG 2000?**
A: This is expected. HTJ2K's faster coder produces ~5–10% larger files than standard JPEG 2000 at equivalent quality. This is the inherent trade-off for speed.

---

**Q: Can I use JP3DEncoder from a `@MainActor` context?**
A: Yes — calling `await encoder.encode(volume)` from `@MainActor` is valid. The encoding work runs off the main thread inside the actor. The main thread is briefly involved for the call and return but not for the heavy computation.

---

**Q: How do I report a bug?**
A: File an issue on the J2KSwift GitHub repository with:
- J2KSwift version (`JP3DEncoder.version`)
- Platform and OS version
- Minimal reproducible code example
- Expected vs. actual behaviour
