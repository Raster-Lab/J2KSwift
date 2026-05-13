# J2KSwift — Optimal Performance Guide

**Audience:** developers integrating J2KSwift into apps, daemons, server libraries, scripts, CI pipelines.
**Goal:** the shortest path to the numbers in [`Benchmarks/CROSS_CODEC_REPORT_v9.5.2_M2_warm.md`](Benchmarks/CROSS_CODEC_REPORT_v9.5.2_M2_warm.md) and [`Benchmarks/J2KSWIFT_OPTIMAL_VS_KAKADU.md`](Benchmarks/J2KSWIFT_OPTIMAL_VS_KAKADU.md) — i.e. the performance position where J2KSwift beats Kakadu CLI on 4 of 7 medical-corpus fixtures.

## TL;DR

| You are | Optimal shape | What you need to do |
|---|---|---|
| **SDK consumer** (app, app extension, daemon, server library embedding the codec) | Direct in-process API — `J2KEncoder.encode(_:)` / `J2KDecoder.decode(_:)` | Call **`J2KDecoder.preWarm()` once at app start** + **reuse encoder/decoder instances**. NO daemon install. |
| **CLI consumer** (scripts, batch pipelines, PACS tooling shelling out per file) | `j2k encode --daemon` / `j2k decode --daemon` | Install the daemon **once per machine**: `j2k daemon-install --force`. |

Everything else (NEON hot path, `.auto` tile mode, GPU forward 5/3 DWT, process-shared Metal session, qstep cache) is **already on by default** — no action required.

---

## Defaults you already have

These were turned on by default in the indicated release. **No code or configuration is required from you.** They're listed here so you know what's in the box.

| Feature | Default since | Knob (only if you need to *disable* for diagnostics) |
|---|---|---|
| **C+NEON HT entropy hot path** — 10-21 % warm-encode wall reduction on M2 vs Swift-only entropy | v9.4.0 | `J2K_NEON_HOT_PATH=0` env var to force the legacy Swift path |
| **`.auto` multi-tile mode** — 2×2 tiles for ≥3 MP fixtures; beats single-tile GPU on post-v9.5 main | v7.0.0 | `J2K_HT_TILE_MODE=single` to force single-tile |
| **GPU forward 5/3 DWT** — fires above the 3 MP per-tile threshold | v6.1.0 | `J2K_GPU_FORWARD_53=0` to force CPU forward DWT |
| **Process-shared Metal session** in `J2KDecoder.decode(_:)` / `decodeGPU(_:)` — amortises Metal cold-start across calls within one process | v6.2.0 | (not user-disable-able; safe to use even when GPU paths are off) |
| **`J2KQstepCache.shared`** — process-default qstep cache for similar-shape lossy 9/7 batches (lossy only; lossless path unaffected) | v9.6 (in v9.5.0 release) | (no opt-out; cache hit is bit-exact identical to cache miss) |
| **Daemon-encode routing** — `j2k encode --daemon` graduated from research to production | v9.5.0 | `--no-daemon` to force in-process encode |
| **HT-conformant lossless output** — production target since v5.38 | v5.38+ | use `--lossless` flag or `config.lossless = true` |

> Verify NEON hot path is active:
>
> ```bash
> .build/release/j2k version
> # 9.5.2 or later → NEON default-on
> ```

---

## SDK consumers — apps, app extensions, daemons embedding J2KSwift

This is the shape that **beats Kakadu** on 4 of 7 medical fixtures (see [`Benchmarks/J2KSWIFT_OPTIMAL_VS_KAKADU.md`](Benchmarks/J2KSWIFT_OPTIMAL_VS_KAKADU.md)).

### Step 1 — preWarm at app startup

```swift
import J2KCodec

// At app/SDK init — once, very early.
Task.detached {
    await J2KDecoder.preWarm()
    // Optionally: includeWarmupDispatch: true for batch/PACS workloads
    // that will issue many decodes; costs ~5-10 ms but saves 10-20 ms
    // on the first real user decode.
}
```

Without `preWarm()`, the **first** decode in your process pays ~50 ms of Metal init cost serially. With it, that cost is paid up-front and overlapped with whatever else the app is doing at launch.

`preWarm()` is **idempotent** — safe to call from multiple SDK boundaries. Failures (e.g. Metal unavailable on Linux) are caught and silently swallowed; the codec falls back to CPU paths.

### Step 2 — reuse encoder/decoder instances

```swift
import J2KCodec

// ✓ Do this — one instance, many calls
let encoder = J2KEncoder(encodingConfiguration: .init(
    quality: 1.0, lossless: true,
    decompositionLevels: 5, qualityLayers: 1,
    progressionOrder: .lrcp, useHTJ2K: true,
    useReversibleFilter: true,
    htj2kBlockFormat: .conformant))

for image in batch {
    let bytes = try await encoder.encode(image)
    // ... handle bytes
}

// ✗ Don't do this — instantiating per call costs nothing functionally
//   but loses the "warm encoder" performance characteristic
for image in batch {
    let encoder = J2KEncoder(encodingConfiguration: .init(...))
    let bytes = try await encoder.encode(image)
}
```

Reusing the encoder lets internal NEON-buffer pools and HT lookup tables stay warm across calls. The first call pays a small allocation cost; every subsequent call is at full speed.

The same applies to `J2KDecoder`:

```swift
let decoder = J2KDecoder()
for data in codestreamBatch {
    let image = try await decoder.decode(data)
}
```

### Step 3 — pick the right decode API for the image size

J2KSwift exposes three decode entry points with different optimal regimes. **You don't have to choose manually** — `J2KDecoder.recommendedDecodeAPI(width:height:)` returns the right one for the dimensions:

```swift
let recommendation = J2KDecoder.recommendedDecodeAPI(width: w, height: h)
switch recommendation {
case .cpu:                let image = try await decoder.decode(data)
case .decodeGPU:          let image = try await decoder.decodeGPU(data)
case .decodeWithGPUHT:    let image = try await decoder.decodeWithGPUHT(data)
}
```

Thresholds (M2-derived; see `J2KDecoder.recommendedDecodeAPI` docstring):

| Pixels | Recommendation | Why |
|---|---|---|
| ≤ 256×256 (65 k px) | `cpu` | GPU dispatch cost ≈ encode work; CPU is within noise |
| 256² – ~1730² (~3 MP) | `decodeGPU` | 1.3–3.0× CPU; GPU-HT dispatch hasn't amortised yet |
| ≥ ~1730² (~3 MP) | `decodeWithGPUHT` | 3–4× CPU; GPU-HT dispatch fully amortises |

### Step 4 — DICOM input is native, use it

J2KSwift reads DICOM Part 10 directly. Don't pre-extract pixel data with DCMTK/pydicom — pass the `.dcm` file directly:

```swift
// Direct DICOM input — works with any J2KEncoder configuration
let dicomData = try Data(contentsOf: dicomURL)
let image = try J2KImage(dicomData: dicomData)  // pseudo-API; check actual surface
let bytes = try await encoder.encode(image)
```

This is J2KSwift's marketable strength — external CLIs (OpenJPH/Grok/Kakadu) are J2K-only and require a separate DICOM extraction step.

### Step 5 — DON'T install the daemon for SDK use

The j2kd daemon adds **2-9 ms of overhead per encode under isolated calls (8-50 ms under sustained-load batch)** vs in-process API calls. See `Benchmarks/DAEMON_OVERHEAD_METHODOLOGY_FINDING.md` for the controlled-measurement decomposition. **SDK consumers should NOT use `j2k daemon-install`** — it's for CLI consumers only. The in-process path is faster and never penalised by system load.

Verify you're not accidentally routing through the daemon: `J2KEncoder.encode(_:)` doesn't consult the daemon at all; you're safe by default.

---

## CLI consumers — scripts, batch pipelines, PACS tooling

If you're shelling out to `j2k encode` / `j2k decode` once per file (or many times in a loop), install the daemon once and use `--daemon`. It eliminates the ~70 ms Swift-runtime + Metal init cost per CLI invocation.

### Step 1 — install the daemon (one-time per machine)

```bash
# Build the daemon binary if not already built
swift build -c release --product j2kd

# Install it (per-user; no sudo required)
.build/release/j2k daemon-install --force

# Verify
.build/release/j2k daemon-ping
# → daemon: available
#   PID: ...
#   uptime: ... s
#   ping round-trip: < 1 ms
```

Install layout (no sudo, per-user):

- Binary: `~/Library/Application Support/J2KSwift/j2kd`
- launchd plist: `~/Library/LaunchAgents/com.raster.j2kd.plist`

The daemon starts on-demand on first XPC request, stays warm for 10 minutes after the last request, then idles out. Subsequent requests within the idle window are instant.

### Step 2 — use `--daemon` on every CLI call

```bash
# Encode (HT-conformant lossless via the warm daemon)
j2k encode -i scan.dcm -o scan.j2k --htj2k --lossless --daemon

# Decode (warm-process speed)
j2k decode -i scan.j2k -o scan.pgm --daemon

# Scripted batch (each call warm)
for f in *.dcm; do
    j2k encode -i "$f" -o "${f%.dcm}.j2k" --htj2k --lossless --daemon --quiet
done
```

The `--daemon` flag is **opt-in**, not the default — pure `j2k encode` without the flag pays the full ~70 ms cold-start every time. The default is **opt-in** so daemon-unaware users get correct (slow) behaviour rather than mysterious failures if the daemon is uninstalled.

### Step 3 — when to skip `--daemon`

- **Single one-shot CLI call** (you'll never invoke the codec again this session). Daemon's startup amortisation doesn't help if there's nothing to amortise across. Add `--no-daemon` for clarity.
- **Daemon unreachable** (uninstalled, or `j2k daemon-ping` fails). J2KSwift falls back to in-process encoding transparently; no need to remove `--daemon`.

### Step 4 — DON'T use `--daemon` from SDK code

If you embed J2KSwift's Swift API in your app/process and ALSO have `j2kd` installed, your in-process `J2KEncoder.encode(_:)` calls **don't go through the daemon** — they execute directly in your process. This is correct (see Phase 6 finding — daemon adds 20 ms of XPC overhead vs direct in-process). The daemon is exclusively for the **CLI** path.

---

## Common mistakes that lose performance

| Mistake | What it costs | Fix |
|---|---|---|
| Instantiating `J2KEncoder` per call | Allocation + NEON-buffer pool reset per encode | Reuse one encoder instance across calls |
| Skipping `J2KDecoder.preWarm()` at app start | ~50 ms Metal init paid by your first user-visible decode | Call once during app init |
| SDK consumer routing through `j2k --daemon` | +2-9 ms per DX-class encode under isolated calls (8-50 ms under sustained-load batch) | Call `J2KEncoder.encode(_:)` directly |
| CLI consumer NOT installing the daemon | +70 ms Swift-runtime + Metal init per invocation | `j2k daemon-install --force` once per machine |
| Pre-extracting DICOM pixel data with DCMTK before encode | DICOM parse cost paid twice (your extraction + J2KSwift would do it anyway) | Pass `.dcm` directly to `J2KEncoder.encode` |
| Setting `J2K_NEON_HOT_PATH=0` in production env | Loses 10-21 % wall reduction the v9.4.0 hot path provides | Don't set it; default is `1` (on). Use only for diagnostics. |
| Setting `J2K_HT_TILE_MODE=single` for large images | Loses parallel CPU tile dispatch; single-tile GPU loses to multi-tile CPU on post-v9.5 per Phase 5 measurement | Don't set it; default is `auto` |
| Forcing CPU-only via `--no-gpu` or `J2K_GPU_FORWARD_53=0` | Loses the GPU forward 5/3 DWT optimisation for ≥3 MP fixtures | Don't set it; default routes correctly per pixel-count threshold |

---

## Verifying you're on the optimal path

Run the in-process medical corpus performance test:

```bash
swift test -c release --filter J2KMedicalCorpusEncodePerformanceTests/testCorpusEncodeAcrossAPIs
```

On Apple M2 you should see CPU encode walls in this range:

```
| Fixture            | CPU encode ms |
| mr_002 (180×180)   | 0.5 – 0.8 |
| ct_001 (512×512)   | 2.0 – 3.0 |
| mr_001 (886×886)   | 12 – 14   |
| xa_001 (1024×1024) | 8 – 10    |
| px_001 (2459×1316) | 26 – 32   |
| dx_002 (2800×2288) | 53 – 60   |
| mg_001 (3520×4784) | 140 – 150 |
```

If your numbers are 10-20 % worse than these:

1. Check `.build/release/j2k version` reports `9.5.2` or later (NEON default-on requires v9.4.0+).
2. Check `J2K_NEON_HOT_PATH` is unset or `1` (not `0`).
3. Check you built with `-c release` (debug builds are 50-100× slower).
4. Check no debugger is attached.

If numbers are 50+ % worse, you're likely in DEBUG mode or hitting an environment-variable override.

---

## Cross-codec position summary (per [`Benchmarks/J2KSWIFT_OPTIMAL_VS_KAKADU.md`](Benchmarks/J2KSWIFT_OPTIMAL_VS_KAKADU.md))

At the optimal SDK configuration described above, on Apple M2 with HT-conformant lossless:

| Workload class | J2KSwift in-proc vs Kakadu CLI |
|---|---|
| ≤ 1 MP (thumbnails, DICOM instances) | **J2KSwift WINS 1.1× – 7.5×** |
| 1-3 MP (medium views) | **J2KSwift WINS** (XA 1024² 1.13×) |
| 3-6 MP (PX panoramic dental) | Kakadu wins 1.43× |
| 6 MP (DX chest radiography) | Kakadu wins 1.39× |
| 17 MP (MG mammography, batch) | Kakadu wins ~3.6× |

For decode, Kakadu currently leads on every fixture (1.9–4.5× lead); J2KSwift's decode optimisation arc is the v9.6+ work.

## Reference

- [`BENCHMARK.md`](BENCHMARK.md) — canonical methodology for any performance claim
- [`Benchmarks/CROSS_CODEC_REPORT_v9.5.2_M2_warm.md`](Benchmarks/CROSS_CODEC_REPORT_v9.5.2_M2_warm.md) — full 38-fixture × 4-codec benchmark
- [`Benchmarks/J2KSWIFT_OPTIMAL_VS_KAKADU.md`](Benchmarks/J2KSWIFT_OPTIMAL_VS_KAKADU.md) — focused J2KSwift-vs-Kakadu head-to-head
- [`research/V10_0_PHASE6_DAEMON_DECOMPOSITION.md`](research/V10_0_PHASE6_DAEMON_DECOMPOSITION.md) — why SDK consumers should NOT use the daemon
- [`releases/RELEASE_NOTES_v9.5.2.md`](releases/RELEASE_NOTES_v9.5.2.md) — daemon-install help SDK-vs-CLI guidance
- [`releases/RELEASE_NOTES_v9.4.0.md`](releases/RELEASE_NOTES_v9.4.0.md) — the C+NEON HT entropy hot path (default-on)
