//
// JP3DPhantomGenerator.swift
// J2KBenchApp — v10.18 JP3D arc / investor showcase
//
// Mathematically-defined 3D volumes that LOOK like real medical scans
// when sliced by the MPR viewer. No external data, no licensing, no
// bundled-data size limits — every phantom is generated from a tiny
// parameter set at view time.
//
// The phantoms target the modalities a radiology audience expects to
// recognise at a glance:
//
//   .sheppLogan3D — the textbook 3D Shepp-Logan head phantom (10
//                   ellipsoids approximating skull / brain / ventricles
//                   / lesions). The canonical CT reconstruction test
//                   object since 1974; every medical-imaging engineer
//                   knows it on sight.
//   .brainMRI     — T1-weighted brain MR analogue: ellipsoidal cranium
//                   with concentric scalp / skull / white matter /
//                   gray matter / CSF shells + lateral ventricles.
//   .thoraxCT     — Chest CT analogue: body cylinder + two lung
//                   ellipsoids (low density) + heart + descending aorta
//                   + rib arc ring + spine.
//   .abdomenCT    — Abdomen CT analogue: body + liver (right side) +
//                   spleen (left) + kidney pair (paravertebral) + spine
//                   + bowel-like low-density region.
//   .spineMR      — Sagittal spine MR analogue: stack of vertebral
//                   bodies with intervertebral disc gaps + spinal
//                   canal + soft-tissue background.
//   .kneeCT       — Knee CT analogue: femur (proximal) + tibia (distal)
//                   + patella + fibula + joint space + soft tissue.
//
// Voxel intensity ranges are scaled to fit the fixture bit-depth's
// max value with Hounsfield-like or signal-intensity-like relative
// spacing (bone bright, air dark, soft tissue mid). The MPR viewer's
// auto window-stretch then maps these to 8-bit display, producing
// visibly-clinical-looking slices.

import Foundation
import J2KCore

/// Identifies which generator builds a given fixture's voxels.
enum JP3DPhantomKind: String, Sendable, Codable, CaseIterable, Hashable {
    case lcg              // legacy LCG noise (kept for the bench corpus)
    case sheppLogan3D
    case brainMRI
    case thoraxCT
    case abdomenCT
    case spineMR
    case kneeCT
}

enum JP3DPhantomGenerator {

    /// Build a J2KVolume of the requested `kind`. Output is single-
    /// component, unsigned, little-endian-packed per the JP3D codec
    /// convention. Spacing fields are set to anatomically-plausible
    /// mm values per modality so the MPR viewer's aspect-ratio
    /// handling produces correct-looking axial / sagittal / coronal
    /// views.
    static func generate(
        kind: JP3DPhantomKind,
        width: Int, height: Int, depth: Int,
        bitDepth: Int,
        seed: UInt64
    ) -> J2KVolume {
        switch kind {
        case .lcg:
            return generateLCG(w: width, h: height, d: depth,
                               bitDepth: bitDepth, seed: seed)
        case .sheppLogan3D:
            return wrap(generateSheppLogan3D(w: width, h: height, d: depth,
                                              bitDepth: bitDepth),
                        w: width, h: height, d: depth, bitDepth: bitDepth,
                        // Brain-CT typical: 1mm isotropic
                        sx: 1.0, sy: 1.0, sz: 1.0)
        case .brainMRI:
            return wrap(generateBrainMRI(w: width, h: height, d: depth,
                                         bitDepth: bitDepth),
                        w: width, h: height, d: depth, bitDepth: bitDepth,
                        // T1 brain typical: 1mm isotropic
                        sx: 1.0, sy: 1.0, sz: 1.0)
        case .thoraxCT:
            return wrap(generateThoraxCT(w: width, h: height, d: depth,
                                         bitDepth: bitDepth, seed: seed),
                        w: width, h: height, d: depth, bitDepth: bitDepth,
                        // Chest CT typical: 0.7mm in-plane, 2.5mm slice
                        sx: 0.7, sy: 0.7, sz: 2.5)
        case .abdomenCT:
            return wrap(generateAbdomenCT(w: width, h: height, d: depth,
                                          bitDepth: bitDepth, seed: seed),
                        w: width, h: height, d: depth, bitDepth: bitDepth,
                        // Abdomen CT: 0.8mm in-plane, 3mm slice
                        sx: 0.8, sy: 0.8, sz: 3.0)
        case .spineMR:
            return wrap(generateSpineMR(w: width, h: height, d: depth,
                                         bitDepth: bitDepth, seed: seed),
                        w: width, h: height, d: depth, bitDepth: bitDepth,
                        // Sag spine MR: 0.6mm L-R, 0.6mm S-I, 4mm slice
                        sx: 0.6, sy: 0.6, sz: 4.0)
        case .kneeCT:
            return wrap(generateKneeCT(w: width, h: height, d: depth,
                                       bitDepth: bitDepth, seed: seed),
                        w: width, h: height, d: depth, bitDepth: bitDepth,
                        // Knee CT: 0.5mm in-plane, 0.625mm slice
                        sx: 0.5, sy: 0.5, sz: 0.625)
        }
    }

    // MARK: - Wrap helper

    /// Pack a `[Double]` voxel buffer (one value per voxel, in plane-
    /// major (z*H + y)*W + x order) into a little-endian J2KVolume.
    /// Normalises non-finite values to 0 and clamps to [0, maxVal].
    private static func wrap(
        _ voxels: [Double],
        w: Int, h: Int, d: Int, bitDepth: Int,
        sx: Double, sy: Double, sz: Double
    ) -> J2KVolume {
        let voxelCount = w * h * d
        let bytesPerSample = (bitDepth + 7) / 8
        let maxVal = (1 << bitDepth) - 1
        var data = Data(count: voxelCount * bytesPerSample)

        data.withUnsafeMutableBytes { raw in
            if bytesPerSample == 1 {
                let p = raw.bindMemory(to: UInt8.self)
                for i in 0..<voxelCount {
                    let v = voxels[i].isFinite ? voxels[i] : 0
                    let clamped = max(0, min(Double(maxVal), v))
                    p[i] = UInt8(clamped)
                }
            } else {
                let p = raw.bindMemory(to: UInt16.self)
                for i in 0..<voxelCount {
                    let v = voxels[i].isFinite ? voxels[i] : 0
                    let clamped = max(0, min(Double(maxVal), v))
                    p[i] = UInt16(clamped)
                }
            }
        }

        let comp = J2KVolumeComponent(
            index: 0, bitDepth: bitDepth, signed: false,
            width: w, height: h, depth: d,
            subsamplingX: 1, subsamplingY: 1, subsamplingZ: 1,
            data: data)
        return J2KVolume(
            width: w, height: h, depth: d,
            components: [comp],
            spacingX: sx, spacingY: sy, spacingZ: sz)
    }

    // MARK: - LCG (legacy)

    /// The original LCG-noise generator. Kept for back-compat so the
    /// bench corpus's `.lcg`-kind fixtures continue to behave as before.
    private static func generateLCG(
        w: Int, h: Int, d: Int, bitDepth: Int, seed: UInt64
    ) -> J2KVolume {
        let voxelCount = w * h * d
        let bytesPerSample = (bitDepth + 7) / 8
        let maxVal = (1 << bitDepth) - 1
        var data = Data(count: voxelCount * bytesPerSample)
        var s: UInt64 = seed &* 6364136223846793005 &+ 1442695040888963407
        data.withUnsafeMutableBytes { raw in
            if bytesPerSample == 1 {
                let p = raw.bindMemory(to: UInt8.self)
                for i in 0..<voxelCount {
                    s = s &* 6364136223846793005 &+ 1442695040888963407
                    p[i] = UInt8(truncatingIfNeeded: Int((s >> 16) & 0xFFFFFFFF) % (maxVal + 1))
                }
            } else {
                let p = raw.bindMemory(to: UInt16.self)
                for i in 0..<voxelCount {
                    s = s &* 6364136223846793005 &+ 1442695040888963407
                    p[i] = UInt16(truncatingIfNeeded: Int((s >> 16) & 0xFFFFFFFF) % (maxVal + 1))
                }
            }
        }
        let comp = J2KVolumeComponent(
            index: 0, bitDepth: bitDepth, signed: false,
            width: w, height: h, depth: d,
            data: data)
        return J2KVolume(
            width: w, height: h, depth: d,
            components: [comp],
            spacingX: 1.0, spacingY: 1.0, spacingZ: 1.0)
    }

    // MARK: - Shape primitives

    /// Inside-ellipsoid test in axis-aligned coords.
    @inline(__always)
    private static func ellipsoid(
        _ x: Double, _ y: Double, _ z: Double,
        cx: Double, cy: Double, cz: Double,
        ax: Double, ay: Double, az: Double
    ) -> Bool {
        let dx = (x - cx) / ax
        let dy = (y - cy) / ay
        let dz = (z - cz) / az
        return dx * dx + dy * dy + dz * dz <= 1
    }

    /// Inside-cylinder test (axis along Z).
    @inline(__always)
    private static func cylinderZ(
        _ x: Double, _ y: Double, _ z: Double,
        cx: Double, cy: Double, zRange: ClosedRange<Double>,
        rx: Double, ry: Double
    ) -> Bool {
        guard zRange.contains(z) else { return false }
        let dx = (x - cx) / rx
        let dy = (y - cy) / ry
        return dx * dx + dy * dy <= 1
    }

    /// Inside-box test.
    @inline(__always)
    private static func box(
        _ x: Double, _ y: Double, _ z: Double,
        xRange: ClosedRange<Double>, yRange: ClosedRange<Double>,
        zRange: ClosedRange<Double>
    ) -> Bool {
        xRange.contains(x) && yRange.contains(y) && zRange.contains(z)
    }

    /// Smooth radial falloff in [0, 1] for soft tissue gradients.
    @inline(__always)
    private static func falloff(_ d: Double) -> Double {
        guard d > 0 && d < 1 else { return d <= 0 ? 1 : 0 }
        let t = 1 - d
        return t * t * (3 - 2 * t)  // smoothstep
    }

    // MARK: - Shepp-Logan 3D

    /// Canonical 10-ellipsoid 3D Shepp-Logan head phantom (per
    /// Kak & Slaney, 1988). Each ellipsoid contributes its `value`
    /// to every voxel inside it; final voxel intensity is the sum,
    /// scaled to fit the fixture's bit depth.
    private static func generateSheppLogan3D(
        w: Int, h: Int, d: Int, bitDepth: Int
    ) -> [Double] {
        struct Ellipsoid {
            let value: Double
            let cx: Double; let cy: Double; let cz: Double
            let a: Double;  let b: Double;  let c: Double
            let phi: Double  // rotation in xy plane (degrees)
        }
        // Canonical Shepp-Logan parameters (centered + scaled to
        // fit normalized [-1, 1] cube).
        let phantoms: [Ellipsoid] = [
            Ellipsoid(value:  2.00, cx:  0.00, cy:  0.00, cz:  0.00,
                      a: 0.69,   b: 0.92,   c: 0.90,   phi:   0),  // skull
            Ellipsoid(value: -0.98, cx:  0.00, cy:  0.00, cz:  0.00,
                      a: 0.6624, b: 0.874,  c: 0.88,   phi:   0),  // brain
            Ellipsoid(value: -0.02, cx: -0.22, cy:  0.00, cz: -0.25,
                      a: 0.41,   b: 0.16,   c: 0.21,   phi:  72),  // left ventricle
            Ellipsoid(value: -0.02, cx:  0.22, cy:  0.00, cz: -0.25,
                      a: 0.31,   b: 0.11,   c: 0.22,   phi: -72),  // right ventricle
            Ellipsoid(value:  0.02, cx:  0.00, cy:  0.35, cz: -0.25,
                      a: 0.21,   b: 0.25,   c: 0.50,   phi:   0),  // upper midline
            Ellipsoid(value:  0.02, cx:  0.00, cy:  0.10, cz: -0.25,
                      a: 0.046,  b: 0.046,  c: 0.046,  phi:   0),  // central dot
            Ellipsoid(value:  0.01, cx: -0.08, cy: -0.65, cz: -0.25,
                      a: 0.046,  b: 0.023,  c: 0.02,   phi:   0),
            Ellipsoid(value:  0.01, cx:  0.00, cy: -0.65, cz: -0.25,
                      a: 0.023,  b: 0.023,  c: 0.023,  phi:   0),
            Ellipsoid(value:  0.02, cx:  0.06, cy: -0.65, cz: -0.25,
                      a: 0.046,  b: 0.023,  c: 0.02,   phi:  90),
            Ellipsoid(value:  0.01, cx:  0.00, cy:  0.10, cz: -0.625,
                      a: 0.056,  b: 0.04,   c: 0.10,   phi:   0),
        ]

        let maxVal = Double((1 << bitDepth) - 1)
        // Map intensity range [0, 2.05] → [0, maxVal] so the
        // skull-rim is near the top of the dynamic range.
        let scale = maxVal / 2.05

        var voxels = [Double](repeating: 0, count: w * h * d)
        for k in 0..<d {
            let z = (Double(k) + 0.5) / Double(d) * 2.0 - 1.0
            for j in 0..<h {
                let y = (Double(j) + 0.5) / Double(h) * 2.0 - 1.0
                for i in 0..<w {
                    let x = (Double(i) + 0.5) / Double(w) * 2.0 - 1.0
                    var sum = 0.0
                    for p in phantoms {
                        // Rotate (x, y) by -phi around (cx, cy).
                        let cosA = cos(-p.phi * .pi / 180.0)
                        let sinA = sin(-p.phi * .pi / 180.0)
                        let dx = x - p.cx
                        let dy = y - p.cy
                        let rx = dx * cosA - dy * sinA
                        let ry = dx * sinA + dy * cosA
                        let nx = rx / p.a
                        let ny = ry / p.b
                        let nz = (z - p.cz) / p.c
                        if nx * nx + ny * ny + nz * nz <= 1 {
                            sum += p.value
                        }
                    }
                    voxels[(k * h + j) * w + i] = max(0, sum) * scale
                }
            }
        }
        return voxels
    }

    // MARK: - Brain MRI

    /// T1-weighted brain MR analogue: concentric ellipsoidal shells
    /// for scalp / skull / brain / ventricles, with a smooth gradient
    /// inside the brain matter so the MPR viewer renders gray/white
    /// matter contrast.
    private static func generateBrainMRI(
        w: Int, h: Int, d: Int, bitDepth: Int
    ) -> [Double] {
        let maxVal = Double((1 << bitDepth) - 1)
        var voxels = [Double](repeating: 0, count: w * h * d)
        for k in 0..<d {
            let z = (Double(k) + 0.5) / Double(d) * 2.0 - 1.0
            for j in 0..<h {
                let y = (Double(j) + 0.5) / Double(h) * 2.0 - 1.0
                for i in 0..<w {
                    let x = (Double(i) + 0.5) / Double(w) * 2.0 - 1.0
                    // Skull egg-shape: prolate, slightly off-axis in Z.
                    let skullR = sqrt((x / 0.78) * (x / 0.78)
                                    + (y / 0.95) * (y / 0.95)
                                    + ((z - 0.05) / 0.85) * ((z - 0.05) / 0.85))
                    let brainR = sqrt((x / 0.72) * (x / 0.72)
                                    + (y / 0.88) * (y / 0.88)
                                    + ((z - 0.05) / 0.78) * ((z - 0.05) / 0.78))
                    let csfR = sqrt((x / 0.70) * (x / 0.70)
                                  + (y / 0.85) * (y / 0.85)
                                  + ((z - 0.05) / 0.75) * ((z - 0.05) / 0.75))

                    var intensity = 0.0
                    if skullR < 1 {
                        // Outermost (skin/fat): T1-bright
                        intensity = 0.65 * maxVal
                    }
                    if brainR < 1 {
                        // Skull (dark on T1 — cortical bone)
                        intensity = 0.05 * maxVal
                    }
                    if csfR < 1 {
                        // White matter / gray matter mix — gradient.
                        let r = sqrt(x * x + y * y + z * z)
                        let wm = 1.0 - smoothstep(0.0, 0.65, r)  // bright center
                        let gm = smoothstep(0.45, 0.95, r)       // mid rim
                        intensity = (0.85 - 0.25 * gm + 0.10 * wm) * maxVal
                    }
                    // Lateral ventricles (CSF, dark on T1) — two ellipsoids.
                    if ellipsoid(x, y, z, cx: -0.18, cy: -0.05, cz:  0.10,
                                 ax: 0.10, ay: 0.30, az: 0.18) ||
                       ellipsoid(x, y, z, cx:  0.18, cy: -0.05, cz:  0.10,
                                 ax: 0.10, ay: 0.30, az: 0.18) {
                        intensity = 0.20 * maxVal
                    }
                    // Third ventricle — central thin midline slit
                    if ellipsoid(x, y, z, cx: 0, cy: 0, cz: 0,
                                 ax: 0.03, ay: 0.12, az: 0.10) {
                        intensity = 0.18 * maxVal
                    }
                    voxels[(k * h + j) * w + i] = intensity
                }
            }
        }
        return voxels
    }

    @inline(__always)
    private static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    // MARK: - Thorax CT

    /// Chest CT analogue: body cylinder + two low-density lungs +
    /// heart + descending aorta + spine + rib arc. Hounsfield-ish
    /// intensity mapping (air dark, soft tissue mid, bone bright).
    private static func generateThoraxCT(
        w: Int, h: Int, d: Int, bitDepth: Int, seed: UInt64
    ) -> [Double] {
        let maxVal = Double((1 << bitDepth) - 1)
        // HU → display: air -1000 → 0.05*max; soft tissue 0 → 0.40*max;
        // bone 1000 → 0.90*max. Linear map: display = 0.4 + 0.05*HU/100
        // for the displayable range we care about.
        func intensity(forHU hu: Double) -> Double {
            // Map HU [-1000, 1500] → fraction [0, 1] then to [0, maxVal].
            let frac = max(0, min(1, (hu + 1000) / 2500))
            return frac * maxVal
        }
        // Small structured noise so soft tissue isn't perfectly flat.
        var rng = seed
        @inline(__always) func noise(_ amplitude: Double) -> Double {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            let u = Double((rng >> 32) & 0xFFFFFFFF) / Double(UInt32.max)
            return (u - 0.5) * amplitude
        }

        var voxels = [Double](repeating: 0, count: w * h * d)
        for k in 0..<d {
            let z = (Double(k) + 0.5) / Double(d) * 2.0 - 1.0
            for j in 0..<h {
                let y = (Double(j) + 0.5) / Double(h) * 2.0 - 1.0
                for i in 0..<w {
                    let x = (Double(i) + 0.5) / Double(w) * 2.0 - 1.0

                    var hu = -1000.0  // start with air (outside)

                    // Body ellipse (axial: wider than tall)
                    if ellipsoid(x, y, z, cx: 0, cy: 0, cz: 0,
                                 ax: 0.82, ay: 0.68, az: 0.98) {
                        hu = 40 + noise(20)  // soft tissue background
                    }
                    // Right lung (subject right = image left)
                    if ellipsoid(x, y, z, cx: -0.38, cy: 0.05, cz: 0.05,
                                 ax: 0.30, ay: 0.40, az: 0.65) {
                        hu = -750 + noise(60)  // lung parenchyma
                    }
                    // Left lung (slightly smaller due to heart)
                    if ellipsoid(x, y, z, cx: 0.40, cy: 0.05, cz: 0.05,
                                 ax: 0.27, ay: 0.38, az: 0.65) {
                        hu = -750 + noise(60)
                    }
                    // Heart (mostly on the left side, mid-anterior)
                    if ellipsoid(x, y, z, cx: 0.10, cy: -0.18, cz: 0.20,
                                 ax: 0.22, ay: 0.20, az: 0.32) {
                        hu = 60 + noise(15)  // myocardium
                    }
                    // Descending aorta (posterior, slightly left)
                    if cylinderZ(x, y, z, cx: 0.10, cy: 0.32,
                                 zRange: -0.6...0.6,
                                 rx: 0.06, ry: 0.06) {
                        hu = 80  // contrast or just blood
                    }
                    // Spine (vertebral body, posterior midline)
                    if cylinderZ(x, y, z, cx: 0, cy: 0.48,
                                 zRange: -0.95...0.95,
                                 rx: 0.12, ry: 0.10) {
                        hu = 350  // cancellous bone
                    }
                    // Spinal cortex (rim of vertebra)
                    let spinalDist = sqrt((x - 0) * (x - 0) / 0.12 / 0.12
                                       + (y - 0.48) * (y - 0.48) / 0.10 / 0.10)
                    if spinalDist > 0.85 && spinalDist <= 1.0 {
                        if abs(z) < 0.95 { hu = 900 }  // cortical bone
                    }
                    // Rib arcs (annulus on the outside of body ellipse)
                    let bodyDist = sqrt((x / 0.78) * (x / 0.78)
                                     + (y / 0.65) * (y / 0.65))
                    if bodyDist > 0.92 && bodyDist <= 1.0 {
                        // Discrete ribs along Z (spaced)
                        let zMod = (z + 1.0) * 6.0  // 12 ribs over height
                        let ribPhase = zMod - floor(zMod)
                        if ribPhase < 0.45 {
                            hu = 1100  // cortical bone
                        }
                    }
                    voxels[(k * h + j) * w + i] = intensity(forHU: hu)
                }
            }
        }
        return voxels
    }

    // MARK: - Abdomen CT

    /// Abdomen CT analogue: body cylinder + liver (right lobe + left
    /// lobe), spleen, kidneys (paravertebral), spine, and a low-
    /// density bowel/fat background.
    private static func generateAbdomenCT(
        w: Int, h: Int, d: Int, bitDepth: Int, seed: UInt64
    ) -> [Double] {
        let maxVal = Double((1 << bitDepth) - 1)
        func intensity(forHU hu: Double) -> Double {
            let frac = max(0, min(1, (hu + 1000) / 2500))
            return frac * maxVal
        }
        var rng = seed
        @inline(__always) func noise(_ amp: Double) -> Double {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            let u = Double((rng >> 32) & 0xFFFFFFFF) / Double(UInt32.max)
            return (u - 0.5) * amp
        }

        var voxels = [Double](repeating: 0, count: w * h * d)
        for k in 0..<d {
            let z = (Double(k) + 0.5) / Double(d) * 2.0 - 1.0
            for j in 0..<h {
                let y = (Double(j) + 0.5) / Double(h) * 2.0 - 1.0
                for i in 0..<w {
                    let x = (Double(i) + 0.5) / Double(w) * 2.0 - 1.0
                    var hu = -1000.0

                    // Body ellipse (wider torso)
                    if ellipsoid(x, y, z, cx: 0, cy: 0, cz: 0,
                                 ax: 0.92, ay: 0.70, az: 0.97) {
                        hu = -100 + noise(30)  // subcutaneous fat background
                    }
                    // Bowel region (centre, slightly low density)
                    if ellipsoid(x, y, z, cx: -0.05, cy: -0.10, cz: 0.10,
                                 ax: 0.55, ay: 0.42, az: 0.55) {
                        hu = 40 + noise(40)  // mixed soft tissue + gas pockets
                    }
                    // Liver (right side, upper) — large blob
                    if ellipsoid(x, y, z, cx: -0.42, cy: -0.10, cz: 0.45,
                                 ax: 0.38, ay: 0.30, az: 0.35) {
                        hu = 90 + noise(10)  // healthy liver parenchyma
                    }
                    // Spleen (left side)
                    if ellipsoid(x, y, z, cx: 0.52, cy: -0.05, cz: 0.40,
                                 ax: 0.16, ay: 0.18, az: 0.22) {
                        hu = 75 + noise(8)
                    }
                    // Right kidney (paravertebral, slightly lower)
                    if ellipsoid(x, y, z, cx: -0.28, cy: 0.20, cz: 0.05,
                                 ax: 0.10, ay: 0.14, az: 0.22) {
                        hu = 35 + noise(15)  // renal cortex
                    }
                    if ellipsoid(x, y, z, cx: -0.28, cy: 0.20, cz: 0.05,
                                 ax: 0.05, ay: 0.07, az: 0.14) {
                        hu = 25  // renal pelvis (slightly darker)
                    }
                    // Left kidney
                    if ellipsoid(x, y, z, cx: 0.28, cy: 0.20, cz: 0.10,
                                 ax: 0.10, ay: 0.14, az: 0.22) {
                        hu = 35 + noise(15)
                    }
                    if ellipsoid(x, y, z, cx: 0.28, cy: 0.20, cz: 0.10,
                                 ax: 0.05, ay: 0.07, az: 0.14) {
                        hu = 25
                    }
                    // Spine (vertebral column)
                    if cylinderZ(x, y, z, cx: 0, cy: 0.46,
                                 zRange: -0.95...0.95,
                                 rx: 0.13, ry: 0.11) {
                        hu = 380
                    }
                    let spinalDist = sqrt((x - 0) * (x - 0) / 0.13 / 0.13
                                       + (y - 0.46) * (y - 0.46) / 0.11 / 0.11)
                    if spinalDist > 0.88 && spinalDist <= 1.0 && abs(z) < 0.95 {
                        hu = 950
                    }
                    voxels[(k * h + j) * w + i] = intensity(forHU: hu)
                }
            }
        }
        return voxels
    }

    // MARK: - Spine MR (sagittal)

    /// Sagittal spine MR analogue. Volume is oriented so:
    /// - X = left-right (small, since sagittal slabs are thin in L-R)
    /// - Y = anterior-posterior
    /// - Z = superior-inferior (head→feet)
    ///
    /// The volume contains 8 vertebral bodies stacked along Z, with
    /// intervertebral disc gaps between them and a spinal canal
    /// running posteriorly through Z.
    private static func generateSpineMR(
        w: Int, h: Int, d: Int, bitDepth: Int, seed: UInt64
    ) -> [Double] {
        let maxVal = Double((1 << bitDepth) - 1)
        var rng = seed
        @inline(__always) func noise(_ amp: Double) -> Double {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            let u = Double((rng >> 32) & 0xFFFFFFFF) / Double(UInt32.max)
            return (u - 0.5) * amp
        }

        var voxels = [Double](repeating: 0, count: w * h * d)
        let vertebraCount = 8
        for k in 0..<d {
            let z = (Double(k) + 0.5) / Double(d) * 2.0 - 1.0
            for j in 0..<h {
                let y = (Double(j) + 0.5) / Double(h) * 2.0 - 1.0
                for i in 0..<w {
                    let x = (Double(i) + 0.5) / Double(w) * 2.0 - 1.0
                    var intensity = 0.0

                    // Soft tissue background (anywhere inside the body
                    // ellipse — narrow L-R because we're a sagittal slab).
                    if ellipsoid(x, y, z, cx: 0, cy: 0, cz: 0,
                                 ax: 0.85, ay: 0.90, az: 0.95) {
                        intensity = 0.35 * maxVal + noise(0.03 * maxVal)
                    }
                    // Vertebral bodies + intervertebral discs along Z.
                    let zRel = (z + 1.0) * Double(vertebraCount) / 2.0
                    let segIdx = Int(floor(zRel))
                    let segFrac = zRel - Double(segIdx)
                    // 80% vertebra, 20% disc
                    let isDisc = segFrac > 0.80
                    // Vertebral body footprint: anterior-bias ellipse.
                    if ellipsoid(x, y, z, cx: 0, cy: -0.05, cz: z,
                                 ax: 0.85, ay: 0.32, az: 0.10) {
                        if isDisc {
                            // Intervertebral disc — bright on T2 MR
                            intensity = 0.85 * maxVal
                        } else {
                            // Vertebral body marrow — moderate intensity
                            intensity = 0.55 * maxVal + noise(0.02 * maxVal)
                        }
                    }
                    // Cortical rim of vertebrae (dark on MR)
                    let vbDist = sqrt((x / 0.85) * (x / 0.85)
                                    + ((y + 0.05) / 0.32) * ((y + 0.05) / 0.32))
                    if vbDist > 0.90 && vbDist <= 1.0 && !isDisc {
                        if abs(y + 0.05) > 0.05 {  // skip the central disc area
                            intensity = 0.10 * maxVal
                        }
                    }
                    // Spinal canal — posterior, dark fluid on T1 / bright on T2
                    if ellipsoid(x, y, z, cx: 0, cy: 0.30, cz: z,
                                 ax: 0.50, ay: 0.08, az: 1.1) {
                        intensity = 0.80 * maxVal  // CSF — bright on T2
                    }
                    voxels[(k * h + j) * w + i] = intensity
                }
            }
        }
        return voxels
    }

    // MARK: - Knee CT

    /// Knee CT analogue (axial). Femur (proximal) + tibia (distal) +
    /// patella (anterior) + fibula (lateral) + soft tissue.
    /// Volume Z spans the joint level.
    private static func generateKneeCT(
        w: Int, h: Int, d: Int, bitDepth: Int, seed: UInt64
    ) -> [Double] {
        let maxVal = Double((1 << bitDepth) - 1)
        func intensity(forHU hu: Double) -> Double {
            let frac = max(0, min(1, (hu + 1000) / 2500))
            return frac * maxVal
        }
        var rng = seed
        @inline(__always) func noise(_ amp: Double) -> Double {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            let u = Double((rng >> 32) & 0xFFFFFFFF) / Double(UInt32.max)
            return (u - 0.5) * amp
        }

        var voxels = [Double](repeating: 0, count: w * h * d)
        for k in 0..<d {
            let z = (Double(k) + 0.5) / Double(d) * 2.0 - 1.0
            for j in 0..<h {
                let y = (Double(j) + 0.5) / Double(h) * 2.0 - 1.0
                for i in 0..<w {
                    let x = (Double(i) + 0.5) / Double(w) * 2.0 - 1.0
                    var hu = -1000.0

                    // Soft tissue (skin/muscle/fat). Roughly cylindrical
                    // leg shape with slight anterior bulge (quadriceps).
                    let bodyDist = sqrt((x / 0.85) * (x / 0.85)
                                     + ((y + 0.05) / 0.78) * ((y + 0.05) / 0.78))
                    if bodyDist <= 1 {
                        hu = -50 + noise(40)  // fat-rich soft tissue
                    }
                    // Muscle layer (just inside skin)
                    if bodyDist <= 0.85 {
                        hu = 50 + noise(20)
                    }

                    // Femur (proximal, upper half of Z, posterior)
                    if z > -0.05 {
                        // Cortical rim
                        let femurDist = sqrt((x / 0.30) * (x / 0.30)
                                          + ((y - 0.05) / 0.32) * ((y - 0.05) / 0.32))
                        if femurDist <= 1.0 {
                            hu = 350 + noise(20)  // marrow
                            if femurDist > 0.84 {
                                hu = 1100  // cortical bone
                            }
                        }
                    }
                    // Tibia (distal, lower half of Z, posterior medial)
                    if z < 0.05 {
                        let tibiaDist = sqrt(((x + 0.05) / 0.32) * ((x + 0.05) / 0.32)
                                          + ((y - 0.05) / 0.32) * ((y - 0.05) / 0.32))
                        if tibiaDist <= 1.0 {
                            hu = 320 + noise(20)
                            if tibiaDist > 0.84 {
                                hu = 1080
                            }
                        }
                    }
                    // Fibula (small bone, lateral, lower half)
                    if z < 0.05 {
                        let fibDist = sqrt(((x - 0.40) / 0.10) * ((x - 0.40) / 0.10)
                                        + ((y - 0.05) / 0.10) * ((y - 0.05) / 0.10))
                        if fibDist <= 1.0 {
                            hu = 250 + noise(15)
                            if fibDist > 0.80 {
                                hu = 1050
                            }
                        }
                    }
                    // Patella (anterior, mid Z, kneecap)
                    if ellipsoid(x, y, z, cx: 0, cy: -0.55, cz: 0,
                                 ax: 0.18, ay: 0.10, az: 0.18) {
                        hu = 600 + noise(30)
                        // Cortical surface
                        let patDist = sqrt((x / 0.18) * (x / 0.18)
                                        + ((y + 0.55) / 0.10) * ((y + 0.55) / 0.10)
                                        + (z / 0.18) * (z / 0.18))
                        if patDist > 0.85 {
                            hu = 1000
                        }
                    }
                    // Joint space (cartilage / synovial fluid between femur/tibia)
                    if abs(z) < 0.05 {
                        if ellipsoid(x, y, z, cx: 0, cy: 0.05, cz: 0,
                                     ax: 0.30, ay: 0.30, az: 0.05) {
                            hu = -80  // joint space (cartilage-ish low density)
                        }
                    }
                    voxels[(k * h + j) * w + i] = intensity(forHU: hu)
                }
            }
        }
        return voxels
    }
}
