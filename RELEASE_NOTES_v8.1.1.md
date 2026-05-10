# J2KSwift v8.1.1 — CI Node 24 opt-in (operational hygiene)

**Tag**: `v8.1.1`
**Released**: 2026-05-10
**Headline**: Adds `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true` to every GitHub Actions workflow that uses Node-20-based actions. Eliminates the deprecation warnings that started 2025-09-19 and pre-empts the 2026-09-16 hard removal of Node 20 from GitHub-hosted runners.

---

## What v8.1.1 is

Pure operational-hygiene release. **No source-code changes** beyond the version bump. Every workflow under `.github/workflows/` (release, ci, conformance, code-quality, documentation, dicomkit-downstream, interactive-testing, jp3d-compliance, performance, create-release-branches) now opts into Node 24 for JavaScript-based actions via the workflow-level env:

```yaml
env:
  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"
```

This is GitHub's own recommended migration path. The action pin versions stay unchanged (`actions/checkout@v4`, `softprops/action-gh-release@v2`); only the Node runtime under which they execute switches from 20 → 24.

## Backward compatibility

- **Codestream bytes byte-identical to v8.1.0**.
- **No Swift API changes**. Pure CI hygiene.
- `getVersion()` returns `"8.1.1"`.
- The Linux / Windows workflows (`linux-arm64.yml`, `swift-build-test.yml`, `windows.yml`) are advisory-only on the Apple-Silicon-first product line per `feedback_apple_only_v8`; they were left untouched in this PR (no JS-actions in those that emit deprecation warnings).

## SemVer rule

**PATCH** per RELEASING.md — pure CI fix; codestream bytes unchanged; no public API change.

## Test Suite Results (release mode, 0 failures)

| suite | tests | result |
|---|---:|---:|
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | 0 failures |
| `J2KMedicalCorpusPerformanceTests` | 2 | 0 failures |
| `J2KStrictCrossCodecValidationTests` | 3 | 0 failures |

## References

- [GitHub blog — Deprecation of Node 20 on GitHub Actions runners (2025-09-19)](https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/)
- v8.1.0 release notes: [`RELEASE_NOTES_v8.1.0.md`](RELEASE_NOTES_v8.1.0.md)

## Reproducing

```bash
swift test -c release --filter \
  'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'
```

CI workflows: trigger any push to `main` or any tag matching `v*.*.*` to verify the deprecation warnings are gone in the run logs.
