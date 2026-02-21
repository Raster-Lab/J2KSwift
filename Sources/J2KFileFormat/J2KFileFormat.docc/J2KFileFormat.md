# ``J2KFileFormat``

File format support for the JPEG 2000 family of standards: JP2, J2K, JPX, JPM, and MJ2.

## Overview

J2KFileFormat handles reading and writing JPEG 2000 file formats as defined by ISO/IEC 15444-1 (JP2), ISO/IEC 15444-2 (JPX), ISO/IEC 15444-6 (JPM), and ISO/IEC 15444-3 (MJ2). The module implements the box-based file structure used across all JPEG 2000 container formats.

The ``J2KFormatDetector`` automatically identifies file formats from their signatures. ``J2KFileReader`` and ``J2KFileWriter`` provide high-level interfaces for reading and writing complete files, whilst the box-level API (``J2KBoxReader`` and ``J2KBoxWriter``) enables fine-grained control over individual boxes within the file structure.

Motion JPEG 2000 support includes ``MJ2FileReader`` for reading video files, ``MJ2Player`` for playback, and ``MJ2Creator`` for authoring MJ2 content.

## Topics

### Format Detection

- ``J2KFormat``
- ``J2KFormatDetector``

### File Reading and Writing

- ``J2KFileReader``
- ``J2KFileWriter``

### Box Infrastructure

- ``J2KBox``
- ``J2KBoxType``
- ``J2KBoxReader``
- ``J2KBoxWriter``

### JP2 Boxes

- ``J2KSignatureBox``
- ``J2KFileTypeBox``
- ``J2KImageHeaderBox``
- ``J2KColourSpecificationBox``
- ``J2KChannelDefinitionBox``
- ``J2KResolutionBox``
- ``J2KPaletteBox``
- ``J2KComponentMappingBox``
- ``J2KBitsPerComponentBox``
- ``J2KIntellectualPropertyBox``
- ``J2KXMLBox``
- ``J2KUUIDBox``
- ``J2KUUIDInfoBox``
- ``J2KURLBox``
- ``J2KContiguousCodestreamBox``

### JPX Extended Format

- ``J2KJPXAnimationSequence``

### Motion JPEG 2000

- ``MJ2FileReader``
- ``MJ2Player``
- ``MJ2Creator``
- ``MJ2Extractor``
