# HTJ2K Guide

High-Throughput JPEG 2000 (HTJ2K, ISO/IEC 15444-15) replaces the traditional block
coding engine with a highly parallelisable algorithm that can achieve 10–100× faster
throughput on modern hardware.  J2KSwift supports the full HTJ2K specification,
including the CAP and CPF markers and the optional VLC and MEL optimisations.

---

## Overview

| Feature | Standard J2K | HTJ2K |
|---------|-------------|-------|
| Block coder | MQ arithmetic | HT block coder |
| Throughput | ~200 MB/s | 2–10 GB/s |
| Lossless | ✅ | ✅ |
| Lossy     | ✅ | ✅ |
| Container | JP2 / J2K  | JP2 / JPH |
| ISO part  | Parts 1, 2 | Part 15 |

---

## Encoding an HTJ2K Codestream

```swift
import J2KCore
import J2KCodec

let htConfig = J2KEncodingConfiguration(
    progressionOrder: .LRCP,
    qualityLayers: 1,
    decompositionLevels: 5,
    useHTJ2K: true,
    enableFastMEL: true,
    enableVLCOptimization: true,
    enableMagSgnPacking: true
)
let encoder = J2KEncoder(encodingConfiguration: htConfig)
let data    = try encoder.encode(image)
```

### HTJ2K-Specific Options

| Option                   | Default | Effect |
|--------------------------|---------|--------|
| `useHTJ2K`               | `false` | Enables HT block coding |
| `enableFastMEL`          | `true`  | Fast MEL entropy coding |
| `enableVLCOptimization`  | `true`  | VLC table optimisation |
| `enableMagSgnPacking`    | `true`  | Efficient magnitude/sign packing |

---

## Writing to a JPH File

JPH (`.jph`) is the recommended container for HTJ2K codestreams as it includes
the CAP marker required by ISO/IEC 15444-15.

```swift
import J2KFileFormat

let writer = J2KFileWriter(format: .jph)
try writer.write(image, to: URL(fileURLWithPath: "output.jph"))
```

---

## Transcoding Standard J2K → HTJ2K

```swift
import J2KCodec

let transcoder = J2KTranscoder()

// Synchronous transcode
let htData = try transcoder.transcode(
    standardJ2KData,
    to: .htj2k
)

// Async transcode (recommended for large images)
let htData = try await transcoder.transcodeAsync(
    standardJ2KData,
    to: .htj2k
)
```

### Detecting HTJ2K Input

```swift
let isHT = try transcoder.isHTJ2K(incomingData)
```

---

## Decoding an HTJ2K Codestream

`J2KDecoder` automatically detects and decodes HTJ2K codestreams — no extra
configuration required:

```swift
let decoder = J2KDecoder()
let image   = try decoder.decode(htData)  // Works for both J2K and HTJ2K
```

---

## JP3D + HTJ2K

Volumetric data can also be encoded with HTJ2K for maximum throughput:

```swift
import J2K3D

let htj2kConfig = JP3DHTJ2KConfiguration.lowLatency
// See JP3D_GUIDE.md for full volumetric encoding examples.
```

---

## Performance Expectations

| Operation        | Apple Silicon (M2) | Intel x86-64 |
|------------------|--------------------|--------------|
| HTJ2K encode     | ≥3× vs standard    | ≥1.5× vs standard |
| HTJ2K decode     | ≥3× vs standard    | ≥1.5× vs standard |

Performance figures are approximate and depend on image dimensions and quality settings.

---

## Conformance

J2KSwift implements ISO/IEC 15444-15:2019 (HTJ2K) including:

- CAP (Coding style extension APplication) marker
- CPF (Corresponding Profile) marker
- Reversible (lossless) HT block coding
- Irreversible (lossy) HT block coding
- All five progression orders

---

## See Also

- [Encoding Guide](ENCODING_GUIDE.md)
- [Decoding Guide](DECODING_GUIDE.md)
- [CLI Guide](CLI_GUIDE.md) — `j2k encode --htj2k` flag
- [Examples/HTJ2KTranscoding.swift](../Examples/HTJ2KTranscoding.swift)
