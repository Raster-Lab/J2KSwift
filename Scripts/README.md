# J2KSwift Scripts

This directory contains utility scripts for development, testing, and benchmarking J2KSwift.

## Available Scripts

### benchmark_openjpeg.sh

Automated performance comparison between J2KSwift and OpenJPEG.

**Purpose**: Provides basic infrastructure for benchmarking J2KSwift against the OpenJPEG reference implementation.

**Usage**:
```bash
./Scripts/benchmark_openjpeg.sh [options]
```

**Options**:
- `-h, --help`: Show help message
- `-o, --output DIR`: Output directory for results (default: `./benchmark_results`)
- `-s, --sizes SIZES`: Comma-separated list of image sizes to test (default: `512,1024`)
- `-r, --runs N`: Number of benchmark runs per test (default: 3)
- `--no-openjpeg`: Skip OpenJPEG benchmarks (test J2KSwift only)

**Requirements**:
- Swift 6.2+
- OpenJPEG (`opj_compress`, `opj_decompress`) - optional with `--no-openjpeg`
- Python 3 (for test image generation)

**Example**:
```bash
# Run quick benchmark with small images
./Scripts/benchmark_openjpeg.sh -s 256,512 -r 3
```

### compare_performance.py

**NEW**: Comprehensive Python-based performance comparison tool with detailed reports.

**Purpose**: Provides advanced benchmarking with encode/decode comparison, multiple formats, and detailed analysis reports.

**Usage**:
```bash
python3 Scripts/compare_performance.py [options]
```

**Options**:
- `-s, --sizes SIZES`: Comma-separated image sizes (default: `256,512,1024`)
- `-r, --runs N`: Number of benchmark runs (default: 5)
- `-o, --output DIR`: Output directory (default: `./benchmark_results`)
- `--j2k-cli PATH`: Path to j2k CLI tool (auto-detected if not provided)

**Example**:
```bash
# Run comprehensive benchmark
python3 Scripts/compare_performance.py -s 256,512,1024,2048 -r 10 -o ./results

# Quick test
python3 Scripts/compare_performance.py -s 256,512 -r 3
```

**Output**:
- Test images in `<output_dir>/test_images/`
- J2KSwift JSON results in `<output_dir>/j2kswift/`
- OpenJPEG output files in `<output_dir>/openjpeg/`
- Markdown report: `<output_dir>/reports/performance_comparison.md`
- CSV data: `<output_dir>/reports/performance_data.csv`

**Features**:
- Benchmarks both encoding and decoding for J2KSwift and OpenJPEG
- Detailed statistics (min, max, average, median, std dev, throughput)
- Generates professional Markdown comparison report
- CSV export for data analysis
- Handles decoder errors gracefully
- Clear pass/fail status against 80% performance target

**Current Status (v1.1.1)**:
- ✅ Encoding benchmarks: Fully functional
- ⚠️ Decoding benchmarks: J2KSwift decoder has issues with images >256×256
- ✅ Report generation: Working
- ⚠️ Performance: J2KSwift encoding is ~33% of OpenJPEG speed (target: ≥80%)

**Example Output**:
```
Benchmarking 1024×1024...
  Running J2KSwift benchmark...
    Encode: 607.2ms avg (1.73 MP/s)
    Decode: FAILED (decoder error)
  Running OpenJPEG encode benchmark...
    Encode: 199.8ms avg (5.25 MP/s)
  Running OpenJPEG decode benchmark...
    Decode: 159.1ms avg (6.59 MP/s)
  J2KSwift vs OpenJPEG:
    Encode: 32.9% of OpenJPEG speed
```

**Status**: 
- ✅ OpenJPEG benchmarking infrastructure
- ✅ J2KSwift CLI tool (complete - supports encode, decode, benchmark commands)
- ✅ Automated benchmarking with JSON output
- ✅ Integration with benchmark_openjpeg.sh script

**Features**:
- Command-line interface for J2KSwift encoding/decoding
- Benchmarking with detailed statistics (min, max, average, median, throughput)
- JSON output for automated processing
- PGM/PPM image format support
- Multiple encoding presets (fast, balanced, quality)
- Detailed timing information

**Usage**:
```bash
# Show help
.build/debug/j2k --help

# Encode an image
.build/debug/j2k encode -i input.pgm -o output.j2k --timing

# Decode an image
.build/debug/j2k decode -i input.j2k -o output.pgm --timing

# Run benchmarks
.build/debug/j2k benchmark -i test.pgm -r 10 -o results.json

# Run comparison benchmarks (J2KSwift vs OpenJPEG)
./Scripts/benchmark_openjpeg.sh -s 512,1024 -r 5
```

**Future Enhancements**:
1. Add RGB/RGBA image tests (PPM format support is implemented)
2. Test multiple quality levels (presets implemented)
3. Memory profiling integration
4. Multi-threaded performance testing
5. Automated report generation with charts

## Future Scripts

### build_release.sh (planned)
Automated release build and packaging script.

### run_conformance_tests.sh (planned)
ISO/IEC 15444 conformance test suite runner.

### generate_docs.sh (planned)
Swift-DocC documentation generation and deployment.

---

**Created**: 2026-02-14  
**For**: J2KSwift v1.1.1 development  
**See**: [ROADMAP_v1.1.md](../ROADMAP_v1.1.md) for development roadmap
