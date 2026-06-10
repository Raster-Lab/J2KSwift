---
name: release-checklist
description: 'Pre-release validation checklist for J2KSwift versions. Use for preparing releases, validating build/test/lint, ISO compliance gate, changelog preparation, version bumping.'
---

# Release Checklist

Complete release preparation workflow for J2KSwift.

## When to Use
- Preparing a new version release
- Validating release readiness
- Creating release branches and tags

## Procedure

### 1. Version Update
```bash
# Check current version
cat VERSION

# Update VERSION file
echo "X.Y.Z" > VERSION
```

### 2. Full Build Verification
```bash
# Clean build
swift package clean
swift build

# Release build
swift build -c release
```

### 3. Complete Test Suite
```bash
# All tests must pass
swift test

# Module-specific verification
swift test --filter J2KCoreTests
swift test --filter J2KCodecTests
swift test --filter J2KAccelerateTests
swift test --filter J2KFileFormatTests
swift test --filter J2KMetalTests
swift test --filter J2KVulkanTests
swift test --filter JPIPTests
swift test --filter JP3DTests
swift test --filter J2KCLITests
```

### 4. ISO/IEC 15444-4 Compliance Gate (MANDATORY)
```bash
swift test --filter J2KConformanceTestingTests
swift test --filter J2KComplianceTests
```

Verify:
- [ ] Profile 0 (Baseline) conformance tests pass
- [ ] Error metrics within tolerance (lossless: MAE=0, lossy: per spec)
- [ ] Cross-codec interoperability with OpenJPEG verified

### 5. Code Quality
```bash
# Lint check
swiftlint

# Format check (optional)
swift format --recursive Sources Tests --check
```

### 6. Documentation
- [ ] CHANGELOG.md updated with all changes
- [ ] RELEASE_NOTES_vX.Y.Z.md created
- [ ] API_REFERENCE.md reflects any API changes
- [ ] README.md version references updated

### 7. Release Checklist Document
Create `RELEASE_CHECKLIST_vX.Y.Z.md` with:
```markdown
# Release Checklist v X.Y.Z

## Build & Test
- [ ] `swift build` passes
- [ ] `swift build -c release` passes
- [ ] `swift test` all tests pass (N/N)

## Compliance Verification (ISO/IEC 15444-4)
- [ ] All conformance tests pass
- [ ] Security tests pass
- [ ] Stress tests pass
- [ ] Cross-platform validation complete
- [ ] Error metrics within tolerance
- [ ] Conformance report updated
- [ ] Known limitations documented
- [ ] Test pass rate: >95%

## Code Quality
- [ ] SwiftLint passes
- [ ] No force unwraps in production code
- [ ] No `fatalError` in production code

## Documentation
- [ ] CHANGELOG.md updated
- [ ] Release notes created
- [ ] API docs current
```

### 8. Git Operations
```bash
# Stage all changes
git add -A

# Commit
git commit -m "Release vX.Y.Z"

# Tag
git tag -a vX.Y.Z -m "Release vX.Y.Z"

# Push (confirm with user first)
git push origin main --tags
```

## Reference Files
- Previous release checklists: `RELEASE_CHECKLIST_v*.md`
- Previous release notes: `RELEASE_NOTES_v*.md`
- `CONFORMANCE_TESTING.md`
