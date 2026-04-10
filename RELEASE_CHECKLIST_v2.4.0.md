# J2KSwift v2.4.0 Release Checklist

**Version**: 2.4.0  
**Release Date**: March 30, 2027  
**Release Type**: Minor Release (Phase 21 — Comprehensive CLI Enhancement)

## Pre-Release Verification

### Code Quality
- [x] All mandatory compliance suites pass (182/182 on 2026-04-10)
- [x] Build successful
- [ ] Build successful with no warnings
- [x] Code review completed
- [x] VERSION file updated to 2.4.0
- [x] getVersion() returns "2.4.0"
- [x] Swift 6.2 strict concurrency mode — zero data races
- [x] No memory leaks in new implementations

### New Features (Phase 21)

#### Phase 21a: Codec Variant CLI Commands (Weeks 336–340)
- [x] Enhanced `encode` with `--htj2k`, `--lossless`, `--lossy` shortcuts
- [x] Enhanced `decode` with component selection, marker inspection
- [x] Enhanced `transcode` with lossless J2K ↔ HTJ2K
- [x] Codec variant tests (CodecVariantTests)
- [x] Enhanced decode tests (DecodeEnhancedTests)
- [x] Lossless transcode tests (TranscodeLosslessTests)
- [x] Batch transcode tests (TranscodeBatchTests)

#### Phase 21b: 3D Volumetric CLI (Weeks 341–348)
- [x] `encode3d` command for JP3D volume encoding
- [x] `decode3d` command for JP3D volume decoding
- [x] 3D tile size, codeblock size, and slice ordering options
- [x] Region-based 3D decoding (`--region x,y,z,w,h,d`)
- [x] Encode3D tests (Encode3DTests)
- [x] Decode3D tests (Decode3DTests)
- [x] Batch 3D tests (Batch3DTests)
- [x] Multi-spectral CLI tests (MultiSpectralCLITests)

#### Phase 21c: JPIP Network Streaming CLI (Weeks 349–356)
- [x] `jpip server` command with session management
- [x] `jpip client` command with interactive mode
- [x] Progressive delivery and region/resolution/quality selection
- [x] Signal handling for graceful server shutdown
- [x] JPIP client tests (JPIPClientTests)
- [x] JPIP server tests (JPIPServerTests)
- [x] JPIP end-to-end tests (JPIPEndToEndTests)

#### Phase 21d: Batch Processing and Utilities (Weeks 357–362)
- [x] `batch` command with parallel processing
- [x] `compare` command with PSNR/SSIM/MSE metrics
- [x] `convert` command for format conversion
- [x] `completions` command for shell completion generation
- [x] Multi-file input and glob support
- [x] Batch command tests (BatchCommandTests)
- [x] Compare command tests (CompareCommandTests)
- [x] Convert command tests (ConvertCommandTests)
- [x] Completion tests (CompletionTests)
- [x] Multi-file input tests (MultiFileInputTests)
- [x] Error handling tests (ErrorHandlingTests)
- [x] Diagnostics tests (DiagnosticsTests)

#### Phase 21e: Documentation and Release Preparation (Weeks 363–365)
- [x] CLI_REFERENCE.md — Complete command reference
- [x] CLI_JPIP_GUIDE.md — JPIP server/client guide
- [x] CLI_3D_GUIDE.md — 3D volumetric CLI guide
- [x] CLI_BATCH_GUIDE.md — Batch processing guide
- [x] CLI_CROSS_LIBRARY_SYNTAX.md — Cross-library syntax specification
- [x] RELEASE_NOTES_v2.4.0.md
- [x] RELEASE_CHECKLIST_v2.4.0.md
- [x] CHANGELOG.md updated
- [x] MILESTONES.md updated
- [x] README.md updated

### Testing

#### Unit Tests
- [x] CodecVariantTests — Codec variant and HTJ2K tests
- [x] DecodeEnhancedTests — Enhanced decode features
- [x] TranscodeLosslessTests — Lossless transcoding
- [x] TranscodeBatchTests — Batch transcoding
- [x] Encode3DTests — 3D volumetric encoding
- [x] Decode3DTests — 3D volumetric decoding
- [x] Batch3DTests — 3D batch processing
- [x] MultiSpectralCLITests — Multi-spectral workflows
- [x] JPIPClientTests — JPIP client operations
- [x] JPIPServerTests — JPIP server operations
- [x] JPIPEndToEndTests — JPIP integration
- [x] BatchCommandTests — Batch encode/decode/transcode
- [x] CompareCommandTests — Image comparison
- [x] ConvertCommandTests — Format conversion
- [x] CompletionTests — Shell completions
- [x] MultiFileInputTests — Multi-file and glob input
- [x] ErrorHandlingTests — Error paths
- [x] DiagnosticsTests — Diagnostics and info

#### Integration Tests
- [x] CLI argument parsing for all new commands
- [x] Cross-command flag consistency
- [x] JSON output format validation
- [x] Error code propagation

### Compliance Verification (ISO/IEC 15444-4)
- [x] All conformance tests pass (54/54 in `J2KConformanceTestingTests`)
- [x] Security tests pass (18/18 in `J2KSecurityTests`)
- [x] Stress tests pass (25/25 in `J2KStressTests`)
- [x] Interoperability tests pass (24/24 in `J2KInteroperabilityTests`)
- [x] Cross-platform validation complete (28/28 in `J2KCrossPlatformValidationTests`)
- [x] ISO test suite checks pass (33/33 in `J2KISOTestSuiteTests`)
- [x] Error metrics within tolerance (lossless: MAE=0, lossy tolerance cases: MAE<=2 in validator coverage)
- [x] Conformance report updated (`CONFORMANCE_TESTING.md`, April 10, 2026)
- [x] Known limitations documented
- [x] Test pass rates documented (182/182, 100%)

### Documentation

#### New Documentation
- [x] Documentation/CLI_REFERENCE.md — Complete command reference
- [x] Documentation/CLI_JPIP_GUIDE.md — JPIP usage guide
- [x] Documentation/CLI_3D_GUIDE.md — 3D volumetric CLI guide
- [x] Documentation/CLI_BATCH_GUIDE.md — Batch processing guide
- [x] Documentation/CLI_CROSS_LIBRARY_SYNTAX.md — Cross-library syntax specification
- [x] RELEASE_NOTES_v2.4.0.md
- [x] RELEASE_CHECKLIST_v2.4.0.md

#### Updated Documentation
- [x] CHANGELOG.md — v2.4.0 entry
- [x] MILESTONES.md — Phase 21 completion
- [x] README.md — Updated CLI section

### Platform Verification
- [x] macOS 15+ (Apple Silicon)
- [x] macOS 15+ (Intel x86-64)
- [x] Linux x86_64
- [x] Linux ARM64

### Performance Verification
- [x] No regression on existing encode/decode tests
- [x] Batch processing scales with CPU core count
- [x] JPIP server handles concurrent sessions

## Post-Release

### Artefacts
- [ ] Git tag `v2.4.0` created
- [ ] GitHub Release published with release notes
- [ ] Swift Package Index updated

### Communication
- [ ] Release announcement prepared
- [ ] Migration notes reviewed (none required for v2.4.0)

---

**Prepared by**: J2KSwift Development Team  
**Review Status**: Complete
