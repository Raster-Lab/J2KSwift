/// # JP3DPacketFormation
///
/// Tier-2 packet formation for JP3D volumetric JPEG 2000 codestreams.
///
/// Organizes quantized wavelet coefficients into packets according to
/// 3D progression orders (LRCPS, RLCPS, PCRLS, SLRCP, CPRLS).
///
/// ## Topics
///
/// ### Packet Types
/// - ``JP3DPacket``
/// - ``JP3DPacketSequencer``
/// - ``JP3DCodestreamBuilder``

import Foundation
import J2KCore

/// A single packet in the JP3D codestream.
///
/// Each packet contains the contributions of a specific quality layer,
/// resolution level, component, and spatial position.
public struct JP3DPacket: Sendable {
    /// Quality layer index.
    public let layer: Int

    /// Resolution level (0 = coarsest).
    public let resolutionLevel: Int

    /// Component index.
    public let componentIndex: Int

    /// Precinct position (linearized).
    public let precinctIndex: Int

    /// Slice index (Z position for slice-based progression).
    public let sliceIndex: Int

    /// The encoded data for this packet.
    public let data: Data

    /// Whether this packet contains any non-zero contributions.
    public var isEmpty: Bool { data.isEmpty }
}

/// Generates the packet ordering for a 3D codestream.
///
/// `JP3DPacketSequencer` determines the order in which packets appear
/// in the codestream based on the selected progression order.
///
/// Example:
/// ```swift
/// let sequencer = JP3DPacketSequencer(progressionOrder: .lrcps)
/// let indices = sequencer.packetOrder(
///     layers: 3, resolutions: 4, components: 1,
///     precinctsPerResolution: [16, 4, 1, 1],
///     slices: 8
/// )
/// ```
public struct JP3DPacketSequencer: Sendable {
    /// The progression order.
    public let progressionOrder: JP3DProgressionOrder

    /// Creates a packet sequencer with the given progression order.
    ///
    /// - Parameter progressionOrder: The progression order. Defaults to `.lrcps`.
    public init(progressionOrder: JP3DProgressionOrder = .lrcps) {
        self.progressionOrder = progressionOrder
    }

    /// A single entry in the packet ordering sequence.
    public struct PacketIndex: Sendable, Equatable {
        /// Quality layer index.
        public let layer: Int
        /// Resolution level.
        public let resolution: Int
        /// Component index.
        public let component: Int
        /// Precinct index (spatial position).
        public let precinct: Int
        /// Slice index.
        public let slice: Int
    }

    /// Computes the full packet ordering for the given codestream parameters.
    ///
    /// - Parameters:
    ///   - layers: Number of quality layers.
    ///   - resolutions: Number of resolution levels.
    ///   - components: Number of components.
    ///   - precinctsPerResolution: Number of precincts at each resolution level.
    ///   - slices: Number of slices for slice-based progression.
    /// - Returns: Ordered array of packet indices.
    public func packetOrder(
        layers: Int,
        resolutions: Int,
        components: Int,
        precinctsPerResolution: [Int],
        slices: Int
    ) -> [PacketIndex] {
        let maxPrecincts = precinctsPerResolution.max() ?? 1

        switch progressionOrder {
        case .lrcps:
            return orderLRCPS(
                layers: layers, resolutions: resolutions, components: components,
                maxPrecincts: maxPrecincts, slices: slices,
                precinctsPerResolution: precinctsPerResolution
            )
        case .rlcps:
            return orderRLCPS(
                layers: layers, resolutions: resolutions, components: components,
                maxPrecincts: maxPrecincts, slices: slices,
                precinctsPerResolution: precinctsPerResolution
            )
        case .pcrls:
            return orderPCRLS(
                layers: layers, resolutions: resolutions, components: components,
                maxPrecincts: maxPrecincts, slices: slices,
                precinctsPerResolution: precinctsPerResolution
            )
        case .slrcp:
            return orderSLRCP(
                layers: layers, resolutions: resolutions, components: components,
                maxPrecincts: maxPrecincts, slices: slices,
                precinctsPerResolution: precinctsPerResolution
            )
        case .cprls:
            return orderCPRLS(
                layers: layers, resolutions: resolutions, components: components,
                maxPrecincts: maxPrecincts, slices: slices,
                precinctsPerResolution: precinctsPerResolution
            )
        }
    }

    // MARK: - Progression Orders

    /// Layer-Resolution-Component-Position-Slice (quality-scalable).
    private func orderLRCPS(
        layers: Int, resolutions: Int, components: Int,
        maxPrecincts: Int, slices: Int,
        precinctsPerResolution: [Int]
    ) -> [PacketIndex] {
        var indices: [PacketIndex] = []
        for l in 0..<layers {
            for r in 0..<resolutions {
                let pCount = r < precinctsPerResolution.count ? precinctsPerResolution[r] : 1
                for c in 0..<components {
                    for p in 0..<pCount {
                        for s in 0..<slices {
                            indices.append(PacketIndex(
                                layer: l, resolution: r, component: c,
                                precinct: p, slice: s
                            ))
                        }
                    }
                }
            }
        }
        return indices
    }

    /// Resolution-Layer-Component-Position-Slice (resolution-first).
    private func orderRLCPS(
        layers: Int, resolutions: Int, components: Int,
        maxPrecincts: Int, slices: Int,
        precinctsPerResolution: [Int]
    ) -> [PacketIndex] {
        var indices: [PacketIndex] = []
        for r in 0..<resolutions {
            let pCount = r < precinctsPerResolution.count ? precinctsPerResolution[r] : 1
            for l in 0..<layers {
                for c in 0..<components {
                    for p in 0..<pCount {
                        for s in 0..<slices {
                            indices.append(PacketIndex(
                                layer: l, resolution: r, component: c,
                                precinct: p, slice: s
                            ))
                        }
                    }
                }
            }
        }
        return indices
    }

    /// Position-Component-Resolution-Layer-Slice (spatial-first).
    private func orderPCRLS(
        layers: Int, resolutions: Int, components: Int,
        maxPrecincts: Int, slices: Int,
        precinctsPerResolution: [Int]
    ) -> [PacketIndex] {
        var indices: [PacketIndex] = []
        for p in 0..<maxPrecincts {
            for c in 0..<components {
                for r in 0..<resolutions {
                    let pCount = r < precinctsPerResolution.count ? precinctsPerResolution[r] : 1
                    guard p < pCount else { continue }
                    for l in 0..<layers {
                        for s in 0..<slices {
                            indices.append(PacketIndex(
                                layer: l, resolution: r, component: c,
                                precinct: p, slice: s
                            ))
                        }
                    }
                }
            }
        }
        return indices
    }

    /// Slice-Layer-Resolution-Component-Position (Z-axis first).
    private func orderSLRCP(
        layers: Int, resolutions: Int, components: Int,
        maxPrecincts: Int, slices: Int,
        precinctsPerResolution: [Int]
    ) -> [PacketIndex] {
        var indices: [PacketIndex] = []
        for s in 0..<slices {
            for l in 0..<layers {
                for r in 0..<resolutions {
                    let pCount = r < precinctsPerResolution.count ? precinctsPerResolution[r] : 1
                    for c in 0..<components {
                        for p in 0..<pCount {
                            indices.append(PacketIndex(
                                layer: l, resolution: r, component: c,
                                precinct: p, slice: s
                            ))
                        }
                    }
                }
            }
        }
        return indices
    }

    /// Component-Position-Resolution-Layer-Slice (component-first).
    private func orderCPRLS(
        layers: Int, resolutions: Int, components: Int,
        maxPrecincts: Int, slices: Int,
        precinctsPerResolution: [Int]
    ) -> [PacketIndex] {
        var indices: [PacketIndex] = []
        for c in 0..<components {
            for p in 0..<maxPrecincts {
                for r in 0..<resolutions {
                    let pCount = r < precinctsPerResolution.count ? precinctsPerResolution[r] : 1
                    guard p < pCount else { continue }
                    for l in 0..<layers {
                        for s in 0..<slices {
                            indices.append(PacketIndex(
                                layer: l, resolution: r, component: c,
                                precinct: p, slice: s
                            ))
                        }
                    }
                }
            }
        }
        return indices
    }
}

/// Builds a JP3D codestream from packets.
///
/// `JP3DCodestreamBuilder` assembles packets with proper marker segments
/// into a complete JP3D codestream conforming to ISO/IEC 15444-10.
public struct JP3DCodestreamBuilder: Sendable {

    /// JP3D marker segment identifiers.
    public enum Marker: UInt16, Sendable {
        /// Start of codestream.
        case soc = 0xFF4F
        /// End of codestream.
        case eoc = 0xFFD9
        /// Start of tile-part.
        case sot = 0xFF90
        /// Start of data.
        case sod = 0xFF93
        /// Image and tile size (SIZ marker).
        case siz = 0xFF51
        /// Coding style default (COD marker).
        case cod = 0xFF52
        /// Quantization default (QCD marker).
        case qcd = 0xFF5C
        /// Comment (COM marker).
        case com = 0xFF64
    }

    /// Creates a new codestream builder.
    public init() {}

    /// Builds a minimal JP3D codestream from encoded tile data.
    ///
    /// - Parameters:
    ///   - tileData: Encoded data for each tile.
    ///   - width: Volume width.
    ///   - height: Volume height.
    ///   - depth: Volume depth.
    ///   - components: Number of components.
    ///   - bitDepth: Bit depth per component.
    ///   - decompositionLevels: Number of wavelet decomposition levels.
    ///   - isLossless: Whether lossless encoding was used.
    /// - Returns: The assembled JP3D codestream as `Data`.
    public func build(
        tileData: [Data],
        width: Int,
        height: Int,
        depth: Int,
        components: Int,
        bitDepth: Int,
        decompositionLevels: Int,
        isLossless: Bool
    ) -> Data {
        var stream = Data()

        // SOC marker
        appendMarker(&stream, .soc)

        // SIZ marker segment (simplified)
        appendSIZ(&stream, width: width, height: height, depth: depth,
                   components: components, bitDepth: bitDepth)

        // COD marker segment (simplified)
        appendCOD(&stream, levels: decompositionLevels, isLossless: isLossless)

        // QCD marker segment (simplified)
        appendQCD(&stream, bitDepth: bitDepth, levels: decompositionLevels, isLossless: isLossless)

        // Tile data
        for (index, data) in tileData.enumerated() {
            appendSOT(&stream, tileIndex: index, tilePartLength: data.count)
            appendMarker(&stream, .sod)
            stream.append(data)
        }

        // EOC marker
        appendMarker(&stream, .eoc)

        return stream
    }

    // MARK: - Private Helpers

    private func appendMarker(_ stream: inout Data, _ marker: Marker) {
        var value = marker.rawValue.bigEndian
        stream.append(contentsOf: withUnsafeBytes(of: &value) { Array($0) })
    }

    private func appendUInt16BE(_ stream: inout Data, _ value: UInt16) {
        var v = value.bigEndian
        stream.append(contentsOf: withUnsafeBytes(of: &v) { Array($0) })
    }

    private func appendUInt32BE(_ stream: inout Data, _ value: UInt32) {
        var v = value.bigEndian
        stream.append(contentsOf: withUnsafeBytes(of: &v) { Array($0) })
    }

    private func appendSIZ(
        _ stream: inout Data,
        width: Int, height: Int, depth: Int,
        components: Int, bitDepth: Int
    ) {
        appendMarker(&stream, .siz)
        // Length (placeholder, simplified)
        let segmentLength: UInt16 = UInt16(38 + 3 * components)
        appendUInt16BE(&stream, segmentLength)
        // Profile: 0 (no restrictions)
        appendUInt16BE(&stream, 0)
        // Image dimensions (XY)
        appendUInt32BE(&stream, UInt32(width))
        appendUInt32BE(&stream, UInt32(height))
        // Image offset
        appendUInt32BE(&stream, 0)
        appendUInt32BE(&stream, 0)
        // Tile dimensions
        appendUInt32BE(&stream, UInt32(width))
        appendUInt32BE(&stream, UInt32(height))
        // Tile offset
        appendUInt32BE(&stream, 0)
        appendUInt32BE(&stream, 0)
        // Components
        appendUInt16BE(&stream, UInt16(components))
        // Component info
        for _ in 0..<components {
            stream.append(UInt8(bitDepth - 1)) // Ssiz
            stream.append(UInt8(1)) // XRsiz
            stream.append(UInt8(1)) // YRsiz
        }
        // Depth (JP3D extension)
        appendUInt32BE(&stream, UInt32(depth))
    }

    private func appendCOD(_ stream: inout Data, levels: Int, isLossless: Bool) {
        appendMarker(&stream, .cod)
        let segmentLength: UInt16 = 12
        appendUInt16BE(&stream, segmentLength)
        // Coding style: no precincts
        stream.append(UInt8(0))
        // Progression order: LRCP
        stream.append(UInt8(0))
        // Quality layers
        appendUInt16BE(&stream, 1)
        // Multiple component transform: none
        stream.append(UInt8(0))
        // Decomposition levels
        stream.append(UInt8(levels))
        // Code-block width/height exponent (64x64)
        stream.append(UInt8(4))
        stream.append(UInt8(4))
        // Code-block style
        stream.append(UInt8(0))
        // Wavelet filter
        stream.append(isLossless ? UInt8(1) : UInt8(0))
    }

    private func appendQCD(_ stream: inout Data, bitDepth: Int, levels: Int, isLossless: Bool) {
        appendMarker(&stream, .qcd)
        let numSubbands = 3 * levels + 1
        let segmentLength: UInt16 = UInt16(3 + numSubbands * (isLossless ? 1 : 2))
        appendUInt16BE(&stream, segmentLength)
        // Quantization style
        if isLossless {
            stream.append(UInt8(0)) // No quantization
            // Guard bits (3) + exponent for each subband
            for _ in 0..<numSubbands {
                stream.append(UInt8((3 << 5) | (bitDepth & 0x1F)))
            }
        } else {
            stream.append(UInt8(2)) // Scalar expounded
            for _ in 0..<numSubbands {
                // Exponent + mantissa
                appendUInt16BE(&stream, UInt16((3 << 11) | ((bitDepth & 0x1F) << 6)))
            }
        }
    }

    private func appendSOT(_ stream: inout Data, tileIndex: Int, tilePartLength: Int) {
        appendMarker(&stream, .sot)
        let segmentLength: UInt16 = 10
        appendUInt16BE(&stream, segmentLength)
        // Tile index
        appendUInt16BE(&stream, UInt16(tileIndex))
        // Tile-part length (including SOT, SOD markers)
        let totalLength = UInt32(12 + 2 + tilePartLength) // SOT(12) + SOD(2) + data
        appendUInt32BE(&stream, totalLength)
        // Tile-part index
        stream.append(UInt8(0))
        // Number of tile-parts (0 = unknown)
        stream.append(UInt8(1))
    }
}
