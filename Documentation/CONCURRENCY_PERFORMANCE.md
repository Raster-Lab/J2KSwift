# Concurrency Performance Tuning — Design Document

**Week 240-241** | **Phase 17a — Swift 6.2 Strict Concurrency Refactoring**

## Overview

This document describes the concurrency performance tuning infrastructure added
in Week 240-241, covering actor contention analysis, parallel pipeline design,
configurable concurrency limits, and work-stealing patterns for uneven tile sizes.

## Design Principles

1. **Zero data races by construction** — All concurrent state uses Swift 6.2
   actor isolation, `Mutex<T>` from the `Synchronization` module, or `Sendable`
   value types. No `@unchecked Sendable` introduced.

2. **Respect system resources** — `J2KConcurrencyLimits` caps parallelism to
   the active processor count and supports memory budgets, preventing
   over-subscription.

3. **Minimize isolation crossings** — Hot paths avoid unnecessary actor hops.
   `J2KConcurrentPipeline` uses bounded `TaskGroup` with direct result
   collection rather than actor-mediated result passing.

4. **Work-stealing for load balance** — When tile sizes or code-block
   complexities vary, `J2KWorkStealingQueue` allows idle workers to steal
   from busy workers, improving utilisation.

## Components

### J2KConcurrencyLimits

Configuration for controlling concurrency:

| Property | Description | Default |
|----------|-------------|---------|
| `maxParallelism` | Maximum concurrent tasks | System processor count |
| `maxMemoryBudget` | Memory budget in bytes (0 = unlimited) | 0 |
| `minItemsPerTask` | Minimum items per task | 1 |
| `enableWorkStealing` | Enable work-stealing for uneven workloads | true |

**Presets**:
- `.forSystem()` — Detects system capabilities automatically.
- `.forCoreCount(n)` — Targets a specific core count (useful for testing).
- `.serial` — Single-threaded execution for baseline comparison.

### J2KActorContentionAnalyzer

An actor that instruments concurrent operations to measure:

- **Message sends** — Number of actor message-passing operations.
- **Isolation crossings** — Boundary crossings between actor and non-actor code.
- **Contention time** — Time spent waiting for actor access.
- **Hot paths** — Labels identifying the most contended code paths.

The analyzer produces `J2KActorContentionMetrics` with derived properties:
- `contentionPercentage` — Fraction of wall-clock time spent in contention.
- `messagesPerTask` — Average messages per concurrent task.
- `averageContentionMicroseconds` — Average contention latency per crossing.

### J2KConcurrentPipeline

A `Sendable` struct that provides tile-level and code-block-level parallelism
for JPEG 2000 encode/decode pipelines.

**Key design decisions**:

1. **Bounded TaskGroup** — Tasks are submitted in batches up to `maxParallelism`.
   As tasks complete, new ones are submitted, maintaining a steady concurrency
   level without over-subscribing the system.

2. **Order preservation** — Results are tagged with their input index and sorted
   before return, guaranteeing deterministic output order regardless of
   completion order.

3. **Adaptive path selection** — For small workloads (≤ 1 item or serial mode),
   parallelism overhead is skipped entirely. For many items with work-stealing
   enabled, the work-stealing path is used.

### J2KWorkStealingQueue

A `Sendable` work-stealing deque using `Mutex<[T]>`:

- **Owner operations** (`takeOwn()`) — Remove from front (FIFO).
- **Thief operations** (`steal()`) — Remove from back (LIFO).

This is the classic Cilk-style work-stealing approach, where each worker
processes its own queue first, then steals from others when idle.

### ConcurrentResultCollector

An internal `Sendable` result collector using `Mutex<[T]>`, following the same
pattern as `ParallelResultCollector<T>` in J2KCodec. Used by the work-stealing
pipeline to collect results thread-safely.

### J2KConcurrencyBenchmark

Benchmarking infrastructure for measuring:

- **Serial vs parallel speedup** — `compareConcurrentVsSerial()` measures both
  execution modes and reports speedup ratio.
- **Scalability curves** — `measureScalability()` runs workloads across
  multiple core counts and produces a `ScalabilityReport` with speedup and
  efficiency at each point.

### J2KConcurrencyMemoryMonitor

Monitors memory pressure during concurrent execution:

- **Snapshots** — Captures resident memory and active task count.
- **Delta measurement** — Measures memory change during an operation.

## Memory Model Compliance

All types in `J2KConcurrencyTuning.swift` follow the Swift 6.2 memory model:

| Type | Isolation Method | Sendable |
|------|-----------------|----------|
| `J2KConcurrencyLimits` | Value type (struct) | ✅ |
| `J2KActorContentionMetrics` | Value type (struct) | ✅ |
| `J2KActorContentionAnalyzer` | Actor isolation | ✅ |
| `J2KWorkStealingQueue<T>` | `Mutex<[T]>` | ✅ |
| `ConcurrentResultCollector<T>` | `Mutex<[T]>` | ✅ |
| `J2KConcurrentPipeline` | Value type (struct) | ✅ |
| `J2KConcurrencyBenchmark` | Value type (struct) | ✅ |
| `J2KConcurrencyMemoryMonitor` | Value type (struct) | ✅ |

**Zero `@unchecked Sendable`** — No new `@unchecked Sendable` types introduced.

## Performance Characteristics

### Expected Scalability

For tile-level parallelism with 8+ tiles:

| Core Count | Expected Speedup | Expected Efficiency |
|------------|------------------|---------------------|
| 1 | 1.0× | 100% |
| 2 | ~1.8× | ~90% |
| 4 | ~3.2× | ~80% |
| 8 | ~5.5× | ~69% |
| 16 | ~7.5× | ~47% |

Efficiency decreases at higher core counts due to:
- Mutex contention in result collection.
- Memory bandwidth saturation.
- TaskGroup coordination overhead.

### Work-Stealing Benefits

Work-stealing improves performance when tiles have uneven processing costs:
- Tiles with complex content (high detail) take longer.
- Tiles near image edges may be smaller.
- HTJ2K and legacy code-blocks have different coding complexities.

The work-stealing path is triggered when `items.count > maxConcurrency * 2`.

## Testing

26 tests covering:

- **Unit tests**: Limits configuration, contention metrics, work-stealing queue.
- **Integration tests**: Pipeline parallel execution, order preservation, error
  propagation, work-stealing path.
- **Scalability tests**: Multi-core benchmarking, concurrent vs serial comparison.
- **Memory tests**: Memory pressure under high concurrency.
- **Sendable conformance**: All public types verified as `Sendable`.

## Future Work

- Profile real-world JPEG 2000 encoding workloads to identify actual contention
  hotspots (requires test images and end-to-end pipeline integration).
- Adaptive concurrency limits that adjust based on thermal state and memory
  pressure at runtime.
- Integration with `J2KPerformanceOptimizer` for unified performance management.
