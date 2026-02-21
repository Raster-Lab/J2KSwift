// BatchProcessing.swift
// J2KSwift Examples
//
// Demonstrates batch JPEG 2000 encoding and decoding using Swift structured
// concurrency (TaskGroup) for maximum throughput on multi-core hardware.

import Foundation
import J2KCore
import J2KCodec
import J2KFileFormat

// MARK: - Helper: create a named synthetic image

struct SyntheticImage {
    let name: String
    let image: J2KImage
}

func makeSyntheticImages(count: Int, width: Int = 128, height: Int = 128) -> [SyntheticImage] {
    (0 ..< count).map { idx in
        let pixel = UInt8((idx * 37) & 0xFF)
        let pixels = Data(repeating: pixel, count: width * height)
        let r = J2KComponent(index: 0, bitDepth: 8, signed: false, width: width, height: height, data: pixels)
        let g = J2KComponent(index: 1, bitDepth: 8, signed: false, width: width, height: height, data: pixels)
        let b = J2KComponent(index: 2, bitDepth: 8, signed: false, width: width, height: height, data: pixels)
        let img = J2KImage(width: width, height: height, components: [r, g, b])
        return SyntheticImage(name: "image_\(String(format: "%04d", idx))", image: img)
    }
}

// MARK: - Example 1: Sequential batch encode

func sequentialBatchEncode(images: [SyntheticImage]) throws -> [Data] {
    let encoder = J2KEncoder(configuration: .balanced)
    var results: [Data] = []
    results.reserveCapacity(images.count)

    for item in images {
        let data = try encoder.encode(item.image)
        results.append(data)
    }
    return results
}

// MARK: - Example 2: Parallel batch encode with TaskGroup

func parallelBatchEncode(images: [SyntheticImage]) async throws -> [Data] {
    // J2KEncoder is Sendable, so it is safe to share across concurrent tasks.
    let encoder = J2KEncoder(configuration: .balanced)

    return try await withThrowingTaskGroup(of: (Int, Data).self) { group in
        for (idx, item) in images.enumerated() {
            group.addTask {
                let data = try encoder.encode(item.image)
                return (idx, data)
            }
        }

        var results = [Data](repeating: Data(), count: images.count)
        for try await (idx, data) in group {
            results[idx] = data
        }
        return results
    }
}

// MARK: - Example 3: Batch decode

func batchDecode(encodedItems: [Data]) async throws -> [J2KImage] {
    let decoder = J2KDecoder()  // J2KDecoder is Sendable

    return try await withThrowingTaskGroup(of: (Int, J2KImage).self) { group in
        for (idx, data) in encodedItems.enumerated() {
            group.addTask {
                let image = try decoder.decode(data)
                return (idx, image)
            }
        }

        var results = [J2KImage?](repeating: nil, count: encodedItems.count)
        for try await (idx, image) in group {
            results[idx] = image
        }
        return results.compactMap { $0 }
    }
}

// MARK: - Example 4: Batch transcode to HTJ2K

func batchTranscodeToHTJ2K(standardJ2KItems: [Data]) async throws -> [Data] {
    let transcoder = J2KTranscoder()

    return try await withThrowingTaskGroup(of: (Int, Data).self) { group in
        for (idx, data) in standardJ2KItems.enumerated() {
            group.addTask {
                let htData = try transcoder.transcode(data, to: .htj2k)
                return (idx, htData)
            }
        }

        var results = [Data](repeating: Data(), count: standardJ2KItems.count)
        for try await (idx, htData) in group {
            results[idx] = htData
        }
        return results
    }
}

// MARK: - Example 5: Batch write to files

func batchWriteToDirectory(encodedItems: [(String, Data)], directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    for (name, data) in encodedItems {
        let url = directory.appendingPathComponent("\(name).jp2")
        try data.write(to: url)
    }
    print("Wrote \(encodedItems.count) files to \(directory.path)")
}

// MARK: - Example 6: Batch read from a directory

func batchReadFromDirectory(directory: URL) throws -> [J2KImage] {
    let reader = J2KFileReader()
    let urls   = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "jp2" }.sorted { $0.path < $1.path }

    return try urls.map { try reader.read(from: $0) }
}

// MARK: - Run examples

let images  = makeSyntheticImages(count: 8)
let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("j2k_batch")

let sema = DispatchSemaphore(value: 0)
Task {
    do {
        print("=== Example 1: Sequential batch encode (8 images) ===")
        let start1 = Date()
        let seqData = try sequentialBatchEncode(images: images)
        let elapsed1 = Date().timeIntervalSince(start1) * 1000
        print("Sequential: \(seqData.count) images in \(String(format: "%.1f", elapsed1)) ms")

        print("\n=== Example 2: Parallel batch encode (8 images) ===")
        let start2 = Date()
        let parData = try await parallelBatchEncode(images: images)
        let elapsed2 = Date().timeIntervalSince(start2) * 1000
        print("Parallel: \(parData.count) images in \(String(format: "%.1f", elapsed2)) ms")

        print("\n=== Example 3: Batch decode ===")
        let decoded = try await batchDecode(encodedItems: parData)
        print("Decoded \(decoded.count) images")

        print("\n=== Example 4: Batch transcode to HTJ2K ===")
        let htData = try await batchTranscodeToHTJ2K(standardJ2KItems: parData)
        print("Transcoded \(htData.count) images to HTJ2K")

        print("\n=== Example 5: Batch write to files ===")
        let namedData = zip(images.map(\.name), parData).map { ($0, $1) }
        try batchWriteToDirectory(encodedItems: namedData, directory: tempDir)

        print("\n=== Example 6: Batch read from directory ===")
        let readBack = try batchReadFromDirectory(directory: tempDir)
        print("Read back \(readBack.count) images from disk")

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    } catch {
        print("Error: \(error)")
    }
    sema.signal()
}
sema.wait()
