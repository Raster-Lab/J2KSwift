# J2KSwift v8.1.4 — mmap'd codestream input propagated to other CLI subcommands

**Tag**: `v8.1.4`
**Released**: 2026-05-10
**Headline**: The v8.1.3 `Data(contentsOf:options: [.alwaysMapped])` fix was applied only to the single-file `decode` CLI in `Commands.swift`. v8.1.4 propagates the same fix to the 5 other CLI call sites that were missed: `batch decode`, `batch transcode`, `decode3d`, `info`, `compare` (×2), and `convert`. Codestream bytes byte-identical to v8.1.3.

---

## What v8.1.4 is

A 1-day cherry-pick from the v8.9 research arc (`v8.9-research` branch). The only production-quality finding from v8.9 was that v8.1.3's mmap input optimization landed only in the single-file `decode` path — but five other CLI subcommands were still using eager full-file reads.

## Changed

| File | What changed |
|------|--------------|
| `Sources/J2KCLI/Batch.swift` | mmap on `batch decode` (line 156) + `batch transcode` (line 189) |
| `Sources/J2KCLI/Decode3D.swift` | mmap on JP3D decode |
| `Sources/J2KCLI/Info.swift` | mmap on info inspection |
| `Sources/J2KCLI/Compare.swift` | mmap on both J2K comparison reads (lines 46, 54) |
| `Sources/J2KCLI/Convert.swift` | mmap on J2K → image conversion |
| `Sources/J2KCore/J2KCore.swift` | `getVersion()` returns `"8.1.4"` |

## Why mmap helps

`Data(contentsOf:url, options: [.alwaysMapped])` returns a `Data` view backed by `mmap`'d file pages instead of an eager copy into anonymous memory. The decoder reads bytes lazily as the codestream is parsed; pages fault in only when actually touched. For large codestreams (DX = 12 MB), this saves ~1-3 ms of the eager memory copy on cold-shot.

For batch flows (`j2k batch decode -i dir/`), the savings compound across N files. An 8-file DX batch saves ~24 ms via deferred load amortisation.

## Backward compatibility

- **Codestream bytes byte-identical to v8.1.3**. No encoder change.
- **No public Swift API changes**.
- **No CLI flag changes**. Existing scripts work unchanged.
- `getVersion()` returns `"8.1.4"`.

## SemVer rule

**PATCH** per RELEASING.md — bug fix (missed CLI call sites in v8.1.3); no public API removed; no codestream byte change.

## Test Suite Results (release mode, 0 failures)

| suite | tests | result |
|---|---:|---:|
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | 2/2 passed |
| `J2KMedicalCorpusPerformanceTests` | 2 | 2/2 passed |
| `J2KStrictCrossCodecValidationTests` | 3 | 3/3 passed |
| `HTTileParityMatrixTests/testTileParityMatrixOnLargeFixtures` | 1 | passed (12/12 cells × 3 decoders = 36/36 bit-exact) |

## Cross-codec parity matrix (re-validated)

`HTTileParityMatrixTests.testTileParityMatrixOnLargeFixtures` — 12 cells (4 fixtures × 3 tile modes) × 3 external decoders (OpenJPH 0.27.0, Grok 20.3.0, Kakadu 8.4.1 demo) = **36/36 cross-decode comparisons bit-exact** (max diff = 0). Codestream bytes preserve the v8.1.3 invariants.

## Research provenance

Productisation of the v8.9 research arc, kept open as `v8.9-research` branch. That branch contains 5 phase-0 probes:

1. **Daemon batch RPC** — wash (in-process `j2k batch` already amortises everything)
2. **Daemon concurrent dispatch** — wash (in-process parallel CLI is already faster than daemon under load)
3. **CLI cold-shot decomposition** — structural ceiling (3.28 ms Swift-runtime floor)
4. **Lazy encoder component init** — N/A (J2KEncoder is value-type, no eager init)
5. **mmap input propagation** — WIN (this release)

Total lever-ceiling investigations on M2 + Swift release: **16**. The codec hot-path AND the IPC layer AND the CLI layer are all at structural ceiling.

## Reproducing

```bash
swift test -c release --filter \
  'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests|HTTileParityMatrixTests/testTileParityMatrixOnLargeFixtures'
```

## References

- v8.1.3 release: [`RELEASE_NOTES_v8.1.3.md`](RELEASE_NOTES_v8.1.3.md) — daemon opt-in default + smart-routing + encoder support + initial mmap input
- v8.9 research summary: [`V8_9_RESEARCH_SUMMARY.md`](../research/V8_9_RESEARCH_SUMMARY.md) (on the `v8.9-research` branch)
- Cross-codec parity matrix: [`Documentation/BENCHMARK.md`](Documentation/BENCHMARK.md)
