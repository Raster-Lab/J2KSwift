# J2KSwift v9.5.2 — daemon-install help: SDK vs CLI guidance (doc-only patch)

**Release date:** 2026-05-12
**Base:** `release/v9.5.1` (`698a8ad`)
**Type:** Doc-only patch per RELEASING.md ("doc-only change | PATCH").

## Why this exists

v9.5.0's `daemon-install` help text and the surrounding release narrative
implied the j2kd daemon is the right path for *any* consumer who wants
warm-process encode/decode speed. **Fresh measurement (v10.0-research
Phase 6) on Apple M2 shows that's only true for CLI consumers.** SDK
consumers calling `J2KEncoder.encode(_:)` / `J2KDecoder.decode(_:)` from
inside a long-lived process already pay zero cold-start after the first
call — and going *through* the daemon adds ~20 ms of XPC IPC overhead
they don't need. The previous docs were misleading for the SDK-integration
case.

## Fixed

### `j2k daemon-install --help`

The help text now includes an explicit **WHEN TO USE THE DAEMON** section
and a three-line measurement summary that decomposes the v9.5.0
"daemon-encode large-fixture closure" headline into:

| DX 2800×2288 encode wall (Apple M2) | ms |
|-------------------------------------|---:|
| cold CLI invocation                 | ~112 |
| warm `j2k --daemon` CLI invocation  |  ~62 |
| **warm in-process J2KEncoder.encode()** | **~42** |

The previous help text said *"subsequent `j2k decode` invocations run at
warm-process speed (no Metal cold-start tax per call)"* — correct for
CLI consumers, but misleading for SDK consumers who would assume
"warm-process speed" implies parity with direct in-process encoding.

The new text:

- Distinguishes **CLI consumers (✓ use the daemon)** from **SDK consumers
  (✗ call the codec directly)**.
- Notes that `--daemon` covers both encode and decode (the v8.8 research
  graduation; previous help text only mentioned decode).
- Cites the Phase 6 measurement directly so future readers see the
  trade.

## Why this isn't a code change

No production codec path is modified. Codestream bytes are bit-identical
to v9.5.1 on every default configuration. The pre-release gate
(`J2KMedicalCorpusEncodePerformanceTests` + `J2KMedicalCorpusPerformanceTests`
+ `J2KStrictCrossCodecValidationTests`) passes 7/7 with no changes
expected vs v9.5.1.

The v10.0-research Phase 6 measurement itself remains on the
`v10.0-research` branch per `feedback_research_no_main_merge.md`. This
v9.5.2 release ships only the user-facing doc consequence of that
research, not the research itself.

## Correctness gate (release mode, Apple M2)

```
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'
```

7/7 tests, 0 failures. Bit-identical codestreams to v9.5.1.

## Backward compatibility

- **No public API changes.**
- **No codestream byte changes.**
- **No behaviour changes** in any encoder/decoder/daemon code path.
- `j2k daemon-install --help` output is longer (now includes guidance);
  callers that parse the help text exactly may need to update — but the
  help text is human-facing, not machine-parseable, and no caller
  in the J2KSwift codebase or known integrators parses it.

## Process change: README update mandatory per release

Pre-v9.5.2 the project README was stuck at `Current Version: 8.1.1`
even though v9.0.0 through v9.5.1 had all shipped. The public-facing
landing page was silently misleading consumers about the project's
current state.

v9.5.2 codifies a fix:

- **`RELEASING.md`** "Release artefacts checklist" now requires every
  release to update `README.md` (Current Version line + Previous
  Release line + a new Release Status paragraph). Applies to every
  release type — patch, minor, major, hotfix.
- **`README.md`** brought current as part of this release: bumped to
  9.5.2, Release Status paragraphs added for v9.3.0, v9.4.0, v9.5.0,
  v9.5.1, v9.5.2 (the v9.x sequence that was missing).

## Files changed

```
Sources/J2KCLI/DaemonInstall.swift     (help text: +21 lines guidance)
Sources/J2KCore/J2KCore.swift          (version → 9.5.2)
README.md                              (Current Version + 5 Release Status paragraphs)
RELEASING.md                           (Release artefacts checklist: README update mandatory)
RELEASE_NOTES_v9.5.2.md                (this doc)
```

## Reproducing

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build -c release --product j2k --product j2kd
.build/release/j2k version                # expect 9.5.2
.build/release/j2k daemon-install --help  # see the new guidance
```

The Phase 6 measurement that motivates this patch can be reproduced via:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test -c release --filter V10Phase6DaemonDecompositionTests
```

(Test lives on the `v10.0-research` branch; not part of the v9.5.2
release tarball.)

## Acknowledgements

The SDK-vs-CLI distinction was surfaced by `V10_0_PHASE6_DAEMON_DECOMPOSITION.md`
on the `v10.0-research` branch (commit `eda2116`, 2026-05-12). This v9.5.2
patch is the user-facing consequence of that research, cherry-picked into
the release flow as a doc-only fix.
