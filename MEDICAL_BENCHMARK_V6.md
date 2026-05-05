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
