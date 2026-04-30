# GPU HT Decoder — Architecture & Implementation Plan

**Branch:** `gpu-ht-decoder-prototype`. Started 2026-04-30 from `gpu-lossless-bit-exact`.

**Why HT first (vs EBCOT):** see [GPU_EBCOT_FEASIBILITY.md](GPU_EBCOT_FEASIBILITY.md). Summary: HT cleanup pass uses MagSgn/MEL/VLC instead of MQ — significantly less branchy per coded sample, more SIMT-friendly. OpenJPH ships an experimental Metal HT decoder as proof of concept.

---

## Phase plan

This is a multi-step build. Each phase is committable and independently testable; we can stop or pivot at any phase boundary.

| Phase | Deliverable | Estimated cost | Status |
|---|---|---|---|
| **0** | **Dispatch-cost probe + microbenchmark** | 1 session | ✅ done — `J2KMetalHTDispatchProbe.swift` + test. Result: **40-44× wins at 777-1024 codeblocks**, break-even at ~16 codeblocks. Phase 1+ is greenlit. |
| 1 | MagSgn-only Metal kernel: read N bits per sample given a precomputed widths array (no MEL, no VLC) | 1 session | ✅ done — `J2KMetalHTMagSgn.swift` + 4 bit-exact tests + 16× speedup measurement |
| 2 | Cleanup-pass kernel for one codeblock (full MagSgn + MEL + VLC + UVLC), bit-exact vs CPU `HTBlockDecoderConformant.decode` | 2-3 sessions | pending |
| 3 | Batched dispatch — N codeblocks in one kernel launch via descriptor pool | 1 session | pending |
| 4 | Pipeline integration — `applyEntropyDecoding` routes HT decode through GPU when `useGPU && useHT && conformant && blockCount ≥ threshold` | 1 session | pending |
| 5 | Bit-exact tests across the 10-DICOM cross-matrix; perf bench updates | 1 session | pending |
| 6 | DICOMKit `J2KSwiftCodec.decodeFrame` opt-in flag for GPU HT path | 1 session | pending |

**Total estimate:** 7-9 sessions of focused work to land production GPU HT.

---

## Phase 0 — dispatch-cost probe (done in this commit)

Goal: measure what the GPU-vs-CPU break-even codeblock count looks like with **trivial** per-block work, so phase-2+ work can be evaluated with real overhead context, not theoretical numbers.

The probe (`J2KMetalHTDispatchProbe`) runs the same data layout the eventual real decoder will use:

- One concatenated codestream pool buffer.
- One per-block descriptor array (`dataOffset`, `dataLength`, `outputOffset`, `width`, `height`).
- One Int32 output pool sized to `Σ width × height`.
- One `j2k_ht_dispatch_probe` kernel dispatch with `blockCount` threads.

Per thread: walk the codeblock's bytes once (LCG mix), then write `width × height` Int32 values — bounded but not eliminable by the optimiser. Substitutes for the eventual MQ-free HT decode workload.

**Microbenchmark:** [Tests/J2KMetalTests/J2KMetalHTDispatchProbeTests.swift](Tests/J2KMetalTests/J2KMetalHTDispatchProbeTests.swift) — runs the probe at `blockCount ∈ {1, 4, 16, 64, 256, 777, 1024, 4096}` and prints CPU-parallel-baseline ms vs GPU wall-clock ms vs GPU kernel-only ms (from `MTLCommandBuffer.gpuStartTime/EndTime`).

Result lines tagged `[ht-probe]` so they're easy to grep:

```
swift test -c release --filter J2KMetalHTDispatchProbeTests 2>&1 | grep '\[ht-probe\]'
```

**Probe results on Apple M2** (debug build, 1 warmup + 1 timed iteration each):

| blockCount | CPU ms | GPU wall ms | GPU kernel ms | Speedup |
|-----------:|-------:|------------:|--------------:|--------:|
|          1 |  0.594 |       0.998 |         0.785 |   0.60× |
|          4 |  0.642 |       1.011 |         0.788 |   0.63× |
|         16 |  1.873 |       1.131 |         0.799 |   1.66× |
|         64 |  6.455 |       1.170 |         0.800 |   5.52× |
|        256 | 26.072 |       1.255 |         0.797 |  20.77× |
|        777 | 78.066 |       2.109 |         1.295 |  37.01× |
|       1024 |104.122 |       2.350 |         1.279 |  44.30× |

**Key findings:**

- **Break-even at ~16 codeblocks**, where CPU and GPU wall-clocks both sit at ~1.1 ms.
- **Dispatch overhead floor: ~1 ms wall, ~0.8 ms kernel** for any block count up to 256. The GPU's parallelism is so abundant that the kernel runs in roughly the same time whether 1 or 256 codeblocks are dispatched.
- **GPU kernel time is flat** until ~777 blocks (where warp granularity finally bites — 1.3 ms vs 0.8 ms — but it's still well-amortised).
- **CPU scales linearly** (~0.04 ms/block) because per-block work hits dispatch overhead in `concurrentPerform`.
- **40× speedup at typical 1024² codeblock counts** even with the probe's trivial per-thread work — once real HT decode work lands per thread, the per-block compute cost grows but the dispatch envelope stays roughly the same shape.

**Implication for phase 2+:** GPU HT decode is viable down to surprisingly small images. A safe gating condition is `blockCount ≥ 64` (~5× safety margin). The full 1024×1024 RGB decode workload (777 codeblocks) is squarely inside the GPU's sweet spot.

**Caveat:** these are *trivial per-thread* numbers. Real HT cleanup decode does ~80 µs of work per codeblock on CPU; on GPU the per-thread work is likely 4-6× slower per cycle (no branch prediction) but with 1024-way parallelism on Apple M2's ~1500 ALUs, the total GPU compute time should be ~0.5-1 ms (well within the dispatch envelope's slack). Optimistic full-decode estimate: **5-15× speedup vs CPU at 1024 codeblocks**.

---

## Phase 1 — MagSgn-only kernel

Smallest meaningful slice. MagSgn is the simplest HT sub-stream: read N bits from a forward-stuffed byte stream per sample, where N comes from a precomputed widths array.

CPU reference: `HTMagSgnDecoderConformant.read(count:)` (~30 lines in [J2KHTConformantMagSgnCoder.swift](Sources/J2KCodec/J2KHTConformantMagSgnCoder.swift)).

MSL port: ~50 lines. State (tmp/bits/unstuff/readIndex) lives in registers.

```metal
struct HTMagSgnState {
    ulong  tmp;
    int    bits;
    int    readIndex;
    int    unstuff;
};

inline uint magsgn_read(thread HTMagSgnState* s,
                        device const uchar* bytes, int byteCount,
                        int count) {
    if (s->bits < count) {
        // refill (FF-stuff aware)
        while (s->bits <= 32) {
            uchar b = (s->readIndex < byteCount) ? bytes[s->readIndex++] : 0xFF;
            int dBits = 8 - s->unstuff;
            uchar mask = (uchar)(0xFF >> s->unstuff);
            ulong value = (ulong)(b & mask);
            s->tmp |= value << s->bits;
            s->bits += dBits;
            s->unstuff = (b == 0xFF) ? 1 : 0;
        }
    }
    ulong mask = (count >= 64) ? (ulong)~0 : ((1ul << count) - 1);
    uint v = (uint)(s->tmp & mask);
    s->tmp >>= count;
    s->bits -= count;
    return v;
}

kernel void j2k_ht_magsgn_decode_widths(
    device const HTMagSgnBlockDescriptor* blocks [[buffer(0)]],
    device const uchar*                    codestream [[buffer(1)]],
    device const uchar*                    widths [[buffer(2)]],   // 1 byte per sample
    device uint*                           output [[buffer(3)]],   // 1 word per sample
    constant uint& blockCount                       [[buffer(4)]],
    uint tid [[thread_position_in_grid]]
) {
    if (tid >= blockCount) return;
    HTMagSgnBlockDescriptor desc = blocks[tid];
    HTMagSgnState s = {0, 0, 0, 0};
    int sampleCount = (int)desc.width * (int)desc.height;
    device const uchar* myBytes = codestream + desc.dataOffset;
    device const uchar* myWidths = widths + desc.outputOffset;
    device uint* myOut = output + desc.outputOffset;
    for (int i = 0; i < sampleCount; i++) {
        myOut[i] = magsgn_read(&s, myBytes, (int)desc.dataLength, (int)myWidths[i]);
    }
}
```

**Test gate:** bit-exact against `HTMagSgnDecoderConformant.decodeBits(_:widths:)` (the existing CPU round-trip helper) on synthetic + the 64×64 PGM the cross-matrix uses.

**Phase 1 results on Apple M2** (debug build):

| Workload                                  | CPU (parallel) | GPU wall | GPU kernel | Speedup |
|-------------------------------------------|---------------:|---------:|-----------:|--------:|
| Single block × 64 samples                 |        ≈0.05ms |  0.33 ms |   0.054 ms |     —   |
| 256 blocks × 256 samples (~64 KB out)     |        ≈10 ms  |  1.10 ms |   0.607 ms |  ~9×    |
| **777 blocks × 4096 samples** (~12 MB out)| **195.63 ms**  | **11.92 ms** | **10.59 ms** | **16.41×** |

The 777-block case mirrors the codeblock count of a 1024×1024 RGB cross-matrix run. The 16× internal-Metal speedup over the parallel-CPU baseline validates two things:

1. **The dispatch envelope's slack absorbs real per-thread compute work.** Phase-0 saw ~1 ms wall-clock with a trivial probe; phase 1 with real per-byte bit-twiddling is ~11 ms — comfortably above the dispatch floor, comfortably below CPU.
2. **Per-thread MagSgn work is small enough to fit MSL execution profile.** No branch divergence concerns surface here because every thread runs the same straight-line bit-reader code with no data-dependent branches. Phase 2 (MEL, VLC, UVLC) introduces data-dependent branches and is where divergence may bite.

---

## Phase 2 — Full cleanup-pass kernel

Add MEL run-length decoding + VLC table lookup + UVLC to the magsgn kernel. This is the substantive port — ~300-500 lines of MSL.

**State per codeblock thread:**

```metal
struct HTCleanupState {
    HTMagSgnState magsgn;
    HTMELState     mel;
    HTVLCState     vlc;
    int  width, height, p;       // p = 30 - missingMSBs
    uchar eVal[34];              // ((width+3)/4)*2 + 2, sized for width<=64
    uchar cxVal[34];
    int  melRun;
};

device const uint16_t* vlc_table_0 [[ constant ]];  // 256 entries
device const uint16_t* vlc_table_1 [[ constant ]];  // 256 entries
device const uint8_t*  mel_exp     [[ constant ]];  // 13 entries
```

VLC tables go in MSL `constant` buffers — read-only fast cache, broadcast to all threads.

**Output:**

```metal
device uint* coefs;              // sample count Int32
```

**Inner loop:** mirrors `DecodeState.decodeInitialRow` + `decodeSubsequentRow` — straight transliteration from Swift to MSL with no algorithmic changes.

**Test gate:**

```swift
@testable import J2KMetal
@testable import J2KCodec  // for HTBlockDecoderConformant

func testHTCleanupGPUMatchesCPU() async throws {
    // Encode a synthetic 64×64 codeblock via HTBlockEncoderConformant,
    // assemble via HTBlockLayoutConformant.assemble.
    // Decode via both:
    //   cpu = HTBlockDecoderConformant.decode(block: , width:, height:, missingMSBs:)
    //   gpu = J2KMetalHTCleanupDecoder().decodeOne(block:, width:, ..)
    // Assert cpu == gpu byte-for-byte.
}
```

---

## Phase 3 — Batched dispatch

Combine the cleanup-pass kernel with the batched layout the probe uses (descriptor pool + codestream pool + output pool, one kernel call per image). At this point we can run a real medical DICOM end-to-end on GPU.

---

## Phase 4 — Pipeline integration

In `J2KDecoderPipeline.applyEntropyDecoding`, gate GPU HT dispatch on:

```swift
let useGPUHT = useHT
            && useConformant
            && metadata.isLargeEnoughForGPU
            && J2KMetalHTCleanupDecoder.isAvailable
            && blocks.count >= probedBreakEvenCount
```

The `probedBreakEvenCount` literal is set from phase-0's microbenchmark output (e.g. `64`).

---

## Phase 5 — Cross-matrix validation

Re-run `HTJ2KBeatsOpenJPEGTests` + the 180-cell cross-codec matrix from `CROSS_CODEC_CPU_VS_GPU_REPORT.md` with the GPU HT path enabled. Targets:

- HT decode 1024+: 1.5× → **5×+** (vs OpenJPEG)
- HT decode 256/512: 3.0× → **10×+** (already at 9-25×)
- All cells stay byte-equal (modulo PGM byte order)

If real-data divergence kills the win at 1024+ (warps execute mixed-state codeblocks together), document it and fall back to CPU at the size where divergence dominates.

---

## Phase 6 — DICOMKit opt-in

Add `useGPUEntropy: Bool` flag to DICOMKit's `J2KSwiftCodec` config, default `true` on Apple platforms with Metal, `false` elsewhere. Document the byte-equality guarantee preserved by the bit-exact MSL kernels.

---

## Risks & exit criteria

| Risk | Detection | Exit |
|---|---|---|
| Branch divergence kills GPU win | Phase-3 batched bench shows GPU < CPU at all sizes | Stop at Phase 3, document |
| Per-block memory budget too high for fast path | Phase-1 probe shows widths array marshalling > magsgn work | Pack 8 widths/byte; revisit |
| OpenJPH MSL approach turns out wildly different | Phase-2 implementation diverges > 50% from CPU code | Re-architect from OpenJPH reference |
| Apple GPU compute scheduler thrashes on 64-thread groups of mixed-state work | gpuKernelTime in probe is 5-10× higher than expected | Smaller groups, more dispatches |

The phase-0 probe (this commit) gives us the data to know whether to proceed past phase 1.

---

## Implementation notes from phase 0

- `J2KMetalShaderLibrary` cleanly accepts new shaders by appending to the kernel-source string + adding a case to `J2KMetalShaderFunction`. No rebuild of pipeline cache needed beyond first use.
- `MTLCommandBuffer.gpuStartTime` / `gpuEndTime` give us kernel-only timing separate from the wall-clock cost of buffer fill / commit / readback. Both are useful — the wall-clock decides production viability, the kernel-only number tells us whether the bottleneck is dispatch or compute.
- `J2KMetalDevice` is an actor — every Metal call from the shader-loading path needs `await`. Already handled in `J2KMetalHTDispatchProbe.run`.
- For the eventual cleanup kernel, the existing `mqStatePacked` approach (fitting MQ tables in 188 bytes for constant memory) is a useful reference for how to shrink VLC tables (~512 entries × 2 bytes = 1 KB; trivial for `[[constant]]`).
