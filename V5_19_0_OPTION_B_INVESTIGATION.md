# v5.19.0 Option B Investigation — Intra-Block Byte-Level Truncation

**Date:** 2026-05-04
**Status:** Investigation phase. Implementation NOT started — finding suggests pivot to a different
working approach.

## TL;DR

The v5.18.0 design doc proposed Option B (intra-block byte-level truncation in PCRD-opt) as a
candidate for closing the residual ~7 dB R-D gap on `.constantBitrate` HT-conformant lossy
workflows. Investigation during v5.19.0 implementation revealed Option B as designed
**doesn't work cleanly** — J2KSwift's decoder (and OpenJPH's, per the Part-15 spec) fills
truncated MagSgn regions with `0xFF` padding bytes, NOT zeros. For coefficients past the
truncation point that the VLC stream indicated as significant, this produces decoded magnitudes
of `(1 << m) - 1` (binary all-ones), which is **worse than no truncation** would have been.

Two paths forward, both need user signoff:

1. **Modify J2KSwift's decoder** to detect "MagSgn EOF reached for a coefficient VLC marked
   significant" and substitute zero-magnitude. This is a decoder-side bitstream-interpretation
   change. Risk: may break `ojph_expand` interop (which we hardened in v5.16.0). Multi-day work.

2. **Pivot to binary-search-on-qstep** (call it Option D). Build on v5.18.0's `.fixedQstep` mode
   by adding an outer loop that takes a `--bitrate X` target and binary-searches `qstep` until
   the achieved bpp matches. Bounded scope (~300 lines), doesn't touch decoder, gives users the
   convenience of `.constantBitrate` with the R-D quality of `.fixedQstep`. ~1 day.

Recommendation: **Option D** (binary-search-on-qstep) as v5.19.0. Defer Option B to v5.20.0+ if
Option D doesn't satisfy user workflows.

## Why Option B is harder than the v5.18.0 design doc claimed

### What the design doc said

> "The HT cleanup pass has only one truncation point per block. OpenJPH supports byte-level
> codeblock truncation via `block_decoder::trim_to`. Porting equivalent logic to J2KSwift is the
> v5.17.0 motivation. Estimated 5–8 days of work on the rate controller + tier-2 writer."

This was based on the Part-15 spec's allowance of truncation. The implementation complexity was
underestimated by missing the decoder-side semantics.

### What investigation found

Reading `Sources/J2KCodec/J2KHTConformantMagSgnCoder.swift:133-150`:

```swift
private mutating func refill() {
    while bits <= 32 {
        let byte: UInt8
        let absIdx = bytesStart + readIndex
        if absIdx < bytesEnd {
            byte = bytes[absIdx]
            readIndex += 1
        } else {
            byte = 0xFF             // ← KEY LINE
        }
        ...
    }
}
```

When the MagSgn stream is exhausted before all coefficients have been read, the decoder
substitutes `0xFF` bytes. Reading `m` bits from `0xFF` (after FF-unstuffing) gives `(1 << m) - 1`
— maximum-magnitude payload.

This is consistent with OpenJPH 0.27's `ojph_block_decoder.cpp` and the Part-15 spec: padded
bytes are 0xFF for arithmetic-coding compatibility.

For our truncation use case, we'd want "zero-fill on truncation" — but that's a different
semantic from what the spec defines. Implementing it requires:

1. **Encoder side**: emit truncated block; tier-2 writes K bytes instead of N.
2. **Decoder side**: when MagSgn would refill from out-of-bounds, ALSO check whether VLC has
   decoded coefficients beyond what MagSgn covered. For those coefficients, use zero magnitude
   (not `(1 << m) - 1`).
3. **Bitstream signaling**: there's no explicit "this block was truncated" marker — the decoder
   has to infer from byte count.

Step 2 is the hard part. The decoder currently doesn't know "how many coefficients should this
many bytes cover." It just reads as many bits as VLC says are needed, refilling 0xFF as needed.

### Why ojph_expand cross-decode is a concern

In v5.16.0 we hardened `ojph_expand` interop (`HTConformantLossyOpenJPHInteropTests` —
|Δ| < 0.5 dB between J2KSwift decode and ojph_expand decode). If J2KSwift modifies its decoder
to handle truncation specially, the bitstream J2KSwift produces (with truncated blocks) would
need both decoders to agree on the interpretation. They won't, by default.

To preserve interop, the encoder would need to emit blocks that BOTH decoders interpret the
same way — which means either no truncation (defeats the point) or a different signaling
mechanism that's spec-compliant.

## Better Option B (Option D): Binary-search-on-qstep

Build on v5.18.0's `.fixedQstep` mode. Add a new bitrate-mode case:

```swift
case constantBitrateViaQstep(
    bitsPerPixel: Double,
    tolerance: Double = 0.05,
    maxIterations: Int = 8)
```

Implementation:

```swift
// in J2KEncoder
public func encode(_ image: J2KImage) async throws -> Data {
    if case .constantBitrateViaQstep(let bpp, let tolerance, let maxIter) = config.bitrateMode {
        return try await encodeViaQstepSearch(image, targetBpp: bpp, tolerance: tolerance, maxIter: maxIter)
    }
    // ... existing path
}

private func encodeViaQstepSearch(_ image: J2KImage, targetBpp: Double, tolerance: Double, maxIter: Int) async throws -> Data {
    let pixelCount = image.width * image.height * image.componentCount
    let targetBytes = Double(pixelCount) * targetBpp / 8.0

    // Initial qstep estimate from calibration table.
    var qstep: Double = initialQstepGuess(targetBpp: targetBpp, bitDepth: image.components[0].bitDepth)
    var lower: Double = qstep / 100.0  // very fine
    var upper: Double = qstep * 100.0  // very coarse

    for iter in 0..<maxIter {
        var subConfig = config
        subConfig.bitrateMode = .fixedQstep(qstep: qstep)
        let encoded = try await encodeWithConfig(image, subConfig)
        let achievedBytes = Double(encoded.count)
        let ratio = achievedBytes / targetBytes
        if abs(ratio - 1.0) < tolerance {
            return encoded  // within tolerance, done
        }
        if achievedBytes > targetBytes {
            lower = qstep
            qstep = sqrt(qstep * upper)  // log-binary-search
        } else {
            upper = qstep
            qstep = sqrt(qstep * lower)
        }
    }
    // Final encode at converged qstep
    var subConfig = config
    subConfig.bitrateMode = .fixedQstep(qstep: qstep)
    return try await encodeWithConfig(image, subConfig)
}
```

Cost: 4-7 encode iterations per image (slow but parallelizable across images). Each iteration
is a full encode, so total time ≈ 4-7× the single-encode cost.

For a 512×512 lossless test image:
- Single encode: ~50 ms
- Binary-search encode: ~200-350 ms

Acceptable for batch workflows. Not ideal for real-time, but the use case is medical archival
where encode time isn't the bottleneck.

### Acceptance criteria for v5.19.0 Option D

1. New mode `.constantBitrateViaQstep(bpp:tolerance:)` ships with calibration and tests.
2. R-D matches OpenJPH within 0.5 dB at matched bpp (vs the 7 dB gap of `.constantBitrate`).
3. Convergence within 8 iterations on >95% of test images.
4. v5.14–v5.18 regression gates remain green.

### What Option D does NOT solve

`.constantBitrate` (the existing, non-iterative mode) still produces ~7 dB worse R-D than
EBCOT/OpenJPH. Users with strict bitrate compliance who want fast single-encode will still hit
this. They'd need to switch to `.constantBitrateViaQstep` (slower) or `.fixedQstep` (variable
bpp).

This is a documentation issue — make the v5.16.0 + v5.18.0 + v5.19.0 mode trade-offs clear in
the public API docs.

## Path forward

Pending user direction:

- **Confirm pivot to Option D**: ship v5.19.0 with `.constantBitrateViaQstep` (this doc's
  recommendation).
- **Or proceed with Option B** despite the decoder complications: multi-day work, requires
  decoder modification + interop verification + bitstream signaling. Higher risk.

Both options stay within the v5.18.0 design doc's spirit — closing the lossy R-D gap. Option D
ships in 1 day; Option B ships in 5–8 days with higher risk.
