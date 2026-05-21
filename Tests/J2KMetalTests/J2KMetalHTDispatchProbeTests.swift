//
// J2KMetalHTDispatchProbeTests.swift
// J2KSwift
//
// Microbenchmarks the GPU HT decoder prototype's dispatch envelope.
// Answers: at what codeblock count does the GPU layout become viable?
//
// Run:
//   swift test -c release --filter J2KMetalHTDispatchProbeTests 2>&1 \
//     | grep '\[ht-probe\]'
//

import XCTest
import J2KMetal
import J2KCore

final class J2KMetalHTDispatchProbeTests: XCTestCase {

    /// Even tinier — exercises only the shader load path. If this hangs
    /// the issue is in pipeline creation; if it returns the issue is
    /// in the GPU run.
    func testShaderLoadOnly() async throws {
        try XCTSkipUnless(J2KMetalHTDispatchProbe.isAvailable, "Metal not available")
        print("[ht-load] requesting probe shader pipeline")
        let dev = J2KMetalDevice()
        try await dev.initialize()
        let lib = J2KMetalShaderLibrary()
        let q = try await dev.commandQueue()
        try await lib.loadShaders(device: q.device)
        let pipeline = try await lib.computePipeline(for: .htDispatchProbe)
        print("[ht-load] pipeline ok: \(pipeline.maxTotalThreadsPerThreadgroup) max threads/group")
    }
}
