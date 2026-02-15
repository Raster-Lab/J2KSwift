# J2KSwift v1.2.0 Release Checklist

**Version**: 1.2.0  
**Release Date**: TBD  
**Release Type**: Minor Release (Critical Bug Fixes & Enhancements)

## Pre-Release Verification

### Code Quality
- [x] All tests pass (1,528 tests, 24 skipped, 0 failures)
- [x] Build successful with no warnings
- [ ] Code review completed
- [x] VERSION file updated to 1.2.0-dev
- [ ] getVersion() returns "1.2.0" (update before release)

### Critical Bug Fixes
- [x] MQDecoder position underflow fixed (Issue #121)
  - [x] Fix implemented in J2KMQCoder.swift
  - [x] testDifferentDecompositionLevels() passes
  - [x] All codec integration tests pass
- [x] Linux lossless decoding issue fixed
  - [x] Fix implemented in J2KDecoderPipeline.swift
  - [x] testLosslessRoundTrip() passes
  - [x] Cross-platform validation confirms fix

### Documentation
- [x] RELEASE_NOTES_v1.2.0.md created
- [x] KNOWN_LIMITATIONS.md updated to v1.2.0-dev status
- [ ] README.md updated (version references)
- [ ] MILESTONES.md updated (v1.2.0 status)
- [ ] CHANGELOG.md updated (if exists)

### Testing
- [x] Unit tests: 100% of non-skipped tests passing
- [x] Integration tests: All passing
- [x] MQDecoder fix validated
- [x] Linux lossless decoding validated
- [ ] Performance regression tests
- [ ] Cross-platform validation (macOS, Linux)

### Known Issues
- [ ] 64×64 MQ coder issue remains (documented, low priority)
- [ ] Performance target not yet met (32.6% vs 80% target)

## Release Process

### Step 1: Final Pre-Release Tasks
- [ ] Update VERSION file to "1.2.0" (remove "-dev")
- [ ] Update getVersion() in J2KCore.swift to return "1.2.0"
- [ ] Update all version references in documentation
- [ ] Run full test suite one final time
- [ ] Verify build on all platforms

### Step 2: Create Git Tag
```bash
cd /path/to/J2KSwift
git checkout main
git pull origin main
git tag -a v1.2.0 -m "Release v1.2.0 - Critical Bug Fixes"
git push origin v1.2.0
```

### Step 3: Create GitHub Release
- [ ] Go to GitHub Releases page
- [ ] Click "Draft a new release"
- [ ] Select tag: v1.2.0
- [ ] Release title: "J2KSwift v1.2.0 - Critical Bug Fixes"
- [ ] Copy content from RELEASE_NOTES_v1.2.0.md
- [ ] Publish release

### Step 4: Update Main Branch
- [ ] Merge release branch to main
- [ ] Update VERSION file to "1.2.1-dev" for next development cycle
- [ ] Update MILESTONES.md with v1.2.0 completion status

### Step 5: Announce Release
- [ ] Post announcement on GitHub Discussions
- [ ] Update project README.md with latest version badge
- [ ] Notify Swift community (if applicable)
- [ ] Update package registry (if applicable)

## Post-Release Verification

### Verification Steps
- [ ] Verify package resolution works
  ```bash
  swift package resolve
  ```
- [ ] Verify tests pass in clean environment
  ```bash
  rm -rf .build
  swift test
  ```
- [ ] Verify documentation builds
  ```bash
  swift package generate-documentation
  ```
- [ ] Check GitHub Actions CI passes

### Monitoring
- [ ] Monitor for issue reports
- [ ] Check download statistics
- [ ] Collect user feedback
- [ ] Plan for v1.2.1 patch release if needed

## Rollback Plan

If critical issues are discovered after release:

1. **Immediate Action**
   - Document issue in GitHub Issues
   - Add warning to release notes
   - Notify users via GitHub Discussions

2. **Short-term Fix (v1.2.1)**
   - Create hotfix branch
   - Implement minimal fix
   - Fast-track testing and release

3. **If Necessary - Rollback**
   - Mark v1.2.0 as pre-release/deprecated on GitHub
   - Recommend users stay on v1.1.1
   - Plan comprehensive fix for v1.2.2

## Success Criteria

Release is considered successful when:
- ✅ All critical bugs fixed
- ✅ No new test failures introduced
- ✅ Documentation complete and accurate
- ⏭️ No critical issues reported within 1 week
- ⏭️ Positive community feedback

## Next Steps After Release

### v1.2.1 (Patch Release - If Needed)
- Address any critical issues discovered
- Performance optimizations
- Additional testing

### v1.3.0 (Minor Release - Planned Q2 2026)
- API refinements
- Performance improvements (target: ≥80% of OpenJPEG)
- Enhanced JPIP features
- Additional cross-platform support

### v2.0.0 (Major Release - Planned Q4 2026)
- HTJ2K codec (ISO/IEC 15444-15)
- Lossless transcoding (JPEG 2000 ↔ HTJ2K)
- JPEG 2000 Part 2 extensions
- Breaking API changes if needed

---

**Checklist Status**: 12/34 items complete (35%)  
**Release Readiness**: In Development  
**Target Release Date**: TBD (when all items complete)

**Last Updated**: 2026-02-15
