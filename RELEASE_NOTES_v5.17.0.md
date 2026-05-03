# J2KSwift v5.17.0 — Medical-grade hardening: RGB non-pow2 + DICOMKit CI + PNG filter recovery

**Release date:** 2026-05-03
**Theme:** Compound correctness gains. Each of v5.15.0 (lossless conformant audit) and v5.16.0
(lossy bitstream interop fix) added one new regression floor; v5.17.0 adds three more across the
non-pow2 RGB matrix, the DICOMKit downstream consumer, and PNG output efficiency.

## The framing

After v5.15.0 ratified single-component lossless HT conformant non-pow2 (11,889 cells) and v5.16.0
fixed lossy bitstream conformance, the lossless conformant story for medical imaging was solid for
grayscale workloads. v5.17.0 closes three smaller-but-real coverage gaps:

1. **RGB lossless conformant non-pow2** — pathology, dermatology, ophthalmology use RGB. v5.15.0
   gates didn't exercise it.
2. **DICOMKit downstream consumer** — the production consumer's build status was checked manually
   each release; nothing automatically caught J2KSwift API breaks at PR time.
3. **PNG output size** — v5.14.2 disabled all PNG filters (filter type 0 / None) after catching a
   bug in the Sub filter. The size penalty was documented as a known issue. v5.17.0 reimplements
   Sub/Up/Average/Paeth with proper ORIGINAL-byte semantics + MAE heuristic for filter selection.

## What's new

### Phase 1 — DICOMKit downstream CI gate

`.github/workflows/dicomkit-downstream.yml` is a new GitHub Actions workflow that runs on every
PR / push:

1. Checks out J2KSwift at the PR commit.
2. Checks out DICOMKit (`Raster-Lab/DICOMKit`).
3. Patches DICOMKit's `Package.swift` to point at the local J2KSwift checkout via SPM `path:`.
4. Runs `swift build` on DICOMKit.

Any J2KSwift API change that breaks the consumer fails the CI gate at PR time, not at the next
DICOMKit upgrade. Test execution is intentionally skipped for now (DICOMKit has 9 pre-existing
unrelated test failures — see `CROSS_CODEC_DICOM_REPORT.md`); a curated test run can be added in
a v5.17.x patch once the build gate stabilises.

### Phase 2 — RGB HT conformant non-pow2 coverage

`Tests/J2KCodecTests/J2KHTConformantRGBNonPowerOf2Tests.swift` —
`testRGB_FullPipeline_NonPowerOf2_LosslessHTConformantSweep` runs:

- 12 dim configurations × 3 decomp levels × 2 bit-depths = **72 cells** of 3-component lossless
  conformant round-trip.
- Per-channel deterministic LCG content (different seeds + gradient slopes per channel) so the
  default Part-1 RCT actually has correlated-but-distinct content to decorrelate.
- Strict pass/fail gate (`XCTAssertEqual(failed.count, 0)`) — any RGB non-pow2 corruption fails.

This extends the v5.15.0 non-pow2 floor to RGB workloads. Combined with the existing
`testRGBSessionAndSessionlessAgreeBitExact` (power-of-2 only), v5.17.0 provides full RGB lossless
non-pow2 coverage.

### Phase 4 — PNG Sub/Up/Average/Paeth re-implementation

`Sources/J2KCLI/PNGSupport.swift` `savePNG(_:to:)` — replaces the v5.14.2 filter-type-0 (None)
writer with all five PNG filter types (None, Sub, Up, Average, Paeth) using proper ORIGINAL-byte
semantics + MAE heuristic for per-row filter selection.

The original v5.14.2 bug was that Sub computed `Filt(x) = Orig(x) - Filt(x-bpp)` (using FILTERED
previous bytes). v5.14.2 disabled filtering as the safe fallback. v5.17.0 implements it correctly:

- Materialises each row's raw (unfiltered) bytes first.
- Computes all five filter outputs from the ORIGINAL row bytes — never from the filtered output.
- Picks the filter with smallest sum-of-absolute-differences (signed-byte, per PNG §12.8 MAE
  heuristic).
- Emits the chosen filter type byte plus the filtered scanline.

Expected file-size reduction: 10–30% on natural images vs v5.16.0's filter-type-0 baseline,
recovering the compression efficiency lost when v5.14.2 took the conservative correctness route.
Existing v5.14.2 PNG round-trip regression tests (e.g. `testPNG_16bit_RoundTrip_BytesIdentical`)
catch any reintroduction of the original Sub-filter bug.

## Verification

### Phase 1 (CI) — verified by the workflow file existing and passing the next push

Will be empirically verified when this PR / commit lands on `main` and CI runs against DICOMKit.
Local equivalent already verified pre-v5.17.0: DICOMKit builds clean against current J2KSwift
HEAD via SPM `path:` override.

### Phase 2 (RGB) — strict regression gate

The new test file enforces `XCTAssertEqual(failed.count, 0)` over 72 cells. Any RGB non-pow2
corruption fails the test loudly. CSV dump at `/tmp/J2K_HT_RGB_NonPowerOf2_Matrix.csv` for
diagnostic purposes.

### Phase 4 (PNG) — gated by v5.14.2 round-trip floor

The pre-existing `testPNG_16bit_RoundTrip_BytesIdentical` (and PGM→J2K→PNG→J2K→PGM tests in
`J2KByteOrderRoundTripTests.swift`) catch any byte-level corruption from the new filter
implementation. Filter selection is purely a compression-efficiency optimisation; correctness is
handled by the per-filter implementation tracking ORIGINAL bytes, never FILTERED bytes.

## Carryover from v5.16.0

- Lossy HT conformant interop gate (`HTConformantLossyOpenJPHInteropTests`) — green.
- 4 v5.15.0 lossless conformant gates — green.
- v5.14.x byte-order regression matrix (10 tests) — green.

All v5.17.0 changes are additive; no encoder/decoder semantics changed except the PNG filter
selection (which is bracketed by the existing PNG correctness tests).

## Known issues (carried over to v5.18.0+)

- **HT conformant lossy R-D gap** (~7 dB at 1 bpp on natural images) due to lack of intra-block
  byte-level truncation in PCRD-opt. Captured in v5.16.0; v5.17.0 doesn't address it. Lossy HT
  conformant remains bitstream-safe; for best compression at low bpp, EBCOT is still recommended
  until the rate controller gets per-codeblock byte truncation.
- **DICOMKit CI test execution** — the new gate currently only checks build success, not test
  execution. DICOMKit has 9 pre-existing unrelated test failures that complicate a clean test
  run; a curated test list is a v5.17.x patch candidate.
- **Phase 3 — Medical corpus expansion** — postponed pending licensed source identification for
  NM, US, MG, OP modalities. v5.17.0 ships Phases 1, 2, and 4.

## Reproducing

```bash
# RGB non-pow2 regression gate (~3-5 s):
swift test --filter HTConformantRGBNonPowerOf2

# Existing v5.14.2 PNG correctness floor (gates the new filter implementation):
swift test --filter J2KByteOrderRoundTripTests

# Manual PNG output-size comparison (quick eyeball check):
swift build -c release
J2K=.build/release/j2k
$J2K decode -i Tests/Fixtures/CrossCodec/ct_study_001_instance_000001.pgm -o /tmp/v5_17_test.png
ls -la /tmp/v5_17_test.png
# Compare against v5.16.0 baseline if available.

# DICOMKit downstream gate — automatic on push to main, or manual:
gh workflow run dicomkit-downstream.yml --ref <branch>
```

## Lesson

The first three releases of the v5.x post-v5.14 era have followed a consistent shape:

1. **v5.14.2** caught a class of byte-order bugs by auditing every reader/writer pair.
2. **v5.15.0** ratified lossless HT conformant via three independent probe levels.
3. **v5.16.0** caught a parallel bitstream conformance bug in lossy HT conformant via cross-decode.
4. **v5.17.0** rounds out the gates: RGB coverage, downstream CI, PNG efficiency.

Each release added regression floors, not just fixes. The compound effect: future J2KSwift
changes have a thicker net of automated tests catching mistakes early. v5.18.0's intra-block
truncation work will land on a much better-protected codebase than v5.16.0 did.
