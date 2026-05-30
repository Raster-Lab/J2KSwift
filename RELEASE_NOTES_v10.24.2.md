# J2KSwift v10.24.2

**Decode performance — load-balanced + P-core-biased entropy scheduling.**

This is a **patch** release. It is a **decoder-only** performance improvement;
codestreams are byte-identical to v10.24.1 and there are no public API changes.

---

## Summary

The parallel tier-1 (code-block) entropy **decode** previously split blocks
into exactly `coreCount` **contiguous** chunks (`chunkSize = blockCount /
coreCount`) with no load-balancing, no oversubscription, and no QoS. Because
code-block decode cost is highly skewed (dense LL / low-frequency vs near-empty
HH) and blocks arrive in resolution/packet order, the expensive blocks
clustered into a few chunks — the slowest chunk gated the whole stage while the
other cores idled (**~2.9 of 8 cores effective on M2**, measured), and the
default-priority tasks spilled onto the M-series E-cores (3–4× slower than
P-cores).

v10.24.2 distributes blocks across `2 × coreCount` buckets using **LPT**
(longest-processing-time-first: sort by descending encoded byte length, greedily
assign each to the least-loaded bucket) and runs the decode tasks at **`.high`
priority** (P-core bias). This is the decode-side analogue of the encoder's
`Tier1ChunkPlan`. Output is keyed by block index, so the redistribution is
**bit-exact**.

This work came out of a rigorous "can we be #1 vs Kakadu" investigation. It is
the genuine, shippable win from that effort; the other levers explored (encode
entropy rebalancing, row-band CPU inverse-DWT) were measured, found to be
washes on M2, and **not** shipped (see Known limitations).

---

## What's New — production-default

- **Load-balanced, P-core-biased decode entropy scheduling.** No flag — it is
  the default decode path. Bit-exact; codestream-agnostic (helps any J2K/HTJ2K
  codestream this decoder reads).

## Backward compatibility

| Aspect | vs v10.24.1 |
|---|---|
| Codestream bytes (encode) | **byte-identical** (encoder untouched) |
| Decoded pixels | **bit-identical** (work redistribution only) |
| Public API | unchanged |

## Performance (M2, warm)

| Workload | v10.24.1 → v10.24.2 |
|---|---|
| **SDK / library decode** (in-process), DX 6.4 MP | 63.9 → **48.1 ms (−25%)** |
| same — CT | 6.2 → **2.3 ms (−63%)** |
| effective cores (DX entropy stage) | 2.9 → **4.4** |
| Canonical decode (large medical geomean) | 49.4 → 48.0 ms (−3%) |
| MG decode (canonical, multi-tile) | −5 to −8% |

The largest gains are on the **in-process library decode path** (the
recommended consumption shape) and on multi-tile MG; on MG-mid J2KSwift now
matches/edges Kakadu and Grok. Gains on single-tile DX/PX are smaller on the
canonical path because their inverse-DWT already runs on GPU and the remaining
wall is entropy-core + tier-2 parse, not the rebalanced scheduling.

## Cross-codec parity (HTJ2K lossless, fresh)

Decoder change is bit-exact, so cross-codec conformance is unchanged from
v10.24.1: J2KSwift's HTJ2K output decodes bit-exactly under OpenJPH 0.27,
Grok 20.3, and Kakadu 8.4 (15/15 cells across CT/MR/DX/MG/PX).

## Test Suite Results

Mandatory commit gate (release mode):

| Suite | Result |
|---|---|
| `J2KMedicalCorpusEncodePerformanceTests` | 2/2 pass |
| `J2KMedicalCorpusPerformanceTests` | 2/2 pass |
| `J2KStrictCrossCodecValidationTests` | 3/3 pass |

Bit-exact round-trip + OpenJPH cross-decode re-verified on DX / PX / MG.

## API surface

No additions, removals, or signature changes.

## Known limitations

- The single-tile DX/PX decode gap to Kakadu (~1.1–1.3×) is **not** closed —
  it lives in the entropy-decode core (pointwise MagSgn/MEL/VLC, repeatedly
  confirmed at the M2 lever ceiling) and fixed per-decode overhead, not in any
  coarse-parallelizable stage. The encode-side rebalance (−0.3%) and the
  row-band CPU inverse-DWT probe (iDWT moves the wall <1 ms — not the
  bottleneck) were both measured as washes and intentionally not shipped.

## Reproducing

```bash
swift build -c release --product j2k
.build/release/j2k inproc-bench <fixture.dcm> --mode decode --runs 40 --warmups 5
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'
```

## Companion documents

- [`PERF_DECODE_ENTROPY_PARALLELISM.md`](PERF_DECODE_ENTROPY_PARALLELISM.md) — the optimization + honest A/B data.
- [`CROSS_CODEC_PERF_REPORT_v10.24.1.md`](CROSS_CODEC_PERF_REPORT_v10.24.1.md) — the cross-codec standing that motivated this work.
