# CI/CD Workflows

This directory contains the J2KSwift GitHub Actions workflows. As of
2026-05-27, **only cloud-mandatory workflows remain** — everything that
could run locally was removed to reduce GitHub Actions billing.

## Remaining cloud workflows

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
| `ci.yml` (macos-15 Build + Test) | `swift test -c release` |
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
