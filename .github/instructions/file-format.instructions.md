---
description: "Use when editing JPEG 2000 file format code: JP2 boxes, JPX extensions, MJ2 Motion JPEG 2000, format detection, file readers/writers, box parsing, metadata."
applyTo: "Sources/J2KFileFormat/**"
---

# File Format Guidelines

## Box Parsing Safety
- Always validate box length before reading content
- Handle truncated boxes gracefully (don't crash)
- Support both 4-byte and 8-byte (extended) box lengths
- Never trust box length to be within file bounds — check first

## Format Detection
JP2 signature: `0x0000000C 6A502020 0D0A870A`
J2K codestream starts with SOC marker: `0xFF4F`

## Memory Efficiency
- Parse boxes lazily — don't load entire file into memory
- Stream large codestream boxes rather than buffering
- Use memory-mapped I/O for files > 100MB

## MJ2 (Motion JPEG 2000)
- Based on ISO Base Media File Format (ISOBMFF/MP4)
- Sample table (stbl) must be consistent with frame data
- Support variable frame rates via sample duration
