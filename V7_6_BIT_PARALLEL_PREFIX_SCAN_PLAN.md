# v7.6 Plan — Bit-parallel NEON refill on chained-unstuff state

**Status**: RFC. Plan only — no implementation in this PR.
**Captured**: 2026-05-09, post-v7.5.0.
**Acceptance discipline carried from v7.4**: each phase ships default-ON only on a measured **≥ 3 ms** improvement on DX 2800×2288 in-process decode (median of 5 on a settled Apple M2). Below that, the path stays behind an opt-in flag.

---

## TL;DR

The "fundamentally different approach" flagged in v7.5's finding was bit-parallel prefix scan on chained-unstuff state. After surveying the current code, the realistic framing is narrower than the original 15-30 % estimate suggested. The opportunity is **VLC refill, not MagSgn refill**:

| target | current state | bit-parallel upside |
|---|---|---|
| **MagSgn refill** | v7.4 Phase 2 default-ON, SWAR 4-byte fast-path wins 99 % of corpus batches at near-optimal per-byte throughput | small — fast path is already cheap; slow path is rare |
| **VLC refill** | v7.4 Phase 3 rejected (noise-bound), SWAR 4-byte fast-path wins only ~10 % of batches; **slow path is per-byte scalar today** | **real** — the 90 % slow case is where the time goes, and it's currently the worst possible code shape (scalar byte loop) |

Plausible outcome: **3-7 ms DX win (5-13 %)** if NEON-vectorising the VLC slow path beats the per-byte scalar by a meaningful factor. Possible outcome: **no-op** if the variable-width bit pack overhead exceeds the per-byte savings. Multi-week investigation either way; the v7.4-style staged measurement discipline limits downside.

The plan revises the original v7.5 finding's "15-30 %" estimate downward based on concrete per-call cost analysis (see §3 below).

---

## 1. Why this is the only remaining viable codec-perf direction

Across v7.4 + v7.5 we tested every "easy" lever on Apple M2 + Swift release:

| experiment | DX A/B Δ | gate | shipped? |
|---|---:|:-:|:-:|
| v7.4 Phase 1 — NEON `readQuadSamples` reconstruction | 0.90 ms | ✗ | flag |
| v7.4 Phase 2 — SWAR 4-byte MagSgn refill | **3.70 ms** | **✓** | **default ON** |
| v7.4 Phase 3 — SWAR 4-byte VLC refill | −0.6 to +2.5 ms (noise) | ✗ | flag |
| v7.5 Phase 0 — Forward HT GPU entropy | −22.4 ms | ✗ | flag |

The SWAR / batched-dispatch shapes are exhausted. The remaining levers are:
1. **Bit-parallel NEON on chained-unstuff state** (this plan)
2. **C-bridged hand-tuned NEON intrinsics** (deferred — would require a C target, build-system surgery, multi-week)
3. **Algorithmic redesign of HT entropy coding** (out of scope; would diverge from spec)

This plan picks (1) because it's the most-contained scope (Swift NEON SIMD intrinsics, no build-system change, falls back to existing scalar/SWAR if it doesn't pay off).

---

## 2. What "bit-parallel prefix scan on chained-unstuff" actually means

The HT MagSgn unstuff rule is **single-step**, not multi-step (correction from earlier loose framing): byte N's processing depends only on byte N-1, not on a propagating chain. Looking at the v7.4 Phase 2 scalar loop:

```swift
let dBits = 8 - (u ? 1 : 0)
let mask: UInt8 = UInt8(0xFF) >> (u ? 1 : 0)
t |= UInt64(byte & mask) << b
b += dBits
u = (byte == 0xFF)
```

The "state propagation" is just `u = (byte_prev == 0xFF)` — one bit of state. So the operation isn't a *prefix* scan in the multi-stage Kogge-Stone sense; it's a **1-position lookback** that's straightforward to vectorise:

1. Vector load 16 bytes into a NEON register
2. Compare lanes to `0xFF` → 16-lane bool mask
3. Shift mask right by 1 lane (carry-in from prior batch's last byte) → 16-lane "prev was 0xFF" mask
4. AND with current-byte bit-7-set mask → 16-lane "this byte should drop bit 7" mask
5. Conditionally clear bit 7 of each byte
6. **Pack the variable-width result into the bit accumulator**

Step 6 is the hard part. When some bytes contribute 7 bits and others 8, the lane-aligned packing breaks down. This is the classic SIMD variable-length-encoding pack problem.

VLC is the same shape with `> 0x8F` instead of `== 0xFF`, plus an additional condition on the current byte's low 7 bits being all-1s.

---

## 3. Why MagSgn vs VLC have very different upsides

### MagSgn — small upside

**v7.4 Phase 2 already wins 99 % of corpus batches via SWAR**. The fast path is one UInt32 load + one OR-into-accumulator + one bit-counter advance. There's almost no per-batch overhead to amortise by going to 16-byte NEON — the SWAR fast path is already at the per-byte ceiling for the 99 % case.

The slow path (1 % of batches, when 0xFF is present) is per-byte scalar. Vectorising it to NEON might be 4-8× faster on the slow path, but slow-path is 1 % of batches → contribution to total wall is sub-1 %.

Realistic MagSgn-only gain: **0-2 ms on DX**, likely below the 3 ms gate.

### VLC — real upside

**v7.4 Phase 3 rejected at noise** because the SWAR fast-path predicate (`all 4 bytes ≤ 0x8F`) fires only ~10 % of batches on uniform random data — bytes > 0x8F are 7/16 of the value space. So **90 % of VLC refill batches go through per-byte scalar today**, even with Phase 3 enabled.

Bit-parallel NEON would let the 90 % slow path process 16 bytes in parallel:
- Compute "is byte > 0x8F" mask in parallel
- Compute "should unstuff" mask via 1-position shift + AND
- Apply mask conditionally
- Pack variable-width result

Even if the variable-width pack costs 30-50 % more than scalar per-byte, the 4× SIMD width amortises favourably. Plausible per-batch speedup: 2-3×.

If VLC refill contributes ~5-10 ms of the ~52 ms DX wall (we'll measure this in Phase 0), a 2-3× speedup on the 90 % scalar portion could save 3-7 ms.

Realistic VLC-only gain: **3-7 ms on DX**, plausibly clearing the 3 ms gate. This is the load-bearing hypothesis.

---

## 4. Phased plan

Each phase has a **bail-out gate** — the plan stops there if the measured Δ doesn't warrant continuing.

### Phase 0 — VLC refill cost share probe (1-2 days)

**Question**: how much of the ~52 ms DX wall is actually spent in VLC reverse-reader refill?

**Method**: re-enable the v7.3.0 `J2KHTEntropyProfile` instrumentation in a measurement-only test (NOT production — it caused 30 % multi-tile contention regression per v7.3.0 #367, which is why it's off in production). Sample a few decodes single-threaded, dump per-call counts and total-time-in-refill, compute share-of-wall.

**Bail-out**: if VLC refill is < 5 ms of the 52 ms DX wall, stop. The maximum possible win is the entire VLC refill cost, which would still be below the 3 ms gate. Document and close as "VLC isn't the lever."

**Deliverable**: `V7_6_PHASE_0_VLC_COST_SHARE_FINDING.md` with the per-stage time breakdown.

### Phase 1 — NEON 16-byte VLC slow-path prototype (1-2 weeks)

**Scope**: implement a NEON 16-byte vectorised VLC refill slow path that handles the `> 0x8F` case in parallel.

Concrete sub-steps:
1. **1a** — 16-byte unaligned load + `> 0x8F` lane mask via `vcgtq_u8`. Carry-in handling for the cross-batch 1-position shift.
2. **1b** — Compute "should drop bit 7" mask: `prev_was_unstuff && (current & 0x7F) == 0x7F`. Two NEON compares + AND.
3. **1c** — Conditional bit 7 clear via `vbicq_u8` (NEON bit-clear). Output: 16 effective bytes, each contributing 7 or 8 bits.
4. **1d** — **Variable-width pack** (the hard part). Options to evaluate:
   - **Option A**: scalar tail pack — process the 16-byte output one byte at a time into the 64-bit accumulator. Vector for detection, scalar for pack. Lower upside but minimal SIMD-pack risk.
   - **Option B**: NEON gather + ARM `tbl` lookup for variable-width pack. Higher complexity, higher upside.
   - **Option C**: process 8-12 bytes per iteration (smaller batch, larger accumulator headroom). Middle ground.

**Bail-out**: if Option A microbench shows < 1.5× speedup vs Phase 3 SWAR (the rejected baseline), stop and close. Don't proceed to B/C.

**Deliverable**:
- `Sources/J2KCodec/J2KHTConformantBlockDecoder.swift` extension — `refillVectorised` path behind a new flag `VLCReverseReaderTesting.vectorisedRefillEnabled` (default `false`).
- Bit-exact parity tests (`V760NeonVlcVectorisedRefillParityTests.swift`) — at minimum the 5 sweeps from Phase 3 (bit-depths, densities, block sizes, 64 random seeds, full corpus end-to-end). Extended with explicit cross-batch carry tests (16-byte boundary cases).
- Microbench (`V760NeonVlcVectorisedRefillMicrobench.swift`) — per-block decode time vs Phase 3 SWAR vs scalar reference.

### Phase 2 — DX in-process A/B (1-2 days)

**Method**: same shape as v7.4 Phase 2 / Phase 3 / v7.5 Phase 0 — toggle the flag, encode-decode the corpus, median of 5 on a settled system.

**Deliverable**: `Tests/J2KCodecTests/V760NeonVlcVectorisedRefillDXWallBenchmark.swift`. Reports CPU vs vectorised-refill wall + telemetry breakdown.

**Acceptance**:
- **Δ ≥ 3 ms** on DX → flip default to ON (v7.4 Phase 2 precedent).
- **0 < Δ < 3 ms** → keep behind flag, document, ship as "available but not default" (v7.4 Phase 1 precedent).
- **Δ ≤ 0 ms** → keep behind flag, document as rejected, ship as "available for future hardware" (v7.4 Phase 3 / v7.5 Phase 0 precedent).

### Phase 3 (optional) — MagSgn 16-byte NEON exploration (1 week, only if Phase 1 succeeded)

If Phase 1 shipped a real win, the same 16-byte NEON pattern *might* close the small remaining MagSgn margin. Phase 3 explores this only if Phase 1 demonstrated the variable-width pack is viable on the M2 NEON path. If Phase 1 failed, skip Phase 3 entirely.

**Bail-out**: same 3 ms DX gate.

### Phase 4 — Release (1-2 days)

**Trigger**: at least one of Phase 1 / Phase 3 cleared its gate.

**Deliverables**:
- `RELEASE_NOTES_v7.6.0.md` — headline = "bit-parallel NEON VLC refill (and possibly MagSgn) defaults ON, +X ms on DX"
- CHANGELOG entry
- README update to v7.6.0 trajectory column
- Cross-codec parity matrix re-run (12/12 must hold)
- Mandatory gate green

If neither Phase 1 nor Phase 3 cleared the gate, the deliverable is a **perf-wash v7.6.0** on the v7.5.0 model — measurements + finding doc, no production code change, workstream documented as closed for this hardware.

---

## 5. Risks and mitigations

| risk | mitigation |
|---|---|
| Variable-width SIMD pack on Apple NEON has known overhead — might exceed the per-byte savings | Phase 1a-b-c-d are independently testable; Option A (scalar pack) sets a floor. If Option A doesn't win, abandon. |
| The 1-position cross-batch carry breaks correctness for boundary 0xFF / >0x8F bytes | Parity gate explicitly tests cross-batch boundaries. Phase 1 deliverable lists this as a required sweep. |
| Phase 0 instrumentation regresses production (per v7.3.0 #367 lesson) | Phase 0 instrumentation is single-threaded measurement-only, never enabled in default builds. Reverted before any Phase 1 PR opens. |
| Multi-week scope but no win at the end | The bail-out gates at Phase 0 and Phase 1a make this a 1-3 day commitment to know if it's viable. Worst case: a perf-wash v7.6 like v7.5 — fine outcome. |
| Measured wall is system-state-sensitive (per v7.4 finding) | All A/B reported on settled-system median of 5, with multiple runs to estimate variance. |
| Breakage of v7.4 Phase 2 MagSgn batched refill (default ON) | v7.6 work touches VLC refill; MagSgn refill is left exactly as-is. Mandatory gate catches regressions. |

---

## 6. Out of scope for v7.6

- **C-bridged hand-tuned intrinsics**. Build-system surgery (add a C target, ABI bridge), worth doing only if Swift NEON SIMD doesn't get us close. Defer to v7.7+ if v7.6 ships under-target.
- **GPU-side anything**. v7.5 closed forward HT GPU entropy as structurally hostile on M2; the same applies to GPU-side refill. M-series GPU isn't the right target for chained-state work.
- **Decoder reconstruction (`readQuadSamples`)**. v7.4 Phase 1 already measured this NEON path at 0.90 ms (rejected). The bit-parallel framing doesn't apply — reconstruction isn't chained-state.
- **Encoder forward path**. v7.5 closed this as structurally non-viable on M2.

---

## 7. Reproduction commands (for each phase as it ships)

```bash
# Phase 0 — cost share probe
swift test -c release --filter V760Phase0VLCCostShareProbe

# Phase 1 — vectorised refill parity
swift test -c release --filter V760NeonVlcVectorisedRefillParityTests

# Phase 1 — vectorised refill microbench
swift test -c release --filter V760NeonVlcVectorisedRefillMicrobench

# Phase 2 — DX in-process A/B
swift test -c release --filter V760NeonVlcVectorisedRefillDXWallBenchmark

# Mandatory gate (every phase before commit)
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'
```

---

## 8. Decision tree (the honest version)

```
Phase 0: VLC refill cost share probe
   └── < 5 ms of DX wall? → STOP. Document. Workstream closed.
       VLC isn't the lever. v7.6 ships as a perf-wash with the
       investigation finding only.

   └── ≥ 5 ms of DX wall? → continue to Phase 1.

Phase 1a-d: NEON 16-byte vectorised VLC slow path
   └── Microbench < 1.5× faster than Phase 3 SWAR? → STOP. Document.
       Variable-width pack overhead exceeds savings on M2 NEON.
       v7.6 ships as a perf-wash.

   └── Microbench ≥ 1.5× faster? → continue to Phase 2.

Phase 2: DX in-process A/B
   └── Δ ≥ 3 ms? → SHIP default ON. v7.6 is a real perf release.
   └── 0 < Δ < 3 ms? → SHIP behind flag. v7.6 is a "flag landed,
       documented under-gate" release on the v7.4 Phase 1 model.
   └── Δ ≤ 0 ms? → SHIP as rejected. v7.6 is a perf-wash.

(Phase 3 — MagSgn exploration — only fires if Phase 1 succeeded.)

Phase 4: Release. v7.6.0 ships in any of the above outcomes;
the headline depends on which branch fired.
```

The disciplined framing: **the worst-case v7.6 outcome is a clean perf-wash with measurement + finding doc**, exactly like v7.5.0. The best-case is a 5-13 % DX win. Either way, the work is bounded and the gates are pre-committed, so we don't drift.

---

## 9. What lands in *this* PR (RFC, plan only)

- This document (`V7_6_BIT_PARALLEL_PREFIX_SCAN_PLAN.md`).

What does **not** land:
- Any code changes. This is a planning artefact for review before any implementation begins.

When this RFC is approved (merged to `main`), Phase 0 starts on a separate `v7.6-phase-0-vlc-cost-share` branch.
