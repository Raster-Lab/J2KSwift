# J2KSwift v10.14.0

**JP3D parallel per-slice encode.** The encoder side gets its first
optimisation in the v10 JP3D arc. The per-slice 2D encode loop in
`JP3DSliceStackCodec` was sequential since shipping — each Z-slice's
2D J2K encode ran one after another even though encodes are
independent across slices. v10.14.0 splits the loop into a sequential
probe (slices 0-1, commits the tile-mode decision) and a parallel
tail (slices 2..N via TaskGroup). M2 release JP3D encode wins
**−4 ms to −76 ms (1.09–1.56× faster)** across every fixture in the
JP3D bench corpus, with the largest absolute win (−76 ms) on the
16M-voxel CT volume.

Encoder-only release; **codestream bytes byte-identical to v10.13.0**.
Decoder unchanged. MINOR per RELEASING.md — no public API removed
or signature-changed; the parallelism is a pure-internal refactor
that produces identical output bytes under the same Z-delta gating.

## Summary

`JP3DSliceStackCodec.encode(...)` previously ran every slice's 2D
encode sequentially:

```
for z in 0..<tile.depth {
    let rawCS = await unsignedEncoder.encode(rawImage)
    if tryBoth { let signedCS = await signedEncoder.encode(signedImage) ... }
    ...
}
```

v10.14.0 keeps the sequential phase **only for slices 0-1** (which
commit the tile-mode decision via the M6/M7 empirical-savings
threshold) and runs **slices 2..N in parallel** via a `withThrowingTaskGroup`.
From slice 2 onward neither `tileSignedOnlyActive` nor
`tileTryBothActive` mutates, so each parallel task captures the
committed flags by value.

The per-slice body is extracted into a new
`encodeOneSlice(...)` instance method so both sequential and
parallel paths share the same logic (raw encode + optional signed
encode + best-of-two pick). The Z-delta correctness guarantee is
preserved: the residual `slice_z − slice_{z-1}` depends only on
the raw input bytes (`TileVoxels`), NOT on the encoded codestream
of slice z-1, so slices can encode in parallel without breaking
the residual chain.

## What's New — production-default

| Public API | v10.13.0 behaviour | v10.14.0 behaviour |
|---|---|---|
| `JP3DEncoder().encode(volume)` (every config) | Sequential per-slice 2D encode | Sequential slices 0-1 (tile-mode commit) + parallel slices 2..N (TaskGroup). **Same output bytes**; 4–76 ms faster |

The change is invisible to consumers — same encoder API, same
codestream bytes. Only the wall-time is faster.

## What's New — opt-in / opt-out

`J2K_JP3D_PARALLEL_ENCODE=0` env var disables the parallel tail,
forcing the legacy serial loop. Diagnostic A/B only; production
should leave it unset.

## Backward compatibility

- **Codestream bytes**: byte-identical to v10.13.0 on every input.
  The parallel encode produces the same per-slice payloads in the
  same order; the round-trip test sweep (519/519 JP3D tests PASS)
  confirms output parity.
- **Decoder**: unchanged.
- **Behaviour change**: none. The encoder is just faster.

## Measured wins — JP3D corpus

M2 release, J2KBenchMac --jp3d, in-process, 7 timed runs / 2 warmups,
median per fixture, **encode** wall time:

| Fixture (modality WxHxD) | voxels | serial ms | parallel ms | Δ ms | ratio |
|---|---:|---:|---:|---:|---:|
| mr_3d_small  MR 128×128×16 | 262K   | 11.84 | 7.58 | **−4.27** | **1.56×** |
| ct_3d_small  CT 256×256×16 | 1.05M  | 33.92 | 26.17 | **−7.75** | **1.30×** |
| us_3d_small  US 320×240×24 | 1.84M  | 58.58 | 40.73 | **−17.85** | **1.44×** |
| mr_3d_mid    MR 256×256×32 | 2.10M  | 71.59 | 65.68 | **−5.91** | 1.09× |
| ct_3d_mid    CT 512×512×32 | 8.39M  | 295.58 | 246.98 | **−48.60** | **1.20×** |
| ct_3d_large  CT 512×512×64 | 16.78M | 615.94 | 539.95 | **−75.99** | **1.14×** |

**All 6/6 fixtures clear the 3 ms acceptance threshold.** Smallest
fixture shows the largest relative speedup (1.56× on mr_3d_small)
because the per-slice fixed cost amortises better; largest fixture
wins 76 ms absolute on the radiologist-relevant 16M-voxel CT.

Sub-linear vs N=8 cores because:
- Z-delta probe is serialized (single pass over slice-pairs).
- Slices 0-1 are sequential to commit the tile-mode decision.
- Memory contention on the 16M-voxel CT writes 33 MB of output.

Raw bench JSONs:
- `Documentation/Benchmarks/data/jp3d-bench-arm64-v10_23-parallel-encode-20260524.json`
- `Documentation/Benchmarks/data/jp3d-bench-arm64-v10_23-serial-encode-20260524.json`

## Decoder unchanged

The four v10.11–v10.13 JP3D decode wins compose on top of the
parallel encode: encode a volume with v10.14.0 (1.09–1.56× faster)
and decode it with the v10.13.0 batched bridge (1.07–1.33× faster
across full / partial-res / ROI lanes). The combined round-trip
on 16M-voxel CT: ~3.5× faster vs v10.10.0.

## Test Suite Results

| Suite | Tests | Result | Coverage |
|---|---:|---|---|
| `swift test --filter JP3D` (regression sweep) | 519/519 | PASS | Full JP3D test suite green; parallel encode bytes-identical to serial under the same Z-delta gating |
| Mandatory commit gate (release mode) | 7/7 | PASS | Encode-perf + decode-perf + cross-codec strict validation |

## API surface — no additions, no removals

Internal refactor only. `JP3DSliceStackCodec.encode(...)` keeps
the same signature; the per-slice loop is split internally.

## Known limitations

- The parallel tail uses Swift structured concurrency's
  `withThrowingTaskGroup` with no explicit concurrency cap — Swift
  runtime caps based on cooperative thread pool size (≈ N CPU
  cores). On very-large fixtures the system may see brief peak
  memory of `N × per-slice encode scratch`; the encoder's
  per-slice memory is bounded.
- Z-delta probe and slices 0-1 remain sequential — could be reduced
  further with speculative tile-mode encoding, but the M6/M7
  savings-threshold logic was designed for the sequential commit.

## Reproducing the headline numbers

```bash
# Build the JP3D bench (research tool on the `v10.23-research` branch;
# not in main's Package.swift):
git fetch origin v10.23-research
git checkout v10.23-research -- Sources/J2KBenchMac/ Package.swift
swift build -c release --product J2KBenchMac

# Parallel encode (default)
.build/release/J2KBenchMac --jp3d --output /tmp/jp3d_parallel.json

# Serial baseline (opt-out)
J2K_JP3D_PARALLEL_ENCODE=0 .build/release/J2KBenchMac --jp3d --output /tmp/jp3d_serial.json
```

## Companion documents

- `Documentation/Benchmarks/data/jp3d-bench-arm64-v10_23-parallel-encode-20260524.json` — raw bench (parallel)
- `Documentation/Benchmarks/data/jp3d-bench-arm64-v10_23-serial-encode-20260524.json` — raw bench (serial baseline)

## Backward upgrade

`swift package update` won't auto-pick this release if your
`Package.swift` pins an exact version; bump the requirement to
`from: "10.14.0"`. No source changes required for consumers.
