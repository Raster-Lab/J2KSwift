# Beat Kakadu execution plan - current evidence

**Date:** 2026-05-15  
**Host measured today:** Apple M2, Darwin 24.6.0  
**J2KSwift:** 9.5.2  
**Primary arena:** two lanes must be tracked separately:

1. **SDK corpus benchmark** — warmed in-process J2KSwift core vs external codec CLIs on the repository corpus.
2. **DICOM Studio observed benchmark** — the actual product comparison panel on loaded DICOM files. This is the product claim gate.

## Evidence from today's runs

### Lane A - SDK corpus benchmark

Command:

```bash
python3 Scripts/benchmarks/cross_codec_warm_bench.py \
  --in-proc --runs 7 --warmups 2 \
  --output /tmp/j2kswift-cross-codec-inproc-20260515-055923.json
```

Result:

| Direction | J2KSwift+inproc wins | Losses | Meaning |
|---|---:|---:|---|
| PGM encode | 30/38 | 8/38 | Small/medium medical workloads are already strong; the remaining fight is large DX/MG. |
| PGM decode | 26/38 | 12/38 | Decode is good below PX/DX scale but still loses large radiography/mammography. |
| DICOM encode | 13 fixtures measured | no external comparator | Useful for SDK wall-time shape, not for cross-codec claims. |

The encode losses are concentrated:

| Fixture class | J2KSwift+inproc | Best external | Gap |
|---|---:|---:|---:|
| DX 2800x2288, legacy real corpus | 39.82 ms | Kakadu 39.28 ms | 1.01x |
| DX real small/mid/large | 31.61-42.18 ms | Kakadu 19.46-20.35 ms | 1.62-2.11x |
| MG real small/mid/large | 64.79-73.91 ms | Kakadu 38.93-39.80 ms | 1.63-1.86x |

PX is no longer the main problem. J2KSwift wins or near-wins PX encode in this run:

| PX fixture | J2KSwift+inproc | Kakadu | Result |
|---|---:|---:|---|
| PX 2459x1316 | 18.55 ms | 19.75 ms | J2KSwift wins by 1.06x |
| PX 2793x1316 real mid | 16.66 ms | 19.61 ms | J2KSwift wins by 1.18x |
| PX 2812x1316 real large | 16.33 ms | 19.77 ms | J2KSwift wins by 1.21x |

### Lane B - DICOM Studio observed benchmark

DICOM Studio is the product-truth lane. It does not run the same comparison as the SDK corpus script. The Studio panel:

- extracts frame 0 from the loaded DICOM file,
- encodes that frame with J2KSwift,
- decodes that J2KSwift codestream with the selected J2KSwift decode path,
- decodes the same codestream with Kakadu CLI (`kdu_expand`) when installed,
- reports median of 7 after 2 warmups when Warm-up is enabled.

This means DICOM Studio can legitimately show J2KSwift far behind Kakadu even when the SDK corpus table says J2KSwift wins many encode fixtures. The most likely product-path losses are large PX/DX/MG decode, Auto-vs-CPU routing differences, Debug builds, and real DICOMs that do not match the normalized PGM corpus distribution.

Record Studio observations here as they are collected:

| Loaded DICOM | Modality/size | Build | Warm-up | J2KSwift encode mode | J2KSwift decode mode | J2KSwift encode | J2KSwift decode | Kakadu decode | Ratio | Product interpretation |
|---|---|---|---|---|---|---:|---:|---:|---:|---|
| TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | Populate from DICOM Studio comparison panel |

#### Business-logic substitute (2026-05-15 v9.6 — post Phase 0 + E2)

After the two evening fixes landed (router recalibration + MG 2x2 override), the substitute corpus shows:

| Modality | Dim | Encode ms | Auto→ | dec `.auto` ms | Kakadu dec | J2K/Kak | Notes |
|---|---|---:|---|---:|---:|---:|---|
| MR | 128×128 | 0.49 | CPU | 0.67 | 3.28 | **0.20×** | J2KSwift wins ~4.9× |
| CT | 512×512 | 2.13 | CPU | 2.53 | 7.75 | **0.33×** | J2KSwift wins ~3.1× (was 2.51× behind on `.auto`) |
| XA | 1024×1024 | 5.53 | decodeGPU | 8.98 | 10.70 | **0.84×** | J2KSwift wins ~1.2× |
| PX | 2793×1316 | 17.68 | decodeGPU | 32.42 | 25.24 | 1.28× | Kakadu wins ~1.3× (was 4.58× behind on `.auto`) |
| DX | 2544×3056 | 42.43 | decodeGPU | 64.25 | 41.70 | 1.54× | Kakadu wins ~1.5× (was 3.21× behind on `.auto`) |
| MG | 3520×4784 | **40.49** | CPU | 125.62 | 65.47 | 1.92× | Kakadu wins ~1.9× (encode dropped from 67.26 ms via E2) |

Combined impact:
- Phase 0 router fix flips `.auto` from `.decodeWithGPUHT` → empirically best mode on CT/PX/DX/MG (4 of 6 modalities).
- Phase E2 MG override drops MG encode from 67.26 ms → 40.49 ms (−40 %).
- 3 modalities (MR / CT / XA) now flip to clean J2KSwift wins; PX/DX/MG gaps narrow to 1.3–1.9× from 1.4–1.9×.

#### Original Phase-A baseline (pre-Phase-0, pre-E2)

Retained for the audit trail.

Driven by `DICOMKit/Tests/DICOMCoreTests/DICOMStudioPanelSubstituteTests.swift`, which calls the public DICOMCore primitives the Studio panel uses (`J2KSwiftCodec.benchEncode/.benchDecode` + `KakaduCLICodec.decodeFrame`) without launching the SwiftUI app. Same warmups=2 / runs=7 / median-of-7 shape as Studio's Warm-up=on path. **Not Studio itself** — skips CGImage rendering and main-thread dispatch.

| Modality | Dim | Codestream | Encode ms | Auto→ | dec `.cpu` ms | dec `.auto` ms | dec `.decodeGPU` ms | dec `.decodeWithGPUHT` ms | Kakadu dec ms | Best mode / ratio |
|---|---|---:|---:|---|---:|---:|---:|---:|---:|---|
| MR | 128×128 | 20.4 KB | 0.44 | CPU | 0.53 | 0.46 | 5.22 | 5.09 | 3.17 | `.auto`/`.cpu` 0.15× (J2KSwift wins ~6.9×) |
| CT | 512×512 | 158.0 KB | 2.20 | decodeGPU | 2.37 | 11.67 | 11.56 | 9.35 | 4.65 | `.cpu` 0.51× (J2KSwift wins ~2.0×) |
| XA | 1024×1024 | 688.6 KB | 6.25 | decodeGPU | 9.56 | 9.35 | 9.40 | 31.38 | 11.58 | `.decodeGPU` 0.81× (J2KSwift wins ~1.2×) |
| PX | 2793×1316 | 3086.6 KB | 82.54 | decodeWithGPUHT | 48.14 | 118.18 | 35.95 | 112.26 | 25.79 | `.decodeGPU` 1.39× (Kakadu wins ~1.4×) |
| DX | 2544×3056 | 7808.7 KB | 43.24 | decodeWithGPUHT | 62.22 | 129.60 | 70.01 | 129.26 | 40.35 | `.decodeGPU` 1.74× (Kakadu wins ~1.7×) |
| MG | 3520×4784 | 5504.3 KB | 67.26 | decodeWithGPUHT | 125.93 | 127.58 | 132.15 | 127.83 | 65.41 | `.cpu` 1.93× (Kakadu wins ~1.9×) |

Findings:

- **`recommendedDecodeAPI` is miscalibrated for CT/DX/PX on M2 + v9.5.2.** On CT 512² it picks `decodeGPU` (11.67 ms) when `.cpu` (2.37 ms) is 4.9× faster. On DX 2544×3056 it picks `decodeWithGPUHT` (129.60 ms) when `.decodeGPU` (70.01 ms) is 1.85× faster. On PX 2793×1316 it picks `decodeWithGPUHT` (118.18 ms) when `.decodeGPU` (35.95 ms) is 3.29× faster. Re-running the threshold sweep is a single-day fix and would change the user-observed `.auto` story on three of six modalities.
- **Studio's default `.cpu` row beats Kakadu on MR (0.15×), CT (0.51×), XA's CPU run is near-parity** — small/medium product-path is already winning. The Kakadu fight is concentrated where the SDK lane already pointed: PX/DX/MG full-frame decode.
- **No single decode mode beats Kakadu across PX/DX/MG.** Best-per-modality is `.decodeGPU` for PX/DX and `.cpu` for MG. A real consumer-body rewrite (Phase 5) is still the structural lever.
- The encode column is J2KSwift-only — the Studio panel does not expose a Kakadu encode row, so this lane cannot judge the encode arc.

### DICOMKit benchmark test

Command:

```bash
cd /Users/raster/Documents/raster/DICOMKit
swift test -c release --filter J2KSwiftCodecBenchmarkTests
```

Result on `instance_003317.dcm`:

| Test | Result |
|---|---|
| J2KSwift real-file decode | 12.580 ms |
| ImageIO comparison | unavailable; ImageIO failed to decode the JPEG 2000 image |
| Legacy J2K decode | 11.622 ms |
| HTJ2K decode | 12.186 ms |
| HTJ2K vs legacy | 0.954x, so HTJ2K is slightly slower on this sample |
| Memory benchmark encode | 23.910 ms |
| Memory benchmark decode | 12.214 ms |
| RSS delta | 2.219 MB |

DICOMKit benchmark tests prove two things:

1. The production path is not the CLI path. DICOM Studio calls J2KSwift in-process through `J2KSwiftCodec`, and the app prewarms the codec.
2. The product claim must remain scoped. DICOM Studio's comparison panel encodes with J2KSwift, then decodes that codestream with J2KSwift, OpenJPEG, Kakadu CLI, and Grok CLI. Kakadu/Grok are decode-only subprocess adapters in that panel, so those rows include temp-file and process cost and do not constitute a Kakadu encode comparison.

## Current target

The useful goal is no longer "beat Kakadu everywhere." That claim is false and too broad. The engineering target should be:

> Preserve SDK corpus encode wins, then beat the Kakadu row in DICOM Studio on the actual loaded DICOM files that users care about.

Concretely:

| Gate | Current | Target for next arc |
|---|---:|---:|
| SDK corpus encode wins | 30/38 | keep >= 30/38, stretch >= 33/38 |
| SDK corpus decode wins | 26/38 | keep >= 26/38 |
| DICOM Studio observed decode | TBD; user observation says J2KSwift can be far behind Kakadu | collect release-build rows, then target <= 1.10x Kakadu on priority studies |
| DICOM Studio observed encode | J2KSwift-only column; no Kakadu encode row in Studio | use as product latency gate, not as Kakadu encode comparison |
| DX real mid SDK encode | 35.95 ms vs Kakadu 20.35 ms | first <= 28 ms, final <= 20 ms |
| MG real mid SDK encode | 64.79 ms vs Kakadu 39.78 ms | first <= 55 ms, final <= 39 ms |
| DICOMKit sample decode | 12.580 ms | no regression above +10%; stretch <= 10 ms |
| DICOMKit sample encode | 23.910 ms | first <= 20 ms |

## Why the old plan needs narrowing

The previous "beat Kakadu" plan treated entropy as the universal answer. Today's evidence says the problem is sharper:

- Small/medium encode is already winning.
- PX encode is now at parity or ahead.
- DX/MG encode remains 1.6-2.1x behind, not 4-5x behind.
- DICOMKit decode on the real MR sample is already about 12 ms; the weaker decode story is mostly PX/DX/MG full-frame scale.
- Prior research found that small decoder tweaks wash out; large decode needs a real consumer-body rewrite, not another wrapper optimization.

That means the next plan should focus on memory movement and block-pipeline fusion before another broad entropy rewrite.

## Phase 0 - lock the product benchmark

Add a DICOM Studio-facing benchmark record to the J2KSwift benchmark policy:

- Always run `cross_codec_warm_bench.py --in-proc --runs 7 --warmups 2`.
- Always run DICOMKit `swift test -c release --filter J2KSwiftCodecBenchmarkTests`.
- Always collect at least one DICOM Studio comparison row from the actual study class being optimized.
- Record build configuration, warm-up toggle, encode mode, decode mode, J2KSwift encode ms, J2KSwift decode ms, Kakadu decode ms, and ratio.
- Treat DICOM Studio comparison rows as product evidence, not universal codec evidence.

Exit gate: benchmark docs show both the SDK corpus scorecard and the DICOM Studio observed scorecard.

## Phase 1 - remove the remaining encode pipeline copies

Primary file: `Sources/J2KCodec/J2KEncoderPipeline.swift`.

Current hot path still copies each block into a new Swift array:

- `Array(coeffsBuffer[0..<blockSize])` when building `PendingCodeBlock`.
- A second scan over `pending.coefficients` for `maxAbs`.
- A second pass converting Int32 coefficients into sign-magnitude UInt32 for the C+NEON encoder.

Plan:

1. Introduce a pointer-backed pending block or direct block-encode call that carries `UnsafeBufferPointer<Int32>` plus metadata.
2. Fuse `maxAbs` and sign-magnitude conversion into one pointer pass.
3. Keep the existing array path as a debug/parity fallback behind an env var.
4. Add byte-exact tests comparing pointer-backed and array-backed block output.

Expected impact: 5-10 ms on large DX/MG if block copy and second scan are still visible under Instruments. This is the cleanest route to the first DX target of <= 28 ms.

## Phase 2 - finish C hot-path fusion

Primary files:

- `Sources/J2KCodec/J2KHTConformantBlockEncoder.swift`
- `Sources/J2KCodecNEON/j2knhe_encode_block_ht.c`
- `Sources/J2KCodec/J2KEncoderPipeline.swift`

The v9.4/v9.5 path already routes conformant HT block encode into C+NEON and has caller-owned buffer entry points. The next step is to stop treating sign-magnitude preparation, block classification, encode, and block assembly as separate Swift-facing stages.

Plan:

1. Add a C entry point that accepts Int32 coefficients directly and writes the three HT streams to caller-owned buffers.
2. Compute `maxAbs`, zero-block status, sign-magnitude, and HT encode inside the same C routine.
3. Return lengths and zero-bit-plane metadata to Swift.
4. Keep `HTBlockLayoutConformant.assembleDataFromRaw` initially; only replace it after measuring whether block assembly is material.

Expected impact: 10-20% on large encode if Swift/C boundary and buffer traffic are still material. This should move DX real mid from ~36 ms toward the high 20s.

## Phase 3 - tune DX/MG tiling and scheduling

Primary file: `Sources/J2KCodec/J2KEncodeTilePlanner.swift` and the call sites in `J2KEncoderPipeline`.

Today's run says PX is good, while DX/MG are still behind. That pattern suggests the planner and worker scheduling may be leaving large, tall, high-bit-depth images under-balanced or memory-bound.

Plan:

1. Run single-tile, auto, 2x2, 4x4, and strip tiling on DX/MG only.
2. Profile block-count balance, worker occupancy, coefficient-copy bandwidth, and codestream assembly.
3. Pick a large-medical preset for DX/MG if one shape consistently wins.
4. Keep the current small/medium defaults unchanged.

Expected impact: fixture-dependent; likely 2-8 ms on DX/MG if current auto mode is not optimal.

## Phase 4 - only then port more DWT to C+NEON

DWT is not the first move because the current measured gap is mostly concentrated after the encoder has already won small/medium and PX. But if Phases 1-3 plateau above Kakadu, DWT becomes the next real compute lever.

Plan:

1. Re-run the current stage profile after Phase 3.
2. If DWT is still >= 20% of DX/MG wall, port the forward 5/3 large-image path to C+NEON.
3. Keep reversible/lossless parity tests first; lossy 9/7 should not gate the DICOMKit lossless target.

Expected impact: 4-8 ms on DX/MG, depending on current DWT share.

## Phase 5 - decode only if product demand needs full-frame DX/MG

Decode is not the first route to a Kakadu headline. DICOMKit's real MR sample decodes in about 12 ms, and prior decoder research found the remaining small levers wash out. The full-frame DX/MG decode gap is real, but it needs a larger rewrite:

1. Rewrite the HT entropy consumer body to batch bitstream reads and reduce per-symbol Swift overhead.
2. Preserve the current CPU path as the default until byte-exact cross-codec parity passes.
3. Measure only against PX/DX/MG; do not let large-frame decode work regress the already-winning small/medium fixtures.

Exit gate: PX/DX decode within 10% of Kakadu or Grok; MG decode <= 1.3x best external.

## Recommended next command sequence

```bash
# 1. Current baseline, already run today
python3 Scripts/benchmarks/cross_codec_warm_bench.py --in-proc --runs 7 --warmups 2

# 2. Product-path baseline, already run today
(cd /Users/raster/Documents/raster/DICOMKit && \
  swift test -c release --filter J2KSwiftCodecBenchmarkTests)

# 3. Before editing the hot path, collect a focused profile on DX/MG encode
swift test -c release --filter J2KMedicalCorpusEncodePerformanceTests
```

## Decision

Start with Phase 1, not another broad algorithm rewrite. The data says Kakadu is beatable in the SDK/product arena if we remove the last Swift array/pointer churn in the large-block encode path. If Phase 1 cannot move DX real mid by at least 5 ms, stop and profile before touching entropy again.
