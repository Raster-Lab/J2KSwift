# GitHub Copilot Instructions for J2KCore

This document provides detailed instructions for GitHub Copilot when working on the J2KCore project.

## Project Overview

J2KCore is a pure Swift 6 implementation of JPEG 2000 (ISO/IEC 15444) encoding and decoding with strict concurrency support. The project emphasizes type safety, performance, and cross-platform compatibility.

## Code Style and Conventions

### Swift 6 and Concurrency

- **ALWAYS** use Swift 6 strict concurrency model
- Mark types as `Sendable` when they are thread-safe
- Use `actor` for types with mutable state that need synchronization
- Prefer `async`/`await` over completion handlers
- Use `@MainActor` for UI-related code
- Avoid `@unchecked Sendable` unless absolutely necessary with clear documentation

### Type Naming

- Types and protocols: `UpperCamelCase` (e.g., `J2KEncoder`, `J2KImage`)
- Functions and variables: `lowerCamelCase` (e.g., `encode`, `imageData`)
- Constants: `lowerCamelCase` (e.g., `maxIterations`, `defaultQuality`)
- Enum cases: `lowerCamelCase` (e.g., `.jp2`, `.lossless`)

### Documentation

All public APIs must include:
- Summary line (one sentence)
- Detailed description (if needed)
- Parameter descriptions with `- Parameter name: description`
- Return value description with `- Returns: description`
- Error descriptions with `- Throws: error description`
- Example usage for complex APIs

Example:
```swift
/// Encodes an image to JPEG 2000 format.
///
/// This method performs complete JPEG 2000 encoding including color transform,
/// wavelet transform, quantization, and entropy coding.
///
/// - Parameter image: The image to encode. Must have valid dimensions and components.
/// - Returns: The encoded JPEG 2000 data.
/// - Throws: ``J2KError/invalidParameter(_:)`` if the image is invalid.
/// - Throws: ``J2KError/internalError(_:)`` if encoding fails.
///
/// Example:
/// ```swift
/// let encoder = J2KEncoder()
/// let data = try encoder.encode(image)
/// ```
public func encode(_ image: J2KImage) throws -> Data {
    // Implementation
}
```

### Error Handling

- Use `throws` for recoverable errors
- Define specific error types in `J2KError` enum
- Include contextual information in error messages
- Never use `fatalError` in production code (only in placeholders)
- Prefer Result types for operations that commonly fail

### Testing

When generating tests:
- Use XCTest framework
- Follow Arrange-Act-Assert pattern
- Use descriptive test method names (e.g., `testEncoderWithCustomConfiguration`)
- Test edge cases and error conditions
- Add performance tests for critical paths using `measure { }`
- Aim for high code coverage (>90%)

Test naming pattern:
```swift
func test<ComponentName><Scenario>() throws {
    // Arrange
    let input = ...
    
    // Act
    let result = try component.method(input)
    
    // Assert
    XCTAssertEqual(result, expected)
}
```

## Module-Specific Guidelines

### J2KCore Module

The foundation module providing core types and utilities.

**Key Types:**
- `J2KImage` - Basic image representation
- `J2KError` - Error types
- `J2KConfiguration` - Configuration options

**Guidelines:**
- Keep types minimal and focused
- Ensure all types are `Sendable`
- No external dependencies except Foundation
- Focus on reusability across other modules

### J2KCodec Module

Encoding and decoding implementation.

**Key Types:**
- `J2KEncoder` - Image encoding
- `J2KDecoder` - Image decoding

**Guidelines:**
- Depend only on J2KCore
- Implement encoding/decoding pipelines
- Focus on correctness first, optimize later
- Use value types where possible

### J2KAccelerate Module

Hardware-accelerated operations.

**Key Types:**
- `J2KDWTAccelerated` - Fast wavelet transforms
- `J2KColorTransform` - Color space conversions

**Guidelines:**
- Use Accelerate framework when available
- Provide fallback implementations
- Benchmark performance gains
- Use `#if canImport(Accelerate)` for conditional compilation

### J2KFileFormat Module

File format support.

**Key Types:**
- `J2KFileReader` - Read JP2/J2K files
- `J2KFileWriter` - Write JP2/J2K files
- `J2KFormat` - Format types

**Guidelines:**
- Support all JPEG 2000 file formats (JP2, J2K, JPX, JPM)
- Robust error handling for malformed files
- Memory-efficient streaming where possible
- Validate file structure

### JPIP Module

Network streaming protocol.

**Key Types:**
- `JPIPClient` - Client implementation
- `JPIPServer` - Server implementation
- `JPIPSession` - Session management

**Guidelines:**
- Use `actor` for client/server types
- All network operations are async
- Implement proper session management
- Handle network errors gracefully
- Use URLSession for HTTP transport

## Implementation Patterns

### Value Types vs Reference Types

Prefer value types (struct) for:
- Immutable data
- Small data structures
- Types that need `Sendable` conformance

Use reference types (class) for:
- Large mutable state
- Identity matters
- Objective-C interop (if needed)

Use actors for:
- Mutable shared state
- Network/I/O operations
- State machines

### Memory Management

- Use `Data` for binary data
- Implement copy-on-write for large buffers
- Be mindful of memory allocations in tight loops
- Use `autoreleasepool` for batch processing
- Consider memory-mapped files for large datasets

### Performance

- Profile before optimizing
- Use SIMD types for numerical operations
- Parallelize independent operations
- Cache expensive computations
- Use lazy evaluation where appropriate

## Milestone Tracking

Refer to [MILESTONES.md](/MILESTONES.md) for the 100-week development roadmap. When implementing features:

1. Check which phase you're in
2. Implement features in order of dependencies
3. Update milestone checklist when completing tasks
4. Add tests for each completed feature
5. Run CLI tools to verify every completed feature before marking it done:
   ```bash
   swift build                          # Full project build
   swift test                           # Run all tests
   swift test --filter <ModuleTests>    # Run module-specific tests
   swiftlint                            # Lint check
   ```
6. Update documentation

Current phase focus: **Phase 0 - Foundation (Weeks 1-10)**

## README Updates

When adding major features:
1. Update feature list in README
2. Add usage examples
3. Update Quick Start if API changes
4. Keep roadmap status current
5. Update installation instructions if needed

## Testing Best Practices

### Unit Tests
- Test each public API
- Test error conditions
- Test edge cases (empty inputs, large inputs, invalid data)
- Use meaningful test data

### Integration Tests
- Test module interactions
- Test complete workflows (encode -> decode)
- Validate against reference implementations
- Test with real-world data

### Performance Tests
- Measure encoding/decoding speed
- Track memory usage
- Compare against benchmarks
- Test scalability

Example performance test:
```swift
func testEncodingPerformance() throws {
    let image = J2KImage(width: 1024, height: 1024, components: 3)
    let encoder = J2KEncoder()
    
    measure {
        _ = try? encoder.encode(image)
    }
}
```

## Common Tasks

### Adding a New Feature

1. Check milestone for phase alignment
2. Create feature branch
3. Implement with tests
4. Run CLI tools to verify the feature:
   ```bash
   swift build            # Ensure the project compiles without errors
   swift test             # Run all tests and confirm they pass
   swiftlint              # Check for code style violations
   ```
5. Update documentation
6. Submit PR with checklist

### Fixing a Bug

1. Write failing test that reproduces bug
2. Fix the bug
3. Run CLI tools to verify the fix:
   ```bash
   swift build            # Ensure the fix compiles cleanly
   swift test             # Confirm the new test passes and no regressions
   swiftlint              # Check for code style violations
   ```
4. Add regression test if needed
5. Update CHANGELOG

### Refactoring

1. Ensure tests exist and pass
2. Make changes incrementally
3. After each change, run CLI tools to verify:
   ```bash
   swift build            # Ensure the project still compiles
   swift test             # Run tests to catch regressions
   swiftlint              # Verify code style compliance
   ```
4. Keep commits atomic
5. Document breaking changes

### Feature Completion Verification

Every completed feature **must** be verified using CLI tools before it is considered done. Run the following commands in order:

```bash
# Step 1: Build the entire project
swift build

# Step 2: Run all tests to ensure nothing is broken
swift test

# Step 3: Run module-specific tests for the feature being completed
swift test --filter J2KCoreTests        # Core module tests
swift test --filter J2KCodecTests       # Codec module tests
swift test --filter J2KAccelerateTests  # Accelerate module tests
swift test --filter J2KFileFormatTests  # File format module tests
swift test --filter JPIPTests           # JPIP module tests

# Step 4: Lint the code for style compliance
swiftlint

# Step 5: (Optional) Generate and review documentation
swift package generate-documentation
```

A feature is only complete when all of the above steps succeed without errors.

## Code Review Checklist

When generating code, ensure:

- [ ] Swift 6 strict concurrency compliance
- [ ] All public APIs documented
- [ ] Tests added/updated
- [ ] `swift build` succeeds without errors or warnings
- [ ] `swift test` passes all tests
- [ ] SwiftLint passes (`swiftlint`)
- [ ] No force unwraps in production code
- [ ] Error handling is appropriate
- [ ] Types are `Sendable` where needed
- [ ] Performance considerations addressed
- [ ] Memory usage is reasonable
- [ ] Cross-platform compatibility maintained

## Useful Commands

```bash
# Build the project
swift build

# Run tests
swift test

# Run specific test
swift test --filter J2KCoreTests

# Generate documentation
swift package generate-documentation

# Run SwiftLint
swiftlint

# Format code (if swift-format is installed)
swift format --in-place --recursive Sources Tests
```

## Resources

- [Swift 6 Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [JPEG 2000 Standard](https://jpeg.org/jpeg2000/)
- [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- [SwiftLint Rules](https://realm.github.io/SwiftLint/rule-directory.html)

## Notes

- Prefer composition over inheritance
- Keep functions focused and small
- Avoid global state
- Use type inference wisely (explicit when it aids clarity)
- Write self-documenting code with good naming
- Add comments for complex algorithms or non-obvious decisions

---

Remember: The goal is to create a high-quality, production-ready JPEG 2000 implementation that the Swift community can rely on. Quality over speed, correctness over convenience, clarity over cleverness.
