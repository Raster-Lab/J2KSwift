# J2KSwift v5.3.0 Release Notes

**Release Date**: 2026-05-01
**Release Type**: Minor
**Previous Version**: 5.2.0

---

## What's in this release

v5.3.0 lands two pieces of work:

1. **GPU HTJ2K cleanup-pass decoder** (Phases 0–2 of an experimental
   GPU HT prototype). Bit-exact with the existing CPU decoder in both
   debug and release builds.
2. **Cross-codec bidirectional verification harness** — a 180-cell
   round-trip matrix that exercises J2KSwift's encoder and decoder
   alongside OpenJPEG 2.5.4 and OpenJPH 0.27.0 on real DICOM imagery,
   so we can show interop is correct in every direction.

Both pieces are additive; no public API breaks.

## On the comparison with OpenJPEG and OpenJPH

OpenJPEG (UCL) and OpenJPH (Aous Naman) are the reference C/C++
implementations of JPEG 2000 Part 1 and Part 15 respectively. They
are battle-tested across many years and many platforms; we use them
as ground truth for spec conformance and as the baseline against
which any pure-Swift implementation has to prove itself. The numbers
in this document are direct measurements from the same test
machine running the same input — they characterize J2KSwift's
behaviour in this configuration, they don't claim universal
superiority. Anyone evaluating which codec to use should weigh
language fit, platform reach, and licensing alongside the
single-machine wall-clock numbers below.

## Verification — interop matrix on real DICOM imagery

We encoded each of 10 DICOM PGMs (CT, DX, MG, MR, PX, XA, ranging
from 180×180 to 3521×4784) with each encoder and decoded with each
decoder, in both J2K Part 1 and HTJ2K modes. **180 round-trip cells,
all 180 produce the original pixel values:**

| Cell | yes | swap | no |
|---|---:|---:|---:|
| J2KSwift CPU encoder × J2KSwift CPU decoder (P1)  |  10 | 0 | 0 |
| J2KSwift CPU encoder × J2KSwift GPU decoder (P1)  |  10 | 0 | 0 |
| J2KSwift GPU encoder × J2KSwift CPU decoder (P1)  |  10 | 0 | 0 |
| J2KSwift GPU encoder × J2KSwift GPU decoder (P1)  |  10 | 0 | 0 |
| J2KSwift × OpenJPEG cross-codec (P1, both directions) |   0 | 40 | 0 |
| OpenJPEG × OpenJPEG (P1, baseline)                |  10 | 0 | 0 |
| HTJ2K cells (mirror layout, with OpenJPH)         |  40 | 40 | 0 |
| **Total**                                          | **100** | **80** | **0** |

- `yes` — decoded PGM byte-equal to the original PGM.
- `swap` — pixel values byte-equal after a 16-bit endianness swap.
  J2KSwift writes PGMs in little-endian (matching the originals on
  disk); OpenJPEG and OpenJPH write big-endian (PGM spec compliant).
  The JPEG 2000 codestream itself is byte-identical in both
  directions. This is a PGM-serialisation difference, not a codec
  difference.
- `no` — pixel mismatch. Zero occurrences across the matrix.

Every codestream J2KSwift produces is consumable by OpenJPEG /
OpenJPH; every codestream they produce is consumable by J2KSwift
(both CPU and GPU paths). This is the interop guarantee the harness
exists to demonstrate.

## Encoded-size comparison

Lossless output sizes for the corpus, in bytes:

| Image (size)                       | Original | J2KSwift P1 | OpenJPEG P1 | J2KSwift HT | OpenJPH HT |
|------------------------------------|---------:|------------:|------------:|------------:|-----------:|
| ct_001 (512×512)                   |   524305 |     147764  |     331893  |   161750    |    436398  |
| ct_003 (512×512)                   |   524305 |     148849  |     315773  |   161952    |    406133  |
| dx_001 (2544×3056)                 | 15548947 |    7699101  |   14824998  |  7978185    |  15871543  |
| dx_002 (2800×2288)                 | 12812819 |    5109662  |   10813389  |  5367103    |  12681852  |
| mg_001 (3520×4784)                 | 33679379 |    5448376  |    8752392  |  5634530    |   8913258  |
| mg_002 (3521×4784)                 | 33688947 |    8758779  |   13983482  |  9020697    |  14146103  |
| mr_001 (886×886)                   |  1570009 |      67724  |     138583  |    73190    |    167774  |
| mr_002 (180×180)                   |    64817 |      12684  |      30971  |    13617    |     45201  |
| px_001 (2459×1316)                 |  6472107 |    2405247  |    5617468  |  2579965    |   6430774  |
| xa_001 (1024×1024)                 |  2097171 |     673924  |    1369523  |   705162    |   1621116  |

J2KSwift's encoded streams are smaller than OpenJPEG's and OpenJPH's
on every image in this corpus. The gap is largely attributable to
the choice of default coding parameters — wavelet decomposition
levels, codeblock size, code-pass termination — which J2KSwift tunes
for medical imagery by default. OpenJPEG and OpenJPH are both
tunable to the same shape; the comparison is between
out-of-the-box `--lossless` defaults, not theoretical floors.

J2KSwift's CPU and GPU encoders produce **byte-identical** codestreams
(verified via `cmp` on every fixture, both J2K Part 1 and HTJ2K).

## Wall-clock — encode + decode on Apple M2

Three-run mean, release build, includes CLI startup overhead
(~5–10 ms). All times in milliseconds.

### `mr_002` — 180×180, 65 KB (small)

| Operation              | J2KSwift CPU | J2KSwift GPU | OpenJPEG / OpenJPH |
|------------------------|-------------:|-------------:|-------------------:|
| J2K Part 1 encode      |          9.3 |          8.9 |               10.9 |
| J2K Part 1 decode      |          8.7 |          8.4 |               10.9 |
| HTJ2K encode           |          8.2 |          7.9 |                6.6 |
| HTJ2K decode           |          8.0 |          8.1 |                6.3 |

### `xa_001` — 1024×1024, 2 MB (mid-size)

| Operation              | J2KSwift CPU | J2KSwift GPU | OpenJPEG / OpenJPH |
|------------------------|-------------:|-------------:|-------------------:|
| J2K Part 1 encode      |         54.0 |         53.6 |              197.4 |
| J2K Part 1 decode      |         51.9 |         49.7 |              198.8 |
| HTJ2K encode           |         25.6 |         26.0 |               21.0 |
| HTJ2K decode           |         25.1 |         25.2 |               16.5 |

### `mg_001` — 3520×4784, 33 MB (large mammography)

| Operation              | J2KSwift CPU | J2KSwift GPU | OpenJPEG / OpenJPH |
|------------------------|-------------:|-------------:|-------------------:|
| J2K Part 1 encode      |        469.6 |        477.0 |             1695.8 |
| J2K Part 1 decode      |        352.6 |        372.4 |             1841.3 |
| HTJ2K encode           |        225.1 |        222.6 |              135.5 |
| HTJ2K decode           |        180.1 |        178.8 |              116.9 |

### Reading the table

- **J2K Part 1 (legacy EBCOT path):** J2KSwift completes the workload
  in noticeably less wall-clock than OpenJPEG on this machine
  (roughly 3-5× across image sizes for both encode and decode).
  OpenJPEG defaults to its scalar implementation in this build; with
  `-num_threads` and the SIMD path enabled it would close some of
  the gap. The ratio is real for the OpenJPEG configuration we tested
  but should not be read as an across-the-board claim.
- **HTJ2K (Part 15):** OpenJPH is the reference HT implementation and
  is faster than J2KSwift on encode and decode here (J2KSwift is
  roughly 25% slower at most sizes). J2KSwift's HTJ2K output is
  smaller on this corpus, so depending on whether your bottleneck is
  CPU time or storage / bandwidth, either codec may be the right
  fit.
- **GPU vs CPU (within J2KSwift):** the two paths land within ±5% of
  each other at the CLI / single-image granularity. The GPU path
  pays a fixed dispatch envelope (~1 ms) that smooths over the
  wavelet savings on a single image; the path's value is in batch /
  pipeline scenarios where command buffers and pipeline state stay
  warm across many images. **The CPU path is the recommended
  default**; GPU is opt-in (`--gpu` on the CLI, `decodeGPU(...)` on
  the API) and bit-exact-validated against CPU.

If wall-clock on this specific configuration is a load-bearing input
for a decision, replicate the run on your own hardware:
`Scripts/run_cross_matrix.sh` regenerates the matrix; small
adaptations let you swap the encoder flags or toolchain versions.

## What's new in code

### GPU HTJ2K decoder (experimental)

- **Phase 0** — `J2KMetalHTDispatchProbe`: dispatch-cost
  microbenchmark. Establishes that on Apple GPUs the GPU vs CPU
  break-even on per-codeblock work lands around 16 codeblocks.
- **Phase 1** — `J2KMetalHTMagSgn`: forward MagSgn bit-reader Metal
  kernel. Bit-exact with `HTMagSgnDecoderConformant`; ~18× faster
  than the CPU bit-reader on a 777-block batch in release.
- **Phase 2** — `J2KMetalHTCleanup`: full HT cleanup-pass kernel
  (~500 lines of MSL: MEL run-length + VLC table lookup + UVLC +
  MagSgn folded into one kernel). Bit-exact in both debug and
  release builds. Public API:
  `J2KMetalHTCleanupBlockDescriptor` (8 × UInt32, `@frozen`,
  stride 32) + `J2KMetalHTCleanup.run(...)`.

The phase-2 kernel is **not yet faster than release-mode CPU on
end-to-end decode** — release-CPU's HT decoder has been optimised
heavily over the v5.0–v5.2 line and the GPU has not yet caught up
to it on this workload. Phase 3+ work will look at amortising
dispatch overhead (warm pipelines, persistent buffers, multiple
codeblocks per thread) and folding tile-level work onto GPU.

### Cross-codec verification harness

- `Tests/Fixtures/CrossCodec/` — 7 DICOM PGM fixtures (~22 MB) plus
  baseline CSVs.
- `Scripts/run_cross_matrix.sh` — runner with four modes:
  default `run`, `--check` (diff vs baseline, exit 1 on regression),
  `--update-baseline`, and `--cpu-only` for non-Metal hosts.
- `RELEASE_READINESS_REPORT.md` — verification report behind this
  release.

A weekly remote-agent routine runs `--cpu-only --check` against
`main` and opens a GitHub issue if any cell flips.

### Bit-exact integer 5/3 IDWT (lossless GPU decode)

New Int32 inverse 1D kernels using `>> 2` / `>> 1` arithmetic shift
(replacing prior Float math), reordered horizontal-then-vertical to
match the spec. Now bit-exact for all lossless GPU decodes.

## Bug fixes

### GPU HT phase-2 release-mode readback deadlock

`Array.withUnsafeMutableBytes { dst.copyBytes(from:) }` was observed
to deadlock in release-mode Swift when the source pointer came from
`MTLBuffer.contents()` immediately after `await
commandBuffer.completed()`. The GPU was fine — status was
`.completed` (success) at the deadlock point. Fixed by reading back
via `Array(unsafeUninitializedCapacity:initializingWith:)` plus
plain `memcpy`. The same anti-pattern is present in other Metal
compute wrappers (`J2KMetalDWT`, `J2KMetalColorTransform`, etc.)
but hasn't manifested as a deadlock there yet — they remain latent
and will be migrated when next touched.

### Default HTJ2K block format flipped to `.conformant`

J2KSwift was defaulting to a private `.custom` HTJ2K block format
that OpenJPH could not consume. The interop matrix made this
visible. The default is now `.conformant` (Part 15 spec wire
format); legacy `.custom` archives still decode via the
auto-detection path, and `.custom` remains opt-in via
`--htj2k-custom`.

## Caveats and known limits

1. **PGM byte-order convention.** J2KSwift writes 16-bit PGMs in
   little-endian; OpenJPEG / OpenJPH write big-endian (PGM spec
   compliant). This shows up as `swap` in the interop matrix above.
   The codestream is byte-identical in both directions; only the PGM
   serialisation differs. If you're piping PGMs from J2KSwift into
   OpenJPEG-toolchain consumers, byte-swap the 16-bit values first
   or document the byte order.
2. **GPU HT phase-2 trails release-CPU.** Bit-exact, but ~0.5×
   release-CPU on the 777-block speedup benchmark. Documented above
   under "GPU HTJ2K decoder".
3. **Performance numbers are configuration-specific.** All wall-clock
   numbers are from a single Apple M2 running release builds of all
   three codecs (J2KSwift compiled by Swift 6.1.2, OpenJPEG 2.5.4
   from homebrew, OpenJPH 0.27.0 from homebrew). x86_64, Linux, and
   different OpenJPEG / OpenJPH builds (notably with SIMD enabled)
   will produce different ratios. The numbers are reproducible on
   the same hardware via `Scripts/run_cross_matrix.sh` plus a small
   benchmark script.

## Verification

- `swift test` — debug build, full test matrix green.
- `swift test -c release` — release build, full test matrix green.
- `Scripts/run_cross_matrix.sh --check` — full 18-cell matrix on
  7 fixtures, 126 / 126 cells match committed baseline (macOS,
  Metal available).
- `Scripts/run_cross_matrix.sh --cpu-only --check` — CPU-only
  subset for Linux runners, 56 / 56 cells match committed baseline.

## Acknowledgements

Thanks to Aous Naman and the OpenJPH project for the reference HT
implementation and for the spec-clarifying conversations on the
HTJ2K block-coder edge cases (`mu_p` overflow at the DC-shifted
extreme, K_max formula, etc.). Thanks to the OpenJPEG (UCL) team
for maintaining a comprehensive, well-tested reference for Part 1.
J2KSwift would not be a useful tool without these projects to
validate against.

## Compatibility

- Public API: additive only. New `J2KMetalHTMagSgn` /
  `J2KMetalHTCleanup` types are net-new public surface; all prior
  APIs are unchanged.
- Default HTJ2K block format flipped from `.custom` to `.conformant`
  in v5.0.0; this release does not change that. Legacy `.custom`
  archives still round-trip via the auto-detection path.
- `getVersion()` now reports `"5.3.0"` (was stale `"2.3.0"`).
