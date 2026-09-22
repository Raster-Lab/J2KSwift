# CI/CD Workflows

This directory contains the J2KSwift GitHub Actions workflows. From
2026-05-27 to 2026-09-22 **only cloud-mandatory workflows remained** —
everything that could run locally was removed to reduce GitHub Actions
billing. `ci.yml` was added on 2026-09-22 under contract 0.8.0, which
makes executing CI a precondition for relocating this codec into
SwiftJ2K. It is deliberately shaped to avoid recreating the 2026-05-27
billing problem; see "Why ci.yml costs little" below.

## Remaining cloud workflows

### `ci.yml`
**Triggers**: `pull_request`, `push` to `main`, `workflow_dispatch`
**Runners**: `ubuntu-24.04` for every automatic job; `macos-15` build-only on PR

The build and test gate. Five tiers, ordered by cost:

| Tier | Job | Trigger | Runner | Billing |
|---|---|---|---|---|
| 1 | `linux-build` | PR + main | ubuntu-24.04 | 1x |
| 1 | `linux-tests` (bounded set) | PR + main | ubuntu-24.04 | 1x |
| 2 | `apple-build` (no tests) | PR + main | macos-15 | 10x, build only |
| 3 | `codec-tests` (J2KCodecTests) | main + dispatch | ubuntu-24.04 | 1x |
| 4 | `apple-tests` (matrix) | **dispatch only** | macos-15 | 10x |
| 5 | `metal-tests` | **dispatch only** | macos-15 | 10x |

#### Why `ci.yml` costs little

The 2026-05-27 deletion happened because ~14 `macos-15` runs per release at a
75-minute cap approached $420 for a single day. Four rules keep that from
recurring:

1. **Linux does the work.** Metal, Accelerate, VideoToolbox and CoreVideo are
   all behind `canImport` guards in `Sources`, so the package is structurally
   buildable for Linux at a tenth of the macOS rate.
2. **macOS builds but does not test on a PR.** A compile break is what an
   Apple-only job realistically catches on a pull request.
3. **The full suite is not in cloud CI.** It measured 4,948 executed tests in
   3h38m for `v11.1.0-rc.1` — roughly 2,200 billable macOS minutes per run. It
   stays a local gate, as `RELEASING.md` requires.
4. **No `schedule:` trigger.** Nothing starts unattended. The 10x tiers are
   `workflow_dispatch` only.

The mandatory performance commit gate in `RELEASING.md` deliberately does not
run here: PERF-02 makes controlled hardware the release gate and CI wall-clock
on a shared runner advisory only.

#### Two things to know before editing it

- **Never add `--scratch-path`.** `J2KCLITests` resolves the built CLI at the
  hardcoded path `.build/debug/j2k`. A non-default scratch path is what
  produced the 8 spurious failures recorded in the `v11.1.0-rc.1` notes.
- **The Linux jobs are unproven.** No Linux build of this package has ever been
  executed. If `linux-build` fails on its first run, that is the job working,
  not the workflow being wrong.

### `release.yml`
**Triggers**: `push` of `v*` tag, `workflow_dispatch`
**Runner**: `ubuntu-latest` (Linux — cheap)

Auto-creates the GitHub Release page using `RELEASE_NOTES_vX.Y.Z.md`
as the body when a `v*` tag is pushed. Cloud-mandatory because it
uses GitHub's release-creation API.

### `create-release-branches.yml`
**Triggers**: `workflow_dispatch` only
**Runner**: `ubuntu-latest` (Linux — cheap)

Creates `release/vX.Y.Z` mirror branches from existing tags. Cloud-
mandatory because it pushes new refs to origin. Manual-dispatch only,
so zero unsolicited cost.

## Workflows removed 2026-05-27

The following workflows were deleted to reduce billing. Their functions
are preserved through local-test alternatives:

| Removed workflow | Local replacement |
|---|---|
| `ci.yml` (macos-15 Build + Test) | superseded by the new `ci.yml` described above |
| `swift-build-test.yml` (macos-15 Build + Test — duplicate of ci) | same |
| `code-quality.yml` (macos-15 SwiftLint) | `swiftlint --strict` locally |
| `conformance.yml` (macos-15 Part-1 + Part-15 conformance, 75-min cap) | `swift test -c release --filter J2K*ConformanceTests` |
| `jp3d-compliance.yml` (macos-15 JP3D compliance) | `swift test -c release --filter "JP3D\|J2KCompliance"` |
| `dicomkit-downstream.yml` (macos-15 downstream consumer build) | manual `swift build` of the consumer repo |
| `performance.yml` (macos-15 benchmarks, 75-min cap) | `swift test -c release --filter "J2KMedicalCorpus*PerformanceTests"` (the mandatory commit gate per `feedback_commit_gate.md`) |
| `documentation.yml` (macos-15 docs build + pages deploy) | `swift package generate-documentation` locally |
| `interactive-testing.yml` (macos-15 scheduled / manual) | manual local run |

## Restoring a workflow

If you want to bring one back, `git log` will show the deletion commit
and `git show <sha>:.github/workflows/<name>.yml > .github/workflows/<name>.yml`
restores the file from history. The original triggers/jobs are
recoverable verbatim.

## Why this state

5 releases were shipped on 2026-05-26 (v10.15.0 → v10.19.0). Each release
triggered ~14 macos-15 workflow runs (PR open + merge to main + tag
push), with the per-job timeout configured at 75 minutes. Even at
typical run times of 8–15 min the day's billing was significant; at
the 75-min cap it would have been ~$420 for the day. After repeated
restrictions on triggers didn't move the needle far enough, the
non-mandatory workflows were deleted entirely. The local commit gate
(`feedback_commit_gate.md`) carries the actual correctness contract;
the cloud workflows were redundant verification.
