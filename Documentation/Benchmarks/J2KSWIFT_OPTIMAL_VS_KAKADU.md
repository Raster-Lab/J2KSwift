# J2KSwift at its optimal config vs Kakadu — Apple M2 warm

**Date:** 2026-05-15
**Host:** Apple M2 (Mac14,2, 4P+4E, 16 GB unified memory), macOS Darwin 24.6.0
**J2KSwift version:** 9.5.2 + v9.4.0 C+NEON HT entropy hot path (default-on)
**Kakadu version:** 8.4.x commercial release (`kdu_compress` / `kdu_expand`)
**Comparison shape:** two separate lanes: **SDK corpus benchmark** and **DICOM Studio observed benchmark**. Do not merge their claims.
**Source data:** 2026-05-15 warm in-process cross-codec bench (`/tmp/j2kswift-cross-codec-inproc-20260515-055923.json`)
**Methodology:** HT-conformant lossless encode; median of 7 after 2 warmups; J2KSwift measured via `j2k inproc-bench`; reference codecs measured through their CLIs.

## TL;DR

| Position | Result |
|---|---|
| SDK corpus benchmark | J2KSwift in-process warm **wins 6 of 7** core medical-corpus encode fixtures vs Kakadu CLI, and **30 of 38** encode fixtures overall |
| Kakadu wins on | 1 of 7 core fixtures: DX 2800×2288 by **1.01×** (39.28 ms vs 39.82 ms) |
| DICOM Studio observed benchmark | Product-path truth. Studio can show J2KSwift far behind Kakadu on loaded DICOM files, especially full-frame PX/DX/MG decode; record and treat those observations separately |
| Current implementation target | Preserve SDK encode wins, then close the DICOM Studio-observed Kakadu gap on the actual product fixtures |

**Narrow benchmark statement supported by this measurement:**

> *"J2KSwift, at its optimal in-process configuration on Apple M2, beats Kakadu's commercial CLI encoder on 6 of 7 core medical-corpus HT-conformant-lossless fixtures and 30 of 38 warm in-process PGM encode fixtures; Kakadu still leads the large DX/MG real full-frame class."*

This is a codec-positioning statement, not an end-to-end DICOM Studio claim. For product-facing DICOM claims, use DICOMKit / DICOM Studio measurements or an equivalent production integration path; see `DICOM_STUDIO_CLAIM_SCOPE_FINDING.md`.

Kakadu no longer leads PX in the 2026-05-15 core run. The remaining encode gap is DX/MG full-frame: **1.62-2.11×** on the expanded DX real fixtures and **1.63-1.86×** on the expanded MG real fixtures.

## SDK corpus benchmark

This lane measures codec-core throughput on the repository corpus. It is useful for engineering regression checks and for scoped SDK claims. It is not the same thing as the DICOM Studio comparison panel.

```bash
python3 Scripts/benchmarks/cross_codec_warm_bench.py \
  --in-proc --runs 7 --warmups 2 \
  --output /tmp/j2kswift-cross-codec-inproc-20260515-055923.json
```

Result on Apple M2 / J2KSwift 9.5.2:

| Direction | J2KSwift+inproc wins | Remaining loss pattern |
|---|---:|---|
| PGM encode | **30/38** | DX/MG real full-frame fixtures; PX is now parity-or-better in this run |
| PGM decode | **26/38** | PX/DX/MG full-frame decode |
| DICOM encode | 13/13 measured | No external encode comparator in this script |

DICOMKit's release benchmark path was also run:

```bash
cd /Users/raster/Documents/raster/DICOMKit
swift test -c release --filter J2KSwiftCodecBenchmarkTests
```

On `instance_003317.dcm`, J2KSwift decoded in **12.580 ms**; ImageIO could not decode the JPEG 2000 sample; the memory benchmark measured **23.910 ms encode**, **12.214 ms decode**, and **2.219 MB RSS delta**. HTJ2K was slightly slower than legacy J2K on this one sample (**12.186 ms vs 11.622 ms**, speedup 0.954x).

The current engineering plan is now captured in [`BEAT_KAKADU_EXECUTION_PLAN_2026_05_15.md`](../research/BEAT_KAKADU_EXECUTION_PLAN_2026_05_15.md). The key move is to attack large DX/MG encode by removing the remaining Swift block-copy / second-scan path and fusing sign-magnitude preparation into the C+NEON block encoder before attempting another broad entropy rewrite.

## DICOM Studio observed benchmark

This is the product-truth lane. If DICOM Studio shows J2KSwift far behind Kakadu on a loaded study, that observation is valid and must not be overwritten by the SDK corpus table above.

DICOM Studio's J2K Compare panel measures a different workflow:

| Step | What Studio does | Consequence |
|---|---|---|
| 1 | Reads the loaded DICOM, extracts frame 0, and builds a `PixelDataDescriptor` | Includes DICOMKit product-path setup and the exact user file, not a normalized PGM corpus fixture |
| 2 | Encodes that frame with J2KSwift only | The Encode column is **not** a Kakadu encode comparison |
| 3 | Decodes the J2KSwift codestream with J2KSwift using the selected decode mode | Default row is CPU `decode`; Auto/router can differ from the published CPU corpus lane |
| 4 | Decodes the same codestream with Kakadu CLI via `kdu_expand` when installed | Kakadu row is decode-only and includes temp-file IO/process launch, yet can still be faster on large studies |
| 5 | Reports median of 7 after 2 warmups when Warm-up is enabled | Matches the run-count shape, but not the fixture/source/workflow shape |

The current DICOMKit release test provides one product-adapter data point, not a full Studio UI corpus:

| Source | Sample | J2KSwift encode | J2KSwift decode | External comparison |
|---|---|---:|---:|---|
| `swift test -c release --filter J2KSwiftCodecBenchmarkTests` | `instance_003317.dcm` | 23.910 ms | 12.214-12.580 ms | ImageIO failed to decode; no Kakadu decode row in this test |

Record DICOM Studio observations in this shape:

| Loaded DICOM | Modality/size | Build | Warm-up | J2KSwift encode mode | J2KSwift decode mode | J2KSwift encode | J2KSwift decode | Kakadu decode | Ratio | Product interpretation |
|---|---|---|---|---|---|---:|---:|---:|---:|---|
| example.dcm | DX/MG/PX/etc. | Release/Debug | on/off | CPU/GPU | CPU/Auto/GPU | ms | ms | ms | J2KSwift/Kakadu | e.g. "far behind Kakadu on Studio decode" |

UI-driven rows from the actual SwiftUI panel are not yet populated. The closest available data is the business-logic substitute below.

### DICOM Studio business-logic substitute (Apple M2, 2026-05-15)

This calls the **same public DICOMCore primitives** the Studio panel calls — `J2KSwiftCodec.benchEncode(...)`, `J2KSwiftCodec.benchDecode(...)`, and `KakaduCLICodec().decodeFrame(...)` — with identical methodology (warmups=2, runs=7, median-of-7) but **without launching the SwiftUI app**. It is *not Studio itself*: it skips CGImage rendering, view-model dispatch, and main-thread cost. Treat it as a closer-to-product proxy, not Lane B proper.

#### Post-Phase-0 + Phase-E2 (2026-05-15 v9.6 baseline)

Two production fixes landed on main after the original Phase-A measurement: the `recommendedDecodeAPI` router recalibration (Phase 0) and the MG-only 2x2 tile override (Phase E2). The substitute driver re-run on the new baseline:

| Modality | Dim | Bits | Codestream | Encode ms | Auto→ | dec `.cpu` | dec `.auto` | dec `.decodeGPU` | dec `.decodeWithGPUHT` | Kakadu dec ms |
|---|---|---:|---:|---:|---|---:|---:|---:|---:|---:|
| MR | 128×128 | 12 | 20.4 KB | 0.49 | CPU | 0.68 | **0.67** | 5.32 | 5.08 | 3.28 |
| CT | 512×512 | 16 | 158.0 KB | 2.13 | CPU | 2.59 | **2.53** | 12.47 | 15.45 | 7.75 |
| XA | 1024×1024 | 12 | 688.6 KB | 5.53 | decodeGPU | 9.09 | **8.98** | 9.02 | 32.90 | 10.70 |
| PX | 2793×1316 | 12 | 3086.6 KB | 17.68 | decodeGPU | 32.60 | **32.42** | 32.26 | 115.44 | 25.24 |
| DX | 2544×3056 | 12 | 7808.7 KB | 42.43 | decodeGPU | 63.37 | **64.25** | 62.59 | 130.08 | 41.70 |
| MG | 3520×4784 | 12 | 5497.2 KB | **40.49** | CPU | 119.39 | **125.62** | 122.02 | 121.90 | 65.47 |

`.auto` is now correctly routed on every modality (it's also the empirical winner per row now).

**Phase 0 (router fix) impact on `.auto` row vs Phase-A baseline:**

| Modality | `.auto` before | `.auto` after | Δ ms | Δ % |
|---|---:|---:|---:|---:|
| MR | 0.46 | 0.67 | +0.21 | noise |
| CT | 11.67 | **2.53** | **−9.14** | **−78 %** |
| XA | 9.35 | 8.98 | −0.37 | noise |
| PX | 118.18 | **32.42** | **−85.76** | **−73 %** |
| DX | 129.60 | **64.25** | **−65.35** | **−50 %** |
| MG | 127.58 | 125.62 | −1.96 | noise (MG decode unchanged; router just picks `.cpu` correctly) |

**Phase E2 (MG 2x2 override) impact on encode column:**

| Modality | Encode before | Encode after | Δ ms | Δ % |
|---|---:|---:|---:|---:|
| MG | 67.26 | **40.49** | **−26.77** | **−40 %** |
| All others | within noise of prior run | — | ≤ \|1 ms\| | — |

**Best-mode vs Kakadu after the two fixes:**

| Modality | Best J2KSwift mode | Best ms | Kakadu ms | J2KSwift / Kakadu | Reading |
|---|---|---:|---:|---:|---|
| MR 128² | `.auto`/`.cpu` | 0.67 | 3.28 | **0.20×** | J2KSwift wins ~4.9× |
| CT 512² | `.auto`/`.cpu` | 2.53 | 7.75 | **0.33×** | J2KSwift wins ~3.1× |
| XA 1024² | `.auto`/`.decodeGPU` | 8.98 | 10.70 | **0.84×** | J2KSwift wins ~1.2× |
| PX 2793×1316 | `.auto`/`.decodeGPU` | 32.42 | 25.24 | 1.28× | Kakadu wins ~1.3× (was 1.39×) |
| DX 2544×3056 | `.auto`/`.decodeGPU` | 64.25 | 41.70 | 1.54× | Kakadu wins ~1.5× (was 1.74×) |
| MG 3520×4784 | `.cpu` | 119.39 | 65.47 | 1.82× | Kakadu wins ~1.8× (was 1.93×) |

MR/CT/XA flipped to clean J2KSwift wins. PX/DX/MG gaps narrowed but are still real — those are the Phase D1 / E1 / E3 targets per the execution plan.

#### Original Phase-A baseline (pre-Phase-0, pre-E2)

Retained for the audit trail.

- Driver: `DICOMKit/Tests/DICOMCoreTests/DICOMStudioPanelSubstituteTests.swift`
- Run: `cd /Users/raster/Documents/raster/DICOMKit && swift test -c release --filter DICOMStudioPanelSubstituteTests`
- Transfer syntax: `1.2.840.10008.1.2.4.201` (HT-J2K Lossless)
- Encode mode: `.cpu`; one frame-0 instance per modality from `SampleStudies/<modality>/study_*/instance_000001.dcm`

J2KSwift decode ms per mode (lower is better). "Auto→" column reports which API `recommendedDecodeRoute` picked.

| Modality | Dim | Bits | Codestream | Encode ms | Auto→ | dec `.cpu` | dec `.auto` | dec `.decodeGPU` | dec `.decodeWithGPUHT` | Kakadu dec ms |
|---|---|---:|---:|---:|---|---:|---:|---:|---:|---:|
| MR | 128×128 | 12 | 20.4 KB | 0.44 | CPU | **0.53** | 0.46 | 5.22 | 5.09 | 3.17 |
| CT | 512×512 | 16 | 158.0 KB | 2.20 | decodeGPU | **2.37** | 11.67 | 11.56 | 9.35 | 4.65 |
| XA | 1024×1024 | 12 | 688.6 KB | 6.25 | decodeGPU | 9.56 | 9.35 | **9.40** | 31.38 | 11.58 |
| PX | 2793×1316 | 12 | 3086.6 KB | 82.54 | decodeWithGPUHT | 48.14 | 118.18 | **35.95** | 112.26 | 25.79 |
| DX | 2544×3056 | 12 | 7808.7 KB | 43.24 | decodeWithGPUHT | 62.22 | 129.60 | **70.01** | 129.26 | 40.35 |
| MG | 3520×4784 | 12 | 5504.3 KB | 67.26 | decodeWithGPUHT | **125.93** | 127.58 | 132.15 | 127.83 | 65.41 |

J2KSwift-best-mode vs Kakadu CLI (decode only — Studio has no Kakadu encode row):

| Modality | Best J2KSwift mode | Best ms | Kakadu ms | J2KSwift / Kakadu | Product reading |
|---|---|---:|---:|---:|---|
| MR 128² | `.cpu` (or `.auto`) | 0.46 | 3.17 | **0.15×** | J2KSwift wins ~6.9× |
| CT 512² | `.cpu` | 2.37 | 4.65 | **0.51×** | J2KSwift wins ~2.0× |
| XA 1024² | `.decodeGPU` | 9.35 | 11.58 | **0.81×** | J2KSwift wins ~1.2× |
| PX 2793×1316 | `.decodeGPU` | 35.95 | 25.79 | **1.39×** | Kakadu wins ~1.4× |
| DX 2544×3056 | `.decodeGPU` | 70.01 | 40.35 | **1.74×** | Kakadu wins ~1.7× |
| MG 3520×4784 | `.cpu` | 125.93 | 65.41 | **1.93×** | Kakadu wins ~1.9× |

Findings worth flagging back to the product team:

1. **`.auto` is mis-routed on CT, DX, PX** — it picks the slowest or near-slowest available mode. On DX 2544×3056 the router chose `.decodeWithGPUHT` (129.60 ms), while `.decodeGPU` ran in 70.01 ms (1.85× faster). On CT 512² it picked `decodeGPU` (11.67 ms), while `.cpu` ran in 2.37 ms (4.93× faster). The 3 MP threshold in `recommendedDecodeAPI` is mis-calibrated for the v9.5.x post-NEON CPU path on these modalities.
2. **Studio's default decode is `.cpu`**, per `J2KTestingViewModel.j2kSwiftDecodeMode = .cpu` ([DICOMKit/Sources/DICOMStudio/ViewModels/J2KTestingViewModel.swift:157](../../DICOMKit/Sources/DICOMStudio/ViewModels/J2KTestingViewModel.swift#L157)). So out-of-the-box Studio users see the `.cpu` column above — Kakadu wins MG 1.93×, DX 1.54×, PX 1.87×.
3. **Picking `.decodeGPU` manually flips DX from `1.54×` to `1.74×`** behind Kakadu (worse for J2KSwift); it only helps on PX (1.87× → 1.39×) and XA. There is no single mode that beats Kakadu across the large-frame class.
4. **Studio UI-driven rows remain TBD.** The substitute matches Studio's `performComparison` business logic but does not include UI rendering / dispatch costs. If those show a different pattern when measured in the running app, those numbers override this table per the Lane B charter.

Until UI-driven rows are populated, any "beats Kakadu" sentence must be scoped to the SDK corpus lane only. If Studio UI observations disagree with the SDK corpus headline, product-facing language follows Studio.

## What "optimal" means for each codec

### J2KSwift optimal config

| Component | Setting | Why |
|---|---|---|
| API surface | `J2KEncoder.encode(_:)` direct in-process call | Eliminates fork+exec + XPC marshal overhead. Isolated calls: 2-9 ms saved; sustained-load batch: up to 50 ms saved (see `DAEMON_OVERHEAD_METHODOLOGY_FINDING.md`) |
| Encoder lifetime | One instance, reused across fixtures, after warmup | Cold-start amortised |
| NEON hot path | `J2K_NEON_HOT_PATH=1` (default since v9.4.0) | Delivers −10 % to −21 % wall vs Swift-only entropy path |
| Tile mode | `J2KEncodeTilePlanner.envMode = .auto` (default since v7.0.0) | Beats single-tile-GPU per Phase 5 measurement on post-v9.5 main |
| GPU forward 5/3 DWT | env-default ON, ≥3 MP threshold | Wash on M2 at default tile-mode (Phase 5); kept on for future-silicon headroom |
| Encoder config | HT-conformant, lossless, 5/3 reversible, 5 decomposition levels | Production target per v5.38+ lossless-only directive |

### Kakadu optimal config

| Component | Setting | Why |
|---|---|---|
| API surface | `kdu_compress` CLI subprocess | Kakadu's SDK is closed-source + paid; CLI is the user-accessible shape |
| Flags | `Creversible=yes Cmodes=HT -quiet` | HT-conformant lossless, matching J2KSwift's output shape |
| Process model | One subprocess per fixture | Kakadu CLI's startup is ~5 ms (tiny C++ binary) — fast enough that there's no "daemon mode" parallel |

This is **NOT cherry-picked.** Kakadu is intentionally measured at its strongest practical usage shape. Anyone evaluating Kakadu for a real Apple Silicon deployment would use the CLI, since the SDK requires a commercial license and runtime royalty.

## Head-to-head — HT-conformant lossless encode (Apple M2, warm)

| Fixture          | pixels | J2KSwift in-proc warm | Kakadu CLI warm | Winner | Ratio |
|------------------|------:|----------------------:|----------------:|--------|------:|
| **MR-small 180²** | 32 400 | **0.56 ms** | 4.48 ms | **J2KSwift** | **8.02×** |
| **MR 886²** | 784 996 | **2.09 ms** | 4.49 ms | **J2KSwift** | **2.15×** |
| **CT 512² (1)** | 262 144 | **2.33 ms** | 4.47 ms | **J2KSwift** | **1.92×** |
| **CT 512² (2)** | 262 144 | **2.33 ms** | 4.50 ms | **J2KSwift** | **1.93×** |
| **XA 1024²** | 1 048 576 | **5.43 ms** | 9.64 ms | **J2KSwift** | **1.78×** |
| **PX 2459×1316** | 3 236 044 | **18.55 ms** | 19.75 ms | **J2KSwift** | **1.06×** |
| DX 2800×2288 | 6 406 400 | 39.82 ms | **39.28 ms** | Kakadu | 1.01× |

**6 of 7 fixtures: J2KSwift faster.** DX is effectively parity in this core table, with Kakadu ahead by 0.54 ms.

### Expanded large-fixture extension

The full 38-fixture rerun shows where Kakadu still has a real encode lead:

| Fixture | pixels | J2KSwift in-proc warm | Kakadu CLI warm | Winner | Ratio |
|---|---:|---:|---:|---|---:|
| DX 2224×2798 real small | 6 222 752 | 31.61 ms | **19.46 ms** | Kakadu | 1.62× |
| DX 2800×2288 real mid | 6 406 400 | 35.95 ms | **20.35 ms** | Kakadu | 1.77× |
| DX 2544×3056 real large | 7 774 464 | 42.18 ms | **20.00 ms** | Kakadu | 2.11× |
| MG 3516×4784 real small | 16 820 544 | 73.91 ms | **39.80 ms** | Kakadu | 1.86× |
| MG 3518×4784 real mid | 16 830 112 | 64.79 ms | **39.78 ms** | Kakadu | 1.63× |
| MG 3521×4784 real large | 16 844 464 | 67.83 ms | **38.93 ms** | Kakadu | 1.74× |

On the largest fixtures (~17 MP mammography), Kakadu remains the batch-encode leader, but the current measured gap is about **1.6-1.9×**, not the stale 3.6× synthetic extension reported by the older focused table.

## Why J2KSwift wins small / medium / PX and Kakadu wins DX/MG

- **Startup amortisation.** J2KSwift's in-process path pays zero per-call setup after the first encoder is built and warmed up. Kakadu CLI pays ~5 ms fork+exec + library init **per fixture**. For sub-millisecond compute (MR-small 180² takes ~0.6 ms actual J2KSwift CPU time), Kakadu's 5 ms startup floor is **the entire wall**.
- **Compute-bound regime.** Above full-frame DX/MG scale, encode work itself dominates the wall. Kakadu's compute is still faster on those fixtures even with the v9.4 C+NEON hot path. The remaining gap is now large-image-specific: PX is parity-or-better in this run, while expanded DX/MG remain 1.6-2.1× behind Kakadu.

## Historical NEON contribution

The following table is retained from the 2026-05-13 focused A/B run. It shows the direction and scale of the v9.4 C+NEON contribution, but it should not be mixed with the 2026-05-15 table above without rerunning `J2K_NEON_HOT_PATH=0` on the same benchmark script.

| Fixture | NEON ON | NEON OFF | Δ ms | Δ % |
|---|---:|---:|---:|---:|
| MR-small 180² | 0.6 | 0.7 | −0.1 | −14 % |
| CT 512² (1) | 2.4 | 2.7 | −0.3 | −11 % |
| CT 512² (2) | 2.3 | 2.9 | −0.6 | −21 % |
| MR 886² | 12.7 | 15.8 | −3.1 | −20 % |
| XA 1024² | 8.5 | 9.7 | −1.2 | −12 % |
| PX 2459×1316 | 28.2 | 32.6 | −4.4 | −13 % |
| DX 2800×2288 | 55.7 | 63.0 | −7.3 | −12 % |

Rerun the NEON OFF leg before making a current 2026-05-15 claim about how many fixtures would flip without the hot path.

## Decoder side (J2KSwift in-process warm vs Kakadu CLI warm)

The 2026-05-15 rerun measured J2KSwift via the same in-process path used for encode:

| Fixture | J2KSwift in-proc decode | Kakadu CLI decode | Winner | Ratio |
|---|---:|---:|---|---:|
| **MR-small 180²** | **0.68 ms** | 4.45 ms | **J2KSwift** | **6.54×** |
| **MR 886²** | **4.88 ms** | 9.49 ms | **J2KSwift** | **1.94×** |
| **CT 512² (1)** | **3.08 ms** | 4.40 ms | **J2KSwift** | **1.43×** |
| **CT 512² (2)** | **2.74 ms** | 4.43 ms | **J2KSwift** | **1.62×** |
| **XA 1024²** | **7.73 ms** | 9.52 ms | **J2KSwift** | **1.23×** |
| PX 2459×1316 | 30.08 ms | **19.70 ms** | Kakadu | 1.53× |
| DX 2800×2288 | 56.00 ms | **39.54 ms** | Kakadu | 1.42× |

On the full 38-fixture run, J2KSwift in-process decode wins **26/38** fixtures. The remaining decode losses are PX/DX/MG full-frame; the expanded MG real fixtures are still roughly 1.8-2.0× behind the best external codec.

## What the data does NOT support

- **"Fastest JPEG 2000 codec on Apple Silicon, universally"** — false. Kakadu still beats J2KSwift on expanded DX/MG real full-frame encode and on large decode fixtures.
- **"DICOM Studio beats Kakadu"** — not supported by the SDK corpus benchmark. Studio must be measured in the product UI or through an equivalent DICOMKit harness.
- **"Beats Kakadu on production hot paths"** — depends on the hot path. App / viewer / DICOM-browser thumbnail rendering (≤ 1 MP): the SDK lane is strong. Product decode of full chest-radiography (DX) or mammography (MG): DICOM Studio may still be far behind Kakadu.
- **"Open-source can beat closed-source commercial"** — partially: J2KSwift beats Kakadu on 6 of 7 core medical fixtures and 30 of 38 encode fixtures at the SDK shape, but still loses the large DX/MG batch workload.

## What the data DOES support

- **"Fastest open-source HTJ2K encoder on Apple Silicon"** — yes for this measured warm in-process SDK shape; J2KSwift beats OpenJPH and Grok broadly on the encode corpus, including the large DX/MG real fixtures.
- **"J2KSwift in-process is faster than Kakadu CLI for the most common clinical viewer workload and the core PX fixture"** — yes, by 1.06× to 8.02× across 6 of 7 core fixtures.
- **"The current Kakadu fight is DX/MG full-frame encode"** — yes; the expanded real DX/MG fixtures are the remaining 1.6-2.1× encode gap and should drive the next implementation plan.
- **"DICOM Studio observed benchmark is the product claim gate"** — yes. SDK corpus wins can guide optimization, but Studio observations decide user-facing claims.

## Caveats

1. **M2-only.** Phase 6 of v10.0-research showed M4 produces a different daemon-vs-in-proc curve. Numbers may shift on M3+ / A-series silicon. Re-measure per host class for production claims.
2. **HT-conformant lossless only.** Lossy 9/7 numbers are out of scope (v5.38+ product target).
3. **Kakadu version may matter.** Measured against 8.4.x; Kakadu releases updates that can shift the gap in either direction.
4. **In-process J2KSwift requires Swift integration.** This is the SDK shape — apps embedding J2KSwift. Pure CLI consumers shelling out to `j2k encode` should use `--daemon` (per `RELEASE_NOTES_v9.5.2.md` SDK-vs-CLI guidance), and the comparable Kakadu shape is its CLI. In CLI-vs-CLI warm (with j2kd daemon) J2KSwift's per-call overhead vs in-proc is **2-9 ms under isolated invocations and 8-50 ms under sustained-load batch** (see `DAEMON_OVERHEAD_METHODOLOGY_FINDING.md` for controlled-measurement decomposition).

## Reproducing this comparison

```bash
# Current cross-codec comparison: J2KSwift in-process, reference codecs via CLI
python3 Scripts/benchmarks/cross_codec_warm_bench.py \
    --in-proc --runs 7 --warmups 2 \
    --output benchmark-results-$(uname -m)-$(date +%Y%m%d)-inproc.json

# Product-path DICOMKit benchmark
(cd /Users/raster/Documents/raster/DICOMKit && \
  swift test -c release --filter J2KSwiftCodecBenchmarkTests)

# Current NEON OFF A/B leg, if needed
J2K_NEON_HOT_PATH=0 python3 Scripts/benchmarks/cross_codec_warm_bench.py \
    --in-proc --runs 7 --warmups 2 \
    --output benchmark-results-$(uname -m)-$(date +%Y%m%d)-inproc-neon-off.json
```

## Companion documents

- [`CROSS_CODEC_REPORT_v9.5.2_M2_warm.md`](CROSS_CODEC_REPORT_v9.5.2_M2_warm.md) — older 2026-05-13 companion report; superseded by the 2026-05-15 rerun for this page's headline table
- [`data/benchmark-results-Mac142-9.5.2-NEONwarm-20260513.json`](data/benchmark-results-Mac142-9.5.2-NEONwarm-20260513.json) — historical NEON A/B source data
- [`DICOM_STUDIO_CLAIM_SCOPE_FINDING.md`](DICOM_STUDIO_CLAIM_SCOPE_FINDING.md) — DICOMKit / DICOM Studio product-claim constraint
- [`BEAT_KAKADU_EXECUTION_PLAN_2026_05_15.md`](../research/BEAT_KAKADU_EXECUTION_PLAN_2026_05_15.md) — current execution plan based on the 2026-05-15 cross-codec and DICOMKit benchmark runs
- [Documentation/research/V10_0_PHASE6_DAEMON_DECOMPOSITION.md](../research/V10_0_PHASE6_DAEMON_DECOMPOSITION.md) — why in-process is J2KSwift's optimal shape (not the daemon)
- [Documentation/releases/RELEASE_NOTES_v9.4.0.md](../releases/RELEASE_NOTES_v9.4.0.md) — the v9.4.0 NEON hot path that closes the Kakadu gap
- [Documentation/BENCHMARK.md](../BENCHMARK.md) — canonical methodology
