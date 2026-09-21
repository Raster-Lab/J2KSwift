// SPDX-License-Identifier: MIT
//
// The shared-contract codec surface for JPEG 2000.
//
// This module exists separately from the codec modules because `Image`,
// `ByteOrder` and `DecoderConfiguration` are already taken there. POL-03
// anticipates it: the contract "defines a specification, not a runtime
// module", and "identically named types from different modules are distinct
// Swift types".
//
// This codec is the one in the suite whose encode and decode are `async`, so
// it is the one that forced MEM-06's owner rule. The entry points below hand
// the codec a scoped-access closure built from the caller's storage lease,
// never a pointer: the closure crosses the suspension, the pointer does not.
//
// Scope is MEM-03's initial shared layout: one plane, one component, unsigned
// 16-bit, little-endian, even `rowBytes >= width * 2`, no subsampling,
// lossless.

import Foundation
import J2KCore
import J2KCodec

public struct J2KContractCodec: Sendable {
    public init(configuration: J2KConfiguration = .lossless) {
        self.configuration = configuration
    }
    private let configuration: J2KConfiguration

    /// What this surface can actually do, as opposed to what the contract
    /// describes. POL-08: planned capability is not reported as present.
    public static var capabilities: CodecCapabilities {
        CodecCapabilities(
            formats: ["JPEG 2000"],
            compressionModes: [.lossless],
            sampleTypes: [.unsignedInteger],
            meaningfulPrecision: 9...16,
            layouts: ["greyscale16"],
            availableBackends: [.scalarCPU],
            canInspect: true, canEncode: true, canDecode: true)
    }

    // MARK: - Inspection

    public func inspect(_ data: Data, limits: ResourceLimits = .default) throws -> ImageDescriptor {
        let info = try Self.inspection(data, limits: limits)
        return try ImageDescriptor.greyscale16(
            width: info.width, height: info.height,
            meaningfulBits: info.bitDepth, limits: limits)
    }

    // MARK: - Encode

    public func encode(_ image: Image,
                       configuration encoderConfiguration: EncoderConfiguration = .default,
                       options: EncodeOptions = EncodeOptions()) async throws -> (Data, OperationReport) {
        let started = Date()
        guard encoderConfiguration.mode == .lossless else {
            throw CodecError(.unsupportedFeature, "This surface encodes the lossless mode only.")
        }
        let layout = try SharedLayout(descriptor: image.descriptor, policy: options.copyPolicy)
        try image.descriptor.validate(limits: options.resourceLimits)

        // The storage owner is captured, not a pointer. It is `Sendable` and
        // retains the allocation; the borrow happens inside the closure, on
        // the codec's own thread, with no suspension in between (MEM-08).
        let storage = image.storage
        let source = J2KSharedSource(
            rowBytes: layout.rowBytes, planeStrideBytes: layout.planeStride,
            byteOrder: .littleEndian,
            withBytes: { body in
                try storage.withUnsafeBytes { raw in
                    try layout.checkCapacity(raw.count)
                    try body(UnsafeRawBufferPointer(
                        rebasing: raw[layout.offset..<(layout.offset + layout.extent)]))
                }
            })

        let data: Data
        do {
            data = try await J2KEncoder(configuration: configuration).encodeFromShared(
                source: source, width: layout.width, height: layout.height,
                bitDepth: layout.meaningfulBits, componentCount: 1)
        } catch let error as J2KSharedPlaneError {
            throw Self.mapped(error)
        } catch let error as J2KError {
            throw CodecError(.internalFailure, "JPEG 2000 encode failed: \(error)")
        }

        let report = OperationReport(
            backend: .scalarCPU, fidelity: .exactSamples,
            copyEvents: [], pixelAllocationCount: 0, peakPixelBytes: 0,
            peakWorkspaceBytes: J2KEncoder.sharedWorkspaceBytes(
                width: layout.width, height: layout.height, components: 1),
            elapsedSeconds: Date().timeIntervalSince(started))
        return (data, report)
    }

    // MARK: - Decode

    @discardableResult
    public func decode(_ data: Data, into destination: ImageDestination,
                       configuration decoderConfiguration: DecoderConfiguration = DecoderConfiguration(),
                       options: DecodeOptions = DecodeOptions()) async throws -> (Image, OperationReport) {
        let started = Date()
        _ = decoderConfiguration
        let layout = try SharedLayout(descriptor: destination.descriptor, policy: options.copyPolicy)
        let info = try Self.inspection(data, limits: options.resourceLimits)
        guard info.width == layout.width, info.height == layout.height else {
            throw CodecError(.incompatibleImageLayout,
                "Codestream is \(info.width)x\(info.height); destination is \(layout.width)x\(layout.height).")
        }
        guard info.bitDepth == layout.meaningfulBits else {
            throw CodecError(.incompatibleImageLayout,
                "Codestream is \(info.bitDepth)-bit; destination declares \(layout.meaningfulBits).")
        }

        // `writeAsync` rather than `write`: the codec suspends, so it is given
        // the owner and its lease and borrows synchronously at its final
        // output stage. Lifecycle is unchanged — one use, sealed on success,
        // invalidated on any throw so nothing partial is published.
        let image = try await destination.writeAsync { storage, lease in
            let shared = J2KSharedDestination(
                rowBytes: layout.rowBytes, planeStrideBytes: layout.planeStride,
                // MEM-12: this codec's native output order is big-endian, and
                // the shared layout is little-endian, so it converts here.
                // Folded into the write it costs nothing and removes the
                // separate byte-swap pass the allocating path runs.
                byteOrder: .littleEndian,
                withBytes: { body in
                    try storage.withUnsafeMutableBytes(lease: lease) { raw in
                        try layout.checkCapacity(raw.count)
                        try body(UnsafeMutableRawBufferPointer(
                            rebasing: raw[layout.offset..<(layout.offset + layout.extent)]))
                    }
                })
            do {
                try await J2KDecoder().decodeIntoShared(data, destination: shared)
            } catch let error as J2KSharedPlaneError {
                throw Self.mapped(error)
            } catch let error as J2KError {
                throw CodecError(.malformedInput, "JPEG 2000 decode failed: \(error)")
            }
        }

        let report = OperationReport(
            backend: .scalarCPU, fidelity: .exactSamples, copyEvents: [],
            pixelAllocationCount: 0, peakPixelBytes: 0,
            // Reported, not waved through: this is four times the final frame.
            peakWorkspaceBytes: J2KDecoder.sharedWorkspaceBytes(
                width: layout.width, height: layout.height, components: 1),
            elapsedSeconds: Date().timeIntervalSince(started))
        return (image, report)
    }

    /// Allocating convenience. MEM-10 requires this and the caller-destination
    /// decode to use the same final-output path, so it allocates a destination
    /// and calls the method above rather than having a path of its own.
    public func decode(_ data: Data,
                       configuration decoderConfiguration: DecoderConfiguration = DecoderConfiguration(),
                       options: DecodeOptions = DecodeOptions()) async throws -> (Image, OperationReport) {
        let descriptor = try inspect(data, limits: options.resourceLimits)
        let destination = try ImageDestination.allocate(
            descriptor: descriptor, limits: options.resourceLimits)
        return try await decode(data, into: destination,
                                configuration: decoderConfiguration, options: options)
    }

    // MARK: - Helpers

    private static func inspection(_ data: Data, limits: ResourceLimits) throws -> J2KSharedInspection {
        guard data.count <= limits.maximumCompressedBytes else {
            throw CodecError(.resourceLimitExceeded, "Compressed input exceeds the operation budget.")
        }
        let info: J2KSharedInspection
        do {
            info = try J2KDecoder().sharedInspect(data)
        } catch let error as J2KSharedPlaneError {
            throw mapped(error)
        } catch {
            throw CodecError(.malformedInput, "JPEG 2000 inspection failed: \(error)")
        }
        guard info.componentCount == 1 else {
            throw CodecError(.unsupportedFeature,
                "This surface handles one component; codestream has \(info.componentCount).")
        }
        guard !info.signed else {
            throw CodecError(.unsupportedFeature, "The shared layout is unsigned.")
        }
        guard !info.subsampled else {
            throw CodecError(.unsupportedFeature, "The shared layout forbids subsampling.")
        }
        guard info.bitDepth > 8, info.bitDepth <= 16 else {
            throw CodecError(.unsupportedFeature,
                "The shared layout is 16-bit storage; codestream is \(info.bitDepth)-bit.")
        }
        return info
    }

    private static func mapped(_ error: J2KSharedPlaneError) -> CodecError {
        switch error {
        case .notSupported(let message): CodecError(.unsupportedFeature, message)
        case .malformed(let message): CodecError(.malformedInput, message)
        }
    }
}

// MARK: - Shared layout

/// The MEM-03 profile read off a descriptor, with MEM-04's checked arithmetic
/// resolved once so neither codec direction repeats it.
struct SharedLayout: Sendable {
    let width: Int, height: Int, meaningfulBits: Int
    let offset: Int, rowBytes: Int, planeStride: Int, extent: Int, sampleCount: Int

    init(descriptor: ImageDescriptor, policy: CopyPolicy) throws {
        guard descriptor.planes.count == 1, descriptor.components.count == 1,
              descriptor.components.first == .grey, descriptor.colour == .greyscale,
              descriptor.alpha == .absent else {
            throw CodecError(.incompatibleImageLayout,
                "This surface requires the single-plane greyscale shared layout.")
        }
        guard descriptor.sampleType == .unsignedInteger, descriptor.storageBits == 16 else {
            throw CodecError(.incompatibleImageLayout, "The shared layout is unsigned 16-bit storage.")
        }
        guard descriptor.byteOrder == .littleEndian else {
            throw CodecError(.incompatibleImageLayout,
                "The shared layout is little-endian; this descriptor is big-endian.")
        }
        let plane = descriptor.planes[0]
        guard plane.pixelStride == 2, plane.sampleStride == 2 else {
            throw CodecError(.incompatibleImageLayout,
                "The shared layout is a two-byte sample and pixel stride.")
        }
        guard plane.rowBytes % 2 == 0, plane.rowBytes >= descriptor.width * 2 else {
            throw CodecError(.incompatibleImageLayout, "rowBytes must be even and at least width * 2.")
        }
        guard plane.offset % 2 == 0 else {
            throw CodecError(.incompatibleImageLayout,
                "Plane offset must be two-byte aligned for 16-bit samples.")
        }
        _ = policy

        width = descriptor.width
        height = descriptor.height
        meaningfulBits = descriptor.meaningfulBits
        offset = plane.offset
        rowBytes = plane.rowBytes
        extent = try checkedAdd(checkedMultiply(descriptor.height - 1, plane.rowBytes),
                                checkedMultiply(descriptor.width, 2))
        // One component today, so the plane stride is the plane's own extent.
        // MEM-03 requires it stated rather than inferred (contract 0.6.0).
        planeStride = extent
        sampleCount = try checkedMultiply(descriptor.width, descriptor.height)
    }

    /// MEM-04: the last byte touched, checked against the retained allocation.
    func checkCapacity(_ byteCount: Int) throws {
        let needed = try checkedAdd(offset, extent)
        guard byteCount >= needed else {
            throw CodecError(.storageUnavailable,
                "Storage holds \(byteCount) bytes; the layout needs \(needed).")
        }
    }
}
