# Contributing to J2KCore

Thank you for your interest in contributing to J2KCore! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Code Style](#code-style)
- [Testing Requirements](#testing-requirements)
- [Documentation Standards](#documentation-standards)
- [Pull Request Process](#pull-request-process)
- [Issue Guidelines](#issue-guidelines)

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

- Xcode 15.0 or later (for Apple platform development)
- Swift 6.0 or later
- Git
- SwiftLint (optional but recommended)

### Setting Up Development Environment

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/J2KCore.git
   cd J2KCore
   ```

3. Add the upstream repository:
   ```bash
   git remote add upstream https://github.com/Raster-Lab/J2KCore.git
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
/// including entropy decoding, inverse wavelet transform, and dequantization.
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
- Expected behavior
- Actual behavior
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
- **P3 - Low**: Polish, optimizations, refactoring

## Recognition

Contributors will be recognized in:

- Release notes
- CONTRIBUTORS.md file
- GitHub contributors page

## Questions?

- Open an issue with the "question" label
- Start a discussion in GitHub Discussions
- Review existing documentation

## License

By contributing to J2KCore, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to J2KCore! Your efforts help make JPEG 2000 support better for the Swift community. 🎉
