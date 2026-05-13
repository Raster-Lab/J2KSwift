# Troubleshooting Guide

Common issues and solutions when working with J2KSwift.

## Table of Contents

- [Installation Issues](#installation-issues)
- [Compilation Errors](#compilation-errors)
- [Runtime Errors](#runtime-errors)
- [Performance Issues](#performance-issues)
- [Memory Issues](#memory-issues)
- [Image Quality Issues](#image-quality-issues)
- [File Format Issues](#file-format-issues)
- [Concurrency Issues](#concurrency-issues)
- [Platform-Specific Issues](#platform-specific-issues)

## Installation Issues

### SPM Cannot Resolve Dependencies

**Problem:**
```
error: Dependencies could not be resolved
```

**Solutions:**

1. **Check Swift version:**
   ```bash
   swift --version  # Should be 6.0 or later
   ```

2. **Clean package cache:**
   ```bash
   swift package clean
   swift package update
   swift package resolve
   ```

3. **Remove derived data:**
   ```bash
   rm -rf .build
   rm -rf ~/Library/Developer/Xcode/DerivedData
   ```

4. **Verify Package.swift:**
   ```swift
   platforms: [
       .macOS(.v13),  // Minimum: macOS 13
       .iOS(.v16),    // Minimum: iOS 16
   ]
   ```

### Xcode Build Fails

**Problem:**
```
Build failed with Xcode
```

**Solutions:**

1. **Update Xcode:**
   - Requires Xcode 15.0 or later for Swift 6

2. **Clean build folder:**
   - Product → Clean Build Folder (⇧⌘K)

3. **Reset package cache:**
   - File → Packages → Reset Package Caches

4. **Check deployment target:**
   - Project settings → Deployment Info
   - Set to macOS 13+ / iOS 16+

## Compilation Errors

### Swift 6 Concurrency Warnings

**Problem:**
```swift
warning: capture of 'self' with non-sendable type in a Sendable closure
```

**Solution:**

Use `@Sendable` closures or actors:

```swift
// Before
Task {
    self.processImage()  // Warning!
}

// After
Task { @Sendable in
    await actor.processImage()
}

// Or use actor
actor ImageProcessor {
    func processImage() { }
}
```

### Type Mismatch Errors

**Problem:**
```swift
error: cannot convert value of type '[UInt8]' to expected argument type 'Data'
```

**Solution:**

```swift
// Convert UInt8 array to Data
let data = Data(byteArray)

// Convert Data to UInt8 array
let byteArray = [UInt8](data)
```

### Missing Import

**Problem:**
```swift
error: cannot find 'J2KImage' in scope
```

**Solution:**

Add missing imports:

```swift
import J2KCore       // For J2KImage, J2KConfiguration
import J2KCodec      // For J2KEncoder, J2KDecoder
import J2KFileFormat // For J2KFileReader, J2KFileWriter
```

## Runtime Errors

### J2KError.invalidParameter

**Problem:**
```swift
J2KError.invalidParameter("Width must be positive")
```

**Common Causes & Solutions:**

1. **Invalid image dimensions:**
   ```swift
   // Wrong
   let image = J2KImage(width: 0, height: 0, components: 3)
   
   // Correct
   let image = J2KImage(width: 512, height: 512, components: 3)
   ```

2. **Invalid bit depth:**
   ```swift
   // Wrong
   let image = J2KImage(width: 512, height: 512, components: 3, bitDepth: 0)
   
   // Correct
   let image = J2KImage(width: 512, height: 512, components: 3, bitDepth: 8)
   ```

3. **Invalid tile size:**
   ```swift
   // Wrong
   let image = J2KImage(width: 512, height: 512, components: 3, tileWidth: 0, tileHeight: 1)
   
   // Correct (both 0 or both positive)
   let image = J2KImage(width: 512, height: 512, components: 3, tileWidth: 256, tileHeight: 256)
   ```

### J2KError.encodingFailed

**Problem:**
```swift
J2KError.encodingFailed("Encoding failed: ...")
```

**Common Causes & Solutions:**

1. **Empty image buffer:**
   ```swift
   // Ensure buffer has data
   let image = J2KImage(width: 512, height: 512, components: 3)
   // Fill buffer with data...
   for i in 0..<(512 * 512) {
       image.components[0].buffer.setValue(0, at: i)
   }
   ```

2. **Incompatible configuration:**
   ```swift
   // Check configuration
   let config = J2KConfiguration(
       decompositionLevels: 5,  // Must be < log2(min(width, height))
       quality: 0.9
   )
   ```

3. **Memory limit exceeded:**
   ```swift
   // Use tiling for large images
   let image = J2KImage(
       width: 10000, height: 10000,
       components: 3,
       tileWidth: 512,
       tileHeight: 512
   )
   ```

### J2KError.decodingFailed

**Problem:**
```swift
J2KError.decodingFailed("Invalid codestream")
```

**Common Causes & Solutions:**

1. **Corrupted data:**
   ```swift
   // Verify data integrity
   do {
       let detector = J2KFormatDetector()
       let format = try detector.detect(data: data)
       print("Valid \(format) file")
   } catch {
       print("Corrupted or invalid file")
   }
   ```

2. **Unsupported format:**
   ```swift
   // Check format before decoding
   let detector = J2KFormatDetector()
   let format = try detector.detect(data: data)
   
   switch format {
   case .jp2, .j2k:
       // Supported
       let image = try decoder.decode(data)
   case .jpx, .jpm:
       // May need special handling
       let reader = J2KFileReader()
       let image = try reader.read(data: data)
   }
   ```

3. **Incomplete data:**
   ```swift
   // For streaming, use incremental decoder
   let incrementalDecoder = try decoder.createIncrementalDecoder()
   try incrementalDecoder.addData(partialData)
   
   if incrementalDecoder.isComplete {
       let image = try incrementalDecoder.getImage()
   } else {
       print("Need more data: \(incrementalDecoder.completionProgress * 100)%")
   }
   ```

## Performance Issues

### Slow Encoding

**Problem:** Encoding takes too long

**Solutions:**

1. **Use faster preset:**
   ```swift
   let config = J2KConfiguration(preset: .fast)  // 2-3× faster
   let encoder = J2KEncoder(configuration: config)
   ```

2. **Reduce decomposition levels:**
   ```swift
   let config = J2KConfiguration(decompositionLevels: 3)  // Instead of 5
   ```

3. **Use tiling for large images:**
   ```swift
   let image = J2KImage(
       width: 8192, height: 8192,
       components: 3,
       tileWidth: 512,
       tileHeight: 512  // Process tiles in parallel
   )
   ```

4. **Enable hardware acceleration (automatic on Apple platforms):**
   ```swift
   import J2KAccelerate
   
   // Automatically used when available
   let encoder = J2KEncoder(configuration: config)
   ```

### Slow Decoding

**Problem:** Decoding takes too long

**Solutions:**

1. **Use partial decoding:**
   ```swift
   // Decode only what you need
   let options = J2KDecodingOptions(
       maxLayers: 3,          // Don't decode all layers
       resolutionLevel: 1     // Decode at half resolution
   )
   let image = try decoder.partialDecode(data: data, options: options)
   ```

2. **Use ROI decoding for large images:**
   ```swift
   // Decode only visible region
   let roi = J2KDecodingROI(x: 0, y: 0, width: 1024, height: 1024)
   let image = try decoder.decodeROI(data: data, roi: roi, strategy: .direct)
   ```

3. **Use resolution pyramid:**
   ```swift
   // Show thumbnail first
   let thumbnail = try decoder.decodeResolution(data: data, level: 3)
   await display(thumbnail)
   
   // Load full resolution in background
   Task {
       let fullRes = try decoder.decode(data)
       await display(fullRes)
   }
   ```

## Memory Issues

### Out of Memory

**Problem:**
```swift
fatal error: Out of memory
```

**Solutions:**

1. **Use tiling:**
   ```swift
   let image = J2KImage(
       width: width, height: height,
       components: 3,
       tileWidth: 512,
       tileHeight: 512
   )
   ```

2. **Set memory limit:**
   ```swift
   let tracker = J2KMemoryTracker()
   tracker.setLimit(500_000_000)  // 500 MB
   
   let config = J2KConfiguration(memoryTracker: tracker)
   ```

3. **Process images sequentially:**
   ```swift
   // Don't load all images at once
   for imageURL in imageURLs {
       autoreleasepool {
           let data = try! Data(contentsOf: imageURL)
           let image = try! decoder.decode(data)
           process(image)
           // Image released after pool
       }
   }
   ```

4. **Use incremental decoding for streaming:**
   ```swift
   let incrementalDecoder = try decoder.createIncrementalDecoder()
   
   // Feed data in chunks
   for chunk in dataChunks {
       try incrementalDecoder.addData(chunk)
   }
   ```

### Memory Leaks

**Problem:** Memory usage grows over time

**Solutions:**

1. **Use autoreleasepool:**
   ```swift
   for i in 0..<1000 {
       autoreleasepool {
           let image = try! decoder.decode(data)
           process(image)
       }
   }
   ```

2. **Clear caches:**
   ```swift
   // For JPIP
   await session.invalidateCache()
   
   // For decoding
   let config = J2KDecodingConfiguration(
       cacheDecodedTiles: false  // Disable caching
   )
   ```

3. **Check for retain cycles:**
   ```swift
   // Use weak/unowned for closures
   Task { [weak self] in
       await self?.processImage()
   }
   ```

## Image Quality Issues

### Poor Quality After Encoding

**Problem:** Encoded image has visible artifacts

**Solutions:**

1. **Increase quality:**
   ```swift
   let config = J2KConfiguration(quality: 0.95)  // Instead of 0.8
   ```

2. **Reduce compression ratio:**
   ```swift
   let config = J2KConfiguration(compressionRatio: 5)  // Instead of 20
   ```

3. **Use lossless mode:**
   ```swift
   let config = J2KConfiguration(lossless: true)
   ```

4. **Increase decomposition levels:**
   ```swift
   let config = J2KConfiguration(decompositionLevels: 6)  // Instead of 3
   ```

5. **Use quality preset:**
   ```swift
   let config = J2KConfiguration(preset: .quality)
   ```

### Wrong Colors After Encoding/Decoding

**Problem:** Colors are incorrect

**Solutions:**

1. **Check color space:**
   ```swift
   print("Color space: \(image.colorSpace)")
   
   // Ensure correct color space
   let image = J2KImage(
       width: width, height: height,
       components: 3,
       colorSpace: .sRGB  // Specify explicitly
   )
   ```

2. **Verify color transform:**
   ```swift
   // Use RCT for lossless
   let losslessConfig = J2KConfiguration(
       lossless: true,
       colorTransform: .reversible
   )
   
   // Use ICT for lossy
   let lossyConfig = J2KConfiguration(
       lossless: false,
       colorTransform: .irreversible
   )
   ```

3. **Check component order:**
   ```swift
   // Ensure RGB order, not BGR
   let r = image.components[0]  // Should be red
   let g = image.components[1]  // Should be green
   let b = image.components[2]  // Should be blue
   ```

## File Format Issues

### Cannot Read JP2 File

**Problem:**
```swift
J2KError.fileFormatError("Invalid JP2 signature")
```

**Solutions:**

1. **Verify file format:**
   ```swift
   let detector = J2KFormatDetector()
   let format = try detector.detect(url: fileURL)
   print("Detected format: \(format)")
   ```

2. **Check file is not corrupted:**
   ```bash
   # Use OpenJPEG tools to verify
   opj_dump -i image.jp2
   ```

3. **Use appropriate reader:**
   ```swift
   // For JP2/JPX/JPM files
   let reader = J2KFileReader()
   let image = try reader.read(from: fileURL)
   
   // For raw codestreams (.j2k)
   let data = try Data(contentsOf: fileURL)
   let decoder = J2KDecoder()
   let image = try decoder.decode(data)
   ```

### Invalid Box Structure

**Problem:**
```swift
J2KError.fileFormatError("Invalid box length")
```

**Solutions:**

1. **Validate file integrity:**
   ```swift
   do {
       let reader = J2KFileReader()
       let image = try reader.read(from: fileURL)
       print("File is valid")
   } catch J2KError.fileFormatError(let message) {
       print("Invalid file: \(message)")
       // Try recovery or partial read
   }
   ```

2. **Check file size:**
   ```swift
   let attrs = try FileManager.default.attributesOfItem(atPath: filePath)
   let fileSize = attrs[.size] as! Int
   print("File size: \(fileSize) bytes")
   
   if fileSize < 12 {
       print("File too small to be valid JP2")
   }
   ```

## Concurrency Issues

### Actor Isolation Warnings

**Problem:**
```swift
warning: call to actor-isolated instance method 'process' in a synchronous nonisolated context
```

**Solution:**

Use `await`:

```swift
// Before
actor.process()  // Warning!

// After
await actor.process()  // ✓
```

### Data Race Warnings

**Problem:**
```swift
warning: data race detected
```

**Solution:**

Use `Sendable` types or actors:

```swift
// Before
var sharedImage: J2KImage?  // Not thread-safe

Task {
    sharedImage = try decoder.decode(data)  // Race!
}

// After
actor ImageStore {
    private var image: J2KImage?
    
    func setImage(_ img: J2KImage) {
        image = img
    }
}

let store = ImageStore()
Task {
    let img = try decoder.decode(data)
    await store.setImage(img)
}
```

## Platform-Specific Issues

### Linux Build Fails

**Problem:** Build fails on Linux

**Solutions:**

1. **Check Swift version:**
   ```bash
   swift --version  # Needs 6.0+
   ```

2. **Accelerate framework not available:**
   ```swift
   // J2KSwift automatically falls back to software implementation
   // No changes needed
   ```

3. **Install dependencies:**
   ```bash
   # Ubuntu/Debian
   sudo apt-get install libfoundation-dev
   ```

### iOS Simulator Issues

**Problem:** Tests fail on simulator

**Solutions:**

1. **Check simulator architecture:**
   - Use Rosetta for Intel Macs running Apple Silicon simulators

2. **Disable hardware acceleration in tests:**
   ```swift
   let config = J2KConfiguration(
       useHardwareAcceleration: false  // For consistent test results
   )
   ```

### visionOS Build Issues

**Problem:** Build fails for visionOS

**Solutions:**

1. **Ensure minimum version:**
   ```swift
   platforms: [
       .visionOS(.v1)  // Minimum: visionOS 1.0
   ]
   ```

2. **Check Xcode version:**
   - Requires Xcode 15.2+ for visionOS support

## Getting Help

If you're still experiencing issues:

1. **Check GitHub Issues:**
   - [Search existing issues](https://github.com/Raster-Lab/J2KSwift/issues)
   - Look for similar problems

2. **Create a Minimal Reproduction:**
   ```swift
   import J2KCore
   import J2KCodec
   
   // Minimal code that reproduces the issue
   let image = J2KImage(width: 512, height: 512, components: 3)
   let encoder = J2KEncoder()
   let data = try encoder.encode(image)  // Fails here
   ```

3. **Gather System Information:**
   ```bash
   swift --version
   uname -a
   xcodebuild -version  # For Xcode builds
   ```

4. **File an Issue:**
   - [Create a new issue](https://github.com/Raster-Lab/J2KSwift/issues/new)
   - Include code, error messages, and system info

5. **Ask in Discussions:**
   - [GitHub Discussions](https://github.com/Raster-Lab/J2KSwift/discussions)
   - Community support

## Quick Reference

### Common Error Patterns

```swift
// Always handle errors
do {
    let result = try operation()
} catch J2KError.invalidParameter(let msg) {
    print("Invalid: \(msg)")
} catch J2KError.encodingFailed(let msg) {
    print("Encoding: \(msg)")
} catch {
    print("Error: \(error)")
}

// For optional results
guard let image = try? decoder.decode(data) else {
    print("Decoding failed")
    return
}

// For async operations
Task {
    do {
        let image = try await client.requestImage(imageID: "test.jp2")
    } catch {
        print("Request failed: \(error)")
    }
}
```

### Debug Mode

```swift
// Enable verbose logging (if available)
let config = J2KConfiguration(
    debugMode: true,
    verbose: true
)

// Profile performance
let profiler = J2KPipelineProfiler()
profiler.start("encoding")
let data = try encoder.encode(image)
profiler.stop("encoding")
print(profiler.report())
```

---

**Status**: Troubleshooting Guide for Phase 8 (Production Ready)  
**Last Updated**: 2026-02-07
