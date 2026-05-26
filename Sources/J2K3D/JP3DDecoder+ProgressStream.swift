// JP3DDecoder+ProgressStream.swift
//
// v10.18.0 — modern AsyncSequence progress reporting alongside the
// existing `setProgressCallback(_:)` closure API (which remains
// supported indefinitely). Pure additive surface — no existing
// behaviour change.
//
// Consumer pattern (idiomatic Swift concurrency):
//
//     let decoder = JP3DDecoder()
//     let progressStream = await decoder.progressStream()
//
//     // Spawn a child task to drive progress UI updates:
//     async let progressDisplay: Void = {
//         for await progress in progressStream {
//             print("\(progress.stage): \(Int(progress.overallProgress * 100))%")
//         }
//     }()
//
//     // Decode produces progress events that flow through the stream:
//     let result = try await decoder.decode(data)
//     _ = await progressDisplay  // join the progress task
//
// Lifecycle: `progressStream()` is `async` and synchronously installs
// the relay closure on the actor before returning the stream — no
// race window where early progress events are missed. When the
// consumer stops iterating (loop ends, task cancellation), the
// continuation terminates and the actor's stored closure becomes a
// no-op writer to a finished continuation. The next call to
// `progressStream()` or `setProgressCallback(_:)` overwrites the
// closure.

import Foundation

extension JP3DDecoder {
    /// Returns an `AsyncStream` that yields the same `JP3DDecoderProgress`
    /// values that would otherwise be delivered to a closure registered
    /// via ``setProgressCallback(_:)``.
    ///
    /// Calling `progressStream()` installs the stream's writer as the
    /// decoder's progress callback. If a prior `setProgressCallback(_:)`
    /// closure was registered, it is overwritten — use one or the other,
    /// not both. Calling `progressStream()` a second time also overwrites
    /// the first stream's writer; the first stream's continuation
    /// receives no further events but isn't explicitly finished.
    ///
    /// - Important: This is `async` so the relay closure is installed
    ///   on the actor before the stream is returned. The consumer is
    ///   guaranteed to receive every progress event fired after the
    ///   `await` returns.
    public func progressStream() async -> AsyncStream<JP3DDecoderProgress> {
        let (stream, continuation) = AsyncStream.makeStream(of: JP3DDecoderProgress.self)
        self.setProgressCallback { progress in
            continuation.yield(progress)
        }
        return stream
    }
}
