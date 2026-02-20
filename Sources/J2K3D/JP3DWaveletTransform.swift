//
// JP3DWaveletTransform.swift
// J2KSwift
//
// JP3DWaveletTransform.swift
// J2KSwift
//
// Implements the 3D Discrete Wavelet Transform for JP3D (ISO/IEC 15444-10).
// Weeks 214–217: separable and full-3D modes with 5/3 and 9/7 filters.

import Foundation
import J2KCore

// MARK: - Filter Type

/// Wavelet filter kernel for 3D DWT operations.
///
/// Two standard JPEG 2000 filters are provided:
/// - ``reversible53``: Le Gall 5/3 – integer-arithmetic lifting, lossless-capable.
/// - ``irreversible97``: CDF 9/7 – floating-point lifting, higher compression ratio.
public enum JP3DWaveletFilter: Sendable {
    /// Le Gall 5/3 reversible filter (integer arithmetic, lossless-capable).
    case reversible53
    /// CDF 9/7 irreversible filter (floating-point, higher compression efficiency).
    case irreversible97
}

// MARK: - Transform Mode

/// Axis ordering strategy for the 3D DWT.
///
/// Both modes produce mathematically equivalent results for separable filters.
public enum JP3DTransformMode: Sendable {
    /// Apply X, Y, and Z filtering in a single conceptual 3D pass.
    ///
    /// Implemented as sequential separable passes (X → Y → Z), which is
    /// equivalent to a simultaneous 3D separable transform for all standard
    /// JPEG 2000 filters.
    case full3D
    /// Apply 2D XY transform first, then 1D Z transform.
    case separable
}

// MARK: - Boundary Extension Mode

/// Boundary extension strategy applied at signal edges during convolution.
public enum JP3DBoundaryMode: Sendable {
    /// Whole-sample symmetric (mirror) extension.
    case symmetric
    /// Periodic (wrap-around) extension.
    case periodic
    /// Zero-padding extension.
    case zeroPadding
}

// MARK: - Configuration

/// Configuration for the JP3D 3D discrete wavelet transform.
///
/// Specifies the filter, transform mode, boundary handling, and the number of
/// decomposition levels along each axis.
///
/// ## Presets
///
/// ```swift
/// let lossless = JP3DTransformConfiguration.defaultLossless
/// let lossy    = JP3DTransformConfiguration.defaultLossy
/// ```
public struct JP3DTransformConfiguration: Sendable {
    /// Wavelet filter kernel to apply.
    public let filter: JP3DWaveletFilter
    /// Axis ordering strategy.
    public let mode: JP3DTransformMode
    /// Boundary extension mode.
    public let boundary: JP3DBoundaryMode
    /// Number of decomposition levels along the X axis.
    public let levelsX: Int
    /// Number of decomposition levels along the Y axis.
    public let levelsY: Int
    /// Number of decomposition levels along the Z axis.
    public let levelsZ: Int

    /// Creates a transform configuration.
    ///
    /// - Parameters:
    ///   - filter: Wavelet filter kernel. Defaults to ``JP3DWaveletFilter/reversible53``.
    ///   - mode: Transform mode. Defaults to ``JP3DTransformMode/separable``.
    ///   - boundary: Boundary extension. Defaults to ``JP3DBoundaryMode/symmetric``.
    ///   - levelsX: Decomposition levels along X. Defaults to 3.
    ///   - levelsY: Decomposition levels along Y. Defaults to 3.
    ///   - levelsZ: Decomposition levels along Z. Defaults to 1.
    public init(
        filter: JP3DWaveletFilter = .reversible53,
        mode: JP3DTransformMode = .separable,
        boundary: JP3DBoundaryMode = .symmetric,
        levelsX: Int = 3,
        levelsY: Int = 3,
        levelsZ: Int = 1
    ) {
        self.filter = filter
        self.mode = mode
        self.boundary = boundary
        self.levelsX = max(0, levelsX)
        self.levelsY = max(0, levelsY)
        self.levelsZ = max(0, levelsZ)
    }

    /// Default lossless configuration: 5/3 filter, separable mode, 3/3/1 levels.
    public static let defaultLossless = JP3DTransformConfiguration(
        filter: .reversible53, mode: .separable, boundary: .symmetric,
        levelsX: 3, levelsY: 3, levelsZ: 1
    )

    /// Default lossy configuration: 9/7 filter, separable mode, 3/3/1 levels.
    public static let defaultLossy = JP3DTransformConfiguration(
        filter: .irreversible97, mode: .separable, boundary: .symmetric,
        levelsX: 3, levelsY: 3, levelsZ: 1
    )
}

// MARK: - Result Type

/// The result of a 3D wavelet forward transform.
///
/// All subband data is stored in a single flat ``J2K3DCoefficients`` buffer
/// (same dimensions as the input). The LLL subband occupies indices
/// `[0..<lllDepth, 0..<lllHeight, 0..<lllWidth]`, and detail subbands fill
/// the remaining spatial quadrants – exactly as in standard JPEG 2000 tiling.
///
/// ## Reconstruction
///
/// Pass this value directly to ``JP3DWaveletTransform/inverse(decomposition:)``
/// to recover the original signal.
public struct JP3DSubbandDecomposition: Sendable {
    /// Width of the coefficient array (equals original width).
    public let width: Int
    /// Height of the coefficient array (equals original height).
    public let height: Int
    /// Depth of the coefficient array (equals original depth).
    public let depth: Int
    /// Number of decomposition levels applied along X.
    public let levelsX: Int
    /// Number of decomposition levels applied along Y.
    public let levelsY: Int
    /// Number of decomposition levels applied along Z.
    public let levelsZ: Int
    /// All subband coefficients stored in a flat in-place layout.
    public var coefficients: J2K3DCoefficients
    /// Original signal width before transform.
    public let originalWidth: Int
    /// Original signal height before transform.
    public let originalHeight: Int
    /// Original signal depth before transform.
    public let originalDepth: Int
}

// MARK: - Actor

/// Three-dimensional discrete wavelet transform for JP3D volumetric data.
///
/// `JP3DWaveletTransform` implements the 3D separable DWT specified in
/// ISO/IEC 15444-10 (JP3D). It supports both the reversible Le Gall 5/3 and
/// the irreversible CDF 9/7 lifting filters, symmetric / periodic / zero-padding
/// boundary extension, and configurable decomposition levels per axis.
///
/// ## Usage
///
/// ```swift
/// let transform = JP3DWaveletTransform()
///
/// // Forward transform
/// let decomp = try await transform.forward(
///     data: volumeFloats, width: 64, height: 64, depth: 16
/// )
///
/// // Inverse transform – reconstructs original signal
/// let reconstructed = try await transform.inverse(decomposition: decomp)
/// ```
///
/// ## Transform Layout
///
/// After a forward transform the coefficients are stored **in-place**: the LLL
/// approximation occupies the low-frequency corner and detail subbands fill the
/// remaining quadrants, mirroring the standard JPEG 2000 subband layout extended
/// to three dimensions.
public actor JP3DWaveletTransform {
    // MARK: - State

    private let configuration: JP3DTransformConfiguration

    // MARK: - Init

    /// Creates a wavelet transform processor with the given configuration.
    ///
    /// - Parameter configuration: Transform configuration. Defaults to
    ///   ``JP3DTransformConfiguration/defaultLossless``.
    public init(configuration: JP3DTransformConfiguration = .defaultLossless) {
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Performs a forward 3D DWT on flat volume data.
    ///
    /// - Parameters:
    ///   - data: Volume samples in row-major order: index = `z*width*height + y*width + x`.
    ///   - width: Number of voxels along X.
    ///   - height: Number of voxels along Y.
    ///   - depth: Number of voxels along Z.
    /// - Returns: ``JP3DSubbandDecomposition`` containing all wavelet coefficients.
    /// - Throws: ``J2KError/invalidParameter(_:)`` when dimensions are invalid.
    public func forward(
        data: [Float],
        width: Int,
        height: Int,
        depth: Int
    ) async throws -> JP3DSubbandDecomposition {
        guard width > 0, height > 0, depth > 0 else {
            throw J2KError.invalidParameter("Dimensions must be positive: \(width)×\(height)×\(depth)")
        }
        guard data.count == width * height * depth else {
            throw J2KError.invalidParameter(
                "Data count \(data.count) does not match \(width)×\(height)×\(depth) = \(width * height * depth)"
            )
        }

        // Clamp requested levels to the maximum meaningful for each axis
        let maxLX = maxLevels(for: width)
        let maxLY = maxLevels(for: height)
        let maxLZ = maxLevels(for: depth)
        let lx = min(configuration.levelsX, maxLX)
        let ly = min(configuration.levelsY, maxLY)
        let lz = min(configuration.levelsZ, maxLZ)

        var buf = data
        applyForward3D(&buf, width: width, height: height, depth: depth,
                       levelsX: lx, levelsY: ly, levelsZ: lz)

        let coeffs = J2K3DCoefficients(
            width: width, height: height, depth: depth,
            decompositionLevels: max(lx, ly, lz),
            data: buf
        )

        return JP3DSubbandDecomposition(
            width: width, height: height, depth: depth,
            levelsX: lx, levelsY: ly, levelsZ: lz,
            coefficients: coeffs,
            originalWidth: width, originalHeight: height, originalDepth: depth
        )
    }

    /// Performs an inverse 3D DWT, reconstructing the original signal.
    ///
    /// - Parameter decomposition: The ``JP3DSubbandDecomposition`` produced by
    ///   ``forward(data:width:height:depth:)``.
    /// - Returns: Reconstructed volume samples in the same row-major layout.
    /// - Throws: ``J2KError/invalidParameter(_:)`` when the decomposition is malformed.
    public func inverse(
        decomposition: JP3DSubbandDecomposition
    ) async throws -> [Float] {
        let width  = decomposition.width
        let height = decomposition.height
        let depth  = decomposition.depth
        guard width > 0, height > 0, depth > 0 else {
            throw J2KError.invalidParameter("Decomposition has invalid dimensions")
        }
        guard decomposition.coefficients.data.count == width * height * depth else {
            throw J2KError.invalidParameter("Coefficient buffer size mismatch")
        }

        var buf = decomposition.coefficients.data
        applyInverse3D(
            &buf, width: width, height: height, depth: depth,
            levelsX: decomposition.levelsX,
            levelsY: decomposition.levelsY,
            levelsZ: decomposition.levelsZ
        )
        return buf
    }

    // MARK: - Forward 3D (separable / full3D)

    private func applyForward3D(
        _ buf: inout [Float],
        width: Int, height: Int, depth: Int,
        levelsX: Int, levelsY: Int, levelsZ: Int
    ) {
        // Both modes use sequential separable passes (X → Y → Z).
        // For full3D the pass order is identical; see documentation note.
        var curW = width, curH = height, curD = depth

        // We decompose the LLL subband iteratively.
        // Each level reduces the active region to ceil(dim/2) along axes where
        // levels remain.
        for lvl in 0..<max(levelsX, max(levelsY, levelsZ)) {
            let doX = lvl < levelsX
            let doY = lvl < levelsY
            let doZ = lvl < levelsZ

            if doX {
                forwardX(&buf, totalW: width, totalH: height, totalD: depth,
                         activeW: curW, activeH: curH, activeD: curD)
            }
            if doY {
                forwardY(&buf, totalW: width, totalH: height, totalD: depth,
                         activeW: curW, activeH: curH, activeD: curD)
            }
            if doZ {
                forwardZ(&buf, totalW: width, totalH: height, totalD: depth,
                         activeW: curW, activeH: curH, activeD: curD)
            }

            // Shrink active region to the LLL subband for the next level
            if doX { curW = (curW + 1) / 2 }
            if doY { curH = (curH + 1) / 2 }
            if doZ { curD = (curD + 1) / 2 }
        }
    }

    // MARK: - Inverse 3D

    private func applyInverse3D(
        _ buf: inout [Float],
        width: Int, height: Int, depth: Int,
        levelsX: Int, levelsY: Int, levelsZ: Int
    ) {
        // Build the active-region size stack (same as forward pass)
        var wStack = [Int](), hStack = [Int](), dStack = [Int]()
        var curW = width, curH = height, curD = depth
        for lvl in 0..<max(levelsX, max(levelsY, levelsZ)) {
            wStack.append(curW); hStack.append(curH); dStack.append(curD)
            if lvl < levelsX { curW = (curW + 1) / 2 }
            if lvl < levelsY { curH = (curH + 1) / 2 }
            if lvl < levelsZ { curD = (curD + 1) / 2 }
        }

        // Unwind in reverse
        let maxLevel = max(levelsX, max(levelsY, levelsZ))
        for lvl in stride(from: maxLevel - 1, through: 0, by: -1) {
            let aw = wStack[lvl], ah = hStack[lvl], ad = dStack[lvl]
            let doZ = lvl < levelsZ
            let doY = lvl < levelsY
            let doX = lvl < levelsX

            if doZ {
                inverseZ(&buf, totalW: width, totalH: height, totalD: depth,
                         activeW: aw, activeH: ah, activeD: ad)
            }
            if doY {
                inverseY(&buf, totalW: width, totalH: height, totalD: depth,
                         activeW: aw, activeH: ah, activeD: ad)
            }
            if doX {
                inverseX(&buf, totalW: width, totalH: height, totalD: depth,
                         activeW: aw, activeH: ah, activeD: ad)
            }
        }
    }

    // MARK: - Axis Passes (Forward)

    /// Forward DWT along X for every row in the active region.
    private func forwardX(
        _ buf: inout [Float],
        totalW: Int, totalH: Int, totalD: Int,
        activeW: Int, activeH: Int, activeD: Int
    ) {
        guard activeW > 1 else { return }
        var row = [Float](repeating: 0, count: activeW)
        for z in 0..<activeD {
            for y in 0..<activeH {
                let base = z * totalW * totalH + y * totalW
                for x in 0..<activeW { row[x] = buf[base + x] }
                forwardDWT1D(&row)
                for x in 0..<activeW { buf[base + x] = row[x] }
            }
        }
    }

    /// Forward DWT along Y for every column in the active region.
    private func forwardY(
        _ buf: inout [Float],
        totalW: Int, totalH: Int, totalD: Int,
        activeW: Int, activeH: Int, activeD: Int
    ) {
        guard activeH > 1 else { return }
        var col = [Float](repeating: 0, count: activeH)
        for z in 0..<activeD {
            for x in 0..<activeW {
                let zBase = z * totalW * totalH
                for y in 0..<activeH { col[y] = buf[zBase + y * totalW + x] }
                forwardDWT1D(&col)
                for y in 0..<activeH { buf[zBase + y * totalW + x] = col[y] }
            }
        }
    }

    /// Forward DWT along Z for every pillar in the active region.
    private func forwardZ(
        _ buf: inout [Float],
        totalW: Int, totalH: Int, totalD: Int,
        activeW: Int, activeH: Int, activeD: Int
    ) {
        guard activeD > 1 else { return }
        let sliceSize = totalW * totalH
        var pillar = [Float](repeating: 0, count: activeD)
        for y in 0..<activeH {
            for x in 0..<activeW {
                let yx = y * totalW + x
                for z in 0..<activeD { pillar[z] = buf[z * sliceSize + yx] }
                forwardDWT1D(&pillar)
                for z in 0..<activeD { buf[z * sliceSize + yx] = pillar[z] }
            }
        }
    }

    // MARK: - Axis Passes (Inverse)

    private func inverseX(
        _ buf: inout [Float],
        totalW: Int, totalH: Int, totalD: Int,
        activeW: Int, activeH: Int, activeD: Int
    ) {
        guard activeW > 1 else { return }
        var row = [Float](repeating: 0, count: activeW)
        for z in 0..<activeD {
            for y in 0..<activeH {
                let base = z * totalW * totalH + y * totalW
                for x in 0..<activeW { row[x] = buf[base + x] }
                inverseDWT1D(&row)
                for x in 0..<activeW { buf[base + x] = row[x] }
            }
        }
    }

    private func inverseY(
        _ buf: inout [Float],
        totalW: Int, totalH: Int, totalD: Int,
        activeW: Int, activeH: Int, activeD: Int
    ) {
        guard activeH > 1 else { return }
        var col = [Float](repeating: 0, count: activeH)
        for z in 0..<activeD {
            for x in 0..<activeW {
                let zBase = z * totalW * totalH
                for y in 0..<activeH { col[y] = buf[zBase + y * totalW + x] }
                inverseDWT1D(&col)
                for y in 0..<activeH { buf[zBase + y * totalW + x] = col[y] }
            }
        }
    }

    private func inverseZ(
        _ buf: inout [Float],
        totalW: Int, totalH: Int, totalD: Int,
        activeW: Int, activeH: Int, activeD: Int
    ) {
        guard activeD > 1 else { return }
        let sliceSize = totalW * totalH
        var pillar = [Float](repeating: 0, count: activeD)
        for y in 0..<activeH {
            for x in 0..<activeW {
                let yx = y * totalW + x
                for z in 0..<activeD { pillar[z] = buf[z * sliceSize + yx] }
                inverseDWT1D(&pillar)
                for z in 0..<activeD { buf[z * sliceSize + yx] = pillar[z] }
            }
        }
    }

    // MARK: - 1D DWT Dispatch

    /// Forward 1D DWT applied to a signal in place.
    ///
    /// The output is interleaved: `[L0, L1, …, H0, H1, …]`
    /// (lowpass samples first, then highpass samples).
    private func forwardDWT1D(_ signal: inout [Float]) {
        let n = signal.count
        guard n > 1 else { return }
        switch configuration.filter {
        case .reversible53:  forward53(&signal)
        case .irreversible97: forward97(&signal)
        }
    }

    /// Inverse 1D DWT applied to an interleaved coefficient signal in place.
    private func inverseDWT1D(_ signal: inout [Float]) {
        let n = signal.count
        guard n > 1 else { return }
        switch configuration.filter {
        case .reversible53:  inverse53(&signal)
        case .irreversible97: inverse97(&signal)
        }
    }

    // MARK: - 5/3 Lifting (Le Gall)

    /// Forward Le Gall 5/3 lifting transform.
    ///
    /// Lifting steps:
    /// 1. Predict (highpass): `H[n] = x[2n+1] − ⌊(x[2n] + x[2n+2]) / 2⌋`
    /// 2. Update  (lowpass):  `L[n] = x[2n]   + ⌊(H[n−1] + H[n] + 2) / 4⌋`
    private func forward53(_ x: inout [Float]) {
        let n = x.count
        let nL = (n + 1) / 2   // number of lowpass samples
        let nH = n / 2          // number of highpass samples

        // Work on a copy extended symmetrically at boundaries
        let ext = extendSymmetric(x, leftPad: 1, rightPad: 2)
        let off = 1 // offset due to left pad

        // Predict step
        var h = [Float](repeating: 0, count: nH)
        for i in 0..<nH {
            let idx = off + 2 * i  // points to x[2i] in extended array
            h[i] = ext[idx + 1] - floor((ext[idx] + ext[idx + 2]) * 0.5)
        }

        // Update step — need H[−1] for L[0]; use symmetric extension: H[−1] = H[0]
        var l = [Float](repeating: 0, count: nL)
        for i in 0..<nL {
            let hPrev = (i == 0) ? h[0] : h[i - 1]
            let hCurr = (i < nH) ? h[i] : h[nH - 1]
            l[i] = ext[off + 2 * i] + floor((hPrev + hCurr + 2) * 0.25)
        }

        // Write back: lowpass first, then highpass
        for i in 0..<nL { x[i]      = l[i] }
        for i in 0..<nH { x[nL + i] = h[i] }
    }

    /// Inverse Le Gall 5/3 lifting transform.
    private func inverse53(_ x: inout [Float]) {
        let n = x.count
        let nL = (n + 1) / 2
        let nH = n / 2

        let l = Array(x[0..<nL])
        let h = Array(x[nL..<nL + nH])

        // Undo update: x[2n] = L[n] − ⌊(H[n−1] + H[n] + 2) / 4⌋
        var even = [Float](repeating: 0, count: nL)
        for i in 0..<nL {
            let hPrev = (i == 0) ? h[0] : h[i - 1]
            let hCurr = (i < nH) ? h[i] : h[nH - 1]
            even[i] = l[i] - floor((hPrev + hCurr + 2) * 0.25)
        }

        // Undo predict: x[2n+1] = H[n] + ⌊(x[2n] + x[2n+2]) / 2⌋
        var odd = [Float](repeating: 0, count: nH)
        for i in 0..<nH {
            let eNext = (i + 1 < nL) ? even[i + 1] : even[nL - 1]
            odd[i] = h[i] + floor((even[i] + eNext) * 0.5)
        }

        // Interleave
        for i in 0..<nL { x[2 * i]     = even[i] }
        for i in 0..<nH { x[2 * i + 1] = odd[i]  }
    }

    // MARK: - 9/7 CDF Lifting

    // CDF 9/7 lifting constants
    private let alpha97: Float = -1.586134342
    private let beta97: Float = -0.052980118
    private let gamma97: Float = 0.882911075
    private let delta97: Float = 0.443506852
    private let k97: Float = 1.149604398   // scaling factor

    /// Forward CDF 9/7 lifting transform.
    ///
    /// Four lifting steps followed by subband scaling.
    private func forward97(_ x: inout [Float]) {
        let n = x.count
        let nL = (n + 1) / 2
        let nH = n / 2

        // Split into even (s) and odd (d) sequences
        var s = [Float](repeating: 0, count: nL)
        var d = [Float](repeating: 0, count: nH)
        for i in 0..<nL { s[i] = x[2 * i] }
        for i in 0..<nH { d[i] = x[2 * i + 1] }

        // Predict 1: d[n] += α * (s[n] + s[n+1])
        for i in 0..<nH {
            let sNext = (i + 1 < nL) ? s[i + 1] : s[nL - 1]
            d[i] += alpha97 * (s[i] + sNext)
        }
        // Update 1: s[n] += β * (d[n-1] + d[n])
        for i in 0..<nL {
            let dPrev = (i == 0) ? d[0] : d[i - 1]
            let dCurr = (i < nH) ? d[i] : d[nH - 1]
            s[i] += beta97 * (dPrev + dCurr)
        }
        // Predict 2: d[n] += γ * (s[n] + s[n+1])
        for i in 0..<nH {
            let sNext = (i + 1 < nL) ? s[i + 1] : s[nL - 1]
            d[i] += gamma97 * (s[i] + sNext)
        }
        // Update 2: s[n] += δ * (d[n-1] + d[n])
        for i in 0..<nL {
            let dPrev = (i == 0) ? d[0] : d[i - 1]
            let dCurr = (i < nH) ? d[i] : d[nH - 1]
            s[i] += delta97 * (dPrev + dCurr)
        }
        // Scaling
        let invK = 1.0 / k97
        for i in 0..<nL { s[i] *= invK }
        for i in 0..<nH { d[i] *= k97  }

        // Write back: lowpass first, then highpass
        for i in 0..<nL { x[i]      = s[i] }
        for i in 0..<nH { x[nL + i] = d[i] }
    }

    /// Inverse CDF 9/7 lifting transform.
    private func inverse97(_ x: inout [Float]) {
        let n = x.count
        let nL = (n + 1) / 2
        let nH = n / 2

        var s = Array(x[0..<nL])
        var d = Array(x[nL..<nL + nH])

        // Undo scaling
        let invK = 1.0 / k97
        for i in 0..<nL { s[i] *= k97  }
        for i in 0..<nH { d[i] *= invK }

        // Undo update 2: s[n] -= δ * (d[n-1] + d[n])
        for i in 0..<nL {
            let dPrev = (i == 0) ? d[0] : d[i - 1]
            let dCurr = (i < nH) ? d[i] : d[nH - 1]
            s[i] -= delta97 * (dPrev + dCurr)
        }
        // Undo predict 2: d[n] -= γ * (s[n] + s[n+1])
        for i in 0..<nH {
            let sNext = (i + 1 < nL) ? s[i + 1] : s[nL - 1]
            d[i] -= gamma97 * (s[i] + sNext)
        }
        // Undo update 1: s[n] -= β * (d[n-1] + d[n])
        for i in 0..<nL {
            let dPrev = (i == 0) ? d[0] : d[i - 1]
            let dCurr = (i < nH) ? d[i] : d[nH - 1]
            s[i] -= beta97 * (dPrev + dCurr)
        }
        // Undo predict 1: d[n] -= α * (s[n] + s[n+1])
        for i in 0..<nH {
            let sNext = (i + 1 < nL) ? s[i + 1] : s[nL - 1]
            d[i] -= alpha97 * (s[i] + sNext)
        }

        // Interleave
        for i in 0..<nL { x[2 * i]     = s[i] }
        for i in 0..<nH { x[2 * i + 1] = d[i] }
    }

    // MARK: - Boundary Extension Helpers

    /// Returns a signal extended with symmetric (mirror) boundary padding.
    ///
    /// For a signal `[a, b, c, d]` with `leftPad=2, rightPad=2`:
    /// `[c, b, a, b, c, d, c, b]`
    private func extendSymmetric(_ s: [Float], leftPad: Int, rightPad: Int) -> [Float] {
        let n = s.count
        var out = [Float](repeating: 0, count: n + leftPad + rightPad)
        // Whole-sample symmetric (WSS) extension: x[-k] = x[k], x[n-1+k] = x[n-1-k]
        for i in 0..<leftPad {
            let srcIdx = min(leftPad - i, n - 1)
            out[i] = s[srcIdx]
        }
        for i in 0..<n { out[leftPad + i] = s[i] }
        for i in 0..<rightPad {
            let srcIdx = max(0, n - 2 - i)
            out[leftPad + n + i] = s[srcIdx]
        }
        return out
    }

    /// Returns a boundary-extended signal using the configured mode.
    ///
    /// Used when the caller needs configurable boundary handling rather than
    /// the fixed symmetric extension used in the 5/3 predict step.
    private func extend(_ s: [Float], leftPad: Int, rightPad: Int) -> [Float] {
        switch configuration.boundary {
        case .symmetric:
            return extendSymmetric(s, leftPad: leftPad, rightPad: rightPad)
        case .periodic:
            return extendPeriodic(s, leftPad: leftPad, rightPad: rightPad)
        case .zeroPadding:
            return extendZero(s, leftPad: leftPad, rightPad: rightPad)
        }
    }

    private func extendPeriodic(_ s: [Float], leftPad: Int, rightPad: Int) -> [Float] {
        let n = s.count
        var out = [Float](repeating: 0, count: n + leftPad + rightPad)
        for i in 0..<leftPad {
            out[i] = s[((n - leftPad + i) % n + n) % n]
        }
        for i in 0..<n { out[leftPad + i] = s[i] }
        for i in 0..<rightPad { out[leftPad + n + i] = s[i % n] }
        return out
    }

    private func extendZero(_ s: [Float], leftPad: Int, rightPad: Int) -> [Float] {
        let n = s.count
        var out = [Float](repeating: 0, count: n + leftPad + rightPad)
        for i in 0..<n { out[leftPad + i] = s[i] }
        return out
    }

    // MARK: - Utility

    /// Returns the maximum useful number of DWT levels for a given dimension.
    private func maxLevels(for dimension: Int) -> Int {
        guard dimension > 1 else { return 0 }
        var lvl = 0
        var d = dimension
        while d > 1 { d = (d + 1) / 2; lvl += 1 }
        return lvl
    }
}

// MARK: - J2K3DCoefficients convenience init

extension J2K3DCoefficients {
    /// Convenience initialiser that also accepts pre-filled data.
    fileprivate init(width: Int, height: Int, depth: Int, decompositionLevels: Int, data: [Float]) {
        self.init(width: width, height: height, depth: depth,
                  decompositionLevels: decompositionLevels)
        self.data = data
    }
}
