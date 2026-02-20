# CI/CD Workflows

This directory contains GitHub Actions workflows for J2KSwift.

## Workflows

### ✅ CI (`ci.yml`)
**Triggers**: Push to main/develop, Pull Requests, Manual

Primary continuous integration workflow:
- **Build and Test (macOS)**: Builds and runs all tests on macOS 15 with Swift 6.2
- **Build and Test (Linux)**: Builds and runs all tests on Ubuntu with Swift 6.2
- **SwiftLint**: Enforces code style guidelines
- SPM dependency caching for faster builds

**Badge**: ![CI](https://github.com/Raster-Lab/J2KSwift/actions/workflows/ci.yml/badge.svg)

### 🔨 Swift Build and Test (`swift-build-test.yml`)
**Triggers**: Push to main/develop, Pull Requests, Manual

Tests the project on multiple platforms:
- **macOS 15**: Full build and test with Swift 6.2
- **Linux (Ubuntu)**: Cross-platform compatibility testing

**Badge**: ![Swift Build](https://github.com/Raster-Lab/J2KSwift/actions/workflows/swift-build-test.yml/badge.svg)

### 📚 Documentation (`documentation.yml`)
**Triggers**: Push to main, Version tags (v*), Manual

Automatically generates and publishes documentation to GitHub Pages:
- Builds DocC documentation for all modules
- Deploys to GitHub Pages
- Accessible at: https://raster-lab.github.io/J2KSwift/

**Badge**: ![Documentation](https://github.com/Raster-Lab/J2KSwift/actions/workflows/documentation.yml/badge.svg)

### 🔍 Code Quality (`code-quality.yml`)
**Triggers**: Push to main/develop, Pull Requests, Manual

Comprehensive code quality checks:
- **SwiftLint**: Enforces code style guidelines
- **Security Audit**: Checks for known vulnerabilities
- **Code Coverage**: Measures test coverage
- **Package Validation**: Validates Swift package configuration

**Badge**: ![Code Quality](https://github.com/Raster-Lab/J2KSwift/actions/workflows/code-quality.yml/badge.svg)

### 🚀 Release (`release.yml`)
**Triggers**: Version tags (v*.*.*), Manual

Automated release process:
- Validates the build
- Runs all tests
- Creates GitHub release with notes
- Publishes release artifacts

**Badge**: ![Release](https://github.com/Raster-Lab/J2KSwift/actions/workflows/release.yml/badge.svg)

### 🏗️ Linux ARM64 CI (`linux-arm64.yml`)
**Triggers**: Push to main/develop, Pull Requests, Manual

ARM64-specific testing via QEMU emulation:
- Build and test on ARM64 Linux with Swift 6.2
- NEON SIMD validation tests
- ARM64 performance benchmarks

**Badge**: ![Linux ARM64](https://github.com/Raster-Lab/J2KSwift/actions/workflows/linux-arm64.yml/badge.svg)

### 🪟 Windows CI (`windows.yml`)
**Triggers**: Push to main/develop, Pull Requests, Manual

Windows platform testing:
- Build and test on Windows with Swift 6.2
- SPM dependency caching
- Release build artifacts

**Badge**: ![Windows](https://github.com/Raster-Lab/J2KSwift/actions/workflows/windows.yml/badge.svg)

### ✅ Conformance Gating (`conformance.yml`)
**Triggers**: Push to main/develop/release, Pull Requests, Manual

ISO/IEC 15444-4 conformance validation:
- Part 1 (Core) conformance tests
- Part 15 (HTJ2K) conformance tests
- Part 10 (JP3D) conformance tests
- Cross-platform conformance (Linux)
- Conformance gate — blocks on any conformance failure

**Badge**: ![Conformance](https://github.com/Raster-Lab/J2KSwift/actions/workflows/conformance.yml/badge.svg)

### 📊 Performance Benchmarks (`performance.yml`)
**Triggers**: Push to main/develop, Pull Requests, Manual

Performance tracking and regression detection:
- macOS Apple Silicon benchmarks
- Linux x86-64 benchmarks
- Linux ARM64 benchmarks (via QEMU)
- OpenJPEG comparison (when available)
- Flags regressions >5%

**Badge**: ![Performance](https://github.com/Raster-Lab/J2KSwift/actions/workflows/performance.yml/badge.svg)

### 🧪 JP3D Compliance (`jp3d-compliance.yml`)
**Triggers**: Push/PR changes to J2K3D sources or compliance tests, Manual

JP3D Part 4 compliance validation:
- macOS and Linux compliance tests
- Conformance report generation and upload

**Badge**: ![JP3D Compliance](https://github.com/Raster-Lab/J2KSwift/actions/workflows/jp3d-compliance.yml/badge.svg)

## Configuration Files

### `dependabot.yml`
Automated dependency updates:
- Weekly updates for GitHub Actions
- Weekly updates for Swift Package Manager dependencies
- Auto-creates PRs with proper labels

## CI/CD Best Practices

### For Contributors

1. **Before pushing**: Ensure all tests pass locally
   ```bash
   swift build
   swift test
   swiftlint lint
   ```

2. **Pull Requests**: The CI will automatically run on PRs
   - All checks must pass before merging
   - Review bot comments for issues

3. **Breaking changes**: Document in CHANGELOG.md

### For Maintainers

1. **Release Process**:
   ```bash
   git tag -a v2.0.0 -m "Release v2.0.0"
   git push origin v2.0.0
   ```
   The release workflow will handle the rest.

2. **Documentation**: Auto-deployed on push to main

3. **Code Quality**: Review reports in workflow artifacts

## Workflow Secrets

No secrets are required for basic workflows. The following permissions are used:

- `GITHUB_TOKEN`: Auto-provided by GitHub Actions
  - Used for creating releases
  - Used for publishing to GitHub Pages
  - Used for posting workflow status

## Troubleshooting

### Workflow fails on macOS
- Check Swift version compatibility
- Ensure Xcode is properly configured

### Workflow fails on Linux
- Verify Linux-compatible code
- Check for platform-specific dependencies

### SwiftLint failures
- Run locally: `swiftlint lint --strict`
- Fix issues or update `.swiftlint.yml`

### Documentation build fails
- Ensure all public APIs are documented
- Check for broken DocC syntax

## Adding New Workflows

1. Create a new `.yml` file in this directory
2. Follow GitHub Actions syntax
3. Test with `workflow_dispatch` trigger first
4. Add badge to main README.md
5. Document in this README

## Status Badges

Add to main README.md:
```markdown
[![CI](https://github.com/Raster-Lab/J2KSwift/actions/workflows/ci.yml/badge.svg)](https://github.com/Raster-Lab/J2KSwift/actions/workflows/ci.yml)
[![Code Quality](https://github.com/Raster-Lab/J2KSwift/actions/workflows/code-quality.yml/badge.svg)](https://github.com/Raster-Lab/J2KSwift/actions/workflows/code-quality.yml)
[![Conformance](https://github.com/Raster-Lab/J2KSwift/actions/workflows/conformance.yml/badge.svg)](https://github.com/Raster-Lab/J2KSwift/actions/workflows/conformance.yml)
[![Performance](https://github.com/Raster-Lab/J2KSwift/actions/workflows/performance.yml/badge.svg)](https://github.com/Raster-Lab/J2KSwift/actions/workflows/performance.yml)
[![Documentation](https://github.com/Raster-Lab/J2KSwift/actions/workflows/documentation.yml/badge.svg)](https://github.com/Raster-Lab/J2KSwift/actions/workflows/documentation.yml)
```
