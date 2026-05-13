# J2KSwift v5.20.0 — GPU 9/7 lossy decode correctness fix (medical-grade critical)

**Release date:** 2026-05-04
**Theme:** Investigation that started as "ratify GPU 9/7 lossy decode" surfaced a
medical-grade-critical correctness defect: `decodeGPU(_:)` and `decodeWithGPUHT(_:)` for 9/7 lossy
produce dramatically different output from CPU. Max abs diff ~45,000 in 16-bit space, average
diff ~19,000 — far beyond Float-vs-Double precision tolerance. v5.20.0 forces 9/7 lossy through
the CPU IDWT until the underlying Metal kernel bug is identified and fixed.

## The framing

The v5.x series shipped GPU HT entropy decode (v5.3–v5.14) and GPU IDWT for 5/3 lossless. 9/7
lossy decode was always supposed to take the GPU IDWT path too — `J2KMetalDWT` exposes
`.irreversible97` as a configurable filter, and `applyInverseWaveletTransformGPU` selects it for
9/7 codestreams.

Investigation for this release started by asking *"how much speedup do we get from GPU 9/7 lossy
decode?"* The first decode-path comparison surfaced something unexpected.

## What we found

Encoding `Tests/Fixtures/CrossCodec/ct_study_001_instance_000001.pgm` (512×512 16-bit CT) to a
lossy 9/7 HT-conformant codestream at 4 bpp, then decoding three ways:

| Decode path | Max abs diff vs CPU | Avg diff vs CPU |
|---|---:|---:|
| `decode(_:)` (CPU baseline) | 0 | 0 |
| `decodeGPU(_:)` | **45,276** | **19,211** |
| `decodeWithGPUHT(_:)` | **45,276** | **19,211** |

GPU and GPU-HT produce **identical** errors, which means the bug is in the **GPU IDWT** stage
(both paths share that). It's not in GPU HT entropy decode (that one's known-correct via
v5.15.0/v5.16.0 regression matrices).

For comparison: Float-vs-Double precision divergence in IDWT should produce max abs diff < 32
LSB (5 bits at 16-bit). 45,000 is in the same order of magnitude as the 16-bit dynamic range —
the GPU output is essentially garbage on this input.

## What v5.20.0 ships

### Fix — gate GPU IDWT to skip 9/7

`Sources/J2KCodec/J2KDecoderPipeline.swift:applyInverseWaveletTransformGPU` now falls back to
the CPU IDWT for any codestream with `waveletFilter == .irreversible97`:

```swift
// v5.20.0 medical-grade gate: GPU 9/7 (irreversible) IDWT
// currently diverges from the CPU reference by max ~45000 in
// 16-bit space (avg ~19000). Far beyond Float-vs-Double
// precision tolerance — there's an unidentified correctness
// bug in the GPU lossy IDWT kernel chain. Until it's fixed,
// force 9/7 lossy through the CPU path.
if case .irreversible97 = metadata.configuration.waveletFilter {
    return try await applyInverseWaveletTransform(subbands, metadata: metadata)
}
```

After the gate, `decodeGPU(_:)` and `decodeWithGPUHT(_:)` produce **identical** output to
`decode(_:)` for 9/7 lossy. Lossless 5/3 (reversible) GPU IDWT is unaffected — it's bit-exact
and gated by v5.7+ regression tests.

### Regression gate

`Tests/J2KCodecTests/J2KGPULossy97DivergenceTests.swift` —
`testBisectDecodePaths` runs all three decode paths and asserts max abs diff is **exactly 0**
between CPU and either GPU path. Any future change that removes the v5.20.0 gate without fixing
the underlying GPU IDWT kernel will fail this gate.

## Performance impact

`decodeGPU(_:)` and `decodeWithGPUHT(_:)` for 9/7 lossy now take the CPU IDWT path. Performance
matches `decode(_:)` exactly. Pre-v5.20.0 these calls produced corrupt output; post-v5.20.0 they
produce correct output at CPU IDWT speed.

For 5/3 lossless, GPU IDWT is unchanged — the v5.7+ Int32 GPU path is bit-exact and remains
active. Lossless GPU performance (the original v5.x acceleration target) is unaffected.

## What this means for users

If you've been calling `decodeGPU(_:)` or `decodeWithGPUHT(_:)` on 9/7 lossy codestreams, your
previous output was likely corrupt (~19k LSB average error in 16-bit space). After v5.20.0:

- **Decode output is now correct** for 9/7 lossy via either GPU entry point.
- Decoded files produced before v5.20.0 with these paths should be re-decoded.
- Stored 9/7 lossy J2K codestreams are unaffected (the bug was decode-only).

## Carryover from v5.14–v5.19.1

All regression gates remain green. The new v5.20.0 gate is additive.

## Known issues / future work

- **GPU IDWT for 9/7 is broken** and currently disabled. Root cause not yet identified — could
  be Metal kernel precision, dequantization mismatch, or subband layout. Fixing it is a
  v5.21.0+ effort once we have time to bisect the kernel chain.
- Until fixed, 9/7 lossy decode runs at CPU speed regardless of which decode entry point is
  called. Performance for 9/7 lossy on the GPU acceleration path is the v5.21.0 motivation.

## Reproducing

```bash
# v5.20.0 regression gate — verifies the fix:
swift test --filter J2KGPULossy97Divergence

# Manual bisection on a real CT image:
swift test --filter J2KGPULossy97Divergence
# Expected output: GPU vs CPU max=0 avg=0 (gate active and working).
# Pre-v5.20.0 output: GPU vs CPU max=45276 avg=19211 (gate missing or kernel bug).
```

## Lesson

The v5.20.0 plan was "GPU 9/7 lossy decode" — measure speedup, document caveats, ship. The
investigation step caught a silent data-corruption defect that was already shipping in v5.5+
whenever a caller invoked `decodeGPU(_:)` or `decodeWithGPUHT(_:)` on a lossy 9/7 codestream.

Without the bisection test surfacing it, the bug would have stayed silent: existing tests were
encoding round-trip (where errors compound but aren't directly observable), or were focused on
HT conformant correctness (where the GPU 9/7 IDWT issue is downstream of the HT decode they
test).

The same shape of correctness audit as v5.14.x byte-order, v5.15.0/v5.16.0 HT conformant, and
v5.17.0 PNG filter classes: when an in-house encoder/decoder pair share an assumption with each
other but diverge from the spec, the bug is invisible until something breaks the symmetry.
v5.20.0's bisection broke the symmetry by comparing GPU vs CPU on the same codestream.

The actual GPU IDWT fix is deferred. Locking in the safety gate is the v5.20.0 deliverable.
