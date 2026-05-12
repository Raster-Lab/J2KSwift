# Releasing J2KSwift

This document is the **single source of truth** for J2KSwift's branching model and release process. Every release from v6.0.1 onward follows it. Updates to the process land via a PR that edits this file.

---

## Branching model — trunk-based with release branches

J2KSwift uses a **trunk-based** model anchored on `main`:

| branch | role | lifetime | who owns |
|---|---|---|---|
| `main` | Trunk. Always releasable. Tags are cut from here. | Permanent | Everyone (PR-only) |
| `feature/<scope>-<topic>` | New work (multi-tile, GPU, codec features, etc.) | Until merged to `main` | Author |
| `fix/<scope>-<topic>` | Bug fixes | Until merged to `main` | Author |
| `vX.Y.Z-release-candidate` | Release prep (notes + final review) | Until merged to `main` and tagged | Releaser |
| `release/vX.Y.Z` | Post-release frozen mirror of the tag, used for hotfixes | Permanent (one per release) | Auto-created by [`release.yml`](.github/workflows/release.yml) |
| `hotfix/vX.Y.(Z+1)` | Patch on top of an existing `release/vX.Y.Z` | Until tagged + cherry-picked back to `main` | Releaser |

There is **no `develop` branch.** The stale `develop` reference in earlier `CONTRIBUTING.md` is removed in the same PR that lands this file.

### Why trunk-based + release branches

- Single maintainer pattern works without an integration branch
- `release/vX.Y.Z` mirrors the tag — it gives hotfixes a stable base without rewinding `main`
- PRs to `main` are the only way new work lands; the CI gate enforces that

---

## Versioning — SemVer 2.0 with project-specific guardrails

J2KSwift follows [SemVer 2.0](https://semver.org/spec/v2.0.0.html). The project applies these rules concretely:

| change | bump | example |
|---|---|---|
| Public API removed, signature changed, or default behaviour flipped | **MAJOR** | v5.38.0 → v6.0.0 was tested as MAJOR-eligible because of `.auto` becoming production default |
| New public type / function / config option, **default unchanged**, codestream bytes byte-identical on default config | **MINOR** | v5.37 → v5.38 (M-series) added new test harnesses without changing defaults |
| Bug fix, perf improvement, doc-only change, CI fix | **PATCH** | this PR (release.yml fix) is patch-eligible |

**Special rules for J2KSwift**

- **Codestream bytes are part of the public contract.** A bytes-changing default flip is automatically MAJOR even if no Swift API changed.
- **Opt-in flags do not count as default changes.** `J2K_GPU_FORWARD_53=1` shipping default-off in v6.0.0 is MINOR-eligible. The MAJOR bump came from `.auto` flipping default tile-mode policy.
- **Lossy changes are out of scope** as of 2026-05-05 (see `feedback_lossless_only_v5_38.md`). No version may ship behaviour that affects `.lossless = false` codestreams unless the scope is explicitly re-opened.

---

## Release scope expectations

**Every minor / major release should include performance work spanning both HTJ2K (Part-15 high-throughput) and general J2K (Part-1 / codestream / tier-2 / file format) where actionable.** The codec library's product target is bit-exact lossless medical archive performance; sustained measurable wins are the user-visible value of each release. Planning a release that ships only one side (e.g., HTJ2K-only or codestream-only) is allowed when no actionable lever exists on the other side, but the release notes must say so explicitly.

Concretely, when planning a release:

- Open with the **stage breakdown** from the previous release's hot path (`EncodeStageProfileLosslessCorpusTests` for the lossless 5/3 path; the equivalent decode breakdown when relevant). The biggest unaccelerated stage is the natural HTJ2K target.
- Identify at least one **non-HTJ2K J2K** lever per release — sub-stage profiling of preprocess / colour / codestream marker writes / tier-2 algorithmic batch writes / decoder-side hot paths / etc. Even a "we measured this stage and it's not the lever" finding (cf. PRs #307, #308) counts as J2K perf work because it informs the next release's planning.
- A release with no measurable wall-time win (perf wash, like the v6-alpha6 entropy arc) is acceptable when the empirical data is the deliverable. Document the wash in the release notes; don't pretend a wash is a win.

Patch releases (hotfixes off `release/vX.Y.(Z-1)`) are exempt from this expectation — they ship targeted bug fixes only.

---

## Standard release flow

Every step below has a command. None of them are interactive.

### 1. Confirm `main` is releasable

```bash
git checkout main && git pull --ff-only
git status              # working tree clean
git log --oneline v$(git describe --tags --abbrev=0)..HEAD | wc -l   # count commits since last tag
```

### 2. Run the mandatory commit gate (release mode)

Per `feedback_commit_gate.md`. **Required for every release.** No exceptions.

```bash
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'
# Must show: Executed N tests, with 0 failures
```

If any test fails, **stop**. Diagnose, fix on a `fix/...` branch, PR, merge, restart from step 1.

### 3. Author `RELEASE_NOTES_vX.Y.Z.md`

Mirror `RELEASE_NOTES_v6.0.0.md` structure. Mandatory sections:

- Summary (2-3 paragraphs, lead with the headline)
- What's New — production-default
- What's New — opt-in (if any)
- Backward compatibility (codestream byte equality vs prior tag)
- **Cross-codec parity matrix** — fresh measurement on the medical
  corpus across at least three external decoders (OpenJPH 0.27.0,
  Grok 20.3.0, Kakadu 8.4.1 demo); cell count and bit-exactness
  must be in the release notes, not just cited from a companion
  doc. Re-run `HTTileParityMatrixTests.testTileParityMatrixOnLargeFixtures`
  + `HTGPUForward53CrossCodecTests` for the data.
- **Medical-corpus benchmarks** — fresh wall-time table for
  encode + decode across the 6 corpus fixtures (MR-small, CT,
  MR 886², XA, PX, DX). Re-run `J2KMedicalCorpusEncodePerformanceTests`
  + `EncodeStageProfileLosslessCorpusTests` (or equivalents) for
  the data; the release-mode median should be inline in the notes.
- Test Suite Results (gate + new validation suites + cell counts)
- API surface (additions only, no breaks)
- Known limitations
- Reproducing the headline numbers (commands)
- Companion documents (BENCHMARK_REPORT_*.md, etc.)

### 4. Cut the release-candidate branch from `main`

```bash
TAG=v6.0.1   # whatever you're releasing
git checkout -b ${TAG}-release-candidate
git add RELEASE_NOTES_${TAG}.md
git commit -m "release: ${TAG} — <one-line headline>"
git push -u origin ${TAG}-release-candidate
```

### 5. Open the PR

```bash
gh pr create --base main --head ${TAG}-release-candidate \
  --title "release: ${TAG} — <one-line headline>" \
  --body-file <(cat <<EOF
## Summary
<3 bullets — what's the headline?>

## Correctness gate (release mode)
<paste J2KMedicalCorpus*PerformanceTests + J2KStrictCrossCodecValidationTests pass-counts>

## Test plan
- [x] Mandatory pre-release gate
- [x] Cross-codec parity matrix vs OpenJPH/Grok/Kakadu
- [x] CrossVersionDeltaBenchmark vs previous tag (codestream MD5 equality where promised)
EOF
)
```

### 6. Review and merge

PR must be reviewed (or self-reviewed if solo) and **merged with a merge commit** (preserves the per-feature commit history that release notes reference). Squash merges are forbidden for release PRs.

```bash
gh pr merge <number> --merge --delete-branch=false
```

### 7. Tag from `main` and push

```bash
git checkout main && git pull --ff-only
git tag -a ${TAG} -m "${TAG}: <headline>

<one-paragraph summary copied from RELEASE_NOTES top-of-file>"
git push origin ${TAG}
```

### 8. Verify the release workflow

The tag push triggers [`release.yml`](.github/workflows/release.yml). It:

1. Creates the GitHub release using `RELEASE_NOTES_vX.Y.Z.md` as the body
2. Creates the `release/vX.Y.Z` branch from the tag

Watch it:

```bash
gh run list --workflow=release.yml --limit 1
gh run watch $(gh run list --workflow=release.yml --limit 1 --json databaseId -q '.[0].databaseId')
```

If the workflow fails, fall back to the **manual publish** path:

```bash
gh release create ${TAG} --title "${TAG} — <headline>" \
  --notes-file RELEASE_NOTES_${TAG}.md
git push origin ${TAG}:refs/heads/release/${TAG} \
  || (git checkout -b release/${TAG} ${TAG} \
      && git push -u origin release/${TAG} \
      && git checkout main)
```

(v6.0.0 used the manual fallback because the validate job was wedged on a sibling-package dep. Fixed in v6.0.1.)

---

## Hotfix flow

For a defect that ships in `vX.Y.Z` and needs a patch release without picking up everything that's accumulated on `main` since:

```bash
TAG=v6.0.1   # the patch you're cutting
PRIOR=v6.0.0 # the release you're patching

# 1. Branch from the frozen release branch (NOT main).
git fetch origin
git checkout -b hotfix/${TAG} origin/release/${PRIOR}

# 2. Apply the fix. Keep the diff minimal — no opportunistic refactors.
$EDITOR <fix>
git commit -m "fix: <one-line description>"

# 3. Run the full mandatory gate.
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# 4. Author RELEASE_NOTES_${TAG}.md (short — one section: "Fixed").
git add RELEASE_NOTES_${TAG}.md && git commit -m "release: ${TAG} — <headline>"

# 5. Push the hotfix branch and PR into release/${PRIOR} (NOT main).
git push -u origin hotfix/${TAG}
gh pr create --base release/${PRIOR} --head hotfix/${TAG} \
  --title "release: ${TAG} — <headline>"
gh pr merge <num> --merge --delete-branch=false

# 6. Tag from release/${PRIOR} and push (triggers release.yml).
git checkout release/${PRIOR} && git pull --ff-only
git tag -a ${TAG} -m "${TAG}: <headline>"
git push origin ${TAG}

# 7. Cherry-pick the fix back to main so it doesn't regress.
git checkout main && git pull --ff-only
git cherry-pick <hotfix-sha>
git push origin main
```

The hotfix tag never goes through `main` first — `main` may carry incompatible work-in-progress that the hotfix recipient explicitly doesn't want. Cherry-pick afterwards to keep history aligned.

---

## Pre-commit gate (every commit, not just releases)

Per `feedback_commit_gate.md`:

```bash
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'
```

If you're committing on a `feature/...` or `fix/...` branch the gate is **strongly recommended**. If you're committing on a `vX.Y.Z-release-candidate` or `hotfix/...` branch the gate is **mandatory**. CI does not currently enforce this; the discipline is human.

---

## CI workflows that affect releases

| workflow | trigger | what it does | release-blocking? |
|---|---|---|---|
| [`release.yml`](.github/workflows/release.yml) | `push` of tag matching `v*.*.*` | Creates GitHub release + `release/vX.Y.Z` branch | No (we have a manual fallback) |
| [`ci.yml`](.github/workflows/ci.yml) | every PR | Build + general tests | Yes — PRs to `main` should pass |
| [`conformance.yml`](.github/workflows/conformance.yml) | every PR | HTJ2K Part-15 conformance | Yes for codec-touching PRs |
| [`performance.yml`](.github/workflows/performance.yml) | every PR | Perf benchmark with regression budget | Advisory — review numbers, doesn't auto-block |

`release.yml` previously had a `Validate Release` job that built the package on `macos-15`. It was removed in v6.0.1 because the workflow can't resolve the sibling-path dep `../CompressionFamily` — that dep isn't on a remote, so CI can never resolve it. The mandatory commit gate (run locally before tagging) is stricter than `swift build -c release` and serves the same purpose.

If `CompressionFamily` is ever pushed to a private GitHub repo, restore the Validate job and add a sibling-checkout step:

```yaml
- name: Checkout CompressionFamily sibling
  uses: actions/checkout@v4
  with:
    repository: Raster-Lab/CompressionFamily
    path: ../CompressionFamily
    ssh-key: ${{ secrets.COMPRESSION_FAMILY_DEPLOY_KEY }}
```

---

## Release artefacts checklist

Before pushing the tag, every release should have on `main`:

- [ ] `RELEASE_NOTES_vX.Y.Z.md` at repo root
- [ ] **`README.md` updated** — `Current Version` line bumped to `X.Y.Z`, `Previous Release` line moved to the prior tag, **AND** a new paragraph appended to the `## 📦 Release Status` section summarising the release headline + a link to `RELEASE_NOTES_vX.Y.Z.md`. **Mandatory for every release type** (patch, minor, major, hotfix). Skipping this leaves the public-facing README stale and silently misleads consumers about the project's current state.
- [ ] All work in the release explicitly tested by the mandatory commit gate (release mode, 0 failures)
- [ ] If codestream bytes change vs previous tag, a `CROSS_VERSION_DELTA_REPORT.md` updated and committed (or a section appended) showing what's the same and what's not
- [ ] If a new validation suite was added, listed in the Test Suite Results table of the release notes with cell count
- [ ] **Cross-codec parity matrix** measured fresh and inline in the release notes — at minimum 7 medical fixtures × {OpenJPH, Grok, Kakadu} = 21 cells, with the bit-exactness count visible in the notes
- [ ] **Medical-corpus benchmarks** measured fresh and inline — encode + decode wall time (median of 5, release mode) for the 6 corpus fixtures, and a stage breakdown when relevant to the release's headline (e.g., when a stage's contribution shifted)
- [ ] **Canonical warm cross-codec benchmark run** — `python3 Scripts/benchmarks/cross_codec_warm_bench.py --output benchmark-results-$(uname -m)-vX.Y.Z-$(date +%Y%m%d).json`. The output JSON file is committed to the repo root and the markdown tables are pasted into `RELEASE_NOTES_vX.Y.Z.md`. **Mandatory from v9.6 onwards** for any release that quotes encode/decode wall times — this is the authoritative apples-to-apples warm methodology backing public performance claims. See [`Documentation/BENCHMARK.md`](Documentation/BENCHMARK.md) "Canonical warm cross-codec benchmark" section for the rationale. Runs in ~5-10 minutes on M-series silicon. Releases that change ONLY documentation (e.g. v9.5.2) may skip this if no perf number is asserted.

After pushing the tag, every release should have on `origin`:

- [ ] Tag `vX.Y.Z` annotated, on `main` (or `release/vX.Y.(Z-1)` for hotfixes)
- [ ] GitHub release at `https://github.com/Raster-Lab/J2KSwift/releases/tag/vX.Y.Z`, body = release notes
- [ ] Branch `release/vX.Y.Z` from the tag

---

## Rollback

If a release ships and is found broken, **don't delete the tag**. Tags are immutable contracts; consumers may already have pulled them. Instead:

1. **Mark the GitHub release as a pre-release** so it stops appearing as latest:
   ```bash
   gh release edit vX.Y.Z --prerelease
   ```
2. **Cut a hotfix `vX.Y.(Z+1)`** that fixes the regression (see Hotfix flow above).
3. **In `RELEASE_NOTES_vX.Y.(Z+1).md`**, lead with: *"This release supersedes vX.Y.Z, which contained <description>. Users on vX.Y.Z should upgrade."*

Force-deleting a published tag is **forbidden**.

---

## FAQ

**Q: When do I bump MAJOR?**
A: When the default config produces different codestream bytes than the prior MAJOR.MINOR.PATCH, OR when public API is removed / signature-changed / behaviour-flipped. v6.0.0 was MAJOR because `.auto` became the default tile mode and that changes bytes for any user who didn't explicitly specify a tile mode.

**Q: Can I tag from a feature branch?**
A: No. Tags come from `main` (releases) or `release/vX.Y.Z` (hotfixes). Always.

**Q: Can I push directly to main?**
A: Only the auto-created release `merge` commit (from `gh pr merge`) and the auto-created tag bumps. Code changes go through PR every time.

**Q: Where does the v5.38.0 → v6.0.0 jump come from?**
A: 26 commits accumulated as the v6-alpha[1-5] phases over a few weeks; once `.auto` flipped to the production default and the GPU forward path landed behind an env gate, the next tag was MAJOR-eligible. The `v5.39.x` slot was effectively reserved by the v5.39 M1-M3 SIMD experiments which were parked (committed, but not in the production hot path).

**Q: What if `release.yml` fails like it did for v6.0.0?**
A: Use the **manual publish** commands in step 8 above. The release artefact is what matters; the workflow is convenience.
