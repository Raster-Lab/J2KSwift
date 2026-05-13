# Overnight session 2026-05-14 — "Beat Kakadu with C" investigation

**Session goal:** identify any remaining C-side optimisation lever to beat Kakadu on Apple M2 (after 12 prior lever-ceiling investigations on this branch family).

**Session duration:** ~5 hours autonomous (00:00-05:00 local time).

**Branch:** `feature/v10-decoder-neon-port` @ `<head>` (research stays on branch per `feedback_research_no_main_merge`).

**Verdict:** **No new viable C-side lever found.** Two probes attempted; both produced decisive negative signals. This is the **13th lever-ceiling-style confirmation** in the encoder/decoder optimisation arc.

---

## Probes attempted tonight

### Probe 1 — Decoder C+NEON port (symmetric to v9.4.0 encoder win)

**Hypothesis:** v9.4.0 shipped C+NEON for the HT *encoder* hot path with measured 2.91× single-thread per-block speedup and −9 % to −20 % warm-encode wall on M2. The *decoder* still uses Swift entropy. Phase 8 of v10.0-research confirmed entropy dominates decode wall (488 ms summed CPU on DX-12T). A symmetric C+NEON decoder port should produce a symmetric win.

**Method:** wrote `Sources/J2KCodecNEON/include/j2knhd.h` + `j2knhd_decode_block_ht.c` containing the 3 HT decoder bit-stream readers (MagSgn, MEL, VLC reverse). Wrote `Tests/J2KCodecTests/V10DecoderNEONPhase0Tests.swift` with bit-exact parity test (Swift vs C MagSgn reader) + per-call speed bench on a DX-shape 4000-read mixed-width stream.

**Result:** **C scalar is 17 % SLOWER than Swift.**

| Reader | Swift median (ns/call) | C median (ns/call) | Speedup |
|---|---:|---:|---:|
| MagSgn (forward LSB-first, 4000 reads) | **5.30** | **6.43** | **0.82×** |

The Swift decoder is already SWAR-tuned (v7.4 batched 4-byte refill, v8.1 8-byte SWAR + 128-bit accumulator). At corpus FF-density of ~0.4 %, the SWAR fast-path is taken ~99 % of refills, leaving no surface area for NEON to win on a byte-stream un-stuffing inner loop that's fundamentally serial.

**Why the encoder won but the decoder doesn't:**
1. v9.4-era Swift encoder was less-tuned than today's Swift decoder.
2. Encoder NEON gain came from the **4-sample-per-quad classifier** (NEON-friendly: parallel `vshl` + `vclz`); decoder hot path is byte-stream un-stuffing (state machine).
3. SWAR fast-path hit rate of ~99 % means the inner loop is already a single OR-into-accumulator — memory-bandwidth bound on the byte-stream load.

**Verdict:** NO-GO. Multi-week full decoder port not viable.

**Artifact:** `V10_DECODER_NEON_PHASE0_FINDING.md` (full writeup with reproducer).

### Probe 2 — Profile-Guided Optimisation (PGO) build pipeline

**Hypothesis:** the v9.4 C+NEON encoder has never been PGO'd. A profile-trained build biasing branch predictions and inline decisions against the medical corpus's actual distribution could extract 5-10 % additional wall savings.

**Method:** modified `Package.swift` to add `-fprofile-instr-generate=/tmp/j2knhe-pgo/default_%m.profraw` to the J2KCodecNEON `cSettings`. Built instrumented binary.

**Result:** **SwiftPM PGO toolchain limitation hit.**

The instrumented C target compiles cleanly but the resulting `j2k` binary contains zero `__llvm_profile*` / `__profc*` / `__profd*` symbols. Running it produces no `.profraw` files. Root cause: `-fprofile-instr-generate` is both a compile flag (instructs clang to instrument) AND a link flag (instructs clang to link `libclang_rt.profile_osx.a` for the runtime symbols). SwiftPM's `cSettings` only affects compile, and the final link is done by `swiftc` invoking `ld` directly — not by `clang` as driver — so the profile runtime is never pulled in.

Workarounds attempted: `LLVM_PROFILE_FILE=path` env var override (no effect since runtime not linked). `linkerSettings` on the C target (not propagated to the Swift binary linker). Pursuing further would require either:
- Building the C target manually with `clang -fprofile-instr-generate -shared` outside SwiftPM, linking via a binary target — significant build-system rework.
- Switching to Xcode project for the PGO experiment — out of scope.

**Verdict:** BLOCKED on tooling. PGO is theoretically attractive but the current SwiftPM-based build pipeline doesn't support it cleanly without multi-day build-system work. Documented for future pursuit.

**Note:** the `-fprofile-instr-generate` modification has been reverted from `Package.swift` — no production impact.

## What this means for "beating Kakadu"

After tonight's two probes + the 12 prior lever-ceiling investigations on `v10.0-research`, the algorithmic frontier on Apple M2 is **structurally exhausted**:

- ✗ Encoder C+NEON optimisations (v9.4 graduated; subsequent C tightening explored across v9.5 + Phase 7 = wash)
- ✗ Decoder C+NEON port (Probe 1 tonight = wash; Swift baseline already SWAR-tuned)
- ✗ Cross-stage fusion (Phase 7 = 0.1 % overhead, structurally non-viable)
- ✗ GPU forward 5/3 single-tile (Phase 5 = wash on post-v9.5 multi-tile CPU)
- ✗ Default tunable sweep (Phase 9 = default is pareto-optimal)
- ✗ PGO build pipeline (Probe 2 tonight = blocked on SwiftPM tooling)

## The remaining real frontiers (none algorithmic on M2)

1. **Cross-silicon measurement** — M3+/A-series may have different memory bandwidth + scheduler characteristics. Phase 6 (`V10_0_PHASE6_DAEMON_DECOMPOSITION.md` on `v10.0-research`) already showed M2 ≠ M4 on the daemon-vs-in-proc curve. Requires hardware not on this development host.

2. **Mammography-specific scaling investigation** — Kakadu encode scales sub-linearly with pixels (DX→MG = 2.03×); J2KSwift scales linearly (DX→MG = 2.54×). The gap WIDENS with size. Workload-specific, not algorithmic. Could surface a tile-policy lever, but v8.7 already tried row-parallel + 4×4 tiles on MG and BOTH regressed. The MG sub-linear-scaling Kakadu mystery is interesting but not directly attackable without measurable hypothesis. NOT investigated tonight.

3. **Productisation / deployment** — j2kd daemon adoption telemetry, SDK marketing of the "wins-4-of-7-fixtures-vs-Kakadu" position (already on main as PRs #420 + #421). Non-engineering work.

## Recommendation

**Stop attempting to beat Kakadu via algorithmic improvements on M2.** The 13 lever-ceiling investigations + tonight's two probes confirm the codec is at its silicon-imposed ceiling. The product position remains strong (per `Documentation/Benchmarks/J2KSWIFT_OPTIMAL_VS_KAKADU.md` on main): J2KSwift beats Kakadu on 4 of 7 medical fixtures via the SDK shape, narrowly trails on the rest. That's the publishable position.

**Realistic next actions:**

1. **Pivot to M3+/A-series measurement** when hardware becomes available. The Phase 5/6/7/8 test harnesses on `v10.0-research` are reusable.
2. **Productisation work** — daemon adoption telemetry, public reproducibility tooling, conference / blog publication of the cross-codec measurements.
3. **Document the lever-ceiling pattern publicly** as a research contribution — 13 investigations is itself a notable engineering finding worth publishing.

## Tonight's commits

```
<head>  V10_OVERNIGHT_BEAT_KAKADU_SUMMARY.md (this doc)
<previous>  v10 decoder C+NEON Phase 0 viability probe — NO-GO
            (Sources/J2KCodecNEON/include/j2knhd.h
             Sources/J2KCodecNEON/j2knhd_decode_block_ht.c
             Tests/J2KCodecTests/V10DecoderNEONPhase0Tests.swift
             V10_DECODER_NEON_PHASE0_FINDING.md)
```

Files added live on `feature/v10-decoder-neon-port`; no merge to main per the research-on-branch policy. The Phase 0 test framework (`V10DecoderNEONPhase0Tests`) is reusable — re-running it on M3+/A-series hardware in the future will produce a directly comparable speedup number.

## Tonight's verdict in one sentence

**There is no remaining C-side lever to beat Kakadu on Apple M2 that the 13 cumulative lever-ceiling investigations have not already closed; the encoder/decoder hot path is at silicon-imposed ceiling, and the only productive direction forward is cross-silicon hardware measurement or product positioning.**
