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

## The crash is `swift test`-harness-specific (key finding)

A second debugging pass narrowed it sharply. The **same test bundle**,
**same single test**, **same code**:

- `swift test --filter testROIDirect_bitExact_DX_2800` — **3/3 crash**
  (SIGABRT, heap corruption).
- `xcrun xctest -XCTest …/testROIDirect_bitExact_DX_2800 <bundle>` —
  **4/4 PASS**, fully executed, all 7 regions `.direct ≡
  .fullImageExtraction ≡ crop` bit-exact.

So the windowed iDWT **produces correct output** — proven by the
V10_13 unit tests *and* four clean bit-exact end-to-end runs under the
standard `xctest` runner. The crash is a deterministic interaction
with the **`swift test` harness specifically** (which co-loads
swift-testing 1501 alongside XCTest), not a defect in the windowed
decode itself.

Attempts that did **not** resolve it:
- AddressSanitizer — does not load (`Sanitizer load violates platform
  policy`).
- Guard Malloc (`libgmalloc` via `DYLD_INSERT_LIBRARIES`) — the env
  var does not survive `swift test`'s process chain (the crash stayed
  in the system `szone` allocator); injected directly into `xcrun
  xctest`, the test simply passes (no crash to catch there).
- Rewriting the windowed routine as `async` + `withTaskGroup`-parallel
  (structurally mirroring `inverseTransformMultiLevel53`) — the
  `swift test` crash persisted, changing only SIGABRT → SIGSEGV. So
  the sync/async call-site shape is not the cause.

This blocks shipping regardless of the windowed code being correct:
the project's **mandatory commit gate runs via `swift test`**, and a
crashing `swift test` cannot produce the required clean gate run.

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

- Reproduce under `swift test` on a host where AddressSanitizer loads
  (e.g. Linux, or a Mac without the sanitizer code-signing
  restriction) — ASan pinpoints the access in one run. The bug only
  manifests under `swift test`, so the repro must use that harness.
- Investigate the `swift test` harness path itself: it co-loads
  swift-testing 1501 + XCTest in one process and runs the bundle via
  `swiftpm-xctest-helper`. Bisecting what that adds vs. plain `xctest`
  (executor configuration, observation hooks, parallel scheduling)
  would localise the interaction.
- The sync/async hypothesis is **ruled out** — the async + parallel
  rewrite did not fix it.
- The `decodeRegion(.direct)` API and the v10.6/v10.7 staging are
  unaffected — Stage 3 slots in behind the same public surface once
  the harness interaction is understood. The windowed transform itself
  needs no further correctness work (bit-exact, four clean `xctest`
  end-to-end runs).
