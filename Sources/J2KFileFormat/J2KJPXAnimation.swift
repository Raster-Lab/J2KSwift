// J2KJPXAnimation.swift
// JPX animation and multi-layer compositing support per ISO/IEC 15444-2
//
// Copyright (c) 2024 J2KSwift contributors
// Licensed under the MIT License

import Foundation
import J2KCore
import J2KCodec

// MARK: - JPX Animation Box Types (ISO/IEC 15444-2)

extension J2KBoxType {
    /// Compositing layer header box ('jplh') — layer header for JPX.
    public static let jplh = J2KBoxType(string: "jplh")

    /// Instruction set box ('inst') — animation instructions.
    public static let inst = J2KBoxType(string: "inst")

    /// Opacity box ('opct') — layer opacity.
    public static let opct = J2KBoxType(string: "opct")

    /// Codestream registration box ('creg') — registration between codestreams.
    public static let creg = J2KBoxType(string: "creg")
}

// MARK: - J2KAnimationTiming

/// Animation timing information for JPX animation sequences.
///
/// Describes the temporal characteristics of an animation, including timescale,
/// total duration, looping behavior, and playback direction.
///
/// Example:
/// ```swift
/// // 5-second animation at millisecond precision
/// let timing = J2KAnimationTiming.milliseconds(duration: 5000, loops: 3)
///
/// // Infinite looping animation
/// let loop = J2KAnimationTiming.infinite()
/// ```
public struct J2KAnimationTiming: Sendable {
    /// Ticks per second (e.g. 1000 for millisecond precision).
    public var timescale: UInt32

    /// Total duration in ticks (0 = infinite).
    public var duration: UInt64

    /// Number of loops (0 = infinite).
    public var loopCount: UInt32

    /// Whether to play in reverse after each forward pass.
    public var autoReverse: Bool

    /// Creates animation timing with explicit parameters.
    ///
    /// - Parameters:
    ///   - timescale: Ticks per second.
    ///   - duration: Total duration in ticks.
    ///   - loopCount: Number of loops (0 = infinite).
    ///   - autoReverse: Whether to auto-reverse playback.
    public init(
        timescale: UInt32,
        duration: UInt64,
        loopCount: UInt32 = 0,
        autoReverse: Bool = false
    ) {
        self.timescale = timescale
        self.duration = duration
        self.loopCount = loopCount
        self.autoReverse = autoReverse
    }

    /// Duration expressed in seconds.
    public var durationSeconds: Double {
        guard timescale > 0 else { return 0 }
        return Double(duration) / Double(timescale)
    }

    /// Whether the animation runs indefinitely.
    public var isInfinite: Bool {
        duration == 0 || loopCount == 0
    }

    /// Creates timing with millisecond precision.
    ///
    /// - Parameters:
    ///   - duration: Duration in milliseconds.
    ///   - loops: Number of loops (0 = infinite).
    /// - Returns: A configured timing instance.
    public static func milliseconds(duration: UInt64, loops: UInt32 = 0) -> J2KAnimationTiming {
        J2KAnimationTiming(timescale: 1000, duration: duration, loopCount: loops)
    }

    /// Creates timing from a seconds value using a 1000-tick timescale.
    ///
    /// - Parameters:
    ///   - duration: Duration in seconds.
    ///   - loops: Number of loops (0 = infinite).
    /// - Returns: A configured timing instance.
    public static func seconds(duration: Double, loops: UInt32 = 0) -> J2KAnimationTiming {
        J2KAnimationTiming(
            timescale: 1000,
            duration: UInt64(duration * 1000),
            loopCount: loops
        )
    }

    /// Creates an infinite-duration timing.
    ///
    /// - Returns: Timing with zero duration and zero loop count.
    public static func infinite() -> J2KAnimationTiming {
        J2KAnimationTiming(timescale: 1000, duration: 0, loopCount: 0)
    }
}

// MARK: - J2KAnimationFrame

/// A single animation frame within a JPX animation sequence.
///
/// Represents a frame referencing a specific codestream and composition layer,
/// with positioning, sizing, opacity, and optional crop region.
///
/// Example:
/// ```swift
/// let frame = J2KAnimationFrame(
///     codestreamIndex: 0,
///     compositionLayerIndex: 0,
///     duration: 100,
///     width: 800,
///     height: 600
/// )
/// ```
public struct J2KAnimationFrame: Sendable, Equatable {
    /// Index of the codestream to display.
    public var codestreamIndex: UInt16

    /// Index of the composition layer.
    public var compositionLayerIndex: UInt16

    /// Frame duration in timescale ticks.
    public var duration: UInt32

    /// Horizontal offset on the canvas.
    public var x: UInt32

    /// Vertical offset on the canvas.
    public var y: UInt32

    /// Display width (0 = use codestream width).
    public var width: UInt32

    /// Display height (0 = use codestream height).
    public var height: UInt32

    /// Opacity from 0 (transparent) to 255 (fully opaque).
    public var opacity: UInt8

    /// Crop region X offset.
    public var cropX: UInt32

    /// Crop region Y offset.
    public var cropY: UInt32

    /// Crop region width (0 = no crop).
    public var cropWidth: UInt32

    /// Crop region height (0 = no crop).
    public var cropHeight: UInt32

    /// Creates an animation frame.
    ///
    /// - Parameters:
    ///   - codestreamIndex: Index of the codestream to display.
    ///   - compositionLayerIndex: Index of the composition layer.
    ///   - duration: Frame duration in timescale ticks.
    ///   - x: Horizontal offset (default: 0).
    ///   - y: Vertical offset (default: 0).
    ///   - width: Display width (default: 0, use codestream width).
    ///   - height: Display height (default: 0, use codestream height).
    ///   - opacity: Opacity 0–255 (default: 255).
    ///   - cropX: Crop X offset (default: 0).
    ///   - cropY: Crop Y offset (default: 0).
    ///   - cropWidth: Crop width (default: 0, no crop).
    ///   - cropHeight: Crop height (default: 0, no crop).
    public init(
        codestreamIndex: UInt16,
        compositionLayerIndex: UInt16,
        duration: UInt32,
        x: UInt32 = 0,
        y: UInt32 = 0,
        width: UInt32 = 0,
        height: UInt32 = 0,
        opacity: UInt8 = 255,
        cropX: UInt32 = 0,
        cropY: UInt32 = 0,
        cropWidth: UInt32 = 0,
        cropHeight: UInt32 = 0
    ) {
        self.codestreamIndex = codestreamIndex
        self.compositionLayerIndex = compositionLayerIndex
        self.duration = duration
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.opacity = opacity
        self.cropX = cropX
        self.cropY = cropY
        self.cropWidth = cropWidth
        self.cropHeight = cropHeight
    }
}

// MARK: - J2KInstructionSetBox

/// Instruction set box.
///
/// The instruction set box ('inst') contains rendering instructions for
/// multi-layer composition and animation sequences as defined in
/// ISO/IEC 15444-2 Annex M.
///
/// ## Box Structure
///
/// - Type: 'inst' (0x696E7374)
/// - Length: Variable
/// - Content:
///   - Instruction type (1 byte): 0 = compose, 1 = animate, 2 = transform
///   - Repeat count (2 bytes): Number of times to repeat
///   - Tick duration (4 bytes): Duration per tick in timescale units
///   - Instruction count (2 bytes): Number of instruction entries
///   - Entries: Array of instruction entries (11 bytes each)
///
/// Each entry (11 bytes):
/// - Layer index (2 bytes)
/// - Horizontal offset (4 bytes, signed)
/// - Vertical offset (4 bytes, signed)
/// - Persistence flag (1 byte)
///
/// Example:
/// ```swift
/// let entry = J2KInstructionSetBox.InstructionEntry(
///     layerIndex: 0,
///     horizontalOffset: 100,
///     verticalOffset: 50,
///     persistenceFlag: true
/// )
/// let box = J2KInstructionSetBox(
///     instructionType: .animate,
///     repeatCount: 3,
///     tickDuration: 100,
///     instructions: [entry]
/// )
/// let data = try box.write()
/// ```
public struct J2KInstructionSetBox: J2KBox, Sendable {
    /// Type of rendering instruction.
    public enum InstructionType: UInt8, Sendable {
        /// Static layer composition.
        case compose = 0
        /// Animated frame sequence.
        case animate = 1
        /// Geometric transformation.
        case transform = 2
    }

    /// A single instruction entry describing layer placement.
    public struct InstructionEntry: Sendable, Equatable {
        /// Index of the composition layer.
        public var layerIndex: UInt16

        /// Signed horizontal offset on the canvas.
        public var horizontalOffset: Int32

        /// Signed vertical offset on the canvas.
        public var verticalOffset: Int32

        /// Whether the layer persists after its display duration.
        public var persistenceFlag: Bool

        /// Creates an instruction entry.
        ///
        /// - Parameters:
        ///   - layerIndex: Composition layer index.
        ///   - horizontalOffset: Horizontal offset.
        ///   - verticalOffset: Vertical offset.
        ///   - persistenceFlag: Whether the layer persists.
        public init(
            layerIndex: UInt16,
            horizontalOffset: Int32 = 0,
            verticalOffset: Int32 = 0,
            persistenceFlag: Bool = false
        ) {
            self.layerIndex = layerIndex
            self.horizontalOffset = horizontalOffset
            self.verticalOffset = verticalOffset
            self.persistenceFlag = persistenceFlag
        }
    }

    /// The type of instruction.
    public var instructionType: InstructionType

    /// Number of times to repeat the instruction sequence.
    public var repeatCount: UInt16

    /// Duration per tick in timescale units.
    public var tickDuration: UInt32

    /// The array of instruction entries.
    public var instructions: [InstructionEntry]

    public var boxType: J2KBoxType {
        .inst
    }

    /// Creates an instruction set box.
    ///
    /// - Parameters:
    ///   - instructionType: Type of instruction (default: compose).
    ///   - repeatCount: Repeat count (default: 1).
    ///   - tickDuration: Tick duration (default: 0).
    ///   - instructions: Array of instruction entries.
    public init(
        instructionType: InstructionType = .compose,
        repeatCount: UInt16 = 1,
        tickDuration: UInt32 = 0,
        instructions: [InstructionEntry] = []
    ) {
        self.instructionType = instructionType
        self.repeatCount = repeatCount
        self.tickDuration = tickDuration
        self.instructions = instructions
    }

    public func write() throws -> Data {
        guard instructions.count <= UInt16.max else {
            throw J2KError.fileFormatError(
                "Too many instruction entries: \(instructions.count), maximum is \(UInt16.max)"
            )
        }

        var output = Data()
        output.reserveCapacity(9 + instructions.count * 11)

        // Instruction type (1 byte)
        output.append(instructionType.rawValue)

        // Repeat count (2 bytes)
        output.append(UInt8((repeatCount >> 8) & 0xFF))
        output.append(UInt8(repeatCount & 0xFF))

        // Tick duration (4 bytes)
        output.append(UInt8((tickDuration >> 24) & 0xFF))
        output.append(UInt8((tickDuration >> 16) & 0xFF))
        output.append(UInt8((tickDuration >> 8) & 0xFF))
        output.append(UInt8(tickDuration & 0xFF))

        // Instruction count (2 bytes)
        let count = UInt16(instructions.count)
        output.append(UInt8((count >> 8) & 0xFF))
        output.append(UInt8(count & 0xFF))

        // Write entries
        for entry in instructions {
            // Layer index (2 bytes)
            output.append(UInt8((entry.layerIndex >> 8) & 0xFF))
            output.append(UInt8(entry.layerIndex & 0xFF))

            // Horizontal offset (4 bytes, signed big-endian)
            let hBits = UInt32(bitPattern: entry.horizontalOffset)
            output.append(UInt8((hBits >> 24) & 0xFF))
            output.append(UInt8((hBits >> 16) & 0xFF))
            output.append(UInt8((hBits >> 8) & 0xFF))
            output.append(UInt8(hBits & 0xFF))

            // Vertical offset (4 bytes, signed big-endian)
            let vBits = UInt32(bitPattern: entry.verticalOffset)
            output.append(UInt8((vBits >> 24) & 0xFF))
            output.append(UInt8((vBits >> 16) & 0xFF))
            output.append(UInt8((vBits >> 8) & 0xFF))
            output.append(UInt8(vBits & 0xFF))

            // Persistence flag (1 byte)
            output.append(entry.persistenceFlag ? 1 : 0)
        }

        return output
    }

    public mutating func read(from data: Data) throws {
        guard data.count >= 9 else {
            throw J2KError.fileFormatError(
                "Invalid instruction set box length: \(data.count), expected at least 9"
            )
        }

        // Instruction type (1 byte)
        guard let type = InstructionType(rawValue: data[0]) else {
            throw J2KError.fileFormatError("Invalid instruction type: \(data[0])")
        }
        self.instructionType = type

        // Repeat count (2 bytes)
        self.repeatCount = UInt16(data[1]) << 8 | UInt16(data[2])

        // Tick duration (4 bytes)
        self.tickDuration = UInt32(data[3]) << 24 |
                            UInt32(data[4]) << 16 |
                            UInt32(data[5]) << 8 |
                            UInt32(data[6])

        // Instruction count (2 bytes)
        let count = UInt16(data[7]) << 8 | UInt16(data[8])

        let expectedSize = 9 + Int(count) * 11
        guard data.count >= expectedSize else {
            throw J2KError.fileFormatError(
                "Invalid instruction set box length: \(data.count), expected at least \(expectedSize)"
            )
        }

        var offset = 9
        var result: [InstructionEntry] = []
        result.reserveCapacity(Int(count))

        for _ in 0..<count {
            // Layer index (2 bytes)
            let layerIndex = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            offset += 2

            // Horizontal offset (4 bytes, signed)
            let hBits = UInt32(data[offset]) << 24 |
                        UInt32(data[offset + 1]) << 16 |
                        UInt32(data[offset + 2]) << 8 |
                        UInt32(data[offset + 3])
            let hOffset = Int32(bitPattern: hBits)
            offset += 4

            // Vertical offset (4 bytes, signed)
            let vBits = UInt32(data[offset]) << 24 |
                        UInt32(data[offset + 1]) << 16 |
                        UInt32(data[offset + 2]) << 8 |
                        UInt32(data[offset + 3])
            let vOffset = Int32(bitPattern: vBits)
            offset += 4

            // Persistence flag (1 byte)
            let persistence = data[offset] != 0
            offset += 1

            result.append(InstructionEntry(
                layerIndex: layerIndex,
                horizontalOffset: hOffset,
                verticalOffset: vOffset,
                persistenceFlag: persistence
            ))
        }

        self.instructions = result
    }
}

// MARK: - J2KOpacityBox

/// Opacity box.
///
/// The opacity box ('opct') specifies how opacity is determined for a
/// compositing layer. It supports three modes: using the last channel as
/// alpha, a separate matte channel, or a single global opacity value.
///
/// ## Box Structure
///
/// - Type: 'opct' (0x6F706374)
/// - Length: 2 bytes
/// - Content:
///   - Opacity type (1 byte): 0 = last channel, 1 = matte, 2 = global value
///   - Opacity value (1 byte): Global opacity (used when type is 2)
///
/// Example:
/// ```swift
/// let box = J2KOpacityBox(opacityType: .globalValue, opacity: 128)
/// let data = try box.write()
/// ```
public struct J2KOpacityBox: J2KBox, Sendable {
    /// How opacity is determined for the layer.
    public enum OpacityType: UInt8, Sendable {
        /// Last channel of the codestream is used as alpha.
        case lastChannel = 0
        /// A separate matte channel provides alpha.
        case matteChannel = 1
        /// A single global opacity value applies to the entire layer.
        case globalValue = 2
    }

    /// The opacity determination method.
    public var opacityType: OpacityType

    /// Global opacity value (0–255). Only meaningful when ``opacityType`` is `.globalValue`.
    public var opacity: UInt8

    public var boxType: J2KBoxType {
        .opct
    }

    /// Creates an opacity box.
    ///
    /// - Parameters:
    ///   - opacityType: How opacity is determined (default: globalValue).
    ///   - opacity: Global opacity value (default: 255, fully opaque).
    public init(opacityType: OpacityType = .globalValue, opacity: UInt8 = 255) {
        self.opacityType = opacityType
        self.opacity = opacity
    }

    public func write() throws -> Data {
        var output = Data()
        output.reserveCapacity(2)
        output.append(opacityType.rawValue)
        output.append(opacity)
        return output
    }

    public mutating func read(from data: Data) throws {
        guard data.count >= 2 else {
            throw J2KError.fileFormatError(
                "Invalid opacity box length: \(data.count), expected at least 2"
            )
        }
        guard let type = OpacityType(rawValue: data[0]) else {
            throw J2KError.fileFormatError("Invalid opacity type: \(data[0])")
        }
        self.opacityType = type
        self.opacity = data[1]
    }
}

// MARK: - J2KCodestreamRegistrationBox

/// Codestream registration box.
///
/// The codestream registration box ('creg') maps codestreams to a composition
/// reference grid, defining how each codestream is positioned relative to
/// the canvas.
///
/// ## Box Structure
///
/// - Type: 'creg' (0x63726567)
/// - Length: Variable
/// - Content:
///   - Horizontal grid size (2 bytes): Reference grid width
///   - Vertical grid size (2 bytes): Reference grid height
///   - Registration count (2 bytes): Number of registrations
///   - Registrations: Array of registration entries (6 bytes each)
///
/// Each registration entry (6 bytes):
/// - Codestream index (2 bytes)
/// - Horizontal offset (2 bytes)
/// - Vertical offset (2 bytes)
///
/// Example:
/// ```swift
/// let reg = J2KCodestreamRegistrationBox.Registration(
///     codestreamIndex: 0,
///     horizontalOffset: 0,
///     verticalOffset: 0
/// )
/// let box = J2KCodestreamRegistrationBox(
///     horizontalGridSize: 1920,
///     verticalGridSize: 1080,
///     registrations: [reg]
/// )
/// let data = try box.write()
/// ```
public struct J2KCodestreamRegistrationBox: J2KBox, Sendable {
    /// A single codestream-to-grid registration.
    public struct Registration: Sendable, Equatable {
        /// Index of the codestream.
        public var codestreamIndex: UInt16

        /// Horizontal offset on the reference grid.
        public var horizontalOffset: UInt16

        /// Vertical offset on the reference grid.
        public var verticalOffset: UInt16

        /// Creates a registration entry.
        ///
        /// - Parameters:
        ///   - codestreamIndex: Codestream index.
        ///   - horizontalOffset: Horizontal offset.
        ///   - verticalOffset: Vertical offset.
        public init(
            codestreamIndex: UInt16,
            horizontalOffset: UInt16 = 0,
            verticalOffset: UInt16 = 0
        ) {
            self.codestreamIndex = codestreamIndex
            self.horizontalOffset = horizontalOffset
            self.verticalOffset = verticalOffset
        }
    }

    /// Reference grid width.
    public var horizontalGridSize: UInt16

    /// Reference grid height.
    public var verticalGridSize: UInt16

    /// Array of codestream registrations.
    public var registrations: [Registration]

    public var boxType: J2KBoxType {
        .creg
    }

    /// Creates a codestream registration box.
    ///
    /// - Parameters:
    ///   - horizontalGridSize: Reference grid width.
    ///   - verticalGridSize: Reference grid height.
    ///   - registrations: Array of registration entries.
    public init(
        horizontalGridSize: UInt16,
        verticalGridSize: UInt16,
        registrations: [Registration] = []
    ) {
        self.horizontalGridSize = horizontalGridSize
        self.verticalGridSize = verticalGridSize
        self.registrations = registrations
    }

    public func write() throws -> Data {
        guard registrations.count <= UInt16.max else {
            throw J2KError.fileFormatError(
                "Too many registrations: \(registrations.count), maximum is \(UInt16.max)"
            )
        }

        var output = Data()
        output.reserveCapacity(6 + registrations.count * 6)

        // Horizontal grid size (2 bytes)
        output.append(UInt8((horizontalGridSize >> 8) & 0xFF))
        output.append(UInt8(horizontalGridSize & 0xFF))

        // Vertical grid size (2 bytes)
        output.append(UInt8((verticalGridSize >> 8) & 0xFF))
        output.append(UInt8(verticalGridSize & 0xFF))

        // Registration count (2 bytes)
        let count = UInt16(registrations.count)
        output.append(UInt8((count >> 8) & 0xFF))
        output.append(UInt8(count & 0xFF))

        // Write registrations
        for reg in registrations {
            output.append(UInt8((reg.codestreamIndex >> 8) & 0xFF))
            output.append(UInt8(reg.codestreamIndex & 0xFF))
            output.append(UInt8((reg.horizontalOffset >> 8) & 0xFF))
            output.append(UInt8(reg.horizontalOffset & 0xFF))
            output.append(UInt8((reg.verticalOffset >> 8) & 0xFF))
            output.append(UInt8(reg.verticalOffset & 0xFF))
        }

        return output
    }

    public mutating func read(from data: Data) throws {
        guard data.count >= 6 else {
            throw J2KError.fileFormatError(
                "Invalid codestream registration box length: \(data.count), expected at least 6"
            )
        }

        // Horizontal grid size (2 bytes)
        self.horizontalGridSize = UInt16(data[0]) << 8 | UInt16(data[1])

        // Vertical grid size (2 bytes)
        self.verticalGridSize = UInt16(data[2]) << 8 | UInt16(data[3])

        // Registration count (2 bytes)
        let count = UInt16(data[4]) << 8 | UInt16(data[5])

        let expectedSize = 6 + Int(count) * 6
        guard data.count >= expectedSize else {
            throw J2KError.fileFormatError(
                "Invalid codestream registration box length: \(data.count), expected at least \(expectedSize)"
            )
        }

        var offset = 6
        var result: [Registration] = []
        result.reserveCapacity(Int(count))

        for _ in 0..<count {
            let csIndex = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            offset += 2
            let hOff = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            offset += 2
            let vOff = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            offset += 2

            result.append(Registration(
                codestreamIndex: csIndex,
                horizontalOffset: hOff,
                verticalOffset: vOff
            ))
        }

        self.registrations = result
    }
}

// MARK: - J2KCompositionLayerHeaderBox

/// Compositing layer header box.
///
/// The compositing layer header box ('jplh') is a super-box that contains
/// layer-specific metadata including color specifications, opacity settings,
/// codestream registration, and labels.
///
/// ## Box Structure
///
/// - Type: 'jplh' (0x6A706C68)
/// - Length: Variable
/// - Content: Sub-boxes including:
///   - 'colr': Color specification boxes
///   - 'opct': Opacity box (optional)
///   - 'creg': Codestream registration box (optional)
///   - 'lbl ': Label boxes (optional)
///
/// Example:
/// ```swift
/// let colorSpec = J2KColorSpecificationBox(
///     method: .enumerated(.sRGB),
///     precedence: 0,
///     approximation: 0
/// )
/// let header = J2KCompositionLayerHeaderBox(
///     colorSpecs: [colorSpec],
///     opacity: J2KOpacityBox(opacityType: .globalValue, opacity: 200)
/// )
/// let data = try header.write()
/// ```
public struct J2KCompositionLayerHeaderBox: J2KBox, Sendable {
    /// Color space specifications for this layer.
    public var colorSpecs: [J2KColorSpecificationBox]

    /// Optional opacity specification.
    public var opacity: J2KOpacityBox?

    /// Optional codestream registration.
    public var registration: J2KCodestreamRegistrationBox?

    /// Optional labels.
    public var labels: [J2KLabelBox]

    public var boxType: J2KBoxType {
        .jplh
    }

    /// Creates a compositing layer header box.
    ///
    /// - Parameters:
    ///   - colorSpecs: Color specifications (default: empty).
    ///   - opacity: Opacity box (default: nil).
    ///   - registration: Codestream registration (default: nil).
    ///   - labels: Label boxes (default: empty).
    public init(
        colorSpecs: [J2KColorSpecificationBox] = [],
        opacity: J2KOpacityBox? = nil,
        registration: J2KCodestreamRegistrationBox? = nil,
        labels: [J2KLabelBox] = []
    ) {
        self.colorSpecs = colorSpecs
        self.opacity = opacity
        self.registration = registration
        self.labels = labels
    }

    public func write() throws -> Data {
        var writer = J2KBoxWriter()

        for colorSpec in colorSpecs {
            try writer.writeBox(colorSpec)
        }
        if let opacity = opacity {
            try writer.writeBox(opacity)
        }
        if let registration = registration {
            try writer.writeBox(registration)
        }
        for label in labels {
            try writer.writeBox(label)
        }

        return writer.data
    }

    public mutating func read(from data: Data) throws {
        colorSpecs = []
        opacity = nil
        registration = nil
        labels = []

        var reader = J2KBoxReader(data: data)
        while let boxInfo = try reader.readNextBox() {
            let content = reader.extractContent(from: boxInfo)

            switch boxInfo.type {
            case .colr:
                var colr = J2KColorSpecificationBox(
                    method: .enumerated(.sRGB),
                    precedence: 0,
                    approximation: 0
                )
                try colr.read(from: content)
                colorSpecs.append(colr)
            case .opct:
                var opct = J2KOpacityBox()
                try opct.read(from: content)
                self.opacity = opct
            case .creg:
                var creg = J2KCodestreamRegistrationBox(
                    horizontalGridSize: 0,
                    verticalGridSize: 0
                )
                try creg.read(from: content)
                self.registration = creg
            case .lbl:
                var lbl = try J2KLabelBox(label: "")
                try lbl.read(from: content)
                labels.append(lbl)
            default:
                break
            }
        }
    }
}

// MARK: - J2KJPXAnimationSequence

/// High-level API for building JPX animation sequences.
///
/// Provides a convenient interface for constructing frame-based animations
/// that can be converted into the underlying composition and instruction set
/// box representations.
///
/// Example:
/// ```swift
/// var animation = J2KJPXAnimationSequence(
///     width: 800,
///     height: 600,
///     timing: .milliseconds(duration: 3000, loops: 0)
/// )
/// animation.addFrame(codestreamIndex: 0, duration: 100)
/// animation.addFrame(codestreamIndex: 1, duration: 100)
///
/// let compositionBox = animation.toCompositionBox()
/// let instructionBox = animation.toInstructionSetBox()
/// ```
public struct J2KJPXAnimationSequence: Sendable {
    /// Canvas width in pixels.
    public var width: UInt32

    /// Canvas height in pixels.
    public var height: UInt32

    /// Animation timing configuration.
    public var timing: J2KAnimationTiming

    /// Ordered list of animation frames.
    public var frames: [J2KAnimationFrame]

    /// Optional background color as (r, g, b).
    public var backgroundColor: (r: UInt8, g: UInt8, b: UInt8)?

    /// Sum of all frame durations in timescale ticks.
    public var totalDuration: UInt64 {
        frames.reduce(0) { $0 + UInt64($1.duration) }
    }

    /// Number of frames in the animation.
    public var frameCount: Int {
        frames.count
    }

    /// Creates a new animation sequence.
    ///
    /// - Parameters:
    ///   - width: Canvas width in pixels.
    ///   - height: Canvas height in pixels.
    ///   - timing: Animation timing configuration.
    public init(width: UInt32, height: UInt32, timing: J2KAnimationTiming) {
        self.width = width
        self.height = height
        self.timing = timing
        self.frames = []
        self.backgroundColor = nil
    }

    /// Appends a fully configured frame.
    ///
    /// - Parameter frame: The animation frame to add.
    public mutating func addFrame(_ frame: J2KAnimationFrame) {
        frames.append(frame)
    }

    /// Appends a simple frame referencing a codestream with a duration.
    ///
    /// - Parameters:
    ///   - codestreamIndex: Codestream to display.
    ///   - duration: Frame duration in timescale ticks.
    public mutating func addFrame(codestreamIndex: UInt16, duration: UInt32) {
        frames.append(J2KAnimationFrame(
            codestreamIndex: codestreamIndex,
            compositionLayerIndex: codestreamIndex,
            duration: duration
        ))
    }

    /// Converts the animation into a ``J2KCompositionBox``.
    ///
    /// Each frame becomes a ``J2KCompositionInstruction`` positioned on the canvas.
    ///
    /// - Returns: A composition box representing this animation.
    public func toCompositionBox() -> J2KCompositionBox {
        let instructions = frames.map { frame in
            J2KCompositionInstruction(
                width: frame.width > 0 ? frame.width : width,
                height: frame.height > 0 ? frame.height : height,
                horizontalOffset: frame.x,
                verticalOffset: frame.y,
                codestreamIndex: frame.codestreamIndex
            )
        }
        let loopCount = timing.loopCount <= UInt32(UInt16.max)
            ? UInt16(timing.loopCount)
            : 0
        return J2KCompositionBox(
            width: width,
            height: height,
            instructions: instructions,
            loopCount: loopCount
        )
    }

    /// Converts the animation into a ``J2KInstructionSetBox``.
    ///
    /// - Returns: An instruction set box with animate-type entries.
    public func toInstructionSetBox() -> J2KInstructionSetBox {
        let entries = frames.map { frame in
            J2KInstructionSetBox.InstructionEntry(
                layerIndex: frame.compositionLayerIndex,
                horizontalOffset: Int32(frame.x),
                verticalOffset: Int32(frame.y),
                persistenceFlag: false
            )
        }
        let repeatCount = timing.loopCount <= UInt32(UInt16.max)
            ? UInt16(timing.loopCount)
            : 0
        return J2KInstructionSetBox(
            instructionType: .animate,
            repeatCount: repeatCount,
            tickDuration: timing.timescale,
            instructions: entries
        )
    }

    /// Validates the animation sequence for consistency.
    ///
    /// - Throws: ``J2KError/fileFormatError(_:)`` if validation fails.
    public func validate() throws {
        guard !frames.isEmpty else {
            throw J2KError.fileFormatError("Animation sequence must contain at least one frame")
        }
        guard width > 0 && height > 0 else {
            throw J2KError.fileFormatError("Animation canvas dimensions must be greater than zero")
        }
        guard timing.timescale > 0 else {
            throw J2KError.fileFormatError("Animation timescale must be greater than zero")
        }
    }
}

// MARK: - J2KMultiLayerCompositor

/// Multi-layer compositing builder for JPX files.
///
/// Provides a high-level interface for positioning and blending multiple
/// codestreams on a shared canvas, converting the result into the
/// corresponding box-level structures.
///
/// Example:
/// ```swift
/// var compositor = J2KMultiLayerCompositor(canvasWidth: 1920, canvasHeight: 1080)
/// compositor.addLayer(
///     codestreamIndex: 0,
///     x: 0, y: 0,
///     width: 960, height: 1080,
///     opacity: 255,
///     compositingMode: .replace
/// )
/// compositor.addLayer(
///     codestreamIndex: 1,
///     x: 960, y: 0,
///     width: 960, height: 1080,
///     opacity: 200,
///     compositingMode: .alphaBlend
/// )
///
/// let compositionBox = compositor.toCompositionBox()
/// let headers = compositor.toLayerHeaders()
/// ```
public struct J2KMultiLayerCompositor: Sendable {
    /// A single layer in the multi-layer composition.
    public struct CompositorLayer: Sendable, Equatable {
        /// Index of the codestream used by this layer.
        public var codestreamIndex: UInt16

        /// Horizontal position on the canvas.
        public var x: UInt32

        /// Vertical position on the canvas.
        public var y: UInt32

        /// Layer width (0 = use natural codestream width).
        public var width: UInt32

        /// Layer height (0 = use natural codestream height).
        public var height: UInt32

        /// Opacity from 0 (transparent) to 255 (fully opaque).
        public var opacity: UInt8

        /// How this layer blends with layers below it.
        public var compositingMode: J2KCompositionInstruction.CompositingMode

        /// Optional human-readable label.
        public var label: String?

        /// Creates a compositor layer.
        ///
        /// - Parameters:
        ///   - codestreamIndex: Codestream index.
        ///   - x: Horizontal position (default: 0).
        ///   - y: Vertical position (default: 0).
        ///   - width: Layer width (default: 0).
        ///   - height: Layer height (default: 0).
        ///   - opacity: Opacity (default: 255).
        ///   - compositingMode: Blend mode (default: replace).
        ///   - label: Optional label (default: nil).
        public init(
            codestreamIndex: UInt16,
            x: UInt32 = 0,
            y: UInt32 = 0,
            width: UInt32 = 0,
            height: UInt32 = 0,
            opacity: UInt8 = 255,
            compositingMode: J2KCompositionInstruction.CompositingMode = .replace,
            label: String? = nil
        ) {
            self.codestreamIndex = codestreamIndex
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.opacity = opacity
            self.compositingMode = compositingMode
            self.label = label
        }
    }

    /// Canvas width in pixels.
    public var canvasWidth: UInt32

    /// Canvas height in pixels.
    public var canvasHeight: UInt32

    /// Ordered list of composition layers (bottom to top).
    public var layers: [CompositorLayer]

    /// Creates a multi-layer compositor.
    ///
    /// - Parameters:
    ///   - canvasWidth: Canvas width in pixels.
    ///   - canvasHeight: Canvas height in pixels.
    public init(canvasWidth: UInt32, canvasHeight: UInt32) {
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.layers = []
    }

    /// Appends a fully configured layer.
    ///
    /// - Parameter layer: The compositor layer to add.
    public mutating func addLayer(_ layer: CompositorLayer) {
        layers.append(layer)
    }

    /// Appends a layer with explicit parameters.
    ///
    /// - Parameters:
    ///   - codestreamIndex: Codestream index.
    ///   - x: Horizontal position.
    ///   - y: Vertical position.
    ///   - width: Layer width.
    ///   - height: Layer height.
    ///   - opacity: Opacity (0–255).
    ///   - compositingMode: Blend mode.
    public mutating func addLayer(
        codestreamIndex: UInt16,
        x: UInt32,
        y: UInt32,
        width: UInt32,
        height: UInt32,
        opacity: UInt8,
        compositingMode: J2KCompositionInstruction.CompositingMode
    ) {
        layers.append(CompositorLayer(
            codestreamIndex: codestreamIndex,
            x: x,
            y: y,
            width: width,
            height: height,
            opacity: opacity,
            compositingMode: compositingMode
        ))
    }

    /// Converts the compositor into a ``J2KCompositionBox``.
    ///
    /// - Returns: A composition box with one instruction per layer.
    public func toCompositionBox() -> J2KCompositionBox {
        let instructions = layers.map { layer in
            J2KCompositionInstruction(
                width: layer.width > 0 ? layer.width : canvasWidth,
                height: layer.height > 0 ? layer.height : canvasHeight,
                horizontalOffset: layer.x,
                verticalOffset: layer.y,
                codestreamIndex: layer.codestreamIndex,
                compositingMode: layer.compositingMode
            )
        }
        return J2KCompositionBox(
            width: canvasWidth,
            height: canvasHeight,
            instructions: instructions
        )
    }

    /// Generates a ``J2KCompositionLayerHeaderBox`` for each layer.
    ///
    /// Each header includes an sRGB color specification, an opacity box
    /// (when opacity is not fully opaque), and a label box (when a label
    /// is provided).
    ///
    /// - Returns: An array of layer header boxes.
    public func toLayerHeaders() -> [J2KCompositionLayerHeaderBox] {
        layers.map { layer in
            let colorSpec = J2KColorSpecificationBox(
                method: .enumerated(.sRGB),
                precedence: 0,
                approximation: 0
            )

            let opacityBox: J2KOpacityBox? = layer.opacity < 255
                ? J2KOpacityBox(opacityType: .globalValue, opacity: layer.opacity)
                : nil

            var labels: [J2KLabelBox] = []
            if let labelText = layer.label, let lbl = try? J2KLabelBox(label: labelText) {
                labels.append(lbl)
            }

            return J2KCompositionLayerHeaderBox(
                colorSpecs: [colorSpec],
                opacity: opacityBox,
                labels: labels
            )
        }
    }

    /// Validates the compositor for consistency.
    ///
    /// - Throws: ``J2KError/fileFormatError(_:)`` if validation fails.
    public func validate() throws {
        guard !layers.isEmpty else {
            throw J2KError.fileFormatError("Compositor must contain at least one layer")
        }
        guard canvasWidth > 0 && canvasHeight > 0 else {
            throw J2KError.fileFormatError("Canvas dimensions must be greater than zero")
        }
    }
}
