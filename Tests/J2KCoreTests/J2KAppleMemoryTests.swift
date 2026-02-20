//
// J2KAppleMemoryTests.swift
// J2KSwift
//
import XCTest
@testable import J2KCore

/// Tests for Apple-specific memory optimizations.
@available(macOS 11.0, iOS 14.0, tvOS 14.0, *)
final class J2KAppleMemoryTests: XCTestCase {
    // MARK: - Unified Memory Manager Tests

    func testUnifiedMemoryManagerAllocation() async throws {
        #if !canImport(Darwin)
        throw XCTSkip("Unified memory only available on Apple platforms")
        #endif
        let manager = J2KUnifiedMemoryManager()

        let size = 1024 * 1024 // 1 MB
        let ptr = try manager.allocateShared(size: size)

        // Verify pointer is valid
        XCTAssertNotEqual(ptr, UnsafeMutableRawPointer(bitPattern: 0))

        // Verify we can write to the memory
        ptr.storeBytes(of: UInt32(0x12345678), as: UInt32.self)
        let value = ptr.load(as: UInt32.self)
        XCTAssertEqual(value, 0x12345678)

        manager.deallocate(ptr)

        let stats = manager.statistics()
        XCTAssertEqual(stats["totalAllocated"], 0)
    }

    func testUnifiedMemoryManagerMultipleAllocations() async throws {
        #if !canImport(Darwin)
        throw XCTSkip("Unified memory only available on Apple platforms")
        #endif
        let manager = J2KUnifiedMemoryManager()

        var pointers: [UnsafeMutableRawPointer] = []

        // Allocate multiple buffers
        for _ in 0..<5 {
            let ptr = try manager.allocateShared(size: 4096)
            pointers.append(ptr)
        }

        let stats = manager.statistics()
        XCTAssertEqual(stats["allocationCount"], 5)

        // Deallocate all
        for ptr in pointers {
            manager.deallocate(ptr)
        }

        let finalStats = manager.statistics()
        XCTAssertEqual(finalStats["totalAllocated"], 0)
    }

    func testUnifiedMemoryManagerAlignment() async throws {
        #if !canImport(Darwin)
        throw XCTSkip("Unified memory only available on Apple platforms")
        #endif
        let config = J2KUnifiedMemoryManager.Configuration(alignment: 64)
        let manager = J2KUnifiedMemoryManager(configuration: config)

        let ptr = try manager.allocateShared(size: 100)

        // Verify 64-byte alignment
        let address = UInt(bitPattern: ptr)
        XCTAssertEqual(address % 64, 0, "Pointer should be 64-byte aligned")

        manager.deallocate(ptr)
    }

    // MARK: - Memory-Mapped File I/O Tests

    func testMemoryMappedFileReadOnly() throws {
        #if os(macOS) || os(iOS)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_mmap_\(UUID().uuidString).dat")

        // Create test file
        let testData = Data((0..<4096).map { UInt8($0 % 256) })
        try testData.write(to: tempURL)

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let mappedFile = J2KMemoryMappedFile()
        try mappedFile.mapFile(at: tempURL, mode: .readOnly, useNoCache: false)

        // Read data
        let readData = try mappedFile.read(offset: 0, length: 4096)
        XCTAssertEqual(readData, testData)

        try mappedFile.unmapFile()
        #else
        throw XCTSkip("Memory-mapped I/O tests require Darwin")
        #endif
    }

    func testMemoryMappedFilePartialRead() throws {
        #if os(macOS) || os(iOS)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_mmap_partial_\(UUID().uuidString).dat")

        let testData = Data((0..<4096).map { UInt8($0 % 256) })
        try testData.write(to: tempURL)

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let mappedFile = J2KMemoryMappedFile()
        try mappedFile.mapFile(at: tempURL, mode: .readOnly)

        // Read partial data
        let readData = try mappedFile.read(offset: 1024, length: 1024)
        XCTAssertEqual(readData.count, 1024)
        XCTAssertEqual(readData, testData.subdata(in: 1024..<2048))

        try mappedFile.unmapFile()
        #else
        throw XCTSkip("Memory-mapped I/O tests require Darwin")
        #endif
    }

    func testMemoryMappedFileReadWrite() throws {
        #if os(macOS) || os(iOS)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_mmap_rw_\(UUID().uuidString).dat")

        // Create test file
        let testData = Data(repeating: 0, count: 4096)
        try testData.write(to: tempURL)

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let mappedFile = J2KMemoryMappedFile()
        try mappedFile.mapFile(at: tempURL, mode: .readWrite)

        // Write data
        let newData = Data([1, 2, 3, 4, 5])
        try mappedFile.write(newData, at: 100)

        // Read it back
        let readData = try mappedFile.read(offset: 100, length: 5)
        XCTAssertEqual(readData, newData)

        try mappedFile.unmapFile()
        #else
        throw XCTSkip("Memory-mapped I/O tests require Darwin")
        #endif
    }

    // MARK: - SIMD-Aligned Buffer Tests

    func testSIMDAlignedBuffer16() throws {
        #if os(macOS) || os(iOS)
        let buffer = try J2KSIMDAlignedBuffer.allocate(size: 1024, alignment: .simd16)

        // Check alignment
        let address = UInt(bitPattern: buffer.pointer)
        XCTAssertEqual(address % 16, 0, "Buffer should be 16-byte aligned")

        XCTAssertEqual(buffer.size, 1024)
        XCTAssertEqual(buffer.alignment, .simd16)

        buffer.deallocate()
        #else
        throw XCTSkip("SIMD-aligned buffers require Darwin")
        #endif
    }

    func testSIMDAlignedBuffer64() throws {
        #if os(macOS) || os(iOS)
        let buffer = try J2KSIMDAlignedBuffer.allocate(size: 2048, alignment: .cache64)

        // Check alignment
        let address = UInt(bitPattern: buffer.pointer)
        XCTAssertEqual(address % 64, 0, "Buffer should be 64-byte aligned")

        buffer.deallocate()
        #else
        throw XCTSkip("SIMD-aligned buffers require Darwin")
        #endif
    }

    func testSIMDAlignedBufferAccess() throws {
        #if os(macOS) || os(iOS)
        let buffer = try J2KSIMDAlignedBuffer.allocate(size: 1024, alignment: .cache64)

        // Write and read data
        buffer.withMemoryRebound(to: UInt32.self) { ptr in
            ptr[0] = 0xDEADBEEF
            ptr[10] = 0xCAFEBABE
        }

        buffer.withMemoryRebound(to: UInt32.self) { ptr in
            XCTAssertEqual(ptr[0], 0xDEADBEEF)
            XCTAssertEqual(ptr[10], 0xCAFEBABE)
        }

        buffer.deallocate()
        #else
        throw XCTSkip("SIMD-aligned buffers require Darwin")
        #endif
    }

    // MARK: - Compressed Memory Monitor Tests

    func testCompressedMemoryMonitorInitialization() async throws {
        let monitor = J2KCompressedMemoryMonitor()

        await monitor.startMonitoring()

        let status = await monitor.currentStatus()
        XCTAssertNotNil(status)

        await monitor.stopMonitoring()
    }

    func testCompressedMemoryMonitorStatus() async throws {
        let monitor = J2KCompressedMemoryMonitor()

        await monitor.startMonitoring()

        let status = await monitor.currentStatus()

        // Should have a valid pressure level
        XCTAssertTrue([
            J2KCompressedMemoryMonitor.MemoryPressure.normal,
            .warning,
            .critical
        ].contains(status.pressure))

        await monitor.stopMonitoring()
    }

    // MARK: - Large Page Allocator Tests

    func testLargePageAllocatorSupport() {
        #if os(macOS) && arch(arm64)
        XCTAssertTrue(J2KLargePageAllocator.isSupported)
        XCTAssertEqual(J2KLargePageAllocator.largePageSize, 2 * 1024 * 1024)
        #else
        // On other platforms, may not be supported
        _ = J2KLargePageAllocator.isSupported
        #endif
    }

    func testLargePageAllocation() throws {
        let size = 4 * 1024 * 1024 // 4 MB
        let ptr = try J2KLargePageAllocator.allocate(size: size)

        XCTAssertNotEqual(ptr, UnsafeMutableRawPointer(bitPattern: 0))

        // Write and read
        ptr.storeBytes(of: UInt64(0x1234567890ABCDEF), as: UInt64.self)
        let value = ptr.load(as: UInt64.self)
        XCTAssertEqual(value, 0x1234567890ABCDEF)

        J2KLargePageAllocator.deallocate(ptr, size: size)
    }

    func testLargePageAllocationPerformance() throws {
        measure {
            do {
                let size = 10 * 1024 * 1024 // 10 MB
                let ptr = try J2KLargePageAllocator.allocate(size: size)

                // Touch all pages to ensure they're allocated
                for offset in stride(from: 0, to: size, by: 4096) {
                    ptr.advanced(by: offset).storeBytes(of: UInt8(42), as: UInt8.self)
                }

                J2KLargePageAllocator.deallocate(ptr, size: size)
            } catch {
                XCTFail("Large page allocation failed: \(error)")
            }
        }
    }
}
