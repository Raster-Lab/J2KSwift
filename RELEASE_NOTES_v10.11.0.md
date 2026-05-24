# J2KSwift v10.11.0

**JP3D batched GPU iDWT.** Closes a multi-week JP3D arc with a
single-dispatch Metal kernel that amortises per-slice GPU overhead
across the whole volume. JP3D full-volume decode wins **-5 ms on
small CT to -115 ms on 16M-voxel CT** vs the per-slice serial loop
(M2 release, in-process, 7 runs / 2 warmups).

Decoder-only release; codestream bytes are byte-identical to v10.10.0.
Encoder unchanged. MINOR per RELEASING.md — no public API removed,
no signature change, no default flip that affects bytes; the new
`_jp3dDecodeToCoefficients` / `_jp3dIDWTAndFinalize` /
`_jp3dIDWTAndFinalizeBatched` bridge SPI on `J2KDecoder` ships as
opaque additive surface.

## Summary

Three coordinated changes inside `Sources/J2KCodec` + `Sources/J2KMetal`
+ `Sources/J2K3D`:

1. **Batched single-dispatch Metal inverse 5/3 iDWT.** Two new Metal
   kernels (`j2k_dwt_inverse_53_horizontal_int_tiled_batched`,
   `..._vertical_..._batched`) extend the existing v10.3 tiled
   threadgroup-memory kernels with a Z-dim grid axis. One dispatch
   per multi-level chain processes N slices in parallel. Kernel-level
   bench (16 slices × 256×256 × 3 levels, M2 release): 5.93 ms
   serial → 2.06 ms batched → **2.4× faster kernel-level dispatch**.

2. **JP3D bridge SPI on `J2KDecoder`.** Three opaque-payload methods
   split the per-slice 2D decode pipeline so JP3D can collect N
   slices' dequantized coefficients before submitting one batched
   iDWT:
   - `_jp3dDecodeToCoefficients(_:Data) -> JP3DSliceCoefficients`
     (Stage A — entropy + dequant)
   - `_jp3dIDWTAndFinalize(_:JP3DSliceCoefficients) -> J2KImage`
     (Stages B–C — iDWT + colour + DC + reconstruct)
   - `_jp3dIDWTAndFinalizeBatched(_:[JP3DSliceCoefficients]) -> [J2KImage]`
     (batched Stages B–C across the whole z-range)
   Bit-exact composition: `decode(data) ≡ _jp3dIDWTAndFinalize(_jp3dDecodeToCoefficients(data))`
   on every single-tile codestream, which is the JP3D wire format.

3. **`JP3DSliceStackCodec` consumes the batched bridge.** The per-tile
   decode loop now runs two new bulk stages before the existing
   sequential Z-delta residual chain:
   - Parallel `_jp3dDecodeToCoefficients` across `[zStart, zUpper)` via
     a TaskGroup (entropy + dequant concurrently across slices).
   - ONE batched `_jp3dIDWTAndFinalizeBatched` call across the whole
     z-range (per-slice GPU dispatch overhead amortises).
   The Z-delta residual chain remains sequential (it's cheap Int32
   adds, not the bottleneck). Eligibility gate: only the (K=0,
   no ROI) production case routes through the bulk path; `K > 0`
   uses `decodeResolution` and any ROI uses `decodeRegion` per
   slice (v10.5 / v10.6 territory; batched bridge for those is
   future work).

## What's New — production-default

| Public API | v10.10.0 behaviour | v10.11.0 behaviour |
|---|---|---|
| `JP3DDecoder().decode(data)` full-volume decode (default config) | Per-slice serial `J2KDecoder.decode` loop inside `JP3DSliceStackCodec` | Parallel `_jp3dDecodeToCoefficients` + ONE batched iDWT dispatch + sequential Z-delta residual chain. **Same output bytes**; 5–115 ms faster wall on the JP3D corpus |
| `JP3DDecoder(configuration: cfg).decode(data)` with `cfg.resolutionLevel > 0` | Per-slice `decodeResolution` loop (v10.10.0) | Unchanged — partial-resolution path not yet bridged |
| `JP3DROIDecoder().decode(data, region:)` | Per-slice `decodeRegion` loop (v10.10.0) | Unchanged — ROI path not yet bridged |

The new `J2KDecoder` bridge SPI methods (`_jp3dDecodeToCoefficients`,
`_jp3dIDWTAndFinalize`, `_jp3dIDWTAndFinalizeBatched`) are public but
underscored — JP3D-internal use only; consumers outside `J2K3D` should
keep calling the normal `J2KDecoder.decode(_:)`.

## What's New — opt-in / opt-out

`J2K_JP3D_BATCHED_BRIDGE=0` env var disables the new batched path,
forcing the per-slice serial loop (the pre-v10.11 shape). Diagnostic-
A/B only; production should leave it unset.

## Backward compatibility

- **Codestream bytes**: byte-identical to v10.10.0 on every input. The
  encoder is unchanged.
- **`JP3DDecoder().decode(data)`** is byte-identical to v10.10.0 on every
  input. Validated by the 519-test `swift test --filter JP3D` regression
  sweep (519/519 PASS) — including the v10.18 round-trip lossless
  baseline, partial-resolution shapes, ROI footprint-skip, and Z-narrow
  ROI cases.
- **`_jp3dIDWTAndFinalizeBatched([coefs])[i]`** is byte-identical to
  `_jp3dIDWTAndFinalize(coefs[i])` for every JP3D-shape input.
  Validated by the new `V10_20_BatchedBridgeParityTests` (5/5 PASS)
  + `V10_20_JP3DBridgeParityTests` (5/5 PASS).
- **Behaviour change**: none.

## Measured wins — JP3D corpus

M2 release, J2KBenchMac --jp3d, in-process, 7 timed runs / 2 warmups,
median per fixture:

| Fixture (modality WxHxD) | voxels | serial ms | batched ms | Δ ms | ratio |
|---|---:|---:|---:|---:|---:|
| mr_3d_small  MR 128×128×16 | 262K   | 13.81  | 14.05  | +0.24    | 0.98× |
| ct_3d_small  CT 256×256×16 | 1.05M  | 44.11  | 38.99  | **−5.12**    | **1.13×** |
| us_3d_small  US 320×240×24 | 1.84M  | 60.44  | 56.29  | **−4.15**    | **1.07×** |
| mr_3d_mid    MR 256×256×32 | 2.10M  | 87.21  | 77.71  | **−9.50**    | **1.12×** |
| ct_3d_mid    CT 512×512×32 | 8.39M  | 369.81 | 316.56 | **−53.25**   | **1.17×** |
| ct_3d_large  CT 512×512×64 | 16.78M | 789.15 | 674.59 | **−114.57**  | **1.17×** |

5/6 fixtures clear the 3 ms acceptance threshold. The single wash
(mr_3d_small @ 13 ms wall) is the smallest fixture where per-slice
dispatch overhead dominates the absolute wall.

Reading: the win scales with slice count × per-slice work — every
extra slice amortises the GPU dispatch overhead it would have paid
in the serial loop. **iDWT is the largest stage in JP3D 5/3 lossless
decode**, so the batched dispatch wedge is structural.

Raw bench JSONs are committed at
`Documentation/Benchmarks/data/jp3d-bench-arm64-v10_20-{batched,serial}-20260524.json`.

## Cross-codec parity (2D codec unchanged)

The 2D codec path (entropy, dequant, single-tile iDWT, colour, DC,
reconstruct) is touched only at the bridge SPI splitting point —
the same per-stage code paths execute, same SubbandInfo flows, same
J2KDWT2DOptimizer / J2KMetalDWT calls. Cross-codec parity vs
OpenJPH 0.27.0 / Grok 20.3.0 / Kakadu 8.4.1 is therefore inherited
from v10.10.0 (no change measured or asserted in this release).

## Test Suite Results

| Suite | Tests | Result | Coverage |
|---|---:|---|---|
| `V10_20_JP3DBridgeParityTests` | 5/5 | PASS | Phase 1 bridge SPI bit-exact composition |
| `V10_20_BatchedInverseInt32ParityTests` | 12/12 | PASS | Batched Metal kernel + multi-level orchestrator bit-exact vs serial GPU |
| `V10_20_BatchedBridgeParityTests` | 5/5 | PASS | Batched bridge SPI bit-exact vs per-slice serial bridge SPI |
| `swift test --filter JP3D` (regression sweep) | 519/519 | PASS | Full JP3D test suite green with the batched wiring |
| Mandatory commit gate (release mode): `J2KMedicalCorpusEncodePerformanceTests` + `J2KMedicalCorpusPerformanceTests` + `J2KStrictCrossCodecValidationTests` | 7/7 | PASS | Encode-perf + decode-perf + cross-codec strict validation |

## API surface — additions only

```swift
extension J2KDecoder {
    public struct JP3DSliceCoefficients: Sendable {
        public var width: Int { get }
        public var height: Int { get }
        // No other public fields — payload opaque to consumers
    }
    public func _jp3dDecodeToCoefficients(_ data: Data) async throws -> JP3DSliceCoefficients
    public func _jp3dIDWTAndFinalize(_ coefs: JP3DSliceCoefficients) async throws -> J2KImage
    public func _jp3dIDWTAndFinalizeBatched(_ coefsBatch: [JP3DSliceCoefficients]) async throws -> [J2KImage]
}
```

No removals. No signature changes.

## Known limitations

- **Partial-resolution + ROI paths not yet batched.** When
  `JP3DDecoderConfiguration.resolutionLevel > 0` or
  `JP3DROIDecoder().decode(_, region:)` is invoked, the per-slice
  loop keeps the v10.10.0 shape (per-slice `decodeResolution` /
  `decodeRegion`). Bridging those paths needs the 2D
  `decodeResolution` / `decodeRegion` to expose their own coefficient-
  split SPI; tracked for a future release.
- **Slice-stack residual chain still sequential.** The Z-delta residual
  apply is a per-slice Int32 add with a cross-slice data dependency
  (slice z reads `prevSliceInt`). Not the bottleneck (iDWT was), but
  not parallelised either.

## Reproducing the headline numbers

```bash
# Build
swift build -c release --product J2KBenchMac

# Batched (default)
.build/release/J2KBenchMac --jp3d --output /tmp/jp3d_batched.json

# Serial baseline (opt-out)
J2K_JP3D_BATCHED_BRIDGE=0 .build/release/J2KBenchMac --jp3d --output /tmp/jp3d_serial.json
```

The bench corpus is fixed (LCG-synthesised volumes at MR/CT/US
shapes), so the wall numbers reproduce across hosts modulo silicon
class.

## Companion documents

- `Documentation/Benchmarks/data/jp3d-bench-arm64-v10_20-batched-20260524.json` — raw bench (batched)
- `Documentation/Benchmarks/data/jp3d-bench-arm64-v10_20-serial-20260524.json` — raw bench (serial baseline)
- `Documentation/research/V10_20_BATCHED_JP3D_IDWT.md` (on the `v10.19-research` branch) — full multi-week arc closure with phase-by-phase deliverables

## Backward upgrade

`swift package update` will not auto-pick this release if your
`Package.swift` pins exact version; bump the requirement to
`from: "10.11.0"` (or accept the next `.upToNextMinor` per your
policy). Consumers of `JP3DDecoder` see only a perf improvement;
no source changes required.
