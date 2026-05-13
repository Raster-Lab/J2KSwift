# GPU HT Decoder — Phase 3 Plan (target: v5.4.0)

## Goal

Take the GPU HT decoder from **0.5× CPU** (release-mode, v5.3.0) to **≥1.5× CPU** on representative DICOM workloads, by eliminating per-stage dispatch overhead and unlocking intra-codeblock parallelism. No new user-visible features — perf-only release. Bit-exactness with the CPU reference is non-negotiable.

## Where the time is going (v5.3.0 baseline)

Each GPU stage in the current pipeline does its own end-to-end round-trip:

1. `metalDevice.initialize()` + `commandQueue()` (cached, cheap)
2. `shaderLibrary.loadShaders(device:)` (one-time, cached after first call)
3. **5 fresh `device.makeBuffer(...)` allocations** — no pool reuse despite `J2KMetalBufferPool` existing
4. 4 host→GPU `copyMemory` uploads (descriptors, codestream, vlc0, vlc1)
5. Command buffer + encoder + `dispatchThreadgroups(blockCount, 1, 1)` with **`threadsPerThreadgroup = (1, 1, 1)`** — one thread per codeblock, leaving 31 SIMD lanes idle on every Apple GPU warp
6. `cb.commit() + await cb.completed()` host round-trip
7. GPU→host `memcpy` readback

A single decode of a multi-tile DICOM frame fires this sequence **multiple times** (HT-MagSgn, HT-Cleanup, DWT, MCT, Quantizer all separately). Each round-trip pays the ~1 ms wall-clock floor that `J2KMetalHTDispatchProbe` already measured.

The four optimisations below each attack a different layer of this overhead.

## Optimisations, in priority order

### 3a — Buffer pool integration (1–2 days)

Wire `J2KMetalBufferPool` into `J2KMetalHTMagSgn.run` and `J2KMetalHTCleanup.run`. The pool already exists ([J2KMetalBufferPool.swift](Sources/J2KMetal/J2KMetalBufferPool.swift)), supports power-of-2 size buckets, and is unused by the HT path.

**Scope:**
- Inject a shared `J2KMetalBufferPool` actor into both decoder structs (default-construct one per `J2KMetalDevice` if not supplied)
- Replace each `makeBuffer(size:)` closure with `try await pool.acquireBuffer(device:, size:)`
- Add `defer { Task { await pool.returnBuffer(...) } }` for every acquired buffer
- VLC tables are static across all calls — promote them to long-lived pool entries keyed separately from per-frame buffers (or to a `private(set)` cache on `J2KMetalShaderLibrary`)

**Expected win:** kills the 5 per-stage `device.makeBuffer` allocations, ~0.2–0.4 ms per stage on warm runs. Compounds with 3c.

**Risk:** low. Pool semantics already battle-tested in DWT.

### 3b — Intra-codeblock parallelism in HT-Cleanup (3–5 days)

[J2KMetalHTCleanup.swift:153-155](Sources/J2KMetal/J2KMetalHTCleanup.swift#L153-L155) dispatches `(blockCount, 1, 1)` threadgroups with `(1, 1, 1)` threads per group. **31 SIMD lanes per warp are idle** on every Apple GPU.

A 64×64 codeblock has 1024 quads (2×2 sample groups) — perfectly parallelisable across 32 threads. The MEL+VLC bit-stream parse must stay sequential (it's a forward bit reader with state), but the MagSgn back-half and the per-quad sign/magnitude reconstruction are embarrassingly parallel.

**Scope:**
- Split the kernel into two phases inside one threadgroup:
  - **Phase A (thread 0 only)**: MEL run-length + VLC table lookup + UVLC parse → write per-quad widths + flags into threadgroup memory
  - **Phase B (32 threads)**: each thread reads N quads from threadgroup memory and emits final UInt32 samples in parallel
- Threadgroup memory budget: 1024 quads × ~8 B/quad = 8 KB, well under Apple GPU 32 KB threadgroup limit
- Dispatch `(blockCount, 1, 1)` threadgroups × `(32, 1, 1)` threads

**Expected win:** 4–8× on the cleanup kernel itself (Phase B dominates compute time on dense codeblocks). End-to-end depends on how cleanup-bound the workload is.

**Risk:** medium. Threadgroup-memory layout + barriers between Phase A and B is the new failure surface. Bit-exactness regression suite (`J2KMetalHTCleanupTests`) gates merging.

### 3c — Single command buffer for the HT→DWT chain (3–4 days)

Currently HT-MagSgn → readback → host code → HT-Cleanup → readback → host code → DWT. The two readbacks between HT stages are pure overhead — DWT consumes the cleanup output directly.

**Scope:**
- New `J2KMetalHTPipeline` struct that takes the full set of descriptors for HT-MagSgn + HT-Cleanup + DWT, allocates output buffers shared across all three stages, and encodes all three into a single command buffer with `MTLComputeCommandEncoder` boundaries
- Single `cb.commit() + await cb.completed()` for the whole frame
- Caller-facing API stays the same (just calls into the new pipeline)

**Expected win:** kills 2 of the 3 host round-trips, ~2 ms wall-clock floor → ~0.7 ms.

**Risk:** medium. Buffer lifetimes need care (the cleanup-output buffer must outlive both encoders). DWT path already has its own command-buffer assumptions in [J2KMetalDWT.swift](Sources/J2KMetal/J2KMetalDWT.swift) — this requires extracting an "encode-into-existing-cb" entry point alongside the existing self-contained `run`.

### 3d — Static-table caching in shader library (½ day)

VLC tables are 2 × 1024 × 2 B = 4 KB and never change. Currently re-uploaded on every `J2KMetalHTCleanup.run` call.

**Scope:**
- Add a lazy `vlcTablesBuffer` to [J2KMetalShaderLibrary.swift](Sources/J2KMetal/J2KMetalShaderLibrary.swift), populated once from the first cleanup call
- Cleanup kernel reads from the shared buffer instead of taking vlc0/vlc1 as parameters

**Expected win:** small (~50 µs), but trivial and one less per-frame upload.

**Risk:** trivial.

## Verification

Every optimisation must clear the same gate:

1. **Bit-exactness**: existing [J2KMetalHTCleanupTests.swift](Tests/J2KMetalTests/J2KMetalHTCleanupTests.swift) and [J2KMetalDWTTests.swift](Tests/J2KMetalTests/J2KMetalDWTTests.swift) pass — every codeblock matches CPU reference byte-for-byte
2. **Cross-codec matrix** (`Scripts/run_cross_matrix.sh --check`) stays green against `Tests/Fixtures/CrossCodec/expected_results.csv`
3. **Perf gate** (new): a release-mode benchmark in `Tests/J2KMetalTests` decodes a representative DICOM (e.g. `mr_001.j2k`) on CPU and GPU, asserts `gpu_wall < cpu_wall × 0.7` (≥1.5× faster). Wire into CI as a separate target — fails the build on regression but doesn't gate unit tests

## Out of scope for v5.4.0

- GPU EBCOT (Part 1) decoder — deferred per `project_gpu_ht_phase2` memory; HT path is the easier win
- HTJ2K non-power-of-2 encoder fix — separately queued for v5.5.0
- JP3D entropy coder — large enough scope to warrant its own release
- iOS/Linux validation — `canImport(Metal)` already gates the entire path; non-macOS builds unaffected

## Sequencing and milestones

| Milestone | Scope | Wall-clock | Cumulative target |
|---|---|---|---|
| M1 | 3a (buffer pool) + 3d (table caching) | 2 days | 0.6× CPU |
| M2 | 3c (single cb HT→DWT) | 4 days | 1.0× CPU |
| M3 | 3b (intra-CB parallelism) | 5 days | 1.5× CPU |
| M4 | Perf gate + release notes | 1 day | ship v5.4.0 |

Total: ~2 weeks of focused work. Each milestone is independently mergeable to a `gpu-ht-phase3` branch; main stays releasable throughout.

## Risks and unknowns

- **Apple GPU SIMD width assumption (32)**: confirmed for M1/M2/M3 Apple Silicon, but the kernel should query `pipeline.threadExecutionWidth` rather than hard-coding 32 — already used elsewhere in the codebase.
- **Threadgroup memory pressure** if 3b lands first and a future change adds more shared state — leave headroom (target ≤16 KB, half the budget).
- **Perf-gate false positives on CI hardware** — Apple Silicon runners vary across M1/M2/M3 generations. Set the threshold conservatively (1.3× CPU, not 1.5×) and tune after first month of data.
- **Phase 3b correctness regression** is the biggest single risk. Plan: develop on a feature branch, validate against the full DICOM fixture set + at least one synthetic worst-case (random codestream within HT spec) before merging.
