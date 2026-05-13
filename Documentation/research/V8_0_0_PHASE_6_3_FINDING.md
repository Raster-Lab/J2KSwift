# v8.0.0 Phase 6.3 — XPC daemon skeleton (macOS-only)

**Captured**: 2026-05-09, Apple M2.
**Phase 6.3 deliverable**: skeleton XPC daemon for macOS — protocol module, daemon executable, in-process round-trip test, launchd plist template. Foundation for Phase 6.4-6.6 which add the decode RPC + CLI client + lifecycle.

## TL;DR

Lands the macOS-only `j2kd` daemon as an SPM executable target. Skeleton scope: a `J2KDaemonProtocol` with one `ping(requestID:reply:)` method, an `NSXPCListener`-based daemon that registers a Mach service (`com.raster.j2kd`), and a 3-test suite that proves the round-trip in-process via `NSXPCListener.anonymous()`.

This is a foundation, not a feature. The CLI doesn't yet talk to the daemon — that's Phase 6.4. The daemon doesn't yet implement decode — that's Phase 6.5. Lifecycle (idle timeout, signal handling) is Phase 6.6.

What ships in this PR proves: **the architecture works.** The protocol is `@objc`-marshalable, NSXPCConnection succeeds, ping/pong round-trips, multiple daemon instances can be tested via anonymous listeners, and the launchd plist template documents the install path for users who want it.

## Architecture

```
+-------------+       Mach service        +-------------+
|             |    com.raster.j2kd        |             |
|   j2k CLI   | ────── NSXPCConnection ──>│  j2kd       │
|   (client)  |                           |  daemon     |
|             |        @objc protocol     |             |
|  fall back  |        J2KDaemonProtocol  |             |
|  to in-proc |                           |             |
+-------------+                           +-------------+
                                                ↑
                                                │ launchd
                                                │ on-demand
                                                │ activation
                                          +─────────────+
                                          │  launchd    │
                                          +─────────────+
```

**Phase 6.3 ships**:
- `Sources/J2KDaemonProtocol/` (library target) — the shared `@objc protocol J2KDaemonProtocol` + the `J2KDaemonMachServiceName` constant. macOS-only at the type level via `#if os(macOS)`.
- `Sources/J2KDaemon/` (executable target) — `j2kd` daemon. Listens on the Mach service registered by launchd, responds to `ping`. macOS-only.
- `Tests/J2KDaemonTests/` — 3 tests, all in-process via `NSXPCListener.anonymous()`:
  1. `testPingRoundTrip_AnonymousInProcess` — full XPC round-trip with reply validation
  2. `testMachServiceNameShape` — sanity-checks the service name constant
  3. `testProtocolIsObjCMarshalable` — `NSXPCInterface(with:)` succeeds (proves @objc compatibility)
- `Resources/launchd/com.raster.j2kd.plist` — install template for users who want to enable the daemon. NOT installed automatically; install steps documented inline.

**Phase 6.3 does NOT ship**:
- Decode RPC (Phase 6.5)
- Real launchd-installed cross-process testing (Phase 6.6)
- CLI client + auto-discovery + fallback logic (Phase 6.4)
- Idle-timeout / lifecycle management (Phase 6.6)

## Why a skeleton-only Phase

Phase 5 finding scoped the XPC daemon as 1-2 weeks of work across 6 sub-phases. Phase 6.3 is the first sub-phase. Splitting the work into smaller PRs:
- Lets each phase have a focused mandatory gate
- Catches integration issues early (the @objc marshaling test in 6.3 catches errors that would otherwise show up in 6.4 with much more code on top)
- Provides a clean revert point if a later sub-phase reveals a flaw in the foundation

## What was VALIDATED

| validation | result |
|---|:-:|
| `swift build -c release` (full package, all targets) | ✓ |
| Daemon executable links + would run | ✓ |
| `J2KDaemonProtocol` is @objc-marshalable | ✓ |
| Anonymous-listener round-trip ping | ✓ |
| Reply payload shape (echoedID, PID, uptime) | ✓ |
| Mandatory gate (10 tests) | ✓ |
| Phase 6.1 warm-decoder API tests (3 tests, both macOS+iOS) | ✓ |
| Phase 6.3 daemon tests (3 tests) | ✓ |
| **16/16 total** | ✓ |

iOS Simulator: build still clean (the daemon target is gated `#if os(macOS)` at every file level).

## launchd plist template

`Resources/launchd/com.raster.j2kd.plist` is provided as a template. Users who want to enable the daemon:

```bash
swift build -c release --product j2kd
cp .build/release/j2kd /usr/local/bin/j2kd
sed -i '' 's|<<J2KD_PATH>>|/usr/local/bin/j2kd|' Resources/launchd/com.raster.j2kd.plist
cp Resources/launchd/com.raster.j2kd.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.raster.j2kd.plist
```

After install, the daemon starts on-demand on the first XPC client connection. Phase 6.4 will add a `j2k daemon-ping` CLI subcommand to test the install.

## Phase 6.4 plan (next sub-phase)

1. Extract `J2KDaemonService` from `Sources/J2KDaemon/main.swift` into `Sources/J2KDaemonProtocol/` (or a new `J2KDaemonCore` library) so daemon AND tests share the implementation rather than duplicating it.
2. Add `J2KDaemonClient` library (macOS-only) that wraps `NSXPCConnection` setup + auto-discovery + fallback.
3. Add `j2k daemon-ping` CLI subcommand to test connectivity.
4. CLI's existing `j2k decode` path: try daemon connection, fall back to in-process if unreachable. **No actual decode RPC yet** — that's Phase 6.5.

## Mandatory gate (release mode, 0 failures)

16/16 pass:
- `J2KMedicalCorpusEncodePerformanceTests` — 2/2
- `J2KMedicalCorpusPerformanceTests` — 2/2
- `J2KStrictCrossCodecValidationTests` — 3/3
- `HTTileParityMatrixTests` — 1/1 (12 cells, 33/33 cross-codec bit-exact)
- `MgRegressionTriageTest` — 2/2
- `V8Phase61WarmDecoderAPITests` — 3/3 (cross-platform warm-decoder API, also runs on iOS)
- `J2KDaemonProtocolRoundTripTests` — 3/3 (Phase 6.3, new)

## Reproduction

```bash
swift build -c release
swift test -c release --filter J2KDaemonTests
```
