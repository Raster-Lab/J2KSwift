# DICOM Studio claim-scope finding

**Date:** 2026-05-14
**Reason:** DICOMKit / DICOM Studio is the downstream product integration, so it must constrain any public "beats Kakadu" language.

## Finding

DICOM Studio proves that raw J2KSwift benchmark wins are not automatically product claims. It uses J2KSwift through the DICOMKit adapter, with DICOM parsing, frame extraction, byte-order packing, round-trip validation, preview rendering, and optional cross-codec comparison layered around the codec.

Local evidence:

- `/Users/raster/Documents/raster/DICOMKit/Package.swift` consumes this checkout through `.package(path: "../J2KSwift")` and exports a `DICOMStudio` product.
- `/Users/raster/Documents/raster/DICOMKit/Sources/DICOMStudio/App/DICOMStudioApp.swift` calls `J2KSwiftCodec.preWarm()` at app startup, matching the intended warm-process SDK path.
- `/Users/raster/Documents/raster/DICOMKit/Sources/DICOMCore/J2KSwiftCodec.swift` adapts `PixelDataDescriptor` and DICOM frame bytes into `J2KImage`, then verifies lossless encode/decode round-trips.
- `/Users/raster/Documents/raster/DICOMKit/Sources/DICOMCore/KakaduCLICodec.swift` and `GrokCLICodec.swift` are decode-only subprocess adapters used exclusively in the DICOM Studio comparison panel, not registered as production codecs.
- `/Users/raster/Documents/raster/DICOMKit/Sources/DICOMStudio/ViewModels/J2KTestingViewModel.swift` encodes frame 0 with J2KSwift and decodes the same codestream with J2KSwift, OpenJPEG, Kakadu CLI, and Grok CLI when available.
- `/Users/raster/Documents/raster/DICOMKit/Sources/DICOMStudio/Views/J2KTestingView.swift` explicitly warns that the comparison is a single fixture and that CLI codecs include process spawn plus temp-file I/O.

## Claim impact

Do not use:

> "Fastest JPEG 2000 codec on Apple Silicon."

That is too broad. The current benchmark set disproves it:

- Sustained CLI encode: `CROSS_HOST_M2_M4_sustained.md` shows J2KSwift+daemon wins 0/38 fixtures on both M2 and M4.
- Focused decode: `J2KSWIFT_OPTIMAL_VS_KAKADU.md` shows Kakadu leading every listed decode fixture by about 1.9-4.5x.
- Large encode: Kakadu still leads PX, DX, and mammography-scale fixtures.

Use scoped language instead:

> "J2KSwift's in-process Apple Silicon SDK encoder is faster than Kakadu's CLI on selected small and medium HT-conformant-lossless medical fixtures; Kakadu remains faster for sustained CLI, decode, and large batch encode workloads."

## Benchmark policy

For codec-core engineering, raw in-process J2KSwift benchmarks are still useful.

For product-facing DICOM claims, cite DICOMKit / DICOM Studio measurements or an equivalent production integration path. A raw J2KSwift SDK-vs-Kakadu-CLI table may support a narrow SDK-positioning statement, but it is not enough to claim end-to-end DICOM Studio superiority.
