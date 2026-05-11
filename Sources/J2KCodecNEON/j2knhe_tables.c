// j2knhe_tables.c — JPEG 2000 Part-15 lookup tables (placeholder).
//
// v9.4-research: these arrays are currently zero-initialised
// placeholders. Day 2 fills them by transcription from the Swift
// source-of-truth in Sources/J2KCodec/J2KHTConformantTables.swift.
// Until then the encoder stub does not consume table values, so the
// stub passes through without functional impact.
//
// The tables are mathematical constants from ITU-T T.814; we do not
// copy any third-party encoder source. The transcription pipeline:
//   1. Swift V94NEONHotPathParityTests.testDumpTablesToC() prints the
//      Swift lazily-initialized arrays as C array-initialiser source.
//   2. The output is hand-saved into this file.
//   3. A bit-identity test (testTablesMatchSwiftSourceOfTruth) runs at
//      every CI build and asserts the C and Swift arrays are equal
//      element-for-element.

#include "j2knhe_tables.h"

const uint16_t j2knhe_vlc_table0[2048] = { 0 };
const uint16_t j2knhe_vlc_table1[2048] = { 0 };
const uint32_t j2knhe_uvlc_table[33]    = { 0 };
