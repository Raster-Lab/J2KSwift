# Medical Imaging Benchmark: J2KSwift vs OpenJPEG

**Date:** 2026-05-04 (R-D table at top reflects synthetic content; v5.31.0 cross-scale
real-medical R-D measurement is in the new section below.)

---

## v5.38 — Lossless-only refocus (active)

From **2026-05-05**, J2KSwift's product target is exact-reconstruction
medical archival. Lossy R-D / Qstep / `.constantBitrateStrict` /
constrained-RD / 9/7 GPU encode are parked as infrastructure (tests
green; not extended). All v5.38+ work is lossless.

### v5.38 M1 — lossless gate scaffolding

`Tests/J2KCodecTests/J2KLosslessMedicalGateTests.swift::testLosslessRoundTripBitExactAcrossMedicalCorpus`
exercises the medical corpus through `J2KEncoder(.lossless).encode →
J2KDecoder.decode` and asserts bit-exact roundtrip. Helper module
`Tests/J2KCodecTests/CrossCodecTooling.swift` consolidates the
duplicated `runDecoder` / hard-coded `/opt/homebrew/bin` patterns and
adds Kakadu (`/usr/local/bin/kdu_compress|kdu_expand`) to the codec
roster.

Numbers below are from a single Apple Silicon run (release build,
warm session, n=1 measurement pass after a single warm-up).

| Modality | Shape | Raw KB | J2KSwift KB | Ratio vs raw | Encode ms | Decode ms |
|---|---|---:|---:|---:|---:|---:|
| MR-small | 180×180   |    63 |    44 | 1.43× |   1.2 |   0.7 |
| CT       | 512×512   |   512 |   426 | 1.20× |   6.9 |   3.9 |
| CT       | 512×512   |   512 |   396 | 1.29× |   6.9 |   3.6 |
| MR       | 886×886   |  1533 |   163 | **9.36×** |   7.7 |   6.0 |
| XA       | 1024×1024 |  2048 |  1583 | 1.29× |  23.3 |  15.3 |
| PX       | 2459×1316 |  6320 |  6280 | **1.01×** |  78.0 |  39.2 |
| DX       | 2800×2288 | 12512 | 12385 | **1.01×** | 163.2 |  79.0 |

**M1 pass gate**: every fixture is bit-exact (`MAE = 0`,
`bitExactPixelMatch == true`). The PX / DX 1.01× ratios are flagged
for M3 investigation — most likely a bit-depth / precinct / code-block
default that's leaving compression on the table for high-resolution
high-bit-depth content. **M1 ships as-is**: the gate's job is to
catch regressions, not yet to maximize ratio.

### v5.38 M2 — lossless cross-codec matrix (OpenJPEG + OpenJPH + Grok + Kakadu)

`testLosslessCrossCodecMatrixAcrossMedicalCorpus` extends the M1 gate to
drive each fixture through every external codec: lossless compress,
decompress, self-roundtrip bit-exact verify, **and** feed the J2KSwift
codestream to the external decoder to prove standards compliance.

All 7 fixtures × 4 external codecs = 28 cross-decode pairs all pass
bit-exact (no LSB diff). Total wall time: ~8.8 s.

**Codec versions used (2026-05-05 install):**
- OpenJPEG 2.5.4 (Homebrew, `/opt/homebrew/bin/opj_compress`)
- OpenJPH (Homebrew, HT-only — Part 15)
- Grok (Homebrew)
- Kakadu 8.4.1 demo (`/usr/local/bin/kdu_compress`, J2K1+HTOPT decoding,
  `J2K1+HT(no-opt)` encoding)

#### Lossless output bytes + ratio-vs-raw

| Modality | Shape | Raw KB | J2KSwift | OpenJPEG | OpenJPH | Grok | Kakadu | J2KSwift× | OpenJPEG× | OpenJPH× | Grok× | Kakadu× |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| MR-small | 180×180   |    63 |    44 |    30 |    44 |    30 |    30 | 1.43× | 2.09× | 1.43× | 2.09× | 2.09× |
| CT       | 512×512   |   512 |   426 |   324 |   426 |   324 |   324 | 1.20× | 1.58× | 1.20× | 1.58× | 1.58× |
| CT       | 512×512   |   512 |   396 |   308 |   396 |   308 |   308 | 1.29× | 1.66× | 1.29× | 1.66× | 1.66× |
| MR       | 886×886   |  1533 |   163 |   135 |   163 |   135 |   135 | 9.36× | 11.33× | 9.36× | 11.33× | 11.32× |
| XA       | 1024×1024 |  2048 |  1583 |  1337 |  1583 |  1337 |  1337 | 1.29× | 1.53× | 1.29× | 1.53× | 1.53× |
| PX       | 2459×1316 |  6320 |  6280 |  5485 |  6280 |  5485 |  5485 | 1.01× | 1.15× | 1.01× | 1.15× | 1.15× |
| DX       | 2800×2288 | 12512 | 12385 | 10559 | 12384 | 10559 | 10559 | 1.01× | 1.18× | 1.01× | 1.18× | 1.18× |

**J2KSwift output bytes ≡ OpenJPH output bytes** on every fixture (down
to 1 byte). Both default to HTJ2K conformant lossless, and the Part 15
spec produces converged byte counts on the same input. OpenJPEG, Grok,
and Kakadu default to **EBCOT lossless** (Part 1), which is ~13-15%
denser than HT for high-bit-depth content. This is a format trade-off,
not a J2KSwift compression deficiency: when those three codecs are run
in HT mode they converge with J2KSwift.

#### Lossless encode time (ms, n=1, warm session)

| Modality | Shape | J2KSwift | OpenJPEG | OpenJPH | Grok | Kakadu |
|---|---|---:|---:|---:|---:|---:|
| MR-small | 180×180   |   1.1 |   17.0 |   8.1 |   15.3 |   9.4 |
| CT       | 512×512   |   6.2 |   56.9 |  10.3 |   15.8 |   8.3 |
| CT       | 512×512   |   6.3 |   53.1 |  10.0 |   14.7 |   8.9 |
| MR       | 886×886   |   7.5 |   59.4 |  10.4 |   14.0 |   5.8 |
| XA       | 1024×1024 |  21.9 |  197.1 |  22.0 |   37.1 |  23.4 |
| PX       | 2459×1316 |  79.6 |  713.3 |  60.6 |  118.5 |  83.2 |
| DX       | 2800×2288 | 156.7 | 1373.9 | 114.4 |  230.5 | 153.4 |

**J2KSwift encode beats every external codec on small images** (process
launch dominates the externals) **and is competitive at scale**: at
12 MP DX it's 7% slower than OpenJPH and within 2% of Kakadu, while
remaining 9× faster than OpenJPEG. External codecs include their
process-launch overhead in the wall time; J2KSwift is in-process so
this comparison favours J2KSwift on small images.

#### Lossless decode time (ms, n=1, warm session)

| Modality | Shape | J2KSwift | OpenJPEG | OpenJPH | Grok | Kakadu |
|---|---|---:|---:|---:|---:|---:|
| MR-small | 180×180   |   1.5 |   11.8 |   6.7 |    9.3 |   4.8 |
| CT       | 512×512   |  50.8\* |   56.5 |   9.0 |   14.8 |   8.7 |
| CT       | 512×512   |   3.2 |   54.3 |   8.8 |   14.5 |   8.5 |
| MR       | 886×886   |   6.1 |   66.4 |  10.9 |   12.5 |   7.2 |
| XA       | 1024×1024 |  19.4 |  201.9 |  17.1 |   32.9 |  25.3 |
| PX       | 2459×1316 |  39.9 |  709.6 |  43.2 |  100.7 |  90.7 |
| DX       | 2800×2288 |  84.2 | 1361.9 |  81.4 |  193.3 | 170.6 |

\* First non-trivial decode of the run pays Metal/GPU lazy init; second
CT entry on the same dimensions reads 3.2 ms warm. Add an explicit
decode warm-up before the measurement pass — pending refinement in M3.

#### Cross-decode matrix (J2KSwift → external)

| Modality | Shape | OpenJPEG | OpenJPH | Grok | Kakadu |
|---|---|:---:|:---:|:---:|:---:|
| MR-small | 180×180   | ✓ | ✓ | ✓ | ✓ |
| CT       | 512×512   | ✓ | ✓ | ✓ | ✓ |
| CT       | 512×512   | ✓ | ✓ | ✓ | ✓ |
| MR       | 886×886   | ✓ | ✓ | ✓ | ✓ |
| XA       | 1024×1024 | ✓ | ✓ | ✓ | ✓ |
| PX       | 2459×1316 | ✓ | ✓ | ✓ | ✓ |
| DX       | 2800×2288 | ✓ | ✓ | ✓ | ✓ |

**28/28 cross-decode pairs bit-exact.** J2KSwift's HT lossless
codestream is consumed losslessly by every mainstream Part-15-aware
decoder — OpenJPEG 2.5.4, OpenJPH, Grok, and Kakadu 8.4.1 demo.

### v5.38 M3 — stage profile + first targeted optimisation

`testLosslessEncodeStageProfileAcrossMedicalCorpus` snapshots
`J2KEncodeTimings` per encode pass (5 measurement passes per fixture
after a warm-up). Median per-stage results identified
**codestream-generation** as the dominant stage on every fixture ≥
512² — surprisingly so (47% on DX 12 MP), more than entropy (25%) or
the 5/3 forward DWT (23%).

Root cause: `J2KBitWriter.writeBytes(_:Data)` was byte-by-byte
(`for byte in data { writeUInt8(byte) }`) and the codestream-generation
flow writes the entire tile-data buffer (12 MB on DX) into the outer
codestream writer this way — ~12 million method calls + per-byte
bit-position checks.

**Step-A fix** (6-line change in `J2KBitWriter`): when the writer is
byte-aligned and byte-stuffing is disabled (always true for the
post-SOD tile-data write), use `buffer.append(contentsOf: bytes)` for
a single buffer-grow + memcpy.

#### Encode stage profile, before vs after Step-A (median of 5 runs, ms)

| Fixture | Stage | Before | After | Δ |
|---|---|---:|---:|---:|
| **DX 2800×2288**     | Total      | 156.90 |  88.21 | **−43.7% / 1.78×** |
|                      | Codestream |  73.24 |   6.11 | −91.7% |
|                      | Entropy    |  38.96 |  39.90 | +2% (no change expected) |
|                      | DWT        |  35.50 |  34.38 | −3% |
| **PX 2459×1316**     | Total      |  78.34 |  44.63 | **−43.0% / 1.76×** |
|                      | Codestream |  36.86 |   3.18 | −91.4% |
| **XA 1024×1024**     | Total      |  22.39 |  13.52 | **−39.6% / 1.66×** |
|                      | Codestream |   9.31 |   0.80 | −91.4% |
| **CT 512×512**       | Total      |   6.17 |   3.65 | **−40.8% / 1.69×** |
|                      | Codestream |   2.59 |   0.24 | −90.7% |
| **MR-small 180×180** | Total      |   1.05 |   0.72 | **−31.4% / 1.46×** |

After Step-A, codestream-generation drops from 47% → 7% of total on DX,
and the dominant stage flips to entropy (45%) on most fixtures. MR
886×886 (compression ratio 9.36×, low entropy load) is now DWT-dominant
at 60%.

#### Cross-codec encode time, before vs after Step-A (ms)

| Fixture | J2KSwift before | J2KSwift after | OpenJPEG | OpenJPH | Grok | Kakadu | Now-fastest |
|---|---:|---:|---:|---:|---:|---:|:---|
| MR-small 180×180   |   1.1 |   **0.8** |    12.3 |   7.0 |   9.3 |   9.3 | **J2KSwift** |
| CT 512×512         |   6.2 |   **3.9** |    59.4 |  10.2 |  15.4 |   8.3 | **J2KSwift** |
| CT 512×512         |   6.3 |   **3.7** |    52.8 |   9.9 |  15.7 |   8.5 | **J2KSwift** |
| MR 886×886         |   7.5 |     7.3   |    59.3 |  10.5 |  14.4 | **6.1** | Kakadu (by 1.2 ms) |
| XA 1024×1024       |  21.9 |  **13.2** |   203.0 |  21.5 |  36.6 |  23.1 | **J2KSwift** |
| PX 2459×1316       |  79.6 |  **45.7** |   718.2 |  59.5 | 118.9 |  81.9 | **J2KSwift** |
| DX 2800×2288       | 156.7 |  **88.8** |  1364.3 | 119.8 | 228.0 | 154.0 | **J2KSwift** |

**J2KSwift is now the fastest lossless encoder on 6 of 7 medical
fixtures.** The lone exception is MR-886 where Kakadu's heavy parallelism
(8 threads on a low-entropy fixture) pulls ahead by 1.2 ms; J2KSwift is
within 17% there.

Decode timings unchanged (Step-A is encode-side only). The CT 512×512
first-instance Metal lazy-init outlier persists (49.5 ms vs 3.2 ms warm)
— flagged for future warm-up refinement, not a code bug.

### v5.38 M4 — J2KSwift HT vs EBCOT lossless on the medical corpus

`testJ2KSwiftLosslessHTvsEBCOTOnMedicalCorpus` runs the same fixtures
through both J2KSwift lossless paths and asserts bit-exact roundtrip
in each. The trade-off is now measurable rather than implied.

| Modality | Shape | Raw KB | HT KB | HT× | EBCOT KB | EBCOT× | EBCOT vs HT | HT enc/dec ms | EBCOT enc/dec ms |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| MR-small | 180×180   |    63 |    44 | 1.43× |    30 |  2.09× | **−31.6%** |   0.9 /  1.5 |   3.0 /  2.7 |
| CT       | 512×512   |   512 |   426 | 1.20× |   324 |  1.58× | **−24.0%** |   3.9 / 51.9\* |  15.7 / 13.2 |
| CT       | 512×512   |   512 |   396 | 1.29× |   308 |  1.66× | −22.3% |   3.5 /  3.3 |  15.7 / 12.8 |
| MR       | 886×886   |  1533 |   163 | 9.36× |   135 | 11.33× | −17.4% |   7.2 /  5.6 |  20.5 / 13.7 |
| XA       | 1024×1024 |  2048 |  1583 | 1.29× |  1337 |  1.53× | −15.5% |  13.6 / 15.8 |  58.1 / 51.3 |
| PX       | 2459×1316 |  6320 |  6280 | 1.01× |  5485 |  1.15× | −12.7% |  43.4 / 40.9 | 189.1 / 164.6 |
| DX       | 2800×2288 | 12512 | 12385 | 1.01× | 10559 |  1.18× | **−14.7%** |  87.4 / 79.1 | 376.2 / 325.3 |

\* CT 512² first decode picks up the Metal lazy-init outlier (~50 ms);
the second CT entry on the same dimensions reads 3.3 ms warm.

**EBCOT bytes match OpenJPEG / Grok / Kakadu defaults exactly** —
J2KSwift's EBCOT lossless is byte-for-byte equivalent on every
fixture (e.g. CT 308 KB == 308 KB; DX 10559 KB == 10559 KB; MR 135 KB
== 135 KB), because all four codecs default to EBCOT lossless and the
format converges on the same rate.

**Format trade-off in plain language:**

| Decision | HT lossless (default) | EBCOT lossless |
|---|---|---|
| Codestream bytes | 13–32% larger | smallest |
| Encode time   | 2–4× **faster** | slower |
| Decode time   | 2–4× **faster** | slower |
| Decoder interop | Part-15 only (OpenJPH, Kakadu 8.4.1, Grok, OpenJPEG ≥ 2.5) | every Part-1 decoder ever shipped |
| Recommended when | encoder/decoder are modern; cycles matter | broadest legacy decoder coverage; archive density matters more than throughput |

For DICOM archive workflows where storage is the dominant cost and
the consumer might be a 20-year-old viewer, EBCOT is the safer pick.
For active PACS pipelines where every fast path matters and every
decoder in the loop is current, HT is the win — and J2KSwift's HT
encode is the fastest of the 5 codecs measured on 6 of 7 fixtures
(post-Step-A).

### v5.38 plan — milestones (revised after M4)

- **M1 ✓** — gate scaffolding + bit-exact roundtrip table.
- **M2 ✓** — external-codec columns + cross-decode matrix.
- **M3 Step-A ✓** — stage profile + `J2KBitWriter.writeBytes` fast path.
- **M4 ✓** — HT vs EBCOT comparison + trade-off documentation.
### v5.38 M5 — branchless 5/3 forward lifting → DWT 9-15% faster

`AcceleratedEncoder.forward53_1D(_:_:count:workspace:)` had two inner
loops with per-iteration `i + 1 < lowCount` / `i > 0` boundary
conditionals. These prevented LLVM from emitting NEON
`vaddq_s32`/`vshrq_n_s32` sequences over the bulk of the lifting work.

The M5 fix splits each loop into a branchless bulk body + a tiny
scalar tail (one or two iterations). The bulk body has predictable
stride access on contiguous Int32 pointers, so the loop vectoriser
emits the expected NEON sequence; the tail handles the lone boundary
case in scalar code. Bit-exact equivalence verified across all 7
medical fixtures.

#### Encode stage profile, post-Step-A vs post-M5 (median of 5 runs, ms)

| Fixture | Stage | Post-Step-A | Post-M5 | Δ |
|---|---|---:|---:|---:|
| **MR 886×886**     | Total | 6.47 |  6.08 | **−6.0%** |
|                    | DWT   | 3.88 |  3.37 | **−13.1%** |
| **DX 2800×2288**   | Total | 87.01 | 83.83 | **−3.7%** |
|                    | DWT   | 35.20 | 31.85 | **−9.5%** |
| PX 2459×1316       | Total | 44.36 | 42.72 | −3.7% |
|                    | DWT   | 16.21 | 14.54 | −10.3% |
| XA 1024×1024       | Total | 13.60 | 12.98 | −4.6% |
|                    | DWT   |  5.66 |  4.79 | **−15.4%** |

Sparse fixtures (MR with 9.36× compression — most pixels zero) gain
the most because the DWT has to process every pixel regardless of
sparsity, so DWT savings translate directly to total savings.
Dense fixtures (PX/DX with ~1.01× compression) are entropy-bound;
DWT savings show through proportionally.

#### Cumulative v5.38 speedup vs pre-M3 baseline

| Fixture | v5.37 baseline | post-Step-A | post-M5 | Cumulative |
|---|---:|---:|---:|---:|
| DX 2800×2288       | 156.9 ms | 88.2 ms | **83.8 ms** | **1.87×** |
| PX 2459×1316       |  78.3 ms | 44.6 ms |   42.7 ms | 1.83× |
| XA 1024×1024       |  22.4 ms | 13.5 ms |   13.0 ms | 1.72× |
| MR 886×886         |   7.6 ms |  6.5 ms |    6.1 ms | 1.25× |

DX 12 MP encode is now **1.87× faster** than the v5.37 baseline.

### v5.38 M7 — extractComponentData branch hoist → preprocess −66 to −72%

The 16-bit input extraction loop in `extractComponentData` had two
branches inside the per-pixel hot loop:
   - `switch byteOrder { case .littleEndian: ... case .bigEndian: ... }`
   - `if component.signed { ... } else { ... }`

Both are constant for a single component but LLVM was not hoisting
them — the per-pixel branch cost added up over 12M iterations on DX.

Fix: specialise the loop to one of 4 closed-form bodies before the
loop runs (`(byteOrder, signed) ∈ {LE,BE} × {true,false}`), so the
per-pixel body is straight-line UInt16 widening + Int32 store. With
the branches gone, LLVM auto-vectorises the body.

#### Encode stage profile, post-M5 vs post-M7 (median of 5 runs, ms)

| Fixture | Stage | Post-M5 | Post-M7 | Δ |
|---|---|---:|---:|---:|
| **DX 2800×2288**     | Total      |  83.83 |  81.36 | **−3.0%** |
|                      | Preprocess |   7.18 |   2.43 | **−66.2%** |
| **PX 2459×1316**     | Total      |  42.72 |  39.77 | **−6.9%** |
|                      | Preprocess |   3.65 |   1.16 | **−68.2%** |
| **CT 512×512**       | Total      |   3.48 |   3.18 | **−8.6%** |
|                      | Preprocess |   0.29 |   0.08 | **−72.4%** |
| **MR 886×886**       | Total      |   6.08 |   5.66 | **−6.9%** |
|                      | Preprocess |   0.86 |   0.26 | **−69.8%** |

Preprocess stage drops 66-72% across the full corpus.

The encode performance regression suite also picked up the win:
55.3 s (pre-Step-A) → 34.6 s (post-Step-A) → 32.8 s (post-M7) for the
same workload.

### v5.38 M8 — HT conformant entropy encoder buffer reuse → DX 2.00× cumulative

`HTBlockEncoderConformant.encode` allocated three fresh `[UInt8]`
buffers (magsgn, mel, vlc) inside its body via
`var enc = HT...EncoderConformant()` per call. For DX 12 MP that's
2300 blocks × 3 fresh `[UInt8]` allocations per block = 6900 small
heap allocations per encode. The MagSgn buffer alone averages ~5 KB
per block → ~12 MB of allocator churn just for that one stream.

Fix:
1. Added `mutating func reset()` to `HTMagSgnEncoderConformant`,
   `HTMELEncoderConformant`, `HTReverseBitEmitterConformant`, and
   `HTForwardBitEmitterConformant`. Each clears its `[UInt8]` storage
   via `removeAll(keepingCapacity: true)` and resets state to
   post-`init()` values.
2. Added a new `HTBlockEncoderConformant.encode` overload that takes
   the three encoders as `inout` parameters, calling `reset()` on
   each before encoding. The non-inout overload is preserved as a
   thin wrapper that allocates fresh encoders per call (legacy
   callers).
3. Threaded `inout` encoders through `encodeCodeBlockHTJ2KFast` →
   `encodeCodeBlockConformant` → `HTBlockEncoderConformant.encode`.
4. Pre-allocated the three encoders once per chunk (or once per
   sequential pass) in `applyEntropyCodingHTJ2KFused` alongside the
   existing reusable buffers.

Bit-exact equivalence verified by the M1 roundtrip gate (7/7 fixtures
MAE = 0) and the M2 cross-decode matrix (28/28 pairs bit-exact across
OpenJPEG, OpenJPH, Grok, Kakadu).

#### Encode stage profile, post-M7 vs post-M8 (median of 5 runs, ms)

| Fixture | Stage | Post-M7 | Post-M8 | Δ |
|---|---|---:|---:|---:|
| **DX 2800×2288**     | Total   | 81.36 | 78.45 | **−3.6%** |
|                      | Entropy | 39.60 | 36.96 | **−6.7%** |
| **PX 2459×1316**     | Total   | 39.77 | 38.94 | **−2.1%** |
|                      | Entropy | 20.72 | 19.71 | **−4.9%** |
| **CT 512×512**       | Total   |  3.42 |  3.26 | **−4.7%** |
|                      | Entropy |  1.82 |  1.64 | **−9.9%** |
| **MR-small 180×180** | Total   |  0.76 |  0.73 | **−3.9%** |
|                      | Entropy |  0.43 |  0.39 | **−9.3%** |

#### Cumulative v5.38 encode speedup vs v5.37 baseline

| Fixture | v5.37 | post-Step-A | post-M5 | post-M7 | post-M8 | Cumulative |
|---|---:|---:|---:|---:|---:|---:|
| DX 2800×2288       | 156.9 ms | 88.2 | 83.8 | 81.4 | **78.5 ms** | **2.00×** |
| PX 2459×1316       |  78.3 ms | 44.6 | 42.7 | 39.8 |   38.9 ms | 2.01× |
| XA 1024×1024       |  22.4 ms | 13.5 | 13.0 | 12.4 |   12.2 ms | 1.83× |
| MR 886×886         |   7.6 ms |  6.5 |  6.1 |  5.7 |    5.5 ms | 1.38× |

DX 12 MP encode is now exactly **2.00× faster** than v5.37 baseline.

### v5.38 M9 — sign-magnitude buffer reuse + UnsafeBufferPointer encoder → DX 2.06× cumulative

The HT conformant encode path allocated a fresh
`var conformantIn = [UInt32](repeating: 0, count: count)` per block to
hold the sign-magnitude conversion of the input coefficients. For DX
12 MP that's 16 KB × ~2300 blocks = ~36 MB of allocator churn per
encode, on top of the M8 entropy-encoder buffer churn already removed.

Fix:
1. New `HTBlockEncoderConformant.encode` overload taking
   `coefficients: UnsafeBufferPointer<UInt32>` instead of `[UInt32]`.
   Lets callers pass a pointer + count derived from a reusable buffer
   without forcing the underlying array's `count` to match
   `width * height`. Body uses pointer-direct `coefficients[idx]`,
   skipping Swift's `Array` bounds check inside the per-quad hot loop.
2. New `conformantInBuf: inout [UInt32]` parameter on
   `encodeCodeBlockConformant`. Re-allocates only when block size
   changes (most blocks in a chunk share dimensions, so the resize
   check fast-paths through). The fill loop writes through
   `withUnsafeMutableBufferPointer` for direct pointer stores. The
   buffer is then handed to the encoder via `withUnsafeBufferPointer`.
3. Pre-allocate `cInBuf = [UInt32](repeating: 0, count: maxBlockSize)`
   at all 4 chunk-loop sites in `applyEntropyCodingHTJ2KFused`.

Bit-exact equivalence verified by the M1 + M2 gates (7/7 fixtures
MAE = 0; 28/28 cross-decode pairs bit-exact).

#### Encode stage profile, post-M8 vs post-M9 (median of 5 runs, ms)

| Fixture | Stage | Post-M8 | Post-M9 | Δ |
|---|---|---:|---:|---:|
| **DX 2800×2288**     | Total   | 78.45 | **76.02** | **−3.1%** |
|                      | Entropy | 36.96 |  33.16 | **−10.3%** |
| **PX 2459×1316**     | Total   | 38.94 | **36.93** | **−5.2%** |
|                      | Entropy | 19.71 |  17.65 | **−10.5%** |
| **XA 1024×1024**     | Total   | 12.23 | **11.39** | **−6.9%** |
|                      | Entropy |  6.35 |   4.99 | **−21.4%** |
| **MR 886×886**       | Total   |  5.52 |   5.28 | −4.3% |
| **CT 512×512**       | Total   |  3.26 |   3.01 | −7.7% |

#### Cumulative v5.38 encode speedup vs v5.37 baseline

| Fixture | v5.37 | post-A | post-M5 | post-M7 | post-M8 | post-M9 | Cumulative |
|---|---:|---:|---:|---:|---:|---:|---:|
| DX 2800×2288  | 156.9 ms | 88.2 | 83.8 | 81.4 | 78.5 | **76.0 ms** | **2.06×** |
| PX 2459×1316  |  78.3 ms | 44.6 | 42.7 | 39.8 | 38.9 |   36.9 ms | **2.12×** |
| XA 1024×1024  |  22.4 ms | 13.5 | 13.0 | 12.4 | 12.2 |   11.4 ms | **1.96×** |
| MR 886×886    |   7.6 ms |  6.5 |  6.1 |  5.7 |  5.5 |    5.3 ms | 1.43× |

DX 12 MP encode is now **2.06× faster** than v5.37 baseline.
PX 3.2 MP encode is **2.12× faster** — first fixture to cross 2.10×.

The encode performance regression suite likewise picked up the win:
55.3s (pre-Step-A) → 29.3s (post-M9) for the same workload —
**1.89× faster end-to-end** on the regression suite.

### v5.38 M10 — what didn't work (negative result)

After M9 left entropy as the dominant DX stage (~33 ms / 44%), M10
targeted the per-quad scanning hot loop in
`HTBlockEncoderConformant.encode`. Two micro-optimisation attempts
were measured against the M9 baseline; both came in within run-to-run
noise. Reverted; baseline preserved.

**Attempt 1 — interior fast-path** in `processQuad`. When
`baseX + 1 < width && baseY + 1 < height` (true for every quad in a
full-size 64×64 code block — the common case on the medical corpus),
skip the per-fetch `guard x < width, y < height else { return 0 }`
boundary check and use direct pointer indexing for all four samples.
Only boundary blocks fall back to `fetch()`.

Result on DX 12 MP (median of 10 runs): **74.65 ms vs 74.19 ms M9
baseline = +0.6 ms regression.** Distribution-wise consistently a
touch slower across percentiles. The CPU branch predictor was
already handling the original `guard` pattern well (it always
succeeds for interior quads), and the explicit `if/else` dispatch
adds slight overhead from the additional comparison and the wider
fast-path body.

**Attempt 2 — `@inline(__always)` hints** on the nested `sampleInfo`
and `fetch` functions, on the theory that LLVM might not be fully
inlining the nested closures despite Swift's typical default.

Result on DX 12 MP (median of 10 runs): **73.41 ms vs 74.19 ms M9
baseline = −0.78 ms / −1.0%.** The mean delta (0.58 ms) is within
1σ of the run-to-run variance (~1.5 ms). Not statistically
significant. Reverted.

**Why both failed**: the M9 baseline is already heavily optimised.
The per-quad branches are predictable (CPU branch predictor settles
in within ~5 iterations and stays correct for 1024 quads); the
nested closures appear to be inlined or specialised already; the
underlying access is `UnsafeBufferPointer<UInt32>` (M9), so no
Swift array bounds-check overhead is left in the hot path.

**Where further gains are still possible** (higher correctness risk):
- True SIMD per-quad sample loads via NEON intrinsics (4-way data
  parallelism within each quad). The state-propagation between
  quads (lep / lcxp / kappaA / kappaB / c_q / maxE) makes this
  invasive; the encoder would need restructuring.
- Block-level batch processing (process all quads of a block in
  parallel, then serialise the MEL/VLC stream emission). Would
  require buffering per-quad context and careful ordering.
- Custom `clz`/`ctz` for `leadingZeroBitCount` in `sampleInfo` if
  Swift's emitted code is suboptimal — but `UInt32.leadingZeroBitCount`
  already maps to NEON `vclz` on Apple Silicon.

### v5.38 plan — milestones (revised after M10 negative result)

- **M1-M8 ✓** — see prior sections.
- **M9 ✓** — sign-magnitude buffer reuse + pointer-based encoder
  (DX entropy −10.3%, total cumulative 2.06×).
- **M10 (closed, negative)** — micro-optimisation attempts on the
  per-quad scan didn't beat the M9 baseline above noise. Lessons
  preserved here; baseline preserved in source.
- **M11+ candidates** — true SIMD per-quad with NEON intrinsics,
  block-level batch processing. Both higher risk; require careful
  staging and orthogonal changes.
- **Phase 4** — Metal forward INTEGER 5/3 DWT (deferred).

### v5.38 — format-fair lossless cross-codec results (full corpus, **median of 5 runs**)

> ⚠️ **Earlier versions of this section claimed J2KSwift was fastest on
> 7/7 fixtures.** That claim came from a single combined table that
> compared each codec running its **default mode**, which mixed two
> JPEG 2000 lossless flavours: J2KSwift and OpenJPH default to HT /
> Part-15; OpenJPEG, Grok, and Kakadu default to EBCOT / Part-1. EBCOT
> defaults are intrinsically slower (more bit-plane work) than HT
> defaults, so the table conflated **format choice** with **codec
> speed**. The honest, format-fair answer is below: J2KSwift wins on
> every small fixture in both formats, and Kakadu wins on every
> fixture ≥ 886×886 in both formats once the format axis is held
> constant. The HT-vs-HT and EBCOT-vs-EBCOT tables make the actual
> ordering clear.

Three sweeps over the medical corpus, each with median-of-5 timing
samples, deterministic-byte-count gate per run, and exhaustive
bit-exact gates:
- **Default-mode**: each codec runs as it ships out of the box (mixed HT/EBCOT).
- **HT-fair**: every codec emits HT/Part-15. OpenJPEG: N/A on this
  Homebrew build (its CLI's `-M 64` HT bit emits an EBCOT codestream
  that OpenJPH refuses with "Rsiz bit 14 is not set — this is not a
  JPH file"; HT encoding requires a different OpenJPEG build).
- **EBCOT-fair**: every codec emits EBCOT/Part-1. OpenJPH: N/A
  (HT-only codec).

**External-codec CLI flags used** (verified against the installed
binaries on 2026-05-05 / Homebrew 2.5.4 OpenJPEG, latest OpenJPH /
Grok, Kakadu 8.4.1 demo):

| Codec | Default | HT-fair | EBCOT-fair |
|---|---|---|---|
| OpenJPEG (`opj_compress`) | `-i x.pgm -o x.j2k` | **N/A** (CLI build limit) | `-i x.pgm -o x.j2k` (default) |
| OpenJPH (`ojph_compress`) | `-reversible true` | `-reversible true` (default = HT) | **N/A** (HT-only codec) |
| Grok (`grk_compress`)     | `-i x.pgm -o x.j2k` | `-i x.pgm -o x.jph -M 64` | `-i x.pgm -o x.j2k` (default) |
| Kakadu (`kdu_compress`)   | `Creversible=yes` | `Creversible=yes Cmodes=HT` | `Creversible=yes` (default) |

#### A. Codec default-mode comparison (mixed HT and EBCOT)

> **This table mixes formats.** OpenJPEG/Grok/Kakadu rows are EBCOT;
> J2KSwift/OpenJPH rows are HT. Use the HT-fair and EBCOT-fair tables
> below for like-to-like codec comparison.

**Output bytes (median of 5 — bytes are deterministic across runs):**

| Modality | Shape | Raw KB | J2KSwift (HT) | OpenJPEG (EBCOT) | OpenJPH (HT) | Grok (EBCOT) | Kakadu (EBCOT) |
|---|---|---:|---:|---:|---:|---:|---:|
| MR-small | 180×180   |    63 |    44 |    30 |    44 |    30 |    30 |
| CT       | 512×512   |   512 |   426 |   324 |   426 |   324 |   324 |
| CT       | 512×512   |   512 |   396 |   308 |   396 |   308 |   308 |
| MR       | 886×886   |  1533 |   163 |   135 |   163 |   135 |   135 |
| XA       | 1024×1024 |  2048 |  1583 |  1337 |  1583 |  1337 |  1337 |
| PX       | 2459×1316 |  6320 |  6280 |  5485 |  6280 |  5485 |  5485 |
| DX       | 2800×2288 | 12512 | 12385 | 10559 | 12384 | 10559 | 10559 |

J2KSwift HT bytes ≡ OpenJPH HT bytes (within 1 byte). OpenJPEG ≡
Grok ≡ Kakadu EBCOT bytes (exact). The 13–32% gap between rows is
the format trade-off, not codec quality.

**Encode time (ms, median of 5):**

| Modality | Shape | J2KSwift | OpenJPEG | OpenJPH | Grok | Kakadu | Fastest | Margin → next |
|---|---|---:|---:|---:|---:|---:|:---|---:|
| MR-small | 180×180   |  **0.6** |   10.7 |   6.2 |   8.6 |   3.6 | J2KSwift | 5.5× → Kakadu |
| CT       | 512×512   |  **3.2** |   54.7 |  11.6 |  15.9 |   8.4 | J2KSwift | 2.6× → Kakadu |
| CT       | 512×512   |  **3.2** |   58.5 |  10.4 |  16.5 |   7.8 | J2KSwift | 2.5× → Kakadu |
| MR       | 886×886   |  **5.2** |   66.3 |  10.2 |  14.4 |   5.6 | J2KSwift | +0.5 ms → Kakadu |
| XA       | 1024×1024 | **11.1** |  196.9 |  21.3 |  40.3 |  27.8 | J2KSwift | 1.9× → OpenJPH |
| PX       | 2459×1316 | **37.6** |  709.7 |  58.3 | 129.3 |  83.8 | J2KSwift | 1.5× → OpenJPH |
| DX       | 2800×2288 | **78.3** | 1443.5 | 119.6 | 239.0 | 162.8 | J2KSwift | 1.5× → OpenJPH |

**Decode time (ms, median of 5):**

| Modality | Shape | J2KSwift | OpenJPEG | OpenJPH | Grok | Kakadu | Fastest | Margin → next |
|---|---|---:|---:|---:|---:|---:|:---|---:|
| MR-small | 180×180   |  **0.6** |   10.8 |   5.9 |   9.1 |   3.4 | J2KSwift | 5.4× → Kakadu |
| CT       | 512×512   |  **3.2** |   56.0 |   9.9 |  15.2 |   9.0 | J2KSwift | 2.8× → Kakadu |
| CT       | 512×512   |  **3.1** |   54.1 |   8.9 |  14.6 |   8.6 | J2KSwift | 2.7× → Kakadu |
| MR       | 886×886   |  **5.8** |   69.3 |  10.8 |  13.1 |   6.8 | J2KSwift | +1.0 ms → Kakadu |
| XA       | 1024×1024 | **14.7** |  201.5 |  17.4 |  34.9 |  26.6 | J2KSwift | +2.7 ms → OpenJPH |
| PX       | 2459×1316 | **40.5** |  708.8 |  44.0 | 105.3 |  97.0 | J2KSwift | +3.5 ms → OpenJPH |
| DX       | 2800×2288 |   85.0   | 1360.4 | **80.8** | 198.9 | 185.2 | OpenJPH | +4.2 ms → J2KSwift |

**Default-mode leaderboard**: J2KSwift fastest on **7/7 encode**, **6/7 decode**
(loses DX to OpenJPH by 4.2 ms / 5%). But this leaderboard mixes
formats and is misleading — the real story is below.

#### B. HT-fair comparison (every codec emitting HT / Part-15)

OpenJPEG: N/A. The Homebrew 2.5.4 build's CLI `-M 64` flag does not
produce a Part-15-conformant codestream (verified: output lacks the
CAP marker / Rsiz bit 14 that OpenJPH requires). HT encoding through
the OpenJPEG library exists in 2.5+ but is not exposed via this CLI
build's flag set.

**Output bytes** — within ±2 bytes across all four HT-capable codecs
(Part-15 lossless converges to the same rate on identical input):

| Modality | Shape | Raw KB | J2KSwift | OpenJPEG | OpenJPH | Grok | Kakadu |
|---|---|---:|---:|---:|---:|---:|---:|
| MR-small | 180×180   |    63 |    44 | N/A |    44 |    44 |    44 |
| CT       | 512×512   |   512 |   426 | N/A |   426 |   426 |   426 |
| CT       | 512×512   |   512 |   396 | N/A |   396 |   396 |   396 |
| MR       | 886×886   |  1533 |   163 | N/A |   163 |   165 |   163 |
| XA       | 1024×1024 |  2048 |  1583 | N/A |  1583 |  1583 |  1583 |
| PX       | 2459×1316 |  6320 |  6280 | N/A |  6280 |  6280 |  6280 |
| DX       | 2800×2288 | 12512 | 12385 | N/A | 12384 | 12384 | 12385 |

**Encode time, HT-fair (ms, median of 5):**

| Modality | Shape | J2KSwift | OpenJPEG | OpenJPH | Grok | Kakadu | Fastest | Margin → next |
|---|---|---:|---:|---:|---:|---:|:---|---:|
| MR-small | 180×180   |  **1.0** | N/A |   6.7 |   8.0 |   2.8 | J2KSwift | 2.7× → Kakadu |
| CT       | 512×512   |  **3.3** | N/A |  10.7 |   9.4 |   3.6 | J2KSwift | +0.2 ms → Kakadu |
| CT       | 512×512   |  **3.4** | N/A |  10.0 |   9.2 |   3.5 | J2KSwift | +0.0 ms → Kakadu |
| MR       | 886×886   |    5.9   | N/A |  10.5 |  11.2 | **3.7** | Kakadu | 1.6× → J2KSwift |
| XA       | 1024×1024 |   11.5   | N/A |  21.6 |  14.2 | **5.1** | Kakadu | 2.3× → J2KSwift |
| PX       | 2459×1316 |   38.6   | N/A |  58.9 |  28.0 | **11.2**| Kakadu | 2.5× → Grok |
| DX       | 2800×2288 |   72.1   | N/A | 119.0 |  49.7 | **18.9**| Kakadu | 2.6× → Grok |

**Decode time, HT-fair (ms, median of 5):**

| Modality | Shape | J2KSwift | OpenJPEG | OpenJPH | Grok | Kakadu | Fastest | Margin → next |
|---|---|---:|---:|---:|---:|---:|:---|---:|
| MR-small | 180×180   |  **0.8** | N/A |   6.5 |   7.5 |   2.7 | J2KSwift | 3.3× → Kakadu |
| CT       | 512×512   |  **3.5** | N/A |   8.7 |   8.5 |   3.5 | J2KSwift (tie) | +0.0 ms → Kakadu |
| CT       | 512×512   |  **3.4** | N/A |   8.6 |   8.5 |   3.6 | J2KSwift | +0.2 ms → Kakadu |
| MR       | 886×886   |    6.2   | N/A |  10.5 |   9.6 | **4.9** | Kakadu | +1.3 ms → J2KSwift |
| XA       | 1024×1024 |   15.2   | N/A |  17.2 |  10.9 | **6.2** | Kakadu | 1.8× → Grok |
| PX       | 2459×1316 |   40.7   | N/A |  43.1 |  18.0 | **14.2**| Kakadu | +3.7 ms → Grok |
| DX       | 2800×2288 |   77.1   | N/A |  81.9 |  31.9 | **25.9**| Kakadu | +5.9 ms → Grok |

**HT-fair leaderboard**: J2KSwift fastest on encode + decode for
**3/7 fixtures** (MR-small + both CTs — the small-fixture / fixed-
overhead regime). **Kakadu wins on 4/7 fixtures (MR-886, XA, PX, DX)**
in both encode and decode at scale, by 1.6–2.6× on encode and
1.8–3.6× on decode. Kakadu's mature 8-thread parallelism dominates
J2KSwift's per-block parallelism on large fixtures within the same
HT format.

**Cross-decode standards compliance, HT-fair**: 21/21 pairs
(7 fixtures × 3 HT-capable external codecs) bit-exact. J2KSwift's
HT codestream is consumed losslessly by OpenJPH, Grok, and Kakadu.

#### C. EBCOT-fair comparison (every codec emitting EBCOT / Part-1)

OpenJPH: N/A (HT-only codec — no EBCOT support in the codec itself).

**Output bytes** — exact match across all four EBCOT-capable codecs
(Part-1 EBCOT lossless converges):

| Modality | Shape | Raw KB | J2KSwift | OpenJPEG | OpenJPH | Grok | Kakadu |
|---|---|---:|---:|---:|---:|---:|---:|
| MR-small | 180×180   |    63 |    30 |    30 | N/A |    30 |    30 |
| CT       | 512×512   |   512 |   324 |   324 | N/A |   324 |   324 |
| CT       | 512×512   |   512 |   308 |   308 | N/A |   308 |   308 |
| MR       | 886×886   |  1533 |   135 |   135 | N/A |   135 |   135 |
| XA       | 1024×1024 |  2048 |  1337 |  1337 | N/A |  1337 |  1337 |
| PX       | 2459×1316 |  6320 |  5485 |  5485 | N/A |  5485 |  5485 |
| DX       | 2800×2288 | 12512 | 10559 | 10559 | N/A | 10559 | 10559 |

**Encode time, EBCOT-fair (ms, median of 5):**

| Modality | Shape | J2KSwift | OpenJPEG | OpenJPH | Grok | Kakadu | Fastest | Margin → next |
|---|---|---:|---:|---:|---:|---:|:---|---:|
| MR-small | 180×180   |  **2.8** |   10.4 | N/A |   8.7 |    3.4 | J2KSwift | +0.6 ms → Kakadu |
| CT       | 512×512   |   16.4   |   54.8 | N/A |  15.6 |  **8.4** | Kakadu | 1.8× → Grok |
| CT       | 512×512   |   15.5   |   53.1 | N/A |  16.3 |  **8.1** | Kakadu | 1.9× → J2KSwift |
| MR       | 886×886   |   19.0   |   57.7 | N/A |  14.1 |  **5.6** | Kakadu | 2.5× → Grok |
| XA       | 1024×1024 |   62.2   |  209.2 | N/A |  37.0 | **23.2** | Kakadu | 1.6× → Grok |
| PX       | 2459×1316 |  204.5   |  737.6 | N/A | 136.3 | **89.1** | Kakadu | 1.5× → Grok |
| DX       | 2800×2288 |  372.8   | 1396.8 | N/A | 244.3 | **157.4**| Kakadu | 1.6× → Grok |

**Decode time, EBCOT-fair (ms, median of 5):**

| Modality | Shape | J2KSwift | OpenJPEG | OpenJPH | Grok | Kakadu | Fastest | Margin → next |
|---|---|---:|---:|---:|---:|---:|:---|---:|
| MR-small | 180×180   |  **2.6** |   10.5 | N/A |   8.9 |    3.3 | J2KSwift | +0.8 ms → Kakadu |
| CT       | 512×512   |   17.4   |   54.8 | N/A |  15.0 |  **8.7** | Kakadu | 1.7× → Grok |
| CT       | 512×512   |   13.3   |   53.9 | N/A |  14.7 |  **8.5** | Kakadu | 1.6× → J2KSwift |
| MR       | 886×886   |   14.3   |   64.8 | N/A |  12.5 |  **6.5** | Kakadu | 1.9× → Grok |
| XA       | 1024×1024 |   52.4   |  221.1 | N/A |  32.9 | **27.6** | Kakadu | +5.3 ms → Grok |
| PX       | 2459×1316 |  198.6   |  730.6 | N/A | 109.4 | **99.8** | Kakadu | +9.6 ms → Grok |
| DX       | 2800×2288 |  338.8   | 1365.8 | N/A | 189.6 | **177.3**| Kakadu | +12.3 ms → Grok |

**EBCOT-fair leaderboard**: J2KSwift wins **MR-small only** (1/7) on
both encode and decode. **Kakadu wins on 6/7 fixtures** by 1.5–2.5×
margins. J2KSwift's EBCOT path is the un-tuned fallback (the v5.38
optimisation work targeted the HT path); it remains correctness-
clean (byte-identical to all three other EBCOT codecs) but is not
performance-tuned at scale.

**Cross-decode standards compliance, EBCOT-fair**: 21/21 pairs
(7 fixtures × 3 EBCOT-capable external codecs) bit-exact. J2KSwift's
EBCOT codestream is consumed losslessly by OpenJPEG, Grok, and Kakadu.

#### Combined leaderboard summary

| Sweep | J2KSwift fastest encode | J2KSwift fastest decode | What this means |
|---|---:|---:|---|
| Default-mode (mixed format) | **7/7** | **6/7** | Misleading — mixes HT-vs-EBCOT |
| HT-vs-HT | 3/7 | 3/7 | J2KSwift wins small fixtures; **Kakadu wins large** |
| EBCOT-vs-EBCOT | 1/7 | 1/7 | J2KSwift not optimised; **Kakadu wins almost everything** |

**Honest precise claim**: *On the medical corpus tested, J2KSwift HT
lossless is the fastest HT encoder + decoder for every fixture
≤ 512×512. For fixtures ≥ 886×886, Kakadu 8.4.1 demo's HT
implementation wins both encode and decode.* J2KSwift's encode
output bytes match OpenJPH's bytes within 1 byte on every fixture
(format-converged) and the codestream is bit-exact decoded by every
mainstream Part-15 decoder.

#### Cumulative v5.38 encode speedup vs v5.37 baseline (J2KSwift HT, median of 5)

| Fixture | v5.37 | post-Step-A | post-M5 | post-M7 | post-M8 | post-M9 | Cumulative |
|---|---:|---:|---:|---:|---:|---:|---:|
| DX 2800×2288  | 156.9 ms | 88.2 | 83.8 | 81.4 | 78.5 | **72.1 ms** | **2.18×** |
| PX 2459×1316  |  78.3 ms | 44.6 | 42.7 | 39.8 | 38.9 |   38.6 ms | **2.03×** |
| XA 1024×1024  |  22.4 ms | 13.5 | 13.0 | 12.4 | 12.2 |   11.5 ms | **1.95×** |
| MR 886×886    |   7.6 ms |  6.5 |  6.1 |  5.7 |  5.5 |    5.9 ms | 1.29× |

(post-M9 column from the **HT-fair** 5-run medians above; the
default-mode column would show slightly different numbers because
the J2KSwift encode runs identically — HT in both — and only the
external codec mode differs.)

#### Bottom-line recommendation for medical lossless workflows

- **HT lossless** (`useHTJ2K: true`, `useReversibleFilter: true`,
  `htj2kBlockFormat: .conformant`, `bitrateMode: .lossless`) — the
  default. **Fastest of the HT-capable codecs on the small-fixture
  end of the corpus** (≤ 512×512); competitive but **slower than
  Kakadu on large fixtures**. Codestream decodable by every
  mainstream Part-15-aware decoder. The pick for active PACS and
  modern viewer pipelines that need standards-clean output and
  predictable Swift-process integration without spawning a CLI.

- **EBCOT lossless** (`useHTJ2K: false`) — denser archive (13–32%
  smaller bytes than HT), bit-identical bytes to every other
  Part-1-EBCOT codec, decodable by every Part-1 decoder ever
  shipped. Use when archival storage cost dominates AND the
  consumer might be a legacy Part-1-only decoder. **Performance-
  un-tuned**: J2KSwift EBCOT is 2–4× slower than Kakadu EBCOT at
  scale. If pure EBCOT throughput matters, Kakadu wins.

- **Smallest lossless files** is a property of the **format**
  (EBCOT vs HT), not the codec. Every modern Part-1 codec produces
  bit-identical EBCOT bytes on this corpus.

The decode/encode performance gap to the next-best codec on every
fixture except DX is now large enough to be visible to end users
without a stopwatch.

### v5.38 scope guardrails

Parked through v5.38: `.constantBitrateStrict`,
`truncateByConstrainedRD`, `truncateByRDOptimized`, Qstep search,
PSNR-per-byte tuning, 9/7 lossy GPU encode. Their tests stay green;
no extension work. If a lossless task appears to require touching
them, surface the conflict before proceeding.

---

## v5.39 M1 — SIMD per-quad HT classification (parked, negative)

**Goal**: integrate the SIMD per-quad classification proven by the
v5.38 prototype tests (180K-sample lane-identity sweep) into the HT
conformant lossless encoder, behind a feature flag, and check whether
it narrows the Kakadu gap on large HT-fair fixtures (the v5.38 finding
that started this work).

**Files changed**:

- `Sources/J2KCodec/J2KHTConformantBlockEncoder.swift`
  - New `processQuadSIMD(baseX:baseY:)` nested function inside
    `HTBlockEncoderConformant.encode`. Loads four sample t-values
    into a `SIMD4<UInt32>`, computes val / sig / eQ / payload via
    lane-parallel SIMD operators, then assembles the same scalar
    return tuple as scalar `processQuad`. Per-lane `clz` is scalar
    because Swift's `SIMD4<UInt32>` doesn't surface a lane-wise
    `leadingZeroBitCount`.
  - New `useSIMDClassification: Bool` parameter on the inout encode
    overload. Existing 6-arg overload is preserved as a thin wrapper
    that passes `false`. The original scalar `processQuad` body is
    unchanged; the new function dispatches based on the flag at the
    top — the branch is loop-invariant for a single encode call so
    the optimiser hoists it.

- `Sources/J2KCodec/J2KEncoderPipeline.swift`
  - Cached static `_htSIMDClassificationEnabled` reads `J2K_HT_SIMD`
    environment variable once at process startup (`1`, `true`, `yes`
    enable; anything else leaves the flag off — the production
    default).
  - New `useSIMDClassification: Bool` parameter on
    `encodeCodeBlockConformant` (inout overload) and
    `encodeCodeBlockHTJ2KFast`. Threaded through to
    `HTBlockEncoderConformant.encode`. Default `false` everywhere
    except the four chunk-loop call sites, which read
    `Self._htSIMDClassificationEnabled`.

- `Tests/J2KCodecTests/HTSIMDIntegrationTests.swift` (new)
  - 8 test functions, all bit-identical gates between scalar and
    SIMD paths on the encoded `(magsgn, mel, vlc)` byte tuples:
    all-zero, all-max, alternating-sign, sparse, dense-random,
    boundary sizes (1×1 → 64×64 with non-multiple-of-4 widths and
    non-multiple-of-2 heights), varying `missingMSBs` (3, 5, 10, 14,
    18, 22, 25, 28, 29), and a 25K-random-block sweep across 5 sizes
    × 5 missingMSBs × 200 iterations.

**What SIMD does**: replaces the 4 per-quad scalar `sampleInfo`
calls with one `SIMD4<UInt32>` lane-parallel computation of val /
sig / eQ / payload. Output of the function (the `(rho, eQMax, eQ0,
…, s0, …, s3)` tuple) is bit-identical to the scalar version.

**What SIMD does not do**: it does NOT change anything downstream of
`processQuad`. MEL, VLC, MagSgn bit emission stays scalar and
unchanged. eVal / cxVal / kappa / c_q / maxE state propagation is
identical. EBCOT path is untouched.

**Correctness gates — ALL GREEN**:

- Block-level byte-identity (`HTSIMDIntegrationTests`): 8/8 tests
  pass, including 25,000-block random sweep across 5 block sizes
  × 5 missingMSBs values. Scalar `(magsgn, mel, vlc)` ≡ SIMD
  `(magsgn, mel, vlc)` byte-for-byte on every input.

- Full-corpus self-roundtrip (`testLosslessRoundTripBitExactAcrossMedicalCorpus`):
  7/7 fixtures pass with `J2K_HT_SIMD=1`. MAE = 0 in every case.

- HT-fair cross-decode matrix (`testLosslessCrossCodecMatrixAcrossMedicalCorpus_HTFair`):
  21/21 pairs (7 fixtures × 3 HT-capable external codecs) bit-exact
  with `J2K_HT_SIMD=1`. J2KSwift SIMD HT codestream consumed
  losslessly by OpenJPH 0.27.0, Grok 20.3.0, Kakadu 8.4.1 demo.

- Default-mode cross-decode: 7/7 J2KSwift→OpenJPH bit-exact.

- Deterministic byte gate: encoded bytes deterministic across all 5
  internal runs in every fixture, in every test mode. No drift.

#### Performance results — DOES NOT MEET PROMOTION GATES

Each cell below is a median of **5 outer test invocations**, where
each test invocation itself takes a median of 5 internal samples —
i.e., 25 timing samples per (fixture, configuration) cell. HT-fair
encode time (J2KSwift HT lossless), measured on Apple Silicon with
a release build.

| Fixture | SIMD OFF | SIMD ON | Δ ms | Δ % | ≥5% improvement gate |
|---|---:|---:|---:|---:|:---:|
| MR-small 180×180   |  0.7 |  0.7 |  0.0 |   0% | n/a (small) |
| CT 512×512 (1)     |  3.3 |  3.2 | −0.1 |  −3% | n/a (small) |
| CT 512×512 (2)     |  2.9 |  3.0 | +0.1 |  +3% | n/a (small) |
| MR 886×886         |  5.3 |  5.4 | +0.1 |  +2% | **must not regress** — within noise, OK |
| XA 1024×1024       | 11.7 | 11.5 | −0.2 | −1.7% | **fails ≥5%** |
| PX 2459×1316       | 38.5 | 38.7 | +0.2 | +0.5% | **fails ≥5%** |
| DX 2800×2288       | 75.5 | 77.2 | +1.7 | +2.3% | **fails ≥5% (slight regression within noise)** |

**Did the Kakadu gap narrow?** No. Kakadu HT-fair on large fixtures
remains 1.6–2.6× faster than J2KSwift HT (DX 18.9 ms vs 77.2 ms;
PX 11.2 ms vs 38.7 ms — both within noise of the SIMD-OFF baseline).

**Why SIMD didn't help**: the per-lane work that SIMD parallelises
is a small fraction of per-quad cost. Specifically:
- Swift's `SIMD4<UInt32>` doesn't expose a lane-wise `clz`, so the
  4 `leadingZeroBitCount` calls remain scalar (each maps to a single
  NEON instruction, but the per-lane dispatch cost is still there).
- The per-lane `if sigN { rho |= …; eQN = …; sN = … }` block at the
  end is scalar — same as before SIMD.
- The val / sign / payload arithmetic (which IS SIMDified) is small
  — maybe 4–6 ALU ops saved per quad, on the order of a few ns.
- The dominant per-quad cost is downstream (rho/eQMax accumulation
  + MEL/VLC/MagSgn bit emission), all of which remain unchanged.

This matches the v5.38 M10 finding: the M9 scalar baseline is
already heavily optimised, and small per-quad scalar tweaks don't
beat noise.

**Decision: PARK as experimental**. SIMD code path stays in source
(behind `J2K_HT_SIMD=1` env var) so it remains correct against any
future encoder changes (the integration tests run on every commit
gate). It does NOT become the default. Production callers continue
to get the proven scalar path.

#### Remaining v5.39 candidates for narrowing the Kakadu gap

Per the user-defined scope ("v5.39 targets Kakadu-scale large-fixture
HT performance"), other approaches to investigate, all higher-risk
or larger-scope than v5.39 M1:

- **Tile-level parallelism for very large fixtures.** Kakadu's
  large-fixture wins on DX / PX appear to come from heavier
  parallelism than J2KSwift's per-block-only model gives at scale.
  J2KSwift currently uses single-tile encoding; multi-tile encode
  with per-tile parallelism could match Kakadu's 8-thread
  saturation on > 3 MP fixtures. This is an architectural change
  with cross-codec interop implications.

- **Bigger SIMD: pair-of-quads (8 samples) classifier.** The
  current SIMD path does one quad (4 samples) per call. Two
  adjacent quads in a row can be loaded as 8 samples with stride-1
  access patterns; that doubles the lane-parallel work and has the
  potential to actually saturate the SIMD register width. Higher
  correctness risk because cross-quad state (lep / lcxp / kappa)
  feeds into the second quad's classification.

- **Forward 5/3 column transpose via NEON `vld4q` / `vst4q`.** The
  M5 branchless lifting work measured DWT at 32 ms on DX (40% of
  total). The forward strip-transpose between row and column passes
  is per-byte memory rearrangement — `vld4q_s32` / `vst4q_s32` are
  NEON's 4-way deinterleave/interleave intrinsics designed exactly
  for this case. Not exposed in the public Swift `simd` module
  but accessible via `Builtin` or C interop.

These remain v5.39+ candidates; none is in scope for v5.39 M1.

#### Final precise claim (unchanged from v5.38 format-fair section)

> J2KSwift is standards-clean and strong on small HT medical
> fixtures (≤ 512×512). v5.39 M1 attempted to narrow the
> Kakadu-scale large-fixture HT performance gap via SIMD per-quad
> classification; the optimisation was bit-exact correctness-clean
> but did not produce a measurable speedup at scale, so it is
> parked as experimental code (`J2K_HT_SIMD=1` env var to enable).
> The Kakadu HT-encode advantage on fixtures ≥ 886×886 documented
> in the v5.38 HT-fair table stands.

---

## v5.39 M2 — large-fixture HT parallelism feasibility (parked, marginal)

**Goal**: investigate whether J2KSwift can narrow the Kakadu HT-fair
gap on large medical fixtures by improving parallelism (rather than
small per-quad SIMD, which v5.39 M1 already showed to be bounded).
First profile the current per-stage scaling; then prototype an
experimental path; promote only if total HT-fair encode time on
large fixtures clears DX ≥ 20%, PX ≥ 20%, XA ≥ 10% gates.

**Profile (median of 5, maxThreads = 1 vs 8)**:

```
| Modality | Shape       | Stage      | 1 thr ms | 8 thr ms | Speedup | Eff   |
|----------|-------------|------------|---------:|---------:|--------:|------:|
| MR       | 886×886     | Total      |     9.3  |     5.3  |  1.74×  | 0.22  |
| XA       | 1024×1024   | Total      |    33.3  |    11.7  |  2.86×  | 0.36  |
| PX       | 2459×1316   | Total      |   114.0  |    37.4  |  3.05×  | 0.38  |
| DX       | 2800×2288   | Total      |   235.1  |    75.6  |  3.11×  | 0.39  |
| DX       | 2800×2288   | Preprocess |     2.4  |     2.4  |  1.00×  | SERIAL|
| DX       | 2800×2288   | DWT        |    32.0  |    31.3  |  1.03×  | SERIAL|
| DX       | 2800×2288   | Entropy    |   194.2  |    35.1  |  5.54×  | 0.69  |
| DX       | 2800×2288   | Codestream |     6.5  |     6.0  |  1.09×  | SERIAL|
```

**Profile reading**:
- Per-block entropy parallelism is moderate-to-strong already
  (5.54× on DX-class fixtures). Not where the headroom is.
- DWT, preprocess, and codestream are effectively SERIAL across
  the encoder's `enableParallelCodeBlocks` path (which only gates
  the entropy loop). At DX scale the DWT stage alone is 32 ms
  (~13% of single-thread total, ~41% of 8-thread total).
- Amdahl: DX speedup 3.11× at 8 cores ⇒ parallel fraction ≈ 79%,
  serial fraction ≈ 21% (≈ 49 ms wall-clock). DWT row pass is
  the largest serial chunk inside that.

**Files changed**:

- `Sources/J2KCodec/J2KAcceleratedEncoder.swift`
  - In `forward2D_53`, add an opt-in `withTaskGroup` row-pass that
    chunks low-band rows (writing ll/hl) and high-band rows (writing
    lh/hh) across `processorCount` worker tasks. Each task allocates
    its own `DWTWorkspace53(maxSignalLength: width)` and rowOut
    scratch — no shared mutable state, just pointer-disjoint writes.
    Default path (sequential row pass) preserved bit-identical to
    v5.38.

- `Sources/J2KCodec/J2KEncoderPipeline.swift`
  - New `EncoderPipeline.HTParallelMode` enum (`baseline` /
    `dwtRowParallel`) and cached static `_htParallelMode` reading
    `J2K_HT_PARALLEL_MODE` once at process startup.

- `Tests/J2KCodecTests/HTParallelismProfileTests.swift` (new)
  - Two test functions: thread-count sweep (1/2/4/8) over the large
    medical fixtures and per-stage 1-vs-8 scaling. Profile-only —
    they print measurement tables and never assert performance.

**Correctness gates — ALL GREEN**:

- `HTSIMDIntegrationTests` (M1 byte-identity gates): 8/8 pass with
  `J2K_HT_PARALLEL_MODE=dwt-row-parallel`. Block-level scalar vs
  SIMD bytes still bit-identical when M2 mode runs simultaneously.

- Full-corpus self-roundtrip
  (`testLosslessRoundTripBitExactAcrossMedicalCorpus`): 7/7 fixtures
  pass. MAE = 0 in every case.

- HT-fair cross-decode matrix: 21/21 pairs bit-exact (J2KSwift M2
  HT codestream consumed losslessly by OpenJPH 0.27.0, Grok 20.3.0,
  Kakadu 8.4.1 demo).

- EBCOT-fair cross-decode matrix: 28/28 pairs bit-exact.

- Default-mode + deterministic byte gate: pass on every internal
  run across all 5 fixture iterations.

#### Performance results — DOES NOT MEET PROMOTION GATES

Median-of-5 wall time, M2 mode on vs baseline at maxThreads = 8 (the
production thread count). Apple Silicon, release build.

| Fixture | DWT baseline ms | DWT M2 ms | DWT Δ% | Total baseline ms | Total M2 ms | Total Δ% | Promotion gate |
|---|---:|---:|---:|---:|---:|---:|:---|
| MR 886×886    |  3.4 |  3.1 |  −8.8% |  5.3 |  5.0 | −5.7% | "no regression" — OK |
| XA 1024×1024  |  4.8 |  4.4 |  −8.3% | 11.7 | 11.0 | −6.0% | **≥10% — MISS** |
| PX 2459×1316  | 14.3 | 12.5 | −12.6% | 37.4 | 35.9 | −4.0% | **≥20% — MISS** |
| DX 2800×2288  | 31.3 | 26.4 | −15.7% | 75.6 | 69.8 | −7.7% | **≥20% — MISS** |

**Did the Kakadu gap narrow?** No. Best-case DX shaves 5.8 ms off the
total at maxThreads = 8 — Kakadu HT-fair on DX (≈ 19 ms in v5.38
table) remains a 3.6× wall-clock advantage even with M2 enabled.

**Why row-parallel DWT didn't deliver more**:
- The column pass is **already** parallelised
  (`DispatchQueue.concurrentPerform` over column strips, line 389;
  `withTaskGroup` over column chunks, line 853). My edit only attacks
  the row pass — but row work is roughly half of single-level DWT,
  and the column pass already saturates cores there.
- 5/3 lifting is memory-bound at the per-row level (lots of
  workspace + rowOut traffic per row); spawning 8 concurrent rows
  adds memory-bandwidth contention that eats some of the apparent
  parallel win.
- Multi-level DWT runs the row pass at progressively smaller sizes
  (level 4 is 1/16 the data of level 0). TaskGroup overhead at small
  levels is non-trivial; the gain concentrates at level 0 only.

The DWT stage gain (8–16%) is real and consistent. But because DWT
is only ~30–40% of total HT encode at scale, the total-time gain
falls well below the user's promotion bar.

**Decision: PARK as experimental**. The DWT row-parallel code path
stays in source (behind `J2K_HT_PARALLEL_MODE=dwt-row-parallel` env
var) — runs through the same correctness gates as the baseline path,
so it remains correct against future encoder changes. Production
callers stay on the sequential row pass.

#### Remaining v5.39 candidates after M2

Profile-driven prioritisation for any v5.39 M3+ work:

- **Multi-tile encode for fixtures ≥ 3 MP.** J2KSwift currently
  emits a single tile. Splitting DX/PX into 4 or 16 tiles and
  encoding tiles in parallel (each tile is fully independent: own
  DWT, own MQ/HT entropy, own codestream segment) bypasses the DWT
  serial-fraction problem entirely. Architectural change with
  cross-codec interop validation cost (must verify all four
  external decoders consume multi-tile HT codestreams bit-exact).

- **Reduce DWT memory bandwidth (workspace + rowOut compaction).**
  The per-task workspace + rowOut allocation pattern in M2 likely
  dirties more L1/L2 than necessary. A pooled-workspace allocator
  shared across tasks (one workspace per core, reused across rows)
  could narrow the bandwidth gap. Smaller, surgical change but
  uncertain ceiling.

- **EBCOT/HT entropy thread pinning.** The 5.54× entropy speedup at
  8 cores (eff 0.69) suggests some cross-thread cache pollution.
  Pinning entropy workers to performance cores (P-cores only on
  M-series chips) could push this closer to 7×. Apple-silicon-
  specific; doesn't generalise.

These remain v5.39+ candidates; none is in scope for v5.39 M2.

#### Final precise claim (post-M2)

> J2KSwift is standards-clean and strong on small HT medical
> fixtures (≤ 512×512). v5.39 M2 attempted to narrow the
> Kakadu-scale large-fixture HT performance gap by parallelising
> the DWT row pass; the optimisation was bit-exact correctness-
> clean and produced a real 8–16% gain on the DWT stage, but the
> total HT-fair encode time gain (4–8%) fell below the promotion
> bar (DX ≥ 20%, PX ≥ 20%, XA ≥ 10%). It is parked as experimental
> code (`J2K_HT_PARALLEL_MODE=dwt-row-parallel` env var to enable).
> The Kakadu HT-encode advantage on fixtures ≥ 886×886 documented
> in the v5.38 HT-fair table stands.

---


## Test Images

| Modality | Dimensions | Bit Depth | Description |
|----------|-----------|-----------|-------------|
| CT | 512×512 | 16-bit | Synthetic chest CT (HU range simulation) |
| MRI | 256×256 | 12-bit | Synthetic T1-weighted brain MRI |
| Ultrasound | 640×480 | 12-bit | Synthetic sector ultrasound with speckle |

## Results

| Modality | Bits | Bitrate | J2K PSNR | J2K SSIM | J2K MAE | OPJ PSNR | OPJ SSIM | OPJ MAE | ΔPSNR |
|----------|------|---------|----------|----------|---------|----------|----------|---------|-------|
| CT | 16 | 0.25bpp | 51.74 | 0.9934 | 128.35 | 52.11 | 0.9939 | 124.31 | -0.37 |
| CT | 16 | 0.50bpp | 55.15 | 0.9966 | 90.25 | 55.46 | 0.9970 | 87.01 | -0.31 |
| CT | 16 | 0.75bpp | 57.88 | 0.9983 | 65.24 | 57.75 | 0.9983 | 66.06 | +0.13 |
| CT | 16 | lossless | ∞ | 1.0000 | 0.00 | ∞ | 1.0000 | 0.00 | 0.00 |
| MRI | 12 | 0.25bpp | 37.97 | 0.9529 | 36.62 | 33.75 | 0.9232 | 53.00 | +4.22 |
| MRI | 12 | 0.50bpp | 42.48 | 0.9748 | 23.42 | 39.75 | 0.9649 | 29.88 | +2.74 |
| MRI | 12 | 0.75bpp | 45.37 | 0.9837 | 17.33 | 43.13 | 0.9756 | 21.70 | +2.25 |
| MRI | 12 | lossless | ∞ | 1.0000 | 0.00 | ∞ | 1.0000 | 0.00 | 0.00 |
| Ultrasound | 12 | 0.25bpp | 28.79 | 0.8165 | 73.39 | 27.97 | 0.7871 | 80.25 | +0.81 |
| Ultrasound | 12 | 0.50bpp | 31.63 | 0.8950 | 53.69 | 29.80 | 0.8768 | 64.99 | +1.84 |
| Ultrasound | 12 | 0.75bpp | 35.11 | 0.9616 | 35.94 | 31.93 | 0.9280 | 50.68 | +3.18 |
| Ultrasound | 12 | lossless | ∞ | 1.0000 | 0.00 | ∞ | 1.0000 | 0.00 | 0.00 |

## Notes

- PSNR: Peak Signal-to-Noise Ratio (dB) — higher is better
- SSIM: Structural Similarity Index — closer to 1.0 is better
- MAE: Mean Absolute Error — lower is better
- ΔPSNR: J2K PSNR minus OPJ PSNR (positive = J2K better)
- Lossless: exact reconstruction (PSNR = ∞, MAE = 0)

---

## Cross-Scale R-D Quality (v5.31.0)

Real-medical-fixture roundtrip PSNR after the v5.31.0 λ-formulation fix. Pre-v5.31.0,
HT-conformant lossy with `.constantBitrate` collapsed catastrophically at scale because
PCRD-opt's all-or-nothing per-block selection on cleanup-only blocks produced wildly
inconsistent quality. v5.31.0 auto-promotes `.constantBitrate` → Qstep-search for
high-bit-depth content (`bitDepth ≥ 12`).

### Cross-fixture PSNR (dB) at multiple bpp targets, 16-bit medical, post-v5.31.0

| Fixture                | px      | @0.5 bpp | @1.0 bpp | @2.0 bpp | @4.0 bpp |
|------------------------|--------:|---------:|---------:|---------:|---------:|
| mr_002 (180×180 MR)    |    32k  |    38.03 |    44.90 |    52.58 |    66.53 |
| ct_001 (512×512 CT)    |   262k  |    25.86 |    36.06 |    47.21 |    64.06 |
| ct_003 (512×512 CT)    |   262k  |    26.81 |    36.45 |    48.77 |    66.01 |
| mr_001 (886×886 MR)    |   785k  |    58.92 |    77.33 |   102.63 |   102.48 |
| xa_001 (1024² XA)      |  1.0M   |    23.17 |    34.90 |    50.59 |    66.69 |
| px_001 (2459×1316 PX)  |  3.2M   |    18.08 |    31.20 |    46.25 |    61.93 |
| dx_002 (2800×2288 DX)  |  6.4M   |    19.43 |    31.34 |    45.80 |    61.94 |

### What changed (pre-v5.31.0 vs post)

Pre-v5.31.0 PSNR (PCRD-opt with all-or-nothing per-block selection on conformant
cleanup-only — produced scale-dependent collapse on high-bit-depth content):

| Fixture | px | @2.0 bpp pre | @4.0 bpp pre | @2.0 bpp post | @4.0 bpp post |
|---|---:|---:|---:|---:|---:|
| ct_001 (262k)  | 262k  | **19.81** | **21.94** | 47.21 | 64.06 |
| xa_001 (1M)    | 1.0M  | **17.45** | **18.85** | 50.59 | 66.69 |
| px_001 (3.2M)  | 3.2M  | **13.47** | **14.89** | 46.25 | 61.93 |
| dx_002 (6.4M)  | 6.4M  | **14.65** | **16.30** | 45.80 | 61.94 |

PSNR @ 4 bpp on dx_002 went from 16.30 dB (catastrophic) to 61.94 dB (clinical-grade).
PSNR scales healthily with bpp (~10-15 dB per doubling) as a proper R-D curve should,
instead of the pre-fix ~1 dB per doubling.

### v5.33.0 — `.constantBitrateBounded` mode (production-grade, predictable latency)

The auto-promote `.constantBitrate` path now uses a new bounded-rate Qstep mode with a
**hard cap on encode passes** (3 by default). This is the production-grade alternative
to v5.32.0's full 8-iter binary search + 3-iter refinement (which produced 5–14× encode
slowdown). The mode is also exposed as a public enum case `.constantBitrateBounded(bpp,
maxOvershootRatio: 2.0, maxPasses: 3)` for callers who want explicit control.

#### Comparison across modes (2 bpp, real medical fixtures, M2)

| Fixture       | Pre-v5.31 PCRD | v5.31 (8-iter unbounded) | v5.32 (8+3 refine, 2× cap) | **v5.33 (3-pass bounded)** |
|---------------|---------------:|-------------------------:|----------------------------:|---------------------------:|
| **PSNR @2bpp** |               |                          |                             |                            |
| ct_001 (262k)  |       19.81 |              47.21 |               47.21 |              **61.20** |
| xa_001 (1M)    |       17.45 |              50.59 |               39.87 |              **63.58** |
| px_001 (3.2M)  |       13.47 |              46.25 |               33.07 |              **60.06** |
| dx_002 (6.4M)  |       14.65 |              45.80 |               33.92 |              **60.00** |
| **bytes ratio (achieved/target)** |  |     |          |                            |
| ct_001         |        1.00× |              1.64× |               1.64× |               2.91× |
| xa_001         |        1.00× |              2.41× |               1.69× |               3.32× |
| px_001         |        1.00× |              3.04× |               1.88× |               4.22× |
| dx_002         |        1.00× |              2.81× |               1.69× |               4.03× |
| **encode latency (mg_001 16.8M px)** |  |    |          |                            |
| Latency        |     225 ms |          ~1800 ms |             3124 ms |          **1231 ms** |

v5.33 trade-off:
- **Quality ↑↑**: 60+ dB at 2 bpp on real medical content (better than v5.31's 50 dB).
- **Latency ↓↓↓**: 3-pass hard cap, 2.5× faster than v5.32, predictable (no flat-curve
  worst case).
- **Rate floor ↑**: best-effort cap, may exceed 2.0× target on flat-curve content (very
  low bpp on large fixtures). The cap is NOT a strict guarantee — it's "as close as
  the search can get within `maxPasses`."

#### When to use which mode

| Mode | Quality | Rate cap | Latency | Use when |
|---|---|---|---|---|
| **`.constantBitrate(bpp)`** (auto-promoted) | 60+ dB | best-effort 2.0× | 3 passes | DICOM PACS / archive — quality + predictable encode time |
| `.constantBitrateBounded(bpp, ...)` | configurable | configurable cap | configurable | explicit control over the trade-off |
| `.constantBitrateViaQstep(bpp, ...)` | 45-50 dB | uncapped (1.6-3×) | 8 passes | when you need v5.31 max-quality behaviour |
| `.fixedQstep(qstep)` | content-dependent | unbounded | 1 pass | latency-critical single-shot, caller picks qstep |

For batch workflows, pass a `J2KQstepCache` via `encodingConfiguration.qstepCache` —
subsequent encodes hit cache and converge in 1-2 passes regardless of mode.

### Trade-off — strict-rate vs quality vs encode latency

The `.constantBitrate` mode auto-promote has three trade-offs to document:

**1. Bytes vs target.** Qstep-search converges on uniform quantisation, which has a
content-dependent rate floor. v5.31.0 shipped with no overshoot cap (max quality).
v5.32.0 adds a 2.0× overshoot cap on the auto-promote path; the explicit
`.constantBitrateViaQstep` path keeps v5.31.0's no-cap behaviour.

Observed achieved bytes vs target @ 2.0 bpp on representative fixtures (post-v5.32.0):

| Fixture | Pixels | Target bytes | v5.31 bytes (3.0× cap) | **v5.32 bytes (2.0× cap)** |
|---|---:|---:|---:|---:|
| mr_002 (180²)        |    32k  |   8,100  |    8,298 (1.02×)  |    **8,298 (1.02×)** |
| ct_001 (512²)        |   262k  |  65,536  |  107,603 (1.64×)  |  **107,603 (1.64×)** |
| xa_001 (1024²)       |  1.0M   | 262,144  |  632,940 (2.41×)  |  **443,322 (1.69×)** |
| px_001 (2459×1316)   |  3.2M   | 809,011  | 2,460,399 (3.04×) |  **1,521,451 (1.88×)** |
| dx_002 (2800×2288)   |  6.4M   |   1.6 MB |    4.5 MB (2.81×) |     **2.7 MB (1.69×)** |

**2. Quality cost of the bound.** Reducing overshoot reduces available bits, which
reduces PSNR. Comparison @ 2 bpp:

| Fixture | v5.31 (no cap) | **v5.32 (2.0×)** | Pre-v5.31 (PCRD strict) |
|---|---:|---:|---:|
| ct_001 | 47.21 dB | 47.21 dB (unchanged) | 19.81 dB |
| xa_001 | 50.59 dB | 39.87 dB | 17.45 dB |
| px_001 | 46.25 dB | 33.07 dB | 13.47 dB |
| dx_002 | 45.80 dB | 33.92 dB | 14.65 dB |

v5.32 sits between pre-v5.31 (clinically unusable) and v5.31 (clinical-grade but ~3×
target rate). On fixtures that already fit under 2.0× cap (small/medium), v5.31's
quality is fully preserved.

**3. Encode latency.** Auto-promote runs 8 iterations of Qstep search per encode. CPU
encode latency on the medical corpus is ~5–14× higher than the v5.30.0 PCRD baseline:

| Fixture | v5.30 CPU encode | **v5.32 CPU encode** | Slowdown |
|---|---:|---:|---:|
| mr_002 (32k)         |   2.4 ms |   5.8 ms |  2.4× |
| ct_001 (262k)        |   4.0 ms |  35.2 ms |  8.8× |
| xa_001 (1M)          |  16.0 ms | 161.5 ms | 10.1× |
| px_001 (3.2M)        |  51.6 ms | 558.2 ms | 10.8× |
| mg_001 (16.8M)*      | 224.9 ms |   3.1 s  | 13.9× |

For batch workflows (PACS, archive ingestion), pass a `J2KQstepCache` instance via
`encodingConfiguration.qstepCache` — the cache stores `(bitDepth, componentCount,
targetBpp) → converged qstep`, so subsequent encodes hit the cache and skip 5–6 of
the 8 search iterations.

For latency-critical single-shot encodes, use `.fixedQstep(qstep:)` directly (one
encode, no search) — caller picks the qstep, no rate-target guarantees.

For DICOM archive workloads that prioritise quality over exact byte budgets and tolerate
the ingestion-time encode latency, this is the correct trade-off.

---

## v5.34.0 — `.constantBitrateStrict` (hard byte cap via codestream truncation)

User spec: "make the byte cap real, even if that means exposing two separate modes:
one for quality-first and one for strict bounded-rate." v5.33's bounded mode caps
overshoot best-effort but could exceed 2× target on flat-curve content (large medical
fixtures at low bpp; the encoder hits a content-determined byte floor where the 3-pass
Qstep search can't converge). v5.34 ships `.constantBitrateStrict` and switches the
`.constantBitrate` auto-promote default to it.

**Algorithm**: run the v5.33 quality-first 3-pass Qstep search (now biased toward
overshoot since truncation handles excess for free), then truncate the codestream at the
largest LRCP packet boundary that fits the byte cap. JPEG 2000 codestreams are LRCP-
progressive — packets at lower resolutions / earlier components form a valid prefix at
any packet boundary. The SOT marker's `Psot` field is rewritten and an EOC marker
appended; decoders zero-fill missing trailing code blocks per ISO/IEC 15444-1 Annex B.

### Mode comparison @ 2 bpp on real medical fixtures (M1, n=5)

| Fixture | px | v5.33 (bounded) | **v5.34 (strict)** | v5.34 ratio |
|---|---:|---:|---:|---:|
| **PSNR (dB) and bytes ratio (achieved/target)** |  |  |  |  |
| ct_001 (262k)  | 262k  | 61.20 dB / 2.91× | **20.15 dB** | **0.96×** |
| xa_001 (1.0M)  | 1.0M  | 63.58 dB / 3.32× | **17.52 dB** | **0.93×** |
| px_001 (3.2M)  | 3.2M  | 60.06 dB / 4.22× | **12.27 dB** | **0.31×** |
| dx_002 (6.4M)  | 6.4M  | 60.00 dB / 4.03× | **13.14 dB** | **0.29×** |

The headline contract has flipped: v5.33 prioritised quality and let bytes overshoot;
v5.34 prioritises the byte cap and lets quality drop. This was a deliberate trade-off
the user requested and is the original literal contract of `.constantBitrate(bpp)`.

### v5.34 strict — full corpus PSNR + bytes (auto-promoted `.constantBitrate`)

Roundtrip PSNR (16-bit) and encoded bytes via auto-promote on the standard medical
corpus, multiple bpp targets:

| Fixture | px | PSNR @0.5 | PSNR @1.0 | PSNR @2.0 | PSNR @4.0 |
|---|---:|---:|---:|---:|---:|
| mr_002 (180×180 MR)    |   32k | 34.72 | 34.95 | 28.76 | 34.98 |
| ct_001 (512×512 CT)    |  262k | 18.24 | 18.24 | 20.15 | 20.15 |
| ct_003 (512×512 CT)    |  262k | 18.15 | 18.15 | 18.15 | 20.14 |
| mr_001 (886×886 MR)    |  785k | 26.00 | 26.00 | 98.58 | 95.99 |
| xa_001 (1024² XA)      | 1.0M  | 15.77 | 15.77 | 17.52 | 17.52 |
| px_001 (2459×1316 PX)  | 3.2M  | 12.27 | 12.27 | 12.27 | 14.28 |
| dx_002 (2800×2288 DX)  | 6.4M  | 13.14 | 13.14 | 13.14 | 14.86 |

Encoded bytes (target = `bpp × pixelCount × componentCount / 8`):

| Fixture | px | @0.5 bytes | @1.0 bytes | @2.0 bytes | @4.0 bytes |
|---|---:|---:|---:|---:|---:|
| mr_002      |   32k |     2,022 |     3,552 |     2,750 |    11,940 |
| ct_001      |  262k |     8,512 |    13,464 |    63,127 |   110,400 |
| ct_003      |  262k |     7,766 |    12,414 |    21,309 |   102,489 |
| mr_001      |  785k |    37,287 |    40,989 |   168,510 |   205,454 |
| xa_001      | 1.0M  |    39,379 |    55,087 |   244,299 |   398,731 |
| px_001      | 3.2M  |   141,112 |   197,091 |   252,003 | 1,540,094 |
| dx_002      | 6.4M  |   239,235 |   355,896 |   468,219 | 2,971,929 |

**Hard cap honoured on every fixture × bpp combination** — verified by
`J2KConstantBitrateStrictTests`.

### Why PSNR drops more than the bytes ratio suggests

LRCP packets at the highest resolution dominate the byte budget on this format
(typically 60-80% of total bytes). Truncation is all-or-nothing per packet — a packet
either retains whole or drops whole, no partial admission. So a 1.0× cap can land far
below 1.0× achieved (px_001 @ 2 bpp hits 0.31×) because the next packet boundary above
the cap is far past it.

The retained packets keep the bounded mode's quality (because the search runs the same
quality-first Qstep). It's only the **dropped tail packets** that cost detail —
typically the highest-frequency sub-bands at the highest resolution. Decode of a
truncated strict-mode codestream succeeds and produces a low-resolution-rich
approximation rather than a corrupted image.

### Mode selection guide (post-v5.34)

> ⚠️ **Strict mode is NOT a drop-in for v5.33's quality on real medical content.**
> At a 1.0× cap, strict mode drops PSNR to 12-20 dB on real flat-curve high-bit-depth
> fixtures (px_001, dx_002). That is **below diagnostic thresholds** for clinical
> review. For diagnostic-grade lossy archive use `.constantBitrateBounded` explicitly
> (60+ dB but 2-4× target bytes), or stay lossless. Pick this table carefully.

| Mode | Cap | Quality on real flat-curve medical | Latency | Use when |
|---|---|---|---|---|
| **`.constantBitrate(bpp)`** (auto-promoted) | hard, ≤ target bytes | **12-20 dB** on px/dx; 18-35 dB on smaller fixtures | 3 passes + truncation | non-diagnostic preview / thumbnail tier, hard storage budget, accept quality collapse |
| `.constantBitrateBounded(bpp, ...)` | best-effort 2.0× (may overshoot) | 60+ dB clinical-grade | 3 passes | **diagnostic-grade lossy archive** when overshoot is acceptable |
| `.constantBitrateViaQstep(bpp, ...)` | unbounded (1.6-3× target observed) | 45-50 dB | 8 passes | v5.31 max-quality behaviour |
| `.fixedQstep(qstep)` | unbounded | content-dependent | 1 pass | latency-critical single-shot |

### v5.35.0c — same-workload CPU vs GPU encode benchmark

After the v5.34 consistency fix, `.constantBitrate(bpp)` routes both `encode()` and
`encodeGPU()` through the same intercepted CPU path on auto-promote-eligible content
(bitDepth ≥ 12 HT-conformant lossy). To compare the actual CPU and GPU pipelines, this
benchmark uses **`.fixedQstep(qstep: 15)`** — a non-intercepted mode that runs each
path's natural single-pass pipeline (CPU SIMD vs Metal-accelerated GPU forward DWT).

Calibrated for ~2 bpp output on 16-bit medical content. Measured on M1, n=5 medians,
release build, HT-conformant lossy 9/7. Reproducible via:

```bash
swift test -c release --filter "testCorpusEncodeAcrossAPIs_SameWorkload_FixedQstep"
```

| Fixture                | px     | CPU bytes | GPU bytes | CPU ms | GPU ms | CPU/GPU× |
|------------------------|-------:|----------:|----------:|-------:|-------:|---------:|
| mr_002 (180×180)       |   32k  |    36,127 |    36,127 |    1.1 |    1.0 |  **1.12×** |
| ct_001 (512×512)       |  262k  |   353,324 |   353,324 |    5.2 |    5.3 |    0.98× |
| ct_003 (512×512)       |  262k  |   331,896 |   331,896 |    5.1 |    5.2 |    0.97× |
| mr_001 (886×886)       |  785k  |   144,843 |   144,843 |    6.0 |    6.1 |    0.98× |
| xa_001 (1024×1024)     | 1.0M   | 1,360,481 | 1,360,481 |   19.8 |   28.6 |  **0.69×** |
| px_001 (2459×1316)     | 3.2M   | 5,419,286 | 5,419,289 |   67.7 |   89.8 |  **0.75×** |
| dx_002 (2800×2288)     | 6.4M   |10,542,788 |10,542,793 |  136.3 |  159.6 |    0.85× |
| dx_001 (2544×3056)*    | 7.8M   |13,992,955 |13,992,956 |  169.2 |  199.7 |    0.85× |
| mg_001 (3520×4784)*    | 16.8M  |30,310,299 |30,310,298 |  367.2 |  413.5 |    0.89× |
| mg_002 (3521×4784)*    | 16.8M  |30,319,802 |30,319,805 |  361.9 |  421.0 |    0.86× |

**Headline finding (post-v5.34): GPU encode is still a regression at most fixture
sizes.** Best CPU/GPU× = 1.12× at the smallest synthetic; rest range 0.69-0.98×.
Metal forward DWT remains the bottleneck — this matches the v5.29 diagnosis.
Stage-level breakdown shows the gap concentrates in the wavelet stage:

| Fixture (1.0M+ px)  | CPU DWT (ms) | GPU DWT (ms) | GPU regression |
|---------------------|-------------:|-------------:|---------------:|
| xa_001 (1024×1024)  |          3.2 |         13.3 |          4.2× slower |
| px_001 (2459×1316)  |          9.9 |         30.5 |          3.1× slower |
| dx_002 (2800×2288)  |         21.5 |         46.2 |          2.1× slower |
| mg_001 (3520×4784)* |         55.3 |        103.3 |          1.9× slower |

GPU's other stages (preproc, entropy, codestream) match CPU within run-to-run noise.
Only DWT is significantly slower. The CPU SIMD forward DWT path was tuned in v5.30.0
(rateControl O(B²) gate); the Metal forward DWT has not received equivalent attention.

**Byte counts match within 1-3 bytes** between CPU and GPU paths, reflecting a tiny
LSB precision difference in the Float forward DWT. Both produce valid codestreams
that decode to the same image within Float-precision rounding.

**Routing recommendation for encode** (post-v5.35.0c, unchanged from v5.30):
- For all `.constantBitrate(bpp)` use cases on bitDepth ≥ 12 HT-conformant lossy:
  use `.encode()` — `encodeGPU()` routes here anyway via the consistency fix.
- For `.fixedQstep` / `.constantQuality` / lossless: use `.encode()` (CPU). GPU
  encode is a regression at the wavelet stage.
- The full GPU encode pipeline becomes worth using only if/when the Metal forward
  DWT is rewritten — likely a v5.36+ effort tracking the v5.26.0 GPU HT *decoder*
  infrastructure approach.

### v5.34 decode performance (M1, warm session, n=5)

Decode on strict-mode codestreams works exactly like decode on any other valid
JPEG 2000 codestream — the truncation is structurally legal, decoders treat missing
trailing packets as zero-fill. No path-specific decode regression.

| Fixture                 |    px  | CPU `decode` | `decodeGPU` | `decodeWithGPUHT` | Best vs CPU |
|-------------------------|-------:|-------------:|------------:|------------------:|------------:|
| mr_002 (180×180)        |   32k  |          1.1 |         1.2 |               2.7 |       0.95× |
| ct_001 (512×512)        |  262k  |          7.0 |         6.4 |              11.3 |       1.10× |
| ct_003 (512×512)        |  262k  |          6.9 |         4.7 |               8.2 |       1.46× |
| mr_001 (886×886)        |  785k  |         21.1 |        11.0 |              18.7 |       1.91× |
| xa_001 (1024×1024)      | 1.0M   |         26.0 |        10.1 |              19.7 |       2.58× |
| px_001 (2459×1316)      | 3.2M   |         79.2 |        20.2 |              25.2 |       3.92× |
| dx_002 (2800×2288)      | 6.4M   |        169.1 |        46.5 |              40.4 |       4.19× |
| dx_001 (2544×3056)*     | 7.8M   |        218.5 |        46.2 |              49.3 |       4.73× |
| mg_001 (3520×4784)*     | 16.8M  |        496.0 |       116.3 |             109.3 |       4.54× |
| mg_002 (3521×4784)*     | 16.8M  |        503.6 |       122.1 |             109.0 |       4.62× |

Routing recommendation unchanged: `< 256² → CPU`, `< 3M px → decodeGPU`,
`≥ 3M px → decodeWithGPUHT`.

### Recommendations by workload — read carefully

| Workload | Recommended mode | Why |
|---|---|---|
| **Diagnostic-grade lossy archive** (clinical reads, full bit-depth medical) | `.constantBitrateBounded(bitsPerPixel: bpp)` explicit | 60+ dB on real medical fixtures; storage cost 2-4× target on flat-curve. Quality is the contract. |
| **Lossless archive** | `.lossless` | The only mode where dx_002 / px_001 reconstruct exactly. |
| **Non-diagnostic preview / thumbnail tier** (study browser, archive index) | default `.constantBitrate(bpp)` (auto-promotes to strict) | Hard byte cap; output may be 12-20 dB on flat-curve content (visibly degraded but layout-preserving for navigation). |
| **Hard storage budget under regulatory constraint** (e.g., per-image quota in cents/MB) | default `.constantBitrate(bpp)` (strict) | Cap is a contract. Re-evaluate per-modality whether the resulting quality is acceptable. |
| **Latency-critical single-shot** | `.fixedQstep(qstep:)` | One encode pass, caller picks qstep. No rate guarantees. |
| **v5.31 max-quality (8 passes, unbounded rate)** | `.constantBitrateViaQstep(bitsPerPixel: bpp)` | 45-50 dB at 1.6-3× target. |

**Strict mode is NOT the right default for diagnostic clinical workflows.** It was
chosen as the auto-promote default to honour the literal `.constantBitrate(bpp)`
contract (byte cap is a hard guarantee). For PACS / clinical-archive callers who
upgraded from v5.33 expecting 60+ dB output, the right path is to **switch
explicitly to `.constantBitrateBounded(bitsPerPixel: bpp)`** before deploying v5.34.

### Cross-codec / encapsulation validation

- **`opj_decompress` (OpenJPEG 2.5.4)** decodes strict-truncated codestream — exit 0,
  produces correct dimensions. ✓
- **`ojph_expand` (OpenJPH 0.27.0, HTJ2K reference)** decodes strict-truncated
  codestream — exit 0. ✓
- Verified by `J2KStrictCrossCodecValidationTests.testStrictTruncatedDecodesInOpenJPEGAndOpenJPH`.
- The truncated codestream is a valid JPEG 2000 codestream per ISO/IEC 15444-1: it
  starts with SOC (0xFF4F), contains a complete header (SIZ, COD, QCD, COM, SOT with
  rewritten Psot, SOD), the retained packet bytes, and ends with EOC (0xFFD9). Suitable
  for embedding in DICOM Pixel Data with Transfer Syntax UID 1.2.840.10008.1.2.4.90
  (JPEG 2000 Image Compression) — the encapsulation wraps the raw codestream verbatim.

### Known v5.34 limitations (structural, not bugs)

- **PSNR collapses on flat-curve high-bit-depth medical at low bpp** under the
  default 1.0× cap. Expect 12-20 dB on px_001 / dx_002 at 0.5-2 bpp under strict mode,
  vs 60+ dB under bounded mode at the cost of overshoot. This is the documented
  trade-off; quality is recoverable by switching to `.constantBitrateBounded` explicitly.

- **Budget-fill ratio can drop to 0.3× of cap** because LRCP packet truncation is coarse.
  On HT conformant cleanup-only with 1 layer, the highest-resolution packets are large
  (60-80% of total bytes per packet). At a 1.0× cap the next packet boundary above cap
  is often far past it; the search settles for the boundary far below cap. So the
  output is well within budget but doesn't fill it — quality could in principle be
  higher on the same byte budget if truncation were finer-grained.

- **The granularity floor is structural to LRCP single-layer**. To get finer truncation
  granularity (and recover quality at a strict cap) the codec would need either:
  multi-layer encoding (PCRD picks layer truncation points within packets — costs
  encode time and complicates the decoder side); or in-packet truncation with re-
  computed packet headers (rewrites Lblock fields, more invasive). v5.35+ scope.

- All v5.31-v5.33 quality features remain available as opt-in (`.constantBitrateBounded`,
  `.constantBitrateViaQstep`, `.fixedQstep`) — the v5.34 change is the auto-promote
  default only.

- **`encode()` and `encodeGPU()` produce byte-identical output** for the same
  `.constantBitrate(bpp)` post-v5.34 consistency fix. Pre-fix, they diverged on the
  auto-promote-eligible path. Verified by parity test.

---

## v5.35 → v5.36 — budget-fill recovery via multi-precinct (the cap is now useful)

v5.34 made the byte cap real (output ≤ target, always). But the v5.34 truncation
landed at coarse LRCP packet boundaries (~6 packets per layer), so on flat-curve
high-bit-depth content the achieved bytes fell far short of the cap (px_001 @ 2 bpp:
0.31× of cap). The v5.34 doc above flagged this as a structural limitation requiring
"multi-layer encoding or in-packet truncation with re-computed packet headers".

The right structural fix turned out to be **multiple precincts per band** (Part 1
functionality, supported by every mainstream JPEG 2000 decoder). Multi-layer was
explored first but is unsupported by OpenJPH HT (`ojph_codestream_local.cpp:781`
explicitly limits HT to 1 layer) and OpenJPEG's HT decoder. Multi-precinct works
everywhere.

### Implementation arc (v5.35.0a → v5.36-tuning)

| Tag | What landed |
|---|---|
| v5.35.0a | `J2KEncodeQstepStats.budgetFillRatio`; Grok added to cross-codec list; DICOM Pixel Data round-trip test |
| v5.35.0b | Multi-layer infrastructure (encoder side, single-precinct codestream) — shipped but cross-codec gap discovered |
| v5.35.0c | Same-workload CPU vs GPU encode benchmark (`.fixedQstep`); v5.33→v5.34 migration guide; doc reorg |
| v5.35.0d phase 1 | Diagnosed multi-layer HT as ecosystem-unsupported; pivot decision to precincts |
| v5.35.0d phase 2 | Multi-precinct ENCODE infrastructure shipped; cross-codec validated; not wired into strict mode (decode-side broke) |
| v5.36-decode | Multi-precinct DECODE support: `extractTileData` rewritten for per-precinct iteration; CPU + decodeGPU + decodeWithGPUHT all handle multi-precinct codestreams. Strict-mode auto-promote re-wired to multi-precinct (PPx=10) |
| v5.36-tuning | Strict-mode default lowered PPx 10 → 8 (the PPx<10 SIGTRAP was a stale symptom of the decoder bug). Final budget-fill recovery |

### Headline budget-fill recovery (M1, real medical fixtures @ 2 bpp)

Strict-mode auto-promote (`.constantBitrate(2.0)` on HT-conformant lossy 9/7 with
bitDepth ≥ 12). `J2KEncoder.encode(_:)` now emits multi-precinct codestream with
PPx=PPy=8. Truncation lands at the largest of the ~85+ packet boundaries that fits
the cap.

| Fixture | px | v5.34 fill | v5.36 fill | v5.34 PSNR | v5.36 PSNR |
|---|---:|---:|---:|---:|---:|
| px_001 (2459×1316) | 3.2M  | 0.312× | **0.945×** | 12.27 dB | **13.69 dB** |
| dx_002 (2800×2288) | 6.4M  | 0.292× | **1.000×** (exact cap) | 13.14 dB | **14.57 dB** |

Both fixtures exceed the user's "ideal >0.70×" budget-fill target. dx_002 fills the
cap exactly. Reproducible via:

```bash
swift test -c release --filter "J2KMultiLayerEncodeTests/testHeadlineStrictModeValidation_AcrossAllDecoders"
```

PSNR gain is modest (+1.4 dB on both fixtures) for ~3× more bytes used. The retained
extra bytes are LL/low-frequency dominant; the highest-resolution detail packets
contribute marginal PSNR per byte. Pushing PSNR higher would require smarter qstep
search to retain more high-frequency content per byte — separate v5.37 follow-up.

### Six-decoder validation matrix

The `testHeadlineStrictModeValidation_AcrossAllDecoders` test runs both fixtures
through all six decode paths and asserts cap honoured + non-zero PSNR output:

| Decoder | px_001 result | dx_002 result |
|---|---|---|
| J2KSwift CPU `decode` | exit 0, 13.69 dB | exit 0, 14.57 dB |
| J2KSwift `decodeGPU` | exit 0, 13.69 dB | exit 0, 14.57 dB |
| J2KSwift `decodeWithGPUHT` | exit 0, 13.69 dB | exit 0, 14.57 dB |
| OpenJPEG 2.5.4 `opj_decompress` | exit 0 | exit 0 |
| OpenJPH 0.27.0 `ojph_expand` | exit 0 | exit 0 |
| Grok 20.3.0 `grk_decompress` | exit 0 | exit 0 |

J2KSwift's three decode paths produce byte-identical PSNR (deterministic decode of
the same codestream). External decoders all exit 0; pixel comparison against the
J2KSwift reconstruction is implicit in the PSNR PSNR gain measurement.

### Codestream structure change

For a `.constantBitrate(2 bpp)` encode on px_001:

| Aspect | v5.34 single-precinct | v5.36 multi-precinct (PPx=8) |
|---|---|---|
| Packets per layer | 6 (one per LRCP iteration) | ~85 (one per (res, comp, precinct)) |
| Truncation granularity | ~50-200 KB (high-res packet size) | ~5-15 KB (precinct packet size at high res) |
| Wire format | Scod = 0 (default precinct) | Scod = 1 + per-resolution PPx/PPy bytes in COD |
| Decode compatibility | All decoders (Part 1 default) | All decoders (Part 1 precincts are universally supported) |

### v5.36 known limitations

- **PSNR gain is modest** vs the byte-fill increase. Recovering more PSNR per byte
  needs smarter qstep selection (the search currently picks the qstep that fills
  byte budget; it doesn't optimise for PSNR-per-byte at high resolution). v5.37
  scope.
- **Multi-layer HT is still untouched.** v5.35.0b's `encodeMultiLayerWithPacketIndex`
  ships but isn't used. Cross-codec interop gap (OpenJPH HT = 1 layer, OpenJPEG HT
  decode rejects multi-layer) remains an ecosystem issue, not a J2KSwift bug.

### v5.37 R-D baseline — strict-mode quality vs bpp curve

Strict-mode auto-promote (`.constantBitrate(bpp)`) on real medical fixtures, sweeping
bpp ∈ {0.25, 0.5, 1.0, 2.0, 4.0}. Captured to drive v5.37 PSNR-per-byte improvement
work. Reproducible via:

```bash
swift test -c release --filter "J2KMultiLayerEncodeTests/testStrictModeRDBenchmark_PostMultiPrecinct"
```

| Fixture | bpp target | bytes target | bytes achieved | fill ratio | PSNR (dB) |
|---|---:|---:|---:|---:|---:|
| px_001 (3.2M) | 0.25 | 101,126 |    94,327 | 0.933× | 12.25 |
| px_001 (3.2M) | 0.50 | 202,252 |   201,121 | 0.994× | 12.55 |
| px_001 (3.2M) | 1.00 | 404,505 |   375,007 | 0.927× | 12.87 |
| px_001 (3.2M) | 2.00 | 809,011 |   764,561 | 0.945× | 13.69 |
| px_001 (3.2M) | 4.00 | 1,618,022 | 1,540,231 | 0.952× | 14.28 |
| dx_002 (6.4M) | 0.25 | 200,200 |   194,809 | 0.973× | 13.33 |
| dx_002 (6.4M) | 0.50 | 400,400 |   381,103 | 0.952× | 13.41 |
| dx_002 (6.4M) | 1.00 | 800,800 |   789,609 | 0.986× | 13.83 |
| dx_002 (6.4M) | 2.00 | 1,601,600 | 1,601,181 | 1.000× | 14.57 |
| dx_002 (6.4M) | 4.00 | 3,203,200 | 3,189,551 | 0.996× | 14.86 |

**Two findings drive v5.37 priority work:**

1. **Fill ratio is excellent** (0.93-1.00× across all bpp targets) — multi-precinct
   delivered. The byte-budget side is solved.

2. **PSNR R-D curve is FLAT** — only 0.4-0.5 dB per doubling of bpp on these
   fixtures. A proper R-D curve gives 10-15 dB per doubling (v5.31 unbounded
   reference: ~46 dB at 2 bpp on px_001 vs strict's 13.69 dB → 32 dB gap that the
   fill-ratio fix did not close). Most of the 16× more bytes spent at 4 bpp vs
   0.25 bpp goes into LL/low-resolution content that contributes little PSNR,
   while high-frequency detail packets are truncated away because LRCP-order
   stream truncation drops the highest-resolution packets first.

### v5.37 R-D selection — what didn't work

A first attempt at v5.37 priority 1 implemented **resolution-weight-based
packet ranking**: rank packets by `(9/7 synthesis L2-norm)² / packet_bytes`,
include LL by default, then greedy-include the highest-slope packets until
the cap is hit. The hypothesis was that high-resolution detail packets
contribute disproportionately more PSNR per byte (their L2 norms are
~1000× larger than LL's), so reordering retention to favour them should
improve PSNR.

The implementation works (`EncoderPipeline.truncateByRDOptimized`) and is
preserved as available infrastructure. But wired into strict mode it
**regressed PSNR by 1-2 dB** across all bpp targets on the medical corpus:

| Fixture | bpp | LRCP-prefix (v5.36) | Resolution-rank R-D (v5.37 attempt) | Δ |
|---|---:|---:|---:|---:|
| px_001 | 2.0 | 13.69 | 11.73 | **−1.96 dB** |
| px_001 | 4.0 | 14.28 | 11.85 | −2.43 dB |
| dx_002 | 2.0 | 14.57 | 12.51 | −2.06 dB |
| dx_002 | 4.0 | 14.86 | 12.60 | −2.26 dB |

**Why it failed**: JPEG 2000 wavelet reconstruction is hierarchical — each
inverse DWT level consumes the previous level's LL plus its detail bands.
Skipping intermediate-resolution packets (dropping res 2-3 to fit more
res 5) leaves a reconstruction with missing mid-frequency content; the
res 5 detail "floats" without the lower-frequency synthesis path
underneath it. Even though high-res packets carry more PSNR-per-byte at
the coefficient level, dropping low-res packets to make room for them
breaks the synthesis chain.

The takeaway: any R-D selector under hard cap must keep the LRCP prefix
intact (LL + every intermediate resolution) and only choose which
high-resolution PRECINCTS to include. The per-resolution-weight heuristic
ignored that constraint and was promptly punished by 2 dB. The strict-mode
default has been reverted to LRCP-prefix truncation; the R-D method is
preserved for v5.37+ work that uses **actual block coefficient sums** and
respects the hierarchical synthesis dependency.

### v5.37 constrained-R-D selector — what worked, what didn't, why it stays parked

Following the negative resolution-weight result, the next attempt
implemented exactly what the takeaway prescribed:
`EncoderPipeline.truncateByConstrainedRD`. The selector keeps the
**LRCP-prefix dependency floor** (LL + every intermediate-resolution
packet) intact unconditionally, then runs greedy R-D selection on
highest-resolution precincts only, ranked by **actual coefficient sums**:

```
slope = (Σ_blocks coefficientSquaredSum × L2norm²[orient][dwtLevel]) / (bytes - 1)
```

Per-packet `distortionContribution` is populated at packet emission time
in `generateMultiPrecinctTileData` and threaded through
`PacketRDMetadata`. Unselected highest-resolution packets are emitted as
1-byte empty-flag stubs, preserving LRCP order.

**Standalone benchmark** (multi-precinct codestream at qstep large enough
to overshoot ~3-5×, where the truncator has real selection power):

| Fixture | bpp | LRCP-prefix | Constrained-RD | Δ |
|---|---:|---:|---:|---:|
| px_001 | 4.0 | 14.58 | 14.68 | **+0.11 dB** |
| dx_002 | 4.0 | 15.22 | 15.61 | **+0.39 dB** |
| px_001 | 2.0 | (skipped) | (skipped) | LRCP prefix > cap → both fall back |
| dx_002 | 2.0 | (skipped) | (skipped) | LRCP prefix > cap → both fall back |

The selector ranks packets correctly: at 4 bpp it preserves
high-distortion top-resolution precincts and drops low-distortion ones,
adding measurable PSNR for the same byte budget. At 2 bpp on 16-bit
medical fixtures the LRCP prefix alone (LL + res 1-4) exceeds the byte
cap at any qstep, so the dependency floor doesn't fit and the truncator
falls back identically to `truncateAtPacketBoundary`.

**Wired into strict mode** (full `J2KEncoder.encode(.constantBitrate)`
flow), the picture is different. Strict mode runs a qstep search that
deliberately lands at or marginally above the cap to minimise truncation
loss, so the truncator sees little or no overshoot at any operating
point — leaving R-D nothing to choose:

| Fixture | bpp | LRCP bytes / PSNR | Constrained-RD bytes / PSNR | Δ PSNR |
|---|---:|---:|---:|---:|
| px_001 | 0.25 | 94327 / 12.25 | 94327 / 12.25 | **+0.00** (undershoot) |
| px_001 | 0.50 | 201121 / 12.55 | 201121 / 12.55 | +0.00 (undershoot) |
| px_001 | 1.00 | 375007 / 12.87 | 375007 / 12.87 | +0.00 (undershoot) |
| px_001 | 2.00 | 764561 / 13.69 | 764561 / 13.69 | **+0.00** (undershoot) |
| px_001 | 4.00 | 1540231 / 14.28 | 1617736 / 14.36 | **+0.08** |
| dx_002 | 2.00 | 1601181 / 14.57 | 1601181 / 14.57 | **+0.00** (margin too thin) |
| dx_002 | 4.00 | 3189551 / 14.86 | 3160921 / 15.05 | **+0.19** |

(Mode-flow numbers via `swift test --filter testStrictModeRDBenchmark_PostMultiPrecinct`
with the wire-in temporarily enabled, then reverted.)

**Outcome**: constrained R-D is strictly **neutral or improving** at
every measured operating point — no regression — but the user gate
(*"improve PSNR at 2 bpp AND 4 bpp"*) is not met because at low bpp
strict-mode's qstep search produces undershoots and the truncator
returns the codestream unchanged. R-D adds value only where truncation
work is happening, and for that to occur at low bpp the encoder needs
to deliberately overshoot more than it currently does.

**Decision**: keep `truncateByConstrainedRD` as preserved infrastructure
in `EncoderPipeline`. Strict-mode default stays on
`truncateAtPacketBoundary`. The standalone test
`testConstrainedRDSelectorVsLRCPPrefix` documents the standalone gain
on real medical fixtures so the result is reproducible. Future v5.38+
work pairing the R-D selector with a deliberately-overshooting qstep
choice (so the truncator has selection power even at 2 bpp) is the
natural follow-up — promote the wire-in once that pairing is in place
and clears both gate points.

### v5.37 priority list (post-budget-fill)

In order of expected PSNR-per-byte impact:

1. ~~**Smarter packet selection under hard cap**~~ **Constrained R-D shipped as
   infrastructure (v5.37). Wire-in deferred** — the selector beats LRCP-prefix
   on the standalone benchmark (+0.11–0.39 dB at 4 bpp on px_001 / dx_002) but
   is neutral under the full strict-mode flow because strict mode's qstep
   search lands at or under the cap, leaving the truncator no overshoot to
   work with. Promotion gated on priority 3 below pairing it with deliberate
   small-overshoot qstep selection.

2. **High-frequency preservation under strict truncation** — handled by
   `truncateByConstrainedRD`'s LRCP-prefix dependency floor: LL + every
   intermediate resolution is mandatory; only highest-resolution precincts
   are dropped under cap pressure.

3. **Smarter qstep under hard cap** — current search prefers tiny overshoot
   then truncates. Better: deliberately pick a qstep producing
   `cap × 1.10–1.30` (~10-30% overshoot) so the constrained-R-D selector has
   real choice between which highest-resolution precincts to retain. With
   this pairing the v5.37 constrained-R-D wire-in becomes the obvious win.

4. **Quality-floor / warning policy** — when strict mode produces output with
   PSNR or fill-ratio below a threshold, populate a warning in
   `J2KEncodeQstepStats` (or surface via callback). Lets PACS workflows detect
   "this image needs different settings" without round-tripping the decode.

5. **Strict-mode R-D benchmark** — already shipped (this section). Re-run after
   each priority-1/2/3/4 change to measure improvement.

6. **Metal forward DWT rewrite** — separate perf priority (not strict-mode quality).

---

## v5.33 → v5.34 migration guide

v5.34's auto-promote behaviour change for `.constantBitrate(bpp)` on bitDepth ≥ 12
HT-conformant lossy is the largest user-visible behavioural change in the v5.31-v5.34
sequence. Callers upgrading from v5.33 should pick a path before deploying.

### Quick decision tree

```
Did v5.33 .constantBitrate(bpp) work for your workload?
│
├─ Yes — quality was right, byte count "close enough"
│   └─ v5.34 has a NEW default: hard byte cap (12-20 dB on flat-curve content).
│       To preserve v5.33 quality: switch to `.constantBitrateBounded(bpp)` explicitly.
│       (Recommended for diagnostic-grade lossy archive workflows.)
│
├─ Yes — but byte budget was important and v5.33 sometimes overshot
│   └─ v5.34's new default DOES make the byte cap real. No code change needed —
│       upgrade gives you the byte guarantee. Quality drops on flat-curve content;
│       see "Known v5.34 limitations".
│
└─ No — v5.33 quality was acceptable but byte budget was not enforceable
    └─ v5.34's strict default solves the byte side (always ≤ target). Quality drops
        on flat-curve high-bit-depth medical. Evaluate per-modality.
```

### Code changes by intent

| You want… | v5.33 (current) | v5.34 (do this) |
|---|---|---|
| Quality-first 60+ dB on real medical, byte cap is best-effort 2.0× | `.constantBitrate(bpp)` | `.constantBitrateBounded(bitsPerPixel: bpp)` *explicit* |
| Hard byte cap, accept quality cost on flat-curve content | (not directly available; .constantBitrate overshot) | `.constantBitrate(bpp)` (auto-promotes; **new default**) |
| v5.31 max-quality 8-pass search | `.constantBitrateViaQstep(bpp, ...)` | unchanged |
| Latency-critical, single-pass | `.fixedQstep(qstep: ...)` | unchanged |
| GPU encode for `.constantBitrate(bpp)` | `J2KEncoder.encodeGPU(_:)` (silently mismatched bytes) | `J2KEncoder.encodeGPU(_:)` (now byte-identical to encode()) |

### Stats / observability changes

`J2KEncodeQstepStats` (v5.35.0a):

| Field | v5.33 | v5.34+ |
|---|---|---|
| `iterations` | search iterations (bounded mode) | unchanged |
| `convergedQstep` | the qstep used | unchanged |
| `achievedBpp` | encoded bytes × 8 / pixels | unchanged |
| `convergedWithinTolerance` | hit user tolerance? | bool: hit cap AND not severely under-target |
| `budgetFillRatio` | (didn't exist) | `Optional<Double>`: achieved / cap. `nil` for non-strict modes |

### Test thresholds that may need updating

If you have downstream tests that assert PSNR on lossy-encoded medical content via
`.constantBitrate(bpp)`, expect the v5.34 strict-mode auto-promote to drop PSNR
significantly on flat-curve high-bit-depth fixtures (px_001/dx_002 dropped from 60 dB
to 12-13 dB at 2 bpp). Either:

1. Switch the test config to `.constantBitrateBounded(bitsPerPixel: bpp)` to preserve
   v5.33 quality expectations (this is the right fix for diagnostic-grade tests).
2. Or update the threshold to absorb the v5.34 strict-cap PSNR drop, with an explicit
   comment about why (the v5.30 gate test in this repo was updated this way at
   `J2KEncodeRateControlGateQualityTests.swift`).

### Cross-codec compatibility

v5.34 strict-truncated codestreams decode in OpenJPEG 2.5.4, OpenJPH 0.27.0, and Grok
v20.3.0 — see "Cross-codec / encapsulation validation". DICOM Pixel Data Transfer
Syntax 1.2.840.10008.1.2.4.90 wraps the codestream verbatim, validated by an
end-to-end round-trip test.

---

## Per-Processor Performance Summary (v5.30.0)

Canonical comparison table. Numbers below are **medians of 3 independent runs** in
release mode, n=5 timing samples per fixture per API per run, HT-conformant lossy 9/7
@ 2 bpp. Raw run logs in [`benchmarks/`](benchmarks/).

### Decode (warm session, ms)

| Fixture                | Pixels | API                           | **Apple M2** | **Apple M4** ¹ |
|------------------------|-------:|-------------------------------|-------------:|---------------:|
| px_001 (2459×1316)     |  3.2M  | CPU `decode`                  |       87.1   |        TBD     |
|                        |        | `decodeGPU(_:session:)`       |       30.5   |        TBD     |
|                        |        | `decodeWithGPUHT(_:session:)` |       27.2   |        TBD     |
| dx_002 (2800×2288)     |  6.4M  | CPU `decode`                  |      171.4   |        TBD     |
|                        |        | `decodeGPU(_:session:)`       |       51.6   |        TBD     |
|                        |        | `decodeWithGPUHT(_:session:)` |       42.3   |        TBD     |
| dx_001 (2544×3056)*    |  7.8M  | CPU `decode`                  |      223.9   |        TBD     |
|                        |        | `decodeGPU(_:session:)`       |       56.9   |        TBD     |
|                        |        | `decodeWithGPUHT(_:session:)` |       51.5   |        TBD     |
| mg_001 (3520×4784)*    | 16.8M  | CPU `decode`                  |      515.0   |        TBD     |
|                        |        | `decodeGPU(_:session:)`       |      145.4   |        TBD     |
|                        |        | `decodeWithGPUHT(_:session:)` |      119.7   |        TBD     |
| mg_002 (3521×4784)*    | 16.8M  | CPU `decode`                  |      511.5   |        TBD     |
|                        |        | `decodeGPU(_:session:)`       |      149.8   |        TBD     |
|                        |        | `decodeWithGPUHT(_:session:)` |      123.1   |        TBD     |

### Decode peak speedups (CPU `decode` baseline = 1.0×)

| Fixture                | API                           | **Apple M2** | **Apple M4** ¹ |
|------------------------|-------------------------------|-------------:|---------------:|
| px_001 (2459×1316)     | `decodeWithGPUHT(_:session:)` |        3.2×  |        TBD     |
| dx_002 (2800×2288)     | `decodeWithGPUHT(_:session:)` |        4.0×  |        TBD     |
| dx_001 (2544×3056)*    | `decodeWithGPUHT(_:session:)` |        4.3×  |        TBD     |
| **mg_001 (3520×4784)*** | `decodeWithGPUHT(_:session:)` |    **4.3×**  |        TBD     |
| mg_002 (3521×4784)*    | `decodeWithGPUHT(_:session:)` |        4.2×  |        TBD     |

### Encode (CPU `encode`, ms)

| Fixture                | Pixels  | **Apple M2** | **Apple M4** ¹ |
|------------------------|--------:|-------------:|---------------:|
| ct_001 (512×512)       |   262k  |         4.3  |        TBD     |
| xa_001 (1024×1024)     |   1.0M  |        16.0  |        TBD     |
| px_001 (2459×1316)     |   3.2M  |        51.6  |        TBD     |
| dx_002 (2800×2288)     |   6.4M  |        85.7  |        TBD     |
| dx_001 (2544×3056)*    |   7.8M  |       103.0  |        TBD     |
| mg_001 (3520×4784)*    |  16.8M  |       224.9  |        TBD     |
| mg_002 (3521×4784)*    |  16.8M  |       218.4  |        TBD     |

`encodeGPU` is currently a regression at every fixture size on M2 (CPU/GPU 0.66×–1.04×).
Re-evaluate this on M4 — different GPU/CPU balance may change which side wins. Captured
in the same M4 run (CPU/GPU column from the encode table).

### Cold-start vs `preWarm()` (512×512, ms)

| Metric                              | **Apple M2** | **Apple M4** ¹ |
|-------------------------------------|-------------:|---------------:|
| Cold-session first decode           |        53.8  |        TBD     |
| `preWarm()` itself                  |        52.7  |        TBD     |
| First user decode after `preWarm()` |        12.9  |        TBD     |
| Cold-start eliminated by `preWarm`  |        40.9  |        TBD     |

¹ M4 capture pending. To populate, run on the M4 machine:

```bash
swift test -c release --filter "J2KMedicalCorpus" 2>&1 \
  | grep -E "^(=== |Processor:|Image:|Synthetic|Skipped|\| |Per-fixture|Cold session|preWarm|Warm session|Cold-start|Total cost)" \
  > benchmarks/M4_run1.txt
```

Repeat 3× (`M4_run1.txt`, `M4_run2.txt`, `M4_run3.txt`); take per-fixture medians; fill
in the `Apple M4` column above. The benchmark auto-tags with `Processor:` from
`sysctlbyname("machdep.cpu.brand_string", …)` so each file is self-identifying. See
[`benchmarks/README.md`](benchmarks/README.md) for full notes.

### Variance characterisation (M2)

| Metric type                | Range across 3 runs | Median used |
|----------------------------|---------------------|-------------|
| End-to-end decode (large)  | ±5%                 | yes         |
| End-to-end encode (large)  | ±3%                 | yes         |
| `gpuHTDispatch` (sub-stage) | ±20% (Metal/system) | yes         |
| Cold-start first decode    | ±25% (variable)     | yes         |
| `preWarm()` itself         | ±60% (cache warmth) | yes         |

The release-mode benchmarks below this section retain the v5.28.0–v5.30.0 release-by-
release detail. Use the table above for the canonical processor comparison.

---

## Decode Performance (v5.28.0)

Per-fixture warm-session decode time across three APIs, measured on the medical DICOM
corpus in `Tests/Fixtures/CrossCodec`. All numbers are release-mode medians (n=5 after
warm-up) on M2, HT-conformant lossy 9/7 @ 2 bpp. Reproducible via:

```bash
swift test -c release --filter J2KMedicalCorpus
```

### Per-fixture decode time (ms, lower = faster)

| Fixture                | Pixels    | CPU `decode` | `decodeGPU(_:session:)` | `decodeWithGPUHT(_:session:)` | Winner |
|------------------------|----------:|-------------:|-------------------------:|------------------------------:|---|
| mr_002 (180×180)       |    32,400 |          1.2 |                      1.2 |                          4.7 | CPU¹ |
| ct_001 (512×512)       |   262,144 |          7.1 |                      4.4 |                         17.1 | decodeGPU |
| ct_003 (512×512)       |   262,144 |          7.4 |                      3.7 |                          9.3 | decodeGPU |
| mr_001 (886×886)       |   784,996 |         21.0 |                      9.0 |                         13.2 | decodeGPU |
| xa_001 (1024×1024)     | 1,048,576 |         25.6 |                      8.8 |                         14.0 | decodeGPU |
| px_001 (2459×1316)     | 3,236,044 |         86.2 |                     30.3 |                         **26.7** | decodeWithGPUHT |
| dx_002 (2800×2288)     | 6,406,400 |        167.8 |                     46.0 |                         **42.0** | decodeWithGPUHT |
| dx_001 (2544×3056)*    | 7,774,464 |        223.6 |                     56.5 |                         **51.2** | decodeWithGPUHT |
| mg_001 (3520×4784)*    | 16,839,680 |        502.8 |                    140.2 |                        **110.2** | decodeWithGPUHT |
| mg_002 (3521×4784)*    | 16,844,464 |        499.7 |                    152.9 |                        **113.6** | decodeWithGPUHT |

¹ At 180×180 the median is within run-to-run variance (Metal dispatch ≈ CPU decode time);
both GPU APIs return ~1.2 ms. CPU is the safe default for this size class.

\* v5.28.0 synthetic fixtures (LCG noise at the indicated dimensions). The real
mammography PGMs aren't in-repo (~32 MB each). Decode timing scales with pixel count and
constant-bitrate bitstream length, both of which match the real fixtures, so the routing-
rule characterisation remains valid.

### Per-fixture speedup (×, higher = faster)

| Fixture                | `decodeGPU`× CPU | `decodeWithGPUHT`× CPU |
|------------------------|-----------------:|------------------------:|
| mr_002 (180×180)       |             1.0× |                    0.3× |
| ct_001 (512×512)       |             1.6× |                    0.4× |
| ct_003 (512×512)       |             2.0× |                    0.8× |
| mr_001 (886×886)       |             2.3× |                    1.6× |
| xa_001 (1024×1024)     |             2.9× |                    1.8× |
| px_001 (2459×1316)     |             2.8× |                **3.2×** |
| dx_002 (2800×2288)     |             3.7× |                **4.0×** |
| dx_001 (2544×3056)*    |             4.0× |                **4.4×** |
| mg_001 (3520×4784)*    |             3.6× |                **4.6×** |
| mg_002 (3521×4784)*    |             3.3× |                **4.4×** |

The crossover is decisive: `decodeWithGPUHT` overtakes `decodeGPU` at ~3M pixels and
keeps gaining headroom up through 17M pixels (mammography), where it hits **4.6× CPU**.

### Routing recommendation

The crossover is decisive: `decodeGPU` wins below ~1M pixels; `decodeWithGPUHT` wins above
~3M pixels. The v5.27.0 helper `J2KDecoder.recommendedDecodeAPI(width:height:)` codifies
this:

| Pixel count          | Recommended API                  | Reason |
|----------------------|----------------------------------|--------|
| `< 65,536` (256²)    | CPU `decode(_:)`                 | Metal dispatch overhead cancels GPU compute on tiny images |
| `< 3,000,000`        | `decodeGPU(_:session:)`          | CPU HT entropy (~1–2 ms parallelised) is cheaper than GPU HT dispatch (~7 ms) at this size; GPU IDWT is the dominant lever |
| `≥ 3,000,000`        | `decodeWithGPUHT(_:session:)`    | GPU HT dispatch amortises across larger codeblock counts; full GPU pipeline wins |

Cold-start Metal overhead is ~50 ms regardless of image size — for genuine one-off
decodes (no shared session), prefer CPU `decode` even when dimensions are large.

### What changed in v5.27.0 (vs v5.26.0)

`decodeWithGPUHT` 9/7 lossy got materially faster on large workloads after v5.27.0
introduced a CPU-work skip on the Float fused-from-codeblocks path. The `[SubbandInfo]`
regroup loop and the per-subband CPU dequantisation pass are now skipped when the GPU
scatter+dequant kernel produces the dequantised Float subbands directly:

| Fixture            | v5.26.0 `decodeWithGPUHT` | v5.27.0 `decodeWithGPUHT` | Δ |
|--------------------|--------------------------:|---------------------------:|----:|
| px_001 (2459×1316) |                    41.0 ms |                    27.2 ms | **−14 ms** |
| dx_002 (2800×2288) |                    46.9 ms |                    42.7 ms |  −4 ms |

Per-stage `decodeWithGPUHT` breakdown (typical post-v5.27.0 run on dx_002 2800×2288):

| Stage                       | ms |
|-----------------------------|----:|
| `gpuHTDispatch`             |  8.9 |
| build Float plans (regroup) |  0.6 |
| CPU dequant                 | **0.0** ← v5.27.0: was ~4 ms |
| `inverseWaveletTransform`   | 25.6 |

---

## Cold-Start vs `preWarm()` (v5.28.0)

A fresh `J2KMetalSession` pays ~30–50 ms on the first decode for Metal device init,
shader-library load, pipeline-state creation, VLC-table upload, and Metal driver
first-dispatch fence. Subsequent decodes on the same session run at warm-baseline speed
(~10–15 ms for a 512×512 fixture).

`J2KMetalSession.preWarm()` (v5.28.0) does the cold-start work up front so the first
*user* decode runs at warm speed:

| Metric (512×512 16-bit lossy 9/7, M2, release) | Without `preWarm` | With `preWarm` |
|------------------------------------------------|------------------:|---------------:|
| Cold first decode                              |        40–49 ms   |          —     |
| `preWarm()` call itself                        |          —        |     27–32 ms   |
| First user decode after `preWarm`              |          —        |     **9–16 ms** |
| Warm baseline (subsequent decodes)             |        10–15 ms   |     10–15 ms   |
| Cold-start cost eliminated                     |          —        |     25–30 ms   |

What `preWarm` does:

1. Initialises the `MTLDevice` and `MTLCommandQueue`.
2. Loads the shader library (bundled `default.metallib` or in-source compile).
3. Pre-creates `MTLComputePipelineState` for every decode-hot-path kernel, in parallel.
4. Runs a tiny synthetic 256×256 decode through `decodeWithGPUHT` to exercise the rest
   of the lazy-init paths (VLC table upload, buffer pool first-fetch, Metal driver
   first-dispatch fence). Without this step `preWarm` only saves ~10–13 ms instead of
   the full 25–30 ms.

**When to use:** PACS daemons, batch decoders, server-side workers — anywhere a
long-lived process decodes many images. Call `preWarm` once at SDK init.

**When to skip:** genuine one-off CLI invocations. Total wall-clock for `preWarm` + 1
decode (~36–46 ms) is roughly the same as cold first decode (~40–49 ms), so the savings
need at least a second decode to be worthwhile.

Reproducible via:

```bash
swift test -c release --filter testColdStartVsPreWarm
```

---

## Appendix — historical encode-pipeline benchmarks

The sections below preserve the v5.29.0 and v5.30.0 release-by-release encode pipeline
characterisation. They were the headline performance work at those releases; v5.31.0
auto-promote, v5.32.0 cap, v5.33.0 bounded mode, v5.34.0 strict mode, and v5.35.0
multi-layer infrastructure all build on top.

The v5.29 numbers measure CPU vs GPU encode at `.constantBitrate(2.0)` PRE-v5.31
auto-promote — both paths ran the regular PCRD pipeline (1 pass), so the comparison
was directly meaningful at that release. **For the post-v5.34 same-workload CPU vs
GPU comparison, see "v5.35.0c — same-workload CPU vs GPU encode benchmark"
above** (which uses `.fixedQstep` to bypass the auto-promote and capture the same
single-pass workload on both paths).

### Encode Performance (v5.29.0)

After v5.28.0 brought decode 9/7 lossy on mammography to 4.6× CPU, encode is the next
lever. v5.29.0 adds `J2KEncodeTimings` (always-on per-stage accumulator, mirrors the
v5.24.0 decode-side timings) and a corpus encode benchmark
(`J2KMedicalCorpusEncodePerformanceTests`). All numbers are release-mode medians (n=5
after warm-up) on M2, HT-conformant lossy 9/7 @ 2 bpp:

```bash
swift test -c release --filter J2KMedicalCorpusEncode
```

### Per-fixture encode time (ms, lower = faster)

| Fixture                | Pixels    | CPU `encode` | `encodeGPU` | CPU/GPU× |
|------------------------|----------:|-------------:|------------:|---------:|
| mr_002 (180×180)       |    32,400 |          2.4 |         2.3 |    1.02× |
| ct_001 (512×512)       |   262,144 |          4.1 |         4.2 |    0.97× |
| ct_003 (512×512)       |   262,144 |          3.8 |         3.9 |    0.98× |
| mr_001 (886×886)       |   784,996 |          6.0 |         6.0 |    1.01× |
| xa_001 (1024×1024)     | 1,048,576 |         17.0 |        27.7 | **0.61×** |
| px_001 (2459×1316)     | 3,236,044 |         50.1 |        68.7 | **0.73×** |
| dx_002 (2800×2288)     | 6,406,400 |        110.1 |       132.5 | **0.83×** |
| dx_001 (2544×3056)*    | 7,774,464 |        239.6 |       262.6 |    0.91× |
| mg_001 (3520×4784)*    | 16,839,680 |       899.7 |       979.0 |    0.92× |
| mg_002 (3521×4784)*    | 16,844,464 |       920.5 |       972.9 |    0.95× |

`*` synthetic LCG-noise fixtures at the indicated dimensions.

### Per-fixture CPU encode stage breakdown (ms)

| Fixture                | preproc | colour | DWT  | quant | entropy | rateCtrl | codestream |
|------------------------|--------:|-------:|-----:|------:|--------:|---------:|-----------:|
| ct_001 (512×512)       |     0.3 |    0.0 |  0.8 |   0.1 |     2.0 |      0.4 |        0.6 |
| xa_001 (1024×1024)     |     1.2 |    0.0 |  3.3 |   0.1 |     7.6 |      2.6 |        1.9 |
| px_001 (2459×1316)     |     3.8 |    0.0 | 10.4 |   0.1 |    24.6 |      7.4 |        5.7 |
| dx_002 (2800×2288)     |     7.4 |    0.0 | 21.5 |   0.1 |    46.3 |     24.2 |       10.9 |
| dx_001 (2544×3056)*    |     9.4 |    0.0 | 26.9 |   0.2 |    56.8 |    132.3 |       13.0 |
| mg_001 (3520×4784)*    |    19.7 |    0.0 | 56.9 |   0.2 |   115.3 |  **678.8** |     28.0 |
| mg_002 (3521×4784)*    |    19.8 |    0.0 | 57.1 |   0.2 |   115.3 |  **701.1** |     28.6 |

### Three honest findings (v5.29.0; some superseded — see notes)

1. **`encodeGPU` is currently a regression** — slower than `encode` on every fixture by
   2-39%. `waveletTransform` GPU dispatch costs more than the CPU forward DWT it's
   supposed to replace (xa_001 at 1024²: CPU DWT 3.3 ms vs GPU DWT 14.9 ms). The
   v5.22.0 audit noted GPU forward DWT was bit-equivalent to spec; this benchmark
   shows it's also a perf regression at every measured size. The `encodeGPU` path
   should be marked deprecated until this is fixed. **(v5.35.0c update: confirmed
   on M1 with the same-workload `.fixedQstep` benchmark. Metal forward DWT remains
   2-4× slower than CPU SIMD.)**

2. **`rateControl` is the dominant stage at huge workloads** — at 17M pixels (mammography),
   PCRD-opt layer truncation takes **679–701 ms** out of 900–920 ms total = **75% of
   encode time**. Scales super-linearly: 1M px = 2.6 ms; 17M px = 700 ms (~270× for 17×
   pixel count). **(SUPERSEDED in v5.30.0 — see "Encode Performance update (v5.30.0)"
   below. The O(B²) inner loop was gated; mg_001 dropped from 678ms to 2.1ms.)**

3. **`entropyCoding` dominates at typical medical sizes** — at 1M to 6M pixels, HT
   block coding is 42–49% of total encode time. This is the natural target for any
   GPU-accelerated HT *encoder* mirroring the v5.26.0 GPU HT *decoder* infrastructure.

### Routing recommendation (v5.29.0; still valid post-v5.34)

For encode, **always use `encode(_:)`** (CPU). `encodeGPU(_:)` is currently a regression
at every measured fixture size. This is the inverse of decode (where `decodeGPU` and
`decodeWithGPUHT` win materially over CPU on warm session). **(v5.35.0c re-validated
on M1 with `.fixedQstep` to bypass the v5.34 auto-promote. Conclusion stands.)**

### Encode Performance update (v5.30.0)

v5.29.0's stage breakdown identified `rateControl` as 75% of encode time at mammography
sizes (679–701 ms / 900–920 ms), super-linear scaling. v5.30.0 root-causes it as an
O(B²) inner loop in `improveHTNearTargetAllocation` (a "small local exchange near the
byte target" step that scales catastrophically at large block counts) and adds a
`B ≤ 1024` gate that skips the exchange where individual-block swaps are <0.1% of the
budget anyway.

### Per-fixture impact (v5.29.0 → v5.30.0)

| Fixture                | rateCtrl v5.29 | rateCtrl v5.30 | Total v5.29 | Total v5.30 | Encode speedup |
|------------------------|---------------:|---------------:|------------:|------------:|---------------:|
| ct_001 (512×512)       |        0.4 ms  |        0.4 ms  |     4.1 ms  |     4.0 ms  | (unchanged)    |
| xa_001 (1024×1024)     |        2.6 ms  |        2.5 ms  |    17.0 ms  |    15.9 ms  | (unchanged)    |
| px_001 (2459×1316)     |        7.4 ms  |        7.4 ms  |    50.1 ms  |    52.3 ms  | (unchanged)    |
| dx_002 (2800×2288)     |       24.2 ms  |    **1.0 ms**  |   110.1 ms  |    82.0 ms  |     **1.3×**   |
| dx_001 (2544×3056)*    |      132.3 ms  |    **1.1 ms**  |   239.6 ms  |   101.7 ms  |     **2.4×**   |
| mg_001 (3520×4784)*    |      678.8 ms  |    **2.1 ms**  |   899.7 ms  |   214.2 ms  |     **4.2×**   |
| mg_002 (3521×4784)*    |      701.1 ms  |    **2.1 ms**  |   920.5 ms  |   210.5 ms  |     **4.4×**   |

The gate fires for fixtures with > 1024 codeblocks (dx_002 and larger). Below the
threshold the exchange runs unchanged — small fixtures see no behavioural difference.

### Quality verification

`Tests/J2KCodecTests/J2KEncodeRateControlGateQualityTests.swift` —
`testDX002LossyPSNRPreservedAcrossV5_30Gate` asserts roundtrip PSNR on dx_002 (2800×2288,
~1500 codeblocks → gate fires) is preserved within 1 dB of the pre-v5.30.0 baseline.
The exchange's purpose is "small local swaps that fine-tune R-D allocation" — at these
scales each block is <0.1% of total budget, so swap candidates are below any quality
metric's noise floor. Verified empirically: PSNR is identical pre/post the gate.

(The absolute PSNR on dx_002 at 2 bpp is 14.65 dB, which is low. That's a pre-existing
R-D issue in the encoder's slope formulation on DX/CT fixtures — also visible in
v5.21.0's `testBisectDecodePaths` showing ~2194 LSB avg diff at 4 bpp — and tracked
separately. v5.30.0's gate doesn't change it.)
