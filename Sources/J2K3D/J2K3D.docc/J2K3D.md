# ``J2K3D``

JPEG 2000 Part 10 (JP3D) volumetric image compression for three-dimensional datasets.

## Overview

J2K3D implements the JP3D extension (ISO/IEC 15444-10) for compressing volumetric image data such as medical CT/MRI scans, satellite imagery stacks, and scientific datasets. It extends the standard JPEG 2000 codec with a third spatial dimension, applying 3D wavelet transforms and volumetric tiling.

The ``JP3DEncoder`` and ``JP3DDecoder`` actors provide the primary encoding and decoding interfaces. They support 3D discrete wavelet transforms via ``JP3DWaveletTransform``, volumetric region-of-interest decoding with ``JP3DROIDecoder``, and progressive quality/resolution access through ``JP3DProgressiveDecoder``.

Codestream handling is managed by ``JP3DCodestreamParser`` for reading and ``JP3DCodestreamBuilder`` for writing JP3D codestreams. The ``JP3DTranscoder`` enables conversion between different JP3D configurations without full decode-reencode cycles.

## Topics

### Encoding and Decoding

- ``JP3DEncoder``
- ``JP3DDecoder``
- ``JP3DProgressiveDecoder``
- ``JP3DROIDecoder``

### Wavelet Transform

- ``JP3DWaveletTransform``

### Codestream

- ``JP3DCodestreamParser``
- ``JP3DCodestreamBuilder``
- ``JP3DPacketSequencer``

### Volumetric Structure

- ``JP3DRegion``
- ``JP3DTile``
- ``JP3DPrecinct``

### Rate Control

- ``JP3DRateController``

### Transcoding

- ``JP3DTranscoder``
