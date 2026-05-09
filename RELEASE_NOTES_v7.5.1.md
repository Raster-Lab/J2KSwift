# J2KSwift v7.5.1 — Release Notes (hotfix)

**Tag**: `v7.5.1`
**Released**: 2026-05-09
**Headline**: Hotfix — disables the v7.2.0 cross-tile batched HT entropy decode path which silently corrupts decode output when total HTJ2K codestream sample count crosses 2^24 (≈16.78 M px). Surfaced on 16+ MP mammography fixtures during a 4-codec eval matrix.

This release supersedes v7.5.0, v7.4.0, v7.3.0, and v7.2.0 for any HTJ2K-lossless workload at ≥ 16.78 M px. **Users decoding mammography (or any 16+ MP HTJ2K-conformant content) on those releases should upgrade.**

---

## What changed

`DecoderPipeline._multiTileBatchedEntropyEnabled` default flipped from `true` to `false`. The flag was introduced in v7.2.0 (PR #356) to amortise per-tile MTLCommandBuffer overhead by aggregating all tiles' GPU-eligible HT codeblocks into one shared command buffer. The original measurement showed a 3 % win on DX 2x2 multi-tile decode.

Empirical investigation on 2026-05-09 found the batched path silently corrupts decode output when the codestream's total sample count crosses 2^24:

| fixture | dimensions | total samples | result |
|---|---|---:|:-:|
| DX 2800×2288 | 2800 × 2288 | 6 406 400 | ✓ pass (covered by mandatory gate) |
| mg 3520×4744 (probe) | 3520 × 4744 | 16 698 880 (just under 2^24) | ✓ pass |
| **mg 3520×4784** | **3520 × 4784** | **16 838 680 (just over 2^24)** | **✗ fail** (16% byte divergence) |

Cross-codec verification: on the same J2KSwift-encoded HTJ2K bytes, **OpenJPH 0.27.0, Grok 20.3.0, and Kakadu 8.4.1 all decode bit-exactly**. The corruption is purely on J2KSwift's batched-decode side — the encoder is correct.

**Trade-off**: this hotfix gives up the 3 % v7.2.0 DX 2x2 wedge until the underlying indexing bug in `decodeMultiTileGPUBatched` is root-caused. A follow-up issue tracks that work. The flag stays public so investigators can re-enable it for repro / diagnosis.

---

## Bisect provenance

| commit | result |
|---|:-:|
| 0fbb853 (v7.2.0 phase-a UMA encode boundary) | ✓ |
| **13aefd1 (v7.2.0 phase-e cross-tile batched HT entropy, PR #356)** | **✗** |
| 89c1a79..529dcea (v7.2.0..v7.5.0) | ✗ |

So the bug shipped in v7.2.0 (May 9) and persisted through v7.5.0 — silently — because the mandatory pre-release gate's largest fixture (DX 2800×2288, 6.4 M px) sits below the 2^24 threshold.

---

## What lands

- `Sources/J2KCodec/J2KDecoderPipeline.swift`: `_multiTileBatchedEntropyEnabled` default `true` → `false` with inline doc-comment of the v7.5.1 hotfix rationale.
- `Sources/J2KCore/J2KCore.swift`: `getVersion()` returns `"7.5.1"`.
- `Tests/J2KCodecTests/MgRegressionTriageTest.swift`: permanent regression test in the gate. Two assertions:
  1. **Round-trip at 16+ MP must be bit-exact** (the lossless contract that the hotfix restores).
  2. **The batched path is documented broken at this scale** — pins the bug for future investigation. If a future fix lands and the batched path works, that test starts failing and prompts re-enabling the flag.
- `RELEASE_NOTES_v7.5.1.md` — this document.

---

## Mandatory pre-release gate

| suite | tests | result |
|---|---:|:-:|
| `J2KMedicalCorpusEncodePerformanceTests` | 2/2 | ✓ |
| `J2KMedicalCorpusPerformanceTests` | 2/2 | ✓ |
| `J2KStrictCrossCodecValidationTests` | 3/3 | ✓ |
| `HTTileParityMatrixTests` | 1/1 | ✓ |
| `MgRegressionTriageTest` | 2/2 | ✓ |

---

## Open follow-up

Root-cause + proper fix for `decodeMultiTileGPUBatched` corruption above 2^24 samples. Tracked as a separate issue. The keyed dimension is total sample count (3520×4744 = 16.70 M passes; 3520×4784 = 16.84 M fails) which suggests a 24-bit overflow somewhere in the cross-tile pre-batch indexing or coefficient marshalling. Once root-caused, default flips back to `true` and the documented-broken regression test inverts.

---

## Upgrade guidance

| current version | recommendation |
|---|---|
| Any v7.2.0 → v7.5.0, decoding HTJ2K-conformant content < 16.78 M px | optional |
| Any v7.2.0 → v7.5.0, decoding HTJ2K-conformant content ≥ 16.78 M px | **upgrade** |
| Any v7.2.0 → v7.5.0, decoding only Part 1 (`--lossless` without `--htj2k`) | unaffected |
| Any v7.2.0 → v7.5.0, encoding only | unaffected (encoder is correct, external decoders verified) |

---

## Reproduction

```bash
# Build
swift build -c release --product j2k

# Run the regression test (must pass on v7.5.1, fails on v7.2.0..v7.5.0)
swift test -c release --filter MgRegressionTriageTest

# CLI repro at 3520×4784 against the bug:
# (synthetic 16-bit content suffices — bug is scale-keyed, not content-keyed)
swift test -c release --filter MgRegressionTriageTest/testMultiTileHTLossless_AboveTwoToTheTwentyFour_BitExact
```
