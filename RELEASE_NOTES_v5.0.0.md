# J2KSwift v5.0.0 Release Notes

**Release Date**: _In progress_ (see `docs/HTJ2K_PART15_PLAN.md`)
**Release Type**: Major
**Previous Version**: 4.0.0

---

## Summary

v5.0.0's headline deliverable is an ISO/IEC 15444-15 (HTJ2K) conformant
block coder that is **bit-stream compatible with OpenJPH 0.26+**.

v4.x shipped an in-house HT block layout that round-trips with itself
but is not decodable by OpenJPH, OpenJPEG Part-15, or any other
conformant codec. For medical PACS deployment, OpenJPH is the
canonical HT reference decoder, so being "not decodable by OpenJPH" is
the opposite of a feature. v5.0.0 closes that gap.

The custom v4.x block format stays reachable behind a configuration
flag for backward compatibility and benchmark comparison.

---

## Highlights

### ISO/IEC 15444-15 (HTJ2K) conformance — scalar path

- Full port of OpenJPH 0.26's scalar HT block encoder and decoder:
  - FF-stuffed MEL coder (13-state exponent table matching the standard).
  - 2048-entry VLC codebooks (`vlc_tbl0`, `vlc_tbl1`) derived from
    ITU T.814 `table0.h` / `table1.h` raw data.
  - 75-entry UVLC (U-value) codebook with prefix/suffix/extension
    encoding.
  - MagSgn forward bit coder with FF-stuff and the standard
    pad-then-drop-if-0xFF terminate rule.
  - Cleanup-pass orchestrator walking 4-sample quad pairs with
    neighborhood context (c_q, rho, eps, kappa) propagation.
  - Scup-trailer block assembly and parse (12-bit interface locator
    word split across the last two bytes of the block).

- Reference decoder using source-table linear search rather than the
  fast 1024-entry reverse lookup. Trades decode speed for simplicity
  and direct parity with the encoder side. The OpenJPH fast tables
  are a v5.x optimization.

### Configuration

- `J2KEncodingConfiguration.htj2kBlockFormat: HTBlockFormat` selector:
  - `.custom` (default, preserved from v4.x) — legacy J2KSwift format,
    not Part-15 conformant.
  - `.part15` — ISO conformant format.
- Default flips to `.part15` in v5.0.0's final release, gated on
  OpenJPH bidirectional cross-codec validation (M7).

### Testing

- 60+ new Part-15 tests covering:
  - Bit-stream emitter FF-stuff edge cases (forward + reverse).
  - MEL coder round-trip (sparse, dense, all-zeros, all-ones).
  - VLC / UVLC codebook construction and lookup.
  - MagSgn coder round-trip with 50 randomized trials.
  - Block layout Scup round-trip + boundary cases (scup in range
    [2, 4079]).
  - Cleanup-pass encoder structural tests across 1x1 through 16x8
    block dimensions.
  - Multi-row self round-trip with scattered bin-centered samples.
  - Fuzz testing: 50 seeded trials over random dimensions and
    sparse sample placement.

---

## Migration

### For v4.x callers

No migration needed at default settings — `J2KEncodingConfiguration()`
still selects the custom format. Existing codestreams continue to
round-trip exactly as before.

### For OpenJPH interop

Opt in with:

```swift
let config = J2KEncodingConfiguration(
    useHTJ2K: true,
    htj2kBlockFormat: .part15
)
```

Once v5.0.0 ships, the same code becomes the default.

---

## Known limitations (v5.0.0 scope)

- **SIMD paths are out of scope.** v5.0.0 targets scalar conformance
  only. SSSE3/AVX2/AVX512 block coders arrive in a v5.x point release.
- **Fused MEL/VLC terminate byte optimization** is skipped; each
  stream terminates independently for a 1-byte/block overhead versus
  OpenJPH. Functionally conformant but not byte-minimal.
- **Decoder uses source-table linear search** (O(n) per codeword)
  rather than the fast 1024-entry lookup. Correctness before speed.

---

## Compatibility matrix

| Encoder  | Decoder  | Interop        |
|----------|----------|----------------|
| J2KSwift (custom)  | J2KSwift (custom)  | ✅ lossless    |
| J2KSwift (part15)  | J2KSwift (part15)  | ✅ lossless    |
| J2KSwift (part15)  | OpenJPH 0.26+      | 🟡 in-progress (M7 validation) |
| OpenJPH 0.26+      | J2KSwift (part15)  | 🟡 in-progress (M7 validation) |
| J2KSwift (custom)  | OpenJPH            | ❌ not supported (by design)    |

---

## Milestone history

Development tracked on branch `feature/htj2k-part15-conformance`:

- M1 — Bit-stream emitters (forward MSB + reverse LSB with FF-stuff).
- M2 — MEL coder with OpenJPH run semantics.
- M3 — VLC + UVLC codebooks.
- M4 — MagSgn forward bit coder.
- M5a — Block layout with Scup trailer.
- M5b — Cleanup-pass codeblock encoder.
- M5c — Reference decoder with correct FF-unstuff.
- M6 — `HTBlockFormat` configuration flag.
- M7 — OpenJPH cross-codec validation _(pending)_.
- M8 — Flip default + finalize docs _(pending)_.
