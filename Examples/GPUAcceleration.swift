// GPUAcceleration.swift
// J2KSwift Examples
//
// Demonstrates Metal GPU-accelerated encoding pipeline on Apple platforms.
// On non-Apple platforms the actors automatically fall back to CPU processing.

import Foundation
import J2KCore
import J2KCodec

#if canImport(J2KMetal)
import J2KMetal
#endif

// MARK: - Helper

func makeImageData(width: Int, height: Int) -> Data {
    var data = Data(capacity: width * height)
    for i in 0 ..< width * height {
        data.append(UInt8((i * 3 + 37) & 0xFF))
    }
    return data
}

// MARK: - Example 1: Initialise Metal device

func metalDeviceExample() throws {
#if canImport(J2KMetal)
    let device = J2KMetalDevice()
    try device.initialize()
    print("GPU: \(device.deviceName())")
    print("Tier: \(device.featureTier())")
    let mb = device.maxWorkingSetSize() / (1024 * 1024)
    print("Max working set: \(mb) MB")
#else
    print("Metal not available on this platform; skipping example 1")
#endif
}

// MARK: - Example 2: GPU-accelerated colour transform (ICT)

func metalColourTransformExample() async throws {
#if canImport(J2KMetal)
    let width  = 256
    let height = 256
    let r = makeImageData(width: width, height: height)
    let g = makeImageData(width: width, height: height)
    let b = makeImageData(width: width, height: height)

    let actor  = J2KMetalColorTransform()
    let config = J2KMetalColorTransformConfiguration(
        transform: .ict,
        componentCount: 3
    )

    let result: J2KMetalColorTransformResult = try await actor.forward(
        componentData: [r, g, b],
        configuration: config
    )

    let stats: J2KMetalColorTransformStatistics = await actor.statistics()
    print("\nICT colour transform: \(result.transformedData.count) bytes output")
    print("GPU passes: \(stats.gpuPassCount), CPU fallbacks: \(stats.cpuFallbackCount)")
#else
    print("Metal not available on this platform; skipping example 2")
#endif
}

// MARK: - Example 3: GPU-accelerated 2-D DWT

func metalDWTExample() async throws {
#if canImport(J2KMetal)
    let width  = 256
    let height = 256
    let pixels = makeImageData(width: width, height: height)

    let dwtActor = J2KMetalDWT()
    try await dwtActor.initialize()

    let coefficients = try await dwtActor.forward2D(
        pixels,
        width: width,
        height: height,
        filter: .cdf97
    )
    print("\nForward DWT output: \(coefficients.count) bytes")

    let restored = try await dwtActor.inverse2D(
        coefficients,
        width: width,
        height: height,
        filter: .cdf97
    )
    print("Inverse DWT restored: \(restored.count) bytes")

    let stats = await dwtActor.statistics()
    print("DWT GPU passes: \(stats.gpuPassCount)")
#else
    print("Metal not available on this platform; skipping example 3")
#endif
}

// MARK: - Example 4: GPU-accelerated multi-level DWT

func metalMultiLevelDWTExample() async throws {
#if canImport(J2KMetal)
    let width  = 512
    let height = 512
    let pixels = makeImageData(width: width, height: height)

    let dwtActor = J2KMetalDWT()
    try await dwtActor.initialize()

    let levels = 5
    let multiCoeff = try await dwtActor.forwardMultiLevel(
        pixels,
        width: width,
        height: height,
        levels: levels,
        filter: .leGall53
    )
    print("\n\(levels)-level multi-level DWT: \(multiCoeff.count) bytes")

    let back = try await dwtActor.inverseMultiLevel(
        multiCoeff,
        width: width,
        height: height,
        levels: levels,
        filter: .leGall53
    )
    print("Reconstructed: \(back.count) bytes")
#else
    print("Metal not available on this platform; skipping example 4")
#endif
}

// MARK: - Example 5: GPU quantisation

func metalQuantizerExample() async throws {
#if canImport(J2KMetal)
    let coefficients = makeImageData(width: 256, height: 256)

    let quantizer = J2KMetalQuantizer()
    let qConfig   = J2KMetalQuantizationConfiguration(
        stepSizes: [0.1, 0.2, 0.4],
        deadzone: true
    )

    let qResult: J2KMetalQuantizationResult = try await quantizer.quantize(
        coefficients,
        configuration: qConfig
    )
    print("\nQuantised: \(qResult.quantizedData.count) bytes")

    let dqResult: J2KMetalDequantizationResult = try await quantizer.dequantize(
        qResult.quantizedData,
        configuration: qConfig
    )
    print("Dequantised: \(dqResult.coefficients.count) bytes")
#else
    print("Metal not available on this platform; skipping example 5")
#endif
}

// MARK: - Run all examples

do {
    print("=== Example 1: Metal device ===")
    try metalDeviceExample()
} catch {
    print("Device init error: \(error)")
}

let sema = DispatchSemaphore(value: 0)
Task {
    do {
        print("\n=== Example 2: Colour transform ===")
        try await metalColourTransformExample()

        print("\n=== Example 3: 2-D DWT ===")
        try await metalDWTExample()

        print("\n=== Example 4: Multi-level DWT ===")
        try await metalMultiLevelDWTExample()

        print("\n=== Example 5: Quantisation ===")
        try await metalQuantizerExample()
    } catch {
        print("Error: \(error)")
    }
    sema.signal()
}
sema.wait()
