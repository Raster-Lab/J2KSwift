# HTJ2K (ISO/IEC 15444-15) Conformance Plan — v5.0.0

**Target**: full Part-15 (HTJ2K) block-coder conformance with bit-exact
interop against OpenJPH 0.26+.

**Status**: scoped 2026-04-24. Work branch: `feature/htj2k-part15-conformance`.

---

## Why v5.0.0

v4.0.0 ships J2KSwift's HTJ2K fast path using a **custom, non-standard**
per-block format: `[melLen:2 | vlcLen:2 | magsgnLen:2 | MEL | MagSgn |
VLC(reversed)]`. This works for J2KSwift self round-trip but cannot be
decoded by OpenJPH or any other Part-15 conformant codec. The gap is
structural, not cosmetic — the MEL thresholds, VLC codebook, MagSgn
predictor, byte stuffing, and block layout all differ from the
standard.

For medical PACS deployment, "OpenJPEG literally can't read this" is
only a differentiator if **OpenJPH CAN read our output**. v5.0.0 closes
that gap so J2KSwift becomes a drop-in upgrade path for institutions
already deploying OpenJPH.

Scope estimate: **~2 weeks of focused work**.

---

## Reference implementation

OpenJPH v0.26.3 checked out at `/private/tmp/openjph/src/core/coding/`:

| Concern | File |
|---|---|
| Scalar encoder | `ojph_block_encoder.cpp` (1523 lines) |
| Scalar 64-bit decoder | `ojph_block_decoder64.cpp` (1662 lines) |
| Common constants | `ojph_block_common.h`, `ojph_block_common.cpp` |
| VLC / U-value tables | `table0.h` (443 lines), `table1.h` (357 lines) |

Port from the scalar paths first (no SIMD); SSSE3/AVX2/AVX512 variants
stay out of scope for v5.0.0.

---

## Milestones

Each milestone is independently testable against OpenJPH. Don't move on
until cross-codec validation passes for the milestone's scope.

### M1 — Bit-stream scaffolding (1 day)

**Goal**: FF-stuffed forward bit writer + reverse FF-stuffed bit writer
that match OpenJPH's byte-level output on trivial inputs.

- Port `mel_encoder::emit_bit()` byte-emit rules (FF-stuff when emitting
  `0xFF` followed by any other byte starting with `1`).
- Port reverse VLC writer (writes from block end backwards, reverse
  FF-stuffing so any `0xFF` in the reverse stream has trailing `1`).
- Unit tests: given known bit sequences, assert identical byte output
  to hand-computed expected values.

Files to add: `J2KHTBitStreamPart15.swift`. Keep everything under a
`Part15` suffix so it coexists with the existing custom format during
migration.

### M2 — MEL coder (1–2 days)

**Goal**: J2KSwift MEL encoder output is byte-for-byte identical to
OpenJPH's on random run-length inputs.

- Port `mel_tbl` (13-entry threshold table) from OpenJPH.
- Port the MEL state machine (`mel_encoder::encode_run_length`).
- Port the MEL decoder inverse.
- Unit tests: encode random run-length sequences, decode with
  `/opt/homebrew/bin/ojph_expand`-equivalent API or in-process OpenJPH
  if we get bindings.

Files to add: `J2KHTMELCoderPart15.swift`.

### M3 — VLC coder with U-value (3–4 days)

**Goal**: Match OpenJPH's cleanup-pass VLC output for 4-sample quads
(the dominant code path).

- Port `table0.h` and `table1.h` verbatim. These are large static
  lookup tables — line-for-line Swift translation as `[UInt16]` /
  `[UInt32]` literals.
- Port U-value unary + suffix-bit encoding
  (`vlc_tbl0`/`vlc_tbl1` selection, encoded as unary prefix + k-bit
  suffix).
- Port 4-sample quad grouping (scan order within the 32×32 codeblock).
- Decoder: reverse lookup with the same tables.
- Unit tests: 32×32 HH/HL/LH/LL blocks with known coefficient patterns;
  assert round-trip matches OpenJPH.

Files to add: `J2KHTVLCCoderPart15.swift`,
`J2KHTPart15Tables.swift`.

### M4 — MagSgn with neighborhood predictor (2–3 days)

**Goal**: Match OpenJPH's MagSgn stream output byte-for-byte.

- Port the U-value extraction of MagSgn bit positions
  (`ojph_block_encoder::encode_magsgn`).
- Port the neighborhood context predictor (4 neighbors N, NE, NW, W
  from already-coded positions; context derived from
  `ρ_n + ρ_ne + ρ_nw + ρ_w`).
- Decoder inverse.
- Unit tests: randomized coefficient arrays, round-trip with OpenJPH
  on both directions.

Files to add: `J2KHTMagSgnCoderPart15.swift`.

### M5 — Block layout with Scup trailer (1 day)

**Goal**: Assemble the standard Part-15 block payload:
`MagSgn | … | VLC_reversed | Scup(12 bits)`.

- Port the Scup assembly (12 bits split as high-4 + low-8 in the last
  2 bytes of the block, encoding `len_vlc_minus_one`).
- Wire M1–M4 into a `HTBlockEncoderPart15` / `HTBlockDecoderPart15`.
- Reuse existing SigProp/MagRef encoder where the algorithm is already
  Part-15 compliant (audit — likely needs light rework).

### M6 — Pipeline integration behind a flag (1 day)

**Goal**: Encoder can emit either custom or Part-15 format; decoder
can parse either. Default stays custom until M7 passes.

- Add `J2KEncodingConfiguration.htj2kBlockFormat: HTBlockFormat`
  (`.custom` | `.part15`), default `.custom` for backward compat.
- Auto-detect on decode (Part-15 streams have no 6-byte length header;
  use codestream marker + block-length signaling to disambiguate).
- Existing tests continue to pass unchanged.

### M7 — Cross-codec validation (2–3 days)

**Goal**: OpenJPH bidirectional interop for all 7 configs in
`testHTJ2KvsOpenJPH`.

- J2KSwift-Part15 encoded → `ojph_expand` decode → bit-exact roundtrip
  for lossless; PSNR within 0.1 dB for lossy.
- `ojph_compress` encoded → J2KSwift-Part15 decode → same criteria.
- Iterate on M2–M5 until the full matrix passes.

### M8 — Flip default + docs (0.5 day)

- `htj2kBlockFormat` default → `.part15`.
- Remove "custom format" known-limitation from README.
- Update RELEASE_NOTES_v5.0.0.md to claim Part-15 conformance.
- Keep `.custom` format reachable for backward compat and benchmarking.

---

## Success criteria (v5.0.0 release gate)

1. All existing tests pass unchanged (no regression on Part-1 path).
2. `testHTJ2KvsOpenJPH` passes bidirectional cross-decode on 7/7 configs.
3. ISO/IEC 15444-15 conformance test suite passes (to be located /
   added if not already).
4. No claim of Part-15 conformance before this gate is met.

---

## Non-goals for v5.0.0

- SIMD-optimized block coder (SSSE3/AVX2/AVX512 equivalents).
  Scalar-only is the v5.0.0 bar; perf tuning is v5.x.
- Dropping the custom fast-path format. It stays reachable behind the
  config flag for J2KSwift-peer-to-peer traffic and benchmark
  comparisons.
- HT-Block performance parity with OpenJPH. v5.0.0 targets
  **conformance**, not speed.
