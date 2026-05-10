# J2KSwift v8.1.0 — `j2kd` XPC daemon adoption push

**Tag**: `v8.1.0`
**Released**: 2026-05-10
**Headline**: Three new CLI subcommands turn the v8.0.0 manual 5-step `j2kd` install into a single command. End-to-end CLI gap on DX 2800×2288 closes from 72 ms cold-shot → ~55 ms with the daemon installed (–24 % wall) — the user-visible payoff of the v8.0.0 phase 6 daemon work, now one command instead of five shell invocations.

---

## What v8.1.0 is

Pure deployment-side work. **Codestream bytes byte-identical to v8.0.1.** No decoder change. The v8.4 lever-ceiling investigation (PR #402) confirmed the M2 + Swift release decoder hot path has no extractable single-codec wins remaining; this release pursues the highest-leverage move available — making the already-shipped `j2kd` daemon trivial to install.

## What's new — opt-in CLI subcommands (macOS)

### `j2k daemon-install`

Replaces the v8.0.0 manual 5-step install (build, copy, sed plist, copy plist, `launchctl load`). Layout is per-user (no sudo):

| artefact | path |
|---|---|
| binary | `~/Library/Application Support/J2KSwift/j2kd` |
| plist | `~/Library/LaunchAgents/com.raster.j2kd.plist` |

Locates the `j2kd` binary in priority order: `--daemon-binary <path>` flag → sibling of the running `j2k` binary → `.build/release/j2kd` in CWD. The plist is rendered from an embedded template with the resolved binary path.

After copy + plist write, runs `launchctl bootstrap gui/<UID> <plist>` (modern API; falls back to `launchctl load` on older macOS) and verifies the install with a real XPC ping.

### `j2k daemon-uninstall`

Reverses the install. `launchctl bootout` (with legacy `unload` fallback), removes the plist, removes the binary. `--keep-binary` flag preserves the binary for re-install.

### `j2k daemon-status`

Reports the install state — checks binary presence, plist presence, launchd service load state via `launchctl print`, and Mach service reachability via a real XPC ping (the v8.0.0 `J2KDaemonClient.isAvailable` is optimistic — `daemon-status` does the actual round-trip). Human-readable output by default; `--json` for scripting.

## Headline CLI gap reduction (DX 2800×2288 cold-shot)

| version | DX CLI cold | Kakadu gap |
|---|---:|---:|
| pre-v8 (v7.5.1) | 134 ms | 4.0× |
| v8.0.0 (Phase 1-4) | 89 ms | 2.47× |
| **v8.1.0 + `daemon-install`** | **~55 ms** | **~1.5×** |

Pure decoder work was exhausted at v8.0.0 (4 lever-ceiling investigations). The remaining 24 ms tax was Metal cold-start per CLI invocation; the daemon eliminates it by amortising the warm `J2KMetalSession.processShared` across calls. The `daemon-install` subcommand makes that elimination one command instead of five.

## Backward compatibility

- **Codestream bytes byte-identical to v8.0.1**.
- **Public API additions only** (3 new CLI subcommands; no Swift API surface changes).
- **`getVersion()` returns `"8.1.0"`**.
- **Existing `j2k daemon-ping` is unchanged** — flat `daemon-X` style preserved.
- The v8.0.0 manual install path still works (the new install command writes to a different layout — `~/Library/Application Support/J2KSwift/` instead of `/usr/local/bin/`).

## SemVer rule

**MINOR** per RELEASING.md — new public CLI surface (`daemon-install`, `daemon-uninstall`, `daemon-status`); no removals; no signature changes; codestream bytes unchanged.

## iOS / iPadOS

The `j2kd` daemon model isn't applicable on iOS — XPC LaunchAgent registration is macOS-only. iOS apps use `J2KDecoder.preWarm()` (shipped in v8.0.0 Phase 6.1) for the same warm-process effect. All three new subcommands are gated `#if os(macOS)`; iOS builds compile clean with the subcommands stubbed to a "macOS-only" message.

## Test Suite Results (release mode, 0 failures)

| suite | tests | result |
|---|---:|---:|
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | 0 failures (29.971 s) |
| `J2KMedicalCorpusPerformanceTests` | 2 | 0 failures (9.784 s) |
| `J2KStrictCrossCodecValidationTests` | 3 | 0 failures (0.481 s) |

End-to-end install round-trip verified on Apple M2 / macOS 26.x:

```
$ j2k daemon-status                     # all ✗ (clean state)
$ j2k daemon-install                    # all ✓ (Mach service reachable)
$ j2k daemon-status --json              # machine-readable
$ j2k daemon-uninstall                  # all ✗ (clean state)
```

## Companion documents

- `V8_4_DECODE_LEVER_CEILING_CONFIRMED.md` — why v8.1.0 is deployment-side work, not decoder optimisation
- `V8_2_0_MG_CORRUPTION_ROOT_CAUSE.md` / `V8_3_0_GPU_IDWT_ROOT_CAUSE.md` — context for the v8.0.1 patch release
- `RELEASE_NOTES_v8.0.0.md` — original `j2kd` daemon scope (Phases 6.3-6.6)

## Reproducing

```bash
swift build -c release --product j2k --product j2kd

# One-shot install
.build/release/j2k daemon-install

# Verify
.build/release/j2k daemon-status
.build/release/j2k daemon-ping

# Mandatory pre-release gate
swift test -c release --filter \
  'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Cleanup
.build/release/j2k daemon-uninstall
```
