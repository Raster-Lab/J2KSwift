// SPDX-License-Identifier: MIT
//
// TEST-09 evidence for the shared-contract surface.
//
// The bar the contract sets: the shipped path is unchanged, encode-side proofs
// compare codestreams rather than samples, padding cannot reach the output,
// decode writes the caller's allocation exactly, the ownership lifecycle is
// exercised including its failure paths, and the checks are shown to be
// load-bearing.

import Foundation
import Testing
import J2KContract
import J2KCore
import J2KCodec

@Suite("Contract image layer")
struct ContractImageLayerTests {

    /// Deterministic content distinct enough to expose a mis-stride or a
    /// dropped row; an all-zero image would hide both.
    static func sample(_ x: Int, _ y: Int, bits: Int = 16) -> UInt16 {
        let maxValue = UInt32(1 << bits) - 1
        let v = UInt32(truncatingIfNeeded: x &* 7 &+ y &* 131 &+ ((x ^ y) << 3))
        return UInt16(v % (maxValue + 1))
    }

    static func descriptor(width: Int, height: Int, bits: Int = 16,
                           pad: Int = 0, offset: Int = 0) throws -> ImageDescriptor {
        try ImageDescriptor.greyscale16(
            width: width, height: height, meaningfulBits: bits,
            rowBytes: width * 2 + pad, offset: offset)
    }

    static func filledImage(width: Int, height: Int, bits: Int = 16,
                            pad: Int = 0, offset: Int = 0) throws -> Image {
        let d = try descriptor(width: width, height: height, bits: bits, pad: pad, offset: offset)
        return try ImageDestination.allocate(descriptor: d)
            .writeUInt16 { x, y in sample(x, y, bits: bits) }
    }

    /// The ordinary, established API encoding the same samples, for comparison.
    static func ordinaryCodestream(width: Int, height: Int, bits: Int = 16) async throws -> Data {
        var bytes = [UInt8](repeating: 0, count: width * height * 2)
        for y in 0..<height {
            for x in 0..<width {
                let v = sample(x, y, bits: bits)
                let o = (y * width + x) * 2
                bytes[o] = UInt8(truncatingIfNeeded: v)
                bytes[o + 1] = UInt8(truncatingIfNeeded: v >> 8)
            }
        }
        let image = J2KImage(width: width, height: height, components: [
            J2KComponent(index: 0, bitDepth: bits, signed: false,
                         width: width, height: height, data: Data(bytes),
                         sampleByteOrder: .littleEndian)])
        return try await J2KEncoder(configuration: .lossless).encode(image)
    }

    // MARK: - Encode

    @Test(arguments: [0, 6, 64])
    func contractEncodeMatchesTheEstablishedEncoderByteForByte(pad: Int) async throws {
        // Byte identity tests the whole input path at once. Sample comparison
        // would pass even if the layer read the wrong bytes in the right order.
        for (w, h) in [(37, 23), (64, 48), (129, 77)] {
            let image = try Self.filledImage(width: w, height: h, pad: pad)
            let (contract, report) = try await J2KContractCodec().encode(image)
            let ordinary = try await Self.ordinaryCodestream(width: w, height: h)
            #expect(contract == ordinary, "\(w)x\(h) pad=\(pad): codestreams diverge")
            #expect(report.copyEvents.isEmpty)
            #expect(report.pixelAllocationCount == 0)
            #expect(report.fidelity == .exactSamples)
            // MEM-10 (0.6.0): the workspace bound is stated, not implied.
            // Encode owns Int32 sample planes, four bytes per sample.
            #expect(report.peakWorkspaceBytes == w * h * 4)
        }
    }

    @Test func rowPaddingNeverReachesTheCodestream() async throws {
        let (w, h, pad) = (64, 48, 16)
        let d = try Self.descriptor(width: w, height: h, pad: pad)
        let clean = try Self.filledImage(width: w, height: h, pad: pad)
        let storage = try OwnedImageStorage(byteCount: d.requiredByteCount)
        let lease = try storage.reserveWrite()
        try storage.withUnsafeMutableBytes(lease: lease) { bytes in
            for i in 0..<bytes.count { bytes[i] = UInt8(truncatingIfNeeded: 0x5A &+ i) }
            for y in 0..<h {
                for x in 0..<w {
                    let v = Self.sample(x, y)
                    let o = y * (w * 2 + pad) + x * 2
                    bytes[o] = UInt8(truncatingIfNeeded: v)
                    bytes[o + 1] = UInt8(truncatingIfNeeded: v >> 8)
                }
            }
        }
        let poisoned = try Image(descriptor: d, storage: try storage.finishAndSeal(lease: lease))
        #expect(try await J2KContractCodec().encode(clean).0 == (try await J2KContractCodec().encode(poisoned).0),
                "padding bytes changed the codestream")
    }

    @Test func aNonZeroPlaneOffsetIsHonoured() async throws {
        let (w, h) = (48, 31)
        let image = try Self.filledImage(width: w, height: h, pad: 4, offset: 32)
        #expect(try await J2KContractCodec().encode(image).0 == (try await Self.ordinaryCodestream(width: w, height: h)))
    }

    // MARK: - Decode

    @Test(arguments: [0, 6, 64])
    func decodeWritesTheCallerDestinationExactly(pad: Int) async throws {
        for (w, h) in [(37, 23), (64, 48), (129, 77)] {
            let codestream = try await Self.ordinaryCodestream(width: w, height: h)
            let destination = try ImageDestination.allocate(
                descriptor: try Self.descriptor(width: w, height: h, pad: pad))
            let allocationID = destination.storage.allocationID
            let (image, report) = try await J2KContractCodec().decode(codestream, into: destination)

            // MEM-13: identity, exact samples, no intermediate frame.
            #expect(image.storage.allocationID == allocationID)
            #expect(report.pixelAllocationCount == 0)
            #expect(report.copyEvents.isEmpty)
            // Decode owns the inverse wavelet transform's spatial-domain
            // Double plane: eight bytes per sample, four times the final
            // frame. Reported rather than implied, as MEM-10 now requires.
            #expect(report.peakWorkspaceBytes == w * h * 8)
            for y in 0..<h {
                for x in 0..<w {
                    #expect(try image.sampleUInt16(x: x, y: y) == Self.sample(x, y),
                            "\(w)x\(h) pad=\(pad) mismatch at \(x),\(y)")
                }
            }
        }
    }

    @Test func theAllocatingConvenienceAgreesWithTheDestinationPath() async throws {
        let (w, h) = (96, 61)
        let codestream = try await Self.ordinaryCodestream(width: w, height: h)
        let (allocated, _) = try await J2KContractCodec().decode(codestream)
        let destination = try ImageDestination.allocate(
            descriptor: try Self.descriptor(width: w, height: h, pad: 10))
        let (intoCaller, _) = try await J2KContractCodec().decode(codestream, into: destination)
        for y in 0..<h {
            for x in 0..<w {
                #expect(try allocated.sampleUInt16(x: x, y: y)
                        == (try intoCaller.sampleUInt16(x: x, y: y)))
            }
        }
    }

    @Test func roundTripThroughTheContractSurfaceOnly() async throws {
        let (w, h) = (80, 53)
        let source = try Self.filledImage(width: w, height: h, pad: 4)
        let (codestream, _) = try await J2KContractCodec().encode(source)
        let destination = try ImageDestination.allocate(
            descriptor: try Self.descriptor(width: w, height: h, pad: 22))
        // Different strides each side, so a stride cannot be mistaken for width.
        let (decoded, _) = try await J2KContractCodec().decode(codestream, into: destination)
        for y in 0..<h {
            for x in 0..<w {
                #expect(try decoded.sampleUInt16(x: x, y: y) == (try source.sampleUInt16(x: x, y: y)))
            }
        }
    }

    @Test func inspectionDescribesWhatDecodeProduces() async throws {
        let codestream = try await Self.ordinaryCodestream(width: 129, height: 77)
        let described = try J2KContractCodec().inspect(codestream)
        let (decoded, _) = try await J2KContractCodec().decode(codestream)
        #expect(described.width == decoded.descriptor.width)
        #expect(described.height == decoded.descriptor.height)
        #expect(described.meaningfulBits == decoded.descriptor.meaningfulBits)
        #expect(described.storageBits == 16)
        #expect(described.byteOrder == .littleEndian)
    }

    // MARK: - Failure paths and lifecycle

    @Test func mismatchedDestinationsAreRefused() async throws {
        let codestream = try await Self.ordinaryCodestream(width: 64, height: 48)
        let codec = J2KContractCodec()
        await #expect(throws: CodecError.self) {
            try await codec.decode(codestream,
                into: try ImageDestination.allocate(descriptor: try Self.descriptor(width: 32, height: 48)))
        }
        await #expect(throws: CodecError.self) {
            try await codec.decode(codestream,
                into: try ImageDestination.allocate(descriptor: try Self.descriptor(width: 64, height: 24)))
        }
        await #expect(throws: CodecError.self) {
            try await codec.decode(codestream,
                into: try ImageDestination.allocate(descriptor: try Self.descriptor(width: 64, height: 48, bits: 12)))
        }
    }

    @Test func aDestinationGrantsOneWriteOnly() async throws {
        let codestream = try await Self.ordinaryCodestream(width: 32, height: 16)
        let destination = try ImageDestination.allocate(
            descriptor: try Self.descriptor(width: 32, height: 16))
        _ = try await J2KContractCodec().decode(codestream, into: destination)
        // MEM-06: the destination is sealed; a second writer is rejected.
        await #expect(throws: CodecError.self) {
            try await J2KContractCodec().decode(codestream, into: destination)
        }
    }

    @Test func preflightRejectionLeavesTheDestinationReusable() async throws {
        // "Preflight rejection before a write begins does not invalidate a
        // caller's existing destination reservation." A truncated codestream
        // breaks the container box length, so it is refused while parsing,
        // before any sample is written.
        let full = try await Self.ordinaryCodestream(width: 64, height: 48)
        let destination = try ImageDestination.allocate(
            descriptor: try Self.descriptor(width: 64, height: 48))
        await #expect(throws: CodecError.self) {
            try await J2KContractCodec().decode(full.prefix(full.count / 2), into: destination)
        }
        let (image, _) = try await J2KContractCodec().decode(full, into: destination)
        for y in stride(from: 0, to: 48, by: 7) {
            for x in stride(from: 0, to: 64, by: 9) {
                #expect(try image.sampleUInt16(x: x, y: y) == Self.sample(x, y))
            }
        }
    }

    // The other half of the rule — "once a fill/write operation begins,
    // thrown errors or cancellation invalidate it and prevent image
    // publication" — is deliberately not asserted here, because in this codec
    // no malformed input reaches it.
    //
    // Truncation is refused in preflight, and corrupting bytes inside the
    // entropy-coded data at 50%, 75% and 90% of the codestream produced a
    // successful decode every time, with no error raised. That tolerance is a
    // property of this decoder, not of the contract, and it is the same
    // behaviour the successor specification already criticises in the legacy
    // code-block path, which catches decode failures and returns zeros rather
    // than propagating them. Asserting the observed behaviour here would
    // enshrine it, so the gap is recorded instead.
    //
    // No in-write failure is constructible through the public API either: the
    // layout extent this surface computes is the same quantity the descriptor
    // validates against plane capacity, so a destination that passes
    // construction cannot fail the in-write bounds check. That consistency is
    // worth having; it just leaves this branch unexercised for JPEG 2000.

    @Test func layoutsOutsideTheSharedProfileAreRefused() async throws {
        let bigEndian = try ImageDescriptor(
            width: 32, height: 16, storageBits: 16, meaningfulBits: 16,
            byteOrder: .bigEndian, components: [.grey], colour: .greyscale,
            planes: [try PlaneDescriptor(width: 32, height: 16, rowBytes: 64, byteCount: 1024)])
        await #expect(throws: CodecError.self) {
            try await J2KContractCodec().decode(try await Self.ordinaryCodestream(width: 32, height: 16),
                                          into: try ImageDestination.allocate(descriptor: bigEndian))
        }
    }

    @Test func resourceLimitsAreEnforced() async throws {
        let codestream = try await Self.ordinaryCodestream(width: 64, height: 48)
        let tight = try ResourceLimits(maximumCompressedBytes: 16)
        await #expect(throws: CodecError.self) {
            try await J2KContractCodec().decode(codestream, options: DecodeOptions(resourceLimits: tight))
        }
    }

    @Test func capabilitiesReportWhatIsImplemented() {
        // POL-08: planned capability is not reported as present.
        let c = J2KContractCodec.capabilities
        #expect(c.canEncode); #expect(c.canDecode); #expect(c.canInspect)
        #expect(c.compressionModes == [.lossless])
        #expect(c.layouts == ["greyscale16"])
        #expect(c.availableBackends == [.scalarCPU])
    }
}
