# ``J2KCore``

The core foundation module providing fundamental JPEG 2000 types, image representation, configuration, error handling, memory management, and benchmarking utilities.

## Overview

J2KCore is the foundational layer of the J2KSwift library. It defines the essential data structures and abstractions used throughout all other modules, including image and tile representations, colour space definitions, codestream markers, memory buffers, and performance profiling tools.

All types in J2KCore are designed for Swift 6 strict concurrency, with ``Sendable`` conformance throughout. The module has no external dependencies beyond Foundation, ensuring broad cross-platform compatibility across macOS, iOS, Linux, and Windows.

Use J2KCore when you need to:

- Represent JPEG 2000 images, tiles, and components
- Configure encoding and decoding parameters
- Parse or construct JPEG 2000 codestream markers
- Manage memory-efficient buffers with SIMD alignment
- Profile and benchmark codec operations
- Validate conformance against JPEG 2000 standards

## Topics

### Image Representation

- ``J2KImage``
- ``J2KComponent``
- ``J2KTile``
- ``J2KTileComponent``
- ``J2KPrecinct``
- ``J2KCodeBlock``
- ``J2KSubband``
- ``J2KColorSpace``

### Configuration and Errors

- ``J2KConfiguration``
- ``J2KError``

### Memory Management

- ``J2KBuffer``
- ``J2KImageBuffer``
- ``J2KSIMDAlignedBuffer``
- ``J2KUnifiedMemoryManager``
- ``J2KCompressedMemoryMonitor``

### Codestream Markers and Bit I/O

- ``J2KMarker``
- ``J2KMarkerSegment``
- ``J2KMarkerParser``
- ``J2KBitReader``
- ``J2KBitWriter``

### Performance and Benchmarking

- ``J2KBenchmarkRunner``
- ``J2KPipelineProfiler``
- ``J2KPerformanceOptimizer``
- ``J2KReferenceBenchmark``

### Concurrency

- ``J2KGCDDispatcher``
- ``J2KActorContentionAnalyzer``
- ``J2KPowerEfficiencyManager``
- ``J2KThermalStateMonitor``

### Conformance Validation

- ``J2KConformanceValidator``
- ``J2KPart1ConformanceTestSuite``
- ``J2KPart2ConformanceValidator``
- ``J2KConformanceMatrix``
- ``HTJ2KConformanceTestHarness``

### Platform Utilities

- ``J2KPlatform``
- ``J2KMemoryInfo``
- ``J2KPathUtilities``
- ``J2KFoundationCompat``
- ``J2KAsyncFileIO``

### Volumetric Data

- ``J2KVolume``
- ``J2KVolumeComponent``
- ``J2KVolumeMetadata``
- ``J2KVolumeModality``
