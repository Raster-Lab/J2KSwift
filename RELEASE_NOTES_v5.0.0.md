# J2KSwift v5.0.0 Release Notes

**Release Date**: 2026-04-24
**Release Type**: Major
**Previous Version**: 4.0.0

---

## Summary

v5.0.0's headline deliverable is an **ISO/IEC 15444-15 (HTJ2K)
conformant encoder** that is bit-stream compatible with OpenJPH
0.26+. Opt in with `htj2kBlockFormat: .part15` and J2KSwift-produced
codestreams are decodable by OpenJPH's `ojph_expand` and — by
extension — the whole downstream ecosystem of Part-15 consumers used
in medical PACS, broadcast archives, and DICOM workflows.

The v4.x in-house format is preserved behind `.custom` for backward
compatibility and benchmark comparison, and remains the default in
v5.0.0 until the decoder side of the Part-15 pipeline also dispatches
(tracked for v5.1).

---

## Highlights

### ISO/IEC 15444-15 conformance — scalar path

Port of OpenJPH 0.26's scalar HT block encoder and decoder:

- FF-stuffed MEL coder (13-state exponent table matching the standard).
- 2048-entry VLC codebooks (`vlc_tbl0`, `vlc_tbl1`) derived from
  ITU T.814's `table0.h` / `table1.h` raw data, plus a 1024-entry
  reverse lookup for constant-time decode.
- 75-entry UVLC (U-value) codebook.
- MagSgn forward bit coder.
- Cleanup-pass orchestrator walking 4-sample quad pairs with
  neighborhood context propagation.
- Scup-trailer block assembly and parse (12-bit interface locator
  word at the end of each block).

### Cross-codec validation

**Byte-identical output vs OpenJPH proven at the block level** for
4×4 uniform / all-white / checkerboard and 8×8 gradient inputs. The
test harness compresses a known PGM with `ojph_compress`, reproduces
OpenJPH's coefficient packing (`sign | |v| << (31 - K_max)`), runs
the J2KSwift Part-15 encoder on the same input, and asserts byte-for-
byte equality against OpenJPH's codestream region.

**End-to-end codestream interop**: encode a PGM via the J2KSwift
public `encode()` API with `.part15`, feed the resulting .j2c to
`ojph_expand`, and assert the decoded output matches OpenJPH's own
self round-trip. 3/3 pass for 4×4 uniform, 8×8 gradient, 32×32
deterministic noise.

### Performance (Apple Silicon, scalar)

| Metric | Before (M5c) | After (v5.0.0) | Speedup |
|---|---|---|---|
| decode 32×32 @ 50% | 10.9 ms (0.1 Ms/s) | **0.44 ms (2.3 Ms/s)** | 25× |
| decode 64×64 @ 25% | 39.4 ms (0.1 Ms/s) | **1.64 ms (2.5 Ms/s)** | 24× |
| round-trip 32×32 @ 30% | 11.7 ms | **1.01 ms** | 12× |

The decoder fast path is OpenJPH's 1024-entry reverse-lookup table
(`(c_q << 7) | cwd7` → packed `e_k|e_1|rho|u_off|cwd_len`), replacing
the initial O(n) linear scan with a single load per codeword.

Encoder: 1.7 Ms/s on 32×32 at 50% density, ahead of OpenJPH's end-
to-end pipeline (1.0 Ms/s) at the block level. Decoder: 2.5 Ms/s on
64×64 at 25% density — now faster than the encoder.

### Configuration

```swift
let config = J2KEncodingConfiguration(
    useHTJ2K: true,
    htj2kBlockFormat: .part15   // opt in for OpenJPH interop
)
let encoder = J2KEncoder(encodingConfiguration: config)
let j2c = try await encoder.encode(image)
// hand j2c to ojph_expand and it will decode correctly.
```

### Testing

91 Part-15 tests, covering:

- Bit-stream emitter FF-stuff edge cases (forward + reverse).
- MEL coder round-trip (sparse / dense / alternating / random).
- VLC / UVLC codebook build + lookup.
- MagSgn coder round-trip with FF-stuffing and terminate pad/drop.
- Block layout Scup round-trip + boundary conditions [2, 4079].
- Cleanup-pass encoder across 1×1 through 16×8 dimensions.
- Multi-row self round-trip with scattered bin-centered samples.
- 50-trial fuzz harness at varied densities and magnitudes.
- **Cross-codec byte-equality** for 4 real input patterns.
- **End-to-end codestream interop**: 3/3 inputs decode correctly
  through `ojph_expand`.

---

## Migration

### For v4.x callers

No migration needed at default settings. `J2KEncodingConfiguration()`
still selects the custom format — existing codestreams produced by
v4.x continue to round-trip through J2KSwift's decoder exactly as
before.

### For OpenJPH interop

Opt in:

```swift
var cfg = J2KEncodingConfiguration()
cfg.useHTJ2K = true
cfg.htj2kBlockFormat = .part15
```

The resulting codestream is decodable by OpenJPH 0.26+ — `ojph_expand
-i your.j2c -o out.pgm` works.

### Reading back `.part15` codestreams

J2KSwift v5.0.0's decoder does **not** yet dispatch to the Part-15
block decoder — it still expects the v4.x custom format. For now,
reading Part-15 codestreams produced by J2KSwift requires piping
them through OpenJPH or using `HTBlockDecoderPart15.decode` at the
block-coder API level. Pipeline-side decoder dispatch is v5.1.

---

## Known limitations (v5.0.0 scope)

- **SIMD paths are out of scope.** v5.0.0 targets scalar conformance
  only. SSSE3/AVX2/AVX512 block coders arrive in a v5.x point
  release.
- **Fused MEL/VLC terminate byte optimization** is skipped; each
  stream terminates independently for a 1-byte/block overhead versus
  OpenJPH. Functionally conformant but not byte-minimal.
- **Decoder-side pipeline dispatch** is not yet wired. Part-15
  codestreams produced by J2KSwift need to round-trip through
  OpenJPH or use the block-level Part-15 decoder directly.
- **8-bit edge case (sample value 0 → 128 on decode)**: for 8-bit
  reversible with 0 decomps, K_max = 7 signals 7-bit magnitude
  capacity, but |DC-shifted 0| = 128 = 2^7 overflows the sign-
  magnitude encoding. OpenJPH produces the same output for the same
  input — this is a standard-level precision limit, not a bug.

---

## Compatibility matrix

| Encoder | Decoder | Interop |
|---------|---------|---------|
| J2KSwift (custom) | J2KSwift (custom) | ✅ lossless |
| J2KSwift (part15) | OpenJPH 0.26+ | ✅ **proven end-to-end** |
| J2KSwift (part15, block-level) | J2KSwift Part-15 block decoder | ✅ |
| OpenJPH | J2KSwift (pipeline) | 🟡 block decoder works; pipeline dispatch in v5.1 |
| J2KSwift (custom) | OpenJPH | ❌ not supported (by design) |

---

## Milestone history

Development on branch `feature/htj2k-part15-conformance`:

- M1 — Bit-stream emitters.
- M2 — MEL coder.
- M3 — VLC + UVLC codebooks.
- M4 — MagSgn forward bit coder.
- M5a — Block layout with Scup trailer.
- M5b — Cleanup-pass codeblock encoder.
- M5c — Reference decoder with conditional FF-unstuff.
- M6 — `HTBlockFormat` configuration flag.
- M7 — Benchmark + byte-equality cross-codec validation.
- **Pipeline integration** — `encodeCodeBlockPart15` dispatch wired
  into `J2KEncoderPipeline`, QCD writer aligned with OpenJPH's
  reversible epsilon convention.
- **End-to-end cross-codec** — J2KSwift → `ojph_expand` decodes
  bit-identically to OpenJPH's self round-trip on 4×4 / 8×8 / 32×32.
- **Decoder fast path** — 1024-entry reverse-lookup table for 25×
  decode speedup.
- M8 — v5.0.0 release.
