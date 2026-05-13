# J2KSwift v8.1.2 — investigation suite (v8.5 + v8.6 + v8.7 phase-0 wash)

**Tag**: `v8.1.2`
**Released**: 2026-05-10
**Headline**: Three phase-0 lever-ceiling investigations land as projected-wash reports. Combined with the five prior decoder-side probes, **eight independent investigations** now confirm the J2KSwift codec hot-path on Apple M2 + Swift release + macOS is at structural lever ceiling for both encode and decode. No production code changes. Empirical data is the deliverable.

---

## What v8.1.2 is

Pure investigation-only release. **No source-code changes** beyond the version bump. The deliverable is the empirical data that closes the v8.4 recommendation tree's three remaining items:

| Investigation                              | Phase 0 measurement                                                              | Decision      |
|--------------------------------------------|----------------------------------------------------------------------------------|---------------|
| **v8.5** — HT entropy consumer body redesign | 4-reads = 14.27 ns/quad, batched-read = 6.04 ns/quad → 1.32 ms DX wall savings    | **WASH**      |
| **v8.6** — encoder forward 5/3 DWT lifting | 0.37 ns/sample at n=2048 (memory-bandwidth-bound L1 throughput)                  | **WASH**      |
| **v8.6** — HT per-quad SIMD classifier     | DX entropy 272 → 277 ms accumulated CPU (slight regression; reproduces v6.1.0 wash) | **WASH**      |
| **v8.7** — DWT stage decomposition         | `forward2D_53Pooled` 18.78 ms wall on DX; transpose only 0.4% of DWT stage        | not the lever |
| **v8.7** — Row-parallel re-test            | DX CLI 110 → 120 ms (+10 ms regression; over-subscription with v7.0.0 multi-tile auto) | **REGRESSION** |
| **v8.7** — Multi-tile 4x4 default-on       | Corpus mixed: PX +4.6%, MG **−8.0%** (mammography hurt); no universal win          | **WASH**      |

All six measurements project below the v7.4 ≥3 ms DX wall acceptance threshold or actively regress. The current `.auto` multi-tile mode (2x2 for ≥3 MP, single for smaller) is empirically near-optimal for the medical corpus.

## Eight-investigation lever-ceiling table

| Direction  | Investigations                                                                         | Outcome    |
|------------|-----------------------------------------------------------------------------------------|------------|
| Decode     | v6-alpha4 step 12, v7.4 NEON, v7.5 GPU entropy, v8.1 prefix-scan, v8.4 (3 probes), v8.5 | WASH all 6 |
| Encode     | v8.6 forward DWT lifting, v8.6 HT SIMD classifier, v8.7 algorithmic                     | WASH all 3 |

## What stays in tree

- `Tests/J2KCodecTests/V8_5_HTConsumerBodyPhase0Bench.swift` — parity check + per-quad cost microbench
- `Tests/J2KCodecTests/V8_6_ForwardDWTPhase0Bench.swift` — per-sample lifting cost microbench
- `Tests/J2KCodecTests/V8_7_ForwardDWTStageDecomposition.swift` — `forward2D_53Pooled` + strip-transpose decomposition
- `V8_5_HT_CONSUMER_BODY_FINDING.md`, `V8_6_FORWARD_DWT_FINDING.md`, `V8_7_ENCODER_REDESIGN_FINDING.md` — close-out documents with projected wall-savings tables and reopen criteria

Future-investigator references; rerun trivially with `swift test --filter`.

## Backward compatibility

- **Codestream bytes byte-identical to v8.1.1**. No production code changes.
- **No Swift API changes**. Pure investigation deliverable.
- `getVersion()` returns `"8.1.2"`.

The cross-codec parity matrix from v8.1.1 (Documentation/BENCHMARK.md, 48/48 bit-exact across the medical corpus × OpenJPH 0.27.0 / Grok 20.3.0 / Kakadu 8.4.1) holds unchanged because no code path that produces bytes was touched.

## SemVer rule

**PATCH** per RELEASING.md — investigation deliverable; no production code change; no public API change; no codestream byte change.

## Recommendation tree state after v8.1.2

| Item                                    | Status                                  |
|-----------------------------------------|-----------------------------------------|
| #1 j2kd daemon adoption push            | DONE — v8.1.0                           |
| #2 HT entropy consumer body redesign    | DONE — v8.5 projected wash              |
| #3 M3+/A-series hardware retest         | OUT OF SCOPE — needs device             |
| #4 Encoder optimisation arc             | DONE — v8.6 projected wash              |
| #5 Encoder algorithmic redesign         | DONE — v8.7 projected wash              |

All pure-perf branches now exhausted on M2. The next workstream selection is genuinely non-perf: JP3D ROI decoder (multi-day product scope — true per-resolution selective decode vs current decode-then-crop), CI maintenance, product feature work, or pause and observe the codec at Apple-Silicon ceiling.

## Test Suite Results (release mode, 0 failures)

| suite | result |
|---|---:|
| `J2KMedicalCorpusEncodePerformanceTests` | 0 failures |
| `J2KMedicalCorpusPerformanceTests` | 0 failures |
| `J2KStrictCrossCodecValidationTests` | 0 failures |

(Full gate run — see Reproducing below.)

## What WOULD justify reopening any of the closed items

For each phase-0 wash to merit a Phase 1A implementation prototype, one of the following would need to hold:

1. **A different machine class** — M3+/A-series with different cache topology / ISA generation. The marketable "Apple Silicon" claim covers all members, but M2 is the canonical reference. Cross-silicon retest is gated on physical-device access.
2. **A bigger fixture class** — significantly more quads or larger images that scale out of the L1-resident memory-bandwidth ceiling. v8.4 already showed no crossover at 16 MP for the decoder.
3. **A larger architectural change** — e.g. fused stage pipeline (DWT+entropy in one pass), per-fixture adaptive tile-mode auto, eliminating the 25 MB intermediate `colResult` buffer. Multi-week scope; out of single-investigation budget.

## References

- v8.5 close-out: [`V8_5_HT_CONSUMER_BODY_FINDING.md`](V8_5_HT_CONSUMER_BODY_FINDING.md) (PR #406)
- v8.6 close-out: [`V8_6_FORWARD_DWT_FINDING.md`](V8_6_FORWARD_DWT_FINDING.md) (PR #407)
- v8.7 close-out: [`V8_7_ENCODER_REDESIGN_FINDING.md`](V8_7_ENCODER_REDESIGN_FINDING.md) (PR #408)
- v8.4 lever-ceiling close-out (3 probes): `V8_4_DECODE_LEVER_CEILING_CONFIRMED.md` (PR #402)
- v8.1.0 release: [`RELEASE_NOTES_v8.1.0.md`](RELEASE_NOTES_v8.1.0.md)
- v8.1.1 release: [`RELEASE_NOTES_v8.1.1.md`](RELEASE_NOTES_v8.1.1.md)
- Cross-codec parity matrix: [`Documentation/BENCHMARK.md`](Documentation/BENCHMARK.md)

## Reproducing

```bash
# Mandatory release gate (release mode):
swift test -c release --filter \
  'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# v8.5 HT consumer body phase 0:
swift test -c release \
  --filter '^J2KCodecTests\.V8_5_HTConsumerBodyPhase0Bench/testBench_4Reads_vs_Batched_Simple$'

# v8.6 forward DWT phase 0:
swift test -c release \
  --filter '^J2KCodecTests\.V8_6_ForwardDWTPhase0Bench/testForward53_PerSampleCost_LengthSweep$'

# v8.7 forward DWT decomposition:
swift test -c release \
  --filter '^J2KCodecTests\.V8_7_ForwardDWTStageDecomposition'
```
