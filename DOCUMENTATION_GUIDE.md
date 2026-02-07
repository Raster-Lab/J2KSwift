# Documentation Generation Guide for J2KSwift

This guide explains how to generate, build, and publish documentation for J2KSwift using Swift-DocC.

## Prerequisites

- Xcode 16.0 or later (includes Swift-DocC)
- Swift 6.2 or later
- macOS 13+ (for DocC generation)

## Quick Start

### Generate Documentation Locally

```bash
# Generate documentation for all modules
swift package generate-documentation

# Generate and preview in browser
swift package --disable-sandbox preview-documentation --target J2KCore
```

### Build Static Documentation Site

```bash
# Build documentation archive for hosting
swift package generate-documentation \
  --output-path ./docs \
  --hosting-base-path J2KSwift

# The generated site will be in ./docs/
```

## Module-by-Module Documentation

### Generate for Specific Modules

```bash
# J2KCore (foundational types)
swift package --disable-sandbox preview-documentation --target J2KCore

# J2KCodec (encoding/decoding components)
swift package --disable-sandbox preview-documentation --target J2KCodec

# J2KFileFormat (file I/O)
swift package --disable-sandbox preview-documentation --target J2KFileFormat

# J2KAccelerate (hardware acceleration)
swift package --disable-sandbox preview-documentation --target J2KAccelerate

# JPIP (streaming protocol)
swift package --disable-sandbox preview-documentation --target JPIP
```

## Publishing to GitHub Pages

### Option 1: Using GitHub Actions (Recommended)

Create `.github/workflows/documentation.yml`:

```yaml
name: Documentation

on:
  push:
    branches: [main, master]
    tags: ['v*']
  workflow_dispatch:

jobs:
  build-documentation:
    runs-on: macos-14
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Setup Swift
        uses: swift-actions/setup-swift@v1
        with:
          swift-version: '6.2'
      
      - name: Generate Documentation
        run: |
          swift package generate-documentation \
            --output-path ./docs \
            --hosting-base-path J2KSwift
      
      - name: Deploy to GitHub Pages
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./docs
```

### Option 2: Manual Deployment

```bash
# 1. Generate documentation
swift package generate-documentation \
  --output-path ./docs \
  --hosting-base-path J2KSwift

# 2. Initialize gh-pages branch (first time only)
git checkout --orphan gh-pages
git reset --hard
cp -r docs/* .
git add .
git commit -m "Initial documentation"
git push origin gh-pages

# 3. For updates
git checkout main
swift package generate-documentation \
  --output-path ./docs \
  --hosting-base-path J2KSwift
  
git checkout gh-pages
rm -rf *
cp -r docs/* .
git add .
git commit -m "Update documentation for $(git describe --tags)"
git push origin gh-pages
```

### Enable GitHub Pages

1. Go to repository Settings
2. Navigate to "Pages" section
3. Source: Deploy from branch
4. Branch: `gh-pages` / `/ (root)`
5. Save

Documentation will be available at: `https://raster-lab.github.io/J2KSwift/`

## Documentation Structure

### Expected Output

```
docs/
├── data/
│   └── documentation/
│       ├── j2kcore/
│       │   ├── j2kimage.json
│       │   ├── j2kconfiguration.json
│       │   └── ...
│       ├── j2kcodec/
│       │   ├── j2kencoder.json
│       │   ├── j2kdecoder.json
│       │   └── ...
│       └── ...
├── documentation/
│   ├── j2kcore/
│   ├── j2kcodec/
│   └── ...
├── css/
├── js/
└── index.html
```

## Customizing Documentation

### Add Documentation Catalog (Optional)

Create `Sources/J2KCore/J2KCore.docc/`:

```
J2KCore.docc/
├── J2KCore.md              # Module landing page
├── GettingStarted.md       # Getting started guide
├── Tutorials/              # Step-by-step tutorials
│   └── EncodingBasics.tutorial
└── Resources/              # Images, videos
    └── diagram.png
```

Example `J2KCore.md`:

```markdown
# ``J2KCore``

Core types and utilities for JPEG 2000 processing.

## Overview

J2KCore provides the foundational types and infrastructure for J2KSwift. It includes image representation, memory management, and I/O primitives used by all other modules.

## Topics

### Image Representation
- ``J2KImage``
- ``J2KComponent``
- ``J2KTile``
- ``J2KTileComponent``

### Configuration
- ``J2KConfiguration``
- ``J2KColorSpace``

### Memory Management
- ``J2KBuffer``
- ``J2KImageBuffer``
- ``J2KMemoryPool``

### I/O
- ``J2KBitReader``
- ``J2KBitWriter``

### Error Handling
- ``J2KError``
```

### Add Code Examples

In source files, add example code to documentation comments:

```swift
/// Encodes an image to JPEG 2000 format.
///
/// Example usage:
/// ```swift
/// let image = J2KImage(width: 512, height: 512, components: 3)
/// let encoder = J2KEncoder(configuration: .balanced)
/// let data = try encoder.encode(image)
/// ```
///
/// - Parameter image: The image to encode
/// - Returns: Encoded JPEG 2000 data
/// - Throws: ``J2KError`` if encoding fails
public func encode(_ image: J2KImage) throws -> Data {
    // Implementation
}
```

## Verifying Documentation Coverage

### Check for Missing Documentation

```bash
# Build with documentation warnings
swift build -Xswiftc -warn-missing-docs

# Or use xcodebuild
xcodebuild build \
  -scheme J2KSwift-Package \
  -destination 'platform=macOS' \
  OTHER_SWIFT_FLAGS="-Xfrontend -warn-on-missing-doc-comments"
```

### Documentation Coverage Report

```bash
# Generate and analyze
swift package generate-documentation \
  --analyze \
  --output-path ./docs

# Check for warnings in build output
```

## Best Practices

### 1. Document All Public APIs

Every public type, method, and property should have:
- Summary line
- Detailed description
- Parameter descriptions
- Return value description
- Throws clause
- Example usage (for complex APIs)

### 2. Use Proper Markup

```swift
/// Brief summary in one line.
///
/// Detailed description with multiple paragraphs.
///
/// Use **bold**, *italic*, and `code` formatting.
///
/// - Parameters:
///   - name: Parameter description
///   - value: Another parameter
/// - Returns: Return value description
/// - Throws: Exception description
///
/// Example:
/// ```swift
/// let result = try function(name: "test", value: 42)
/// ```
///
/// - Note: Additional notes
/// - Warning: Important warnings
/// - Important: Critical information
/// - SeeAlso: Related types
```

### 3. Cross-Reference Types

Use double backticks to link to other types:

```swift
/// Processes an image using ``J2KDWT2D`` for wavelet transform.
///
/// See also ``J2KQuantizer`` and ``J2KMQCoder``.
```

### 4. Organize with Topics

Group related APIs in topic sections in `.docc` files.

## Integration with README

Update README.md with documentation link:

```markdown
## 📚 Documentation

Full API documentation is available at: https://raster-lab.github.io/J2KSwift/

- [Getting Started Guide](https://raster-lab.github.io/J2KSwift/documentation/j2kcore/getting-started)
- [API Reference](https://raster-lab.github.io/J2KSwift/documentation/j2kcore)
- [Tutorials](https://raster-lab.github.io/J2KSwift/tutorials)
```

## Troubleshooting

### "No such module" Errors

If DocC can't find modules:

```bash
# Build first
swift build

# Then generate documentation
swift package generate-documentation
```

### Missing Symbols

Ensure types are marked `public`:

```swift
// Will appear in documentation
public struct J2KImage { }

// Will NOT appear
internal struct InternalType { }
```

### Build Failures

```bash
# Clean build directory
swift package clean

# Reset package cache
rm -rf .build

# Try again
swift package generate-documentation
```

### Hosting Issues

- Ensure `--hosting-base-path` matches repository name
- Check GitHub Pages is enabled in repository settings
- Verify gh-pages branch exists and has content
- Wait 1-2 minutes for GitHub Pages to update

## Additional Resources

- [Swift-DocC Documentation](https://www.swift.org/documentation/docc/)
- [Swift-DocC Plugin](https://github.com/apple/swift-docc-plugin)
- [Documenting a Swift Framework or Package](https://developer.apple.com/documentation/xcode/documenting-a-swift-framework-or-package)

## Automated Documentation Updates

For continuous documentation updates, consider:

1. **On Every Commit**: Update docs on main branch pushes
2. **On Release**: Update docs when tags are created
3. **Nightly**: Rebuild docs daily to catch issues
4. **On PR**: Preview documentation for pull requests

Example workflow trigger:

```yaml
on:
  push:
    branches: [main]
  release:
    types: [published]
  schedule:
    - cron: '0 0 * * *'  # Daily at midnight
```

## Version-Specific Documentation

To maintain multiple documentation versions:

```bash
# Tag documentation with version
git checkout v1.0.0
swift package generate-documentation \
  --output-path ./docs/1.0.0 \
  --hosting-base-path J2KSwift/1.0.0

# Deploy to versioned path
# Repeat for each version
```

Create a landing page that links to different versions.

---

**Last Updated**: 2026-02-07  
**Swift-DocC Version**: 6.2.3  
**Xcode Version**: 16.0+
