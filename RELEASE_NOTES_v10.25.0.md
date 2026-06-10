# J2KSwift v10.25.0

**Optimization-audit release — GPU iDWT stale-gate cluster, QoS, JP3D hot loops, CLI partial decode + two CLI defect fixes, multi-tile partial-resolution decode.**

This is a **MINOR** release. Codestream bytes are **byte-identical** to v10.24.2 on
default configurations (verified directly on MG/DX/PX real-medical fixtures), and
decoded pixels are **bit-identical** on both the CPU and GPU decode paths. The public
API gains new surface; nothing is removed or changed in signature.

---

## Summary

v10.25.0 is the product of a full-project, 8-dimension optimization audit
(60 adversarially-verified findings; `OPTIMIZATION_AUDIT_2026-06-10.md`) followed by
an implementation arc that fixed every confirmed stale-gate, QoS, and product-layer
item that cleared the acceptance bar. Highlights:

1. **MG decode −8 to −10 ms (−9 to −11 %)** from the GPU iDWT stale-gate cluster:
   the multi-level fused Int32 iDWT had been dead-gated since v10.3.0 (it was
   coupled to the GPU-HT-*entropy* flag that release turned off), so every default
   DX/MG GPU decode paid a CPU readback + re-upload of the LL band at every
   decomposition level. The chain is now gated on session presence, per-tile iDWTs
   run on fresh command queues (concurrent tiles previously serialised on the one
   shared queue), per-level buffers come from the heap-backed pool, and the pool's
   power-of-two bucketing is linear above 16 MB (a 67 MB MG buffer previously
   rounded to 128 MB, exhausting the 256 MB budget with two buffers).

2. **CLI partial decode wired** — `--level` and `--region` were parsed and
   documented but never reached the v10.4–v10.7 partial-decode APIs; every decode
   ran at full resolution. `--level 0` on a DX 2800×2288 now decodes in **10 ms vs
   57 ms** full. In the process, the wiring surfaced a latent API defect: …

3. **Multi-tile partial-resolution decode fixed** — `decodeResolution` produced
   corrupt output (junk pixels, full-size buffers) on multi-tile codestreams — the
   production `.auto` layout for every ≥3 MP image — since v10.5.0. The per-tile
   truncated iDWT now anchors parity origins at the true canvas depth
   (`outputDepthOffset`) and composites reduced-dimension tiles with ceil-div
   offsets per ISO/IEC 15444-1. The smoke tests that let this ship were
   strengthened to assert buffer sizes and content correlation on both single- and
   multi-tile fixtures.

4. **Two CLI defects fixed**: the documented stdin/stdout piping (`-i -` / `-o -`)
   never worked (the parser treated the bare `-` pipe sentinel as a flag
   terminator); and daemon decode silently returned only component 0 of
   multi-component images (the client now detects this and falls back to a correct
   in-process decode).

5. **`swift test` exit code fixed** — all CLI command logic moved to a new
   `J2KCLICore` library target with a thin `@main` wrapper. Previously, the
   executable entry point linked into the unified test binary hijacked SwiftPM's
   swift-testing pass, printing CLI usage and exiting 1 even when every suite
   passed — CI and scripts could not trust the exit code.

6. **QoS completion of the v10.24.2 arc** — the daemon's RPC handlers ran the
   entire request (`Task.detached`) at unspecified priority, E-core-eligible; the
   encoder's forward-DWT component tasks (the dominant encode stage) and all
   multi-tile per-tile task groups likewise. All now run `.high`, matching the
   v10.24.2 decode-entropy fix.

7. **JP3D Foundation `Data` hot loops** — the v10.10–v10.20 arc shipped per-voxel
   `Data` subscript loops on whole-volume paths (~67 M bounds-checked accesses per
   decode finalization of a 512×512×128 volume, 2 per 16-bit sample). All five
   sites now use bulk pointer conversion (with explicit byte-count guards), and the
   default batched decode no longer copies the whole compressed payload a second
   time.

8. **preWarm honesty** — `preWarm()` compiled a stale PSO list (the legacy scalar
   5/3 kernels, now only the odd-origin fallback) and dispatched only a lossy 9/7
   warmup; the tiled/fused/batched 5/3 Int kernels that production lossless decode
   actually uses compiled lazily inside the first real decode. The list now covers
   them, a lossless reversible 5/3 warmup dispatch was added, and `j2kd` pre-warms
   at startup (with warmup dispatches) instead of inside the first request.

One audit recommendation was **empirically rejected** during this release: excluding
MG 2x2 tiles from per-tile GPU forward DWT (per the documented design intent of the
threshold) regressed MG encode by +20 to +35 ms — the in-code measurement table that
justified the exclusion predates the fresh-per-call-queue fix and is stale. The
explicit routing knob and the `.multiTilePerTile` telemetry reason ship; the default
keeps v10.24.2 routing. This is the v10.7.0 lesson cutting in the opposite
direction: previously-correct routing tables go stale as the codec evolves —
re-measure before trusting them.

## What's New — production-default

- Multi-level fused GPU iDWT chaining on all session decodes (decoder-only,
  bit-exact).
- Fresh per-call command queues + pooled buffers in the per-level GPU iDWT path.
- Linear ≥16 MB buffer-pool bucketing.
- `.high` task priority: daemon RPCs, encoder forward-DWT/tile tasks, decoder tile
  tasks.
- preWarm covers production 5/3 kernels + lossless warmup dispatch; j2kd pre-warms
  at startup.
- True multi-tile partial-resolution decode (`decodeResolution` /
  `decodePartial`).
- CLI: working `-i -` / `-o -` piping; `--level` → `decodeResolution`; `--region
  x,y,w,h` → `decodeRegion(.direct)`; daemon multi-component fallback.
- JP3D bulk serialization on all volume paths.
- 11 remaining instances of the documented release-mode Metal readback deadlock
  pattern (`withUnsafeMutableBytes { copyBytes }` after `cb.completed()`) replaced
  with `unsafeUninitializedCapacity` + pointer update.

## What's New — opt-in / tooling

- `EncoderPipeline._gpuForward53MultiTilePerTilePixelThreshold` — explicit
  routing knob for multi-tile per-tile GPU forward DWT (default = single-tile
  threshold; production routing unchanged), with a new
  `J2KGPUForward53Telemetry.SkipReason.multiTilePerTile` case.
- `J2KMetalDWT.fusedKernelEligible(...)` — public single source of truth for the
  fused-kernel routing predicate.
- `J2KCLICore` library target (the `j2k` executable is now a thin wrapper; the
  executable product is unchanged).

## Backward compatibility

| Aspect | vs v10.24.1/.2 |
|---|---|
| Codestream bytes (encode, default config) | **byte-identical** (verified: MG/DX/PX real-medical fixtures, baseline binary vs this release) |
| Decoded pixels (CPU and GPU paths) | **bit-identical** (verified: MG/DX, both backends) |
| Public API | additive only; `encodeInverse2DInt32` public signature preserved via an internal optional-column-buffer variant |
| CLI behavioural changes | `--level`/`--region` now take effect (previously silently ignored — note `--level 0` now means *smallest thumbnail* per the API, not "full" as the stale v10.24.2 help text said); `-i -`/`-o -` now work; multi-component daemon decodes fall back in-process instead of silently dropping components |

## Cross-codec parity matrix (fresh, this release)

`HTTileParityMatrixTests.testTileParityMatrixOnLargeFixtures` — 12 cells
(MR 886², XA 1024², PX 2459×1316, DX 2800×2288 × 2x2 / 4x4 / strips4 tile modes,
spanning ALL-EVEN (9 cells) and ANY-ODD (3 cells) tile-origin parities). **All 12
cells: self round-trip max diff = 0 (bit-exact) and OpenJPH 0.27 / Grok 20.3 /
Kakadu 8.4 cross-decode max diff = 0.**

| Modality | Shape | Mode | Parity | Self RT | OpenJPH | Grok | Kakadu |
|---|---|---|---|---:|---:|---:|---:|
| MR | 886×886 | 2x2 | ANY-ODD | 0 | 0 | 0 | 0 |
| MR | 886×886 | 4x4 | ALL-EVEN | 0 | 0 | 0 | 0 |
| MR | 886×886 | strips4 | ALL-EVEN | 0 | 0 | 0 | 0 |
| XA | 1024×1024 | 2x2 | ALL-EVEN | 0 | 0 | 0 | 0 |
| XA | 1024×1024 | 4x4 | ALL-EVEN | 0 | 0 | 0 | 0 |
| XA | 1024×1024 | strips4 | ALL-EVEN | 0 | 0 | 0 | 0 |
| PX | 2459×1316 | 2x2 | ALL-EVEN | 0 | 0 | 0 | 0 |
| PX | 2459×1316 | 4x4 | ANY-ODD | 0 | 0 | 0 | 0 |
| PX | 2459×1316 | strips4 | ANY-ODD | 0 | 0 | 0 | 0 |
| DX | 2800×2288 | 2x2 | ALL-EVEN | 0 | 0 | 0 | 0 |
| DX | 2800×2288 | 4x4 | ALL-EVEN | 0 | 0 | 0 | 0 |
| DX | 2800×2288 | strips4 | ALL-EVEN | 0 | 0 | 0 | 0 |

## Performance (Apple M2, release, warm)

### A/B vs v10.24.2 — in-process SDK (`j2k inproc-bench`, median-of-7+, interleaved)

Decode (HT-conformant lossless, 16-bit real medical):

| Fixture | v10.24.2 ms | v10.25.0 ms | Δ |
|---|---:|---:|---:|
| MG small 3516×4784 | 89.1–93.4 | 82.6–84.8 | **−6.5 to −8.6** |
| MG mid 3518×4784 | 86.9–88.2 | 75.3–78.5 | **−9.7 to −11.6** |
| MG large 3521×4784 | 95.4–101.4 | 90.9–93.3 | **−4.5 to −8.1** |
| DX small/mid/large | 47.5–65.2 | 49.1–66.3 | ±1.6 (noise) |
| CT / XA | 2.3–6.9 | 2.3–7.1 | ±0.2 (noise) |

Encode: every fixture within the ±3 ms noise band; MG-large tiebreak (interleaved
11-run medians ×2) base 55.4/51.7 vs branch 50.9/51.2. Bytes byte-identical.

CLI partial decode (DX 2800×2288 multi-tile, cold one-shot): `--level 0` 10 ms vs
57 ms full decode; `--region 100,100,512,512` output verified bit-exact against the
full-decode crop.

### Canonical cross-codec benchmark

`Scripts/benchmarks/cross_codec_warm_bench.py --in-proc` (median-of-7 after 2
warmups; J2KSwift in-process SDK vs OpenJPH 0.27 / Grok 20.3 / Kakadu 8.4 CLIs;
data: `benchmark-results-Mac142-10.25.0-warm-inproc-20260610.json`).

**Decode, real medical large fixtures (median ms):**

| Fixture | J2KSwift | OpenJPH | Grok | Kakadu |
|---|---:|---:|---:|---:|
| PX 2459×1316 (small) | 31.08 | 48.22 | 23.69 | 23.21 |
| PX 2793×1316 (mid) | 30.18 | 82.79 | 23.68 | 22.75 |
| PX 2812×1316 (large) | 30.93 | 81.18 | 24.33 | 23.55 |
| DX 2224×2798 (small) | 48.23 | 81.66 | 43.91 | 44.34 |
| DX 2800×2288 (mid) | 49.56 | 86.06 | 46.79 | 47.15 |
| DX 2544×3056 (large) | 60.75 | 141.82 | 47.52 | 46.53 |
| MG 3516×4784 (small) | **80.56** | 199.45 | 84.19 | 80.84 |
| MG 3518×4784 (mid) | **79.58** | 141.70 | 82.38 | 84.50 |
| MG 3521×4784 (large) | 95.43 | 190.79 | 80.72 | 83.01 |

**J2KSwift now leads BOTH Kakadu and Grok on MG small and MG mid decode** —
extending the v10.3.0 "tied on MG" result to an outright lead on 2 of 3 MG
fixtures. Large-medical decode geomean: J2KSwift 51.6 ms vs Kakadu 44.5 ms /
Grok 44.9 ms (1.16× — improved from ~1.27× at v10.24.1). Encode geomean: 32.2 ms
vs Kakadu 21.3 ms (1.51×; encode was not a target of this release and is
byte-identical to v10.24.2). Whole-corpus tallies (38 fixtures): decode 27/38
fastest, encode 24/38 — as always, the small-fixture wins partly reflect
competitor CLI startup; the large-fixture table above is the honest comparison.

## Test Suite Results

- Mandatory commit gate (`J2KMedicalCorpusEncodePerformanceTests` +
  `J2KMedicalCorpusPerformanceTests` + `J2KStrictCrossCodecValidationTests`):
  **7/7, 0 failures** — and `swift test` now exits **0** (previously 1 even on
  full pass; fixed by the J2KCLICore split).
- `HTGPUForward53Phase9PolicyTests` (6) + `HTTileParityMatrixTests` (1, 12 cells):
  0 failures.
- Partial-decode suites (`V10_10_DecodeResolutionSmokeTests` — strengthened with
  buffer-size + content-correlation assertions on single- and multi-tile fixtures,
  `V10_14_DecodePartialTests`, `J2KAdvancedDecodingTests`): 0 failures.
- New `CLIPipeSentinelParserTests` covering the parser fix.

## Known limitations

- `--layer` / `--component(s)` are accepted and forwarded but the
  `decodeResolution`/`decodeRegion` entry points do not yet apply them
  (documented as informational in the CLI help).
- `--level` above the codestream's decomposition count decodes full resolution
  (documented) rather than erroring.
- The daemon `decodeFile` RPC still writes only component 0 by contract (its
  reply carries `componentCount` for callers to detect); the in-band `decode` RPC
  is the one with the new client-side guard.
- The audit's larger structural findings (decode-tail `[Double]` materialization,
  `J2KComponent` bytes-as-big-endian-`Data` API, ~48 K lines of dead weight,
  JPIP/J2KFileFormat audits) are documented in `OPTIMIZATION_AUDIT_2026-06-10.md`
  as future arcs.

## Reproducing

```bash
swift test -c release --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'
python3 Scripts/benchmarks/cross_codec_warm_bench.py --in-proc \
  --output benchmark-results-<host>-10.25.0-warm-inproc-<date>.json
# CLI partial decode
.build/release/j2k decode -i <file.j2k> -o thumb.pgm --level 0
.build/release/j2k decode -i <file.j2k> -o roi.pgm --region 100,100,512,512
```

## Companion documents

- `OPTIMIZATION_AUDIT_2026-06-10.md` — the 60-finding audit this release implements.
- `benchmark-results-Mac142-10.25.0-warm-inproc-20260610.json` — canonical bench data.
