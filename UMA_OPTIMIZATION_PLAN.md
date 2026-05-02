# UMA optimization plan — v5.9 → v5.11 detour

**Predecessor:** v5.8.0 (end-to-end fused HT cleanup → scatter → DWT)
**Theme:** stop leaving Apple Silicon Unified Memory Architecture wins on the table. Three sized-down releases — zero-copy boundary first, then storage-mode pass, then heap pool — then resume the previously-queued v5.12+ functional roadmap.

## Why this is the right detour now

v5.6 → v5.7 → v5.8 added GPU-resident pipelines and chained command buffers, and warm-process speedup landed at **~1.5×–1.6× median**. The leftover gap to "as fast as we could be on M-series" is mostly memory-shaped:

1. **Every `MTLBuffer.contents() → memcpy → [Int32]` boundary on UMA is a CPU-to-CPU copy of memory the CPU could already address directly**. The decoder pipeline does this several times per frame (decoded codeblocks, DWT output, etc) before handing data to downstream stages, and the post-DWT `currentLL.map { Double($0) }` at [J2KDecoderPipeline.swift:2702](Sources/J2KCodec/J2KDecoderPipeline.swift#L2702) allocates an N-pixel `Double` array per component just to feed colour transform that immediately re-iterates. None of these consumers strictly need owned `Array` storage — a borrowed `UnsafeBufferPointer<Int32>` or a passed-through `MTLBuffer` would do.

2. **Every `MTLBuffer` allocation in J2KMetal uses `.storageModeShared`** — 15+ call sites including DWT, HT cleanup, MCT, scatter, multi-level fused. `.storageModeShared` keeps CPU coherency invariants alive even on intermediates that the CPU never touches; `.storageModePrivate` lets Apple's GPU stack pick faster memory layouts and skip implicit coherency syncs. The buffer pool already has a `.private` enum case ([J2KMetalBufferPool.swift:311](Sources/J2KMetal/J2KMetalBufferPool.swift#L311)), but **no caller exercises it**.

3. **Per-buffer `device.makeBuffer(length:options:)` calls** ask the Metal driver to allocate fresh OS pages each time the pool misses. The v5.8 fused dispatch's per-tile peak holds 5 levels × 4 subband buffers + intermediates + outputs (~15+ buffers). `MTLHeap` sub-allocation collapses these to a single OS-level allocation amortised across many sub-buffers — the win is reduced allocator overhead and driver bookkeeping churn, not just latency on individual allocations.

The bet is that fixing all three lifts the whole pipeline by another ~10–25% on Apple Silicon without adding any user-visible feature. The ceiling probably isn't a 2× jump — UMA already amortises a lot of what discrete GPUs pay — but the wins compound, and the v5.9 zero-copy boundary in particular is the prerequisite that makes the v5.10 private-storage pass safe and the v5.11 heap allocator useful.

After this detour, **the previously-queued items resume as v5.12+**: multi-tile in-flight cbs, GPU colour transform fusion, 9/7 irreversible fusion, `.metallib` bundling. None are blocked by the UMA work — but each becomes incrementally cheaper to implement on top of a UMA-aware buffer layer that has fewer copies and fewer allocations.

## Instrumentation prerequisite (lands with or before v5.9)

Optimization without measurement is guessing. Before or alongside the v5.9 work, add lightweight per-decode instrumentation to `J2KMetalSession` (or an equivalent diagnostics struct) that tracks:

- **`memcpyCount`** — every `buffer.contents() → memcpy → Array` boundary increments this. Target after v5.9: **zero on the hot path** (final API readback excluded).
- **`makeBufferCount`** — every `device.makeBuffer(length:options:)` call increments this. Target after v5.11: bounded by initial heap allocations + true overflow only.
- **`bufferContentsAccessCount`** — every `MTLBuffer.contents()` call increments this. Target after v5.10: zero on `.storageModePrivate` buffers (asserted in debug builds).

This is a lightweight counter pattern, not full tracing — counters live behind `#if DEBUG` or a runtime flag so release builds pay no overhead. Surface the counters in the existing `J2KMetalSessionTests.testCorpusWarmProcessPerf` benchmark output so every release-cycle measurement reports them alongside wall-clock time. **Without these numbers, "we improved memory perf" is unverifiable.**

## Three milestones

### v5.9 — Zero-copy CPU↔GPU boundary (FIRST)

**Goal.** No intermediate `[Int32]` or `[Double]` allocations inside the decode pipeline.

The pipeline stages today communicate via owned `Array` types — `[Int32]` from HT decode, `[[Double]]` from DWT output, etc. On UMA every `MTLBuffer.contents()` is already CPU-addressable, so the only reason to copy bytes into an `Array` is for the consumer's lifetime contract — and the consumer rarely needs that. v5.9 makes the pipeline buffer-native end-to-end.

**Patterns to eliminate.**

- `buffer.contents() → memcpy → Array<T>(unsafeUninitializedCapacity:...)` patterns inside any pipeline stage. Currently appears in `J2KMetalDWT.readInt32Array`, `J2KGPUHTDispatch.decodeBatchGPUResident.decodedBlockCoefficients`, the `runIntegerMagnitude` readback, and several others.
- `.map { Double($0) }` in any hot path. Specifically: [`currentLL.map { Double($0) }`](Sources/J2KCodec/J2KDecoderPipeline.swift#L2702) at the end of the inverse DWT must be removed or deferred to the final API boundary.

**Patterns to replace them with.**

- Pass `MTLBuffer` references through pipeline stages directly. Stages that currently take `[Int32]` accept either a buffer + sample-count or a borrowed pointer.
- Scoped `withUnsafeBufferPointer { ... }` blocks where the consumer is genuinely transient (e.g. a `for`-loop reader). Lifetime is the closure scope; the underlying `MTLBuffer` outlives it via the pool/session.
- `readInt32Array`-style helpers must **not** allocate unless at the final API boundary (the public `J2KDecoder.decode*` return value is the only legal allocation point inside the GPU path).

**Invariant.** Arrays are only allowed at API boundaries or test adapters — never inside the pipeline.

This is the load-bearing rule for v5.10 and v5.11. v5.10 can't safely move buffers to `.storageModePrivate` while pipeline stages are still calling `.contents()` on them; v5.11's heap pool can't reduce allocations meaningfully if the consumer copies out to an `Array` and forces the buffer back to the pool inside the inner loop. v5.9 unblocks both.

**Risks.** Borrowed pointers have lifetime constraints. A consumer that retains an `UnsafeBufferPointer` past the buffer's pool-return point gets use-after-free. Mitigated by the scoped-closure idiom and by the v5.10 audit that follows — any callsite that retains beyond a closure scope is flagged.

**Verification.**

- All existing bit-exactness gates pass byte-for-byte (`testFullDICOMCorpus_GPUHTMatchesCPUHT` is the canonical check).
- The instrumentation `memcpyCount` for a typical decode goes to **zero on the hot path** (final API readback is the only allowed copy).
- Perf measurement: should show measurable wins on multi-component tiles where the post-DWT conversion was a real cost.

**Wall-clock.** ~3 days (API redesign + 2-3 callsite migrations + new instrumentation + tests).

### v5.10 — Storage-mode optimization (`.storageModePrivate` for intermediates)

**Goal.** Move every GPU-only buffer to `.storageModePrivate` so the Metal stack can pick faster memory layouts and skip implicit coherency syncs.

**The strict rule.** Any buffer marked `.storageModePrivate` must have **zero `.contents()` access anywhere in the codebase**. Not "almost zero", not "only in legacy debug paths" — zero. v5.9 makes this rule enforceable; v5.10 enforces it.

**Classification.**

- **Inputs / outputs** (caller provides bytes / caller reads bytes) → `.storageModeShared`. This includes descriptor uploads, codestream pool, VLC tables, and the final API-boundary readback buffer.
- **GPU-only intermediates** (kernel writes, kernel reads, no CPU touch) → `.storageModePrivate`. This includes `colLowBuffer`, `colHighBuffer`, `sgnMagBuffer`, the per-subband LL/LH/HL/HH buffers between scatter and DWT, and MCT scratch.

**No implicit blit fallbacks allowed.** When an intermediate buffer needs to be observed from the CPU (debug, unit test, etc), the test or debug path must explicitly request a separate readback buffer or use `.storageModeShared` for that specific run. There must not be hidden blits inserted at runtime to "make private buffers CPU-readable" — that path defeats the point.

**Required audit work.**

- Audit every `.contents()` call site in the codebase. Each must be on a `.storageModeShared` buffer. Flag any that aren't.
- Add a debug assertion (`#if DEBUG` or `precondition` behind a runtime flag) that traps if `.contents()` is called on a buffer the caller declared `.storageModePrivate`. The assertion is on the caller's declared intent, not the underlying `MTLBuffer.storageMode` (since Metal won't always trap by itself).
- Add `bufferContentsAccessCount` instrumentation breakdown by storage mode — release-mode builds should show zero `.contents()` calls on private buffers.

**Risks.** Misclassifying a buffer as private when CPU code reads `.contents()` produces undefined behaviour at runtime (or a bus error on stricter sanitisers). v5.9's invariant ("Arrays only at API boundaries") is what makes this rule mechanically enforceable — if no pipeline stage allocates an `Array` from buffer contents, no pipeline stage is reading those contents on CPU, and the buffer is safe to mark private.

**Verification.**

- Bit-exactness preserved on the corpus.
- Instrumentation: zero `.contents()` calls on `.storageModePrivate` buffers in any release-mode decode.
- Perf measurement: ~5–15% warm-process speedup expected on the per-tile hot path (modest on its own; compounds with v5.11).

**Wall-clock.** ~2 days (audit + thread strategy through call sites + debug assertion + tests + perf measurement).

### v5.11 — `MTLHeap`-backed buffer pool

**Goal.** Replace per-buffer `device.makeBuffer(length:options:)` allocator pressure with `MTLHeap` sub-allocations.

**The benefit.** Heap-backed sub-allocation reduces **allocation churn and driver overhead**, not just per-call latency. The Metal driver bookkeeps every distinct `MTLBuffer` it allocates (lifetime tracking, residency hints, hazard-tracking metadata); a heap collapses N transient buffers' worth of bookkeeping into a single resource. The v5.8 per-tile fused dispatch creates ~15 transient buffers per (tile, component); a heap reduces this to one resident heap that's reset between decodes, with sub-allocations that are ~free at the driver level.

**Sizing.** Heap size must consider **peak tile usage** — for the largest fixture in the DICOM corpus (2800×2288 single-component), the v5.8 fused dispatch needs ~32 MB across all transient buffers; for 3 components scale to ~96 MB. Default heap size: `max(96 MB, peak-observed-resident)`, configurable on `J2KMetalSession`.

**Fallback path must remain.** When a request exceeds the heap budget (either single-allocation > heap free space, or unusually large tile), fall through to `device.makeBuffer` as today. The fallback must not be removed — heap-only would create cliff-edge failures on out-of-spec inputs.

**Alignment and reuse strategy.** Heap sub-allocations must respect Metal's `MTLHeapDescriptor.size` alignment requirements (typically 16 KB on Apple Silicon). The reuse strategy needs to avoid fragmentation — a per-decode reset (heap fully freed when decode completes) is the simplest correct policy and matches the v5.8 fused-dispatch lifetime. More aggressive sub-buffer reuse during a single decode (rather than per-decode) is a v5.12+ optimisation if profiling justifies it.

**Risks.**

- Heaps require Apple Silicon (`MTLDeviceSupportsFamily(.apple4)` or later — every M-series). Discrete-GPU Macs (Intel/AMD) need the device-allocator fallback.
- Sizing wrong → fallback path; sizing too large → wastes resident memory.
- Per-decode reset means the heap holds memory for the duration of a decode; for very long-lived sessions across many decodes, that's strictly less than alternative heap-grow strategies, but worth measuring.

**Verification.**

- Bit-exactness preserved on the corpus.
- Instrumentation: `makeBufferCount` drops to ~the number of heap allocations + fallback allocations only (single-digit per decode, vs ~15+ today).
- Perf comparison: heap-vs-device allocation perf measured at multiple sizes.

**Wall-clock.** ~3 days (new pool actor + integration + size-sweep perf measurement).

## Sequencing

| Milestone | Wall-clock | Headline gate |
| --- | --- | --- |
| Instrumentation prerequisite | ½ day | Counters wired; baseline numbers reported |
| v5.9 — Zero-copy boundary | 3 days | Bit-exact corpus; `memcpyCount` → 0 on hot path |
| v5.10 — Storage-mode pass | 2 days | Bit-exact corpus; `.contents()` count = 0 on private buffers; ≥5% warm speedup |
| v5.11 — `MTLHeap` pool | 3 days | Bit-exact corpus; `makeBufferCount` drops by ≥10× per decode |

Each milestone independently mergeable. Main stays releasable throughout.

## Out-of-scope-but-tracked

- **Encode-side UMA pass.** The encoder's GPU MCT and DWT have similar `.storageModeShared` patterns and `Array`-based pipeline boundaries. Out of scope for this detour (decode is the read path that gets exercised in production); revisit when encode perf surfaces as a bottleneck.
- **JP3D Metal paths.** Same observation; revisit alongside the JP3D-beats-OpenJPEG work tracked separately.
- **`.metallib` bundling.** Still wired but dormant since v5.6. Independent from UMA; resumes in v5.12+.

## Return path — resuming v5.12+

After v5.11, the previously-queued items move forward in their original order:

1. **v5.12** — Multi-tile in-flight command buffers (overlap CPU prep of tile N+1 with GPU decode of tile N)
2. **v5.13** — GPU colour transform / DC offset fusion (full-pipeline GPU residency past the DWT)
3. **v5.14** — 9/7 irreversible (lossy) DWT fusion
4. **v5.15** — `.metallib` bundling for cold-CLI wins (requires Metal Toolchain in build env)

## Verification gates (every milestone)

1. **Bit-exactness preserved** — all existing tests pass byte-for-byte. The corpus gate (`testFullDICOMCorpus_GPUHTMatchesCPUHT`, 7 fixtures) is the canonical check.
2. **Cross-codec matrix unaffected** — `Scripts/run_cross_matrix.sh --check` continues to pass 147/147.
3. **No regression on the v5.7.0/v5.8 warm-process baseline** — the perf measurement runs at every milestone and is reported in release notes alongside the new numbers.
4. **Instrumentation counters trend in the right direction** — `memcpyCount`, `makeBufferCount`, and `bufferContentsAccessCount` reported in every release; targets above must be hit.

## Why not just "do all three at once and ship as v5.9"?

Each milestone is independently bit-exactness-gated, and isolating them lets us pin perf wins to specific changes. Doing them as one merge commit conflates causes — when the corpus speedup goes from 1.5× to 1.7× we wouldn't know whether to attribute the delta to zero-copy, private storage, or heap allocation. The release cadence we've been on (one merit-named release per architectural step) is already serving the project well; this detour follows the same pattern.

The reordering matters too: zero-copy first (v5.9) makes the storage-mode rule (v5.10) mechanically enforceable rather than just a code-review aspiration, and creates the conditions where heap allocation (v5.11) actually reduces allocator pressure rather than just shuffling it. Doing them in any other order would land smaller wins per step.
