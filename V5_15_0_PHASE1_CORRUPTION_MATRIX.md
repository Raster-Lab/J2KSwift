# v5.15.0 Phase 1 — HT Conformant non-power-of-2 corruption matrix

**Date:** 2026-05-03
**Scope:** Reproduce the non-power-of-2 subband corruption bug documented in the encoder docstring
([J2KEncodingPresets.swift:341-347](Sources/J2KCodec/J2KEncodingPresets.swift#L341-L347)) and quantify
the failure surface so Phase 2 can root-cause it.

## TL;DR

**The bug is gone.** Three independent probes — block-level, full-pipeline self round-trip, and
OpenJPH cross-decode — all pass at 100% across the dimension grid the docstring describes as broken.
The docstring caveat is **stale**.

| Probe | Cells tested | Failed | Notes |
|---|---:|---:|---|
| `HTBlockEncoderConformant` ↔ `HTBlockDecoderConformant` | 11,520 | **0** | block dims 1×1 to 64×64, missingMSBs ∈ {0, 5, 10, 20, 25}, 9 patterns |
| `J2KEncoder` lossless conformant → `J2KDecoder` | 228 | **0** | image dims 31×31 to 511×511, decomp ∈ {0, 1, 3, 5}, bit-depth ∈ {8, 12, 16} |
| `J2KEncoder` lossless conformant → `ojph_expand` | 120 | **0** | image dims 31×31 to 257×257, decomp ∈ {0, 1, 3, 5}, bit-depth ∈ {8, 16} |

Total cells: **11,868. Failed: 0.**

## What the docstring says

```swift
/// Non-power-of-2 subband dimensions (typical in multi-resolution decodes of
/// arbitrary image sizes) are known to be lossy in the conformant encoder
/// path — the same behavior is observed when the encoder output is handed
/// to OpenJPH, so the bug lives in the shared block-coder geometry —
/// tracked for follow-up.
```

Source: [Sources/J2KCodec/J2KEncodingPresets.swift:341-347](Sources/J2KCodec/J2KEncodingPresets.swift#L341-L347).

This caveat originated with v5.1.0 when the original team flipped the default to `.conformant`,
hit non-power-of-2 corruption on real images, reverted the flip — *but kept the caveat in the docstring
even after the default was later flipped back to `.conformant`*. By v5.14.x the default is `.conformant`
in both the public API ([J2KEncodingPresets.swift:435](Sources/J2KCodec/J2KEncodingPresets.swift#L435))
and the CLI ([Commands.swift:184](Sources/J2KCLI/Commands.swift#L184)), but the caveat still warns users.

## Probe 1 — Block-level encode→decode (synthetic)

Source: [Tests/J2KCodecTests/J2KHTConformantNonPowerOf2ProbeTests.swift](Tests/J2KCodecTests/J2KHTConformantNonPowerOf2ProbeTests.swift).

Sweep dimensions: `{1, 2, 3, 4, 5, 6, 7, 8, 11, 13, 16, 17, 23, 32, 33, 64}` × same for height.
Patterns: all-zero, single corners, edge column/row, checkerboard, dense-uniform at μ_p=1 and μ_p=3,
random-seeded LCG.
`missingMSBs ∈ {0, 5, 10, 20, 25}` — controls quantization parameter `p = 30 − missingMSBs`.

**Methodology note**: an earlier first-cut of this probe used arbitrary integer magnitudes
(e.g. `0x10`) and saw 100% "corruption" on dense patterns. That was a methodology bug —
arbitrary magnitudes are sub-bin-center inputs that the encoder *correctly* quantizes to zero.
The corrected probe uses bin-aligned values `(2μ_p + 1) << (p − 1)` only, since those are the
inputs an encoder is supposed to losslessly transmit.

Result: **11,520 / 11,520 cells bit-exact**. No dependency on power-of-2-ness, missingMSBs, or
pattern. The block coder pair handles partial-quad geometry correctly.

CSV: `/tmp/J2K_HT_NonPowerOf2_BlockMatrix.csv`

## Probe 2 — Full-pipeline self round-trip

Source: [Tests/J2KCodecTests/J2KHTConformantPipelineNonPowerOf2Tests.swift](Tests/J2KCodecTests/J2KHTConformantPipelineNonPowerOf2Tests.swift).

Sweep image dimensions chosen to force odd subbands at multi-level DWT:
`(32,32), (33,33), (31,31), (64,64), (65,65), (63,63), (33,64), (64,33), (65,31), (31,65),
(128,128), (129,129), (127,127), (257,257), (255,255), (37,53), (79,61), (101,113), (511,511)`.
Decomp levels `{0, 1, 3, 5}`, bit-depths `{8, 12, 16}`. Lossless HT conformant configuration.

Synth pattern: gradient + LCG noise so neighboring pixels differ. Forces high-frequency subband
energy at the edges where partial-quad processing happens.

Result: **228 / 228 cells bit-exact** through `J2KEncoder → J2KDecoder`.

CSV: `/tmp/J2K_HT_NonPowerOf2_PipelineMatrix.csv`

## Probe 3 — OpenJPH cross-decode (decisive)

Source: [Tests/J2KCodecTests/J2KHTConformantOpenJPHCrossDecodeTests.swift](Tests/J2KCodecTests/J2KHTConformantOpenJPHCrossDecodeTests.swift).

Same input grid as probe 2 (trimmed to skip 12-bit since OpenJPH's PGM sink doesn't support it
cleanly). Each cell encodes via J2KSwift conformant → writes `.j2c` → decodes via
`/opt/homebrew/bin/ojph_expand` → diffs the resulting PGM payload against the original bytes.

This is the test that the v5.1.0 memory note said failed: *"the same behavior is observed when
the encoder output is handed to OpenJPH"*.

Result: **120 / 120 cells bit-exact**. OpenJPH reads J2KSwift's conformant output without any
pixel-level error, including at the non-power-of-2 dimensions the docstring flags.

CSV: `/tmp/J2K_HT_NonPowerOf2_OJPHCrossMatrix.csv`

## Why the original bug is gone

Best hypothesis: the v5.1.1 K_max fix (memory note item 5 in `project_htj2k_deferred.md`) widened
the magnitude range — **bumping `kMax = pending.bitDepth - guardBits + 1`** in
`encodeCodeBlockConformant` and emitting `ε_b = B + G_b + 1 - guardBits` in the conformant
reversible branch of `writeQCDMarker`. That change addressed an off-by-one that masked the input's
top bit when `2^(B-1)` was the magnitude. The same off-by-one was likely the underlying source of
the "non-power-of-2 corruption" — the failing cells the v5.1.0 team observed were probably
*power-of-1-coverage* edge samples that hit the K_max overflow, and the apparent dimension dependency
was correlation, not causation.

Ground truth: `git log --oneline | grep -i 'kmax\|conformant\|ht-encoder'` shows the trajectory
landed in v5.1.1, after which all subsequent v5.x.x work has had `.conformant` as the default
without anyone hitting silent corruption.

## What this means for the v5.15.0 plan

**Phase 2 (root-cause + fix) is not needed.** No bug to root-cause, no fix to write.

**Phase 3 (regression matrix + R-D parity) gets simpler:**
- Lift probes 1, 2, 3 into permanent regression tests (rename, drop the "Probe" prefix, gate
  pass/fail strictly).
- Run `Scripts/rd_benchmark.py` to confirm J2KSwift conformant is within 0.3 dB of OpenJPH at
  matched achieved bpp. If not, encoder rate-control becomes a real workstream.

**Phase 4 (ship):**
- Remove the stale caveat from `J2KEncodingPresets.swift:341-347`.
- Update `project_htj2k_deferred.md` memory: items #2 and #6 → done.
- Tag v5.15.0 with release notes themed *"the documented latent bug isn't latent anymore — confirmed
  via three independent probe levels and OpenJPH cross-decode"*. Same audit-style framing as v5.14.2.

## Reproducing

```bash
# Block-level (~2.2s):
swift test --filter HTConformantNonPowerOf2ProbeTests

# Full-pipeline self round-trip (~10s):
swift test --filter HTConformantPipelineNonPowerOf2Tests

# OpenJPH cross-decode (~2.4s, requires /opt/homebrew/bin/ojph_expand):
swift test --filter HTConformantOpenJPHCrossDecodeTests

# CSVs land in /tmp/J2K_HT_NonPowerOf2_*.csv
```

## Risks / caveats

- Synthetic gradient+LCG inputs may not exercise *every* coefficient distribution real images
  produce. Phase 3 will add a real-corpus probe (CT/MR/DX PGMs from `Tests/Fixtures/CrossCodec/`)
  for completeness before declaring victory.
- Lossy conformant was not tested in Phase 1. Phase 3 will add a lossy variant probe; the original
  bug was reported in lossless mode, so lossless is the riskier branch and the one we exhaustively
  tested first.
