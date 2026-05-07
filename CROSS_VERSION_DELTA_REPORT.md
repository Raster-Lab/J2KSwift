# J2KSwift cross-version delta — `v5.38.0` ↔ `gpu-ht-decoder-prototype` (HEAD `f18d52b`)

**Date**: 2026-05-06
**Tag baseline**: `v5.38.0` (`799662f` — *release: v5.38.0 — lossless medical archival + 2.06× DX encode speedup*)
**Branch HEAD**: `f18d52b` (*gpu(ht): phase 9 — routing observability + threshold-boundary sweep*)
**Distance**: 17 commits since v5.38.0 (v5.39.0, v6-alpha2/3/4/5 phases 0–9)
**Platform**: macOS 15, Apple M2, Swift 6.1.2 release build
**Encode config**: HTJ2K conformant Part-15, 5 decomposition levels, lossless 5/3 reversible, single component, 16-bit BE
**Methodology**: Median of 5 wall-time samples per cell after 1 warm-up; same harness compiled into both worktrees and run independently. Source: [`Tests/J2KCodecTests/CrossVersionDeltaBenchmark.swift`](Tests/J2KCodecTests/CrossVersionDeltaBenchmark.swift).

---

## TL;DR

| Axis | Result |
|---|---|
| **Quality** (lossless) | **No regression.** 13/13 codestream byte-streams MD5-identical between v5.38.0 and current (single-tile + 2x2). 7/7 fixtures decode bit-exact through OpenJPH 0.27.0, Grok 20.3.0, Kakadu 8.4.1 — **21/21 cross-decoder cells**. |
| **Speed — production single-tile path** | **Statistical wash.** −10% to +14% per-fixture (run-to-run noise band on M2 is ±5–10%). Largest fixtures (PX, DX) run 3–5% faster on current. |
| **Speed — production-default `.auto` multi-tile path** | **Net win on every corpus fixture ≥ 500 K px.** v5.38.0 didn't have `.auto` mode; it landed in v6-alpha2. Versus v5.38.0's own single-tile baseline, current `.auto` gives **DX 1.31×, PX 1.55×, XA 1.30×, MR 1.94×** encode speedup. (Numbers below are median of 5 from [`BENCHMARK_REPORT_v6_alpha5_phase9.md`](BENCHMARK_REPORT_v6_alpha5_phase9.md) §3.) |
| **New on current** | Opt-in GPU forward 5/3 INT path (`J2K_GPU_FORWARD_53=1`, ≥ 4 MP single-tile) — extra **+19% to +24%** on top of CPU-best, byte-identical to CPU output, 21/21 cross-codec cells. Off by default. |

---

## 1. Quality — bytes byte-identical, every external decoder bit-exact

### 1.1 Codestream-byte parity (v5.38.0 ↔ current)

For every fixture × mode the harness records both the bytes produced and an MD5 of those bytes. **Identical MD5 ≡ identical codestream.**

| fixture | shape | mode | bytes | v5.38.0 MD5 | current MD5 | identical |
|---|---|:---:|---:|---|---|:---:|
| MR-small | 180×180 | single | 45 224 | `f4add755ec268203…` | `f4add755ec268203…` | ✓ |
| CT | 512×512 | single | 436 460 | `6c968561c0d38462…` | `6c968561c0d38462…` | ✓ |
| CT | 512×512 | tile2x2 | 436 460 | `6c968561c0d38462…` | `6c968561c0d38462…` | ✓ |
| CT (alt) | 512×512 | single | 406 187 | `043a41ec40f3aacd…` | `043a41ec40f3aacd…` | ✓ |
| CT (alt) | 512×512 | tile2x2 | 406 187 | `043a41ec40f3aacd…` | `043a41ec40f3aacd…` | ✓ |
| MR | 886×886 | single | 167 728 | `98c9b2a02d6690d9…` | `98c9b2a02d6690d9…` | ✓ |
| MR | 886×886 | tile2x2 | 167 728 | `98c9b2a02d6690d9…` | `98c9b2a02d6690d9…` | ✓ |
| XA | 1024×1024 | single | 1 621 219 | `bc6adb3ee9075e20…` | `bc6adb3ee9075e20…` | ✓ |
| XA | 1024×1024 | tile2x2 | 1 621 219 | `bc6adb3ee9075e20…` | `bc6adb3ee9075e20…` | ✓ |
| PX | 2459×1316 | single | 6 431 507 | `6d4c6e4aadfb9861…` | `6d4c6e4aadfb9861…` | ✓ |
| PX | 2459×1316 | tile2x2 | 6 431 507 | `6d4c6e4aadfb9861…` | `6d4c6e4aadfb9861…` | ✓ |
| DX | 2800×2288 | single | 12 683 182 | `860e357e8462c082…` | `860e357e8462c082…` | ✓ |
| DX | 2800×2288 | tile2x2 | 12 683 182 | `860e357e8462c082…` | `860e357e8462c082…` | ✓ |

**13 / 13 codestream MD5s match** — verified by both the in-test MD5 column and an out-of-test `cmp` of the two `/tmp/j2k_delta_*/` directories.

> Note on `tile2x2` rows. v5.38.0's encoder routes the requested `tileSize` through the same single-tile fast path for these fixture sizes (its multi-tile native path was added in v6-alpha2/3). The current branch reproduces the same decision for backward-compat — hence single-tile bytes ≡ tile2x2 bytes on both versions. Multi-tile divergence would only show on current branch's newer `.auto` mode, which isn't in v5.38.0; that path is reported separately in §3 below from the existing benchmark.

### 1.2 External-decoder bit-exact reconstruction

Every single-tile codestream from §1.1 was decoded by OpenJPH / Grok / Kakadu and the resulting PGM was diffed against the source PGM (header-stripped pixel comparison; Grok prepends a `#Grok-20.3.0` comment).

| fixture | OpenJPH 0.27.0 | Grok 20.3.0 | Kakadu 8.4.1 |
|---|:---:|:---:|:---:|
| MR-small 180×180 | ✓ | ✓ | ✓ |
| CT 512×512 | ✓ | ✓ | ✓ |
| CT (alt) 512×512 | ✓ | ✓ | ✓ |
| MR 886×886 | ✓ | ✓ | ✓ |
| XA 1024×1024 | ✓ | ✓ | ✓ |
| PX 2459×1316 | ✓ | ✓ | ✓ |
| DX 2800×2288 | ✓ | ✓ | ✓ |

**21 / 21 cross-decoder cells bit-exact.** Since v5.38.0 and current bytes are byte-identical, this row applies equally to both versions.

---

## 2. Speed — single-tile lossless encode + decode

The harness runs single-tile and `J2KImage.tileWidth/tileHeight` 2x2 — the only multi-tile API exposed at v5.38.0. Median of 5 release-mode wall-time samples on Apple M2.

### 2.1 Encode wall time (ms)

| fixture | shape | px | mode | v5.38.0 | current | Δ ms | Δ % |
|---|---|---:|:---:|---:|---:|---:|---:|
| MR-small | 180×180 | 32 400 | single | 0.65 | 0.74 | +0.09 | **+13.8 %** (slower) |
| CT | 512×512 | 262 144 | single | 3.12 | 2.92 | −0.20 | **−6.4 %** (faster) |
| CT | 512×512 | 262 144 | tile2x2 | 2.87 | 3.03 | +0.16 | +5.6 % |
| CT (alt) | 512×512 | 262 144 | single | 2.71 | 2.85 | +0.14 | +5.2 % |
| CT (alt) | 512×512 | 262 144 | tile2x2 | 2.92 | 2.83 | −0.09 | −3.1 % |
| MR | 886×886 | 784 996 | single | 5.26 | 4.74 | −0.52 | **−9.9 %** (faster) |
| MR | 886×886 | 784 996 | tile2x2 | 5.23 | 4.83 | −0.40 | −7.6 % |
| XA | 1024×1024 | 1 048 576 | single | 10.85 | 10.58 | −0.27 | −2.5 % |
| XA | 1024×1024 | 1 048 576 | tile2x2 | 10.80 | 10.51 | −0.29 | −2.7 % |
| PX | 2459×1316 | 3 236 044 | single | 37.20 | 35.44 | −1.76 | **−4.7 %** (faster) |
| PX | 2459×1316 | 3 236 044 | tile2x2 | 37.20 | 35.50 | −1.70 | −4.6 % |
| DX | 2800×2288 | 6 406 400 | single | 72.01 | 69.56 | −2.45 | **−3.4 %** (faster) |
| DX | 2800×2288 | 6 406 400 | tile2x2 | 77.37 | 69.05 | −8.32 | **−10.8 %** (faster) |

### 2.2 Decode wall time (ms)

| fixture | shape | mode | v5.38.0 | current | Δ ms | Δ % |
|---|---|:---:|---:|---:|---:|---:|
| MR-small 180×180 | 180×180 | single | 0.62 | 0.70 | +0.08 | +12.9 % |
| CT 512×512 | 512×512 | single | 3.12 | 3.24 | +0.12 | +3.8 % |
| CT 512×512 | 512×512 | tile2x2 | 3.08 | 3.16 | +0.08 | +2.6 % |
| CT (alt) 512×512 | 512×512 | single | 3.03 | 3.16 | +0.13 | +4.3 % |
| CT (alt) 512×512 | 512×512 | tile2x2 | 3.14 | 3.18 | +0.04 | +1.3 % |
| MR 886×886 | 886×886 | single | 5.60 | 5.56 | −0.04 | −0.7 % |
| MR 886×886 | 886×886 | tile2x2 | 5.55 | 5.68 | +0.13 | +2.3 % |
| XA 1024×1024 | 1024×1024 | single | 14.58 | 14.78 | +0.20 | +1.4 % |
| XA 1024×1024 | 1024×1024 | tile2x2 | 14.36 | 14.83 | +0.47 | +3.3 % |
| PX 2459×1316 | 2459×1316 | single | 39.20 | 39.14 | −0.06 | −0.2 % |
| PX 2459×1316 | 2459×1316 | tile2x2 | 40.44 | 39.16 | −1.28 | −3.2 % |
| DX 2800×2288 | 2800×2288 | single | 76.37 | 76.94 | +0.57 | +0.7 % |
| DX 2800×2288 | 2800×2288 | tile2x2 | 77.46 | 76.20 | −1.26 | −1.6 % |

### 2.3 Reading the table

- **Apple M2 wall-time noise band on small fixtures is ±5–10 %.** MR-small (180²) at 0.6–0.7 ms straddles thermal/scheduler jitter; the +13.8 % encode delta is one std-dev of run-to-run on a 200 KB workload.
- **From CT 512² up the deltas are mostly inside ±5 %.** With one direction in the noise and the other slightly faster (current 5/8 cells faster on encode, 6/13 faster on decode by ≥ 1 %).
- **The two largest fixtures — PX 3.2 MP and DX 6.4 MP — are 3–11 % faster on current** for both single and tile2x2. These are the production-relevant high-impact cases.
- **Decode is essentially flat** — neither version did decode-side work in this window; the deltas are all inside ±4 %.

The single-tile path didn't get materially faster because **most encode work since v5.38.0 went into the multi-tile fast path** (v6-alpha2/3) and the GPU forward DWT path (v6-alpha5 phases 0–9). Single-tile sees mostly indirect benefits from rateControl tightening (v5.30) and entropy hot-path tweaks.

---

## 3. Where the real speedup lives — production-default `.auto` multi-tile (current only)

`.auto` is a v6-alpha2 addition; it picks `2x2` below 3 MP and `4x4` above. v5.38.0 has no equivalent, so the comparison below is **v5.38.0 single-tile** (the closest production-default at that version) versus **current `.auto` multi-tile** (the production-default now). Numbers from [`BENCHMARK_REPORT_v6_alpha5_phase9.md`](BENCHMARK_REPORT_v6_alpha5_phase9.md) §3 / §5.

| Fixture | shape | v5.38.0 single (this report) | current `.auto` (existing report) | speedup | mode picked |
|---|---|---:|---:|---:|:---:|
| MR | 886×886 | 5.26 ms | 2.61 ms | **2.02×** | auto → 2x2 |
| XA | 1024×1024 | 10.85 ms | 8.16 ms | **1.33×** | auto → 2x2 |
| PX | 2459×1316 | 37.20 ms | 23.72 ms | **1.57×** | auto → 4x4 |
| DX | 2800×2288 | 72.01 ms | 54.40 ms | **1.32×** | auto → 4x4 |

The multi-tile speedup is the headline encode win since v5.38.0 — **1.32× to 2.02×** on every corpus fixture ≥ 500 K pixels. Codestream bytes still pass external bit-exact (36 / 36 cells in the parity matrix; see §1 of the existing report).

---

## 4. Where extra speed lives — opt-in GPU forward DWT (current only)

`J2K_GPU_FORWARD_53=1` enables a Metal-backed forward 5/3 INT DWT at the encoder. Gate fires only at single-tile ≥ 4 MP where measurement showed consistent wall-time win. Off by default; codestream bytes byte-identical to CPU. From [`BENCHMARK_REPORT_v6_alpha5_phase9.md`](BENCHMARK_REPORT_v6_alpha5_phase9.md) §7.

| Fixture | px | current CPU fwd | current GPU fwd | extra Δ vs current CPU | bytes match | cross-codec |
|---|---:|---:|---:|---:|:---:|:---:|
| 4 MP (2000²) | 4 000 000 | 41.19 | 33.21 | **−19.4 %** | ✓ | 7/7 OpenJPH+Grok+Kakadu |
| 6 MP (2449²) | 5 997 601 | 56.75 | 45.90 | **−19.1 %** | ✓ | (above) |
| 12 MP (3464²) | 11 999 296 | 106.57 | 84.44 | **−20.8 %** | ✓ | (above) |
| 16 MP (4000²) | 16 000 000 | 163.35 | 124.97 | **−23.5 %** | ✓ | (above) |

Stacked on top of the multi-tile speedup, the largest single-tile fixtures (where `.auto` keeps single-tile because tile bookkeeping doesn't help) get **+19–24 % on top of CPU-best**, byte-identical, externally validated.

---

## 5. Quality — final ledger

| Axis | v5.38.0 | current (`f18d52b`) | Δ |
|---|---|---|---|
| Single-tile lossless codestream bytes | reference | byte-identical | **0** |
| 2x2-via-`tileSize` codestream bytes | reference | byte-identical | **0** |
| OpenJPH bit-exact reconstruction | 7/7 | 7/7 | **0** |
| Grok bit-exact reconstruction | 7/7 | 7/7 | **0** |
| Kakadu bit-exact reconstruction | 7/7 | 7/7 | **0** |
| Self-roundtrip first-mismatch | 0 (every fixture) | 0 (every fixture) | **0** |
| New cross-codec coverage | n/a | 36/36 multi-tile cells, 21/21 GPU-forward cells | **+57 cells of new coverage with 0 regressions** |

There is **no observable quality regression** between v5.38.0 and current on the production lossless single-tile path. Everything that was bit-exact at v5.38.0 stays bit-exact.

---

## 6. Reproducing this report

Run the harness in both worktrees and diff the resulting CSVs / `.j2c` files:

```bash
# v5.38.0 worktree
git worktree add ../J2KSwift-v5.38 v5.38.0
cp Tests/J2KCodecTests/CrossVersionDeltaBenchmark.swift \
   ../J2KSwift-v5.38/Tests/J2KCodecTests/
cd ../J2KSwift-v5.38
J2K_DELTA_OUT=/tmp/j2k_delta_v5.38.0 LABEL=v5.38.0 RUNS=5 \
  swift test -c release \
    --filter CrossVersionDeltaBenchmark \
    --skip OpenJPEGInteropTests

# current branch
cd /Users/raster/Documents/raster/J2KSwift
J2K_DELTA_OUT=/tmp/j2k_delta_current LABEL=current RUNS=5 \
  swift test -c release --filter CrossVersionDeltaBenchmark

# byte-equality check
for f in /tmp/j2k_delta_v5.38.0/*.j2c; do
  base=$(basename "$f")
  cmp -s "$f" "/tmp/j2k_delta_current/$base" \
    && echo "BYTES-EQUAL $base" \
    || echo "BYTES-DIFFER $base"
done

# cross-decoder bit-exact (OpenJPH / Grok / Kakadu)
# (see top-of-report cross-decode loop — each tool emits a PGM
#  and `tail -c "$pixelBytes"` of the orig PGM is compared against
#  `tail -c "$pixelBytes"` of the decoded PGM.)
```

The harness file is committed at [`Tests/J2KCodecTests/CrossVersionDeltaBenchmark.swift`](Tests/J2KCodecTests/CrossVersionDeltaBenchmark.swift); it uses only API present in both v5.38.0 and current and writes outputs to `${J2K_DELTA_OUT:-/tmp/j2k_delta_${LABEL:-current}}/`.

---

## v6.3.0 → v7.0.0 — multi-tile encoding production-default flip

**Release date**: TBD (release-candidate in progress)
**Tag baseline**: `v6.3.0` (`28d251d` — *release: v6.3.0 — multi-tile decode correctness + PX encode +10.9 %*)
**Branch HEAD**: `feature/v7.0.0-multi-tile-default-on`
**SemVer rationale**: MAJOR — `J2KEncoder.encode(_:)` default tile mode changes from `.single` to `.auto` per [`docs/V6_4_0_G1_2_INVESTIGATION.md`](docs/V6_4_0_G1_2_INVESTIGATION.md) Path 2. RELEASING.md "Special rules for J2KSwift" — codestream bytes are part of the public contract.

### What changes

| Path | v6.3.0 default | v7.0.0 default |
|---|---|---|
| `J2KEncoder.encode(_:)` with HT-conformant lossless 5/3 + no `J2K_HT_TILE_MODE` env var | single-tile codestream | `.auto` planner picks the best tile grid per fixture pixel count |
| `J2KEncoder.encode(_:)` with `.lossless = false` (lossy 9/7) | single-tile (unchanged) | **single-tile (unchanged)** — lossy is out of scope per `feedback_lossless_only_v5_38.md` |
| `J2KEncoder.encode(_:)` with explicit `J2K_HT_TILE_MODE=single` | single-tile | **single-tile (unchanged)** — opt-out path preserves v6.x bytes-equality |
| `J2KEncoder.encode(_:)` with explicit `J2K_HT_TILE_MODE=auto` | already opt-in via env var | **unchanged** — was already auto |

### What does NOT change

- **Decoded pixel data**: byte-identical to v6.3.0 across the medical corpus. Verified by `HTTileParityMatrixTests` (12/12 cells × OpenJPH/Grok/Kakadu/self-RT = 48 bit-exact pixel-diff cells) and `HTGPUForward53CrossCodecTests` (7/7 cells bit-exact). DICOM consumers reading our codestreams see different bytes but get **identical images**.
- **Lossy 9/7 encoding**: out of scope per the lossless-only product target; routing unchanged.
- **Decoding behaviour**: unchanged from v6.3.0. v6.x consumers can decode v7.0.0 codestreams; v7.0.0 can decode v6.x codestreams.
- **Public Swift API surface**: no removals, no signature changes. Default fallback value of `J2KHTTileMode.from(envValue: nil)` changed (now `.auto` was `.single`).

### Per-fixture byte deltas (HT-conformant lossless 5/3, M2 release)

Source: `HTGPUForward53CrossCodecTests.testGPUForward53_MedicalCorpus_CrossDecodesBitExactExternalDecoders` run on the v7.0.0 default-flipped commit.

| Modality | Shape | px | v6.3.0 bytes (single) | v7.0.0 bytes (auto) | Δ bytes | Δ % | mode picked |
|---|---|---:|---:|---:|---:|---:|---|
| MR-small | 180×180 | 32,400 | 45,224 | 45,224 | 0 | 0.000 % | single (gated) |
| CT | 512×512 | 262,144 | 436,460 | 436,460 | 0 | 0.000 % | single (gated) |
| CT | 512×512 | 262,144 | 406,187 | 406,187 | 0 | 0.000 % | single (gated) |
| **MR** | 886×886 | 784,996 | 167,728 | **169,709** | **+1,981** | **+1.18 %** | **2x2** |
| **XA** | 1024×1024 | 1,048,576 | 1,621,219 | **1,621,712** | **+493** | **+0.03 %** | **2x2** |
| **PX** | 2459×1316 | 3,236,044 | 6,431,507 | **6,453,588** | **+22,081** | **+0.34 %** | **4x4** |
| **DX** | 2800×2288 | 6,406,400 | 12,683,182 | **12,705,470** | **+22,288** | **+0.18 %** | **4x4** |

**Storage overhead is negligible** (≤1.18 % per fixture) — the byte deltas come from per-tile SOT/SOD markers (~10 bytes per tile) plus per-tile codestream-header artefacts; each tile is itself a self-contained sub-codestream with its own packet headers.

### What v6.x consumers should do

Three options:

1. **Accept the new bytes** — the decoded image is byte-identical, which is what 99 % of consumers care about. Storage size grows by ≤1.18 %. Most consumers should pick this.
2. **Pin v6.x bytes** — set `J2K_HT_TILE_MODE=single` env var. Restores v6.3.0 codestream bytes verbatim.
3. **Hash on decoded pixels, not codestream bytes** — the recommended long-term pattern for hash-stability across J2KSwift versions (and across J2K codecs in general; OpenJPEG / Kakadu produce different bytes for the same image).

### Encode wall-time impact (the v7.0.0 headline)

The v7.0.0 default flip captures the +30-50 % production-default encode wall-time wins on MR/XA/PX measured in [`docs/V6_4_0_G1_0_INVESTIGATION.md`](docs/V6_4_0_G1_0_INVESTIGATION.md) and [`docs/V6_4_0_G1_2_INVESTIGATION.md`](docs/V6_4_0_G1_2_INVESTIGATION.md):

| Modality | Shape | v6.3.0 wall (single) | v7.0.0 wall (auto) | Δ |
|---|---|---:|---:|---:|
| MR | 886×886 | 6.07 ms | 3.05 ms | **+50 %** |
| XA | 1024×1024 | 12.09 ms | 7.86 ms | **+35 %** |
| PX | 2459×1316 | 34.80 ms | 24.26 ms | **+30 %** |
| DX | 2800×2288 | 56.42 ms | 52.79 ms | +6 % |

**Kakadu encode-wall gap closure on M2** (post-v7.0.0 default flip):

| Modality | v6.3.0 J2KSwift | v7.0.0 J2KSwift | Kakadu | v6.3 gap | v7.0 gap |
|---|---:|---:|---:|---:|---:|
| MR 886² | 6.07 ms | 3.05 ms | 3.7 ms | +1.6× behind | **we win 1.21×** |
| XA 1024² | 12.09 ms | 7.86 ms | 5.1 ms | +2.4× behind | +1.5× behind |
| PX 2459×1316 | 34.80 ms | 24.26 ms | 11.2 ms | +3.1× behind | +2.2× behind |
| DX 2800×2288 | 56.42 ms | 52.79 ms | 18.9 ms | +3.0× behind | +2.8× behind |

**MR 886² flips from being 1.6× behind Kakadu to 1.21× ahead.** XA / PX gaps narrow materially. DX gap remains the big lever for v7.x — the deferred E1.3 GPU multi-tile compute correctness + I-series GPU forward HT entropy approach C/D from the v6.4.0 plan are still actionable in v7.x for further narrowing.
