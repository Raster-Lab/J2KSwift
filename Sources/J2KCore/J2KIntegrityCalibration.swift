//
// J2KIntegrityCalibration.swift
// J2KSwift
//
// Measured thresholds for `J2KIntegrityThresholds`.
//
// Corpus: 310 codestreams from four independent encoders (Kakadu, OpenJPEG,
// OpenJPH, Grok) over ten source images, spanning lossless and lossy,
// single- and multi-layer, tiled and untiled, two code-block sizes, and the
// BYPASS / RESTART / SEGMARK / PREDICTABLE / SOP-EPH coding modes.
//
// Each stream was decoded and its samples compared against the source the
// encoder was given, so "clean" here means *verified correctly decoded*, not
// merely "not corrupted" — a distinction that matters, because the
// calibration run found J2KSwift mis-decoding a large share of conformant
// third-party streams, and those must not be mistaken for a benign baseline.
//
// Measured over 116 verified-correct reversible streams:
//
//     maximum single-block under-read  0 bytes
//     maximum single-block over-read   8 bytes   (0, 2, 3 and 8 observed)
//
// The thresholds sit above both, so an encoder whose flush strategy leaves a
// small legitimate tail is not rejected. ISO/IEC 15444-1 Annex C defines the
// past-the-end `0xFF` feed, so over-read in particular is normal operation;
// T.800 also permits dropping trailing `0xFF` bytes, which is the mechanism
// by which an unsampled encoder could plausibly produce a short under-read.
//
// A threshold sweep showed 4 / 16 to be the widest margin that costs no
// detection: under-read thresholds of 0, 1, 2 and 4 all detect 73 of 78
// mis-decodes with zero false positives, and only at 8 does detection fall
// to 71. Over-read thresholds of 8 and 16 both detect 73; 32 falls to 72.
//
// Reproduce with `Scripts/calibrate-integrity.sh`.
//

/// See ``J2KIntegrityThresholds/benignBlockUnderRead``.
///
/// Observed maximum on verified-correct streams: 0 bytes.
let calibratedBenignBlockUnderRead: Int = 4

/// See ``J2KIntegrityThresholds/benignBlockOverRead``.
///
/// Observed maximum on verified-correct streams: 8 bytes.
let calibratedBenignBlockOverRead: Int = 16
