// JP3DROIDecoder+ProgressStream.swift
//
// v10.18.0 — modern AsyncSequence progress reporting on JP3DROIDecoder.
// See JP3DDecoder+ProgressStream.swift for the consumer pattern.

import Foundation

extension JP3DROIDecoder {
    /// Returns an `AsyncStream` that yields the same `JP3DDecoderProgress`
    /// values that would otherwise be delivered to ``setProgressCallback(_:)``.
    ///
    /// - Important: `async` so the relay closure is installed on the actor
    ///   before the stream is returned. Calling `progressStream()` a second
    ///   time overwrites the first stream's writer.
    public func progressStream() async -> AsyncStream<JP3DDecoderProgress> {
        let (stream, continuation) = AsyncStream.makeStream(of: JP3DDecoderProgress.self)
        self.setProgressCallback { progress in
            continuation.yield(progress)
        }
        return stream
    }
}
