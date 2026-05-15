# J2KSwift v10.0.0 — C+NEON HT decoder default-on, MG tile override, v9.5.2-router recalibration

**Release date:** 2026-05-15
**Base:** `v9.5.2` (`release/v9.5.2`)
**Type:** MAJOR per RELEASING.md "Codestream bytes are part of the public contract" — Phase E2's MG tile override flips MG codestream bytes vs v9.5.2 on the `.auto` planner default.

## Summary

v10.0.0 ships three coordinated wins on Apple M2 versus v9.5.2:

1. **Phase 0 — `recommendedDecodeAPI` router recalibrated for v9.5.2 post-NEON.** The v5.27 thresholds (256² → `.cpu`; <3 MP → `.decodeGPU`; else `.decodeWithGPUHT`) pre-date the v9.4 C+NEON encoder hot path and mis-routed CT 512² by 4.93× and PX/DX by 1.85-3.29×. New policy: `pixels < 500_000 → .cpu`, `500_000 ≤ pixels < 15_000_000 → .decodeGPU`, `pixels ≥ 15_000_000 → .cpu`. `.decodeWithGPUHT` is no longer auto-recommended on M2 (env-override `J2K_AUTO_DECODE_API` keeps it available for diagnostics).
2. **Phase E2 — MG-only 2x2 tile override in `J2KEncodeTilePlanner`.** Gate: `(pixels ≥ 12 MP AND min(w, h) ≥ 2400)` selects 2x2 instead of the previous 4x4. Justified by the v8.7 corpus A/B that measured MG 3517×4784 at −13.32 ms / −8.0 % on 2x2 vs 4x4. **MG codestream bytes change** (different tile layout); other modalities unaffected.
3. **Phase D1.5-D — C+NEON HT decoder default-on.** New `j2knhd_decode_block_ht32` C entry point wires MEL + VLC reverse-reader + MagSgn into a row-dispatch state machine. SWAR-4 MagSgn refill mirrors Swift v7.4 `refillBatched`. Decoder output is bit-exact with `HTBlockDecoderConformant.decode` per `V10_2_DecodeBlockParityTests` (~100+ block configurations, 0 failures). Cleared the v7.4 ≥3 ms DX A/B threshold decisively across three independent warm-bench runs. Opt-out: set `J2K_AUTO_DECODE_API=cpu` or `J2K_NEON_HT_DECODE=0`.

## What's New — production-default

### Decode router recalibration (Phase 0)

`J2KDecoder.recommendedDecodeAPI(width:height:)` now reads:

```swift
if pixels < 500_000 { return .cpu }
if pixels >= 15_000_000 { return .cpu }
return .decodeGPU
```

15-case regression suite in `Tests/J2KCodecTests/RecommendedDecodeAPIRouterTests.swift` pins every substitute-corpus modality plus threshold boundaries.

`.auto` row impact on the DICOM Studio substitute corpus (M2 v9.5.2-baseline vs v10.0.0):

| Modality | v9.5.2 `.auto` ms | v10.0.0 `.auto` ms | Δ |
|---|---:|---:|---:|
| CT 512² | 11.67 | **2.28** | **−9.39 (−80 %)** |
| PX 2793×1316 | 118.18 | **30.12** | **−88.06 (−75 %)** |
| DX 2544×3056 | 129.60 | **56.49** | **−73.11 (−56 %)** |
| MG 3520×4784 | 127.58 | **120.90** | **−6.68** |

### MG-only 2x2 tile override (Phase E2)

`J2KEncodeTilePlanner.plan` adds a single conditional before the existing `pixels ≥ 3 MP → 4x4` default: `(pixels ≥ 12 MP AND min(w, h) ≥ 2400) → 2x2`. Catches MG (16.8 MP, min 3520) cleanly without touching XA (7.86 MP), DX (≤7.78 MP), or any sub-megapixel fixture.

MG encode impact:

| MG fixture | v9.5.2 encode ms | v10.0.0 encode ms | Δ |
|---|---:|---:|---:|
| MG 3516×4784 small | 73.91 | **62.28** | **−11.63 (−16 %)** |
| MG 3521×4784 large | 67.83 | **50.86** | **−16.97 (−25 %)** |

### C+NEON HT decoder default-on (Phase D1.5-D)

`HTBlockDecoderConformantNEON.routingEnabled` defaults to `true`. The Swift reference path (`HTBlockDecoderConformant.decode`) routes per-call into the C entry `j2knhd_decode_block_ht32`. Opt-out via `J2K_NEON_HT_DECODE=0`.

Per-block microbench (64×64, M2 release; v10.2 `V10_2_DecodeBlockCMicrobench`):

| Sparsity | Swift ST | C SWAR ST | ST ratio | Swift MT | C SWAR MT | MT ratio |
|---|---:|---:|---:|---:|---:|---:|
| 5%  | 14833 | 9459  | **1.57×** | 16083 | 11375 | **1.41×** |
| 25% | 27584 | 16917 | **1.63×** | 29833 | 18625 | **1.60×** |
| 50% | 34791 | 21125 | **1.65×** | 37500 | 22959 | **1.63×** |

Geo means: ST **1.61×**, MT **1.55×**.

## What's New — opt-in / opt-out

- **`J2K_AUTO_DECODE_API=cpu|decodeGPU|decodeWithGPUHT`** — forces a specific `recommendedDecodeAPI` recommendation regardless of dimensions.
- **`J2K_NEON_HT_DECODE=0`** — opt out of the C+NEON HT decoder; falls back to the Swift reference path.

## Backward compatibility

- **Encoder codestream bytes change for MG fixtures** (16.8 MP+, min dim ≥ 2400) due to Phase E2's tile-layout flip. Other modalities are byte-identical to v9.5.2.
- **Decoder output is bit-identical to v9.5.2** on every fixture: the C+NEON HT decoder is a bit-exact mirror of the Swift reference path, validated across ~100+ block configurations + 33-fixture cross-codec corpus.
- Public Swift API unchanged. No type removals, no signature changes.

## Cross-codec parity matrix

`J2KStrictCrossCodecValidationTests` (release): 3/3 PASS (both with default-on and `J2K_NEON_HT_DECODE=0`).

| Encoder bytes consumed by | Decode-bit-exact vs J2KSwift |
|---|---|
| OpenJPH 0.21.x (`ojph_expand`) | PASS |
| Grok 20.3.0 (`grk_decompress`) | PASS |
| Kakadu 8.4.x (`kdu_expand`) | PASS |

## Medical-corpus benchmarks

Warm cross-codec bench (M2 release, `Scripts/benchmarks/cross_codec_warm_bench.py --in-proc --runs 7 --warmups 2`):

### Decode wall — J2KSwift in-process vs Kakadu CLI (medical-real fixtures)

| Fixture | v9.5.2 J2KSwift ms | v10.0.0 J2KSwift ms | Δ | v10.0.0 vs Kakadu |
|---|---:|---:|---:|---:|
| PX 2459×1316 small | 27.71 | 25.03 | **−2.68** | 1.07× |
| PX 2793×1316 mid | 30.89 | 27.89 | **−3.00** | 1.20× |
| PX 2812×1316 large | 30.93 | 27.64 | **−3.29** | 1.19× |
| DX 2224×2798 small | 48.94 | 44.00 | **−4.94** | 0.93× **(J2KSwift wins)** |
| DX 2800×2288 mid | 50.93 | 45.25 | **−5.68** | 1.03× |
| DX 2544×3056 large | 64.53 | 56.38 | **−8.15** | 1.20× |
| MG 3516×4784 small | 127.13 | 126.60 | −0.53 | 1.44× |
| MG 3518×4784 mid | 132.19 | 130.03 | −2.16 | 1.47× |
| MG 3521×4784 large | 138.91 | 141.35 | +2.44 | 1.60× |

5/9 fixtures clear v7.4's 3 ms acceptance threshold for default-on. MG within ±3 ms of v9.5.2 on every fixture — no measurable regression.

### Encode wall — J2KSwift in-process (medical-real fixtures)

| Fixture | v9.5.2 ms | v10.0.0 ms | Δ |
|---|---:|---:|---:|
| MG 3516×4784 small | 73.91 | **62.28** | **−11.63** |
| MG 3521×4784 large | 67.83 | **50.86** | **−16.97** |
| (other modalities) | within noise | — | — |

## Test Suite Results (release mode)

| Suite | Tests | Outcome |
|---|---:|---|
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | PASS |
| `J2KMedicalCorpusPerformanceTests` | 2 | PASS |
| `J2KStrictCrossCodecValidationTests` | 3 | PASS |
| `RecommendedDecodeAPIRouterTests` | 15 | PASS |
| `V10_1_*` (MEL/MagSgn/VLC scalar C parity + microbench) | 24 | PASS |
| `V10_2_MagSgnSWARParityTests` (triple-path SWAR equivalence) | 8 | PASS |
| `V10_2_MagSgnSWARMicrobench` | 1 | PASS (1.87× geo mean) |
| `V10_2_DecodeBlockParityTests` (Swift vs C block-level) | 8 | PASS |
| `V10_2_DecodeBlockCMicrobench` | 1 | PASS (1.61× ST / 1.55× MT) |

## API surface (additions only)

- `J2KDecoder.recommendedDecodeAPIEnvOverride()` private — env-var helper for `J2K_AUTO_DECODE_API`.
- `HTBlockDecoderConformantNEON.routingEnabled: Bool` — public flag, defaults to `true` on Apple Silicon.
- C entry points (linkable from Swift via `import J2KCodecNEON`):
  - `j2knhd_mel_init`, `j2knhd_mel_next_run`
  - `j2knhd_vlc_init`, `j2knhd_vlc_peek`, `j2knhd_vlc_consume`, `j2knhd_vlc_read`
  - `j2knhd_magsgn_init`, `j2knhd_magsgn_init_swar`, `j2knhd_magsgn_read`
  - `j2knhd_decode_block_ht32`

## Known limitations

- **MG variance is high** (5-11 ms swing across "same config" warm-bench runs on the 16.8 MP fixtures). The 3-run consensus shows MG within ±3 ms of v9.5.2 — no regression — but the MG win signal is below the variance noise floor. A 20-30-sample re-run + Instruments stage profile is the recommended follow-up to tighten the MG wall claim.
- **MG decode Kakadu gap is 1.6×** — narrower than v9.5.2's 1.93×, but the iDWT-share question (entropy share at 16.8 MP) stays open for a future research arc.

## Reproducing the headline numbers

```bash
# Mandatory commit gate
swift test -c release --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Warm cross-codec bench (default-on path)
python3 Scripts/benchmarks/cross_codec_warm_bench.py --in-proc --runs 7 --warmups 2

# Warm cross-codec bench with C decoder OPT-OUT
J2K_NEON_HT_DECODE=0 python3 Scripts/benchmarks/cross_codec_warm_bench.py --in-proc --runs 7 --warmups 2

# DICOM Studio business-logic substitute (DICOMKit path dep)
(cd ../DICOMKit && swift test -c release --filter DICOMStudioPanelSubstituteTests)
```

## Companion documents

- [`Documentation/research/BEAT_KAKADU_EXECUTION_PLAN_2026_05_15.md`](../research/BEAT_KAKADU_EXECUTION_PLAN_2026_05_15.md) — execution plan that owns this release
- [`Documentation/research/V10_2_DECODE_C_NEON_RETROFIT_PROBE.md`](../research/V10_2_DECODE_C_NEON_RETROFIT_PROBE.md) — D1.5 probe scoping + 3-run consensus
- [`Documentation/research/V10_1_DECODE_C_PORT_PROBE.md`](../research/V10_1_DECODE_C_PORT_PROBE.md) — scalar C arc close-out (predecessor research)
- [`Documentation/Benchmarks/J2KSWIFT_OPTIMAL_VS_KAKADU.md`](../Benchmarks/J2KSWIFT_OPTIMAL_VS_KAKADU.md) — full Lane A + Lane B numbers
- [`Documentation/Benchmarks/DICOM_STUDIO_CLAIM_SCOPE_FINDING.md`](../Benchmarks/DICOM_STUDIO_CLAIM_SCOPE_FINDING.md) — Lane B charter

## Migration notes

- **DX/PX-heavy decode workloads**: no action required. The default C decoder + recalibrated `.auto` router deliver the 5-8 ms DX wall reduction and 80 % CT/PX `.auto` improvement automatically.
- **MG-heavy encode workloads**: codestream bytes change vs v9.5.2 (still HT-conformant lossless; OpenJPH/Grok/Kakadu decode them bit-exactly). If you have downstream byte-equality checksums tracking pre-v10.0.0 MG codestreams, rebuild them after upgrading.
- **MG-heavy decode workloads** that observed a regression: opt-out via `J2K_NEON_HT_DECODE=0`. File a report so the MG iDWT-share investigation can converge.
