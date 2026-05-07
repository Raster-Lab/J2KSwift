# v6.4.0 G1.2 — auto-multi-tile production-default decision (SemVer gate)

**Status**: Empirical findings + SemVer decision required from user. No production code change in this PR.

**Branch**: `feature/v6.4.0-auto-multi-tile-default-on`

**Anchors**:
- [`docs/V6_4_0_PLAN.md`](V6_4_0_PLAN.md) §G1.2 — production-default decision
- [`docs/V6_4_0_G1_0_INVESTIGATION.md`](V6_4_0_G1_0_INVESTIGATION.md) — audit reveals parallelism is in place but unrouted
- [`RELEASING.md`](../RELEASING.md) §"Special rules for J2KSwift" — codestream bytes are part of the public contract

---

## Why this exists

G1.0 (#329) measured that `encodeNativeMultiTile` already ships per-tile parallelism wins of +30 to +49 % on MR/XA/PX, but the production default `J2KEncoder.encode(_:)` does not route through it — only the `J2K_HT_TILE_MODE` env var triggers multi-tile. G1.2 was scoped to "production-default decision".

The decision turns out to be **a SemVer-version-bump gate**, not a code change. Per [`RELEASING.md`](../RELEASING.md) "Special rules for J2KSwift":

> **Codestream bytes are part of the public contract.** A bytes-changing default flip is automatically MAJOR even if no Swift API changed.
> v6.0.0 was MAJOR because `.auto` became the default tile mode and that changes bytes for any user who didn't explicitly specify a tile mode.

Flipping `J2KEncoder.encode(_:)` to use the `.auto` planner by default would change codestream bytes for every user without an explicit `.single` env var. Pixels remain bit-exact (HTTileParityMatrixTests 12/12 confirms), but **codestream bytes differ** (single-tile codestream vs multi-tile codestream).

---

## Empirical findings — auto vs single (M2 release, median of 5)

`HTMultiTilePerfProbeTests.testMultiTilePerfProbeOnLargeFixtures` re-run on the v6.4.0 G1.2 branch. The auto planner picks the optimal mode per fixture pixel count (`pixels < 500K` → single, `500K ≤ pixels < 3M` → 2x2, `pixels ≥ 3M` → 4x4):

| Modality | Shape | px | Auto-picked mode | single ms | auto ms | Δ |
|---|---|---:|---|---:|---:|---:|
| MR-small | 180×180 | 32K | single (gated) | — | — | unchanged |
| CT | 512×512 | 262K | single (gated) | — | — | unchanged |
| **MR** | **886×886** | **785K** | **2x2** | **6.07** | **3.05** | **+50%** |
| **XA** | **1024×1024** | **1.05M** | **2x2** | **12.09** | **7.86** | **+35%** |
| **PX** | **2459×1316** | **3.24M** | **4x4** | **34.80** | **24.26** | **+30%** |
| **DX** | **2800×2288** | **6.41M** | **4x4** | **56.42** | **52.79** | **+6%** |

Note: small-fixture path (MR-small, CT) stays single-tile per the planner's `pixels < 500K` rule — the per-tile dispatch overhead exceeds the parallelism gain at small sizes. **No regression on small fixtures.**

### Cross-codec parity confirmation

`HTTileParityMatrixTests` on the auto-routed multi-tile codestreams (release mode):

```
MR  886×886  2x2 / 4x4 / strips4   — 0 / 0 / 0 (4 codecs)
XA 1024×1024 2x2 / 4x4 / strips4   — 0 / 0 / 0
PX 2459×1316 2x2 / 4x4 / strips4   — 0 / 0 / 0
DX 2800×2288 2x2 / 4x4 / strips4   — 0 / 0 / 0
```

**12 / 12 cells × OpenJPH / Grok / Kakadu / self-RT = 48 cells, all bit-exact pixel reconstruction.** The auto-routed codestream is fully standards-compliant; external decoders see correct pixels.

### What changes for users who upgrade?

If v7.0.0 ships with `.auto` default:
- Users without `J2K_HT_TILE_MODE=single`: codestream bytes for MR/XA/PX/DX change from single-tile → multi-tile
- Decoded pixel data: **byte-identical** to v6.x (HTTileParityMatrixTests guarantees)
- Encode wall time: **+30 to +50 % faster** on MR/XA/PX, +6 % on DX
- DICOM consumers reading our codestreams: see different bytes but get the same image
- Storage size: ~+0.05 % overhead from multi-tile SOT/SOD markers

---

## SemVer decision tree

The user must decide between three paths for v6.4.0:

### Path 1 — Ship as v6.4.0 OPT-IN (most conservative)

**No code change.** Keep production default `.single`; users opt in via `J2K_HT_TILE_MODE=auto` env var (the existing path).

- ✅ MINOR-eligible per `RELEASING.md` (no default change)
- ✅ Backward-compatible — no consumer is surprised
- ❌ The +30-50 % wins stay invisible to typical consumers
- ❌ Doesn't move the Kakadu deadline needle for production users

**v6.4.0 release notes ship**: "G1.0 audit + perf data findings; multi-tile remains opt-in" — adds documentation, no shipped behaviour change for default users.

### Path 2 — Ship as v7.0.0 with default flip (HEADLINE)

Flip the production default from `.single` → `.auto`. Requires v7.0.0 MAJOR bump per `RELEASING.md` SemVer rule.

- ✅ Captures the +30-50 % wins as the v7.0.0 production-default headline
- ✅ Materially closes the Kakadu encode gap on MR/XA/PX (DX small)
- ✅ Pixels remain bit-exact (HTTileParityMatrixTests 48/48)
- ⚠️ Codestream bytes change — `CROSS_VERSION_DELTA_REPORT.md` required documenting which fixtures' bytes changed
- ⚠️ Existing consumers receive different bytes; need release-notes prominence
- ⚠️ v7.0.0 is a bigger release than originally scoped (was v6.4.0 minor)

**v7.0.0 release notes ship**: "Multi-tile encoding production-default; +30-50 % encode wall on MR/XA/PX; codestream bytes change vs v6.x for users without explicit single-tile."

### Path 3 — Ship as v6.4.0 with NEW gate flag, default OFF (deferred enable)

Add `EncoderPipeline._autoMultiTileEnabled: Bool` static var (default `false`); wire it into `J2KEncoder.encode(_:)` to short-circuit `.auto` planner when `true`. Mirror of v6.0.0's `_gpuForward53Enabled` opt-in pattern.

- ✅ MINOR-eligible (no default change in v6.4.0)
- ✅ Sets up infrastructure for v7.0.0 default-flip
- ✅ Users can programmatically opt-in via `EncoderPipeline._autoMultiTileEnabled = true` without env var
- ⚠️ Adds API surface (one new static var) that must persist
- 🟡 Half-step — the wins still don't reach typical consumers without action

**v6.4.0 release notes ship**: "Auto multi-tile gate flag added (default off); flip to true for opt-in production wins; v7.0.0 default-on planned."

---

## Recommendation

The user signalled "bigger release, Kakadu deadline near" in the v6.4.0 plan request. **Path 2 (v7.0.0 default flip) directly serves that goal**:

- The empirical +30-50 % wins on MR/XA/PX are the biggest single-release Kakadu-gap-narrow available without further engineering work
- The infrastructure is already in production (since v6-alpha3 step 9); only the routing default needs to flip
- Cross-codec parity is solid (12/12 cells bit-exact across all 4 reference decoders)
- The major-bump cost is paid once; subsequent v7.x can carry MINOR perf work

**Path 1 vs Path 3** are both half-steps that defer the win — both leave production-default consumers without the encode boost. Path 3 is slightly better than Path 1 because it adds the toggle infrastructure for a future flip.

If the user accepts Path 2, the next PR scope is:
- Flip `from(envValue: nil)` default from `.single` to `.auto` (or equivalent route in `J2KEncoder.encode`)
- Update RELEASE_NOTES_v7.0.0.md with the codestream byte change
- Add `CROSS_VERSION_DELTA_REPORT.md` documenting the byte-shift per fixture
- Bump version to 7.0.0 in `Package.swift` / wherever versioned

If the user picks Path 1 or 3, this PR ships as **investigation only** with the data above as the v6.4.0 release-notes contribution; the default-flip waits.

---

## Decision required

Before any code change PR opens, the user must pick a path:

| Path | Version | Default | Wins reach typical consumers | SemVer cost |
|---|---|---|---|---|
| 1 | v6.4.0 | `.single` (unchanged) | NO | MINOR (free) |
| 2 | **v7.0.0** | **`.auto`** | **YES — production headline** | **MAJOR (one-time)** |
| 3 | v6.4.0 | `.single` (with new flag) | only if user flips programmatically | MINOR (free) |

This investigation PR ships as Path 1 default — no code change beyond the documentation. The decision moves which follow-up PR opens.
