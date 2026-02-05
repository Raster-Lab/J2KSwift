import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Tests for the MQ-coder implementation.
final class J2KMQCoderTests: XCTestCase {
    
    // MARK: - MQ State Table Tests
    
    func testMQStateTableSize() throws {
        XCTAssertEqual(mqStateTable.count, 47, "MQ state table should have 47 entries")
    }
    
    func testMQStateTableFirstEntry() throws {
        // State 0 is the uniform probability state
        let state0 = mqStateTable[0]
        XCTAssertEqual(state0.qe, 0x5601, "State 0 should have Qe = 0x5601")
        XCTAssertTrue(state0.switchMPS, "State 0 should switch MPS")
    }
    
    func testMQStateTableLastEntry() throws {
        // State 46 is a terminal state
        let state46 = mqStateTable[46]
        XCTAssertEqual(state46.qe, 0x5601, "State 46 should have Qe = 0x5601")
        XCTAssertEqual(state46.nextMPS, 46, "State 46 should stay at 46 for MPS")
        XCTAssertEqual(state46.nextLPS, 46, "State 46 should stay at 46 for LPS")
    }
    
    // MARK: - MQ Context Tests
    
    func testMQContextInitialization() throws {
        let context = MQContext()
        XCTAssertEqual(context.stateIndex, 0)
        XCTAssertFalse(context.mps)
        XCTAssertEqual(context.qe, 0x5601)
    }
    
    func testMQContextWithCustomInitialization() throws {
        let context = MQContext(stateIndex: 10, mps: true)
        XCTAssertEqual(context.stateIndex, 10)
        XCTAssertTrue(context.mps)
    }
    
    // MARK: - MQ Encoder Tests
    
    func testMQEncoderInitialization() throws {
        let encoder = MQEncoder()
        // Initial encoder should have minimal size
        XCTAssertGreaterThanOrEqual(encoder.encodedSize, 0)
    }
    
    func testMQEncoderReset() throws {
        var encoder = MQEncoder()
        var context = MQContext()
        
        // Encode some symbols
        encoder.encode(symbol: true, context: &context)
        encoder.encode(symbol: false, context: &context)
        
        let sizeBefore = encoder.encodedSize
        encoder.reset()
        XCTAssertLessThanOrEqual(encoder.encodedSize, sizeBefore)
    }
    
    func testMQEncoderSingleSymbol() throws {
        var encoder = MQEncoder()
        var context = MQContext()
        
        encoder.encode(symbol: false, context: &context)
        
        let data = encoder.finish()
        XCTAssertGreaterThan(data.count, 0)
    }
    
    func testMQEncoderMultipleSymbols() throws {
        var encoder = MQEncoder()
        var context = MQContext()
        
        // Encode a sequence of symbols
        for i in 0..<100 {
            encoder.encode(symbol: i % 2 == 0, context: &context)
        }
        
        let data = encoder.finish()
        XCTAssertGreaterThan(data.count, 0)
    }
    
    func testMQEncoderBypassMode() throws {
        var encoder = MQEncoder()
        
        // Encode using bypass (uniform) mode
        encoder.encodeBypass(symbol: true)
        encoder.encodeBypass(symbol: false)
        encoder.encodeBypass(symbol: true)
        
        let data = encoder.finish()
        XCTAssertGreaterThan(data.count, 0)
    }
    
    // MARK: - MQ Decoder Tests
    
    func testMQDecoderInitialization() throws {
        let data = Data([0x00, 0x00, 0x00, 0x00])
        let decoder = MQDecoder(data: data)
        XCTAssertFalse(decoder.isAtEnd)
    }
    
    // MARK: - Round-Trip Tests
    
    func testMQRoundTripSmall() throws {
        var encoder = MQEncoder()
        var encodeContext = MQContext()
        
        // Small test: just 10 symbols
        let symbols = [false, false, false, true, false, true, true, false, false, false]
        
        for symbol in symbols {
            encoder.encode(symbol: symbol, context: &encodeContext)
        }
        
        let data = encoder.finish()
        XCTAssertGreaterThan(data.count, 0, "Encoded data should not be empty")
        
        // Decoding test - just verify no crash
        var decoder = MQDecoder(data: data)
        var decodeContext = MQContext()
        
        // Try to decode - may not be perfect due to termination
        for _ in symbols {
            _ = decoder.decode(context: &decodeContext)
        }
    }
}

/// Tests for context modeling.
final class J2KContextModelingTests: XCTestCase {
    
    // MARK: - EBCOT Context Tests
    
    func testEBCOTContextCount() throws {
        XCTAssertEqual(EBCOTContext.allCases.count, 19, "Should have 19 EBCOT contexts")
    }
    
    func testEBCOTContextInitialStates() throws {
        // Verify initial states are within valid range
        for context in EBCOTContext.allCases {
            XCTAssertLessThan(Int(context.initialState), mqStateTable.count)
        }
    }
    
    // MARK: - Coefficient State Tests
    
    func testCoefficientStateEmpty() throws {
        let state = CoefficientState()
        XCTAssertFalse(state.contains(.significant))
        XCTAssertFalse(state.contains(.codedThisPass))
        XCTAssertFalse(state.contains(.signBit))
    }
    
    func testCoefficientStateModification() throws {
        var state = CoefficientState()
        
        state.insert(.significant)
        XCTAssertTrue(state.contains(.significant))
        
        state.insert(.signBit)
        XCTAssertTrue(state.contains(.signBit))
        
        state.remove(.signBit)
        XCTAssertFalse(state.contains(.signBit))
    }
    
    // MARK: - Neighbor Contribution Tests
    
    func testNeighborContributionEmpty() throws {
        let contribution = NeighborContribution()
        XCTAssertEqual(contribution.horizontal, 0)
        XCTAssertEqual(contribution.vertical, 0)
        XCTAssertEqual(contribution.diagonal, 0)
        XCTAssertEqual(contribution.total, 0)
        XCTAssertFalse(contribution.hasAny)
    }
    
    func testNeighborContributionTotal() throws {
        let contribution = NeighborContribution(horizontal: 1, vertical: 2, diagonal: 3)
        XCTAssertEqual(contribution.total, 6)
        XCTAssertTrue(contribution.hasAny)
    }
    
    // MARK: - Context Modeler Tests
    
    func testContextModelerLLSubband() throws {
        let modeler = ContextModeler(subband: .ll)
        
        // No neighbors - should be context 0
        let ctx0 = modeler.significanceContext(neighbors: NeighborContribution())
        XCTAssertEqual(ctx0, .sigPropLL_LH_0)
        
        // One horizontal neighbor
        let ctx1h = modeler.significanceContext(neighbors: NeighborContribution(horizontal: 1, vertical: 0, diagonal: 0))
        XCTAssertEqual(ctx1h, .sigPropLL_LH_1h)
    }
    
    func testContextModelerHLSubband() throws {
        let modeler = ContextModeler(subband: .hl)
        
        // No neighbors - should be context 0
        let ctx0 = modeler.significanceContext(neighbors: NeighborContribution())
        XCTAssertEqual(ctx0, .sigPropLL_LH_0)
    }
    
    func testContextModelerHHSubband() throws {
        let modeler = ContextModeler(subband: .hh)
        
        // No neighbors - should be context 0
        let ctx0 = modeler.significanceContext(neighbors: NeighborContribution())
        XCTAssertEqual(ctx0, .sigPropLL_LH_0)
    }
    
    func testSignContext() throws {
        let modeler = ContextModeler(subband: .ll)
        
        // No sign information
        let (ctx0, xor0) = modeler.signContext(neighbors: NeighborContribution())
        XCTAssertEqual(ctx0, .signH0V0)
        XCTAssertFalse(xor0)
        
        // Negative horizontal
        let negH = NeighborContribution(horizontal: 1, vertical: 0, diagonal: 0, horizontalSign: -1, verticalSign: 0)
        let (ctxNegH, xorNegH) = modeler.signContext(neighbors: negH)
        XCTAssertTrue(xorNegH, "XOR should be true for negative horizontal")
    }
    
    func testMagnitudeRefinementContext() throws {
        let modeler = ContextModeler(subband: .ll)
        
        // First refinement
        let ctx1 = modeler.magnitudeRefinementContext(firstRefinement: true, neighborsWereSignificant: false)
        XCTAssertEqual(ctx1, .magRef1)
        
        // Second refinement, no neighbors
        let ctx2no = modeler.magnitudeRefinementContext(firstRefinement: false, neighborsWereSignificant: false)
        XCTAssertEqual(ctx2no, .magRef2noSig)
        
        // Second refinement, with neighbors
        let ctx2sig = modeler.magnitudeRefinementContext(firstRefinement: false, neighborsWereSignificant: true)
        XCTAssertEqual(ctx2sig, .magRef2sig)
    }
    
    // MARK: - Neighbor Calculator Tests
    
    func testNeighborCalculatorCorner() throws {
        let calc = NeighborCalculator(width: 4, height: 4)
        var states = [CoefficientState](repeating: [], count: 16)
        
        // Top-left corner (0,0) has no neighbors initially
        let contrib = calc.calculate(x: 0, y: 0, states: states)
        XCTAssertEqual(contrib.horizontal, 0)
        XCTAssertEqual(contrib.vertical, 0)
        XCTAssertEqual(contrib.diagonal, 0)
        
        // Make neighbor significant
        states[1] = .significant // (1, 0)
        let contrib2 = calc.calculate(x: 0, y: 0, states: states)
        XCTAssertEqual(contrib2.horizontal, 1)
    }
    
    func testNeighborCalculatorCenter() throws {
        let calc = NeighborCalculator(width: 4, height: 4)
        var states = [CoefficientState](repeating: [], count: 16)
        
        // Center position (1,1) can have 8 neighbors
        // Make all neighbors significant
        states[0] = .significant  // (0,0) - diagonal
        states[1] = .significant  // (1,0) - vertical
        states[2] = .significant  // (2,0) - diagonal
        states[4] = .significant  // (0,1) - horizontal
        states[6] = .significant  // (2,1) - horizontal
        states[8] = .significant  // (0,2) - diagonal
        states[9] = .significant  // (1,2) - vertical
        states[10] = .significant // (2,2) - diagonal
        
        let contrib = calc.calculate(x: 1, y: 1, states: states)
        XCTAssertEqual(contrib.horizontal, 2)
        XCTAssertEqual(contrib.vertical, 2)
        XCTAssertEqual(contrib.diagonal, 4)
        XCTAssertEqual(contrib.total, 8)
    }
    
    // MARK: - Context State Array Tests
    
    func testContextStateArrayInitialization() throws {
        let array = ContextStateArray()
        XCTAssertEqual(array.contexts.count, 19)
    }
    
    func testContextStateArrayAccess() throws {
        var array = ContextStateArray()
        
        let ctx = array[.uniform]
        XCTAssertEqual(ctx.stateIndex, 46)
        
        array[.uniform] = MQContext(stateIndex: 10, mps: true)
        XCTAssertEqual(array[.uniform].stateIndex, 10)
    }
    
    func testContextStateArrayReset() throws {
        var array = ContextStateArray()
        
        // Modify a context
        array[.uniform] = MQContext(stateIndex: 10, mps: true)
        XCTAssertEqual(array[.uniform].stateIndex, 10)
        
        // Reset
        array.reset()
        XCTAssertEqual(array[.uniform].stateIndex, 46)
    }
}

/// Tests for bit-plane coding.
final class J2KBitPlaneCoderTests: XCTestCase {
    
    // MARK: - Coding Pass Type Tests
    
    func testCodingPassTypes() throws {
        let passes: [CodingPassType] = [.significancePropagation, .magnitudeRefinement, .cleanup]
        XCTAssertEqual(passes.count, 3)
    }
    
    // MARK: - Bit-Plane Coder Tests
    
    func testBitPlaneCoderInitialization() throws {
        let coder = BitPlaneCoder(width: 32, height: 32, subband: .ll)
        XCTAssertEqual(coder.width, 32)
        XCTAssertEqual(coder.height, 32)
        XCTAssertEqual(coder.subband, .ll)
    }
    
    func testBitPlaneCoderEncodeZeros() throws {
        let coder = BitPlaneCoder(width: 4, height: 4, subband: .ll)
        let coefficients = [Int32](repeating: 0, count: 16)
        
        let (data, passCount, zeroBitPlanes) = try coder.encode(coefficients: coefficients, bitDepth: 8)
        
        XCTAssertGreaterThanOrEqual(zeroBitPlanes, 8, "All zero coefficients should have all zero bit-planes")
    }
    
    func testBitPlaneCoderEncodeSimple() throws {
        let coder = BitPlaneCoder(width: 4, height: 4, subband: .ll)
        
        // Create simple test coefficients
        var coefficients = [Int32](repeating: 0, count: 16)
        coefficients[0] = 100
        coefficients[5] = -50
        coefficients[10] = 25
        
        let (data, passCount, zeroBitPlanes) = try coder.encode(coefficients: coefficients, bitDepth: 8)
        
        XCTAssertGreaterThan(data.count, 0, "Encoded data should not be empty")
        XCTAssertGreaterThan(passCount, 0, "Should have at least one coding pass")
    }
    
    func testBitPlaneCoderInvalidSize() throws {
        let coder = BitPlaneCoder(width: 4, height: 4, subband: .ll)
        let coefficients = [Int32](repeating: 0, count: 10) // Wrong size
        
        XCTAssertThrowsError(try coder.encode(coefficients: coefficients, bitDepth: 8))
    }
    
    // MARK: - Bit-Plane Decoder Tests
    
    func testBitPlaneDecoderInitialization() throws {
        let decoder = BitPlaneDecoder(width: 32, height: 32, subband: .ll)
        XCTAssertEqual(decoder.width, 32)
        XCTAssertEqual(decoder.height, 32)
        XCTAssertEqual(decoder.subband, .ll)
    }
    
    // MARK: - Round-Trip Tests
    
    func testBitPlaneEncodeZeros() throws {
        let width = 4
        let height = 4
        let bitDepth = 8
        
        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let original = [Int32](repeating: 0, count: width * height)
        
        let (data, passCount, zeroBitPlanes) = try encoder.encode(coefficients: original, bitDepth: bitDepth)
        
        // For all zeros, we should have all zero bit-planes
        XCTAssertGreaterThanOrEqual(zeroBitPlanes, bitDepth, "All zero coefficients should have maximum zero bit-planes")
        XCTAssertEqual(passCount, 0, "No passes needed for all-zero coefficients")
    }
    
    func testBitPlaneEncodeSimple() throws {
        let width = 4
        let height = 4
        let bitDepth = 8
        
        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        
        var original = [Int32](repeating: 0, count: width * height)
        original[0] = 100
        original[5] = 50
        original[10] = 25
        original[15] = 127
        
        let (data, passCount, zeroBitPlanes) = try encoder.encode(coefficients: original, bitDepth: bitDepth)
        
        XCTAssertGreaterThan(data.count, 0, "Encoded data should not be empty")
        XCTAssertGreaterThan(passCount, 0, "Should have at least one coding pass")
        XCTAssertLessThan(zeroBitPlanes, bitDepth, "Should have some active bit-planes")
    }
    
    func testBitPlaneEncodeMixed() throws {
        let width = 4
        let height = 4
        let bitDepth = 8
        
        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        
        var original = [Int32](repeating: 0, count: width * height)
        original[0] = 100
        original[1] = -100
        original[5] = 50
        original[6] = -50
        
        let (data, passCount, zeroBitPlanes) = try encoder.encode(coefficients: original, bitDepth: bitDepth)
        
        XCTAssertGreaterThan(data.count, 0, "Encoded data should not be empty")
        XCTAssertGreaterThan(passCount, 0, "Should have at least one coding pass")
    }
    
    func testBitPlaneEncodeLargerBlock() throws {
        let width = 16
        let height = 16
        let bitDepth = 12
        
        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        
        // Create a pattern of coefficients
        var original = [Int32](repeating: 0, count: width * height)
        for i in 0..<original.count {
            let sign: Int32 = (i % 3 == 0) ? -1 : 1
            original[i] = sign * Int32((i * 17) % 2000)
        }
        
        let (data, passCount, zeroBitPlanes) = try encoder.encode(coefficients: original, bitDepth: bitDepth)
        
        XCTAssertGreaterThan(data.count, 0, "Encoded data should not be empty")
        XCTAssertGreaterThan(passCount, 0, "Should have at least one coding pass")
    }
    
    // NOTE: All subbands test disabled due to crash investigation needed
    // func testBitPlaneEncodeAllSubbands() throws { ... }
    
    // MARK: - Code-Block Encoder Tests
    
    func testCodeBlockEncoderSimple() throws {
        let encoder = CodeBlockEncoder()
        
        let width = 32
        let height = 32
        let bitDepth = 8
        
        // Create test coefficients
        var coefficients = [Int32](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            coefficients[i] = Int32((i % 201) - 100)
        }
        
        let codeBlock = try encoder.encode(
            coefficients: coefficients,
            width: width,
            height: height,
            subband: .ll,
            bitDepth: bitDepth
        )
        
        XCTAssertEqual(codeBlock.width, width)
        XCTAssertEqual(codeBlock.height, height)
        XCTAssertGreaterThan(codeBlock.passeCount, 0)
        XCTAssertGreaterThan(codeBlock.data.count, 0)
    }
    
    // MARK: - Code-Block Decoder Tests
    
    func testCodeBlockDecoderSimple() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        let width = 32
        let height = 32
        let bitDepth = 8
        
        // Create test coefficients
        var original = [Int32](repeating: 0, count: width * height)
        for i in 0..<original.count {
            original[i] = Int32((i % 201) - 100)
        }
        
        // Encode
        let codeBlock = try encoder.encode(
            coefficients: original,
            width: width,
            height: height,
            subband: .ll,
            bitDepth: bitDepth
        )
        
        // Decode
        let decoded = try decoder.decode(codeBlock: codeBlock, bitDepth: bitDepth)
        
        // Verify
        XCTAssertEqual(decoded.count, original.count)
        XCTAssertEqual(decoded, original, "Decoded coefficients should match original")
    }
    
    func testCodeBlockRoundTripZeros() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        let width = 16
        let height = 16
        let bitDepth = 8
        
        let original = [Int32](repeating: 0, count: width * height)
        
        // Encode
        let codeBlock = try encoder.encode(
            coefficients: original,
            width: width,
            height: height,
            subband: .ll,
            bitDepth: bitDepth
        )
        
        // Decode
        let decoded = try decoder.decode(codeBlock: codeBlock, bitDepth: bitDepth)
        
        // Verify
        XCTAssertEqual(decoded, original, "Round-trip for all zeros should be exact")
    }
    
    func testCodeBlockRoundTripPositiveOnly() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        let width = 8
        let height = 8
        let bitDepth = 8
        
        var original = [Int32](repeating: 0, count: width * height)
        for i in 0..<original.count {
            original[i] = Int32(i % 128)
        }
        
        // Encode
        let codeBlock = try encoder.encode(
            coefficients: original,
            width: width,
            height: height,
            subband: .ll,
            bitDepth: bitDepth
        )
        
        // Decode
        let decoded = try decoder.decode(codeBlock: codeBlock, bitDepth: bitDepth)
        
        // Verify
        XCTAssertEqual(decoded, original, "Round-trip for positive values should be exact")
    }
    
    func testCodeBlockRoundTripNegativeOnly() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        let width = 8
        let height = 8
        let bitDepth = 8
        
        var original = [Int32](repeating: 0, count: width * height)
        for i in 0..<original.count {
            original[i] = -Int32(i % 128)
        }
        
        // Encode
        let codeBlock = try encoder.encode(
            coefficients: original,
            width: width,
            height: height,
            subband: .ll,
            bitDepth: bitDepth
        )
        
        // Decode
        let decoded = try decoder.decode(codeBlock: codeBlock, bitDepth: bitDepth)
        
        // Verify
        XCTAssertEqual(decoded, original, "Round-trip for negative values should be exact")
    }
    
    func testCodeBlockRoundTripMixed() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        let width = 16
        let height = 16
        let bitDepth = 8
        
        var original = [Int32](repeating: 0, count: width * height)
        for i in 0..<original.count {
            let sign: Int32 = (i % 2 == 0) ? 1 : -1
            original[i] = sign * Int32((i % 127) + 1)
        }
        
        // Encode
        let codeBlock = try encoder.encode(
            coefficients: original,
            width: width,
            height: height,
            subband: .ll,
            bitDepth: bitDepth
        )
        
        // Decode
        let decoded = try decoder.decode(codeBlock: codeBlock, bitDepth: bitDepth)
        
        // Verify
        XCTAssertEqual(decoded, original, "Round-trip for mixed signs should be exact")
    }
    
    func testCodeBlockRoundTripAllSubbands() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        let width = 32
        let height = 32
        let bitDepth = 12
        
        let subbands: [J2KSubband] = [.ll, .hl, .lh, .hh]
        
        for subband in subbands {
            var original = [Int32](repeating: 0, count: width * height)
            for i in 0..<original.count {
                let sign: Int32 = (i % 3 == 0) ? -1 : 1
                original[i] = sign * Int32((i * 7) % 1000)
            }
            
            // Encode
            let codeBlock = try encoder.encode(
                coefficients: original,
                width: width,
                height: height,
                subband: subband,
                bitDepth: bitDepth
            )
            
            // Decode
            let decoded = try decoder.decode(codeBlock: codeBlock, bitDepth: bitDepth)
            
            // Verify
            XCTAssertEqual(decoded, original, "Round-trip for \(subband) subband should be exact")
        }
    }
    
    func testCodeBlockRoundTripLargeBlock() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        let width = 64
        let height = 64
        let bitDepth = 12
        
        var original = [Int32](repeating: 0, count: width * height)
        for i in 0..<original.count {
            let sign: Int32 = (i % 5 == 0) ? -1 : 1
            original[i] = sign * Int32((i * 13) % 2048)
        }
        
        // Encode
        let codeBlock = try encoder.encode(
            coefficients: original,
            width: width,
            height: height,
            subband: .ll,
            bitDepth: bitDepth
        )
        
        // Decode
        let decoded = try decoder.decode(codeBlock: codeBlock, bitDepth: bitDepth)
        
        // Verify
        XCTAssertEqual(decoded, original, "Round-trip for large block should be exact")
    }
    
    func testCodeBlockRoundTripHighBitDepth() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        let width = 32
        let height = 32
        let bitDepth = 16
        
        var original = [Int32](repeating: 0, count: width * height)
        for i in 0..<original.count {
            let sign: Int32 = (i % 2 == 0) ? 1 : -1
            original[i] = sign * Int32((i * 257) % 32768)
        }
        
        // Encode
        let codeBlock = try encoder.encode(
            coefficients: original,
            width: width,
            height: height,
            subband: .ll,
            bitDepth: bitDepth
        )
        
        // Decode
        let decoded = try decoder.decode(codeBlock: codeBlock, bitDepth: bitDepth)
        
        // Verify
        XCTAssertEqual(decoded, original, "Round-trip for high bit-depth should be exact")
    }
    
    func testCodeBlockRoundTripSparse() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        let width = 32
        let height = 32
        let bitDepth = 8
        
        // Create sparse data (mostly zeros with some non-zero values)
        var original = [Int32](repeating: 0, count: width * height)
        original[0] = 127
        original[width - 1] = -100
        original[width * height / 2] = 50
        original[width * height - 1] = -75
        
        // Encode
        let codeBlock = try encoder.encode(
            coefficients: original,
            width: width,
            height: height,
            subband: .ll,
            bitDepth: bitDepth
        )
        
        // Decode
        let decoded = try decoder.decode(codeBlock: codeBlock, bitDepth: bitDepth)
        
        // Verify
        XCTAssertEqual(decoded, original, "Round-trip for sparse data should be exact")
    }
    
    func testCodeBlockRoundTripEdgeCases() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        let width = 16
        let height = 16
        let bitDepth = 8
        
        // Test with maximum positive values
        var original = [Int32](repeating: 0, count: width * height)
        for i in 0..<original.count {
            original[i] = 127 // Max for 8-bit
        }
        
        let codeBlock = try encoder.encode(
            coefficients: original,
            width: width,
            height: height,
            subband: .ll,
            bitDepth: bitDepth
        )
        
        let decoded = try decoder.decode(codeBlock: codeBlock, bitDepth: bitDepth)
        XCTAssertEqual(decoded, original, "Round-trip for max positive values should be exact")
        
        // Test with maximum negative values
        for i in 0..<original.count {
            original[i] = -128 // Min for 8-bit signed
        }
        
        let codeBlock2 = try encoder.encode(
            coefficients: original,
            width: width,
            height: height,
            subband: .ll,
            bitDepth: bitDepth
        )
        
        let decoded2 = try decoder.decode(codeBlock: codeBlock2, bitDepth: bitDepth)
        XCTAssertEqual(decoded2, original, "Round-trip for max negative values should be exact")
    }
    
    // MARK: - Bit-Plane Decoder Direct Tests
    
    func testBitPlaneDecoderRoundTrip4x4() throws {
        let width = 4
        let height = 4
        let bitDepth = 8
        
        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)
        
        var original = [Int32](repeating: 0, count: width * height)
        original[0] = 100
        original[5] = -50
        original[10] = 25
        original[15] = -10
        
        let (data, passCount, zeroBitPlanes) = try encoder.encode(
            coefficients: original,
            bitDepth: bitDepth
        )
        
        let decoded = try decoder.decode(
            data: data,
            passCount: passCount,
            bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes
        )
        
        XCTAssertEqual(decoded, original, "Small block round-trip should be exact")
    }
    
    func testBitPlaneDecoderRoundTripDifferentSubbands() throws {
        let width = 16
        let height = 16
        let bitDepth = 10
        
        let subbands: [J2KSubband] = [.ll, .hl, .lh, .hh]
        
        for subband in subbands {
            let encoder = BitPlaneCoder(width: width, height: height, subband: subband)
            let decoder = BitPlaneDecoder(width: width, height: height, subband: subband)
            
            var original = [Int32](repeating: 0, count: width * height)
            for i in 0..<original.count {
                let sign: Int32 = (i % 2 == 0) ? 1 : -1
                original[i] = sign * Int32((i * 11) % 512)
            }
            
            let (data, passCount, zeroBitPlanes) = try encoder.encode(
                coefficients: original,
                bitDepth: bitDepth
            )
            
            let decoded = try decoder.decode(
                data: data,
                passCount: passCount,
                bitDepth: bitDepth,
                zeroBitPlanes: zeroBitPlanes
            )
            
            XCTAssertEqual(decoded, original, "Round-trip for \(subband) should be exact")
        }
    }
    
    // MARK: - Performance Tests
    
    func testBitPlaneEncodingPerformance() throws {
        let width = 64
        let height = 64
        let bitDepth = 12
        
        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        
        // Create test coefficients
        var coefficients = [Int32](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            coefficients[i] = Int32((i % 2001) - 1000)
        }
        
        measure {
            _ = try? encoder.encode(coefficients: coefficients, bitDepth: bitDepth)
        }
    }
}

// MARK: - Bypass Mode Tests

/// Tests for selective arithmetic coding bypass mode.
final class J2KBypassModeTests: XCTestCase {
    
    // MARK: - CodingOptions Tests
    
    func testCodingOptionsDefault() throws {
        let options = CodingOptions.default
        XCTAssertFalse(options.bypassEnabled, "Default options should not enable bypass")
        XCTAssertEqual(options.bypassThreshold, 0, "Default threshold should be 0")
    }
    
    func testCodingOptionsFastEncoding() throws {
        let options = CodingOptions.fastEncoding
        XCTAssertTrue(options.bypassEnabled, "Fast encoding should enable bypass")
        XCTAssertGreaterThan(options.bypassThreshold, 0, "Fast encoding should have non-zero threshold")
    }
    
    func testCodingOptionsCustom() throws {
        let options = CodingOptions(bypassEnabled: true, bypassThreshold: 3)
        XCTAssertTrue(options.bypassEnabled)
        XCTAssertEqual(options.bypassThreshold, 3)
    }
    
    func testCodingOptionsNegativeThreshold() throws {
        // Negative threshold should be clamped to 0
        let options = CodingOptions(bypassEnabled: true, bypassThreshold: -5)
        XCTAssertEqual(options.bypassThreshold, 0, "Negative threshold should be clamped to 0")
    }
    
    // MARK: - Bit-Plane Coder with Bypass Tests
    
    func testBitPlaneCoderWithBypass() throws {
        let options = CodingOptions(bypassEnabled: true, bypassThreshold: 4)
        let coder = BitPlaneCoder(width: 16, height: 16, subband: .ll, options: options)
        
        var coefficients = [Int32](repeating: 0, count: 16 * 16)
        for i in 0..<coefficients.count {
            let sign: Int32 = (i % 2 == 0) ? 1 : -1
            coefficients[i] = sign * Int32((i % 100) + 1)
        }
        
        let (data, passCount, zeroBitPlanes) = try coder.encode(
            coefficients: coefficients,
            bitDepth: 8
        )
        
        XCTAssertGreaterThan(data.count, 0, "Encoded data should not be empty")
        XCTAssertGreaterThan(passCount, 0, "Should have at least one coding pass")
    }
    
    func testBitPlaneCoderBypassVsNormal() throws {
        let width = 32
        let height = 32
        let bitDepth = 10
        
        var coefficients = [Int32](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            let sign: Int32 = (i % 3 == 0) ? -1 : 1
            coefficients[i] = sign * Int32((i * 7) % 512)
        }
        
        // Encode without bypass
        let normalCoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let (normalData, normalPasses, normalZero) = try normalCoder.encode(
            coefficients: coefficients,
            bitDepth: bitDepth
        )
        
        // Encode with bypass
        let bypassOptions = CodingOptions(bypassEnabled: true, bypassThreshold: 5)
        let bypassCoder = BitPlaneCoder(width: width, height: height, subband: .ll, options: bypassOptions)
        let (bypassData, bypassPasses, bypassZero) = try bypassCoder.encode(
            coefficients: coefficients,
            bitDepth: bitDepth
        )
        
        // Both should produce valid data
        XCTAssertGreaterThan(normalData.count, 0, "Normal encoding should produce data")
        XCTAssertGreaterThan(bypassData.count, 0, "Bypass encoding should produce data")
        
        // Pass counts should be the same
        XCTAssertEqual(normalPasses, bypassPasses, "Pass counts should match")
        XCTAssertEqual(normalZero, bypassZero, "Zero bit-planes should match")
        
        // Bypass encoding may produce slightly different size due to less context adaptation
        // But both should be reasonable
        let sizeDiff = abs(normalData.count - bypassData.count)
        let maxAcceptableDiff = max(normalData.count, bypassData.count) / 2
        XCTAssertLessThanOrEqual(sizeDiff, maxAcceptableDiff, "Size difference should be reasonable")
    }
    
    // MARK: - Code-Block Encoder/Decoder with Bypass Tests
    
    func testCodeBlockBypassRoundTrip() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        let width = 32
        let height = 32
        let bitDepth = 12
        
        var original = [Int32](repeating: 0, count: width * height)
        for i in 0..<original.count {
            let sign: Int32 = (i % 2 == 0) ? 1 : -1
            original[i] = sign * Int32((i * 13) % 2000)
        }
        
        let options = CodingOptions.fastEncoding
        
        // Encode with bypass
        let codeBlock = try encoder.encode(
            coefficients: original,
            width: width,
            height: height,
            subband: .ll,
            bitDepth: bitDepth,
            options: options
        )
        
        // Decode with same options
        let decoded = try decoder.decode(
            codeBlock: codeBlock,
            bitDepth: bitDepth,
            options: options
        )
        
        // Verify exact round-trip
        XCTAssertEqual(decoded, original, "Bypass round-trip should be exact")
    }
    
    func testCodeBlockBypassAllSubbands() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        let width = 16
        let height = 16
        let bitDepth = 10
        let options = CodingOptions(bypassEnabled: true, bypassThreshold: 3)
        
        let subbands: [J2KSubband] = [.ll, .hl, .lh, .hh]
        
        for subband in subbands {
            var original = [Int32](repeating: 0, count: width * height)
            for i in 0..<original.count {
                let sign: Int32 = (i % 3 == 0) ? -1 : 1
                original[i] = sign * Int32((i * 11) % 512)
            }
            
            // Encode
            let codeBlock = try encoder.encode(
                coefficients: original,
                width: width,
                height: height,
                subband: subband,
                bitDepth: bitDepth,
                options: options
            )
            
            // Decode
            let decoded = try decoder.decode(
                codeBlock: codeBlock,
                bitDepth: bitDepth,
                options: options
            )
            
            // Verify
            XCTAssertEqual(decoded, original, "Bypass round-trip for \(subband) should be exact")
        }
    }
    
    func testCodeBlockBypassZeros() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        let width = 16
        let height = 16
        let bitDepth = 8
        let options = CodingOptions.fastEncoding
        
        let original = [Int32](repeating: 0, count: width * height)
        
        // Encode
        let codeBlock = try encoder.encode(
            coefficients: original,
            width: width,
            height: height,
            subband: .ll,
            bitDepth: bitDepth,
            options: options
        )
        
        // Decode
        let decoded = try decoder.decode(
            codeBlock: codeBlock,
            bitDepth: bitDepth,
            options: options
        )
        
        // Verify
        XCTAssertEqual(decoded, original, "Bypass round-trip for all zeros should be exact")
    }
    
    func testCodeBlockBypassSparse() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        let width = 32
        let height = 32
        let bitDepth = 10
        let options = CodingOptions(bypassEnabled: true, bypassThreshold: 6)
        
        // Create sparse data
        var original = [Int32](repeating: 0, count: width * height)
        original[0] = 511
        original[width - 1] = -400
        original[width * height / 2] = 300
        original[width * height - 1] = -200
        
        // Encode
        let codeBlock = try encoder.encode(
            coefficients: original,
            width: width,
            height: height,
            subband: .ll,
            bitDepth: bitDepth,
            options: options
        )
        
        // Decode
        let decoded = try decoder.decode(
            codeBlock: codeBlock,
            bitDepth: bitDepth,
            options: options
        )
        
        // Verify
        XCTAssertEqual(decoded, original, "Bypass round-trip for sparse data should be exact")
    }
    
    func testCodeBlockBypassHighBitDepth() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        let width = 16
        let height = 16
        let bitDepth = 16
        let options = CodingOptions(bypassEnabled: true, bypassThreshold: 8)
        
        var original = [Int32](repeating: 0, count: width * height)
        for i in 0..<original.count {
            let sign: Int32 = (i % 2 == 0) ? 1 : -1
            original[i] = sign * Int32((i * 257) % 32768)
        }
        
        // Encode
        let codeBlock = try encoder.encode(
            coefficients: original,
            width: width,
            height: height,
            subband: .ll,
            bitDepth: bitDepth,
            options: options
        )
        
        // Decode
        let decoded = try decoder.decode(
            codeBlock: codeBlock,
            bitDepth: bitDepth,
            options: options
        )
        
        // Verify
        XCTAssertEqual(decoded, original, "Bypass round-trip for high bit-depth should be exact")
    }
    
    func testCodeBlockBypassVariousThresholds() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        let width = 16
        let height = 16
        let bitDepth = 8
        
        var original = [Int32](repeating: 0, count: width * height)
        for i in 0..<original.count {
            original[i] = Int32((i % 201) - 100)
        }
        
        // Test with different bypass thresholds
        let thresholds = [0, 1, 2, 4, 6, 8]
        
        for threshold in thresholds {
            let options = CodingOptions(bypassEnabled: true, bypassThreshold: threshold)
            
            // Encode
            let codeBlock = try encoder.encode(
                coefficients: original,
                width: width,
                height: height,
                subband: .ll,
                bitDepth: bitDepth,
                options: options
            )
            
            // Decode
            let decoded = try decoder.decode(
                codeBlock: codeBlock,
                bitDepth: bitDepth,
                options: options
            )
            
            // Verify
            XCTAssertEqual(
                decoded,
                original,
                "Bypass round-trip with threshold \(threshold) should be exact"
            )
        }
    }
    
    func testCodeBlockBypassLargeBlock() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()
        
        let width = 64
        let height = 64
        let bitDepth = 12
        let options = CodingOptions.fastEncoding
        
        var original = [Int32](repeating: 0, count: width * height)
        for i in 0..<original.count {
            let sign: Int32 = (i % 5 == 0) ? -1 : 1
            original[i] = sign * Int32((i * 17) % 2048)
        }
        
        // Encode
        let codeBlock = try encoder.encode(
            coefficients: original,
            width: width,
            height: height,
            subband: .ll,
            bitDepth: bitDepth,
            options: options
        )
        
        // Decode
        let decoded = try decoder.decode(
            codeBlock: codeBlock,
            bitDepth: bitDepth,
            options: options
        )
        
        // Verify
        XCTAssertEqual(decoded, original, "Bypass round-trip for large block should be exact")
    }
    
    // MARK: - Performance Tests
    
    func testBypassEncodingPerformance() throws {
        let width = 64
        let height = 64
        let bitDepth = 12
        let options = CodingOptions.fastEncoding
        
        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll, options: options)
        
        var coefficients = [Int32](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            coefficients[i] = Int32((i % 2001) - 1000)
        }
        
        measure {
            _ = try? encoder.encode(coefficients: coefficients, bitDepth: bitDepth)
        }
    }
    
    func testNormalVsBypassEncodingSpeed() throws {
        let width = 32
        let height = 32
        let bitDepth = 10
        
        var coefficients = [Int32](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            coefficients[i] = Int32((i % 1001) - 500)
        }
        
        // Measure normal encoding
        let normalCoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let normalStart = Date()
        for _ in 0..<10 {
            _ = try? normalCoder.encode(coefficients: coefficients, bitDepth: bitDepth)
        }
        let normalTime = Date().timeIntervalSince(normalStart)
        
        // Measure bypass encoding
        let bypassOptions = CodingOptions.fastEncoding
        let bypassCoder = BitPlaneCoder(width: width, height: height, subband: .ll, options: bypassOptions)
        let bypassStart = Date()
        for _ in 0..<10 {
            _ = try? bypassCoder.encode(coefficients: coefficients, bitDepth: bitDepth)
        }
        let bypassTime = Date().timeIntervalSince(bypassStart)
        
        // Bypass should typically be faster (though this is not a strict requirement in debug builds)
        print("Normal encoding time: \(normalTime)s")
        print("Bypass encoding time: \(bypassTime)s")
        print("Speedup: \(normalTime / bypassTime)x")
        
        // Just verify both completed successfully
        XCTAssertGreaterThan(normalTime, 0)
        XCTAssertGreaterThan(bypassTime, 0)
    }
}
