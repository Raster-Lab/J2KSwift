# J2KSwift v11.0.0

**Dead-weight removal + packaging — ~125K deleted lines, an unsafeFlags-free manifest, and J2KSwift finally consumable as a versioned SwiftPM dependency.**

This is a **MAJOR** release because exported products are removed. It contains
**zero codec behaviour change**: codestream bytes and decoded pixels are identical
to v10.25.0 (no codec source file's logic was touched — the only codec-adjacent
edits delete never-referenced code), and the warm A/B confirms performance is
unchanged. Every removal candidate was verified reference-free by a 25-agent
sweep with adversarial re-checks before deletion.

---

## Summary

The 2026-06-10 optimization audit identified ~48K lines of production-dead code
accumulated over the project's research arcs. v11.0.0 removes it — and fixes the
packaging defect that prevented any package from depending on J2KSwift by version.

| Metric (Apple M2) | v10.25.0 | v11.0.0 | Δ |
|---|---:|---:|---:|
| Clean debug build (wall) | 52.8 s | 39.8 s | **−24.6 %** |
| Clean debug build (CPU) | 196.7 s | 165.1 s | −16.1 % |
| `Sources/` lines | 178,274 | 144,353 | **−33,921 (−19 %)** |
| Whole-repo diff | — | — | **−124,718 lines** (incl. tests + 23 MB artifacts) |
| Tracked repo size | 286.7 MB | 261.7 MB | −25.0 MB |
| `j2k` release binary | 14.69 MB | 12.02 MB | **−18.2 %** |
| `j2kd` release binary | 10.05 MB | 6.38 MB | **−36.5 %** |
| Versioned SwiftPM consumption | ❌ rejected (unsafeFlags) | ✅ **verified working** | — |

## Removed products (the MAJOR part)

| Product | Lines (src+tests) | Why it was dead |
|---|---:|---|
| `J2KAccelerate` | 16,451 | Zero `import J2KAccelerate` anywhere in production. The one known downstream use (DICOMKit's backend-description string) is `#if canImport`-guarded with an `#else` fallback — see Migration. |
| `J2KVulkan` | 4,153 | Apple-Silicon-only product since v8.0.0; the module's own tests asserted Vulkan is unavailable. |
| `J2KXS` | 2,305 | JPEG XS stub untouched since v2.3.0; its J2KCore type leaks removed with it. |

## Removed internal dead code

- **x86 SSE/AVX2** (`Sources/J2KCodec/x86` + Intel benchmark infra) — arm64-only product.
- **MJ2 container stack** in J2KFileFormat (9 files, 33 public symbols, zero callers;
  the J2KCodec/J2KMetal MJ2 video-encoding pieces remain).
- **Dead allocator/pool modules**: `J2KBufferPool`, `J2KHTBlockCoderPooled`,
  `J2KMemoryPool`, `J2KOptimizedAllocator`, `J2KZeroCopyBuffer` (the **live**
  `J2KMetalBufferPool` is untouched).
- **Dead concurrency infra**: `J2KConcurrencyTuning` (work-stealing queue,
  contention analyzer, concurrent pipeline), `J2KThreadPool`, `J2KGCDDispatcher`
  (`J2KQualityOfService` kept — live via JPIP).
- **Benchmark/probe files compiled into production libraries**:
  `J2KRealWorldBenchmarks`, `J2KLosslessDecodingBenchmark`, `J2KReferenceBenchmark`,
  both Metal HT dispatch probes + their kernels (metallib regenerated; the shader
  function inventory drops 74 → 72).
- **Conformance/interop scaffolding** (~15K lines out of J2KCore): the Part-2/3-10/4/15
  one-shot conformance suites, ISO test-suite loader, OpenJPEG interop pipeline +
  benchmark harness, performance-validation report generator, and the Windows/cross-platform
  validation obsolete since the v8 Apple-only narrowing. **Survivors, unchanged
  signatures**: the Part-1 validators behind `j2k validate`
  (`J2KDecoderConformanceClass`, `J2KMarkerSegmentValidator`,
  `J2KCodestreamSyntaxValidator`), the DICOMKit-consumed HT conformance API
  (`J2KErrorMetrics`, `J2KTestVector`, `J2KConformanceValidator`,
  `HTJ2KTestVectorGenerator`, `HTJ2KConformanceTestHarness`,
  `J2KHTInteroperabilityValidator` — now in `J2KHTConformanceAPI.swift`), and the
  OpenJPEG CLI wrapper behind `j2k benchmark --compare-openjpeg`
  (now `J2KOpenJPEGCLI.swift`).
- **Orphan `Sources/` directories** never declared in the manifest
  (DiagTest, AppFlowTest, PipelineTest, LossyDiagnostic, J2KBenchApp).
- **~23 MB of tracked artifacts**: stale profiler outputs and result dumps deleted;
  release-cited benchmark captures moved to `Documentation/Benchmarks/data/`
  (links updated); `.gitignore` hardened against re-accretion.

## Restructured

- `J2KTestAppModels` moved from J2KCore to a new **`J2KTestAppCore`** library
  target. The audit recommended deletion; the verification sweep corrected it —
  the shipping `j2k testapp --headless` command consumes these models via
  J2KCLICore. J2KCore drops ~4.7K lines of SwiftUI view-models that every SDK
  consumer used to compile.

## Packaging — versioned SwiftPM consumption unblocked

The manifest carried `unsafeFlags` on five targets, and **any** `unsafeFlags`
makes a package ineligible as a version-based SwiftPM dependency (path/branch
deps only). All are gone:

- `-O -whole-module-optimization` on J2KCore/J2KCodec — redundant (SwiftPM release
  config already implies both).
- `-parse-as-library` on the three executables — replaced by renaming the entry
  files (`main.swift` → `Entry.swift` / `J2KDaemonMain.swift`) so `@main` works bare.
- The J2KCodecNEON `-O3 -fno-*` block — removed **after** an interleaved warm A/B
  against SwiftPM's default release C optimization: DX −0.44 ms, MG +1.35 ms,
  CT +0.06 ms — all inside the 3 ms acceptance gate (Clang's default `-O` handles
  the NEON intrinsics core fine; consistent with the v10.6 finding that Clang
  auto-optimizes this code well).

**Verified end-to-end**: a scratch consumer package depending on
`.package(url:…, exact: "11.0.0")` resolves, builds, and runs against the
`J2KCodec` product. Before this release SwiftPM rejected the manifest outright.

## Deferred (documented, not removed)

- The legacy non-conformant **`.custom` HT block format** (~4.3K lines + dual
  routing branches): three live consumer chains (the `j2k transcode` /
  `batch-transcode` CLI paths and JPIP) route through it. Removal needs a
  deprecation cycle, not a dead-code sweep.
- Stale env-var experiment gates (J2K_HT_SIMD, J2K_RAW_POINTER_ENGINES,
  J2K_GPU_FORWARD_HT_ENTROPY, J2K_METAL_IDWT_2D, …) are inventoried in the audit
  report; code removal is a future arc.

## Migration

- **DICOMKit**: remove the `J2KAccelerate` product dependency from DICOMCore's
  manifest (one line). Its `#if canImport(J2KAccelerate)` falls to the `#else`
  branch automatically; only a backend-description string changes.
- Consumers of removed products (`J2KAccelerate`, `J2KVulkan`, `J2KXS`) or the
  removed MJ2 container API: these had no functional production pathway in
  J2KSwift; there is no replacement. The MJ2 *video encoding* pieces in
  J2KCodec/J2KMetal are unaffected.
- `swift test` users: the J2KAccelerateTests/J2KVulkanTests/J2KXSTests/
  J2KInteroperabilityTests/PerformanceTests targets no longer exist;
  `Scripts/run-full-regression.sh` is updated.

## Backward compatibility

| Aspect | vs v10.25.0 |
|---|---|
| Codestream bytes (encode, default config) | **byte-identical** (no codec logic touched) |
| Decoded pixels | **bit-identical** |
| Codec performance | unchanged (NEON-flag A/B inside noise; all other removals are never-executed code) |
| Public API | products/symbols REMOVED per the inventory above — MAJOR |

## Test Suite Results

- Mandatory commit gate + every suite the removals touched: **271 tests,
  0 failures, exit 0** (release mode).
- Trimmed conformance suites: 77/77. J2KTestAppTests: 310/310.
- CLI smoke: `j2k validate --part1`, `j2k benchmark --compare-openjpeg`,
  `j2k testapp --headless --playlist "Quick Smoke Test"` all green.
- DICOMKit symbol cross-check: both consumed symbols
  (`J2KHTInteroperabilityValidator`, `HTJ2KConformanceTestHarness`) confirmed in
  the kept API, signatures unchanged.

## Reproducing

```bash
swift test -c release --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'
# versioned-consumption proof
mkdir consumer && cd consumer && swift package init --type executable
# add .package(url: "<J2KSwift repo>", exact: "11.0.0") + product J2KCodec, then:
swift build
```

## Companion documents

- `OPTIMIZATION_AUDIT_2026-06-10.md` — the audit that scoped this arc.
