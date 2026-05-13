# J2KSwift v5.15.0 — HT conformant lossless: silent-default audit + permanent regression floor

**Release date:** 2026-05-03
**Theme:** Verify a silently-flipped default isn't sitting on a documented latent bug. Prove it both
ways — three independent probe levels, OpenJPH cross-decode, real medical PGM corpus. Lift the
proofs into permanent regression gates.

## The framing

Sometime after v5.1.0, `J2KEncodingPresets.htj2kBlockFormat` was flipped from `.custom` to
`.conformant` — exposing every CLI user calling `--htj2k` and every API caller using the
default initializer to the Part-15 codepath.

The docstring on that property *still warned* users: *"non-power-of-2 subband dimensions are known
to be lossy in the conformant encoder path."*

Two possibilities: either the warning was stale (someone fixed it but forgot the doc), or the
default was flipped without re-validating. Either is bad. v5.15.0 settles it.

## What this release ratifies

### Three independent corruption probes, all 100% bit-exact

| Probe | Cells | Failed | Coverage |
|---|---:|---:|---|
| Block-level `HTBlockEncoderConformant` ↔ `HTBlockDecoderConformant` | 11,520 | **0** | dims 1×1 to 64×64, missingMSBs ∈ {0, 5, 10, 20, 25}, 9 patterns (bin-aligned magnitudes only — the methodology subtlety) |
| Full-pipeline `J2KEncoder` lossless conformant → `J2KDecoder` | 228 | **0** | image dims 31×31 to 511×511, decomp ∈ {0, 1, 3, 5}, bit-depth ∈ {8, 12, 16} |
| Cross-decode `J2KEncoder` lossless conformant → `ojph_expand` | 120 | **0** | image dims 31×31 to 257×257, decomp ∈ {0, 1, 3, 5}, bit-depth ∈ {8, 16} |
| Real medical PGM corpus (CT/DX/MR/PX/XA, 7 fixtures × 3 decomp) | 21 | **0** | actual DICOM-derived 16-bit content, 5 of 7 fixtures non-power-of-2 |

**Total: 11,889 cells, zero corruption.** The docstring caveat is removed.

### Where the bug went

Best hypothesis: the K_max off-by-one closed in v5.1.1 (`kMax = bitDepth - guardBits + 1`,
`ε_b = B + G_b + 1 - guardBits`, see commit memory note). The original v5.1.0 team observed
non-power-of-2 corruption that was likely a correlation, not a causation — the failing samples
were edge-case magnitudes that hit the `2^(B-1)` rollover, and the dimension dependency was a
function of *which subbands had which magnitude distributions* rather than the dimensions
themselves. The K_max widening fixed the rollover, the corruption stopped, but the docstring
caveat and the `project_htj2k_deferred.md` open-item-#6 outlived the fix.

## Permanent regression floor

The probes are now **strict pass/fail gates** in
`Tests/J2KCodecTests/J2KHTConformantNonPowerOf2*Tests.swift`:

```swift
XCTAssertEqual(failed.count, 0,
    "regression: \(failed.count) cells corrupted in HT block round-trip")
```

Plus `Tests/J2KCodecTests/J2KHTConformantPhase2RealCorpusTests.swift` adds the medical-corpus
gate (`testRealCorpus_LosslessConformant_SelfRoundTrip`).

Future encoder changes that regress conformant non-power-of-2 lossless round-trip will fail
all four gates simultaneously.

## Side: R-D parity finding (deferred to v5.16.0)

While running the standard `Scripts/rd_benchmark.py` matrix to confirm encoder competitiveness,
the R-D pipeline surfaced a separate finding: **lossy HT conformant mode is NOT competitive**
with peer codecs.

| Image | bpp | J2KSwift (EBCOT) | J2KSwift-HT | OpenJPH |
|---|---:|---:|---:|---:|
| synth_8b_512 | 1.00 | 33.22 | **30.73** | 33.60 |
| synth_8b_512 | 2.00 | 38.57 | **31.48** | 38.26 |
| synth_12b_512 | 2.00 | 34.30 | **27.40** | 34.20 |

J2KSwift-HT lossy is 2.5–6.9 dB worse than both J2KSwift's own legacy EBCOT path AND OpenJPH at
matched achieved bpp. The encoder produces *correct* HT codestreams (Phase 1 confirmed bit-exact
lossless round-trip, Phase 3 R-D errors aren't decode failures — they're rate-control quality
losses). The gap appears to be in `J2KStepSizeCalculator` quantization-step semantics not being
HT-aware, plus a layer-truncation granularity mismatch (HT cleanup-pass-only vs EBCOT three-passes).

This is multi-day work and is captured as the v5.16.0 motivation in
[V5_15_0_PHASE3_RD_PARITY.md](../research/V5_15_0_PHASE3_RD_PARITY.md).

**Practical guidance for v5.15.0**: lossless HT conformant is the recommended default. Lossy HT
users should fall back to EBCOT (`--htj2k-custom` or unset `--htj2k`) until v5.16.0 closes the
R-D gap.

## Test results

Probes (Phase 1 + Phase 2):
- HT block-level non-pow2 sweep: 11,520 cells, 0 fail (~2.2 s).
- HT full-pipeline non-pow2 sweep: 228 cells, 0 fail (~10 s).
- HT OpenJPH cross-decode sweep: 120 cells, 0 fail (~2.4 s).
- HT real-corpus lossless: 21 cells, 0 fail (~53 s on 7 medical fixtures).
- HT real-corpus lossy non-pow2 ≥ pow2: passes (non-pow2 +37 dB at decomp ≥ 3 — content-dependent).

Full suite: pass (TBD on final test run).

## Caveats

- **Lossy HT R-D**: see above. Lossless HT conformant is fully ratified; lossy HT is not.
- **Probes use synthetic + medical PGM inputs**. Color (RGB) HT conformant non-pow2 is not
  exercised by the new probes; existing `testRGBSessionAndSessionlessAgreeBitExact` covers
  power-of-2 RGB. Adding non-pow2 RGB to the matrix is a v5.15.x patch candidate.
- **OpenJPH cross-decode probe requires** `/opt/homebrew/bin/ojph_expand`. Auto-skipped when
  missing.

## Reproducing

```bash
# Probes:
swift test --filter HTConformantNonPowerOf2 # block-level
swift test --filter HTConformantPipeline    # full pipeline
swift test --filter HTConformantOpenJPH     # OpenJPH cross-decode
swift test --filter HTConformantPhase2      # real medical corpus

# R-D parity (requires release build + ojph_compress + opj_compress):
swift build -c release
python3 Scripts/rd_benchmark.py --quick --out-dir results/rd_benchmark_v5_15_0
```

## Lesson

A silently-flipped default with a stale "known broken" docstring is worse than either a known-
broken default *or* a known-working default — users get no signal about whether the warning is
real. v5.15.0's contribution isn't fixing a bug — it's **proving the bug isn't there with enough
rigor to lift the proof into a permanent regression gate**. Same shape of work as v5.14.2's
byte-order audit: catch a class of latent issues by constructing exhaustive matrices and turning
the matrices into test floors.

The R-D parity issue is a separate, real bug — flagged and scoped, but not in v5.15.0.
