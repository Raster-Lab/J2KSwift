# Contributing to J2KSwift

Thank you for your interest in contributing to J2KSwift! This document provides guidelines and instructions for contributing to the project.

All documentation in J2KSwift is written in **British English**. Please use British spellings throughout your contributions (see [Language](#language) below and [ADR-005](Documentation/ADR/ADR-005-british-english.md)).

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [CI/CD Process](CI_CD_GUIDE.md) - **See comprehensive CI/CD guide**
- [Code Style](#code-style)
- [Testing Requirements](#testing-requirements)
- [Performance Testing Guidelines](#performance-testing-guidelines)
- [Documentation Standards](#documentation-standards)
- [Architecture Decision Records](#architecture-decision-records)
- [Pull Request Process](#pull-request-process)
- [Issue Guidelines](#issue-guidelines)
- [Language](#language)

## Code of Conduct

### Our Pledge

We are committed to providing a welcoming and inclusive environment for all contributors. Please treat everyone with respect and kindness.

### Expected Behavior

- Use welcoming and inclusive language
- Be respectful of differing viewpoints and experiences
- Gracefully accept constructive criticism
- Focus on what is best for the community
- Show empathy towards other community members

### Unacceptable Behavior

- Harassment, discrimination, or offensive comments
- Trolling, insulting/derogatory comments, and personal attacks
- Public or private harassment
- Publishing others' private information without permission
- Other conduct that could reasonably be considered inappropriate

## Getting Started

### Prerequisites

- Xcode 16.0 or later (for Apple platform development)
- Swift 6.2 or later
- Git
- SwiftLint (optional but recommended)

### Setting Up Development Environment

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/J2KSwift.git
   cd J2KSwift
   ```

3. Add the upstream repository:
   ```bash
   git remote add upstream https://github.com/Raster-Lab/J2KSwift.git
   ```

4. Install SwiftLint (optional):
   ```bash
   brew install swiftlint
   ```

5. Build the project:
   ```bash
   swift build
   ```

6. Run tests to ensure everything works:
   ```bash
   swift test
   ```

7. Read the architecture overview before making structural changes:
   - [`Documentation/ARCHITECTURE.md`](Documentation/ARCHITECTURE.md) — module organisation, concurrency model, performance subsystems

## Development Workflow

### Branching Strategy

- `main` - Stable releases only
- `develop` - Integration branch for features
- `feature/*` - New features
- `bugfix/*` - Bug fixes
- `release/*` - Release preparation

### Working on a Feature

1. Create a feature branch from `develop`:
   ```bash
   git checkout develop
   git pull upstream develop
   git checkout -b feature/my-feature
   ```

2. Make your changes with clear, atomic commits
3. Write/update tests for your changes
4. Update documentation as needed
5. Ensure all tests pass:
   ```bash
   swift test
   ```

6. Run SwiftLint:
   ```bash
   swiftlint
   ```

7. Push your changes:
   ```bash
   git push origin feature/my-feature
   ```

8. Open a pull request

### Commit Messages

Follow these guidelines for commit messages:

- Use the present tense ("Add feature" not "Added feature")
- Use the imperative mood ("Move cursor to..." not "Moves cursor to...")
- Limit the first line to 72 characters or less
- Reference issues and pull requests liberally after the first line
- Consider starting the commit message with an applicable emoji:
  - 🎨 `:art:` - Improving structure/format of the code
  - ⚡️ `:zap:` - Improving performance
  - 🔥 `:fire:` - Removing code or files
  - 🐛 `:bug:` - Fixing a bug
  - ✨ `:sparkles:` - Introducing new features
  - 📝 `:memo:` - Adding or updating documentation
  - ✅ `:white_check_mark:` - Adding or updating tests
  - 🔒 `:lock:` - Fixing security issues
  - ⬆️ `:arrow_up:` - Upgrading dependencies
  - ⬇️ `:arrow_down:` - Downgrading dependencies

Example:
```
✨ Add support for ROI encoding

- Implement MaxShift ROI method
- Add ROI mask generation
- Update documentation with examples

Closes #123
```

## Code Style

### Swift Style Guide

We follow the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) and enforce style with SwiftLint.

Key points:

- **Indentation**: 4 spaces (no tabs)
- **Line Length**: Maximum 120 characters
- **Naming**:
  - Types and protocols: `UpperCamelCase`
  - Functions, variables, constants: `lowerCamelCase`
  - Enum cases: `lowerCamelCase`
- **Whitespace**:
  - One blank line between type definitions
  - One blank line between method definitions
  - No trailing whitespace

### Concurrency

- Use `async`/`await` for asynchronous operations
- Mark types as `Sendable` when thread-safe
- Use actors for mutable shared state
- Follow Swift 6 strict concurrency rules

### Example

```swift
/// Encodes images to JPEG 2000 format.
///
/// This encoder provides high-quality JPEG 2000 encoding with support
/// for various compression modes and quality settings.
public struct J2KEncoder: Sendable {
    /// The configuration to use for encoding.
    public let configuration: J2KConfiguration
    
    /// Creates a new encoder with the specified configuration.
    ///
    /// - Parameter configuration: The encoding configuration.
    public init(configuration: J2KConfiguration = J2KConfiguration()) {
        self.configuration = configuration
    }
    
    /// Encodes an image to JPEG 2000 format.
    ///
    /// - Parameter image: The image to encode.
    /// - Returns: The encoded image data.
    /// - Throws: ``J2KError`` if encoding fails.
    public func encode(_ image: J2KImage) throws -> Data {
        // Implementation
    }
}
```

## Testing Requirements

### Unit Tests

- Every public API must have unit tests
- Aim for at least 90% code coverage for new code
- Use descriptive test names that explain what is being tested
- Follow the Arrange-Act-Assert pattern
- Use XCTest framework

Example:
```swift
func testEncoderWithCustomConfiguration() throws {
    // Arrange
    let config = J2KConfiguration(quality: 0.7, lossless: false)
    let encoder = J2KEncoder(configuration: config)
    
    // Act
    let image = J2KImage(width: 100, height: 100, components: 3)
    let data = try encoder.encode(image)
    
    // Assert
    XCTAssertGreaterThan(data.count, 0)
    XCTAssertEqual(encoder.configuration.quality, 0.7, accuracy: 0.001)
}
```

### Integration Tests

- Test interaction between modules
- Validate end-to-end workflows
- Test with realistic data

### Performance Tests

- Add performance tests for critical paths
- Use `XCTestCase.measure` for benchmarking
- Document performance expectations

## Performance Testing Guidelines

Performance is a first-class concern in J2KSwift. The following guidelines
ensure that performance regressions are caught early and that benchmarks are
reproducible.

### Using `XCTestCase.measure { }`

Wrap the code under test in `measure { }` to record wall-clock time across
ten iterations. XCTest computes the mean and standard deviation automatically.

```swift
func testDWTPerformance() {
    let image = J2KImage.syntheticRGB(width: 1024, height: 1024)
    measure {
        _ = try? J2KDWT2D().forward(image.components[0])
    }
}
```

Place performance tests in the `Tests/PerformanceTests/` directory, **not**
alongside unit tests, so that CI can run them separately on dedicated hardware.

### Running the Performance Test Suite

```bash
# Run all performance tests
swift test --filter PerformanceTests

# Run a single benchmark
swift test --filter PerformanceTests.J2KDWTPerformanceTests/testDWTPerformance
```

Performance tests are excluded from the default `swift test` run in CI to
avoid flaky results on shared runners. They run on dedicated bare-metal GitHub
Actions runners on every pull request that touches codec, transform, or
accelerate code.

### Performance Regression Thresholds

The following thresholds apply to the reference hardware (Apple M2 Pro, 16 GB):

| Operation | Target | Regression threshold |
|-----------|--------|---------------------|
| Lossy encode — 4K RGB | ≥ 500 MP/s | < 450 MP/s |
| Lossless encode — 4K RGB | ≥ 350 MP/s | < 315 MP/s |
| Lossy decode — 4K RGB | ≥ 600 MP/s | < 540 MP/s |
| DWT forward pass (1024×1024) | ≤ 4 ms | > 5 ms |
| ICT colour transform (1024×1024) | ≤ 1 ms | > 1.5 ms |

A CI job compares the measured baseline against these thresholds and fails the
build if any threshold is exceeded. Results are posted as a PR comment.

### Using the OpenJPEG Benchmark Script

`Scripts/benchmark_openjpeg.sh` compares J2KSwift throughput against
OpenJPEG on a set of reference images. Run it locally before submitting
performance-sensitive changes:

```bash
# Requires OpenJPEG to be installed (brew install openjpeg)
bash Scripts/benchmark_openjpeg.sh

# Limit to a specific image size
bash Scripts/benchmark_openjpeg.sh --size 4096x4096
```

The script outputs a Markdown table suitable for pasting into a pull request
description. Benchmark results are also saved to `profile_results/` for
historical comparison.

## Documentation Standards

### Code Documentation

- All public APIs must have documentation comments
- Use Swift's markup format for documentation
- Include:
  - Summary description
  - Detailed description (if needed)
  - Parameters with descriptions
  - Return value description
  - Throws description
  - Example usage (for complex APIs)

Example:
```swift
/// Decodes JPEG 2000 data into an image.
///
/// This method performs complete decoding of a JPEG 2000 codestream,
/// including entropy decoding, inverse wavelet transform, and dequantisation.
///
/// - Parameter data: The JPEG 2000 data to decode. Must be a valid
///   JPEG 2000 codestream or file format.
/// - Returns: The decoded image with all components.
/// - Throws: ``J2KError/invalidParameter(_:)`` if the data is invalid.
/// - Throws: ``J2KError/internalError(_:)`` if decoding fails.
///
/// Example:
/// ```swift
/// let decoder = J2KDecoder()
/// let image = try decoder.decode(jpegData)
/// print("Decoded: \(image.width)x\(image.height)")
/// ```
public func decode(_ data: Data) throws -> J2KImage {
    // Implementation
}
```

### README and Guides

- Keep README.md up to date with major changes
- Update tutorials when APIs change
- Add examples for new features
- Document migration paths for breaking changes

## Pull Request Process

### Before Submitting

1. ✅ All tests pass
2. ✅ SwiftLint reports no violations
3. ✅ Code coverage is maintained or improved
4. ✅ Documentation is updated
5. ✅ CHANGELOG.md is updated (if applicable)
6. ✅ Branch is up to date with target branch

### PR Description Template

```markdown
## Description
Brief description of changes

## Motivation
Why are these changes needed?

## Changes
- List of specific changes
- Be as detailed as necessary

## Testing
- Describe testing performed
- Include any manual testing steps

## Screenshots (if applicable)
Add screenshots for UI changes

## Checklist
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] SwiftLint passes
- [ ] All tests pass
- [ ] Breaking changes documented

## Related Issues
Closes #123
```

### Review Process

1. At least one maintainer must review and approve
2. All CI checks must pass
3. No unresolved review comments
4. Branch must be up to date with target branch

### After Approval

- Maintainers will merge using squash commits
- Your changes will be included in the next release
- You'll be credited in the release notes

## Issue Guidelines

### Reporting Bugs

Use the bug report template and include:

- Clear, descriptive title
- Steps to reproduce
- Expected behaviour
- Actual behaviour
- Environment details (OS, Swift version, etc.)
- Relevant code snippets or error messages

### Requesting Features

Use the feature request template and include:

- Clear description of the feature
- Use cases and motivation
- Proposed API (if applicable)
- Alternatives considered
- Any related issues or discussions

### Asking Questions

- Check existing issues and documentation first
- Use GitHub Discussions for general questions
- Be specific and provide context
- Include relevant code or examples

## Priority Levels

Issues and PRs are labeled with priority:

- **P0 - Critical**: Security issues, data loss bugs
- **P1 - High**: Major bugs, important features
- **P2 - Medium**: Minor bugs, nice-to-have features
- **P3 - Low**: Polish, optimisations, refactoring

## Recognition

Contributors will be recognised in:

- Release notes
- CONTRIBUTORS.md file
- GitHub contributors page

## Questions?

- Open an issue with the "question" label
- Start a discussion in GitHub Discussions
- Review existing documentation

## Architecture Decision Records

Architecture Decision Records (ADRs) document the significant architectural
choices made in J2KSwift — what was decided, why, and what the consequences are.

ADRs live in [`Documentation/ADR/`](Documentation/ADR/). The
[`Documentation/ADR/README.md`](Documentation/ADR/README.md) file provides an
index of all records.

### When to Write an ADR

Write a new ADR when you are:

- Introducing a new module or changing the module dependency graph.
- Adopting a new concurrency pattern or changing actor boundaries.
- Adding a new platform target or GPU backend.
- Making a breaking change to a public API.
- Choosing between two or more reasonable technical approaches with different
  trade-offs.

### ADR Lifecycle

| Status | Meaning |
|--------|---------|
| Proposed | Under discussion; not yet agreed |
| Accepted | Decision taken and implemented |
| Deprecated | Was accepted but no longer applies |
| Superseded | Replaced by a newer ADR |

### Current ADRs

| ADR | Decision |
|-----|---------|
| [ADR-001](Documentation/ADR/ADR-001-swift6-strict-concurrency.md) | Swift 6 strict concurrency |
| [ADR-002](Documentation/ADR/ADR-002-value-types-cow.md) | Value types with copy-on-write storage |
| [ADR-003](Documentation/ADR/ADR-003-modular-gpu-backends.md) | Modular GPU backends (Metal + Vulkan) |
| [ADR-004](Documentation/ADR/ADR-004-no-dicom-dependency.md) | No DICOM library dependencies |
| [ADR-005](Documentation/ADR/ADR-005-british-english.md) | British English in documentation |

## Language

All **documentation** and **source code comments** in J2KSwift use **British
English**. The rationale is recorded in
[ADR-005](Documentation/ADR/ADR-005-british-english.md).

Common spellings to remember:

| Use (British) | Avoid (American) |
|---------------|-----------------|
| colour | color |
| optimisation | optimization |
| organise | organize |
| behaviour | behavior |
| recognise | recognize |
| analyse | analyze |
| favour | favor |
| artefact | artifact |
| initialisation | initialization |
| parallelisation | parallelization |

**Exception**: Swift identifier names (`colorSpace`, `optimize`, etc.) use
American English to match the Swift standard library and Apple's frameworks.



By contributing to J2KSwift, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to J2KSwift! Your efforts help make JPEG 2000 support better for the Swift community. 🎉
