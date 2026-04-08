import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Minimal test to isolate RLC position encoding round-trip
final class J2KRLCMinimalRoundTripTest: XCTestCase {
    
    /// Test a 1-wide, 4-tall block where position encoding is used
    /// This is the absolute minimum: 1 stripe column, eligible for RLC
    func testSingleColumnRLC() throws {
        // 1x4 block: single stripe column, all 4 rows
        // Value at position 2 is significant (pos=2), others zero
        let width = 1
        let height = 4
        let bitDepth = 4
        let subband: J2KSubband = .ll
        let coefficients: [Int32] = [0, 0, 5, 0]  // only position 2 is significant at bitPlane 2
        
        // Test with default termination first
        let defOpts = CodingOptions()
        let defCoder = BitPlaneCoder(width: width, height: height, subband: subband, options: defOpts)
        let (defData, defPC, defZBP, defSL, _) = try defCoder.encode(coefficients: coefficients, bitDepth: bitDepth)
        let defDecoder = BitPlaneDecoder(width: width, height: height, subband: subband, options: defOpts)
        let defResult = try defDecoder.decode(data: defData, passCount: defPC, bitDepth: bitDepth, zeroBitPlanes: defZBP, passSegmentLengths: defSL)
        print("Default termination: input=\(coefficients) decoded=\(defResult)")
        
        // Test with predictable termination
        let options = CodingOptions(terminationMode: .predictable)
        let coder = BitPlaneCoder(width: width, height: height, subband: subband, options: options)
        let (encoded, passCount, zeroBitPlanes, segmentLengths, _) = try coder.encode(
            coefficients: coefficients,
            bitDepth: bitDepth
        )
        
        print("1x4 RLC test: passes=\(passCount), zeroBP=\(zeroBitPlanes), segments=\(segmentLengths), bytes=\(encoded.count)")
        
        let decoder = BitPlaneDecoder(width: width, height: height, subband: subband, options: options)
        let decoded = try decoder.decode(
            data: encoded,
            passCount: passCount,
            bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes,
            passSegmentLengths: segmentLengths
        )
        
        print("Predictable termination: input=\(coefficients) decoded=\(decoded)")
        
        // Test MQ round-trip directly with predictable vs default termination
        print("\n--- Direct MQ round-trip test ---")
        let testSymbols: [[Bool]] = [
            [false, false, true, false],
            [true, false, true, true, false],
            [false, true]
        ]
        
        for (i, symbols) in testSymbols.enumerated() {
            // Predictable termination
            var enc = MQEncoder()
            var ctx = ContextStateArray()
            for sym in symbols {
                enc.encode(symbol: sym, context: &ctx[.runLength])
            }
            let predData = enc.finish(mode: .predictable)
            
            var dec = MQDecoder(data: predData)
            var dctx = ContextStateArray()
            var predDecoded: [Bool] = []
            for _ in symbols {
                predDecoded.append(dec.decode(context: &dctx[.runLength]))
            }
            
            // Default termination
            var enc2 = MQEncoder()
            var ctx2 = ContextStateArray()
            for sym in symbols {
                enc2.encode(symbol: sym, context: &ctx2[.runLength])
            }
            let defData = enc2.finish(mode: .default)
            
            var dec2 = MQDecoder(data: defData)
            var dctx2 = ContextStateArray()
            var defDecoded: [Bool] = []
            for _ in symbols {
                defDecoded.append(dec2.decode(context: &dctx2[.runLength]))
            }
            
            let predMatch = symbols == predDecoded ? "MATCH" : "MISMATCH"
            let defMatch = symbols == defDecoded ? "MATCH" : "MISMATCH"
            print("MQ test \(i): pred=\(predMatch) data=\(Array(predData).map { String(format: "%02x", $0) }), def=\(defMatch) data=\(Array(defData).map { String(format: "%02x", $0) })")
        }
        
        XCTAssertEqual(coefficients.map { Int($0) }, decoded.map { Int($0) }, "Single column RLC round-trip failed")
    }
    
    /// Test a single 4x4 block with controlled data
    func test4x4Block() throws {
        let width = 4
        let height = 4
        let bitDepth = 4
        let subband: J2KSubband = .ll
        // One stripe, 4 columns
        // Col 0: all zero (eligible, no sig -> rlc false)
        // Col 1: [0,0,3,0] (eligible, has sig at pos 2 -> rlc true, pos=2)
        // Col 2: [0,0,0,7] (eligible, has sig at pos 3 -> rlc true, pos=3) 
        // Col 3: [0,0,0,0] (eligible, no sig -> rlc false)
        let coefficients: [Int32] = [
            0, 0, 0, 0,   // row 0
            0, 0, 0, 0,   // row 1
            0, 3, 0, 0,   // row 2
            0, 0, 7, 0,   // row 3
        ]
        
        let options = CodingOptions(terminationMode: .predictable)
        let coder = BitPlaneCoder(width: width, height: height, subband: subband, options: options)
        let (encoded, passCount, zeroBitPlanes, segmentLengths, _) = try coder.encode(
            coefficients: coefficients,
            bitDepth: bitDepth
        )
        
        print("4x4 RLC test: passes=\(passCount), zeroBP=\(zeroBitPlanes), segments=\(segmentLengths ?? []), bytes=\(encoded.count)")
        
        let decoder = BitPlaneDecoder(width: width, height: height, subband: subband, options: options)
        let decoded = try decoder.decode(
            data: encoded,
            passCount: passCount,
            bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes,
            passSegmentLengths: segmentLengths
        )
        
        print("Input:   \(coefficients)")
        print("Decoded: \(decoded)")
        XCTAssertEqual(coefficients.map { Int($0) }, decoded.map { Int($0) }, "4x4 RLC round-trip failed")
    }
    
    /// Test with HL subband (which passes in old tests)
    func test4x4BlockHL() throws {
        let width = 4
        let height = 4
        let bitDepth = 4
        let subband: J2KSubband = .hl
        let coefficients: [Int32] = [
            0, 0, 0, 0,
            0, 0, 0, 0,
            0, 3, 0, 0,
            0, 0, 7, 0,
        ]
        
        let options = CodingOptions(terminationMode: .predictable)
        let coder = BitPlaneCoder(width: width, height: height, subband: subband, options: options)
        let (encoded, passCount, zeroBitPlanes, segmentLengths, _) = try coder.encode(
            coefficients: coefficients,
            bitDepth: bitDepth
        )
        
        let decoder = BitPlaneDecoder(width: width, height: height, subband: subband, options: options)
        let decoded = try decoder.decode(
            data: encoded,
            passCount: passCount,
            bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes,
            passSegmentLengths: segmentLengths
        )
        
        print("HL Input:   \(coefficients)")
        print("HL Decoded: \(decoded)")
        XCTAssertEqual(coefficients.map { Int($0) }, decoded.map { Int($0) }, "4x4 HL round-trip failed")
    }
    
    /// Test with default (non-predictable) termination
    func testDefaultTermination() throws {
        // First: stress-test MQ coder with many symbols and multiple contexts
        print("=== MQ Coder Stress Test ===")
        let numSymbols = 5000
        var rng = numSymbols  // simple deterministic sequence
        var symbols: [(Bool, EBCOTContext)] = []
        let ctxChoices: [EBCOTContext] = [.sigPropLL_LH_0, .sigPropLL_LH_1h, .sigPropLL_LH_2, 
                                           .signH0V0, .signHnegV0, .magRef1, .runLength, .uniform]
        for i in 0..<numSymbols {
            rng = (rng &* 1103515245 &+ 12345) & 0x7FFFFFFF
            let sym = (rng & 1) != 0
            let ctx = ctxChoices[i % ctxChoices.count]
            symbols.append((sym, ctx))
        }
        
        var enc = MQEncoder()
        var ectx = ContextStateArray()
        for (sym, ctx) in symbols {
            enc.encode(symbol: sym, context: &ectx[ctx])
        }
        let data = enc.finish(mode: .default)
        
        var dec = MQDecoder(data: data)
        var dctx = ContextStateArray()
        var mismatches = 0
        var firstMM = -1
        for (i, (expectedSym, ctx)) in symbols.enumerated() {
            let decoded = dec.decode(context: &dctx[ctx])
            if decoded != expectedSym {
                if firstMM < 0 { firstMM = i }
                mismatches += 1
            }
        }
        print("MQ stress test: \(mismatches)/\(numSymbols) mismatches, first at \(firstMM)")
        XCTAssertEqual(mismatches, 0, "MQ coder stress test failed!")
        
        // Now the bit-plane coder test
        let size = 31
        let width = size
        let height = size
        let bitDepth = 12
        let subband: J2KSubband = .ll
        
        var coefficients = [Int32](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            let sign: Int32 = (i.isMultiple(of: 3)) ? -1 : 1
            coefficients[i] = sign * Int32((i * 7) % 1000)
        }
        
        // ISO + default with per-symbol tracing
        EBCOTDebugTrace.shared.reset()
        EBCOTDebugTrace.shared.enabled = true
        
        let isoOpts = CodingOptions(useISOPositionEncoding: true)
        let isoCoder = BitPlaneCoder(width: width, height: height, subband: subband, options: isoOpts)
        let (isoData, isoPC, isoZBP, isoSL, _) = try isoCoder.encode(coefficients: coefficients, bitDepth: bitDepth)
        
        let encSymbols = EBCOTDebugTrace.shared.encoderSymbols
        EBCOTDebugTrace.shared.decoderSymbols = []
        
        let isoDecoder = BitPlaneDecoder(width: width, height: height, subband: subband, options: isoOpts)
        let isoResult = try isoDecoder.decode(data: isoData, passCount: isoPC, bitDepth: bitDepth, zeroBitPlanes: isoZBP, passSegmentLengths: isoSL)
        
        let decSymbols = EBCOTDebugTrace.shared.decoderSymbols
        EBCOTDebugTrace.shared.enabled = false
        
        // Print per-pass operation counts
        let encPassStates = EBCOTDebugTrace.shared.encoderPassStates
        let decPassStates = EBCOTDebugTrace.shared.decoderPassStates
        
        var isoMM = 0
        for i in 0..<coefficients.count {
            if coefficients[i] != isoResult[i] { isoMM += 1 }
        }
        print("ISO+default: \(isoMM)/\(coefficients.count) mismatches, data=\(isoData.count) bytes, passes=\(isoPC)")
        print("Encoder symbols: \(encSymbols.count), Decoder symbols: \(decSymbols.count)")
        
        // CRITICAL TEST: replay encoder's exact symbol+label sequence through decoder
        print("\n=== MQ Replay Test ===")
        var replayDecoder = MQDecoder(data: isoData)
        var replayCtx = ContextStateArray()
        var replayMismatches = 0
        var firstReplayMM = -1
        for (i, e) in encSymbols.enumerated() {
            let label = Int(e.4)  // context label from encoder
            let expectedSym = e.2   // symbol the encoder encoded
            let ebcotCtx = EBCOTContext(rawValue: UInt8(label))!
            let decoded = replayDecoder.decode(context: &replayCtx[ebcotCtx])
            if decoded != expectedSym {
                if firstReplayMM < 0 { firstReplayMM = i }
                replayMismatches += 1
                if replayMismatches <= 3 {
                    print("  Replay mismatch at \(i): label=\(label), expected=\(expectedSym), got=\(decoded)")
                }
            }
        }
        print("Replay: \(replayMismatches)/\(encSymbols.count) mismatches, first at \(firstReplayMM)")
        
        // Dump encoded bytes around decoder position at divergence
        print("Encoded data bytes around positions 280-290:")
        let dstart = max(0, 275)
        let dend = min(isoData.count, 295)
        for i in dstart..<dend {
            print("  byte[\(i)] = 0x\(String(format: "%02X", isoData[i]))")
        }
        print("Encoder pass count: \(encPassStates.count), Decoder pass count: \(decPassStates.count)")
        
        // Compare per-pass operation counts
        let passCmp = min(encPassStates.count, decPassStates.count)
        for i in 0..<passCmp {
            let ep = encPassStates[i]
            let dp = decPassStates[i]
            let opMatch = ep.opCount == dp.opCount ? "OK" : "MISMATCH"
            let aMatch = ep.a == dp.a ? "OK" : "MISMATCH"
            print("  Pass \(i): enc(ops=\(ep.opCount), A=\(String(format: "%04X", ep.a)), C=\(String(format: "%08X", ep.c))) dec(ops=\(dp.opCount), A=\(String(format: "%04X", dp.a)), C=\(String(format: "%08X", dp.c))) ops=\(opMatch) A=\(aMatch)")
        }
        
        // Find first pass with operation count mismatch
        var firstBadPass = -1
        for i in 0..<passCmp {
            if encPassStates[i].opCount != decPassStates[i].opCount {
                firstBadPass = i
                break
            }
        }
        if firstBadPass >= 0 {
            print("FIRST PASS WITH OP COUNT MISMATCH: pass \(firstBadPass)")
        }
        
        // Find first symbol divergence
        let minSyms = min(encSymbols.count, decSymbols.count)
        var firstDivergence = -1
        var firstADivergence = -1
        var firstLabelDivergence = -1
        for i in 0..<minSyms {
            let e = encSymbols[i]
            let d = decSymbols[i]
            if e.2 != d.2 && firstDivergence < 0 {
                firstDivergence = i
            }
            if e.3 != d.3 && firstADivergence < 0 {
                firstADivergence = i
            }
            if e.4 != d.4 && firstLabelDivergence < 0 {
                firstLabelDivergence = i
            }
        }
        
        print("First SYMBOL divergence at index \(firstDivergence)")
        print("First A-register divergence at index \(firstADivergence)")
        print("First LABEL divergence at index \(firstLabelDivergence)")
        
        if firstLabelDivergence >= 0 && firstLabelDivergence <= firstDivergence {
            let i = firstLabelDivergence
            let start = max(0, i - 3)
            let end = min(minSyms, i + 5)
            print("Context around first LABEL divergence:")
            for j in start..<end {
                let e = encSymbols[j]
                let d = decSymbols[j]
                let marker = j == i ? " <<<" : ""
                print("  [\(j)] enc(op=\(e.0), ctxSt=\(e.1), sym=\(e.2), A=\(String(format: "%04X", e.3)), label=\(e.4)) dec(op=\(d.0), ctxSt=\(d.1), sym=\(d.2), A=\(String(format: "%04X", d.3)), label=\(d.4))\(marker)")
            }
        }
        
        if firstDivergence >= 0 {
            let i = firstDivergence
            let start = max(0, i - 3)
            let end = min(minSyms, i + 5)
            print("Context around first SYMBOL divergence:")
            for j in start..<end {
                let e = encSymbols[j]
                let d = decSymbols[j]
                let marker = j == i ? " <<<" : ""
                print("  [\(j)] enc(op=\(e.0), ctxSt=\(e.1), sym=\(e.2), A=\(String(format: "%04X", e.3)), label=\(e.4)) dec(op=\(d.0), ctxSt=\(d.1), sym=\(d.2), A=\(String(format: "%04X", d.3)), label=\(d.4))\(marker)")
            }
        }
        
        // Compare state snapshots after each cleanup pass 
        let encSnaps = EBCOTDebugTrace.shared.encoderStatesSnapshots
        let decSnaps = EBCOTDebugTrace.shared.decoderStatesSnapshots
        for key in encSnaps.keys.sorted() {
            if let eStates = encSnaps[key], let dStates = decSnaps[key] {
                var mismatches = 0
                var firstMM = -1
                for i in 0..<min(eStates.count, dStates.count) {
                    if eStates[i] != dStates[i] {
                        if firstMM < 0 { firstMM = i }
                        mismatches += 1
                    }
                }
                if mismatches > 0 {
                    print("State snapshot '\(key)': \(mismatches) mismatches, first at idx \(firstMM)")
                } else {
                    print("State snapshot '\(key)': MATCH")
                }
            }
        }
        
        // Compare MQ context states at pass boundaries
        let encCtxStates = EBCOTDebugTrace.shared.encoderContextStates
        let decCtxStates = EBCOTDebugTrace.shared.decoderContextStates
        let ctxLabels = ["sigLL_0", "sigLL_1h", "sigLL_1v", "sigLL_2", "sigLL_1d",
                         "sigHL_h", "sigHL_v", "sigHH_h", "sigHH_v",
                         "signHnVn", "signH0Vn", "signHpVn", "signHnV0", "signH0V0",
                         "magRef1", "magRef2noS", "magRef2sig",
                         "runLength", "uniform"]
        for pass in 0..<30 {
            guard let enc = encCtxStates[pass], let dec = decCtxStates[pass] else { continue }
            var diffs: [String] = []
            for i in 0..<min(enc.count, dec.count) {
                if enc[i].0 != dec[i].0 || enc[i].1 != dec[i].1 {
                    let label = i < ctxLabels.count ? ctxLabels[i] : "ctx\(i)"
                    diffs.append("\(label):enc(\(enc[i].0),\(enc[i].1))!=dec(\(dec[i].0),\(dec[i].1))")
                }
            }
            if !diffs.isEmpty {
                print("CTX MISMATCH after pass \(pass): \(diffs.joined(separator: ", "))")
            }
        }
    }
    
    /// Test larger block matching the original failing test pattern
    func test16x16OriginalPattern() throws {
        let width = 16
        let height = 16
        let bitDepth = 4
        let subband: J2KSubband = .ll
        
        let maxVal = (1 << bitDepth) - 1
        var coefficients = [Int32](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            let val = Int32(i % 256)
            coefficients[i] = min(val, Int32(maxVal))
            if i % 3 == 0 { coefficients[i] = -coefficients[i] }
        }
        
        let options = CodingOptions.default
        let coder = BitPlaneCoder(width: width, height: height, subband: subband, options: options)
        let (encoded, passCount, zeroBitPlanes, segmentLengths, _) = try coder.encode(
            coefficients: coefficients,
            bitDepth: bitDepth
        )
        
        let decoder = BitPlaneDecoder(width: width, height: height, subband: subband, options: options)
        let decoded = try decoder.decode(
            data: encoded,
            passCount: passCount,
            bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes,
            passSegmentLengths: segmentLengths
        )
        
        var mismatches = 0
        for i in 0..<coefficients.count {
            if coefficients[i] != decoded[i] {
                if mismatches < 5 {
                    print("Mismatch at \(i): expected \(coefficients[i]), got \(decoded[i])")
                }
                mismatches += 1
            }
        }
        print("16x16 LL: \(mismatches) mismatches out of \(coefficients.count)")
        XCTAssertEqual(mismatches, 0, "16x16 LL round-trip failed with \(mismatches) mismatches")
    }
}
