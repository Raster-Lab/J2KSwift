c# J2KSwift Copilot Agents & Skills

## Agents

Invoke agents with `@agent-name` in VS Code Copilot Chat.

| Agent | Invoke With | Domain |
|-------|-------------|--------|
| Codec Dev | `@codec-dev` | Encoder/decoder pipeline, DWT, EBCOT, MQ coder, quantization, rate control |
| Testing | `@testing` | Unit tests, cross-codec validation, XCTest, test coverage |
| Compliance | `@compliance` | ISO/IEC 15444-4 conformance, release gates, error tolerances |
| CLI Dev | `@cli-dev` | `j2k` CLI commands, image I/O, OpenJPEG wrappers, batch processing |
| GPU Dev | `@gpu-dev` | Metal shaders, Vulkan pipelines, Accelerate/vDSP, SIMD, buffer pools |
| Benchmark | `@benchmark` | J2KSwift vs OpenJPEG benchmarking, encode/decode speed, quality metrics |
| HTJ2K Dev | `@htj2k-dev` | HTJ2K (Part 15) encoding/decoding, FBCOT block coder, MEL/VLC/MagSgn, conformance |
| JP3D Dev | `@jp3d-dev` | 3D volumetric imaging, CT/MRI volumes, multispectral, Part 10 |
| File Format Dev | `@file-format-dev` | JP2/JPX/JPM/JPH/MJ2 boxes, format detection, metadata |
| JPIP Dev | `@jpip-dev` | JPIP client/server, WebSocket, progressive delivery, caching |
| Perf Dev | `@perf-dev` | Profiling, benchmarking, memory optimization, concurrency tuning |

### Example Prompts

```
@codec-dev Fix the MQ coder carry propagation for 0xFF sequences
@testing Write tests for multi-tile lossless roundtrip with 1x1 edge tiles
@compliance Run the full ISO conformance suite and report results
@cli-dev Add a --tile-size flag to the encode command
@gpu-dev Optimize the Metal DWT kernel for Apple M4
@benchmark Compare J2KSwift vs OpenJPEG encode speed for 4096x4096 lossless
@benchmark Run lossy quality comparison at 20:1 compression ratio
@htj2k-dev Optimize the MEL coder for sparse coefficient patterns
@htj2k-dev Fix mixed-mode encoding for HT + legacy blocks in multi-tile images
@jp3d-dev Implement progressive 3D decoding for CT volumes
@file-format-dev Add JPH (HTJ2K) file format writing support
@jpip-dev Fix WebSocket reconnection with session persistence
@perf-dev Profile the encoder pipeline and identify the bottleneck
```

---

## Skills

Invoke skills with `/skill-name` in VS Code Copilot Chat.

| Skill | Invoke With | Workflow |
|-------|-------------|----------|
| Cross-Codec Testing | `/cross-codec-testing` | Full J2KSwift ↔ OpenJPEG interoperability test matrix |
| Conformance Testing | `/conformance-testing` | Pre-release ISO/IEC 15444-4 compliance verification |
| Medical Imaging | `/medical-imaging-validation` | DICOM/CT/MRI lossless validation with quality metrics |
| Release Checklist | `/release-checklist` | Complete pre-release validation (build, test, lint, compliance) |
| Performance Profiling | `/performance-profiling` | Pipeline profiling, bottleneck identification, OpenJPEG comparison |
| GPU Benchmark | `/gpu-benchmark` | GPU vs CPU benchmarking across Metal, Vulkan, Accelerate |
| HTJ2K Benchmark | `/htj2k-benchmark` | HTJ2K vs legacy throughput, quality parity, OpenJPEG HT interop |

### Example Prompts

```
/cross-codec-testing Run the full interop matrix for 256x256 grayscale
/conformance-testing Verify Profile 0 compliance before v2.5 release
/medical-imaging-validation Validate 16-bit CT lossless roundtrip
/release-checklist Prepare release v2.5.0
/performance-profiling Find the bottleneck in the lossy encoder pipeline
/gpu-benchmark Compare Metal DWT vs CPU DWT on a 4096x4096 image
```

---

## Combining Agents with Skills

Agents and skills work together. Use an agent for context, then invoke a skill for a workflow:

```
@testing /cross-codec-testing
Run the full interop matrix and fix any failures

@compliance /conformance-testing
Verify all profiles before the v2.5.0 release

@perf-dev /performance-profiling
Profile the decoder and optimize the slowest stage

@gpu-dev /gpu-benchmark
Benchmark Metal vs CPU for all DWT modes and optimize

@htj2k-dev /htj2k-benchmark
Benchmark HTJ2K vs legacy EBCOT across all image sizes and report speedup

@benchmark /cross-codec-testing
Benchmark J2KSwift vs OpenJPEG across all sizes and report speed + quality

@testing /medical-imaging-validation
Validate 16-bit DICOM lossless roundtrip across both codecs

@compliance /release-checklist
Run the complete release checklist for v2.5.0
```

---

## File-Specific Instructions

These load automatically when you edit files in their scope — no invocation needed.

| Instruction | Auto-Loads For | What It Provides |
|-------------|----------------|------------------|
| `swift-conventions` | `**/*.swift` | Swift 6 concurrency, naming, error handling |
| `codec-pipeline` | `Sources/J2KCodec/**` | Pipeline invariants, edge cases, symmetry rules |
| `testing` | `Tests/**` | XCTest patterns, naming, coverage requirements |
| `gpu-acceleration` | `Sources/J2KAccelerate/**`, `J2KMetal/**`, `J2KVulkan/**` | Platform guards, CPU fallback, buffer management |
| `file-format` | `Sources/J2KFileFormat/**` | Box parsing safety, format detection, streaming I/O |
| `jpip-networking` | `Sources/JPIP/**` | Actor isolation, session management, transport |
