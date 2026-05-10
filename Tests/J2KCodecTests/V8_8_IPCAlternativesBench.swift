// V8_8_IPCAlternativesBench.swift
//
// v8.8 (research) — alternative IPC primitive microbenches for the
// daemon's 25 MB pixel-data result transfer.
//
// Background: V8_8_DaemonOverheadDecomposition + the trace
// instrumentation showed daemon-side decode runs at ~52 ms (matches
// in-process), with ~5 ms additional overhead outside the daemon
// dominated by NSXPCConnection bytes-transfer. Of that, ~2.5 ms is
// the 25 MB pixelData OOL transfer back to the client.
//
// This bench measures the BYTE-TRANSFER cost of three alternative
// primitives in isolation, intra-process (a single test running both
// "producer" and "consumer" sides), to establish a lower bound on
// what's achievable. Cross-process (between daemon and CLI) would add
// XPC handshake overhead but not change the per-byte transfer cost.
//
// Probes:
//   3a. POSIX shm_open + mmap (single-process write+map+read)
//   3b. IOSurface (single-process create+lock+write+unlock+read)
//   3c. Pure memcpy reference (lower bound — what zero-copy strives for)

#if os(macOS)

import XCTest
import Foundation
import Darwin
import IOSurface

final class V8_8_IPCAlternativesBench: XCTestCase {

    @inline(never)
    private func errlog(_ s: String) {
        FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
    }

    private static let bytes = 25 * 1024 * 1024  // 25 MB ≈ DX pixelData

    // Pre-fill a source buffer with deterministic data.
    private func sourceBuffer() -> UnsafeMutableRawPointer {
        let p = UnsafeMutableRawPointer.allocate(byteCount: Self.bytes, alignment: 16)
        let pInt = p.bindMemory(to: UInt32.self, capacity: Self.bytes / 4)
        for i in 0..<(Self.bytes / 4) { pInt[i] = UInt32(truncatingIfNeeded: i &* 7919) }
        return p
    }

    /// Probe 3a — file-backed mmap (surrogate for POSIX shm; kernel handles
    /// both via the unified VM cache so per-byte costs are similar).
    /// Pattern: producer creates + ftruncate + mmap + memcpy + unmap.
    /// Consumer opens + mmap + reads. Simulates daemon→client zero-copy.
    func testProbe3a_POSIX_shm() {
        let src = sourceBuffer()
        defer { src.deallocate() }

        let shmPath = "/tmp/v8_8_shm_bench_\(getpid()).bin"

        let runs = 7
        var producerSamples: [Double] = []
        var consumerSamples: [Double] = []

        for _ in 0..<runs {
            unlink(shmPath)

            // Producer side: open + size + map + write + unmap + close.
            let t0 = DispatchTime.now()
            let fd = open(shmPath, O_CREAT | O_RDWR | O_TRUNC, 0o600)
            if fd == -1 { XCTFail("open failed: \(String(cString: strerror(errno)))"); return }
            ftruncate(fd, off_t(Self.bytes))
            let mapped = mmap(nil, Self.bytes, PROT_READ | PROT_WRITE,
                              MAP_SHARED, fd, 0)
            if mapped == MAP_FAILED { XCTFail("mmap failed"); return }
            memcpy(mapped, src, Self.bytes)
            munmap(mapped, Self.bytes)
            close(fd)
            let dtProducer = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            producerSamples.append(Double(dtProducer) / 1_000_000.0)

            // Consumer side: open + map + touch every page.
            let t1 = DispatchTime.now()
            let fd2 = open(shmPath, O_RDONLY)
            if fd2 == -1 { XCTFail("consumer open failed"); return }
            let mapped2 = mmap(nil, Self.bytes, PROT_READ, MAP_SHARED, fd2, 0)
            if mapped2 == MAP_FAILED { XCTFail("consumer mmap failed"); return }
            var checksum: UInt32 = 0
            let pInt = mapped2!.bindMemory(to: UInt32.self, capacity: Self.bytes / 4)
            var i = 0
            while i < Self.bytes / 4 {
                checksum = checksum &+ pInt[i]
                i += 1024
            }
            munmap(mapped2, Self.bytes)
            close(fd2)
            unlink(shmPath)
            let dtConsumer = DispatchTime.now().uptimeNanoseconds &- t1.uptimeNanoseconds
            consumerSamples.append(Double(dtConsumer) / 1_000_000.0)
            XCTAssertNotEqual(checksum, 0, "shm read should produce non-zero data")
        }

        producerSamples.sort()
        consumerSamples.sort()
        let prodMed = producerSamples[runs / 2]
        let consMed = consumerSamples[runs / 2]
        let totalMed = prodMed + consMed

        errlog("")
        errlog("=== v8.8 — IPC Alternatives Probe 3a: POSIX shm_open + mmap ===")
        errlog("Buffer: \(Self.bytes) bytes (\(Double(Self.bytes) / 1024 / 1024) MB), simulating DX pixelData round-trip")
        errlog(String(format: "  Producer (create+map+memcpy+unmap): median %.3f ms (n=%d)", prodMed, runs))
        errlog(String(format: "  Consumer (open+map+touch+unmap):    median %.3f ms (n=%d)", consMed, runs))
        errlog(String(format: "  Combined:                            median %.3f ms", totalMed))
        errlog("")
    }

    /// Probe 3b — IOSurface: create + lock-write + unlock + lock-read + unlock.
    func testProbe3b_IOSurface() {
        let src = sourceBuffer()
        defer { src.deallocate() }

        let runs = 7
        var producerSamples: [Double] = []
        var consumerSamples: [Double] = []

        for _ in 0..<runs {
            let props: [IOSurfacePropertyKey: Any] = [
                .width: Self.bytes,
                .height: 1,
                .bytesPerElement: 1,
                .pixelFormat: 0,
            ]

            // Producer.
            let t0 = DispatchTime.now()
            guard let surface = IOSurface(properties: props) else {
                XCTFail("IOSurface create failed"); return
            }
            // Lock for write.
            let lockResult = surface.lock(options: [], seed: nil)
            XCTAssertEqual(lockResult, kIOReturnSuccess, "lock failed")
            let base = surface.baseAddress
            memcpy(base, src, Self.bytes)
            let unlockResult = surface.unlock(options: [], seed: nil)
            XCTAssertEqual(unlockResult, kIOReturnSuccess, "unlock failed")
            let dtProducer = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            producerSamples.append(Double(dtProducer) / 1_000_000.0)

            // Consumer (read-side).
            let t1 = DispatchTime.now()
            let lock2 = surface.lock(options: .readOnly, seed: nil)
            XCTAssertEqual(lock2, kIOReturnSuccess, "consumer lock failed")
            let base2 = surface.baseAddress
            var checksum: UInt32 = 0
            let pInt = base2.bindMemory(to: UInt32.self, capacity: Self.bytes / 4)
            var i = 0
            while i < Self.bytes / 4 {
                checksum = checksum &+ pInt[i]
                i += 1024
            }
            let unlock2 = surface.unlock(options: .readOnly, seed: nil)
            XCTAssertEqual(unlock2, kIOReturnSuccess, "consumer unlock failed")
            let dtConsumer = DispatchTime.now().uptimeNanoseconds &- t1.uptimeNanoseconds
            consumerSamples.append(Double(dtConsumer) / 1_000_000.0)
            XCTAssertNotEqual(checksum, 0)
        }

        producerSamples.sort()
        consumerSamples.sort()
        let prodMed = producerSamples[runs / 2]
        let consMed = consumerSamples[runs / 2]

        errlog("=== v8.8 — IPC Alternatives Probe 3b: IOSurface ===")
        errlog(String(format: "  Producer (create+lock+memcpy+unlock): median %.3f ms (n=%d)", prodMed, runs))
        errlog(String(format: "  Consumer (lock+touch+unlock):         median %.3f ms (n=%d)", consMed, runs))
        errlog(String(format: "  Combined:                              median %.3f ms", prodMed + consMed))
        errlog("")
    }

    /// Probe 3c — pure memcpy reference (the lower bound for any
    /// shared-memory primitive that requires actual byte movement).
    func testProbe3c_memcpy_reference() {
        let src = sourceBuffer()
        let dst = UnsafeMutableRawPointer.allocate(byteCount: Self.bytes, alignment: 16)
        defer { src.deallocate(); dst.deallocate() }

        let runs = 10
        var samples: [Double] = []

        // Warm-up.
        memcpy(dst, src, Self.bytes)

        for _ in 0..<runs {
            let t0 = DispatchTime.now()
            memcpy(dst, src, Self.bytes)
            let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            samples.append(Double(dt) / 1_000_000.0)
        }
        samples.sort()
        let med = samples[runs / 2]

        errlog("=== v8.8 — IPC Alternatives Probe 3c: pure memcpy reference ===")
        errlog(String(format: "  memcpy 25 MB (single-pass):  median %.3f ms (n=%d)", med, runs))
        errlog("  This is the lower bound for ANY primitive that physically moves bytes.")
        errlog("  IOSurface / shm primitives that beat this number do so by avoiding the copy entirely.")
        errlog("")
    }

    /// Probe 3d — mach_vm_remap: in-process page table remap.
    /// Tests whether remapping pages (vs copying) reduces transfer cost.
    /// In a cross-process scenario this would use mach_vm_remap with
    /// the daemon's task port; intra-process (this bench) uses the
    /// current task as both source and target.
    func testProbe3d_mach_vm_remap() {
        let runs = 7
        var samples: [Double] = []

        for _ in 0..<runs {
            // Allocate a source region.
            var src: vm_address_t = 0
            let kr0 = vm_allocate(mach_task_self_, &src, vm_size_t(Self.bytes), VM_FLAGS_ANYWHERE)
            XCTAssertEqual(kr0, KERN_SUCCESS, "vm_allocate failed")
            // Touch every page in source to force fault-in.
            let pSrc = UnsafeMutableRawPointer(bitPattern: UInt(src))!
                .bindMemory(to: UInt32.self, capacity: Self.bytes / 4)
            for i in stride(from: 0, to: Self.bytes / 4, by: 1024) {
                pSrc[i] = UInt32(i)
            }

            // Time the remap (page-table operation, no byte copy).
            let t0 = DispatchTime.now()
            var dst: vm_address_t = 0
            var curProt: vm_prot_t = 0
            var maxProt: vm_prot_t = 0
            let kr = vm_remap(
                mach_task_self_,        // target task
                &dst,                    // target address (out)
                vm_size_t(Self.bytes),  // size
                0,                       // mask (alignment)
                VM_FLAGS_ANYWHERE,
                mach_task_self_,        // source task
                src,                     // source address
                0,                       // copy = false (true would force COW copy)
                &curProt,
                &maxProt,
                VM_INHERIT_NONE
            )
            let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            samples.append(Double(dt) / 1_000_000.0)
            XCTAssertEqual(kr, KERN_SUCCESS, "vm_remap failed kr=\(kr)")

            // Verify remapped region has the same data (touch it).
            let pDst = UnsafeMutableRawPointer(bitPattern: UInt(dst))!
                .bindMemory(to: UInt32.self, capacity: Self.bytes / 4)
            var checksum: UInt32 = 0
            for i in stride(from: 0, to: Self.bytes / 4, by: 1024) {
                checksum = checksum &+ pDst[i]
            }
            XCTAssertNotEqual(checksum, 0)

            // Cleanup.
            vm_deallocate(mach_task_self_, dst, vm_size_t(Self.bytes))
            vm_deallocate(mach_task_self_, src, vm_size_t(Self.bytes))
        }
        samples.sort()
        let med = samples[runs / 2]

        errlog("=== v8.8 — IPC Alternatives Probe 3d: mach_vm_remap (intra-process) ===")
        errlog(String(format: "  vm_remap 25 MB pages:  median %.3f ms (n=%d)", med, runs))
        errlog("  Cross-process vm_remap requires task ports + xpc_endpoint plumbing,")
        errlog("  but per-page remap cost should be similar (page-table operation, not byte copy).")
        errlog("")
    }

    /// Synthesis: print a summary table comparing the three primitives
    /// against the measured NSXPCConnection ~2.5 ms baseline for the
    /// 25 MB result-transfer leg.
    func testProbe3d_synthesis_table() {
        errlog("")
        errlog("=== v8.8 IPC alternatives — synthesis ===")
        errlog("")
        errlog("Reference: NSXPCConnection 25 MB pixelData receive (current production):")
        errlog("  ~2.5 ms (auto-OOL via mach_msg shared-memory descriptors)")
        errlog("")
        errlog("Run testProbe3a/3b/3c independently to populate this table:")
        errlog("  POSIX shm    | (see Probe 3a)")
        errlog("  IOSurface    | (see Probe 3b)")
        errlog("  memcpy ref   | (see Probe 3c)")
        errlog("")
        errlog("If POSIX shm or IOSurface combined producer+consumer cost is")
        errlog("BELOW NSXPCConnection's 2.5 ms, that's the daemon overhead fix.")
        errlog("If they MATCH or EXCEED, the bytes-transfer cost is structural.")
    }
}

#endif
