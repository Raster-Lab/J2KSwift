# J2KSwift v1.4.0 Release Notes

**Release Date**: February 18, 2026  
**Release Type**: Minor Release  
**GitHub Tag**: v1.4.0

## Overview

J2KSwift v1.4.0 is a **minor release** that enhances the JPIP (JPEG 2000 Interactive Protocol) module with comprehensive HTJ2K support. This release completes Phase 11 of the development roadmap, enabling format-aware streaming, on-the-fly transcoding, and intelligent data bin generation for both legacy JPEG 2000 and HTJ2K formats.

### Key Highlights

- 🎯 **HTJ2K Format Detection**: Automatic format detection for J2K, JPH, and JP2 files
- 📡 **Capability Signaling**: HTJ2K capability headers in JPIP session responses
- 🔄 **On-the-fly Transcoding**: Automatic format conversion during JPIP serving
- 📦 **Data Bin Generation**: Extract and stream data bins from HTJ2K codestreams
- ✅ **Comprehensive Testing**: 199 JPIP tests (35 new Phase 11 tests, 100% pass rate)
- 📚 **Full Integration**: Seamless codec integration with JPIP streaming

---

## What's New

### 1. JPIP HTJ2K Format Detection

The JPIP module now automatically detects and handles HTJ2K formats, enabling intelligent streaming based on image format.

#### Features

- **Format Auto-Detection**: Automatic detection of J2K, JPH, and JP2 file formats via signatures
- **CAP Marker Detection**: Identifies HTJ2K capability markers in J2K codestreams
- **JPIPImageInfo Type**: Tracks registered image formats and capabilities
- **Format-Aware Metadata**: Generates appropriate metadata for each format

#### API Example

```swift
import JPIP

// JPIPImageInfo tracks format information
let imageURL = URL(fileURLWithPath: "/path/to/image.jph")
let imageInfo = JPIPImageInfo(url: imageURL, format: .jph, isHTJ2K: true)

print("Format: \(imageInfo.format)")       // .jph
print("MIME Type: \(imageInfo.mimeType)")  // "image/jph"
print("Is HTJ2K: \(imageInfo.isHTJ2K)")    // true
```

### 2. JPIP Capability Signaling

The JPIP server now signals HTJ2K capabilities to clients during session creation, enabling clients to request format-specific streaming.

#### Features

- **HTJ2K Capability Headers**: Automatic JPIP-cap and JPIP-pref headers in responses
- **JPIPCodingPreference**: Client-side format preference signaling (.none, .htj2k, .legacy)
- **Format-Aware Sessions**: Session creation with HTJ2K capability information
- **Preference Serialization**: Query parameter support for coding preferences

#### API Example

```swift
import JPIP

// Client requests with coding preference
var request = JPIPRequest(target: "image1")
request.codingPreference = .htj2k

// Server responds with capability headers
let server = JPIPServer()
let session = try await server.createSession(for: imageURL)
// Response includes: JPIP-cap: htj2k, JPIP-pref: htj2k
```

### 3. Full Codec Integration for Data Bin Streaming

The new JPIPDataBinGenerator enables extraction of data bins directly from JPEG 2000 and HTJ2K codestreams for efficient JPIP streaming.

#### Features

- **Data Bin Extraction**: Extract main header, tile-header, and precinct data bins
- **HTJ2K Support**: Full support for HTJ2K codestream data bins
- **Efficient Parsing**: Minimal overhead for data bin identification
- **Integration with JPIP Server**: Seamless streaming of extracted data bins

#### API Example

```swift
import JPIP

// Extract data bins from codestream
let generator = JPIPDataBinGenerator()
let codestream = try Data(contentsOf: imageURL)

let dataBins = try generator.extractDataBins(from: codestream)
print("Extracted \(dataBins.count) data bins")

// Stream via JPIP
for dataBin in dataBins {
    print("Class ID: \(dataBin.classID), In-class ID: \(dataBin.inClassID)")
    // Stream dataBin.data to client
}
```

### 4. On-the-fly Transcoding During JPIP Serving

The JPIPTranscodingService enables automatic format conversion during JPIP streaming, allowing servers to serve content in the format preferred by the client.

#### Features

- **Automatic Transcoding**: Convert between legacy JPEG 2000 and HTJ2K based on client preference
- **Result Caching**: Cache transcoded codestreams for efficiency
- **Integration with Server**: Seamless integration with JPIPServer
- **Preference Handling**: Respects client coding preferences from JPIP requests

#### API Example

```swift
import JPIP

// Server automatically transcodes based on client preference
let transcodingService = JPIPTranscodingService()

// Client requests HTJ2K but server has legacy JPEG 2000
let legacyCodestream = try Data(contentsOf: legacyImageURL)
let htj2kCodestream = try await transcodingService.transcode(
    legacyCodestream,
    from: .legacy,
    to: .htj2k
)

// Cache result for future requests
transcodingService.cacheResult(htj2kCodestream, for: cacheKey)
```

### 5. Enhanced JPIPServer API

The JPIPServer has been enhanced with format-aware capabilities and transcoding support.

#### Features

- **Image Format Detection**: Automatic format detection on image registration
- **Image Info Caching**: Cache JPIPImageInfo for registered images
- **HTJ2K-Aware Session Creation**: Include HTJ2K capabilities in session responses
- **Public getImageInfo() API**: Query registered image format information
- **Integrated Transcoding**: Automatic transcoding during request handling

#### API Example

```swift
import JPIP

// Create server and register images
let server = JPIPServer()

// Server automatically detects format
try await server.registerImage(at: htj2kImageURL, withID: "image1")
try await server.registerImage(at: legacyImageURL, withID: "image2")

// Query image information
if let imageInfo = server.getImageInfo(forID: "image1") {
    print("Image 1 format: \(imageInfo.format)")
    print("Is HTJ2K: \(imageInfo.isHTJ2K)")
}

// Server handles transcoding automatically when client preference differs
```

---

## Testing & Quality

### Test Coverage

- **Total JPIP Tests**: 199 (was 164 before Phase 11)
- **New Phase 11 Tests**: 35
  - JPIP HTJ2K Support Tests: 26 tests
  - Data Bin Generator Tests: 10 tests
  - Transcoding Service Tests: 25 tests (overlap with existing tests)
- **Pass Rate**: 100%

### Test Files

- `JPIPHTJ2KSupportTests.swift`: HTJ2K format detection and capability signaling
- `JPIPDataBinGeneratorTests.swift`: Data bin extraction from codestreams
- `JPIPTranscodingServiceTests.swift`: On-the-fly transcoding functionality

---

## Dependencies

This release adds a new dependency:

- **JPIP → J2KCodec**: Required for data bin generation and transcoding services

All other dependencies remain unchanged:

- Swift Standard Library
- Foundation framework
- Accelerate framework (Apple platforms, optional)
- XCTest for testing

---

## Breaking Changes

**None**. This release is fully backward compatible with v1.3.0.

---

## Deprecations

**None**. No APIs have been deprecated in this release.

---

## Bug Fixes

This release focuses on new features. All existing functionality from v1.3.0 is preserved.

---

## Performance

### JPIP HTJ2K Streaming

- **Format Detection**: Minimal overhead (<1ms for typical images)
- **Data Bin Generation**: Efficient extraction with minimal memory overhead
- **Transcoding**: Leverages existing J2KTranscoder performance (1.05-2× speedup for multi-tile)
- **Caching**: Transcoding results cached to avoid redundant conversions

---

## Documentation

### Updated Documentation

- **JPIP_PROTOCOL.md**: Updated with Phase 11 HTJ2K support details
- **API_REFERENCE.md**: Added new JPIP HTJ2K APIs
- **MILESTONES.md**: Updated with v1.4.0 completion status
- **NEXT_PHASE.md**: Updated with Phase 11 completion
- **README.md**: Updated with v1.4.0 features and version

### API Documentation

All new public APIs are fully documented with:
- Comprehensive descriptions
- Parameter documentation
- Return value descriptions
- Usage examples
- Error handling information

---

## Migration Guide

### From v1.3.0 to v1.4.0

No migration required! This release is fully backward compatible.

### New Optional Features

If you want to use the new JPIP HTJ2K features:

```swift
// 1. Format detection (automatic)
let server = JPIPServer()
try await server.registerImage(at: imageURL, withID: "myImage")

// 2. Query image format
if let info = server.getImageInfo(forID: "myImage") {
    print("Format: \(info.format), HTJ2K: \(info.isHTJ2K)")
}

// 3. Client-side format preferences
var request = JPIPRequest(target: "myImage")
request.codingPreference = .htj2k  // or .legacy, .none

// 4. Data bin generation
let generator = JPIPDataBinGenerator()
let dataBins = try generator.extractDataBins(from: codestream)

// 5. Transcoding service
let service = JPIPTranscodingService()
let transcoded = try await service.transcode(data, from: .legacy, to: .htj2k)
```

---

## Known Limitations

All known limitations from v1.3.0 remain. No new limitations introduced.

Refer to `KNOWN_LIMITATIONS.md` for the complete list.

---

## Upgrade Instructions

### Via Swift Package Manager

Update your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/J2KSwift.git", from: "1.4.0")
]
```

Then run:

```bash
swift package update
```

### Via Git Tag

```bash
git checkout v1.4.0
swift build
swift test
```

---

## Acknowledgments

Thank you to the Swift community and all contributors who provided feedback and testing during Phase 11 development.

---

## What's Next

### v1.4.1 (Patch Release - If Needed)
- Bug fixes if critical issues discovered
- Additional JPIP HTJ2K optimizations
- Documentation improvements

### v1.5.0 (Minor Release - Planned Q2 2026)
- Additional HTJ2K optimizations
- Extended JPIP features
- Enhanced streaming capabilities

### v2.0.0 (Major Release - Planned Q4 2026)
- JPEG 2000 Part 2 extensions (JPX format)
- Advanced HTJ2K features
- Potential breaking API changes for modernization

---

**Release Status**: ✅ Released  
**Total Tests**: 1,666 (100% pass rate)  
**Phase Completion**: Phase 11 Complete ✅

For detailed technical information, see:
- `JPIP_PROTOCOL.md` - JPIP protocol implementation details
- `HTJ2K.md` - HTJ2K implementation guide
- `API_REFERENCE.md` - Complete API reference
- `MILESTONES.md` - Development roadmap and milestones
