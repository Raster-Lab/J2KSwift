# J2KBenchApp — A-series cross-silicon bench

Shareable SwiftUI iOS app that drives the same warm in-process bench
the M2/M4 canonical runs do, on whatever Apple Silicon device it's
installed on. The output JSON drops into
`Documentation/Benchmarks/data/` next to the
`benchmark-results-Mac142-…json` / `…Mac1610-…json` baselines and is
consumed by `Scripts/benchmarks/compare_hosts.py` without
modification.

Why this exists: v10.5's [cross-silicon arc](../../Documentation/research/V10_5_CROSS_SILICON_PROBE.md)
needs A-series readings, but `Scripts/benchmarks/run_canonical_bench.sh`
can't deploy to iOS — no fork/exec, no `launchd` daemon, no
`kdu_expand` inside the iOS app sandbox. This app substitutes the
in-process J2KSwift lane (encode + decode across `.cpu` /
`.decodeGPU` / `.decodeWithGPUHT`); the cross-codec lanes (Kakadu /
OpenJPH / Grok) stay macOS-only.

## Running on your iPhone

The bench app ships as an iOS **`.xcodeproj`** wrapper at
`Sources/J2KBenchApp/J2KBenchApp.xcodeproj` (generated from
`project.yml` with [xcodegen](https://github.com/yonaskolb/XcodeGen)).
SwiftPM-only executable targets aren't proper iOS `.app` bundles, so
they can't sign or install on a device — the xcodeproj wraps the same
sources with automatic provisioning.

1. **One-time Xcode account setup.** Open Xcode → Settings → Accounts
   → tap **+** → sign in with the Apple ID that owns your iOS
   developer team. Free Apple IDs work too (7-day app lifetime per
   install).
2. Open `Sources/J2KBenchApp/J2KBenchApp.xcodeproj`.
3. Click the **J2KBenchApp** target → **Signing & Capabilities** tab
   → tick **Automatically manage signing** → pick your **Team** from
   the dropdown. Xcode will generate a provisioning profile against
   your Apple ID on first run. If the bundle ID `in.raster.j2k.bench`
   collides with another developer's account, change it to anything
   unique (e.g. `<yourdomain>.j2k.bench`).
4. Connect your iPhone via USB. Pick it as the run destination at the
   top of the Xcode window.
5. Hit **Run** (⌘R). On first run, trust the developer cert under
   *Settings → General → VPN & Device Management* on the iPhone.
6. In the app, tap **Run Benchmark**. The bench takes 2–6 minutes
   depending on the device (large mammography fixtures dominate the
   wall time).
7. Tap **Share JSON** when complete and AirDrop / Mail / Message the
   file back. Filename is
   `benchmark-results-<model>-<j2k-version>-warm-inproc-<YYYYMMDD>.json`
   so it lands in the correct bucket on the compare side.

### Regenerating the xcodeproj after source edits

The xcodeproj is committed but the source of truth is `project.yml`.
If you add a new Swift file, change the bundle ID, or bump the
deployment target, regenerate with:

```bash
brew install xcodegen   # one-time
cd Sources/J2KBenchApp && xcodegen generate
```

## What it measures

7 small/mid synthetic + 3 medical-class large fixtures, same LCG
seeds as `Scripts/benchmarks/generate_synthetic_corpus.py`. Each
fixture:

* **Encode** — HT-J2K conformant lossless (the canonical bench's
  encode config), median of 7 runs after 2 warmups.
* **Decode** — same codestream replayed through three public APIs:
  `J2KDecoder.decode()` (CPU), `decodeGPU()`, `decodeWithGPUHT()`.
  7-run median, 2 warmups, on a pre-warmed
  `J2KMetalSession.processShared`.

That mirrors the in-process arithmetic that
`cross_codec_warm_bench.py --in-proc` runs on macOS, so the JSON is
directly comparable.

## What it does NOT measure

* Cross-codec — Kakadu, OpenJPH, Grok aren't reachable from inside
  an iOS app sandbox. The macOS canonical bench still owns those
  lanes.
* Daemon / CLI lanes (`--sustained`, `--isolated`) — same reason:
  no `launchd`, no subprocess.
* Real-medical-PGM corpus — fixtures are deterministic LCG-noise
  fields. Perf rankings are valid across silicon; absolute byte
  ratios won't match the real-medical PGM reports.

## Distributing to friends/family for Diwali testing

For users who already have Xcode + an Apple ID:

* Share the repo (or just the `Sources/J2KBenchApp/` + `Package.swift`
  pair via a private link). They open `Package.swift` in Xcode, pick
  the **J2KBenchApp** scheme, plug in their device, hit Run, and
  AirDrop the resulting JSON back.

For users without Xcode:

* Build + export an IPA from your developer account, then sideload
  via AltStore / Sideloadly. Free-tier sideloads expire after 7 days
  per device — fine for a one-off cross-silicon datapoint, but the
  recipient must re-sign if you want a second reading later.

## Filing the JSON

Place the file in `Documentation/Benchmarks/data/`. The
compare script will pick it up by glob:

```bash
python3 Scripts/benchmarks/compare_hosts.py \
    Documentation/Benchmarks/data/benchmark-results-Mac142-10.1.0-warm-inproc-*.json \
    Documentation/Benchmarks/data/benchmark-results-iPhone17*-10.1.0-warm-inproc-*.json \
    --output Documentation/Benchmarks/CROSS_HOST_M2_A18Pro_v10_1_0_inproc.md
```

## Limitations to call out in the comparison report

* iOS power-management throttles sustained workloads after ~20–30
  seconds; the medical-class large fixtures (DX 2544×3056, MG
  3520×4784) can stretch into that window. Run the bench twice and
  compare medians to confirm thermal stability before publishing the
  M-vs-A delta.
* Background-app priority on iOS differs from macOS foreground; lock
  the screen off, plug in power, and leave the app in foreground.
