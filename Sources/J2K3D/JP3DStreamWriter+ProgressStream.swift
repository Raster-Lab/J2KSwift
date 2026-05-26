// JP3DStreamWriter+ProgressStream.swift
//
// v10.18.0 — modern AsyncSequence progress reporting on JP3DStreamWriter.
// See JP3DDecoder+ProgressStream.swift for the consumer pattern.

import Foundation

extension JP3DStreamWriter {
    /// Returns an `AsyncStream` that yields the same `JP3DStreamProgress`
    /// values that would otherwise be delivered to ``setProgressCallback(_:)``.
    ///
    /// - Important: `async` so the relay closure is installed on the actor
    ///   before the stream is returned. Calling `progressStream()` a second
    ///   time overwrites the first stream's writer.
    public func progressStream() async -> AsyncStream<JP3DStreamProgress> {
        let (stream, continuation) = AsyncStream.makeStream(of: JP3DStreamProgress.self)
        self.setProgressCallback { progress in
            continuation.yield(progress)
        }
        return stream
    }
}
