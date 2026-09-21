// Shared-storage seam for the contract module.
//
// `package` rather than `public`: J2KContract needs these, nothing outside
// the package does, and the codec modules' public API is unchanged.
//
// The crux here is that this codec's encode and decode are `async`, which the
// other three in the suite are not. MEM-08 forbids a pointer borrow spanning
// an `await`, so the pipeline cannot be handed a buffer. It is handed a
// `@Sendable` closure that opens a scoped borrow instead: the closure crosses
// the suspension, the pointer never does, and the contract module keeps the
// owner and its lease.
//
// The conversion cores below are the ones the Phase 2 spike measured. They
// are used by both the allocating path and the caller-storage path, so
// MEM-10's single final-output path holds by construction.

import Foundation
import J2KCore

#if canImport(Accelerate)
import Accelerate
#endif

/// A caller plane the pipeline may write, with the layout to write it in.
package struct J2KSharedDestination: Sendable {
    package let rowBytes: Int
    /// Distance between consecutive component plane origins. MEM-03 as
    /// revised in 0.6.0 requires this to be stated, never inferred: with
    /// padded rows the two readings differ by one row's padding per plane and
    /// shear the image instead of failing.
    package let planeStrideBytes: Int
    package let byteOrder: J2KComponent.ByteOrder
    /// Synchronous scoped write access to the caller's allocation, supplied
    /// by the contract module from its storage lease.
    package let withBytes: @Sendable ((UnsafeMutableRawBufferPointer) throws -> Void) throws -> Void

    package init(rowBytes: Int, planeStrideBytes: Int, byteOrder: J2KComponent.ByteOrder,
                 withBytes: @escaping @Sendable ((UnsafeMutableRawBufferPointer) throws -> Void) throws -> Void) {
        self.rowBytes = rowBytes
        self.planeStrideBytes = planeStrideBytes
        self.byteOrder = byteOrder
        self.withBytes = withBytes
    }
}

/// A caller plane the pipeline may read, with the layout it is stored in.
package struct J2KSharedSource: Sendable {
    package let rowBytes: Int
    package let planeStrideBytes: Int
    package let byteOrder: J2KSampleByteOrder
    package let withBytes: @Sendable ((UnsafeRawBufferPointer) throws -> Void) throws -> Void

    package init(rowBytes: Int, planeStrideBytes: Int, byteOrder: J2KSampleByteOrder,
                 withBytes: @escaping @Sendable ((UnsafeRawBufferPointer) throws -> Void) throws -> Void) {
        self.rowBytes = rowBytes
        self.planeStrideBytes = planeStrideBytes
        self.byteOrder = byteOrder
        self.withBytes = withBytes
    }
}

/// How the destination plane is laid out for the final-output writer.
///
/// MEM-10 requires the allocating convenience and the caller-destination decode
/// to use the *same* final-output path, so both build one of these and call
/// `j2kWriteFinalSamples`. `flat` reproduces the shipped behaviour exactly:
/// one span covering the whole plane, chunked at 64 Ki samples for vDSP.
struct J2KFinalOutputLayout {
    /// Samples to write in total.
    var sampleCount: Int
    /// Number of destination spans (1 when packed, `height` when padded).
    var spanCount: Int
    /// Samples in each span.
    var spanSamples: Int
    /// Destination byte advance between spans.
    var spanStrideBytes: Int

    /// Packed, no row padding: the whole plane is one span. This is what the
    /// allocating path uses, so its chunking is unchanged by the refactor.
    static func flat(sampleCount: Int) -> J2KFinalOutputLayout {
        J2KFinalOutputLayout(sampleCount: sampleCount, spanCount: 1,
                             spanSamples: sampleCount, spanStrideBytes: 0)
    }

    /// Row-strided: one span per row, so padding between `width * bpp` and
    /// `rowBytes` is skipped rather than written.
    static func strided(width: Int, height: Int, rowBytes: Int, bytesPerPixel: Int) -> J2KFinalOutputLayout {
        // A packed destination is described as flat so the fast path is not
        // lost to a stride that happens to equal the row payload.
        if rowBytes == width * bytesPerPixel {
            return .flat(sampleCount: width * height)
        }
        return J2KFinalOutputLayout(sampleCount: width * height, spanCount: height,
                                    spanSamples: width, spanStrideBytes: rowBytes)
    }
}

/// Convert one component's spatial-domain `[Double]` samples to final integer
/// samples and write them into `dst`.
///
/// This is the whole of the decoder's final-output stage. `reconstructImage`
/// calls it with a freshly allocated `Data`'s buffer; `decodeIntoShared` calls
/// it with the caller's plane. Neither has its own copy of the conversion, so
/// the two cannot drift, and the shared path cannot silently become a copy of
/// a second decoded image.
func j2kWriteFinalSamples(
    from compData: UnsafeBufferPointer<Double>,
    into dst: UnsafeMutableRawBufferPointer,
    layout: J2KFinalOutputLayout,
    bitDepth: Int,
    signed: Bool,
    byteOrder: J2KComponent.ByteOrder,
    lowerBound: Int32,
    upperBound: Int32,
    scratch: inout [Float]
) {
    guard layout.sampleCount > 0,
          let dstBase = dst.baseAddress,
          let srcBase = compData.baseAddress else { return }
    #if canImport(Accelerate)
    precondition(!scratch.isEmpty, "the vDSP path needs a staging buffer")
    #endif
    let ptr = dstBase.assumingMemoryBound(to: UInt8.self)
    let bytesPerPixel = bitDepth <= 8 ? 1 : 2
    let lo = Double(lowerBound), hi = Double(upperBound)

    // Swap only when the requested order differs from the host's. With
    // `.bigEndian` on a little-endian host this is the shipped behaviour; with
    // MEM-03's `.littleEndian` on the same host the pass disappears.
    let needsSwap = (byteOrder == .bigEndian) == j2kHostIsLittleEndian()

    // Read the chunk size once. `forEachRun` runs inside
    // `scratch.withUnsafeMutableBufferPointer` on the Accelerate path, and
    // reading `scratch.count` there would be a second access to a buffer
    // already exclusively borrowed. An empty scratch means no vDSP staging is
    // needed, so runs are not split at all.
    let chunkSize = scratch.isEmpty ? Int.max : scratch.count

    func clampRoundedToInt32(_ value: Double) -> Int32 {
        let rounded = value.rounded()
        if rounded.isNaN { return 0 }
        if rounded >= Double(Int32.max) { return Int32.max }
        if rounded <= Double(Int32.min) { return Int32.min }
        return Int32(rounded)
    }

    /// Visit every (source sample offset, destination byte offset, count) run,
    /// never straddling a destination row.
    func forEachRun(_ body: (Int, Int, Int) -> Void) {
        var srcOffset = 0
        for span in 0..<layout.spanCount {
            let spanByteBase = span * layout.spanStrideBytes
            var x = 0
            while x < layout.spanSamples {
                let n = min(chunkSize, layout.spanSamples - x)
                body(srcOffset + x, spanByteBase + x * bytesPerPixel, n)
                x += n
            }
            srcOffset += layout.spanSamples
        }
    }

#if canImport(Accelerate)
    var floatLo = Float(lo), floatHi = Float(hi)
    scratch.withUnsafeMutableBufferPointer { fBuf in
        let f = fBuf.baseAddress!
        if bitDepth <= 8 && !signed {
            forEachRun { src, dstByte, n in
                let cnt = vDSP_Length(n)
                vDSP_vdpsp(srcBase + src, 1, f, 1, cnt)
                vDSP_vclip(f, 1, &floatLo, &floatHi, f, 1, cnt)
                vDSP_vfixru8(f, 1, ptr + dstByte, 1, cnt)
            }
        } else if bitDepth > 8 && !signed {
            forEachRun { src, dstByte, n in
                let cnt = vDSP_Length(n)
                let u16 = UnsafeMutableRawPointer(ptr + dstByte)
                    .assumingMemoryBound(to: UInt16.self)
                vDSP_vdpsp(srcBase + src, 1, f, 1, cnt)
                vDSP_vclip(f, 1, &floatLo, &floatHi, f, 1, cnt)
                vDSP_vfixru16(f, 1, u16, 1, cnt)
                if needsSwap { for i in 0..<n { u16[i] = u16[i].byteSwapped } }
            }
        } else if bitDepth > 8 && signed {
            forEachRun { src, dstByte, n in
                let cnt = vDSP_Length(n)
                let i16 = UnsafeMutableRawPointer(ptr + dstByte)
                    .assumingMemoryBound(to: Int16.self)
                vDSP_vdpsp(srcBase + src, 1, f, 1, cnt)
                vDSP_vclip(f, 1, &floatLo, &floatHi, f, 1, cnt)
                vDSP_vfixr16(f, 1, i16, 1, cnt)
                if needsSwap { for i in 0..<n { i16[i] = i16[i].byteSwapped } }
            }
        } else {
            forEachRun { src, dstByte, n in
                for i in 0..<n {
                    let rounded = min(upperBound, max(lowerBound, clampRoundedToInt32(srcBase[src + i])))
                    ptr[dstByte + i] = UInt8(bitPattern: Int8(clamping: rounded))
                }
            }
        }
    }
#else
    if bitDepth <= 8 {
        forEachRun { src, dstByte, n in
            for i in 0..<n {
                let rounded = min(upperBound, max(lowerBound, clampRoundedToInt32(srcBase[src + i])))
                ptr[dstByte + i] = signed
                    ? UInt8(bitPattern: Int8(clamping: rounded))
                    : UInt8(clamping: max(0, rounded))
            }
        }
    } else {
        let wantsBigEndian = (byteOrder == .bigEndian)
        forEachRun { src, dstByte, n in
            for i in 0..<n {
                let rounded = min(upperBound, max(lowerBound, clampRoundedToInt32(srcBase[src + i])))
                let v = signed
                    ? UInt16(bitPattern: Int16(clamping: rounded))
                    : UInt16(clamping: max(0, rounded))
                let off = dstByte + i * 2
                ptr[off]     = wantsBigEndian ? UInt8(v >> 8)   : UInt8(v & 0xFF)
                ptr[off + 1] = wantsBigEndian ? UInt8(v & 0xFF) : UInt8(v >> 8)
            }
        }
    }
#endif
}


/// How the source plane is laid out for the input stage.
///
/// The encoder-side twin of `J2KFinalOutputLayout`. `flat` reproduces the
/// shipped behaviour exactly — one run over the whole plane — so the ordinary
/// encode path is unchanged by the refactor.
struct J2KInputLayout {
    var sampleCount: Int
    var spanCount: Int
    var spanSamples: Int
    var spanStrideBytes: Int

    static func flat(sampleCount: Int) -> J2KInputLayout {
        J2KInputLayout(sampleCount: sampleCount, spanCount: 1,
                       spanSamples: sampleCount, spanStrideBytes: 0)
    }

    static func strided(width: Int, height: Int, rowBytes: Int, bytesPerPixel: Int) -> J2KInputLayout {
        if rowBytes == width * bytesPerPixel {
            return .flat(sampleCount: width * height)
        }
        return J2KInputLayout(sampleCount: width * height, spanCount: height,
                              spanSamples: width, spanStrideBytes: rowBytes)
    }
}

/// Widen one component's stored samples into the encoder's `[Int32]` workspace.
///
/// This is the whole of the encoder's input stage. `extractComponentData`
/// calls it with the component's own `Data`; `encodeFromShared` calls it with
/// the caller's plane. Neither has its own copy of the loop, so the two cannot
/// drift and the shared path cannot quietly become a copy of the caller's
/// plane. Row padding beyond `width * bytesPerPixel` is never read, so it
/// cannot reach the codestream.
@inline(__always)
func j2kReadComponentSamples(
    from src: UnsafeRawBufferPointer,
    into dst: UnsafeMutableBufferPointer<Int32>,
    layout: J2KInputLayout,
    bitDepth: Int,
    signed: Bool,
    byteOrder: J2KSampleByteOrder
) {
    guard layout.sampleCount > 0,
          let srcBase = src.baseAddress?.assumingMemoryBound(to: UInt8.self),
          let out = dst.baseAddress else { return }
    let bytesPerPixel = bitDepth <= 8 ? 1 : 2

    /// Visit every (destination sample offset, source byte offset, count) run,
    /// never straddling a source row.
    @inline(__always)
    func forEachRun(_ body: (Int, Int, Int) -> Void) {
        var dstOffset = 0
        for span in 0..<layout.spanCount {
            body(dstOffset, span * layout.spanStrideBytes, layout.spanSamples)
            dstOffset += layout.spanSamples
        }
    }

    if bitDepth <= 8 {
        if signed {
            forEachRun { d, s, n in
                for i in 0..<n { out[d &+ i] = Int32(Int8(bitPattern: srcBase[s &+ i])) }
            }
        } else {
            forEachRun { d, s, n in
                for i in 0..<n { out[d &+ i] = Int32(srcBase[s &+ i]) }
            }
        }
        return
    }

    // v5.38 M7: the (byteOrder × signedness) branches stay hoisted out of the
    // per-pixel loop. Both are constant for a component, and specialising to
    // one of four closed-form bodies is what lets LLVM auto-vectorise the
    // UInt16 widening into NEON Int32 stores. For 12 MP DX this runs 12M
    // iterations per encode, so the shape matters.
    _ = bytesPerPixel
    switch (byteOrder, signed) {
    case (.bigEndian, false):
        forEachRun { d, s, n in
            for i in 0..<n {
                let v = (UInt16(srcBase[s &+ i &* 2]) << 8) | UInt16(srcBase[s &+ i &* 2 &+ 1])
                out[d &+ i] = Int32(v)
            }
        }
    case (.bigEndian, true):
        forEachRun { d, s, n in
            for i in 0..<n {
                let v = (UInt16(srcBase[s &+ i &* 2]) << 8) | UInt16(srcBase[s &+ i &* 2 &+ 1])
                out[d &+ i] = Int32(Int16(bitPattern: v))
            }
        }
    case (.littleEndian, false):
        forEachRun { d, s, n in
            for i in 0..<n {
                let v = UInt16(srcBase[s &+ i &* 2]) | (UInt16(srcBase[s &+ i &* 2 &+ 1]) << 8)
                out[d &+ i] = Int32(v)
            }
        }
    case (.littleEndian, true):
        forEachRun { d, s, n in
            for i in 0..<n {
                let v = UInt16(srcBase[s &+ i &* 2]) | (UInt16(srcBase[s &+ i &* 2 &+ 1]) << 8)
                out[d &+ i] = Int32(Int16(bitPattern: v))
            }
        }
    }
}


// MARK: - Package entry points

package struct J2KSharedInspection: Sendable {
    package let width: Int
    package let height: Int
    package let bitDepth: Int
    package let componentCount: Int
    package let signed: Bool
    package let subsampled: Bool
}

package enum J2KSharedPlaneError: Error, Sendable {
    case notSupported(String)
    case malformed(String)
}

extension J2KDecoder {
    /// Describe the output layout, without decoding.
    package func sharedInspect(_ data: Data) throws -> J2KSharedInspection {
        var pipeline = DecoderPipeline()
        pipeline.metalSession = nil
        let (metadata, _) = try pipeline.parseCodestream(data)
        guard let component = metadata.components.first else {
            throw J2KSharedPlaneError.malformed("codestream declares no components")
        }
        return J2KSharedInspection(
            width: metadata.width, height: metadata.height,
            bitDepth: component.bitDepth, componentCount: metadata.components.count,
            signed: component.signed,
            subsampled: component.subsamplingX != 1 || component.subsamplingY != 1)
    }

    /// Decode writing final samples into the caller's storage.
    ///
    /// `destination` carries scoped write access rather than a pointer: this
    /// call suspends, and MEM-08 forbids a borrow spanning an `await`. The
    /// closure is invoked synchronously inside the final-output stage.
    package func decodeIntoShared(
        _ data: Data, destination: J2KSharedDestination
    ) async throws {
        var pipeline = DecoderPipeline()
        pipeline.metalSession = J2KMetalSession.processShared
        // Inspect before committing, so an unsupported codestream fails
        // without the caller's destination being touched.
        let parsed = try pipeline.parseCodestream(data)
        pipeline.sharedDestination = destination
        // The inspection above already parsed; hand the result on so the
        // decode does not repeat it.
        pipeline.preparsedCodestream = parsed
        let image = try await pipeline.decode(data)
        // Runtime check, not a comment: no second final image was produced.
        guard image.components.allSatisfy({ $0.data.isEmpty }) else {
            throw J2KSharedPlaneError.malformed("shared decode also materialised component data")
        }
    }

    /// Workspace this decode owns, for MEM-10's stated bound: the inverse
    /// wavelet transform's spatial-domain plane, eight bytes per sample per
    /// component. Frame-proportional and larger than the final frame, which
    /// is why the contract requires it to be reported rather than implied.
    package static func sharedWorkspaceBytes(width: Int, height: Int, components: Int) -> Int {
        width * height * components * MemoryLayout<Double>.size
    }
}

extension J2KEncoder {
    /// Encode reading samples out of the caller's storage.
    package func encodeFromShared(
        source: J2KSharedSource, width: Int, height: Int,
        bitDepth: Int, componentCount: Int
    ) async throws -> Data {
        let image = J2KImage(
            width: width, height: height,
            components: (0..<componentCount).map { index in
                J2KComponent(index: index, bitDepth: bitDepth, signed: false,
                             width: width, height: height, data: Data(),
                             sampleByteOrder: bitDepth > 8 ? .littleEndian : nil)
            })
        var pipeline = EncoderPipeline(config: encodingConfiguration)
        pipeline.sharedSource = source
        return try await pipeline.encode(image)
    }

    /// Workspace this encode owns: the Int32 sample planes, four bytes per
    /// sample per component.
    package static func sharedWorkspaceBytes(width: Int, height: Int, components: Int) -> Int {
        width * height * components * MemoryLayout<Int32>.size
    }
}
