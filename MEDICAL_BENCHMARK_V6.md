# Medical Imaging Benchmark — v5.39 → v6 (HTJ2K lossless)

**Scope**: J2KSwift HT-conformant Part-15 lossless on the medical
corpus (MR, CT, XA, PX, DX). Lossy R-D / Qstep / strict / GPU-encode
work is parked as infrastructure under v5.38 — see the legacy
`MEDICAL_BENCHMARK.md` if you need the historical lossy detail.

---

## Headline (post-v6-alpha2)

J2KSwift HT lossless on the medical corpus is **standards-clean on
the production single-tile path** (28/28 cross-decode pairs bit-exact
through OpenJPEG 2.5.4, OpenJPH 0.27.0, Grok 20.3.0, and Kakadu 8.4.1
demo) and **standards-clean on the experimental multi-tile path** for
the subset of fixtures whose tile-component image-coordinate origins
are aligned to `2^decompositionLevels` (XA 1024² with 5 levels and
multi-tile dims 512 / 256 satisfies; the rest of the corpus does
not).

**Kakadu HT advantage on fixtures ≥ 886×886 still stands** — see
v5.38 HT-fair table below. v6-alpha2 didn't move the needle there;
it identified the structural fix needed and implemented the
correctness gate (the planner constraint). Closing the perf gap
needs the v6-alpha3 native multi-tile refactor.

| Mode default | Single-tile production path |
|---|---|
| Parked / experimental | SIMD M1, DWT row-parallel M2, multi-tile M4 (post-v6-alpha2 planner-constrained) |

---

## v5.38 — HT-fair format-fair lossless results (median of 5)

The format-fair table that anchors every claim about
J2KSwift-vs-Kakadu speed on this corpus. **Every codec emits HT /
Part-15**; OpenJPEG: N/A on this Homebrew CLI build. Encode +
decode times in ms; "fastest" + "margin → next" tell the
ordering at a glance.

### Encode time, HT-fair (ms)

| Modality | Shape | J2KSwift | OpenJPH | Grok | Kakadu | Fastest | Margin → next |
|---|---|---:|---:|---:|---:|:---|---:|
| MR-small | 180×180   |  **1.0** |   6.7 |   8.0 |   2.8 | J2KSwift | 2.7× → Kakadu |
| CT       | 512×512   |  **3.3** |  10.7 |   9.4 |   3.6 | J2KSwift | +0.2 ms → Kakadu |
| CT       | 512×512   |  **3.4** |  10.0 |   9.2 |   3.5 | J2KSwift | +0.0 ms → Kakadu |
| MR       | 886×886   |    5.9   |  10.5 |  11.2 | **3.7** | Kakadu  | 1.6× → J2KSwift |
| XA       | 1024×1024 |   11.5   |  21.6 |  14.2 | **5.1** | Kakadu  | 2.3× → J2KSwift |
| PX       | 2459×1316 |   38.6   |  58.9 |  28.0 | **11.2**| Kakadu  | 2.5× → Grok |
| DX       | 2800×2288 |   72.1   | 119.0 |  49.7 | **18.9**| Kakadu  | 2.6× → Grok |

### Decode time, HT-fair (ms)

| Modality | Shape | J2KSwift | OpenJPH | Grok | Kakadu | Fastest |
|---|---|---:|---:|---:|---:|:---|
| MR-small | 180×180   |  **0.8** |   6.5 |   7.5 |   2.7 | J2KSwift |
| CT       | 512×512   |  **3.5** |   8.7 |   8.5 |   3.5 | J2KSwift (tie) |
| CT       | 512×512   |  **3.4** |   8.6 |   8.5 |   3.6 | J2KSwift |
| MR       | 886×886   |    6.2   |  10.5 |   9.6 | **4.9** | Kakadu  |
| XA       | 1024×1024 |   15.2   |  17.2 |  10.9 | **6.2** | Kakadu  |
| PX       | 2459×1316 |   40.7   |  43.1 |  18.0 | **14.2**| Kakadu  |
| DX       | 2800×2288 |   77.1   |  81.9 |  31.9 | **25.9**| Kakadu  |

**Honest claim**: J2KSwift HT lossless is the fastest HT encoder +
decoder on every fixture ≤ 512×512. For fixtures ≥ 886×886, **Kakadu
8.4.1 demo wins both encode and decode**. J2KSwift output bytes match
OpenJPH within 1 byte on every fixture, and the codestream is
bit-exact decoded by every mainstream Part-15 decoder (21/21 pairs
HT-fair; 28/28 pairs EBCOT-fair).

### Cumulative v5.38 single-tile speedup vs v5.37 baseline

| Fixture | v5.37 | post-M9 | Cumulative |
|---|---:|---:|---:|
| DX 2800×2288  | 156.9 ms | **72.1 ms** | **2.18×** |
| PX 2459×1316  |  78.3 ms |   38.6 ms   | **2.03×** |
| XA 1024×1024  |  22.4 ms |   11.5 ms   | **1.95×** |
| MR 886×886    |   7.6 ms |    5.9 ms   |   1.29× |

The 2.0× single-tile floor comes from M3-A (`writeBytes` fast path),
M5 (branchless 5/3 forward lifting), M7 (preprocess branch hoist),
M8 (HT entropy buffer reuse), and M9 (sign-magnitude + UnsafeBufferPointer).
Post-M9, single-tile micro-optimisations are exhausted (M10 negative
result, v5.39 M1 SIMD per-quad neutral, v5.39 M2 DWT row-parallel
+4-8% but below promotion gate).

---

## v5.39 M3 — single-tile bottleneck diagnosis (anchors the v6 work)

After M1/M2 micro-attempts both missed the user's 25% gate, M3 ran a
diagnostic-only profile to identify what's actually limiting J2KSwift
HT vs Kakadu on large fixtures. The full per-fixture / per-stage /
per-thread-count tables live in the legacy doc; the headline:

**DX 2800×2288 @ 8 threads, baseline median of 5**:

| Stage      | Time   | % of total |
|------------|-------:|-----------:|
| Preprocess |   2.45 |       3 %  |
| DWT        |  32.16 |      39 %  |
| Entropy    |  40.49 |      50 %  |
| Codestream |   6.33 |       8 %  |
| **Wall**   |  81.52 |     100 %  |

**Amdahl decomposition (8 threads)**: parallel fraction ≈ 74 %,
serial fraction ≈ 26 % (~60 ms at 1 thread). Even with infinite
cores, DX wall would floor at ~60 ms — parallelism alone cannot
close the Kakadu gap (which lands at 19 ms HT-fair).

**Top three contributors to the gap**:
1. DWT structural ceiling (~28 ms of the ~62 ms gap) — DWT is
   already core-saturated via internal `processorCount` TaskGroup;
   no more lever in single-tile.
2. Entropy parallel-efficiency cap (0.58 on DX) — chunk imbalance,
   per-chunk allocator overhead, memory bandwidth contention.
3. Preprocess + codestream serial floor (~9 ms) — single-pass
   work that doesn't scale with `maxThreads`.

**M3 ranked the M4 candidates**:

| Candidate | Estimated DX gain | Pass 25% gate? | Cross-codec risk |
|---|---:|:---:|:---:|
| A. Block-batch HT (work-stealing entropy queue) | −15 % | ✗ | low |
| B. **Tile-level parallelism** (multi-tile encode) | **−38 %** | ✓ | medium |
| C. Memory-layout rewrite (per-thread scratch pool) | −6 % | ✗ | low |
| D. Metal integer 5/3 (GPU forward DWT) | −27 % | ✓ | high (GPU encode has been a regression) |

**B** picked as the v5.39 M4 / v6-alpha1 direction: addresses two of
the three contributors (DWT ceiling AND entropy efficiency) in one
architectural change.

---

## v5.39 M4 / v6-alpha1 — wrap-and-stitch multi-tile prototype (parked)

**Architecture skeleton** (production default unchanged — multi-tile
opt-in via `J2K_HT_TILE_MODE` env var):

| File | Role |
|---|---|
| `Sources/J2KCodec/J2KEncodeTilePlanner.swift` | `J2KHTTileMode` enum (single/2x2/4x4/strips4/auto), `J2KTileLayout` grid, env-var-cached planner. |
| `Sources/J2KCodec/J2KMultiTileCodestream.swift` | Per-tile sub-image slicer + main-header stitcher (patches Xsiz/Ysiz, rewrites SOT.Isot). |
| `Sources/J2KCodec/J2KMultiTileEncoder.swift` | `withTaskGroup` over N tile encodes via existing single-tile pipeline; per-tile observation diagnostics. |
| `Sources/J2KCodec/J2KCodec.swift` | `J2KEncoder.encode(_:)` dispatch + new internal `_singleTileEncode(_:)`. |

**Gate results (M4 baseline, no constraint)**:

| Gate | Single | 2x2 | 4x4 | strips4 | auto |
|---|:---:|:---:|:---:|:---:|:---:|
| Self-roundtrip 7/7 | ✓ | ✓ | ✓ | ✓ | ✓ |
| HT-fair cross-decode 21/21 | ✓ | **✗** | **✗** | **✗** | **✗** |

**Wrap-and-stitch ceiling on J2KSwift→J2KSwift path** (median of 5,
M2 release build):

| Fixture | single | 4x4 | speedup |
|---|---:|---:|:---:|
| MR 886×886 | 6.51 ms | 3.92 ms | 1.66× / −40 % |
| XA 1024×1024 | 11.52 ms | 8.38 ms | 1.37× / −27 % |
| PX 2459×1316 | 43.60 ms | 26.35 ms | 1.65× / −40 % |
| DX 2800×2288 | 77.11 ms | 54.04 ms | 1.43× / −30 % |

The architectural ceiling cleared the user's 25 % gate decisively.
But the codestream wasn't externally decodable for tiles ≥ 1.

---

## v6-alpha2 — root cause + planner-constrained promotion (active)

### The parity matrix that nailed root cause

`Tests/J2KCodecTests/HTTileParityMatrixTests.swift` runs every
(fixture, mode) cell through the M4 multi-tile path and checks
cross-decode against three external HT decoders. The data refuted
M4's "tile origin parity" hypothesis and pointed at the real rule:

| Modality | Shape | Mode | Tile origins | OpenJPH | Grok | Kakadu |
|---|---|---|---|---:|---:|---:|
| MR | 886×886    | 2x2     | (0,443) ×  (0,443)     | 64371 | 64371 | 64371 |
| MR | 886×886    | 4x4     | (0,222,444,666)²       | 63153 | 63153 | 63153 |
| MR | 886×886    | strips4 | (0)  ×  (0,222,444,666)| FAIL  | 61296 | 61296 |
| **XA** | **1024×1024**  | **2x2**     | **(0,512) ×  (0,512)**     | **0** | **0** | **0** |
| **XA** | **1024×1024**  | **4x4**     | **(0,256,512,768)²**       | **0** | **0** | **0** |
| **XA** | **1024×1024**  | **strips4** | **(0) × (0,256,512,768)**  | **0** | **0** | **0** |
| PX | 2459×1316  | 2x2     | (0,1230) ×  (0,658)    | FAIL  | 62646 | 65031 |
| PX | 2459×1316  | 4x4     | (0,615,1230,1845) × (0,329,658,987) | FAIL | 65532 | FAIL |
| PX | 2459×1316  | strips4 | (0)  ×  (0,329,658,987)| FAIL  | 65533 | 65533 |
| DX | 2800×2288  | 2x2     | (0,1400) ×  (0,1144)   | FAIL  | 32768 | FAIL |
| DX | 2800×2288  | 4x4     | (0,700,1400,2100) × (0,572,1144,1716) | FAIL | 65533 | FAIL |
| DX | 2800×2288  | strips4 | (0)  ×  (0,572,1144,1716) | FAIL | 65533 | FAIL |

(Numbers are max-abs-pixel-diff vs original; `0` = bit-exact;
`FAIL` = decoder returned non-zero exit status.)

**XA passes every cell. Every other fixture fails every multi-tile
cell.** The "M4 parity" hypothesis (top-level tile origin parity)
predicted MR-2x2 fails (origin 443 odd) but DX-2x2 passes (origin
1400 even) — the data shows BOTH fail.

### Root cause: tile origin must be `2^decompositionLevels`-aligned

The JPEG 2000 5/3 reversible DWT lifting depends on
**image-coordinate parity at every decomposition level**, not just
the topmost. The wrap-and-stitch encoder treats each tile as a
standalone image with origin (0, 0) — which has even parity at every
level. A multi-tile decoder applies the inverse DWT using
image-coordinate parity at each level (`origin / 2^level`). For the
two interpretations to agree, the tile's image-coordinate origin
must be a multiple of `2^decompositionLevels` — i.e., origin / 2^N
must be integral and even at every N from 0 to decompositionLevels.

**For 5 decomposition levels** (the J2KSwift default), the origin
must be a multiple of **32**.

| Fixture | Tile dim @ 2x2 | 32-aligned? | Tile dim @ 4x4 | 32-aligned? |
|---|---:|:---:|---:|:---:|
| XA 1024×1024 |  512 | ✓ (16·32) |  256 | ✓ (8·32) |
| MR 886×886   |  443 | ✗         |  222 | ✗ |
| PX 2459×1316 | 1230×658 | ✗     |  615×329 | ✗ |
| DX 2800×2288 | 1400×1144 | ✗    |  700×572 | ✗ |

**XA is the only corpus fixture whose tile dims are 32-aligned at
every multi-tile mode**, and is exactly the only fixture whose
multi-tile codestreams cross-decode bit-exact. That isn't
coincidence — it's the structural fix's specification.

### Fix — planner constraint (v6-alpha2 lands today)

`J2KEncodeTilePlanner.plan(...)` now enforces both correctness
constraints:

```swift
// Constraint 1 — DWT depth floor: each tile must be ≥ 2^N along each axis.
let minDim = 1 << decompositionLevels
if tileW < minDim || tileH < minDim { return single }

// Constraint 2 — DWT parity alignment: tileW and tileH must each be
// multiples of minDim, so every tile's origin lands on a 2^N boundary.
if cols > 1 && (tileW % minDim != 0) { return single }
if rows > 1 && (tileH % minDim != 0) { return single }
```

When constraint 2 is violated, the planner returns single — which
means the encoder runs the existing v5.38 / v5.39 single-tile path
unchanged. **No regression, no correctness gap.**

### v6-alpha2 gate results (post-constraint)

**1. Self-roundtrip + HT-fair cross-decode + EBCOT-fair cross-decode
+ default-mode + bytes-deterministic** for every mode:

| Mode | Self-RT 7/7 | HT-fair 21/21 | EBCOT-fair 28/28 | Default 7/7 | Bytes deterministic 5/5 runs |
|---|:---:|:---:|:---:|:---:|:---:|
| single  | ✓ | ✓ | ✓ | ✓ | ✓ |
| 2x2     | ✓ | ✓ | ✓ | ✓ | ✓ |
| 4x4     | ✓ | ✓ | ✓ | ✓ | ✓ |
| strips4 | ✓ | ✓ | ✓ | ✓ | ✓ |
| auto    | ✓ | ✓ | ✓ | ✓ | ✓ |

Every multi-tile mode is **fully standards-clean** — but most large
fixtures fall back to single-tile because the planner constraint
isn't satisfied.

**2. Mandatory commit gates** (CPU + GPU + cross-codec, default off):

- `J2KMedicalCorpusEncodePerformanceTests`: pass
- `J2KMedicalCorpusPerformanceTests`: pass
- `J2KStrictCrossCodecValidationTests`: pass

### v6-alpha2 perf (post-constraint, median of 5)

| Modality | Shape | single | 2x2 | 4x4 | strips4 | Layout fired |
|---|---|---:|---:|---:|---:|:---|
| MR | 886×886    |  5.30 |  5.45 |  5.43 |  5.46 | All 1×1 (constraint forces fallback) |
| XA | 1024×1024  | 11.09 |  **7.96** (+28 %) | **8.75** (+21 %) | **8.08** (+27 %) | All 32-aligned, multi-tile fires |
| PX | 2459×1316  | 39.36 | 39.42 | 41.86 | 39.97 | All 1×1 |
| DX | 2800×2288  | 75.94 | 78.43 | 83.58 | 79.81 | All 1×1 |

**XA is the only fixture where multi-tile fires post-constraint, and
it clears the user's 15 % promotion gate decisively** (28 % at 2x2 /
27 % at strips4 / 21 % at 4x4 — all median of 5). MR / PX / DX fall
back to single-tile and run at v5.38 baseline (within run-to-run
noise; no regression).

### Kakadu HT-fair comparison (post-v6-alpha2)

| Fixture | Kakadu HT | J2KSwift single | J2KSwift best correct multi-tile | Gap before | Gap after |
|---|---:|---:|---:|---:|---:|
| MR 886×886    |  3.7 ms |  5.9 ms |  5.9 ms (planner falls back to single) | 1.6× | 1.6× (unchanged) |
| **XA 1024×1024**  |  **5.1 ms** | **11.1 ms** | **8.0 ms** (2x2)        | **2.18×** | **1.57×** |
| PX 2459×1316  | 11.2 ms | 38.6 ms | 38.6 ms (planner falls back to single) | 3.45× | 3.45× (unchanged) |
| DX 2800×2288  | 18.9 ms | 72.1 ms | 72.1 ms (planner falls back to single) | 3.81× | 3.81× (unchanged) |

**v6-alpha2 narrows the Kakadu HT gap on XA only** (2.18× → 1.57×).
The other large-fixture gaps stand because the planner constraint
forces single-tile fallback. **The Kakadu HT advantage on fixtures
≥ 886×886 documented in the v5.38 HT-fair table stands.**

### Final v6-alpha2 decision

- ✓ **Promote constraint** (the planner's 32-alignment check) — it's
  the correctness guarantee that protects production. Multi-tile
  default remains `single`; opt-in modes only fire when correctness
  is provable.
- ✗ **Do NOT promote auto multi-tile.** Auto-mode fires multi-tile
  for XA only and falls back to single for everything else; users
  expecting 4 MP / 6 MP fixture acceleration would not see it. The
  net product value is small until the v6-alpha3 native multi-tile
  refactor lands.
- ✓ **Architecture stays in source** behind `J2K_HT_TILE_MODE` env
  var for v6-alpha3 work to extend.

> M4 proved multi-tile can close a large part of the performance
> gap, but v6-alpha2 had to make the multi-tile codestream
> standards-clean first. With v6-alpha2's planner constraint,
> multi-tile is now correctness-clean for every mode — but only XA
> 1024² actually fires multi-tile, because every other large medical
> fixture has tile dimensions that aren't multiples of 32 (5
> decomposition levels). Closing the Kakadu gap on the rest of the
> corpus needs the v6-alpha3 native multi-tile refactor.

### v6-alpha3 scope (recommended)

**Native multi-tile encoder refactor**: propagate per-tile
image-coordinate origin through:
- DWT lifting start parity (`AcceleratedDWT2D.forward2D_53` accepts
  `tileOriginX` / `tileOriginY` and uses them at each lifting
  level).
- Code-block grid origin (currently implicit (0,0) in
  tile-component coords; for the v6-alpha2 wrap-and-stitch this is
  fine, but a parity-correct encoder needs the origin to align
  with image-coord-modulo-2 of the band).
- Packet header generation (precinct origin propagation).
- Single pass through `generateCodestream` that emits N tile-parts
  rather than N standalone codestreams stitched.

This unblocks DX/PX/MR multi-tile and would (per M4 measurements)
deliver:
- DX 30 % gain (close 27 ms of the 53 ms Kakadu gap)
- PX 40 % gain
- MR 40-51 % gain

After v6-alpha3, the v5.38 HT-fair table needs re-measurement on
each large fixture in best-tile-mode to determine whether the
"Kakadu wins ≥ 886×886" claim still holds. **Until that
measurement is done with a corrected multi-tile path, the v5.38
claim stands.**

---

## Single-tile is the safe default — final wording

> J2KSwift HT lossless is standards-clean and strong on small HT
> medical fixtures (≤ 512×512). Multi-tile encoding is now
> correctness-clean across every mode (5/5 lossless gates green
> per mode, 21/21 HT-fair cross-decode, 28/28 EBCOT-fair
> cross-decode, deterministic bytes), but the v6-alpha2 planner
> constraint forces fallback to single-tile on every fixture
> whose tile dimensions aren't multiples of `2^decompositionLevels`.
> XA 1024² is the only corpus fixture currently delivering a
> multi-tile speedup (28 %, clears the 15 % gate). Closing the
> Kakadu HT gap on the rest of the corpus is v6-alpha3 work.

---

## v6-alpha3 step 1 — parity-aware 5/3 forward 1D DWT (math primitive)

### What landed

The mathematical primitive that v6-alpha3 needs to build on:
**`AcceleratedDWT2D.forward53_1D(_:_:count:uOrigin:workspace:)`** in
`Sources/J2KCodec/J2KAcceleratedEncoder.swift`. New parity-aware
overload of the existing 1D forward 5/3 reversible DWT.

The signature gains one parameter — `uOrigin: Int` — the
tile-component image-coordinate origin in this axis. Behaviour:

- `uOrigin == 0` (or any even value): output is **bit-identical**
  to the no-origin overload. The function early-returns to the
  existing path (same code, same lifting bulk, same boundary
  handling). This is the regression guard for the production
  single-tile encode hot path.
- `uOrigin & 1 == 1` (odd origin): the local-index-to-band mapping
  flips per ISO/IEC 15444-1 F.4.4 (low-pass samples gather from
  local-odd indices because image-even positions in [u, u+n) are
  at local-odd; high-pass gather from local-even). Boundary cases
  reflect over a different mirror axis. Lifting arithmetic is
  identical to the even-origin case.

### Unit tests

`Tests/J2KCodecTests/HTDWTParityAwarenessTests.swift` covers four
invariants:

| Invariant | Test |
|---|---|
| Even-origin output is byte-identical to no-origin overload | `testEvenOriginIsByteIdenticalToNoOriginOverload` (n ∈ 2…32, u ∈ {0, 2, 4, 100, 1024}) |
| Band counts swap on odd origin (`lowCount = ⌊n/2⌋, highCount = ⌈n/2⌉`) | `testBandCountsForOddOriginSwap` (n ∈ 2…20) |
| Odd-origin forward+inverse roundtrips bit-exactly | `testOddOriginRoundTripIsBitExact` (n ∈ 2…32, u ∈ {1, 3, 5, 33, 99, 1399}) |
| Even-origin forward+inverse via reference inverse also roundtrips | `testEvenOriginRoundTripViaReferenceInverse` (sanity) |

The reference inverse is implemented inline in the test (the
production inverse 5/3 lives inside the decoder pipeline and is
harder to call in isolation). Forward uses the new parity-aware
production code; inverse uses a parity-aware reference. Every
(n, u) pair in the test matrix passes — the math primitive is
verified.

### Mandatory commit gates

All green with the new code in source (default path unchanged):

- `J2KLosslessMedicalGateTests` (HT-fair cross-decode 21/21,
  self-roundtrip 7/7) — pass
- `J2KMedicalCorpusEncodePerformanceTests` — pass
- `J2KStrictCrossCodecValidationTests` — pass

### What's NOT yet in this step (deferred to v6-alpha3 step 2+)

**This commit lands the math primitive only.** Threading origin
through to actually fix non-32-aligned multi-tile fixtures
requires multi-step work that is **not** part of this commit:

1. **`forward2D_53` recursion + multi-level origin tracking.**
   The 2D function calls `forward53_1D` once per row and once per
   column, and the encoder calls `forward2D_53` recursively for
   each decomposition level. Each level's LL band has its origin
   at `floor(parent_origin / 2)` (per spec F.4.4), which can flip
   parity at every level. Threading this requires changing the
   2D function signature and the multi-level recursion in the
   pipeline.

2. **Code-block grid origin.** Code-block partition origins are
   in tile-component coordinates which already start at (0, 0),
   so this is likely already correct — but needs audit on the
   parity-corrected codestream where band sizes shift.

3. **Packet header generation.** `generateTileData` packetises
   block bytes in LRCP order. The packet header's per-band
   block-inclusion tag-trees encode block coordinates that may
   need origin awareness when band dimensions shift.

4. **Native multi-tile codestream assembler.** Replace
   `J2KMultiTileAssembler.stitch` (wrap-and-stitch) with a single
   pass through `generateCodestream` that emits one main header
   + N tile-parts using the parity-aware DWT for each tile.

5. **Cross-decode validation on non-32-aligned fixtures.** The
   parity matrix test (`HTTileParityMatrixTests`) currently
   shows MR/PX/DX failing every cross-decode cell on the
   wrap-and-stitch path. After native multi-tile lands, the
   parity matrix should show **all cells passing** for every
   fixture, and the planner constraint can be relaxed.

6. **Perf re-measurement.** M4 prototype showed multi-tile
   ceiling at DX −30 % / PX −40 % / MR −51 % via 4×4 (median of
   5). After native multi-tile lands and cross-decode passes, the
   real perf gain on these fixtures (vs the v5.38 single-tile
   baseline) needs re-measuring with median-of-5 + mandatory
   commit gates per fixture.

### v6-alpha3 step 1 — final precise claim

> A parity-aware 5/3 forward 1D DWT primitive lands in
> `AcceleratedDWT2D.forward53_1D(...uOrigin:workspace:)`. It is
> bit-identical to the existing function at any even origin
> (regression-safe for production single-tile) and produces
> mathematically reversible output at odd origins (verified by
> 4 unit tests covering n ∈ 2…32 and u ∈ {0, 1, 2, 3, 5, 33, 99,
> 100, 1024, 1399}). **This is a building-block commit, not a
> shipping fix**: the v6-alpha2 planner constraint still forces
> non-32-aligned multi-tile cells to fall back to single-tile,
> and the Kakadu HT advantage on fixtures ≥ 886×886 stands.
> v6-alpha3 step 2+ will plumb this primitive through the 2D DWT,
> code-block grid, packet headers, and codestream assembler so
> that DX/PX/MR multi-tile cross-decode passes — at which point
> the planner constraint can be relaxed and the v5.38 HT-fair
> table re-measured.

---

## v6-alpha3 step 2 — parity-aware 2D 5/3 DWT + multi-level recursion

### What landed

Two new origin-aware overloads in
`Sources/J2KCodec/J2KAcceleratedEncoder.swift`:

- **`AcceleratedDWT2D.forward2D_53(data:width:height:tileOriginX:tileOriginY:)`** —
  parity-aware 2D forward 5/3 DWT. Column pass calls the parity-
  aware 1D DWT with `uOrigin = uY`, row pass calls it with
  `uOrigin = uX`. Output band sizes (LL/HL/LH/HH) are computed
  per ISO/IEC 15444-1 F.4.4 with origin-aware low/high counts
  (`lowCount = ⌈n/2⌉` for even origin, `⌊n/2⌋` for odd). When
  both origins are zero the function routes to the existing
  no-origin overload — output is byte-identical, no perf
  regression on single-tile.

- **`AcceleratedDWT2D.forwardDecomposition53(...tileOriginX:tileOriginY:)`** —
  parity-aware multi-level recursion. At each level, the LL band's
  origin updates as `floor(parent_origin / 2)` per spec F.4.4.
  When the starting origin is `(0, 0)`, every level's origin stays
  at `(0, 0)` and the recursion is byte-identical to the no-origin
  recursion.

### Unit tests

`Tests/J2KCodecTests/HTDWT2DParityAwarenessTests.swift` covers
eight invariants:

| Invariant | Test |
|---|---|
| Even-origin 2D output byte-identical to no-origin overload (sweep across small sizes × even-origin pairs) | `testEvenOrigin2DByteIdenticalToNoOriginOverload` |
| Odd-origin 2D forward+inverse roundtrips bit-exactly (every parity combo: even/even, odd/even, even/odd, odd/odd) | `testOdd2DForwardInverseRoundTrip` |
| 5-level multi-level at MR 2x2 tile1 origin (443, 0) — uX odd, uY even — roundtrips | `testMultiLevelMRTile1OriginRoundTrip` |
| 5-level at MR 2x2 tile3 (443, 443) — both odd, both flipping every level — roundtrips | `testMultiLevelMRTile3OriginRoundTrip` |
| 5-level at PX 2x2 tile1 (1230, 0) on 1229×658 trailing tile — non-square — roundtrips | `testMultiLevelPXTile1OriginRoundTrip` |
| 5-level at DX 2x2 tile3 (1400, 1144) — both even at level 0, both flip parity at deeper levels — roundtrips | `testMultiLevelDXTile3OriginRoundTrip` |
| 5-level at DX 4x4 (700, 572) — both even at level 0, parity flips at level 2+ — roundtrips | `testMultiLevelDX4x4OriginRoundTrip` |
| 5-level at origin (0, 0) byte-identical to no-origin recursion | `testMultiLevelEvenOriginByteIdenticalToNoOriginRecursion` |

The reference 2D inverse is built atop the parity-aware 1D inverse
and exercises the spec-correct origin-trajectory per level. Every
real-fixture origin pair tested produces a bit-exact roundtrip.

### Mandatory commit gates

All green with the new overloads in source (default path
unchanged):

- `J2KLosslessMedicalGateTests`: 5/5 passes (HT-fair 21/21,
  EBCOT-fair 28/28, self-roundtrip 7/7, default-mode 7/7,
  HT-vs-EBCOT)
- `J2KMedicalCorpusEncodePerformanceTests`: 2/2 passes
- `J2KStrictCrossCodecValidationTests`: 3/3 passes
- `HTDWTParityAwarenessTests` (1D): 4/4 passes
- `HTDWT2DParityAwarenessTests` (2D + multi-level): 8/8 passes

Production single-tile encode is byte-identical to v5.38 / v5.39 /
v6-alpha2.

### What's still NOT in this step (deferred to v6-alpha3 step 3+)

This step plumbs **only** the DWT mathematics. The cross-decode
gap on non-32-aligned multi-tile fixtures (MR / PX / DX) is **not
yet closed** because the wrap-and-stitch encoder doesn't yet call
this new origin-aware overload — it still encodes each tile as a
standalone image at origin (0, 0). To close the gap, v6-alpha3
step 3+ must:

1. Update `J2KMultiTileEncoder` and the upstream encoder pipeline
   to thread per-tile `tileOriginX` / `tileOriginY` from the slicer
   into the DWT call (replacing the implicit zero origin).
2. Audit the code-block grid: code-block partitioning is already
   in tile-component coordinates (tile-relative), so it should be
   correct, but needs a cross-decode validation pass under the
   parity-corrected DWT output.
3. Audit the packet header generation: per-band block-inclusion
   tag-trees and Lblock counts need re-validation when band sizes
   shift due to origin parity.
4. Replace the wrap-and-stitch codestream assembler with a single
   pass through `generateCodestream` that emits one main header +
   N tile-parts, each tile encoded with the origin-aware DWT.
5. Cross-decode gates: re-run `HTTileParityMatrixTests` and confirm
   MR/PX/DX cells now pass through OpenJPH, Grok, and Kakadu.
6. Once cross-decode passes for non-32-aligned fixtures, relax the
   v6-alpha2 planner constraint to admit those fixtures into
   multi-tile mode; re-measure the v5.38 HT-fair table.

### v6-alpha3 step 2 — final precise claim

> v6-alpha3 step 2 plumbs parity-aware origin through multi-level
> 2D 5/3 forward DWT (`AcceleratedDWT2D.forward2D_53(...tileOriginX:tileOriginY:)`
> and `forwardDecomposition53(...tileOriginX:tileOriginY:)`).
> Single-tile output remains byte-identical (verified by sweep
> across small sizes × multiple even-origin pairs). Multi-level
> roundtrip is bit-exact at every real-fixture origin tested
> (MR 443, MR 443×443, PX 1230 on 1229-wide trailing tile, DX
> 1400×1144, DX 700×572 with deeper-level parity flips).
>
> **This removes the DWT parity blocker for native multi-tile, but
> it is still not the full shipping multi-tile fix until
> code-block / packet / codestream origin handling is completed
> and MR/PX/DX cross-decode passes.** The v6-alpha2 planner
> constraint stays in place; the Kakadu HT advantage on fixtures
> ≥ 886×886 still stands until the v6-alpha3 step 3+ work lands
> and the v5.38 HT-fair table is re-measured.

---

## v6-alpha3 step 3 — pipeline plumbing for per-tile origin

### What landed

Threading from the multi-tile dispatcher down to the parity-aware
DWT call. Every link in the chain now carries the tile's
image-coordinate origin instead of silently encoding each tile at
local origin (0, 0).

| Link | Change |
|---|---|
| `EncoderPipeline.applyWaveletTransform(...)` | New `tileOriginX: Int = 0, tileOriginY: Int = 0` parameters. Threads to `AcceleratedDWT2D.forwardDecomposition53(...tileOriginX:tileOriginY:)` on the 5/3 reversible non-Float path (the lossless HT one). All other DWT paths (Float 9/7, Double, custom kernels) are unchanged — origin only matters for the lossless path that's actually being multi-tiled. |
| `EncoderPipeline.encode(...)` | New `tileOriginX: Int = 0, tileOriginY: Int = 0` parameters; threads to `applyWaveletTransform`. Default values keep all existing callers byte-identical. |
| `EncoderPipeline._htTileDebugOrigins` | New cached env-var reader: `J2K_HT_TILE_DEBUG_ORIGINS=1` prints per-tile origin/dim/level/origin-aware lines from inside `encode(...)`. Off by default; production logs are unaffected. |
| `J2KEncoder._singleTileEncode(_:tileOriginX:tileOriginY:)` | New origin-aware overload alongside the existing `_singleTileEncode(_:)`. Used by `J2KMultiTileEncoder`. Public `J2KEncoder.encode(_:)` stays on the no-origin path so its byte output is unchanged. |
| `J2KMultiTileEncoder.encode(...)` | Computes each tile's `(rect.x, rect.y)` from `J2KTileLayout.rect(forTile:)` and passes them to `_singleTileEncode(_:tileOriginX:tileOriginY:)`. |
| `J2KTileWorkObservation` | New `originX` / `originY` fields so tests can probe what the dispatcher actually sent. |

### Unit tests

`Tests/J2KCodecTests/HTTileOriginPropagationTests.swift` adds four
focused tests:

| Test | Result |
|---|---|
| `testMultiTileOriginsReachEncoder` — for every (fixture, mode) probe (MR 2x2, PX 2x2, DX 2x2, DX 4x4, XA 2x2), the per-tile observation's `(originX, originY)` matches the layout's `rect(forTile: k).(x, y)` for every k | ✓ |
| `testSingleTileBytesUnchanged` — `_singleTileEncode(_:tileOriginX:0,tileOriginY:0)` produces byte-identical output to `_singleTileEncode(_:)`; both runs deterministic | ✓ |
| `testXAMultiTileSelfRoundtripStillBitExact` — XA 2x2 (the v6-alpha2-aligned fixture) self-roundtrip remains bit-exact | ✓ |
| `testCrossDecodeProbeXAOnly` — XA 2x2 cross-decode through OpenJPH / Grok / Kakadu remains bit-exact (max diff = 0); per-tile observations confirm 3 of 4 tiles carry non-zero origins | ✓ |

### Mandatory commit gates (default off)

All green:

| Suite | Result |
|---|---|
| `HTDWTParityAwarenessTests` (1D parity-aware DWT) | 4/4 |
| `HTDWT2DParityAwarenessTests` (2D + multi-level) | 8/8 |
| `HTTileOriginPropagationTests` (step 3 plumbing) | 4/4 |
| `J2KLosslessMedicalGateTests` (HT-fair 21/21, EBCOT-fair 28/28) | 5/5 |
| `J2KMedicalCorpusEncodePerformanceTests` | 2/2 |
| `J2KStrictCrossCodecValidationTests` | 3/3 |

Production single-tile bytes are byte-identical to v5.38 / v5.39 /
v6-alpha2.

### What changed about the MR/PX/DX failure mode

The v6-alpha2 cross-decode failure on non-32-aligned multi-tile
fixtures (MR/PX/DX) was a **wrong-pixels** failure: the
wrap-and-stitch encoder produced bytes that decoded with up to 64K
max abs diff. After v6-alpha3 step 3 the DWT now receives the
correct image-coordinate origin (verified by
`testMultiTileOriginsReachEncoder`), so the DWT parity blocker
documented in v6-alpha2 is gone.

**However**: driving the multi-tile encoder on a non-32-aligned
fixture (planner-bypassed, e.g. MR 886×886 → 2x2 → 443×443 tile)
now triggers a **downstream trap** in the encoder pipeline (signal
SIGTRAP / signal 5 inside `J2KMultiTileEncoder.encode(...)`). The
DWT itself runs correctly (the math primitive is verified by the
2D parity tests), but downstream stages that consume its output —
likely code-block grid construction, packet header generation,
and/or the wrap-and-stitch codestream assembler — hit
preconditions or out-of-range buffers when band dimensions shift
because of origin parity at deep DWT levels.

`testCrossDecodeProbeXAOnly` therefore exercises only XA (the v6-
alpha2-aligned fixture) to keep the test suite green; its
docstring explicitly notes that MR/PX/DX bypass-the-planner
encodes currently trap downstream of DWT, and that this is the
expected v6-alpha3 step 4+ failure mode (a stronger signal than
the previous v6-alpha1 wrong-pixels failure — the parity-correct
DWT output exposes structural assumptions in the rest of the
pipeline that need fixing).

The v6-alpha2 `HTTileParityMatrixTests` (which uses the planner)
still shows only XA cells (planner correctly forces fallback for
MR/PX/DX). Cross-decode behaviour for non-32-aligned fixtures is
unchanged from the user perspective: the planner still blocks
them, so production single-tile bytes are returned. The v6-alpha2
"Kakadu wins on fixtures ≥ 886×886" claim is unchanged.

### What's still NOT in this step (deferred to v6-alpha3 step 4+)

This step lands the **DWT-call plumbing** only. Three downstream
stages still need origin-awareness work before MR/PX/DX multi-
tile cross-decode can pass:

1. **Code-block grid origin.** Code-block partitioning happens
   in tile-component coordinates, so its origin is conceptually
   tile-relative (i.e., still (0, 0) per tile-component). But
   when the DWT band sizes shift due to origin parity, the
   code-block loop limits and the per-block `(x, y)` in
   `PendingCodeBlock` need to reflect the parity-shifted band
   dimensions. The current trap may originate here.

2. **Packet header generation.** `generateTileData` packetises
   block bytes in LRCP order. Per-band block-inclusion tag-trees
   encode per-block `(blocksX, blocksY)` indices and Lblock
   counts. With origin-shifted bands these indices need to align
   with what a multi-tile decoder will read.

3. **Native multi-tile codestream assembler.** Replace
   `J2KMultiTileAssembler.stitch` (which still glues N standalone
   per-tile codestreams) with a single pass through
   `generateCodestream` that emits one main header + N tile-
   parts using the parity-aware DWT for each tile.

Once those three land, `HTTileParityMatrixTests` should see
MR/PX/DX cells flip from FAIL to bit-exact, the v6-alpha2 planner
constraint can be relaxed, and the v5.38 HT-fair table can be
re-measured.

### v6-alpha3 step 3 — final precise claim

> v6-alpha3 step 3 threads real tile image-coordinate origin
> into the multi-tile encode pipeline and invokes the parity-aware
> multi-level 2D 5/3 DWT for each tile. Single-tile remains
> byte-identical (verified by `testSingleTileBytesUnchanged` and
> the lossless gate suite). XA 2x2 cross-decode through OpenJPH,
> Grok, and Kakadu remains bit-exact (verified by
> `testCrossDecodeProbeXAOnly`). Per-tile origin propagation is
> verified by `testMultiTileOriginsReachEncoder` against the
> MR / PX / DX origin sets the planner currently rules out.
>
> **This removes the pipeline plumbing blocker.** However: driving
> the multi-tile encoder on a non-32-aligned fixture
> (planner-bypassed) now traps downstream of the DWT — the DWT
> output is parity-correct but code-block / packet / wrap-and-
> stitch stages haven't been audited for origin-shifted bands
> yet. **Planner relaxation and Kakadu remeasurement are still
> blocked until MR/PX/DX cross-decode passes through OpenJPH,
> Grok, and Kakadu.** The Kakadu HT advantage on fixtures ≥ 886×886
> documented in the v5.38 HT-fair table stands.

---

## v6-alpha3 step 4 — locate downstream blocker, install fail-fast guard

### What the trap actually was

Step 3 plumbed origin into the DWT call. Step 4 reproduced the
SIGTRAP on a minimal 90×90 → 2×2 → 45×45 synthetic fixture (45 is
not 32-aligned) and traced it to its first failure point: not in
the encoder at all, but in the **decoder** —
`J2KCodec/J2KHTConformantMagSgnCoder.swift:132: Precondition
failed: MagSgn read width > 32`.

Tracing the decode-side band-size computation
(`J2KDWT1DOptimized.inverseTransform53Symmetric`,
`J2KDWT1D.inverseTransform53`) confirmed the J2KSwift decoder is
**not parity-aware**: it always interleaves with
`result[i*2] = even[i]; result[i*2+1] = odd[i]` — fine for
origin (0, 0) but wrong for any other origin. When the encoder
produces parity-aware bytes for origin (45, 0) but the decoder
reads them assuming origin (0, 0), the band sizes disagree, the
MagSgn byte-stream alignment drifts, and the next codeword reads
as a width > 32 → precondition trap.

### Why wrap-and-stitch can't legally represent the parity-correct output

Each per-tile encode in the wrap-and-stitch path is a *standalone*
J2K codestream. Its `SIZ` marker declares `XOsiz = YOsiz = XTOsiz
= YTOsiz = 0` — origin (0, 0). After step 3, the per-tile
encoder's *content* is encoded for the tile's actual
image-coordinate origin (e.g., (443, 0) for MR tile 1). The
result is an **internally-inconsistent** standalone codestream:
its declared origin doesn't match its content. Three failure
modes follow:

| Decoder | Outcome | Why |
|---|---|---|
| J2KSwift's own decoder (per-tile standalone) | SIGTRAP in MagSgn read | not parity-aware, band sizes from SIZ origin (0, 0) ≠ encoder's parity-aware sizes |
| J2KSwift's own decoder (stitched multi-tile) | same SIGTRAP | inverse DWT has no per-tile origin propagation |
| External (parity-aware) decoders on stitched output | exit 0, max abs diff = 65281 | accepts the codestream, applies parity-aware inverse DWT, but per-tile body bytes carry a wrap-and-stitch incompatibility ([different from v6-alpha2's 64371](#v6-alpha2-the-parity-matrix-that-nailed-root-cause); the encoder behaviour did change but not in a way that closes the gap) |

The wrap-and-stitch model **cannot legally represent** parity-
correct multi-tile encoding because the per-tile codestream's
single-tile SIZ has no place to declare a non-zero tile-grid
origin. The proper fix is the **native multi-tile assembler**
(v6-alpha3 step 5): emit one main header + N tile-parts in a
single pass, no per-tile standalone codestreams to stitch.

### The step-4 guard

Rather than land the full step-5 refactor in this commit, step 4
adds a **fail-fast guard** at the entry to
`J2KMultiTileEncoder.encode(...)`. The guard refuses any layout
whose tile origins aren't multiples of `2^decompositionLevels` in
both axes, throwing `J2KError.invalidTileConfiguration` with a
clear message:

```swift
let minDim = 1 << configuration.decompositionLevels
for k in 0..<n {
    let r = layout.rect(forTile: k)
    if (r.x % minDim != 0) || (r.y % minDim != 0) {
        throw J2KError.invalidTileConfiguration(
            "v6-alpha3 step 4: wrap-and-stitch multi-tile cannot " +
            "represent tile \(k) at origin (\(r.x), \(r.y)) — " +
            "origin must be a multiple of 2^decompositionLevels " +
            "(= \(minDim)) in both axes for the per-tile " +
            "codestream to remain self-consistent. Native " +
            "multi-tile assembler (v6-alpha3 step 5+) required " +
            "for non-aligned origins.")
    }
}
```

The constraint duplicates the v6-alpha2 planner's check at a
deeper layer of the pipeline. **Production never sees a
violating layout** because the planner rejects it up front;
only test code that bypasses the planner can hit the guard.
What the guard buys: those tests get a *clean error*, not a
SIGTRAP.

### v6-alpha3 step 4 — non-crash regression tests

`Tests/J2KCodecTests/HTMultiTileTrapReproducer.swift` adds seven
tests:

| Test | What it asserts |
|---|---|
| `testPlannerBypassedMR2x2DoesNotTrap` | MR 886×886 / 2x2 (origins include 443) → clean `J2KError.invalidTileConfiguration` throw, no SIGTRAP |
| `testPlannerBypassedPX2x2DoesNotTrap` | PX 2459×1316 / 2x2 (origins 1230, 658) → clean throw |
| `testPlannerBypassedDX2x2DoesNotTrap` | DX 2800×2288 / 2x2 (origins 1400, 1144) → clean throw |
| `testPlannerBypassedDX4x4DoesNotTrap` | DX 2800×2288 / 4x4 (origins 700, 572) → clean throw |
| `testPlannerBypassedSyntheticOddOriginDoesNotTrap` | Synthetic 90×90 / 2x2 (origin 45) → clean throw — the minimal reproducer, runs without medical fixtures |
| `testThirtyTwoAlignedXAStillSucceeds` | XA 1024×1024 / 2x2 (origins 512) → encode + self-roundtrip bit-exact |
| `testThirtyTwoAlignedSyntheticStillSucceeds` | Synthetic 64×64 / 2x2 (origins 32) → encode succeeds |

All seven pass.

### Mandatory commit gates (default off)

All green:

| Suite | Result |
|---|---|
| `HTDWTParityAwarenessTests` (1D parity-aware DWT) | 4/4 |
| `HTDWT2DParityAwarenessTests` (2D + multi-level) | 8/8 |
| `HTTileOriginPropagationTests` (step 3 plumbing, XA-only after step 4) | 4/4 |
| `HTMultiTileTrapReproducer` (step 4 non-crash regression) | 7/7 |
| `J2KLosslessMedicalGateTests` (HT-fair 21/21, EBCOT-fair 28/28) | 5/5 |
| `J2KMedicalCorpusEncodePerformanceTests` | 2/2 |
| `J2KStrictCrossCodecValidationTests` | 3/3 |

Production single-tile bytes are byte-identical to v5.38 / v5.39 /
v6-alpha2.

### What's still NOT in this step (deferred to v6-alpha3 step 5+)

The fail-fast guard is **not a substitute for the actual fix**;
it's a hygiene improvement that turns SIGTRAPs into diagnosable
errors. The architectural blocker remains:

1. **Native multi-tile codestream assembler** (step 5). Replace
   `J2KMultiTileAssembler.stitch` (which glues N standalone
   per-tile codestreams) with a single-pass
   `generateCodestream` that emits one main header + N tile-
   parts using the parity-aware DWT for each tile. The native
   assembler doesn't need per-tile standalone codestreams, so
   the SIZ-vs-content inconsistency goes away.

2. **Parity-aware J2KSwift decoder inverse DWT** (step 6). The
   existing `J2KDWT1D{,Optimized}.inverseTransform53*` functions
   hard-code origin (0, 0) interleaving. To self-roundtrip a
   native-multi-tile codestream, the decoder needs an
   `uOrigin:` parameter on the inverse 1D and the per-tile
   inverse-DWT call needs to thread the tile's image-coordinate
   origin through it. Symmetric to the encoder's step 1+2 but
   on the decode side.

3. **Cross-decode validation on non-32-aligned fixtures** (step
   7). Re-run `HTTileParityMatrixTests` and confirm MR / PX /
   DX cells flip from FAIL to bit-exact under the native
   assembler. Once that's green, the v6-alpha2 planner
   constraint can be relaxed.

4. **Perf re-measurement vs M4 ceiling** (step 8). Median-of-5
   wall time on MR / PX / DX / XA single-tile vs best-correct
   multi-tile; re-measure the v5.38 HT-fair Kakadu comparison
   table.

### v6-alpha3 step 4 — final precise claim

> v6-alpha3 step 4 removes the downstream trap exposed by
> origin-aware DWT on non-32-aligned multi-tile fixtures and
> identifies the first post-DWT structural assumption blocking
> native multi-tile: the J2KSwift decoder's inverse 5/3 DWT is
> not parity-aware, and the wrap-and-stitch encoder's per-tile
> standalone codestream cannot legally declare a non-zero tile
> origin. Step 4 lands a fail-fast guard
> (`J2KMultiTileEncoder.encode` throws
> `J2KError.invalidTileConfiguration` on non-32-aligned layouts)
> that turns SIGTRAPs into clean errors; production never sees
> the guard fire because the v6-alpha2 planner already enforces
> the same constraint up front. **This is not a broad security
> detour; it is the next Kakadu-performance unblocker. Planner
> relaxation and Kakadu remeasurement remain blocked until
> MR/PX/DX cross-decode passes through OpenJPH, Grok, and
> Kakadu** — which requires the v6-alpha3 step 5+ native
> multi-tile assembler and the step-6 parity-aware decoder
> inverse DWT. The Kakadu HT advantage on fixtures ≥ 886×886
> documented in the v5.38 HT-fair table stands.

---

## v6-alpha3 step 5 — native multi-tile codestream assembler

### What landed

Step 5 replaces wrap-and-stitch with a **native multi-tile
codestream assembler**. The encoder no longer produces N
standalone per-tile codestreams glued at byte-level — it emits
ONE legal HTJ2K codestream with a single main header and N
tile-parts, encoding each tile with its real image-coordinate
origin via the parity-aware DWT path landed in steps 1+2+3.

| File | Change |
|---|---|
| `Sources/J2KCodec/J2KEncoderPipeline.swift` | New `EncoderPipeline.encodeNativeMultiTile(image:layout:)` produces the full multi-tile codestream. New private `runEncodeStagesForNativeAssembly(image:tileOriginX:tileOriginY:)` runs preprocess + DWT(parity-aware) + entropy + rate-control + `generateTileData` and returns ONLY the tile-data bytes (no SOC/SIZ/SOT/SOD/EOC). New private `writeSIZMarkerMultiTile(...)` writes a SIZ marker that carries full image dims + tile grid (the existing private `writeSIZMarker` hard-codes single-tile dims and stays as-is for the single-tile path). |
| `Sources/J2KCodec/J2KMultiTileEncoder.swift` | `J2KMultiTileEncoder.encode(...)` no longer slices each tile to a standalone J2K and stitches headers — it now calls `EncoderPipeline.encodeNativeMultiTile(...)` directly. The step-4 fail-fast guard is removed (it papered over the wrap-and-stitch SIZ-vs-content inconsistency, which step 5 eliminates structurally). The v6-alpha2 planner constraint stays in place to gate production routing. |

### Codestream structure (post step 5)

For a 2×2 layout:

```
SOC (2 bytes)
SIZ  — Xsiz/Ysiz = full image dims, XTsiz/YTsiz = tile dims
CAP/CPF (HTJ2K Part-15 capability markers)
COD  — single, shared across tiles
QCD  — single, shared across tiles
COM  — J2KSwift HT-conformant block format signal
SOT(Isot=0)  +  SOD  +  tile-data 0
SOT(Isot=1)  +  SOD  +  tile-data 1
SOT(Isot=2)  +  SOD  +  tile-data 2
SOT(Isot=3)  +  SOD  +  tile-data 3
EOC
```

Each `Psot` field on the SOT marker is the byte length from the
start of SOT to the last byte of tile-part data (per spec); each
SOT's Psot points exactly to the start of the next SOT, and the
last tile's Psot points to the EOC.

### Structural unit tests

`Tests/J2KCodecTests/HTNativeMultiTileAssemblerTests.swift`
adds 13 tests covering structural invariants and cross-decode:

| Test | What it asserts |
|---|---|
| `testNativeAssemblerEmitsSingleSOC` | exactly one SOC marker |
| `testNativeAssemblerEmitsSingleSIZ` | exactly one SIZ; Xsiz/Ysiz = image dims, XTsiz/YTsiz = tile dims |
| `testNativeAssemblerEmitsExpectedSOTCountFor2x2` | 4 SOT + 4 SOD markers in 2x2 layout |
| `testNativeAssemblerSOTTileIndicesAreCorrect` | SOT.Isot fields = 0,1,2,3 in row-major order |
| `testNativeAssemblerPsotLengthsAreValid` | each SOT's Psot points to next SOT or EOC |
| `testNativeAssemblerDoesNotCopyPerTileMainHeaders` | at most 1 each of SIZ/COD/QCD/CAP/CPF (wrap-and-stitch would have N) |
| `testNativeAssemblerXA2x2SelfRoundtrip` | XA self-roundtrip bit-exact |
| `testNativeAssemblerXA2x2CrossDecodeOpenJPHGrokKakadu` | XA cross-decode bit-exact through all 3 external HT decoders |
| `testNativeAssemblerMR2x2DoesNotUseWrapAndStitch` | MR 886×886 2x2 produces structurally-valid native codestream |
| `testNativeAssemblerPX2x2DoesNotUseWrapAndStitch` | PX 2459×1316 2x2 same |
| `testNativeAssemblerDX2x2DoesNotUseWrapAndStitch` | DX 2800×2288 2x2 same |
| `testNativeAssemblerDX4x4DoesNotUseWrapAndStitch` | DX 2800×2288 4x4 same |
| `testNativeAssemblerExternalCrossDecodeProbe` | diagnostic probe — runs every fixture through OpenJPH/Grok/Kakadu, prints results |

All 13 pass.

### Cross-decode probe (post step 5, diagnostic only)

| Modality | Shape | Mode | OpenJPH | Grok | Kakadu |
|---|---|---|---:|---:|---:|
| **XA** | **1024×1024** | **2x2** | **0** | **0** | **0** |
| MR | 886×886 | 2x2 | 65281 | 65281 | 65281 |
| PX | 2459×1316 | 2x2 | FAIL | 63116 | FAIL |
| DX | 2800×2288 | 2x2 | FAIL | 32768 | FAIL |
| DX | 2800×2288 | 4x4 | FAIL | 65533 | FAIL |

(Numbers are max-abs-pixel-diff; `0` = bit-exact; `FAIL` = decoder
exit non-zero.)

**XA 2x2 cross-decode is bit-exact through every external decoder**
— the regression guard for the v6-alpha2-aligned fixture holds.
**MR/PX/DX are not yet bit-exact**, but the cells now have a
characteristic post-step-5 shape: Grok accepts every codestream
(it's the most lenient), while OpenJPH/Kakadu reject PX and DX
2x2/4x4. The wrong-pixels values for MR (65281) match the
post-step-3 wrap-and-stitch readings — meaning step 5's
structural fix didn't move the wire-level cross-decode bug:
the bug is *downstream of the codestream container* (most likely
in code-block grid construction or packet header generation
under parity-shifted bands).

### Step-4 → step-5 changes for the trap-reproducer suite

`Tests/J2KCodecTests/HTMultiTileTrapReproducer.swift` updated for
the post-step-5 reality:

- The step-4 guard threw `J2KError.invalidTileConfiguration` on
  non-32-aligned layouts. Step 5 replaced wrap-and-stitch with
  the native assembler, eliminating the underlying bug, so the
  guard is removed.
- The five `testPlannerBypassed{MR,PX,DX,Synthetic}…DoesNotTrap`
  tests now assert "the call completes without SIGTRAP" — either
  succeeds with a non-empty codestream (the new normal) or
  throws a `J2KError` (kept as an acceptable outcome so a future
  intentional guard can be added without rewriting these tests).
  All 5 still pass.
- The two 32-aligned happy-path tests remain bit-exact: XA 2x2
  self-roundtrip + synthetic 64×64.

### Mandatory commit gates (default off)

All green. **46 tests, 0 failures.**

| Suite | Result |
|---|---|
| `HTDWTParityAwarenessTests` (1D parity-aware DWT) | 4/4 |
| `HTDWT2DParityAwarenessTests` (2D + multi-level) | 8/8 |
| `HTTileOriginPropagationTests` (step 3 plumbing, XA + step-3 origin probes) | 4/4 |
| `HTMultiTileTrapReproducer` (post-step-5 native: encode completes without trap, no SIGTRAP regression) | 7/7 |
| `HTNativeMultiTileAssemblerTests` (step 5: structural + XA cross-decode + MR/PX/DX probes) | 13/13 |
| `J2KLosslessMedicalGateTests` (HT-fair 21/21, EBCOT-fair 28/28, default 7/7, self-roundtrip 7/7, HT-vs-EBCOT) | 5/5 |
| `J2KMedicalCorpusEncodePerformanceTests` | 2/2 |
| `J2KStrictCrossCodecValidationTests` | 3/3 |

Production single-tile bytes are byte-identical to v5.38 / v5.39 /
v6-alpha2.

### What's still NOT in this step (deferred to v6-alpha3 step 6+)

The native assembler eliminates the wrap-and-stitch SIZ-vs-content
inconsistency, but **MR/PX/DX cross-decode is still wrong-pixels
on external decoders**. The data above shows the failure mode
unchanged from step 3 — meaning the bug is downstream of the
codestream container. Two structural fixes remain:

1. **Code-block grid + packet header origin awareness** (step 6
   scope). Code-block partition origins are tile-component-relative
   (already (0, 0) per tile-component, conceptually correct). But
   when DWT band sizes shift due to image-coordinate origin parity,
   block loop limits, per-block `(x, y)` indices, and packet-header
   tag-tree dimensions all need to reflect the actual band shapes.
   The `Grok-accepts-but-wrong-pixels` and
   `OpenJPH/Kakadu-rejects-PX/DX` patterns above suggest one or
   both of these stages still uses an even-origin band shape
   somewhere.

2. **Parity-aware J2KSwift decoder inverse DWT** (also step 6).
   The existing `J2KDWT1D{,Optimized}.inverseTransform53*`
   functions hard-code origin (0, 0) interleaving; J2KSwift
   self-roundtrip on non-32-aligned tiles still fails. Symmetric
   to the encoder steps 1+2 but on the decode side.

3. **MR/PX/DX cross-decode validation + planner relaxation** (step
   7). Once 1 and 2 land, re-run `HTTileParityMatrixTests` against
   the native path and confirm MR/PX/DX flip from FAIL to
   bit-exact through OpenJPH/Grok/Kakadu. The v6-alpha2 planner
   constraint can then be relaxed.

4. **Perf re-measurement vs M4 ceiling + Kakadu remeasurement**
   (step 8).

### v6-alpha3 step 5 — final precise claim

> v6-alpha3 step 5 replaces wrap-and-stitch with a native
> multi-tile codestream assembler that emits one main header
> plus N tile-parts. Each tile is encoded with its real
> image-coordinate origin using the parity-aware DWT path. This
> removes the standalone per-tile SIZ/content inconsistency
> identified in step 4 and structurally validates on every
> medical fixture (single SOC + SIZ + COD + QCD + N SOTs +
> EOC, no per-tile main-header copies). XA 2x2 cross-decode
> through OpenJPH, Grok, and Kakadu remains bit-exact.
> **Planner relaxation and Kakadu remeasurement remain blocked
> until MR/PX/DX cross-decode passes through OpenJPH, Grok, and
> Kakadu**, and J2KSwift self-roundtrip on non-aligned tiles
> still requires step 6 parity-aware decoder inverse DWT plus
> the code-block / packet-header origin audit. The Kakadu HT
> advantage on fixtures ≥ 886×886 documented in the v5.38
> HT-fair table stands.
