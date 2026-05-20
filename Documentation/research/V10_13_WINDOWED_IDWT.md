# v10.13-research — ROI decode Stage 3 (windowed inverse DWT)

**Branch:** `v10.13-research`
**Status:** transform implemented + exhaustively unit-validated; pipeline
integration **blocked** by a heap-corruption bug — Stage 3 does NOT ship.
**Date:** 2026-05-20

## Goal

ROI decode Stage 3 — the windowed inverse DWT. v10.6.0 (Stage 1)
skipped entropy decode for off-region code-blocks; v10.7.0 (Stage 2)
skipped whole off-region tiles. Both still ran the inverse DWT in full
for every tile the region touches (and for every single-tile fixture).
Stage 3 windows the inverse 5/3 DWT so it reconstructs only the
region's rows — extending the ROI win to single-tile fixtures (CT / DX
/ PX / MR) and the touched tile of a multi-tile decode.

## What was built (validated, retained)

### `inverseLift53InPlaceWindowed` — windowed 1D inverse 5/3 lift

Exact by **loop-restriction**, not approximation. The 5/3 inverse
decomposes into Step 1 (evens, from input high-pass only) then Step 2
(odds, from Step-1 evens) — a tight forward dependency. Producing pairs
`[pairFrom, pairTo)` needs evens `[pairFrom, pairTo+1)` then odds
`[pairFrom, pairTo)`, no halo. The per-sample arithmetic is
bit-identical to `inverseLift53InPlace`; only the loop bounds change.

Validation (`V10_13_WindowedIDWTTests`): exact vs the full lift across
**every** window of **14** dyadic even/odd count pairings, plus a
strided variant. PASS.

### `inverseTransformMultiLevel53RowWindowed` — row-windowed multi-level

Reconstructs only output rows `[outRowLo, outRowHi)` of the full tile.
The row pass is the unchanged full-width `inverseLift53InPlace`; the
column pass is the windowed lift. The per-level row window propagates
with `parentRows` = `[lo>>1, ((hi+1)>>1)+1)` — the exact, halo-free
support of the 5/3 inverse column lift.

Validation: bit-identical to the full `inverseTransformMultiLevel53`
across 9 shapes — including odd dimensions and the **2800×2288** /
**512²** medical sizes — × 6 row windows (full, empty, corners, strips).
PASS. Bounds preconditions throughout the routine never trip.

## The blocker — pipeline integration heap corruption

Wiring the windowed transform into the live decoder (`applyInverseWaveletTransform`:
when `regionOfInterest` is set, force the CPU iDWT path and call the
windowed routine) crashes the DX `.direct` decode with **SIGABRT —
`free_list_checksum_botch`** (heap corruption detected on a `free`).

Isolation performed:

- **CPU-reroute alone is fine.** With the windowed branch disabled but
  ROI still forced onto the CPU iDWT path, DX `.direct` passes
  bit-exact. So forcing `allowGPUPath = false` for ROI is sound.
- **The windowed branch triggers the corruption.** Enabling it
  reintroduces the crash.
- **The windowed routine is provably memory-safe in isolation.** The
  V10_13 unit tests drive it at DX dimensions with bounds preconditions
  active — nothing trips, output is bit-exact. The column lift
  provably accesses a strict subset of the original full lift's
  (in-bounds) index set.
- The corruption is *detected* on a `free` inside the routine but is
  **not caused by its buffer writes** (every `base` / `currentBuf` /
  `tmp` write is preconditioned and in-bounds; allocations and frees
  pair exactly, no double-free). This points to a subtler defect — a
  use-after-free, an aliasing violation, or a latent data race exposed
  by the integration (the windowed routine is synchronous where the
  full `inverseTransformMultiLevel53` is `async`, changing the
  suspension structure at that call site).

Root-causing a heap-corruption bug of this kind needs **AddressSanitizer**.
ASan does not load in this environment — the runtime rejects the
sanitizer dylib under the platform code-signing policy
(`Sanitizer load violates platform policy`). Without ASan, further
diagnosis is disproportionately expensive.

## Outcome

Per the project's release discipline (no shipping of crashing or
unverified code), the pipeline integration was **reverted** —
`J2KDecoderPipeline.swift` is byte-identical to `main`; the production
decoder is unchanged from v10.7.0. ROI decode remains: Stage 1
entropy-skip (v10.6.0) + Stage 2 tile-skip (v10.7.0).

The windowed lift + windowed multi-level transform + `V10_13_WindowedIDWTTests`
are retained on this branch as a **validated, reusable foundation**.
The transform math is correct and proven; only the live wiring is
unresolved.

## Next steps

- Re-attempt the integration in an environment where AddressSanitizer
  loads — ASan will pinpoint the offending access in one run.
- Alternatively, rule out the sync/async hypothesis by giving the
  windowed routine an `async` signature that mirrors
  `inverseTransformMultiLevel53`'s task-group structure, so the call
  site's suspension behaviour is unchanged.
- The `decodeRegion(.direct)` API and the v10.6/v10.7 staging are
  unaffected — Stage 3 slots in behind the same public surface when
  the integration is resolved.
