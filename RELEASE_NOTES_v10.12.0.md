# J2KSwift v10.12.0

**JP3D batched bridge extension — partial-resolution + ROI.** Closes
the v10.11.0 known limitation: the batched bridge SPI now handles
the `JP3DDecoderConfiguration.resolutionLevel > 0` and
`JP3DROIDecoder(_:region:)` cases inside `JP3DSliceStackCodec` via a
new `JP3DBridgeOptions` overload. Same single-dispatch architecture
as v10.11.0; the orchestrator truncates the chain for partial-res
and crops after iDWT for ROI. M2 release JP3D decode wins
**−10 ms to −83 ms** on production-relevant CT volumes across all
three lanes (full / partial-res-1 / ROI 1/4).

Decoder-only release; codestream bytes are byte-identical to v10.11.0.
Encoder unchanged. MINOR per RELEASING.md — additive public surface
(`JP3DBridgeOptions` + new `_jp3dDecodeToCoefficients(_:options:)`
overload), no signature removal, no default flip that affects bytes.

## Summary

Three coordinated changes that extend v10.11.0's batched bridge SPI
to the two cases it previously dropped to per-slice serial:

1. **`JP3DBridgeOptions` struct + new bridge SPI overload.**
   `JP3DBridgeOptions(partialResolutionLevel:, regionOfInterest:)`
   carries the partial-resolution K and/or ROI rectangle. The new
   `J2KDecoder._jp3dDecodeToCoefficients(_:options:)` overload
   forwards them to the underlying `DecoderPipeline`, where the
   entropy-stage Stage B.1 (partial-res) / Stage 1 (ROI footprint-
   skip) wins fire just like in the standalone
   `decodeResolution` / `decodeRegion`. The options ride along
   inside the returned bundle so the matching finalize call sizes /
   crops the output without re-plumbing.

2. **Batched orchestrator handles uniform-options batches.** The
   eligibility gate now accepts partial-res K and ROI when all
   slices in the batch carry the same options (JP3D slice-stack
   always does — these are per-volume not per-slice). For partial-
   res the orchestrator truncates the chain to `effectiveLevels =
   N − K` levels (output dims = `levelSizes[K]`); for ROI the chain
   runs full and `cropImage` slices the per-slice output to the
   region rectangle. K=0 (thumbnail) falls back to per-slice serial
   because the orchestrator can't dispatch an empty iDWT chain.

3. **`JP3DSliceStackCodec` consumes both new cases.** The K>0
   (partial-resolution) and ROI branches now build a
   `JP3DBridgeOptions` and route through the bulk parallel
   `_jp3dDecodeToCoefficients` + ONE batched iDWT, instead of
   per-slice `decoder.decodeResolution` / `decodeRegion`. The
   only combination still routed per-slice is `K > 0 AND ROI` —
   the 2D codec doesn't compose partial-res with ROI; the
   pre-existing throw still fires for that case.

## What's New — production-default

| Public API | v10.11.0 behaviour | v10.12.0 behaviour |
|---|---|---|
| `JP3DDecoder(configuration: cfg).decode(data)` with `cfg.resolutionLevel > 0` | Per-slice serial `decodeResolution` loop | Parallel `_jp3dDecodeToCoefficients(options:)` + ONE batched iDWT (truncated chain). **Same output bytes**; 10–26 ms faster wall on the JP3D corpus' larger CT volumes |
| `JP3DROIDecoder().decode(data, region:)` | Per-slice serial `decodeRegion` loop | Parallel `_jp3dDecodeToCoefficients(options:)` + ONE batched iDWT + per-slice ROI crop. **Same output bytes**; 4–48 ms faster wall on the JP3D corpus |
| `JP3DDecoder().decode(data)` full-volume decode | v10.11.0 batched bridge (unchanged) | Unchanged |

The new bridge SPI surface (`JP3DBridgeOptions` + the options
overload) is public but `JP3DBridgeOptions` ships in J2KCodec
alongside the existing underscored `_jp3d*` methods. Consumers
outside `J2K3D` should keep calling the normal
`J2KDecoder.decode(_:)` / `decodeResolution(_:options:)` /
`decodeRegion(_:options:)`.

## What's New — opt-in / opt-out

`J2K_JP3D_BATCHED_BRIDGE=0` env var (introduced v10.11.0) continues
to disable the batched path on ALL three lanes — full, partial-res,
ROI — forcing per-slice serial. Diagnostic-A/B only; production
should leave it unset.

## Backward compatibility

- **Codestream bytes**: byte-identical to v10.11.0 on every input.
  Encoder unchanged.
- **`JP3DDecoder(cfg).decode(data)` with `cfg.resolutionLevel > 0`**
  is byte-identical to v10.11.0 — validated by
  `V10_21_BatchedBridgeOptionsParityTests` (per-slice serial vs
  batched-with-options bit-exact on 4-slice K=2 / K=4 / K=N=full /
  K=0 batches).
- **`JP3DROIDecoder().decode(data, region:)`** is byte-identical to
  v10.11.0 — validated by `V10_21_BatchedBridgeOptionsParityTests`
  ROI-only and ROI+K composition tests.
- **Behaviour change**: none.

## Measured wins — JP3D corpus

M2 release, J2KBenchMac --jp3d, in-process, 7 timed runs / 2 warmups,
median per fixture per lane (`full` = full-volume decode, `res1` =
JP3D `resolutionLevel = 1`, `ROIq` = centre quarter ROI):

| Fixture (modality WxHxD) | voxels | full Δ ms (ratio) | res1 Δ ms (ratio) | ROIq Δ ms (ratio) |
|---|---:|---:|---:|---:|
| mr_3d_small  MR 128×128×16 | 262K   | −0.05 (1.00×) | +1.86 (0.75×) | −0.02 (1.00×) |
| ct_3d_small  CT 256×256×16 | 1.05M  | **−4.19** (1.11×) | −0.32 (1.02×) | −2.19 (1.24×) |
| us_3d_small  US 320×240×24 | 1.84M  | **−4.69** (1.08×) | +1.25 (0.95×) | −2.73 (1.24×) |
| mr_3d_mid    MR 256×256×32 | 2.10M  | **−9.35** (1.12×) | −1.63 (1.06×) | **−4.22** (1.23×) |
| ct_3d_mid    CT 512×512×32 | 8.39M  | **−38.85** (1.12×) | **−10.44** (1.09×) | **−21.18** (1.30×) |
| ct_3d_large  CT 512×512×64 | 16.78M | **−82.89** (1.13×) | **−25.82** (1.12×) | **−47.53** (1.33×) |

Per acceptance discipline (≥3 ms wins): **full lane 4/6, res1 lane
2/6, ROIq lane 3/6** clear. Smaller fixtures wash on res1/ROIq
because the reduced workload (fewer iDWT levels or smaller region)
leaves less for the batched dispatch to amortise. The 8M-voxel
ct_3d_mid and 16M-voxel ct_3d_large CT volumes (radiologist
scrolling case) win on every lane.

Raw bench JSONs:
- `Documentation/Benchmarks/data/jp3d-bench-arm64-v10_21-batched-20260524.json`
- `Documentation/Benchmarks/data/jp3d-bench-arm64-v10_21-serial-20260524.json`

## Cross-codec parity (2D codec unchanged)

The 2D codec path (entropy, dequant, iDWT, colour, DC, reconstruct)
is touched only at the bridge SPI splitting point — the same per-
stage code paths execute, same `SubbandInfo` flows, same partial-res
truncation and ROI crop the standalone `decodeResolution` /
`decodeRegion` apply. Cross-codec parity vs OpenJPH 0.27.0 /
Grok 20.3.0 / Kakadu 8.4.1 is inherited from v10.11.0 (no change
measured or asserted in this release).

## Test Suite Results

| Suite | Tests | Result | Coverage |
|---|---:|---|---|
| `V10_21_BatchedBridgeOptionsParityTests` | 7/7 | PASS | New options-bridge parity (K=0/2/4/N, ROI, K+ROI) |
| `V10_20_JP3DBridgeParityTests` | 5/5 | PASS | Phase 1 bridge SPI bit-exact composition |
| `V10_20_BatchedInverseInt32ParityTests` | 12/12 | PASS | Batched Metal kernel + multi-level orchestrator bit-exact vs serial GPU |
| `V10_20_BatchedBridgeParityTests` | 5/5 | PASS | Batched bridge SPI bit-exact vs per-slice serial (full-volume) |
| `swift test --filter JP3D` (regression sweep) | 519/519 | PASS | Full JP3D test suite green with the K>0 + ROI batched wiring |
| Mandatory commit gate (release mode) | 7/7 | PASS | Encode-perf + decode-perf + cross-codec strict validation |

## API surface — additions only

```swift
/// v10.12.0 — JP3D bridge SPI decode options.
public struct JP3DBridgeOptions: Sendable, Equatable {
    public let partialResolutionLevel: Int?
    public let regionOfInterest: J2KRegion?
    public init(partialResolutionLevel: Int? = nil,
                regionOfInterest: J2KRegion? = nil)
    public static let `default`: JP3DBridgeOptions
}

extension J2KDecoder {
    /// v10.12.0 — options overload.
    public func _jp3dDecodeToCoefficients(
        _ data: Data,
        options: JP3DBridgeOptions
    ) async throws -> JP3DSliceCoefficients
}
```

No removals. No existing signatures changed.

## Known limitations

- **`K > 0 AND ROI` composition** still throws. The 2D codec doesn't
  support "footprint-skip at a downsampled resolution" — that's a
  v10.5.0 + v10.6.0 follow-up that wasn't included in this arc.
- **K=0 thumbnail batched dispatch.** The orchestrator can't
  dispatch an empty iDWT chain, so K=0 (which produces the deepest
  LL only) falls back to per-slice serial. Per-slice K=0 is already
  cheap (one LL Int32→pixel copy per slice), so the impact is minor.

## Reproducing the headline numbers

```bash
# Build the JP3D bench (research tool; not in main's Package.swift
# but checked out on v10.21-research):
git fetch origin v10.21-research
git checkout v10.21-research -- Sources/J2KBenchMac/ Package.swift
swift build -c release --product J2KBenchMac

# Batched (default)
.build/release/J2KBenchMac --jp3d --output /tmp/jp3d_batched.json

# Serial baseline (opt-out)
J2K_JP3D_BATCHED_BRIDGE=0 .build/release/J2KBenchMac --jp3d --output /tmp/jp3d_serial.json
```

## Companion documents

- `Documentation/Benchmarks/data/jp3d-bench-arm64-v10_21-batched-20260524.json` — raw bench (batched)
- `Documentation/Benchmarks/data/jp3d-bench-arm64-v10_21-serial-20260524.json` — raw bench (serial baseline)

## Backward upgrade

`swift package update` will not auto-pick this release if your
`Package.swift` pins an exact version; bump the requirement to
`from: "10.12.0"` (or accept the next `.upToNextMinor` per your
policy). Consumers of `JP3DDecoder` / `JP3DROIDecoder` see only a
perf improvement; no source changes required.
