# v8.0.0 Phase 3 — CPU 5/3 INT IDWT SIMD vectorisation

**Captured**: 2026-05-09, Apple M2.
**Phase 3 deliverable per the Phase 2 finding §"Phase 3 candidates"**: attack the in-process compute gap on PX/DX by SIMD-vectorising the CPU 5/3 INT inverse 1D wavelet transform (`J2KDWT1DOptimized.inverseTransform53Symmetric`).

## TL;DR

Adds a `SIMD4<Int32>` path to the inverse 5/3 lifting hot loop. **Bit-exact equivalent** to the scalar reference (mandatory gate 10/10, parity matrix 12/12). Real CPU win on the iDWT stage:

| fixture | iDWT accumulated (Phase 0) | iDWT accumulated (Phase 3) | reduction |
|---|---:|---:|---:|
| MR-small | 0.16 ms | 0.16 ms | 0 % (too small) |
| CT 512² | 1.05 ms | 1.07 ms | 0 % (too small) |
| MR 886² | 9.39 ms | 9.26 ms | 1 % |
| XA 1024² | 9.40 ms | 9.60 ms | 0 % (within noise) |
| **PX 2459×1316** | **67.14 ms** | **63.52 ms** | **5.4 %** |
| **DX 2800×2288** | **119.82 ms** | **100.43 ms** | **16.2 %** |

The savings concentrate on PX/DX where the per-tile IDWT work is largest. Smaller fixtures don't benefit because their IDWT is already tiny.

## CLI matrix (median of 5, M2 release, post-Phase-3 default mode)

| fixture | bytes | Phase 2 default | **Phase 3 default** | Kakadu | gap |
|---|---:|---:|---:|---:|---:|
| MR-small 180² | 45 224 | 17 ms | 19 ms | 15 ms | 1.27× |
| CT 512² | 436 460 | 21 ms | 22 ms | 16 ms | 1.38× |
| MR 886² | 169 709 | 24 ms | 25 ms | 17 ms | 1.47× |
| XA 1024² | 1 621 712 | 29 ms | 30 ms | 18 ms | 1.67× |
| PX 2459×1316 | 6 453 588 | 57 ms | 57 ms | 24 ms | 2.38× |
| DX 2800×2288 | 12 705 470 | 103 ms | **91 ms** | 34 ms | 2.68× |

DX CLI gap dropped 12 ms (Phase 2 → Phase 3); other fixtures unchanged within run-to-run noise. **Wall-time improvements are smaller than accumulated-iDWT improvements** because the multi-tile decode runs IDWT in parallel via TaskGroup — accumulated work drops 16% on DX, wall drops ~12% (Phase 2 finding §"Why DX is still 2.78× off" predicted exactly this parallelism-saturation behaviour).

## Implementation

`Sources/J2KCodec/J2KDWT1DOptimized.swift::inverseTransform53Symmetric` gains a SIMD4<Int32> inner loop on top of the scalar reference, processing 4 lifting iterations per chunk. Falls back to scalar for the tail and boundary cases.

```swift
while i &+ 4 <= interiorEnd {
    let lpVec = SIMD4<Int32>(lp[i], lp[i+1], lp[i+2], lp[i+3])
    let hpL  = SIMD4<Int32>(hp[i-1], hp[i], hp[i+1], hp[i+2])
    let hpR  = SIMD4<Int32>(hp[i], hp[i+1], hp[i+2], hp[i+3])
    let avg  = (hpL &+ hpR &+ SIMD4<Int32>(repeating: 2)) &>> SIMD4<Int32>(repeating: 2)
    let outVec = lpVec &- avg
    rp[i*2]      = outVec[0]
    rp[(i+1)*2]  = outVec[1]
    rp[(i+2)*2]  = outVec[2]
    rp[(i+3)*2]  = outVec[3]
    i &+= 4
}
```

Step 2 (predict-undo) gets the same shape, gathering even-position results from `rp` into a SIMD4 and folding into the H band.

**Bit-exact correctness**: `&+`, `&-`, `&>>` on SIMD4<Int32> are element-wise wrapping integer ops with arithmetic shift on signed types — semantically identical to the scalar `&+`, `&-`, `>>` operators on Int32. The cross-codec parity matrix (12 cells × {OpenJPH, Grok, Kakadu}) is the existence proof: every cell still passes 33/33.

## Why the wall-time win is bounded

Phase 0's accumulated-vs-wall analysis showed the multi-tile decode parallelises across 16 tiles via TaskGroup, with effective parallelism limited by Apple M2's 8 P-cores + 4 E-cores. Per-tile iDWT work drops 16% on DX, but the wall is dominated by the longest critical-path tile's combined entropy + iDWT + dequant time. With iDWT being one component of that path, a 16% iDWT speedup translates to a smaller wall-time delta.

To get a 1:1 mapping, we'd need:
- The iDWT to be the SOLE per-tile bottleneck (it isn't — entropy is comparable)
- OR the iDWT to be on the SERIAL portion of the critical path (it isn't — it's parallel-tile)

The right way to read the Phase 3 result: **CPU iDWT is genuinely faster, but we've hit the parallelism saturation ceiling on Apple M2**. Further iDWT optimisation will give diminishing returns until either entropy is also faster (bringing iDWT back into the critical path) or per-tile parallelism increases.

## What lands in this PR

- `Sources/J2KCodec/J2KDWT1DOptimized.swift` — SIMD4<Int32> lifting path in `inverseTransform53Symmetric` (with scalar tail).
- `V8_0_0_PHASE_3_FINDING.md` — this document.

## Mandatory gate (release mode, 0 failures)

10/10 pass:
- `J2KMedicalCorpusEncodePerformanceTests` — 2/2
- `J2KMedicalCorpusPerformanceTests` — 2/2
- `J2KStrictCrossCodecValidationTests` — 3/3
- `HTTileParityMatrixTests` — 1/1 (12 cells × 3 decoders = 33/33 cross-codec bit-exact)
- `MgRegressionTriageTest` — 2/2

## Phase 4 candidates (priority-ranked)

1. **CPU HT entropy hot-path**: 199 ms accumulated on DX is 2× the iDWT cost. Bigger lever than further IDWT work, but v7.4 already covered most of the easy levers — uncertain remaining headroom.
2. **Reduce per-tile dispatch overhead in TaskGroup**: ParallelTile allocator profiling could find allocation churn or lock contention. Bounded scope, plausibly 5-10 ms wall savings.
3. **Persistent Metal session via XPC daemon (v8.1)**: makes GPU IDWT viable in CLI mode. Out of v8.0 scope per Phase 0 §5.
4. **CPU 5/3 INT odd-origin SIMD path**: this PR only vectorises the symmetric (even-origin) path. The odd-origin variant is rarer (only fires on ANY-ODD tile origins) but covered by parity matrix.

## v8 progression to date

| version | DX CLI | gap to Kakadu |
|---|---:|---:|
| pre-v8 (user's eval, v7.5.0 baseline) | 134 ms | 4.0× |
| v8 Phase 0 (no code change, finding only) | 134 ms | 4.0× |
| v8 Phase 1 (cold-start elimination, --no-gpu honored) | 91 ms | 2.7× |
| v8 Phase 2 (default CPU routing) | 103 ms | 2.8× |
| **v8 Phase 3 (this PR, SIMD IDWT)** | **91 ms** | **2.7×** |

(The "gap" delta from Phase 2 → Phase 3 on DX is real but small; the bigger Phase 3 contribution is the iDWT-stage-specific savings that compound with future per-stage work.)

## Reproduction

```bash
swift build -c release --product j2k

# In-process per-stage breakdown
swift test -c release --filter DecodeStageProfileLosslessCorpusTests

# CLI matrix (J2KSwift default vs Kakadu)
for fix in mr_small ct_512 mr_886 xa_1024 px dx; do
  /usr/bin/time .build/release/j2k decode -i ${fix}.j2k -o /tmp/out.pgm \
    --output-format pgm --quiet
done
```
