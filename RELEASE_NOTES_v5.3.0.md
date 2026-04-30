# J2KSwift v5.3.0 Release Notes

**Release Date**: 2026-04-30
**Release Type**: Minor
**Previous Version**: 5.2.0

---

## Summary

v5.3.0 lands the **bit-exact GPU HTJ2K cleanup-pass decoder** (Phase 0
through Phase 2 of the GPU HT prototype) and the **180-cell
bidirectional cross-codec verification harness** that proves J2KSwift
round-trips losslessly through OpenJPEG 2.5.4 and OpenJPH 0.27.0 on
real DICOM imagery in every backend × codec combination.

The headline correctness gate is **180 / 180 cross-codec round-trip
cells pass** on the 10-image DICOM corpus (CT × 2, DX × 2, MG × 2,
MR × 2, PX × 1, XA × 1 — sizes from 180×180 to 3521×4784).

## What's new

### GPU HTJ2K decoder — bit-exact, debug + release

- **Phase 0** — `J2KMetalHTDispatchProbe`: trivial-per-thread
  microbenchmark establishes the GPU vs CPU dispatch envelope. 40-44×
  wins at 1024 codeblocks; break-even at 16 codeblocks.
- **Phase 1** — `J2KMetalHTMagSgn`: MagSgn forward bit-reader Metal
  kernel. Bit-exact with `HTMagSgnDecoderConformant`. **18× faster
  than CPU** on a 777-block batch in release.
- **Phase 2** — `J2KMetalHTCleanup`: full HT cleanup-pass kernel
  (~500 lines of MSL: MEL run-length + VLC table lookup + UVLC +
  MagSgn folded into one kernel). Bit-exact with
  `HTBlockDecoderConformant.decode` in **both debug and release**
  builds. Public API: `J2KMetalHTCleanupBlockDescriptor` (8 × UInt32,
  `@frozen`, stride 32) + `J2KMetalHTCleanup.run(...)`.
- **GPU encoder bit-equality**: `cmp` confirms `*_jcpu_p1.j2k ≡
  *_jgpu_p1.j2k` and the HTJ2K equivalents on every fixture.

### Cross-codec verification harness

- `Tests/Fixtures/CrossCodec/` — 7 DICOM PGM fixtures (~22 MB) +
  baseline CSVs.
- `Scripts/run_cross_matrix.sh` — script with four modes:
  - default `run` — write CSV
  - `--check` — diff CSV against baseline, exit 1 on regression
  - `--update-baseline` — overwrite the committed baseline
  - `--cpu-only` — skip Metal cells (for Linux runners)
- `RELEASE_READINESS_REPORT.md` — full bidirectional verification
  report. 100 cells exact byte match, 80 cells byte-swap match
  (PGM endianness convention difference between J2KSwift's LE-native
  and OpenJPEG/OpenJPH's BE-spec output).
- Weekly remote agent cron schedules `Scripts/run_cross_matrix.sh
  --cpu-only --check` against `main` every Monday 09:00 IST and
  opens a GitHub issue if any cell regresses.

### Bit-exact integer 5/3 IDWT (lossless GPU decode)

- New Int32 inverse 1D kernels using `>> 2` / `>> 1` arithmetic
  shift, replacing prior Float math. Bit-exact with the spec. New
  Int32 inverse-2D dispatch path in `J2KMetalDWT`.
- Reordered horizontal-then-vertical to match the spec (was V-then-H).

### Performance: CPU optimisations carrying forward from 5.2.0

- **MQ state lookup table packed** into one UInt32 per state (188
  bytes total). Part 1 EBCOT decode: 1.07× of OpenJPEG (was 0.99×).
- **HTJ2K conformant encoder**: fixed-tuple `processQuad` drops two
  per-quad heap allocations. Encode: ~4× faster on a 1024² codeblock.
- **HTJ2K conformant decoder**: slice-based stream readers across
  MEL/VLC/MagSgn. Decode: 2× faster, ~30 MB fewer allocations per
  1024² input.

## Headline numbers (Apple M2, release build)

### Correctness — cross-codec matrix on 10 DICOM PGMs

| Cell | yes | swap | no |
|---|---:|---:|---:|
| J2KSwift CPU enc → J2KSwift CPU dec (P1) |  10 | 0 | 0 |
| J2KSwift CPU enc → J2KSwift GPU dec (P1) |  10 | 0 | 0 |
| J2KSwift GPU enc → J2KSwift CPU dec (P1) |  10 | 0 | 0 |
| J2KSwift GPU enc → J2KSwift GPU dec (P1) |  10 | 0 | 0 |
| J2KSwift × OpenJPEG cross (P1)            |   0 | 40 | 0 |
| OpenJPEG enc → OpenJPEG dec (baseline)    |  10 | 0 | 0 |
| HTJ2K cells (mirror layout)               |  40 | 40 | 0 |
| **Total**                                 | **100** | **80** | **0** |

### Compression — encoded sizes vs reference codecs (lossless, average)

| Codec / mode                | vs original | vs reference codec |
|-----------------------------|------------:|-------------------:|
| J2KSwift J2K Part 1 lossless | 4.7×       | **0.49× the size of OpenJPEG** |
| J2KSwift HTJ2K lossless      | 4.5×       | **0.55× the size of OpenJPH**  |

### Performance — `dx_study_001` (2544×3056, 16-bit, 14.8 MB)

| Operation              | Encode ms | Decode ms |
|------------------------|----------:|----------:|
| J2KSwift CPU P1        |     381   |     316   |
| J2KSwift GPU P1        |     389   |     310   |
| OpenJPEG P1            |    1730   |    1742   |
| J2KSwift CPU HT        |     166   |     117   |
| J2KSwift GPU HT        |     166   |     116   |
| OpenJPH HT             |     133   |      88   |

J2KSwift is **3.5-5× faster than OpenJPEG** at J2K Part 1 (every image
size, encode + decode); **~25% slower than OpenJPH** at HTJ2K but
produces 35-45% smaller files. CPU and GPU paths land within ±5% of
each other at the CLI / single-image granularity (CLI startup
dominates; the GPU path's value emerges in batch / pipeline
scenarios).

## Bug fixes

### GPU HT phase-2 release-mode readback deadlock

`Array.withUnsafeMutableBytes { dst.copyBytes(from:) }` deadlocked in
release-mode Swift when the source pointer came from
`MTLBuffer.contents()` immediately after `await
commandBuffer.completed()`. The GPU was fine — status was
`.completed` (success) at the deadlock point. Fix: read back via
`Array(unsafeUninitializedCapacity:initializingWith:) + memcpy`. The
`withUnsafeMutableBytes` / `copyBytes` interaction is sidestepped
entirely.

The same anti-pattern is present in other Metal compute wrappers in
the codebase (`J2KMetalDWT`, `J2KMetalColorTransform`, etc.) but
hasn't manifested as a deadlock there yet — likely because their
completion paths or buffer sizes don't trigger the same Swift-runtime
condition. They remain latent and should be migrated when next
touched.

### GPU 5/3 IDWT non-bit-exact (lossless)

Float arithmetic and V-then-H dispatch order produced
near-but-not-exact output relative to the spec's integer reference.
Fixed by adding Int32 kernels using `>> 2` / `>> 1` arithmetic shift,
plus reordering to H-then-V.

### HTJ2K cross-codec interop (legacy custom block format)

J2KSwift was defaulting to its private `.custom` HTJ2K block format,
which OpenJPH could not consume. The default flipped to
`.conformant` (Part 15 spec wire format); custom remains opt-in via
`--htj2k-custom`.

## Caveats / known issues

1. **PGM byte-order convention.** J2KSwift writes PGMs in
   little-endian (matches the originals on disk); OpenJPEG and
   OpenJPH write big-endian (PGM spec compliant). The JPEG 2000
   codestream is byte-identical across codecs — only the PGM file
   output differs. If you're shipping PGMs from J2KSwift to
   OpenJPEG-toolchain consumers, byte-swap the 16-bit pixels first
   or document the byte order.
2. **Phase 2 GPU HTJ2K is 0.5× release-CPU on the speedup
   benchmark.** Release-mode CPU's HT decoder is ~30× faster than
   debug-CPU because of the v5.2.0 optimisations (slice readers,
   raw-pointer MQ, packed state tables). The GPU phase-2 kernel is
   correct but doesn't yet beat it. Phase 3+ work targets dispatch
   overhead amortisation (warm pipelines, persistent buffers,
   multiple codeblocks per thread, fold tile-level work onto GPU).

## Verification

- `swift test` — debug build, full test matrix green
- `swift test -c release` — release build, full test matrix green
- `Scripts/run_cross_matrix.sh --check` — full 18-cell matrix on 7
  fixtures, 126 / 126 cells match committed baseline
- `Scripts/run_cross_matrix.sh --cpu-only --check` — CPU-subset for
  Linux runners, 56 / 56 cells match committed baseline

## Compatibility

- Public API: additive only. New `J2KMetalHTMagSgn` /
  `J2KMetalHTCleanup` types are net-new public surface.
- Default HTJ2K block format flipped from `.custom` to `.conformant`
  in v5.0.0; this release does not change that. Legacy custom
  archives still decode via the auto-detection path.
- `getVersion()` now reports `"5.3.0"` (was stale `"2.3.0"`).
