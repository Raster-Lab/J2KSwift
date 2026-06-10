# Cloud-bill reduction — status report

**Date:** 2026-05-27 (overnight pause)
**State:** All file changes are LOCAL ONLY. Nothing was pushed to origin tonight.
**Cloud side-effects taken** (not files): 14 in-flight workflow runs were
cancelled via `gh run cancel` to stop ongoing billing immediately (see
"Active-run cancellations" below).

## Two-stage local reduction

The branch `bill-reduction` (LOCAL ONLY) has TWO commits stacked on top
of `main`:

| Commit | Scope |
|---|---|
| `cd45476` | **Stage 1** — restricted triggers on 5 expensive workflows (push triggers removed; PR or manual only) |
| `35d0620` | **Stage 2** — outright **deleted 9 non-cloud-mandatory workflows** after the user asked to "remove the workflow which is not to be cloud mandatorly" |

Commit 35d0620 supersedes cd45476 for the 5 workflows that appeared in
both (the trigger restrictions are moot once the files are deleted).
The combined diff vs main is what gets pushed when you apply.

## Final workflow inventory (cloud-mandatory only)

After `35d0620`, `.github/workflows/` contains only:
- `release.yml` — auto-creates GitHub Release on tag push (Linux, cheap)
- `create-release-branches.yml` — manual-dispatch only, creates `release/vX.Y.Z` mirror branches from tags (Linux, cheap)
- `README.md` — workflow documentation (rewritten to reflect the new state)

Deleted (all `macos-15`, all redundant with local tests):
- `ci.yml`, `swift-build-test.yml` — Build + Test → `swift test -c release`
- `code-quality.yml` — SwiftLint → `swiftlint --strict` locally
- `conformance.yml`, `jp3d-compliance.yml` — Part-1/Part-15 + JP3D conformance (75-min cap each) → local `swift test --filter J2K*ConformanceTests`
- `dicomkit-downstream.yml` — downstream consumer build → manual `swift build`
- `performance.yml` — benchmarks (75-min cap) → already covered by the mandatory commit gate (`J2KMedicalCorpus*PerformanceTests`)
- `documentation.yml` — DocC build + Pages deploy → local `swift package generate-documentation`
- `interactive-testing.yml` — manual/scheduled macOS suite

## Active-run cancellations

When you raised the bill concern, **14 workflow runs were still in-flight**
(queued or running) from the v10.19.0 push earlier in the day —
Documentation, Conformance Gating, Performance Benchmarks, Swift Build
and Test, Code Quality, CI, DICOMKit Downstream Build. I issued
`gh run cancel` against every queued + in-progress run to stop the
billing clock immediately. Final post-cancel state:

- Documentation: cancelled
- Performance Benchmarks: cancelled
- Conformance Gating: cancel-pending (GitHub processed it shortly after)
- All others: cancelled or already-completed at request time

The Release workflow (the v10.19.0 tag push that triggered the
canonical release) completed successfully BEFORE I cancelled — that's
the workflow that created the release page + mirror branch you'd
expect. Only the redundant macOS-15 jobs were cancelled.

## What happened — bill spike analysis

5 releases shipped on 2026-05-26 (v10.15.0 → v10.19.0). Each release
fires roughly this sequence:

1. Push RC branch (e.g. `v10.19.0-release-candidate`) — *skipped by
   the workflows, all triggers were scoped to `main/develop/release/*`*
2. **Open PR** → fires **~7 macOS-15 workflow jobs** (ci, code-quality,
   conformance, dicomkit-downstream, jp3d-compliance, performance,
   swift-build-test) — each up to **75-min timeout** at ~10× Linux cost
3. **Merge to main** → fires the same **~7 macOS-15 jobs again** (the
   merge commit is a fresh push to main)
4. **Push tag** → release.yml (Linux, cheap) + documentation.yml
   (macOS, 1 job) + create-release-branches.yml (Linux, cheap)

→ **~14 macOS-15 jobs per release × 5 releases = ~70 macOS-runner
jobs on 2026-05-26 alone**. At cap (75 min × $0.08/min ≈ $6/job)
the worst case is ≈ $420 in a single day; even at typical run
times of 8–15 min the day's burn rate is $50–$150.

## What I did tonight — local-only changes

**`v10.20.0-pending` work is preserved as `stash@{0}` (NOT pushed)**.
Six new `Sources/J2K3D/JP3D*+PreWarm.swift` extensions, the V10_32
test file, the release notes, and the `getVersion()` bump are all in
the stash. Restore with `git stash pop` whenever desired.

**`bill-reduction` branch (commit `cd45476`)** carries five surgical
workflow restrictions. Branch is LOCAL ONLY — not pushed to origin.
Files changed:

| Workflow | Change | Rationale |
|---|---|---|
| `.github/workflows/performance.yml` | Removed `push` + `pull_request` triggers. Now `workflow_dispatch` + weekly cron (`0 3 * * 0`) only | Single biggest line item — 75-min macOS benchmark on every push. Per-release perf coverage is preserved by the local commit gate (`J2KMedicalCorpus*PerformanceTests`). |
| `.github/workflows/conformance.yml` | Dropped `push` trigger. PR + workflow_dispatch retained | Was running the 75-min Part-1/Part-15 conformance suite on every push AND every PR. The PR run is the real merge gate; the post-merge push re-run was pure duplication. |
| `.github/workflows/dicomkit-downstream.yml` | Dropped `push` trigger. PR + workflow_dispatch retained | Same redundancy pattern as conformance. |
| `.github/workflows/swift-build-test.yml` | Dropped `push` trigger. PR + workflow_dispatch retained | This is a duplicate of `ci.yml` (both run Build + Test on macos-15). We were paying for two identical jobs on every push to main; ci.yml carries post-merge coverage by itself. |
| `.github/workflows/documentation.yml` | Restricted from "every main commit" to "tag push only" | Docs only rebuild when we ship — intermediate-commit rebuilds had no consumer-visible value. |

**Workflows kept unchanged (still on `push` + `pull_request`):**
- `ci.yml` — main merge gate, Build + Test
- `code-quality.yml` — SwiftLint, 10-min timeout, low cost
- `jp3d-compliance.yml` — already path-filtered to `Sources/J2K3D/**` so it only fires on JP3D-touching commits
- `release.yml` — Linux only, tag push only (cheap)
- `create-release-branches.yml` — `workflow_dispatch` only (already cheap)

## Projected reduction

| Stage | Before | After |
|---|---:|---:|
| PR open | ~7 macOS jobs | ~5-6 macOS jobs |
| Merge to main | ~7 macOS jobs | ~2-3 macOS jobs |
| Tag push | ~1 macOS job | ~1 macOS job |
| **Per-release total** | **~14-15 macOS jobs** | **~8-10 macOS jobs** |
| **Per-hour performance.yml drift** | every push to main/develop | weekly only |

Estimated **~40% reduction per release** + elimination of the
push-driven performance.yml hourly drift.

## What to do when you wake up

### Review the diff

```bash
cd /Users/raster/Documents/raster/J2KSwift
git checkout bill-reduction
git diff main bill-reduction -- .github/workflows/
```

### Apply (push to origin) if you approve

After Stage 2 (`35d0620`), the 9 macOS workflows have been DELETED in
the branch's tree. Once you push the branch / merge to main, those
workflows no longer exist on origin → they cannot fire on future
pushes. Workflows are evaluated based on the file state at the SHA
being processed, so the deletion commit itself **does NOT** trigger
the deleted workflows (no final "one last hit" cost).

```bash
# Option A — push branch + open PR (the PR open itself triggers nothing
# now that those workflows are absent in this branch's tree)
git push -u origin bill-reduction
gh pr create --base main --head bill-reduction \
  --title "ci: delete non-cloud-mandatory workflows + restrict triggers" \
  --body "See BILL_REDUCTION_STATUS_2026-05-27.md"
gh pr merge <number> --merge --delete-branch=false

# Option B — fast-forward main directly (skips the PR step entirely)
git checkout main
git merge --ff-only bill-reduction
git push origin main
```

Either option: the push triggers ONLY the workflows that REMAIN in the
file tree at the pushed commit. Since both `release.yml` and
`create-release-branches.yml` are gated to tag-push / manual only,
NO workflow runs are triggered by applying this change.

### Revert if you disagree

```bash
git checkout main
git branch -D bill-reduction
git stash drop stash@{0}   # only if you want to discard v10.20 too
```

### Restore a specific deleted workflow

If after pushing the deletion you decide you want one workflow back:

```bash
# E.g., bring back ci.yml from before the deletion
git show 35d0620^:.github/workflows/ci.yml > .github/workflows/ci.yml
git add .github/workflows/ci.yml
git commit -m "ci: restore ci.yml"
git push origin main
```

The deletion commit `35d0620^` (the parent) has every workflow file
in its original form; you can recover any of the nine deleted ones
without losing other history.

### Restore the v10.20 work

The v10.20 ship (JP3D preWarm symmetric completion, 6 new wrappers
covering JP3DEncoder + JP3DMultiSpectralEncoder/Decoder +
JP3DProgressiveDecoder + JP3DStreamWriter + JP3DTranscoder + V10_32
test file + release notes + version bump) is stashed:

```bash
git checkout main
git stash pop stash@{0}
# Working tree now has v10.20 changes ready to ship.
```

I recommend NOT shipping v10.20 the same day as the bill-reduction
PR (it would trigger more macOS jobs while the reduction itself is
fresh). Better: ship the reduction first, observe a few days of
billing, then ship v10.20 once you're comfortable with the new
cadence.

## What didn't happen tonight

- No `git push` operations to origin
- No new PRs or merges
- No new tags
- No GitHub Actions workflows triggered by my work
- No release artifacts created

The autonomous shipping spree paused at v10.19.0 (the last shipped
release). Everything beyond that is local-only until you act on
this report.

## Open candidate-list for future releases (unchanged)

After the billing situation stabilises and you're ready to resume
shipping:

1. **v10.20.0** — JP3D preWarm symmetric completion (already done,
   in stash@{0})
2. **v10.21.0 — `J2KDICOMHelpers` Phase 3** — DICOM file parser
   extraction (J2K-tagged datasets only, no Python deps)
3. **JPIP Phase 1 response parser** — 2-3 weeks
4. **IncrementalJ2KDecoder completion** — 2-3 weeks

If you want me to slow the shipping cadence (e.g., one release per
week instead of multiple per day), tell me when you resume and I'll
adjust the autonomous-continue behaviour accordingly.
