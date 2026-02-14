# J2KSwift Scripts

This directory contains utility scripts for development, testing, and benchmarking J2KSwift.

## Available Scripts

### benchmark_openjpeg.sh

Automated performance comparison between J2KSwift and OpenJPEG.

**Purpose**: Provides infrastructure for benchmarking J2KSwift against the OpenJPEG reference implementation, enabling performance validation and optimization tracking.

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

# Run comprehensive benchmark
./Scripts/benchmark_openjpeg.sh -s 512,1024,2048 -r 10 -o ./results
```

**Output**:
- Test images in `<output_dir>/test_images/`
- OpenJPEG results in `<output_dir>/openjpeg/`
- Comparison reports in `<output_dir>/reports/`

**Status**: 
- ✅ OpenJPEG benchmarking infrastructure
- ⏳ J2KSwift CLI tool (pending - required for automated J2KSwift benchmarks)

**Future Enhancements**:
1. Implement J2KSwift CLI tool for automated benchmarking
2. Add RGB/RGBA image tests
3. Test multiple quality levels
4. Memory profiling integration
5. Multi-threaded performance testing
6. Automated report generation with charts

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
