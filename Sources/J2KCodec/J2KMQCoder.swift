/// # MQ-Coder
///
/// Implementation of the MQ arithmetic coder used in JPEG 2000 entropy coding.
///
/// The MQ-coder is a context-adaptive binary arithmetic coder used in JPEG 2000's
/// EBCOT (Embedded Block Coding with Optimized Truncation) algorithm. It provides
/// efficient compression by adapting probability estimates based on context.

import Foundation
import J2KCore

// MARK: - MQ State Table

/// Represents a single entry in the MQ-coder probability estimation table.
public struct MQState: Sendable, Equatable {
    /// The probability estimate for the less probable symbol (Qe value).
    public let qe: UInt32
    
    /// The next state index after encoding/decoding the most probable symbol (MPS).
    public let nextMPS: Int
    
    /// The next state index after encoding/decoding the least probable symbol (LPS).
    public let nextLPS: Int
    
    /// Whether to switch the MPS sense after an LPS event.
    public let switchMPS: Bool
}

/// The MQ-coder probability estimation state table (47 states).
public let mqStateTable: [MQState] = [
    MQState(qe: 0x5601, nextMPS: 1, nextLPS: 1, switchMPS: true),
    MQState(qe: 0x3401, nextMPS: 2, nextLPS: 6, switchMPS: false),
    MQState(qe: 0x1801, nextMPS: 3, nextLPS: 9, switchMPS: false),
    MQState(qe: 0x0AC1, nextMPS: 4, nextLPS: 12, switchMPS: false),
    MQState(qe: 0x0521, nextMPS: 5, nextLPS: 29, switchMPS: false),
    MQState(qe: 0x0221, nextMPS: 38, nextLPS: 33, switchMPS: false),
    MQState(qe: 0x5601, nextMPS: 7, nextLPS: 6, switchMPS: true),
    MQState(qe: 0x5401, nextMPS: 8, nextLPS: 14, switchMPS: false),
    MQState(qe: 0x4801, nextMPS: 9, nextLPS: 14, switchMPS: false),
    MQState(qe: 0x3801, nextMPS: 10, nextLPS: 14, switchMPS: false),
    MQState(qe: 0x3001, nextMPS: 11, nextLPS: 17, switchMPS: false),
    MQState(qe: 0x2401, nextMPS: 12, nextLPS: 18, switchMPS: false),
    MQState(qe: 0x1C01, nextMPS: 13, nextLPS: 20, switchMPS: false),
    MQState(qe: 0x1601, nextMPS: 29, nextLPS: 21, switchMPS: false),
    MQState(qe: 0x5601, nextMPS: 15, nextLPS: 14, switchMPS: true),
    MQState(qe: 0x5401, nextMPS: 16, nextLPS: 14, switchMPS: false),
    MQState(qe: 0x5101, nextMPS: 17, nextLPS: 15, switchMPS: false),
    MQState(qe: 0x4801, nextMPS: 18, nextLPS: 16, switchMPS: false),
    MQState(qe: 0x3801, nextMPS: 19, nextLPS: 17, switchMPS: false),
    MQState(qe: 0x3401, nextMPS: 20, nextLPS: 18, switchMPS: false),
    MQState(qe: 0x3001, nextMPS: 21, nextLPS: 19, switchMPS: false),
    MQState(qe: 0x2801, nextMPS: 22, nextLPS: 19, switchMPS: false),
    MQState(qe: 0x2401, nextMPS: 23, nextLPS: 20, switchMPS: false),
    MQState(qe: 0x2201, nextMPS: 24, nextLPS: 21, switchMPS: false),
    MQState(qe: 0x1C01, nextMPS: 25, nextLPS: 22, switchMPS: false),
    MQState(qe: 0x1801, nextMPS: 26, nextLPS: 23, switchMPS: false),
    MQState(qe: 0x1601, nextMPS: 27, nextLPS: 24, switchMPS: false),
    MQState(qe: 0x1401, nextMPS: 28, nextLPS: 25, switchMPS: false),
    MQState(qe: 0x1201, nextMPS: 29, nextLPS: 26, switchMPS: false),
    MQState(qe: 0x1101, nextMPS: 30, nextLPS: 27, switchMPS: false),
    MQState(qe: 0x0AC1, nextMPS: 31, nextLPS: 28, switchMPS: false),
    MQState(qe: 0x09C1, nextMPS: 32, nextLPS: 29, switchMPS: false),
    MQState(qe: 0x08A1, nextMPS: 33, nextLPS: 30, switchMPS: false),
    MQState(qe: 0x0521, nextMPS: 34, nextLPS: 31, switchMPS: false),
    MQState(qe: 0x0441, nextMPS: 35, nextLPS: 32, switchMPS: false),
    MQState(qe: 0x02A1, nextMPS: 36, nextLPS: 33, switchMPS: false),
    MQState(qe: 0x0221, nextMPS: 37, nextLPS: 34, switchMPS: false),
    MQState(qe: 0x0141, nextMPS: 38, nextLPS: 35, switchMPS: false),
    MQState(qe: 0x0111, nextMPS: 39, nextLPS: 36, switchMPS: false),
    MQState(qe: 0x0085, nextMPS: 40, nextLPS: 37, switchMPS: false),
    MQState(qe: 0x0049, nextMPS: 41, nextLPS: 38, switchMPS: false),
    MQState(qe: 0x0025, nextMPS: 42, nextLPS: 39, switchMPS: false),
    MQState(qe: 0x0015, nextMPS: 43, nextLPS: 40, switchMPS: false),
    MQState(qe: 0x0009, nextMPS: 44, nextLPS: 41, switchMPS: false),
    MQState(qe: 0x0005, nextMPS: 45, nextLPS: 42, switchMPS: false),
    MQState(qe: 0x0001, nextMPS: 45, nextLPS: 43, switchMPS: false),
    MQState(qe: 0x5601, nextMPS: 46, nextLPS: 46, switchMPS: false)
]

// MARK: - MQ Context

/// Represents a context used by the MQ-coder.
public struct MQContext: Sendable {
    /// The current index into the state table.
    public var stateIndex: Int
    
    /// The current most probable symbol (0 or 1).
    public var mps: Bool
    
    /// Creates a new context with the specified initial state.
    public init(stateIndex: Int = 0, mps: Bool = false) {
        self.stateIndex = stateIndex
        self.mps = mps
    }
    
    /// Creates a new context (UInt8 compatibility).
    public init(stateIndex: UInt8, mps: Bool = false) {
        self.stateIndex = Int(stateIndex)
        self.mps = mps
    }
    
    /// Returns the current state from the state table.
    public var state: MQState {
        return mqStateTable[stateIndex]
    }
    
    /// Returns the current Qe value.
    public var qe: UInt32 {
        return state.qe
    }
}

// MARK: - MQ Encoder

/// Encodes binary symbols using the MQ arithmetic coding algorithm.
public struct MQEncoder: Sendable {
    private var c: UInt32 = 0
    private var a: UInt32 = 0x8000
    private var ct: Int = 12
    private var buffer: Int = -1
    private var output: [UInt8] = []
    
    /// Creates a new MQ encoder.
    public init() {
        output.reserveCapacity(1024)
    }
    
    /// Encodes a binary symbol using the specified context.
    public mutating func encode(symbol: Bool, context: inout MQContext) {
        let state = context.state
        let qe = state.qe
        
        a -= qe
        
        if symbol == context.mps {
            // MPS
            if a < 0x8000 {
                if a < qe {
                    c += a
                    a = qe
                }
                context.stateIndex = state.nextMPS
                renormalize()
            }
        } else {
            // LPS
            if a >= qe {
                c += a
                a = qe
            }
            if state.switchMPS {
                context.mps = !context.mps
            }
            context.stateIndex = state.nextLPS
            renormalize()
        }
    }
    
    /// Encodes a symbol using uniform (bypass) coding.
    public mutating func encodeBypass(symbol: Bool) {
        c <<= 1
        if symbol {
            c += a
        }
        ct -= 1
        if ct == 0 {
            emitByte()
        }
    }
    
    /// Renormalizes the encoder state.
    private mutating func renormalize() {
        while a < 0x8000 {
            a <<= 1
            c <<= 1
            ct -= 1
            if ct == 0 {
                emitByte()
            }
        }
    }
    
    /// Emits a byte to the output.
    private mutating func emitByte() {
        if buffer >= 0 {
            if c > 0x07FFFFFF {
                buffer += 1
                if buffer == 0xFF {
                    output.append(0xFF)
                    buffer = Int((c >> 20) & 0x7F)
                    c &= 0x000FFFFF
                    ct = 7
                } else if buffer > 0xFF {
                    // Carry overflow - this should not happen in normal operation
                    // Handle by emitting 0xFF and adjusting
                    output.append(0xFF)
                    buffer = Int((c >> 20) & 0x7F)
                    c &= 0x000FFFFF
                    ct = 7
                } else {
                    output.append(UInt8(buffer & 0xFF))
                    buffer = Int((c >> 19) & 0xFF)
                    c &= 0x0007FFFF
                    ct = 8
                }
            } else {
                output.append(UInt8(buffer & 0xFF))
                if buffer == 0xFF {
                    buffer = Int((c >> 20) & 0x7F)
                    c &= 0x000FFFFF
                    ct = 7
                } else {
                    buffer = Int((c >> 19) & 0xFF)
                    c &= 0x0007FFFF
                    ct = 8
                }
            }
        } else {
            buffer = Int((c >> 19) & 0xFF)
            c &= 0x0007FFFF
            ct = 8
        }
    }
    
    /// Finishes encoding and returns the compressed data.
    public mutating func finish() -> Data {
        // Flush
        c += a
        c <<= ct
        emitByte()
        c <<= ct
        emitByte()
        
        if buffer >= 0 && buffer <= 0xFF && buffer != 0xFF {
            output.append(UInt8(buffer & 0xFF))
        }
        
        return Data(output)
    }
    
    /// Resets the encoder to its initial state.
    public mutating func reset() {
        c = 0
        a = 0x8000
        ct = 12
        buffer = -1
        output.removeAll(keepingCapacity: true)
    }
    
    /// Returns the current size of the encoded data.
    public var encodedSize: Int {
        return output.count + (buffer >= 0 ? 1 : 0)
    }
}

// MARK: - MQ Decoder

/// Decodes binary symbols using the MQ arithmetic coding algorithm.
public struct MQDecoder: Sendable {
    private var c: UInt32 = 0
    private var a: UInt32 = 0x8000
    private var ct: Int = 0
    private let data: Data
    private var position: Int = 0
    private var buffer: UInt8 = 0
    private var nextBuffer: UInt8 = 0
    
    /// Creates a new MQ decoder with the specified compressed data.
    public init(data: Data) {
        self.data = data
        initializeDecoder()
    }
    
    /// Initializes the decoder state.
    private mutating func initializeDecoder() {
        buffer = readByte()
        c = UInt32(buffer) << 16
        fillC()
        c <<= 7
        ct -= 7
        a = 0x8000
    }
    
    /// Reads a byte from the input.
    private mutating func readByte() -> UInt8 {
        if position < data.count {
            let b = data[position]
            position += 1
            return b
        }
        return 0xFF
    }
    
    /// Fills the C register with more data.
    private mutating func fillC() {
        if buffer == 0xFF {
            nextBuffer = readByte()
            if nextBuffer > 0x8F {
                // Marker - don't advance, stuff zeros
                c += 0xFF00
                ct = 8
                position -= 1
            } else {
                c += UInt32(nextBuffer) << 9
                buffer = nextBuffer
                ct = 7
            }
        } else {
            buffer = readByte()
            c += UInt32(buffer) << 8
            ct = 8
        }
    }
    
    /// Decodes a binary symbol using the specified context.
    public mutating func decode(context: inout MQContext) -> Bool {
        let state = context.state
        let qe = state.qe
        
        a -= qe
        
        let mps = context.mps
        var symbol: Bool
        
        if (c >> 16) < a {
            // MPS region
            if a < 0x8000 {
                if a < qe {
                    // Conditional exchange
                    symbol = !mps
                    if state.switchMPS {
                        context.mps = !context.mps
                    }
                    context.stateIndex = state.nextLPS
                } else {
                    symbol = mps
                    context.stateIndex = state.nextMPS
                }
                renormalizeDecoder()
            } else {
                symbol = mps
            }
        } else {
            // LPS region
            c -= a << 16
            if a < qe {
                // Conditional exchange
                symbol = mps
                context.stateIndex = state.nextMPS
            } else {
                symbol = !mps
                if state.switchMPS {
                    context.mps = !context.mps
                }
                context.stateIndex = state.nextLPS
            }
            a = qe
            renormalizeDecoder()
        }
        
        return symbol
    }
    
    /// Decodes a symbol using uniform (bypass) coding.
    public mutating func decodeBypass() -> Bool {
        if ct == 0 {
            fillC()
        }
        ct -= 1
        c <<= 1
        
        if (c >> 16) >= a {
            c -= a << 16
            return true
        }
        return false
    }
    
    /// Renormalizes the decoder state.
    private mutating func renormalizeDecoder() {
        while a < 0x8000 {
            if ct == 0 {
                fillC()
            }
            a <<= 1
            c <<= 1
            ct -= 1
        }
    }
    
    /// Resets the decoder.
    public mutating func reset() {
        position = 0
        c = 0
        a = 0x8000
        ct = 0
        buffer = 0
        initializeDecoder()
    }
    
    /// Returns true if at end of data.
    public var isAtEnd: Bool {
        return position >= data.count && ct == 0
    }
    
    /// Returns the current position.
    public var currentPosition: Int {
        return position
    }
}
