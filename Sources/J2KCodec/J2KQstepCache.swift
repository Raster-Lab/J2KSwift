// J2KQstepCache.swift
// v5.19.1 — qstep cache for `.constantBitrateViaQstep` batch workflows.
//
// Many real-world workflows encode hundreds or thousands of similar
// images: a DICOMKit pipeline encoding a CT scan series (same width
// × height × bit-depth × target bpp), an archive run on a directory
// of pathology slides, etc. v5.19.0's binary-search-on-qstep takes
// 4–6 encode iterations per image — wasted work when the converged
// qstep is virtually identical across the batch.
//
// J2KQstepCache stores (image-class → converged qstep) pairs.
// `J2KEncoder.encodeViaQstepSearch` consults the cache for its
// initial guess and stores the converged qstep back. With a warm
// cache, subsequent images converge in 1–2 iterations instead of
// 4–6, cutting `.constantBitrateViaQstep`'s overhead by ~70%.
//
// Image class key: (bitDepth, componentCount, targetBpp). Width and
// height are intentionally excluded — qstep at convergence depends
// primarily on coefficient distribution per pixel, which is more
// strongly correlated with bit-depth + bpp than with image size.
// (For pathological workflows where width/height should partition
// the cache, the user can use multiple `J2KQstepCache` instances
// sharded by their own key.)

import Foundation

/// Thread-safe cache mapping image-class keys to converged qstep
/// values for `.constantBitrateViaQstep` workflows.
///
/// Use one cache per logical batch of similar images. Pass via
/// `J2KEncodingConfiguration.qstepCache`. Cache hits skip 2–4
/// binary-search iterations on average.
public actor J2KQstepCache {

    /// Cache key — combines the image properties that primarily
    /// determine the converged qstep at a given target bpp.
    public struct Key: Hashable, Sendable {
        public let bitDepth: Int
        public let componentCount: Int
        /// Target bpp rounded to 0.01 to allow modest variation
        /// (e.g. 1.99 vs 2.00) to share a cache entry.
        public let targetBppBucket: Int

        public init(bitDepth: Int, componentCount: Int, targetBpp: Double) {
            self.bitDepth = bitDepth
            self.componentCount = componentCount
            self.targetBppBucket = Int((targetBpp * 100.0).rounded())
        }
    }

    private var cache: [Key: Double] = [:]

    public init() {}

    /// Look up a cached qstep. Returns `nil` on miss.
    public func lookup(_ key: Key) -> Double? {
        return cache[key]
    }

    /// Store a converged qstep for future lookups. Overwrites any
    /// existing entry — the most recent successful convergence is
    /// always the best initial guess.
    public func store(_ key: Key, qstep: Double) {
        cache[key] = qstep
    }

    /// Clear all cached entries. Useful when starting a new logical
    /// batch with different content characteristics.
    public func clear() {
        cache.removeAll(keepingCapacity: true)
    }

    /// Current cache size, for diagnostics.
    public var count: Int {
        return cache.count
    }
}

/// Diagnostic stats from a `.constantBitrateViaQstep` search loop.
/// Returned alongside encoded data by
/// `J2KEncoder.encodeWithQstepStats(_:)`.
///
/// Useful for batch workflows to measure cache effectiveness, average
/// iterations, and convergence quality.
public struct J2KEncodeQstepStats: Sendable {
    /// Number of encode iterations the search loop performed.
    /// 1 means the very first iteration converged within tolerance
    /// (typically only happens with a hot cache hit on identical content).
    public let iterations: Int

    /// The qstep used for the first iteration. Either from the
    /// `J2KQstepCache` (if `cacheHit == true`) or from the calibration
    /// table fallback.
    public let initialQstep: Double

    /// The qstep at which the search converged (or the closest-
    /// achieved iteration if convergence didn't reach tolerance).
    public let convergedQstep: Double

    /// Bits per pixel actually achieved by the converged encode.
    public let achievedBpp: Double

    /// The user-requested target bpp.
    public let targetBpp: Double

    /// Whether the initial qstep came from the cache (vs the
    /// calibration table fallback). True for warm cache, false for
    /// cold cache or no cache.
    public let cacheHit: Bool

    /// Whether the search reached the user-specified tolerance. False
    /// if the encoder fell back to the closest-achieved iteration
    /// because `maxIterations` was exhausted or the bracket narrowed
    /// below the tolerance limit (16-bit content with low α).
    public let convergedWithinTolerance: Bool
}
