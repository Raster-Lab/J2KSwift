// JPIPStreaming.swift
// J2KSwift Examples
//
// Demonstrates JPIP (JPEG 2000 Interactive Protocol) client usage.
// These examples show the API surface; actual network calls require a
// live JPIP server. Replace "http://jpip.example.com/" with your server URL.

import Foundation
import J2KCore
import J2KCodec
import JPIP

// MARK: - Example 1: Create a JPIP client and session

/// Demonstrates session creation and full-image retrieval.
///
/// In a real deployment, `createSession` completes the JPIP handshake and
/// `requestImage` fetches all data-bins for the target image.
func jpipClientExample() async throws {
    let serverURL = URL(string: "http://jpip.example.com/")!

    // Instantiate the client (no network connection made here)
    let client = JPIPClient(serverURL: serverURL)

    print("Creating JPIP session for 'photo.jp2' …")
    print("(Network call skipped — no live server in this example)")

    // Production usage:
    //   let session = try await client.createSession(target: "photo.jp2")
    //   print("Session ID: \(session.sessionID)")
    //   let image = try await client.requestImage(imageID: "photo")
    //   try await client.close()

    print("JPIPClient created at: \(serverURL)")
    _ = client
}

// MARK: - Example 2: Progressive quality requests

/// Shows how to request successive quality layers for a progressive
/// render-as-it-arrives experience.
func progressiveQualityExample() async throws {
    let client = JPIPClient(serverURL: URL(string: "http://jpip.example.com/")!)

    print("\nProgressive quality ladder (imageID='photo'):")
    for layers in [1, 2, 4, 8] {
        print("  Layer \(layers): requestProgressiveQuality(imageID:\"photo\", upToLayers:\(layers))")
        // Production:
        // let draft = try await client.requestProgressiveQuality(imageID: "photo", upToLayers: layers)
        // renderPreview(draft)
    }
    _ = client
}

// MARK: - Example 3: Spatial region request

/// Demonstrates fetching only the pixels within a viewport region,
/// avoiding decompression of out-of-view tile data.
func spatialRegionExample() async throws {
    let client = JPIPClient(serverURL: URL(string: "http://jpip.example.com/")!)

    print("\nSpatial region request:")
    print("  origin=(512,256), size=256×256, resolutionLevel=2, layers=4")
    // Production:
    // let roi = try await client.requestRegion(
    //     imageID: "photo",
    //     regionX: 512, regionY: 256,
    //     regionWidth: 256, regionHeight: 256,
    //     resolutionLevel: 2, layers: 4
    // )
    _ = client
}

// MARK: - Example 4: Resolution-level thumbnails

/// Shows how to request successively finer resolution levels to build
/// a multi-scale image pyramid.
func resolutionThumbnailExample() async throws {
    let client = JPIPClient(serverURL: URL(string: "http://jpip.example.com/")!)

    print("\nResolution pyramid for 'photo':")
    for level in 0 ... 4 {
        let divisor = 1 << level
        print("  Level \(level) → 1/\(divisor) resolution: requestResolutionLevel(level:\(level))")
        // Production:
        // let thumb = try await client.requestResolutionLevel(imageID: "photo", level: level)
    }
    _ = client
}

// MARK: - Example 5: Component selection

/// Demonstrates fetching only the luminance component for a fast
/// greyscale preview, reducing data transfer.
func componentSelectionExample() async throws {
    let client = JPIPClient(serverURL: URL(string: "http://jpip.example.com/")!)

    print("\nComponent selection (luminance only):")
    print("  requestComponents(imageID:\"photo\", components:[0], layers:4)")
    // Production:
    // let gray = try await client.requestComponents(imageID: "photo", components: [0], layers: 4)
    _ = client
}

// MARK: - Example 6: Image metadata

/// Shows how to retrieve image dimensions and component metadata without
/// fetching any pixel data.
func metadataExample() async throws {
    let client = JPIPClient(serverURL: URL(string: "http://jpip.example.com/")!)

    print("\nMetadata for 'photo':")
    print("  requestMetadata(imageID:\"photo\")")
    // Production:
    // let meta = try await client.requestMetadata(imageID: "photo")
    // print("  Width: \(meta["width"] as? Int ?? 0)")
    // print("  Components: \(meta["components"] as? Int ?? 0)")
    _ = client
}

// MARK: - Run examples

let sema = DispatchSemaphore(value: 0)
Task {
    do {
        print("=== Example 1: JPIP client session ===")
        try await jpipClientExample()

        print("\n=== Example 2: Progressive quality ===")
        try await progressiveQualityExample()

        print("\n=== Example 3: Spatial region ===")
        try await spatialRegionExample()

        print("\n=== Example 4: Resolution thumbnail ===")
        try await resolutionThumbnailExample()

        print("\n=== Example 5: Component selection ===")
        try await componentSelectionExample()

        print("\n=== Example 6: Metadata ===")
        try await metadataExample()
    } catch {
        print("Error: \(error)")
    }
    sema.signal()
}
sema.wait()
