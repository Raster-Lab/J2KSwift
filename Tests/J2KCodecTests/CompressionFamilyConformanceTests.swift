// Pin-down: J2KSwift's public types conform to the
// `CompressionFamily` protocol surface shared with JXLSwift.

import XCTest
import CompressionFamily
@testable import J2KCore
@testable import J2KCodec

final class CompressionFamilyConformanceTests: XCTestCase {

    /// `J2KImage` carries `width: Int, height: Int` matching
    /// the `CompressionImage` protocol.
    func testJ2KImage_isCompressionImage() throws {
        let image = J2KImage(width: 16, height: 32, components: [])
        let asProtocol: any CompressionImage = image
        XCTAssertEqual(asProtocol.width, 16)
        XCTAssertEqual(asProtocol.height, 32)
    }

    /// `J2KEncoder` conforms to `CompressionEncoder` with
    /// `Image = J2KImage` and `Output = Data` (`Data` carries
    /// the default `CompressionOutput` conformance).
    func testJ2KEncoder_isCompressionEncoder() throws {
        let enc = J2KEncoder()
        let asEncoder: any CompressionEncoder = enc
        // Type-system assertions (compile-time only).
        XCTAssertNotNil(asEncoder)
    }

    /// `J2KDecoder` conforms to `CompressionDecoder` with
    /// `Image = J2KImage`.
    func testJ2KDecoder_isCompressionDecoder() throws {
        let dec = J2KDecoder()
        let asDecoder: any CompressionDecoder = dec
        XCTAssertNotNil(asDecoder)
    }

    /// `J2KError` conforms to `CompressionError` (the umbrella
    /// protocol). Callers can `catch let e as CompressionError`.
    func testJ2KError_isCompressionError() throws {
        let err: any Error = J2KError.invalidParameter("test")
        XCTAssertTrue(err is CompressionError,
            "J2KError must conform to CompressionError")
        XCTAssertNotNil((err as? LocalizedError)?.errorDescription)
    }

    /// Generic-over-codec helper compiles and runs against
    /// J2KEncoder.
    func testGenericOverCompressionEncoder_acceptsJ2K() async throws {
        @Sendable
        func plumbViaProtocol<E: CompressionEncoder>(
            _ encoder: E, image: E.Image
        ) -> E {
            // Trivial helper — just verifies the constraint
            // resolves at compile time. Encoding itself isn't
            // exercised here (J2KEncoder needs full image data).
            _ = encoder
            _ = image
            return encoder
        }
        let enc = J2KEncoder()
        let img = J2KImage(width: 8, height: 8, components: [])
        let returned = plumbViaProtocol(enc, image: img)
        XCTAssertNotNil(returned)
    }
}
