# Parallelization Strategy for JPEG 2000 Entropy Coding

This document outlines the parallelization opportunities and challenges for JPEG 2000 entropy coding in J2KSwift.

## Current Implementation Status

As of Phase 1 Week 20-22, the entropy coding implementation is single-threaded and operates on individual code-blocks sequentially.

## Parallelization Opportunities

### 1. Code-Block Level Parallelization (Primary Opportunity)

**Where**: Multiple independent code-blocks can be encoded/decoded in parallel.

**Why**: Each code-block in JPEG 2000 is an independent unit of entropy coding with its own:
- MQ encoder/decoder state
- Context models
- Coefficient data
- No dependencies on other code-blocks

**Implementation Strategy**:
```swift
// Future API (conceptual)
actor CodeBlockProcessor {
    func processCodeBlocks(_ blocks: [CodeBlock]) async -> [EncodedCodeBlock] {
        await withTaskGroup(of: EncodedCodeBlock.self) { group in
            for block in blocks {
                group.addTask {
                    await self.encodeCodeBlock(block)
                }
            }
            
            var results: [EncodedCodeBlock] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }
}
```

**Requirements**:
1. Actor-based or structured concurrency design
2. Thread-safe memory pooling for temporary buffers
3. Proper ordering of results (maintain code-block indices)
4. Load balancing for varying code-block sizes

**Expected Performance Gain**: Near-linear scaling with core count (up to 8 cores: 80%+ efficiency)

### 2. Bit-Plane Level Parallelization (Limited Opportunity)

**Where**: Within a single code-block, different coding passes.

**Why**: Bit-plane coding has sequential dependencies:
- Each bit-plane depends on state from previous bit-planes
- Within a bit-plane, passes must execute in order (SPP → MRP → CP)

**Challenges**:
- Strong data dependencies between bit-planes
- State updates must be synchronized
- Overhead of parallelization likely exceeds benefits

**Verdict**: NOT RECOMMENDED due to fine-grained dependencies and synchronization overhead.

### 3. Tile and Component Level Parallelization

**Where**: Multiple tiles or components can be processed independently.

**Why**: Each tile/component has independent code-blocks and can be fully processed in parallel.

**Implementation Strategy**:
```swift
actor TileProcessor {
    func processTiles(_ tiles: [Tile]) async -> [EncodedTile] {
        await withTaskGroup(of: EncodedTile.self) { group in
            for tile in tiles {
                group.addTask {
                    await self.encodeTile(tile)
                }
            }
            // ... collect results
        }
    }
}
```

**Requirements**:
1. Separate processing pipeline per tile
2. Memory management for multiple active tiles
3. Rate-distortion optimization may need coordination

**Expected Performance Gain**: Excellent scaling for multi-tile images

## Architecture Recommendations

### Phase 1: Foundation (Current)
- [x] Single-threaded, optimized MQ-coder
- [x] Profile and optimize hot paths
- [x] Establish performance baselines

### Phase 2: Code-Block Parallelization (Future)
- [ ] Design actor-based code-block processor
- [ ] Implement thread-safe memory pooling
- [ ] Add concurrent code-block encoding
- [ ] Benchmark and tune for different core counts

### Phase 3: Higher-Level Parallelization (Future)
- [ ] Tile-level parallel processing
- [ ] Component-level parallel processing
- [ ] Integrate with rate-distortion optimization

## Performance Targets

Based on typical JPEG 2000 workloads:

| Configuration | Current | Target (8 cores) |
|--------------|---------|------------------|
| Single code-block | ~1.0 ms | ~1.0 ms (no change) |
| 64 code-blocks | ~64 ms | ~10-12 ms (5-6x speedup) |
| 256 code-blocks | ~256 ms | ~35-40 ms (6-7x speedup) |

## Memory Considerations

Parallel code-block processing requires careful memory management:

1. **Per-Thread Buffers**: Each encoding thread needs its own MQ encoder and buffers
2. **Memory Pooling**: Reuse buffers across code-blocks to avoid allocations
3. **Cache Efficiency**: Group small code-blocks together to improve cache utilization

## Implementation Priority

1. **High Priority**: Code-block level parallelization (Phase 2)
   - Largest performance gain
   - Clean architectural boundaries
   - Aligns with JPEG 2000 standard structure

2. **Medium Priority**: Tile-level parallelization (Phase 3)
   - Good scaling for large images
   - Requires higher-level coordination

3. **Low Priority**: Bit-plane parallelization
   - Complex implementation
   - Limited benefits due to dependencies
   - Not recommended

## Next Steps

When implementing parallelization:

1. Start with code-block level parallelization
2. Use Swift's structured concurrency (async/await, actors)
3. Maintain backward compatibility with single-threaded API
4. Add configuration options for thread count
5. Benchmark thoroughly on various image sizes and code-block configurations
6. Profile to identify any unexpected bottlenecks

## References

- ISO/IEC 15444-1: JPEG 2000 image coding system (Section on EBCOT)
- Swift Concurrency: Structured concurrency and actors
- Performance targets based on OpenJPEG multi-threading benchmarks

---

**Last Updated**: 2026-02-05
**Status**: Documentation complete, implementation deferred to future phase
