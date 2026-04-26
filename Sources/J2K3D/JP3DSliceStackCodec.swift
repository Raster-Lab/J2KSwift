//
//  JP3DSliceStackCodec.swift
//  J2KSwift
//
//  Slice-stack tile-payload codec for JP3D. A volumetric tile is
//  encoded as a sequence of fully-J2K-compliant 2D codestreams (one
//  per Z-slice), with an optional per-slice Z-delta predictor that
//  closes the inter-slice DWT gap vs OpenJPEG's 3D-EBCOT on highly
//  correlated volumes (seismic, hyperspectral, thin-slice CT).
//
//  Wire format
//  -----------
//      Bytes  Field
//      0..3   Magic  'J3DS' (0x4A 0x33 0x44 0x53)
//      4..7   Version (uint32 BE)        — currently 2
//      8..11  Flags   (uint32 BE)        — bit 0=HTJ2K, bit 1=lossless,
//                                          bit 2=Z-delta enabled (v2+)
//      12..15 Slice count (uint32 BE)
//      16..19 Tile width  in voxels (uint32 BE)
//      20..23 Tile height in voxels (uint32 BE)
//      24..27 Component count (uint32 BE)
//      28..31 Bit depth   per component (uint32 BE)
//      32..   For each slice z = 0..<sliceCount:
//                 v1: [uint32 BE: codestream length L][L bytes: codestream]
//                 v2: [uint8: slice_flags]
//                       bit 0 = is_residual — codestream encodes
//                       (slice_z - slice_{z-1}) as a SIGNED component
//                       at the same bit-depth (only when every
//                       residual fits in [-2^(B-1), 2^(B-1)-1]; else
//                       the encoder falls back to raw for this slice
//                       so lossless round-trip is unconditional).
//                     [uint32 BE: codestream length L]
//                     [L bytes: codestream]
//
//  The Z-delta path is opportunistic: it engages on slices where the
//  signed residual range is representable at the input bit-depth and
//  silently falls back per-slice when it isn't. The container is
//  always fully reversible.
//
//  This codec lives inside the JP3D outer codestream as the SOD
//  payload of each tile — the outer envelope (SOC/SIZ/COD/QCD/SOT/EOC)
//  remains a standards-shaped JP3D wrapper.

import Foundation
import J2KCore
import J2KCodec

@usableFromInline
struct JP3DSliceStackCodec: Sendable {

    // MARK: - Wire format

    /// Magic bytes 'J3DS' identifying a slice-stack tile payload.
    @usableFromInline
    static let magic: [UInt8] = [0x4A, 0x33, 0x44, 0x53]

    /// Current wire-format version. v2 adds the per-slice flag byte
    /// that signals Z-delta residual coding.
    @usableFromInline
    static let version: UInt32 = 2

    @usableFromInline
    static let headerByteCount = 32

    /// Header `flags` bits.
    private static let flagHTJ2K: UInt32   = 0x1
    private static let flagLossless: UInt32 = 0x2
    private static let flagZDelta: UInt32   = 0x4

    /// Per-slice `slice_flags` bits (v2 wire format).
    private static let sliceFlagIsResidual: UInt8 = 0x1

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
    /// Each Z-slice becomes one 2D J2K codestream. When the
    /// `zDeltaMode` policy permits, slices whose residual against
    /// the previous slice both fits the bit-depth signed range AND
    /// shrinks the codestream are emitted as residuals instead of
    /// raw samples — closing the inter-slice DWT gap vs OpenJPEG
    /// 3D-EBCOT on highly correlated volumes. Lossless round-trip
    /// is unconditional via per-slice opportunism.
    func encode(
        tile: TileVoxels,
        useHTJ2K: Bool,
        lossless: Bool,
        quality: Double,
        zDeltaMode: JP3DZDeltaMode = .auto
    ) async throws -> Data {

        // Layer 1: respect the policy.
        // Layer 2 (in `.auto` only): skip Z-delta on tiles whose
        // slices are too small for the per-slice probe overhead
        // (~0.5–1 ms / slice) to be amortised against a baseline
        // encode that's just a few ms / slice. Empirically the 6
        // small 12-bit MR rows (mr/study_003 at 176×256, mr/study_005
        // at 192×192) regress encode speed below the 1.5× gate
        // when Z-delta engages — the absolute byte savings are too
        // small to outweigh the probe cost. The 50 000-voxel-per-
        // slice threshold sits between mr/study_003 (45 056) and
        // the synthetic seismic / hyperspectral cases (65 536) that
        // the M4 fix targets, so default `.auto` keeps every M4 win
        // and recovers every M4 small-MR speed-gate miss.
        let zDeltaAllowed: Bool
        switch zDeltaMode {
        case .never:
            zDeltaAllowed = false
        case .always:
            zDeltaAllowed = true
        case .auto:
            let sliceVoxels = tile.width * tile.height
            zDeltaAllowed = sliceVoxels >= 50_000
        }

        // Lightweight probe across 4 slice-pairs sampled through the
        // volume's Z range. Probes do not allocate residual buffers
        // — they stream bytes, count overflow, and accumulate L1
        // sums in one pass, so even committing the tile to raw-only
        // adds only ~1 ms total.
        let probedZDelta: Bool = {
            guard zDeltaAllowed, lossless, tile.depth > 1 else { return false }
            let probeCount = min(4, tile.depth - 1)
            for i in 0..<probeCount {
                let cur = max(1, (i + 1) * (tile.depth - 1) / probeCount)
                if !probeResidualLooksGood(
                    currentZ: cur, previousZ: cur - 1, in: tile) {
                    return false
                }
            }
            return true
        }()

        let unsignedConfig = makeEncodingConfig(
            useHTJ2K: useHTJ2K, lossless: lossless, quality: quality)
        let unsignedEncoder = J2KEncoder(encodingConfiguration: unsignedConfig)

        // The signed encoder is identical except its J2KComponents are
        // built with `signed: true` — the bit-depth and reversibility
        // settings stay the same so the codestream is bit-exactly
        // round-trippable through `J2KDecoder`.
        let signedEncoder = unsignedEncoder

        var slicePayloads: [(flags: UInt8, data: Data)] = []
        slicePayloads.reserveCapacity(tile.depth)

        // Z-delta works against the previous slice's BYTES, not an
        // Int32 cache — `computeResidualCandidate` reads both slices'
        // raw byte buffers inline. This keeps the slice path
        // overhead-free on natural medical content (which usually
        // can't benefit from Z-delta) so the 1.5× encode-speed gate
        // holds even on small 192×192 / 256×256 volumes.

        // Empirical savings gate (M6): after the first try-both pair,
        // measure the *actual* compressed-size delta and commit the
        // tile to one of three modes for slices 2..N:
        //
        //   savings ≥ signedOnlyThreshold (≥ 20 %)
        //     → tileSignedOnlyActive: skip the raw encode entirely,
        //       just emit the signed residual codestream. This is the
        //       M7 fix — on tiles where Z-delta is a clear win
        //       (seismic / hyperspectral / strongly-correlated CT),
        //       skipping ~3 ms/slice of redundant raw encoding closes
        //       the lone hyperspectral 1.48× speed-gate miss from M6.
        //
        //   firstSliceSavingsThreshold (≥ 3 %) ≤ savings < 20 %
        //     → keep tileTryBothActive: per-slice opportunism with
        //       try-both. Used when slice-by-slice gain is real but
        //       modest enough that occasional slices may lose to raw.
        //
        //   savings < firstSliceSavingsThreshold (< 3 %)
        //     → commit tile to raw-only: skip residual allocation
        //       AND second encode for slices 2..N. Used for tiles
        //       where probe accepted but actual J2K savings are too
        //       marginal to absorb the 2× encode cost (the M6 fix
        //       for thin-slice CT σ=20/80).
        let firstSliceSavingsThreshold: Double = 0.03
        let signedOnlyThreshold: Double = 0.20
        var tileTryBothActive = probedZDelta
        var tileSignedOnlyActive = false

        for z in 0..<tile.depth {
            // Fast path: tile committed to signed-only after seeing
            // huge savings on slice 1. Encode just the residual,
            // falling back to raw only when the bit-depth signed
            // range overflows on this particular slice.
            if tileSignedOnlyActive && z > 0 {
                if let candidate = computeResidualCandidate(
                    currentZ: z, previousZ: z - 1, in: tile) {
                    let signedImage = makeSignedImage(
                        from: candidate.perComponent, in: tile)
                    let signedCS = try await signedEncoder.encode(signedImage)
                    slicePayloads.append((Self.sliceFlagIsResidual, signedCS))
                    continue
                }
                // Residual overflowed — must fall through to raw for
                // this slice. The next slice still tries the residual
                // path; tileSignedOnlyActive is preserved.
            }

            // Per-slice gating when try-both is active:
            //   1) Allocation-free probe (`probeResidualLooksGood`)
            //      keeps natural-medical slices that won't benefit
            //      out of the heavyweight path.
            //   2) Only when tier 1 passes does
            //      `computeResidualCandidate` allocate the residual
            //      buffer — skipping tier 1 would burn ~1.5 ms per
            //      slice on natural MR even when residual is rejected.
            var candidate: ResidualCandidate? = nil
            if tileTryBothActive && z > 0
               && probeResidualLooksGood(currentZ: z, previousZ: z - 1, in: tile) {
                candidate = computeResidualCandidate(
                    currentZ: z, previousZ: z - 1, in: tile)
            }

            let rawImage = makeUnsignedImage(forSlice: z, in: tile)
            let rawCS = try await unsignedEncoder.encode(rawImage)

            var bestFlags: UInt8 = 0
            var bestCS = rawCS
            var measuredSavings: Double = 0.0

            if let candidate {
                let signedImage = makeSignedImage(from: candidate.perComponent, in: tile)
                let signedCS = try await signedEncoder.encode(signedImage)
                if signedCS.count < bestCS.count {
                    measuredSavings = Double(rawCS.count - signedCS.count) / Double(rawCS.count)
                    bestCS = signedCS
                    bestFlags |= Self.sliceFlagIsResidual
                }
            }

            slicePayloads.append((bestFlags, bestCS))

            // After the first slice that actually attempted try-both,
            // commit a tile-wide decision based on the empirical
            // savings (see thresholds above).
            if tileTryBothActive && z == 1 {
                if measuredSavings >= signedOnlyThreshold {
                    tileSignedOnlyActive = true
                } else if measuredSavings < firstSliceSavingsThreshold {
                    tileTryBothActive = false
                }
            }
        }

        return assemble(
            slicePayloads: slicePayloads,
            tile: tile,
            useHTJ2K: useHTJ2K,
            lossless: lossless,
            useZDelta: probedZDelta
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
        let voxelsPerSlice = header.tileWidth * header.tileHeight
        var componentBuffers = [[Float]](
            repeating: [Float](repeating: 0, count: voxelsPerComponent),
            count: header.componentCount
        )

        let decoder = J2KDecoder()
        var cursor = payload.index(payload.startIndex, offsetBy: Self.headerByteCount)

        // v2 only — v1 codestreams predate this branch and aren't
        // produced anywhere now.
        guard header.version == 2 else {
            throw J2KError.decodingError(
                "JP3D slice-stack version \(header.version) not supported (need v2)"
            )
        }

        // Holds the previous reconstructed slice, per component, as
        // Int32 — used to add the residual when `is_residual` is set.
        var prevSliceInt: [[Int32]]? = nil

        for z in 0..<header.sliceCount {
            guard cursor + 5 <= payload.endIndex else {
                throw J2KError.decodingError(
                    "JP3D slice-stack truncated reading slice \(z) header"
                )
            }
            let sliceFlags = payload[cursor]
            cursor = cursor.advanced(by: 1)
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
            let isResidual = (sliceFlags & Self.sliceFlagIsResidual) != 0
            let decodedInt = try readImageAsInt32(
                image, tileWidth: header.tileWidth, tileHeight: header.tileHeight,
                bitDepth: header.bitDepth, signed: isResidual
            )

            let sliceInt: [[Int32]]
            if isResidual {
                guard let prev = prevSliceInt,
                      prev.count == decodedInt.count,
                      prev[0].count == voxelsPerSlice else {
                    throw J2KError.decodingError(
                        "JP3D slice-stack: slice \(z) marked residual but no prior reconstructed slice"
                    )
                }
                var combined: [[Int32]] = []
                combined.reserveCapacity(decodedInt.count)
                for c in 0..<decodedInt.count {
                    var sl = [Int32](repeating: 0, count: voxelsPerSlice)
                    for i in 0..<voxelsPerSlice {
                        sl[i] = prev[c][i] + decodedInt[c][i]
                    }
                    combined.append(sl)
                }
                sliceInt = combined
            } else {
                sliceInt = decodedInt
            }

            // Write the reconstructed slice into the per-component
            // Float buffers (the outer JP3DDecoder takes Floats).
            for c in 0..<sliceInt.count {
                let dstOffset = z * voxelsPerSlice
                let src = sliceInt[c]
                for i in 0..<voxelsPerSlice {
                    componentBuffers[c][dstOffset + i] = Float(src[i])
                }
            }
            prevSliceInt = sliceInt
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

    /// Result of a candidate-residual evaluation. `nil` means the
    /// residual either overflows the bit-depth signed range or the
    /// cheap L1-norm pre-check predicts it won't compress better
    /// than raw — in both cases the encoder should skip the second
    /// encode and just ship the raw slice.
    private struct ResidualCandidate {
        let perComponent: [[Int32]]
    }

    /// Allocation-free probe: streams two slices' bytes, returns
    /// `true` only when EVERY voxel diff fits in the signed bit-depth
    /// range AND the L1 ratio of residuals to DC-shifted current is
    /// below `residualL1Threshold`. Used by the tile-level gate to
    /// decide whether to engage Z-delta on this tile WITHOUT paying
    /// for residual-buffer allocations on every probe.
    private func probeResidualLooksGood(
        currentZ: Int, previousZ: Int, in tile: TileVoxels
    ) -> Bool {
        let bitDepth = tile.bitDepth
        let bytesPerSample = max(1, (bitDepth + 7) / 8)
        let voxelsPerSlice = tile.width * tile.height
        let sliceByteCount = voxelsPerSlice * bytesPerSample
        let signedMin = -(Int32(1) << (bitDepth - 1))
        let signedMax = (Int32(1) << (bitDepth - 1)) - 1
        let dcMidpoint = Int32(1) << (bitDepth - 1)

        var residualL1: Int64 = 0
        var sliceL1: Int64 = 0

        for compIdx in 0..<tile.componentCount {
            let buf = tile.componentData[compIdx]
            let curStart = currentZ  * sliceByteCount
            let prvStart = previousZ * sliceByteCount
            guard curStart + sliceByteCount <= buf.count,
                  prvStart + sliceByteCount <= buf.count else { return false }

            let overflowed: Bool = buf.withUnsafeBytes { rawBuf -> Bool in
                guard let base = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return true
                }
                if bytesPerSample == 1 {
                    for i in 0..<voxelsPerSlice {
                        let cur = Int32(base[curStart + i])
                        let prv = Int32(base[prvStart + i])
                        let d = cur - prv
                        if d < signedMin || d > signedMax { return true }
                        residualL1 += Int64(d.magnitude)
                        sliceL1   += Int64((cur &- dcMidpoint).magnitude)
                    }
                } else {
                    for i in 0..<voxelsPerSlice {
                        let curLo = UInt16(base[curStart + i * 2])
                        let curHi = UInt16(base[curStart + i * 2 + 1])
                        let prvLo = UInt16(base[prvStart + i * 2])
                        let prvHi = UInt16(base[prvStart + i * 2 + 1])
                        let cur = Int32((curHi << 8) | curLo)
                        let prv = Int32((prvHi << 8) | prvLo)
                        let d = cur - prv
                        if d < signedMin || d > signedMax { return true }
                        residualL1 += Int64(d.magnitude)
                        sliceL1   += Int64((cur &- dcMidpoint).magnitude)
                    }
                }
                return false
            }
            if overflowed { return false }
        }

        // Probe is intentionally TIGHTER (0.20) than the slow path's
        // 0.55: it gates whether to even attempt residual encoding,
        // and over-engaging on natural medical content (which often
        // has L1 ratios in the 0.03–0.50 band but doesn't yield
        // matching codestream savings) burns 50 ms/slice for no
        // material ratio improvement. The slow path's 0.55 then
        // serves as a final per-slice safety check.
        // 0.20 is the empirical sweet spot for the lightweight probe:
        //   - Engages on synthetic seismic/hyperspectral and thin-
        //     slice CT (L1 ratios 0.001–0.10) — closes the user-
        //     reported failures.
        //   - Disengages on real medical CT/MR/XA where intra-volume
        //     variability lifts at least one of the 4 probe positions
        //     above 0.20, sparing the per-slice try-both cost.
        // This is a *speed/ratio tradeoff*: when Z-delta engages, the
        // tile pays roughly 2× encode time in exchange for material
        // ratio improvement (up to 4× on perfectly-correlated Z).
        let probeThreshold: Double = 0.20
        return Double(residualL1) < probeThreshold * Double(sliceL1)
    }

    /// Reads slices `currentZ` and `previousZ` directly from the
    /// tile's component byte buffers, computes per-voxel differences
    /// inline, and returns a `ResidualCandidate` only when:
    ///   1) every residual fits in the signed range of `tile.bitDepth`, AND
    ///   2) the L1-norm of residuals is at least 30 % below the L1-norm
    ///      of the DC-shifted current slice — i.e. the residual is
    ///      meaningfully more compressible than the raw slice itself.
    ///
    /// The inline byte-level path (no separate Int32 cache for both
    /// slices) is what keeps natural-image content above the 1.5×
    /// encode-speed gate on small (≤ 256-wide) volumes.
    private func computeResidualCandidate(
        currentZ: Int, previousZ: Int, in tile: TileVoxels
    ) -> ResidualCandidate? {
        let bitDepth = tile.bitDepth
        let bytesPerSample = max(1, (bitDepth + 7) / 8)
        let voxelsPerSlice = tile.width * tile.height
        let sliceByteCount = voxelsPerSlice * bytesPerSample

        let signedMin = -(Int32(1) << (bitDepth - 1))
        let signedMax = (Int32(1) << (bitDepth - 1)) - 1
        let dcMidpoint = Int32(1) << (bitDepth - 1)

        var perComponent: [[Int32]] = []
        perComponent.reserveCapacity(tile.componentCount)
        var residualL1: Int64 = 0
        var sliceL1: Int64 = 0

        for compIdx in 0..<tile.componentCount {
            let buf = tile.componentData[compIdx]
            let curStart = currentZ  * sliceByteCount
            let prvStart = previousZ * sliceByteCount
            guard curStart + sliceByteCount <= buf.count,
                  prvStart + sliceByteCount <= buf.count else {
                return nil
            }
            var diff = [Int32](repeating: 0, count: voxelsPerSlice)
            let overflowed: Bool = buf.withUnsafeBytes { rawBuf -> Bool in
                guard let base = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return true
                }
                if bytesPerSample == 1 {
                    for i in 0..<voxelsPerSlice {
                        let cur = Int32(base[curStart + i])
                        let prv = Int32(base[prvStart + i])
                        let d = cur - prv
                        if d < signedMin || d > signedMax { return true }
                        diff[i] = d
                        residualL1 += Int64(d.magnitude)
                        sliceL1   += Int64((cur &- dcMidpoint).magnitude)
                    }
                } else {
                    for i in 0..<voxelsPerSlice {
                        // Tile buffers are LE per `serialiseFloatSamples`
                        // in JP3DEncoder.makeTileVoxels.
                        let curLo = UInt16(base[curStart + i * 2])
                        let curHi = UInt16(base[curStart + i * 2 + 1])
                        let prvLo = UInt16(base[prvStart + i * 2])
                        let prvHi = UInt16(base[prvStart + i * 2 + 1])
                        let cur = Int32((curHi << 8) | curLo)
                        let prv = Int32((prvHi << 8) | prvLo)
                        let d = cur - prv
                        if d < signedMin || d > signedMax { return true }
                        diff[i] = d
                        residualL1 += Int64(d.magnitude)
                        sliceL1   += Int64((cur &- dcMidpoint).magnitude)
                    }
                }
                return false
            }
            if overflowed { return nil }
            perComponent.append(diff)
        }

        // 0.55 is the empirical sweet spot from the 51-row matrix:
        //   - Synthetic seismic / hyperspectral / thin-slice CT have
        //     residual_L1 / slice_L1 well below 0.5 — they engage
        //     Z-delta and pick up 2-4× ratio improvements vs raw.
        //   - Real medical CT/MR consecutive slices typically sit at
        //     0.55-0.75 — at 0.55 they fall back to raw encoding,
        //     keeping the 1.5× encode-speed gate happy.
        //   - Tighter (e.g. 0.40) loses the marginal thin-slice
        //     CT wins; looser (e.g. 0.70) over-engages on natural
        //     medical and the 2× try-both encode cost violates the
        //     speed gate without buying material ratio improvement.
        // Always revalidate against `Scripts/jp3d_clinical_validation.py`
        // when changing this — both the 1.5× speed gate AND the
        // ratio_delta ≥ 0.99 gate must hold.
        let residualL1Threshold: Double = 0.55
        if Double(residualL1) >= residualL1Threshold * Double(sliceL1) {
            return nil
        }

        return ResidualCandidate(perComponent: perComponent)
    }

    private func makeUnsignedImage(forSlice z: Int, in tile: TileVoxels) -> J2KImage {
        let bytesPerSample = max(1, (tile.bitDepth + 7) / 8)
        let voxelsPerSlice = tile.width * tile.height
        let sliceByteCount = voxelsPerSlice * bytesPerSample

        var components: [J2KComponent] = []
        components.reserveCapacity(tile.componentCount)

        for compIdx in 0..<tile.componentCount {
            let compBuffer = tile.componentData[compIdx]
            let zStart = z * sliceByteCount
            let zEnd   = zStart + sliceByteCount
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

    /// Wraps per-component Int32 residuals as a J2KImage with
    /// `signed: true` components at the same bit-depth as the input.
    /// The caller has already verified that every residual fits in
    /// `[-2^(B-1), 2^(B-1)-1]`, so the LE serialisation below cannot
    /// truncate.
    private func makeSignedImage(from residuals: [[Int32]],
                                  in tile: TileVoxels) -> J2KImage {
        let bytesPerSample = max(1, (tile.bitDepth + 7) / 8)
        let voxelsPerSlice = tile.width * tile.height

        var components: [J2KComponent] = []
        components.reserveCapacity(tile.componentCount)

        for compIdx in 0..<tile.componentCount {
            let resid = residuals[compIdx]
            var bytes = Data(count: voxelsPerSlice * bytesPerSample)
            bytes.withUnsafeMutableBytes { rawBuf in
                let base = rawBuf.baseAddress!
                if bytesPerSample == 1 {
                    for i in 0..<voxelsPerSlice {
                        let v = Int8(truncatingIfNeeded: resid[i])
                        base.advanced(by: i)
                            .storeBytes(of: UInt8(bitPattern: v), as: UInt8.self)
                    }
                } else {
                    for i in 0..<voxelsPerSlice {
                        let v = Int16(truncatingIfNeeded: resid[i])
                        let u = UInt16(bitPattern: v).littleEndian
                        base.advanced(by: i * 2)
                            .storeBytes(of: u, as: UInt16.self)
                    }
                }
            }
            components.append(J2KComponent(
                index: compIdx,
                bitDepth: tile.bitDepth,
                signed: true,
                width: tile.width,
                height: tile.height,
                data: bytes,
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
        slicePayloads: [(flags: UInt8, data: Data)],
        tile: TileVoxels,
        useHTJ2K: Bool,
        lossless: Bool,
        useZDelta: Bool
    ) -> Data {
        var flags: UInt32 = 0
        if useHTJ2K   { flags |= Self.flagHTJ2K }
        if lossless   { flags |= Self.flagLossless }
        if useZDelta  { flags |= Self.flagZDelta }

        // 1 byte per-slice flag + 4-byte length prefix + codestream.
        let totalSlicePayloadBytes = slicePayloads.reduce(0) {
            $0 + 1 + 4 + $1.data.count
        }
        var out = Data(capacity: Self.headerByteCount + totalSlicePayloadBytes)

        out.append(contentsOf: Self.magic)
        appendUInt32BE(&out, Self.version)
        appendUInt32BE(&out, flags)
        appendUInt32BE(&out, UInt32(tile.depth))
        appendUInt32BE(&out, UInt32(tile.width))
        appendUInt32BE(&out, UInt32(tile.height))
        appendUInt32BE(&out, UInt32(tile.componentCount))
        appendUInt32BE(&out, UInt32(tile.bitDepth))

        for (sliceFlags, cs) in slicePayloads {
            out.append(sliceFlags)
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

    /// Reads a J2KDecoder-output image as one Int32 buffer per
    /// component. Knows about J2KDecoder's BE 16-bit convention
    /// (`J2KDecoderPipeline.swift:2689`) and sign-extends 8-bit and
    /// 16-bit signed components correctly so residual addition stays
    /// arithmetically faithful.
    private func readImageAsInt32(
        _ image: J2KImage,
        tileWidth: Int, tileHeight: Int,
        bitDepth: Int, signed: Bool
    ) throws -> [[Int32]] {
        guard image.componentCount > 0 else {
            throw J2KError.decodingError("JP3D slice-stack: decoded image has no components")
        }
        let bytesPerSample = max(1, (bitDepth + 7) / 8)
        let voxelsPerSlice = tileWidth * tileHeight

        var out: [[Int32]] = []
        out.reserveCapacity(image.componentCount)

        for (compIdx, comp) in image.components.enumerated() {
            guard comp.width == tileWidth, comp.height == tileHeight else {
                throw J2KError.decodingError(
                    "JP3D slice-stack: decoded slice comp \(compIdx) is " +
                    "\(comp.width)x\(comp.height), expected \(tileWidth)x\(tileHeight)"
                )
            }
            let data = comp.data
            var slice = [Int32](repeating: 0, count: voxelsPerSlice)

            if bytesPerSample == 1 {
                for i in 0..<voxelsPerSlice {
                    let byte = data[data.startIndex + i]
                    slice[i] = signed
                        ? Int32(Int8(bitPattern: byte))
                        : Int32(byte)
                }
            } else {
                // J2KDecoder writes 16-bit samples as big-endian.
                for i in 0..<voxelsPerSlice {
                    let hi = UInt16(data[data.startIndex + i * 2])
                    let lo = UInt16(data[data.startIndex + i * 2 + 1])
                    let u = (hi << 8) | lo
                    slice[i] = signed
                        ? Int32(Int16(bitPattern: u))
                        : Int32(u)
                }
            }
            out.append(slice)
        }
        return out
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
