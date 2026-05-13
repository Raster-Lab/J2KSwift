# v8.0.0 Strategy — Metal-first, Apple Silicon target

**Status**: RFC. Strategy artefact only — no implementation in this PR.
**Captured**: 2026-05-09, post-v7.5.1 hotfix.
**Branch**: long-running `v8-metal-first` (this RFC lives on `v8-metal-first-strategy`).

---

## TL;DR

Pivot the J2KSwift release line to **Metal-first, Apple Silicon-targeted**. Drop the cross-platform / general-CPU framing of v7.x and concentrate the next major release's engineering on **beating Kakadu's HT decode wall on M-series hardware** in CLI-warm and in-process modes. The defensible marketable claim becomes: **"fastest JPEG 2000 codec on Apple Silicon."**

CPU paths remain functional as fallbacks, but stop receiving optimisation budget. The v7.6 RFC (CPU bit-parallel prefix-scan, PR #376) is superseded by this strategy and should close.

---

## 1. Why pivot now

Across v7.4 + v7.5 the codec hot-path lever-ceiling on Apple M2 + Swift release became empirically clear:

| experiment | DX A/B Δ | accepted? |
|---|---:|:-:|
| v7.4 Phase 1 — NEON `readQuadSamples` reconstruction | 0.90 ms | ✗ flag |
| v7.4 Phase 2 — SWAR 4-byte MagSgn refill | **3.70 ms** | **✓ default ON** |
| v7.4 Phase 3 — SWAR 4-byte VLC refill | noise | ✗ flag |
| v7.5 Phase 0 — Forward HT GPU entropy | −22.4 ms (worse) | ✗ flag |

Three of four "easy" levers rejected, one accepted for a 5.9 % wedge. The remaining CPU-side levers — bit-parallel prefix scan (v7.6 RFC), C-bridged hand-tuned NEON intrinsics — are **multi-week prototypes with uncertain payoff** and would still leave the Kakadu gap structural.

**Marketable framing**: "we're 25 % off OpenJPH and 2× off Kakadu, on a pure-Swift codec, on Apple Silicon" is not a sales pitch. **"Fastest JPEG 2000 codec on Apple Silicon"** is. That requires beating Kakadu specifically on the platform J2KSwift already runs on natively, and it requires GPU not CPU.

---

## 2. Where we actually are vs Kakadu (CLI-warm)

From the user's external eval matrix (`/Users/raster/J2KSwift-Evaluation/results_4codec_20260509_183147.csv`, 2026-05-09):

| fixture | J2KSwift HT CPU | J2KSwift HT GPU | **Kakadu HT** | gap (CPU-best) |
|---|---:|---:|---:|---:|
| ct 512² | 66 ms | 172 ms | **10 ms** | **6.6×** |
| mr 886² | 65 ms | 108 ms | **11 ms** | **5.9×** |
| xa 1024² | 78 ms | 145 ms | **13 ms** | **6.0×** |
| px 2459×1316 | 108 ms | 237 ms | **19 ms** | **5.7×** |
| dx 2544×3056 | 147 ms | 280 ms | **34 ms** | **4.3×** |
| mg 3520×4784 | 264 ms | 242 ms | **58 ms** | **4.2×** |

**The reality is harsher than v7.4 in-process numbers suggested.** The CLI-warm gap is 4-7× behind Kakadu, not the 2.10× from the in-process DX measurement. The difference is:
- CLI startup / process-spawn cost
- Cold metallib load
- File I/O (reading PGM, writing PGM)
- Components J2KSwift pays per-invocation that Kakadu's binary doesn't

Some of those are addressable; some aren't. The strategy below picks the ones that are.

Notable observation from the table: **GPU is currently SLOWER than CPU on every fixture in CLI-warm mode**. The in-process `decodeWithGPUHT` 4.6× win at 17 M px (per v5.28.0 memory) doesn't translate to CLI invocations because cold-start dominates. The Metal-first pivot has to address this directly.

---

## 3. Win condition

**Primary**: J2KSwift on M-series ≤ Kakadu on M-series for HT-conformant lossless decode wall, all 6 corpus fixtures, **CLI-warm mode** (the user-facing observable). Headline: published in `RELEASE_NOTES_v8.0.0.md` with a fresh eval matrix table.

**Secondary** (if achievable in v8 scope): J2KSwift HT encode wall ≤ Kakadu HT encode wall on M-series, same fixtures.

**Tertiary** (stretch): J2KSwift Part-1 (EBCOT) decode ≤ Kakadu Part-1 decode on M-series.

**What we will NOT claim**: "fastest JPEG 2000 codec globally." This is intentional — Kakadu's x86 hand-tuned AVX-512 path will beat us on Linux / Windows servers, and that's fine. The marketable claim is platform-specific.

---

## 4. What changes in scope

### Continues
- HT-conformant lossless decode + encode (the medical archive product target)
- JP3D slice-stack codec (51/51 medical-grade matrix, already wins on Apple Silicon)
- Bit-exact correctness with OpenJPH / Grok / Kakadu (cross-codec parity matrix is a permanent gate)
- Mandatory commit gate (now extended to include `MgRegressionTriageTest` per v7.5.1)

### De-prioritised / parked
- **CPU NEON optimisation work** (v7.4 Phase 2 stays shipped; no further phases)
- **v7.6 RFC** (#376) — bit-parallel CPU prefix-scan: closed as superseded
- **Generic / cross-platform CPU framing** — code keeps building / passing on Linux for downstream consumers (DICOMKit), but Linux is not a perf target
- **`fix/multitile-batched-24bit-overflow` branch** — work is valid (3% wedge on DX 2x2) but de-prioritised; the v7.5.1 hotfix path is the safe default and the wedge it gives up is < 1 % of the Kakadu gap

### Becomes the focus
- **Metal kernel work**: HT cleanup-pass, IDWT, MCT, dequant, scatter — every stage that touches sample data
- **Cold-start elimination**: `preWarm()` extension, persistent metallib, CLI invocation fast-path
- **In-process / CLI parity**: the same Metal session reused across CLI invocations of `j2k decode`
- **Apple Silicon-specific tuning**: M2/M3/M4/M5 dispatch probes, threadgroup-memory layouts, tile-memory exploitation, UMA-aware batching

---

## 5. Phase breakdown (high-level — each phase gets its own RFC PR)

Each phase is gated by a measured improvement on the win-condition matrix. Carry-over of the v7.4 staged-NEON discipline: numbers ship before the default flips.

### Phase 0 — Honest baseline + bottleneck identification (1-2 weeks)

**Question**: where does the 4-7× CLI-warm gap actually live?

**Method**:
1. Reproduce the user's eval matrix locally on M-series with current main.
2. Add stage-level timing to the CLI decode path: process-startup, file-read, codestream-parse, entropy, IDWT, dequant, write-output.
3. Compare per-stage breakdown vs Kakadu's `kdu_expand` (instrument via wall-time around the binary and flame-graph if needed).
4. Identify the 1-2 dominant stages of the gap.

**Deliverable**: `V8_0_0_PHASE_0_BASELINE.md` with the per-stage breakdown and a ranked list of attack candidates.

**Bail-out**: if the gap is dominated by something fundamentally unfixable (e.g., Kakadu uses a proprietary algorithm we can't replicate without licence), document and exit. This RFC's PR opens with a list of suspect stages, but only Phase 0 measurement decides which is real.

### Phase 1 — Cold-start elimination for CLI (1 week)

**Hypothesis**: a meaningful fraction of CLI-mode wall time is the metallib + Metal device cold-start that gets paid every CLI invocation. v5.28.0's `preWarm()` saved 25-30 ms in-process but isn't called in the CLI's first-decode path.

**Method**: persistent Metal session shared across CLI invocations (via XPC daemon, or a long-lived `j2k` server mode). Or: pre-compile the metallib to an Apple-Silicon-optimised binary embedded in the CLI binary and skip dynamic load.

**Deliverable**: `V8_0_0_PHASE_1_COLD_START.md` + new CLI mode + measurements.

### Phase 2-N — Stage-by-stage Metal acceleration

Sequence depends on Phase 0's ranking. Likely candidates in priority order based on current state:

- **HT cleanup-pass kernel optimisation** — current kernel works (`J2KMetalHTCleanup`) but threadgroup layout, register usage, and buffer-pool integration are first-pass. Apple-specific tuning probably gets 2-4× on this kernel.
- **Inverse DWT 5/3 INT** — current Metal path is bit-exact (v5.21.0 fix) but per-level dispatch overhead may dominate. Multi-level-fused IDWT (v5.25.0 pattern, 9/7 lossy) for 5/3 INT lossless.
- **MCT + DC-shift Metal kernel** — currently CPU. Tiny win individually but a stage-merge with IDWT eliminates a host round-trip.
- **Cross-tile dispatch amortisation** — re-attempting the v7.2.0 PR #356 idea but this time with the 24-bit overflow root-caused (currently parked on `fix/multitile-batched-24bit-overflow`). Becomes Phase N when its parent Phase ships.
- **Encoder forward path** — re-examine GPU encode (v5.29.0 regression, v7.5 forward HT GPU rejection). Apple Silicon-specific Metal-first redesign might invert what was rejected.

Each Phase ships as its own PR with the v7.4 acceptance discipline: ≥ measurable improvement on the win-condition matrix before merge.

### Phase Final — Release v8.0.0

Trigger: enough phases shipped that the win condition is met on at least the headline DX fixture and ideally most of the corpus.

---

## 6. SemVer + branding

**Bump**: MAJOR. Per RELEASING.md §Versioning:
- "Default behaviour flipped" — Metal becomes the default routing on Apple Silicon for decode (and possibly encode), where currently it's a per-fixture-size threshold gate.

**Codestream bytes**: byte-identical to v7.5.1 (no encoder change yet; encoder may shift in later v8.x).

**Branding**:
- README headline: "Fastest JPEG 2000 codec on Apple Silicon"
- Sub-headline: "Native Metal acceleration on M-series; cross-platform CPU fallback for Linux / x86_64"
- Release notes lead with the Kakadu-comparison matrix on M-series (not on the 6.4 MP DX in-process number that we've been optimising for since v7.0.0)

---

## 7. Open questions for review

These are the strategic calls I'd like you to make before Phase 0 starts:

1. **Cross-platform support level**: should v8.0.0 keep building / running on Linux x86_64 for DICOMKit's CI and other consumers? My recommendation: yes — keep it building, but explicitly mark Linux performance as best-effort. The downside cost is small; the upside (DICOMKit downstream gate stays green) is real.

2. **Encode in scope?**: the win condition above lists encode as "secondary if achievable." Encode's CLI gap to Kakadu is also large (4-9×), but the v7.5 forward HT GPU work was rejected as structurally hostile. Do we re-attempt it in v8 with Metal-first reframing, or punt encode to v8.x?

3. **CLI vs in-process target**: the user's eval matrix is CLI-mode, the in-process measurements are different. Do we target both, or just one? My recommendation: lead with CLI-warm (most observable to users) but report both. If CLI-warm gap closes, in-process gap closes by definition.

4. **Branch model**: `v8-metal-first` long-running branch where each phase RFC merges, then `v8-metal-first` merges to main as v8.0.0? Or each phase merges directly to main and v8.0.0 cuts when win-condition is met? My recommendation: each phase merges to main (smaller blast radius, matches v7.4/v7.5 staged discipline). The `v8-metal-first` long-running branch is a tracking pointer, not the merge target.

5. **Disposition of v7.6 RFC #376 and `fix/multitile-batched-24bit-overflow`**: I'll close #376 as superseded by this strategy and park the 24-bit overflow branch (kept available, not actively worked). Confirm or override.

6. **Hardware target**: M2/M3/M4/M5 all? Just whatever the user has? Apple Silicon includes A-series (iPad / iPhone) — is iOS/iPadOS in scope or just macOS? My recommendation: M-series macOS only for v8.0; A-series + iOS as v8.x stretch. The Metal API is the same but threadgroup limits / GPU core counts differ enough that "fastest on Apple Silicon" without further qualification overpromises.

---

## 8. What lands in *this* PR (RFC, strategy only)

- This document (`V8_0_0_METAL_FIRST_STRATEGY.md`).
- Disposition note: PR #376 (v7.6 RFC) closes as superseded when this RFC is approved; `fix/multitile-batched-24bit-overflow` branch parks pending Phase 0 ranking.

What does **not** land:
- Any code changes. This is a strategic decision artefact for review before Phase 0 begins.

When this RFC is approved (merged to `main`), Phase 0 starts on `v8-phase-0-baseline-measurement`.

---

## 9. Honest framing — risks + commitments

This pivot is not free:
- **Multi-major-version horizon**: closing a 4-7× Kakadu gap on Apple Silicon is plausible but multi-quarter. v8.0.0 may not fully close it; v8.1 / v8.2 may be needed.
- **Apple lock-in trade-off**: Linux + Windows users get a slower codec. Acceptable if J2KSwift's primary consumers (DICOMKit, Apple-platform medical imaging) don't need x86 perf, painful otherwise.
- **Kakadu has 25 years of head start**: even on Apple Silicon, Kakadu's algorithmic + data-structure tuning is mature. Catching it requires both Metal smarts AND attention to the 80 % of the codec that isn't on GPU.
- **The marketable claim depends on benchmarks holding up**: we need our own benchmark methodology to be reproducible and our numbers to be defensible. Phase 0's measurement work is therefore the load-bearing first step.

The commitment back is the v7.4 / v7.5 staged-NEON discipline: pre-committed gates, honest measurements, perf-wash releases when nothing pans out, and explicit close-out when a phase doesn't clear the bar. The Metal-first pivot doesn't give up that discipline — it just changes the target the discipline is pointed at.
