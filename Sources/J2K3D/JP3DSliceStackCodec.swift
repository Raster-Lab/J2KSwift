//
//  JP3DSliceStackCodec.swift
//  J2KSwift
//
//  Slice-stack tile-payload codec for JP3D (M2 — replaces the
//  raw-Int32 entropy stub at JP3DEncoder.swift:387-392 and the
//  matching decoder path).
//
//  A volumetric tile is encoded as a sequence of fully-J2K-compliant
//  2D codestreams (one per Z-slice), wrapped in a small fixed header:
//
//      Bytes  Field
//      0..3   Magic  'J3DS' (0x4A 0x33 0x44 0x53)
//      4..7   Version (uint32 BE = 1)
//      8..11  Flags    (uint32 BE — bit 0 = HTJ2K, bit 1 = lossless)
//      12..15 Slice count (uint32 BE)
//      16..19 Tile width  in voxels (uint32 BE)
//      20..23 Tile height in voxels (uint32 BE)
//      24..27 Component count (uint32 BE)
//      28..31 Bit depth   per component (uint32 BE)
//      32..   For each slice z = 0..<sliceCount:
//                 [uint32 BE: codestream length L]
//                 [L bytes : J2K codestream encoding all C components of slice z]
//
//  Each slice is a regular 2D J2K(/HTJ2K) codestream. Real entropy
//  coding from `J2KCodec`'s pipeline applies — that is what fixes the
//  7× compression-ratio gap diagnosed in M1.
//
//  The container format is private to J2KSwift JP3D — it is wrapped
//  inside the JP3D codestream as the SOD payload of each tile, so
//  the outer envelope (SOC/SIZ/COD/QCD/SOT/EOC) remains intact.

import Foundation
import J2KCore
import J2KCodec

@usableFromInline
struct JP3DSliceStackCodec: Sendable {

    // MARK: - Wire format

    /// Magic bytes 'J3DS' identifying a slice-stack tile payload.
    @usableFromInline
    static let magic: [UInt8] = [0x4A, 0x33, 0x44, 0x53]

    /// Current wire-format version.
    @usableFromInline
    static let version: UInt32 = 1

    @usableFromInline
    static let headerByteCount = 32

    /// Returns true when `data` begins with the J3DS magic.
    @inlinable
    static func hasMagic(_ data: Data) -> Bool {
        guard data.count >= magic.count else { return false }
        return data[data.startIndex..<(data.startIndex + magic.count)]
            .elementsEqual(magic)
    }

    // MARK: - Encode

    /// Encode `tile` into a slice-stack payload.
    ///
    /// Returns a `Data` blob suitable for use as a JP3D tile payload
    /// (i.e. the SOD content). Each Z-slice of the tile becomes one
    /// 2D J2K codestream that includes every component.
    func encode(
        tile: TileVoxels,
        useHTJ2K: Bool,
        lossless: Bool,
        quality: Double
    ) async throws -> Data {

        let encodingConfig = makeEncodingConfig(
            bitDepth: tile.bitDepth,
            useHTJ2K: useHTJ2K,
            lossless: lossless,
            quality: quality
        )
        let encoder = J2KEncoder(encodingConfiguration: encodingConfig)

        var slicePayloads: [Data] = []
        slicePayloads.reserveCapacity(tile.depth)

        for z in 0..<tile.depth {
            let image = makeImage(forSlice: z, in: tile)
            let codestream = try await encoder.encode(image)
            slicePayloads.append(codestream)
        }

        return assemble(
            slicePayloads: slicePayloads,
            tile: tile,
            useHTJ2K: useHTJ2K,
            lossless: lossless
        )
    }

    // MARK: - Decode

    /// Parse a slice-stack payload, decode each slice, and return the
    /// reconstructed voxel buffers (one Float buffer per component, in
    /// volume voxel order — i.e. interior tile coordinates).
    func decode(
        payload: Data,
        expectedTile: ExpectedTile
    ) async throws -> [[Float]] {

        let header = try parseHeader(from: payload)
        guard header.tileWidth == expectedTile.width,
              header.tileHeight == expectedTile.height,
              header.sliceCount == expectedTile.depth else {
            throw J2KError.decodingError(
                "JP3D slice-stack tile dims \(header.tileWidth)x\(header.tileHeight)x\(header.sliceCount) " +
                "do not match expected \(expectedTile.width)x\(expectedTile.height)x\(expectedTile.depth)"
            )
        }
        guard header.componentCount == expectedTile.componentCount else {
            throw J2KError.decodingError(
                "JP3D slice-stack component count \(header.componentCount) " +
                "does not match expected \(expectedTile.componentCount)"
            )
        }

        let voxelsPerComponent = header.tileWidth * header.tileHeight * header.sliceCount
        var componentBuffers = [[Float]](
            repeating: [Float](repeating: 0, count: voxelsPerComponent),
            count: header.componentCount
        )

        let decoder = J2KDecoder()
        var cursor = payload.index(payload.startIndex, offsetBy: Self.headerByteCount)

        for z in 0..<header.sliceCount {
            guard cursor + 4 <= payload.endIndex else {
                throw J2KError.decodingError(
                    "JP3D slice-stack truncated reading slice \(z) length"
                )
            }
            let length = Int(readUInt32BE(payload, at: cursor))
            cursor = cursor.advanced(by: 4)

            guard cursor + length <= payload.endIndex else {
                throw J2KError.decodingError(
                    "JP3D slice-stack truncated reading slice \(z) " +
                    "(need \(length) bytes, have \(payload.distance(from: cursor, to: payload.endIndex)))"
                )
            }
            let codestream = payload.subdata(
                in: cursor..<(cursor.advanced(by: length))
            )
            cursor = cursor.advanced(by: length)

            let image = try await decoder.decode(codestream)
            try copy(
                image: image, slice: z,
                tileWidth: header.tileWidth, tileHeight: header.tileHeight,
                bitDepth: header.bitDepth,
                into: &componentBuffers
            )
        }

        return componentBuffers
    }

    // MARK: - Inputs

    /// The tile's voxel data, ready for slice-stack encoding.
    @usableFromInline
    struct TileVoxels: Sendable {
        let width: Int
        let height: Int
        let depth: Int
        let bitDepth: Int
        let signed: Bool
        /// Per-component flat buffer, voxel order = (z * h + y) * w + x.
        let componentData: [Data]

        var componentCount: Int { componentData.count }
    }

    @usableFromInline
    struct ExpectedTile: Sendable {
        let width: Int
        let height: Int
        let depth: Int
        let componentCount: Int
    }

    // MARK: - Internals: Encode

    private func makeEncodingConfig(
        bitDepth: Int,
        useHTJ2K: Bool,
        lossless: Bool,
        quality: Double
    ) -> J2KEncodingConfiguration {
        // Tuning for medical 16-bit CT/MR slices (the target):
        //   - codeBlockSize 64×64 (default) is already optimal for
        //     512×512 medical slices on this codec.
        //   - useReversibleFilter must be true in lossless mode so the
        //     5/3 wavelet round-trips bit-exact.
        //   - qualityLayers: 1 in lossless mode — extra layers cost
        //     packet-header bytes for no rate-distortion benefit when
        //     every coding pass is included anyway.
        return J2KEncodingConfiguration(
            quality: lossless ? 1.0 : max(0.1, min(1.0, quality)),
            lossless: lossless,
            qualityLayers: lossless ? 1 : 5,
            useHTJ2K: useHTJ2K,
            useReversibleFilter: lossless
        )
    }

    private func makeImage(forSlice z: Int, in tile: TileVoxels) -> J2KImage {
        let bytesPerSample = max(1, (tile.bitDepth + 7) / 8)
        let voxelsPerSlice = tile.width * tile.height
        let sliceByteCount = voxelsPerSlice * bytesPerSample

        var components: [J2KComponent] = []
        components.reserveCapacity(tile.componentCount)

        for compIdx in 0..<tile.componentCount {
            let compBuffer = tile.componentData[compIdx]
            let zStart = z * sliceByteCount
            let zEnd   = zStart + sliceByteCount
            // Defensive — encoder uses tile.componentData built by the
            // J2KEncoder caller in the same module, but a length mismatch
            // is much easier to chase here than inside J2KEncoder.
            let sliceData: Data
            if zEnd <= compBuffer.count {
                sliceData = compBuffer.subdata(in: zStart..<zEnd)
            } else {
                sliceData = Data(count: sliceByteCount)
            }
            components.append(J2KComponent(
                index: compIdx,
                bitDepth: tile.bitDepth,
                signed: tile.signed,
                width: tile.width,
                height: tile.height,
                data: sliceData,
                // serialiseFloatSamples writes uint16 in little-endian
                // — make that explicit so J2KEncoder doesn't have to
                // guess from the sample distribution at full 16-bit
                // depth (where both interpretations fit UInt16).
                sampleByteOrder: tile.bitDepth > 8 ? .littleEndian : nil
            ))
        }

        return J2KImage(
            width: tile.width,
            height: tile.height,
            components: components,
            colorSpace: tile.componentCount >= 3 ? .sRGB : .grayscale
        )
    }

    private func assemble(
        slicePayloads: [Data],
        tile: TileVoxels,
        useHTJ2K: Bool,
        lossless: Bool
    ) -> Data {
        var flags: UInt32 = 0
        if useHTJ2K { flags |= 0x1 }
        if lossless { flags |= 0x2 }

        let totalSlicePayloadBytes = slicePayloads.reduce(0) { $0 + 4 + $1.count }
        var out = Data(capacity: Self.headerByteCount + totalSlicePayloadBytes)

        out.append(contentsOf: Self.magic)
        appendUInt32BE(&out, Self.version)
        appendUInt32BE(&out, flags)
        appendUInt32BE(&out, UInt32(tile.depth))
        appendUInt32BE(&out, UInt32(tile.width))
        appendUInt32BE(&out, UInt32(tile.height))
        appendUInt32BE(&out, UInt32(tile.componentCount))
        appendUInt32BE(&out, UInt32(tile.bitDepth))

        for cs in slicePayloads {
            appendUInt32BE(&out, UInt32(cs.count))
            out.append(cs)
        }
        return out
    }

    // MARK: - Internals: Decode

    private struct StackHeader {
        let version: UInt32
        let flags: UInt32
        let sliceCount: Int
        let tileWidth: Int
        let tileHeight: Int
        let componentCount: Int
        let bitDepth: Int
    }

    private func parseHeader(from data: Data) throws -> StackHeader {
        guard data.count >= Self.headerByteCount else {
            throw J2KError.decodingError(
                "JP3D slice-stack tile too short for header (\(data.count) < \(Self.headerByteCount))"
            )
        }
        guard Self.hasMagic(data) else {
            throw J2KError.decodingError("JP3D slice-stack missing 'J3DS' magic")
        }
        let base = data.startIndex
        let version    = readUInt32BE(data, at: base.advanced(by: 4))
        let flags      = readUInt32BE(data, at: base.advanced(by: 8))
        let sliceCount = Int(readUInt32BE(data, at: base.advanced(by: 12)))
        let tileWidth  = Int(readUInt32BE(data, at: base.advanced(by: 16)))
        let tileHeight = Int(readUInt32BE(data, at: base.advanced(by: 20)))
        let compCount  = Int(readUInt32BE(data, at: base.advanced(by: 24)))
        let bitDepth   = Int(readUInt32BE(data, at: base.advanced(by: 28)))

        guard version == Self.version else {
            throw J2KError.decodingError(
                "JP3D slice-stack version \(version) not supported (expected \(Self.version))"
            )
        }
        guard sliceCount > 0, tileWidth > 0, tileHeight > 0,
              compCount > 0, bitDepth > 0 else {
            throw J2KError.decodingError(
                "JP3D slice-stack header has invalid dimensions"
            )
        }
        return StackHeader(
            version: version, flags: flags,
            sliceCount: sliceCount,
            tileWidth: tileWidth, tileHeight: tileHeight,
            componentCount: compCount, bitDepth: bitDepth
        )
    }

    private func copy(
        image: J2KImage,
        slice z: Int,
        tileWidth: Int, tileHeight: Int,
        bitDepth: Int,
        into componentBuffers: inout [[Float]]
    ) throws {
        guard image.componentCount == componentBuffers.count else {
            throw J2KError.decodingError(
                "JP3D slice-stack: decoded slice has \(image.componentCount) components, " +
                "expected \(componentBuffers.count)"
            )
        }
        let bytesPerSample = max(1, (bitDepth + 7) / 8)
        let voxelsPerSlice = tileWidth * tileHeight
        let sliceOffset = z * voxelsPerSlice

        for (compIdx, comp) in image.components.enumerated() {
            // The decoded image's component must be the right shape; if
            // it isn't (e.g. the J2K codestream was for a different
            // size), bail with a clear error rather than scribble.
            guard comp.width == tileWidth, comp.height == tileHeight else {
                throw J2KError.decodingError(
                    "JP3D slice-stack: decoded slice comp \(compIdx) is " +
                    "\(comp.width)x\(comp.height), expected \(tileWidth)x\(tileHeight)"
                )
            }
            let data = comp.data
            let sampleCount = comp.width * comp.height

            if bytesPerSample == 1 {
                for i in 0..<sampleCount {
                    componentBuffers[compIdx][sliceOffset + i] = Float(data[data.startIndex + i])
                }
            } else {
                // 16-bit medical-imaging path. J2KDecoder writes uint16
                // samples as big-endian (PGM / DICOM Explicit-VR-BE
                // convention — see J2KDecoderPipeline.swift:2689); the
                // outer JP3DDecoder later round-trips these floats back
                // to whatever byte order the caller's J2KVolumeComponent
                // expects, so reading them correctly here is what makes
                // the lossless cycle bit-exact.
                for i in 0..<sampleCount {
                    let hi = UInt16(data[data.startIndex + i * 2])
                    let lo = UInt16(data[data.startIndex + i * 2 + 1])
                    let v = (hi << 8) | lo
                    componentBuffers[compIdx][sliceOffset + i] = Float(v)
                }
            }
        }
    }

    // MARK: - Helpers

    @inline(__always)
    private func appendUInt32BE(_ data: inout Data, _ v: UInt32) {
        var be = v.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    @inline(__always)
    private func readUInt32BE(_ data: Data, at index: Data.Index) -> UInt32 {
        let b0 = UInt32(data[index])
        let b1 = UInt32(data[index.advanced(by: 1)])
        let b2 = UInt32(data[index.advanced(by: 2)])
        let b3 = UInt32(data[index.advanced(by: 3)])
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }
}
