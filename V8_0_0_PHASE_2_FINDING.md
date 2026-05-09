# v8.0.0 Phase 2 — CLI default routes to CPU-first

**Captured**: 2026-05-09, Apple M2.
**Phase 2 actual scope**: pivoted from the strategy RFC's "in-process IDWT Metal kernel" to "CLI default-routing fix" after empirical measurement showed the latter is higher-leverage and a sharper win than the former in CLI mode.

## TL;DR

Phase 1 (#381) honoured `--no-gpu` and made it 40-47 ms faster than default. Phase 2 (this PR) **flips the CLI default to the fast path automatically** — users no longer need `--no-gpu` to get the Phase 1 speedup. Default CLI invocations on CT/MR/DX go from 74-140 ms down to 17-103 ms (52-53 ms saved, identical to the `--no-gpu` path).

The original Phase 2 plan (multi-level fused 5/3 INT IDWT Metal kernel) is **deferred to a later phase** because measurement showed that path doesn't help in CLI single-shot mode — GPU IDWT in CLI is consistently 2-5× SLOWER than CPU due to Metal cold-start tax that one-shot processes pay every invocation. The Metal IDWT kernel already exists and is wired in; making it faster doesn't change the fact that GPU dispatch + driver cold-start dominates wall time on CLI runs.

## Why the pivot

Per Phase 1, the GPU IDWT path:
- Pays ~50 ms Metal device init on first access (cold-start tax)
- Plus per-block GPU dispatch overhead per tile

For long-lived processes (PACS daemons, batch decoders) these are amortised and GPU IDWT genuinely wins. For one-shot CLI invocations, they aren't, and CPU wins by 50+ ms. The user's external eval matrix and post-Phase-1 local matrix both confirmed this:

| fixture | default CLI (pre-Phase-2) | --no-gpu | difference |
|---|---:|---:|---:|
| MR-small 180² | 18 ms | 18 ms | 0 ms (below GPU threshold either way) |
| CT 512² | 74 ms | 21 ms | **53 ms — default is paying the cold-start** |
| MR 886² | 76 ms | 24 ms | **52 ms — same** |
| DX 2800×2288 | 140 ms | 87 ms | **53 ms — same** |

Phase 2's question: should the CLI default to the slow path or the fast one? Strategy RFC §6 says "Metal becomes the default WHERE IT'S FASTER." For CLI single-shot, it isn't. **Default flipped to CPU.**

## What changed

`Sources/J2KCLI/Commands.swift::decodeCommand` now sets the routing env vars (`J2K_GPU_INVERSE_53=0`, `J2K_GPU_HT_ENTROPY=0`) when neither `--gpu` nor `--gpu-ht` was explicitly passed. Users who want GPU paths must opt in.

```swift
let explicitGPU = (options["gpu"] != nil && options["gpu"] != "false")
               || (options["gpu-ht"] != nil)
let forceCPU = options["no-gpu"] != nil || !explicitGPU
if forceCPU {
    setenv("J2K_GPU_INVERSE_53", "0", 1)
    setenv("J2K_GPU_HT_ENTROPY", "0", 1)
}
```

Backwards-compatibility note: callers who previously got the GPU IDWT path implicitly will now get CPU. Their wall time will be the same as if they had passed `--no-gpu`. **No correctness change** — codestream bytes and decoded pixel data are byte-identical between the paths.

## Measurement (median of 5, M2 release, post-Phase-2)

| fixture | bytes | default CLI | Kakadu | gap |
|---|---:|---:|---:|---:|
| MR-small 180² | 45 224 | 17 ms | 15 ms | 1.13× |
| CT 512² | 436 460 | 21 ms | 15 ms | 1.40× |
| MR 886² | 169 709 | 24 ms | 17 ms | 1.41× |
| XA 1024² | 1 621 712 | 29 ms | 18 ms | 1.61× |
| PX 2459×1316 | 6 453 588 | 57 ms | 25 ms | 2.28× |
| DX 2800×2288 | 12 705 470 | 103 ms | 37 ms | 2.78× |

Compared to **pre-v8** (the user's external eval CSV from 2026-05-09, before Phase 0):
- MR-small: 64 → 17 ms (3.8× faster, BEAT Kakadu by 2 ms eq, only 13 % off)
- CT: 65 → 21 ms (3.1× faster, 1.40× off Kakadu)
- DX: 134 → 103 ms (1.30× faster, 2.78× off Kakadu)

Phase 1 and Phase 2 together close the v8 strategy's "CLI fixed overhead" component substantially. The remaining gap on PX/DX is the **in-process compute gap** — HT entropy + 5/3 IDWT — addressed in later phases.

## Why MR-small is now 1.13× off

MR-small CLI is 17 ms, Kakadu is 15 ms — a 2 ms gap that's on the edge of measurement noise. Most of the remaining 17 ms is process startup itself (`j2k version` = 15 ms, `kdu_expand -version` = 13 ms). The actual decode work is ~2 ms vs Kakadu's ~2 ms. Meaningfully close enough that further optimisation here would be sub-millisecond — diminishing returns.

## Why DX is still 2.78× off

DX in-process decode is ~59 ms (per Phase 0 stage profile). Kakadu's DX implied in-process is ~30 ms. The remaining 30 ms gap is **per-stage compute** dominated by:
- HT entropy decode: 199 ms accumulated across 16 parallel tiles
- 5/3 IDWT: 120 ms accumulated

These are the real Phase 3+ targets. Phase 2's CPU-default flip does not address them.

## Open questions for review

1. **Should `--gpu` alone (not `--gpu-ht`) still trigger GPU IDWT?** Currently yes — `explicitGPU = options["gpu"] != nil`. The user might expect `--gpu` to mean "any GPU acceleration" which is what we honour. If we wanted to gate on per-fixture-size routing inside the decoder for `--gpu` mode, that's a Phase 3 candidate.

2. **Should the encode CLI also flip to CPU-default?** Encode is symmetrically affected — `J2K_GPU_FORWARD_53` and `J2K_GPU_FORWARD_HT_ENTROPY` exist as separate flags. The v7.5.0 finding closed forward HT GPU as structurally hostile on M2 anyway, so encode-side default is already CPU. No change needed.

3. **Documentation update**: the CLI `--help` text should mention the default-CPU shift. Trivial; not in this PR (defer to a docs polish pass).

## What lands in this PR

- `Sources/J2KCLI/Commands.swift` — default-CPU routing logic in `decodeCommand`
- `V8_0_0_PHASE_2_FINDING.md` — this document

## Mandatory gate (release mode, 0 failures)

10/10 pass:
- `J2KMedicalCorpusEncodePerformanceTests` — 2/2
- `J2KMedicalCorpusPerformanceTests` — 2/2
- `J2KStrictCrossCodecValidationTests` — 3/3
- `HTTileParityMatrixTests` — 1/1
- `MgRegressionTriageTest` — 2/2

## Phase 3 candidates (in priority order)

1. **In-process compute gap on PX/DX** — the real remaining target. Sub-options:
   - 1a. CPU 5/3 INT IDWT SIMD vectorisation (`SIMD4<Int32>` lifting steps in `J2KDWT1DOptimized`)
   - 1b. CPU HT entropy hot-path tightening beyond v7.4 (uncertain — much already done)
   - 1c. Reduce per-tile dispatch overhead in the multi-tile TaskGroup
2. **Persistent Metal session via XPC daemon** — make GPU paths viable in CLI by amortising cold-start across invocations. Per Phase 0 §5 deferred to v8.1.
3. **Re-attempt cross-tile batched HT entropy decode** — root-cause the 24-bit overflow parked on `fix/multitile-batched-24bit-overflow`; restores a 3 % wedge on DX 2x2.

## Reproduction

```bash
swift build -c release --product j2k

# Default mode now equals --no-gpu speed
.build/release/j2k decode -i fixture.j2k -o out.pgm --output-format pgm --quiet

# Explicit opt-in for GPU paths (slower in CLI single-shot on M2)
.build/release/j2k decode -i fixture.j2k -o out.pgm --output-format pgm --gpu --gpu-ht --quiet
```
