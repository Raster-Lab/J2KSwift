/// # JPIPBandwidthEstimator
///
/// Real-time bandwidth estimation for JPIP streaming.
///
/// Provides accurate bandwidth measurement using throughput tracking,
/// moving averages, congestion detection, and predictive adaptation.

import Foundation
import J2KCore

/// Bandwidth measurement sample.
public struct JPIPBandwidthSample: Sendable {
    /// Timestamp of measurement.
    public let timestamp: Date
    
    /// Measured throughput in bytes per second.
    public let throughput: Int
    
    /// Round-trip time in milliseconds.
    public let rtt: Double
    
    /// Number of bytes transferred in this sample.
    public let bytesTransferred: Int
    
    /// Duration of sample in seconds.
    public let duration: TimeInterval
    
    /// Creates a bandwidth sample.
    public init(
        timestamp: Date = Date(),
        throughput: Int,
        rtt: Double,
        bytesTransferred: Int,
        duration: TimeInterval
    ) {
        self.timestamp = timestamp
        self.throughput = throughput
        self.rtt = rtt
        self.bytesTransferred = bytesTransferred
        self.duration = duration
    }
}

/// Bandwidth estimation result.
public struct JPIPBandwidthEstimate: Sendable {
    /// Estimated available bandwidth in bytes per second.
    public let bandwidth: Int
    
    /// Bandwidth trend (-1.0 to 1.0, negative = decreasing).
    public let trend: Double
    
    /// Confidence level (0.0-1.0).
    public let confidence: Double
    
    /// Congestion detected flag.
    public let congestionDetected: Bool
    
    /// Average round-trip time in milliseconds.
    public let averageRTT: Double
    
    /// Predicted bandwidth for next interval (bytes per second).
    public let predictedBandwidth: Int
    
    /// Creates a bandwidth estimate.
    public init(
        bandwidth: Int,
        trend: Double,
        confidence: Double,
        congestionDetected: Bool,
        averageRTT: Double,
        predictedBandwidth: Int
    ) {
        self.bandwidth = bandwidth
        self.trend = trend
        self.confidence = confidence
        self.congestionDetected = congestionDetected
        self.averageRTT = averageRTT
        self.predictedBandwidth = predictedBandwidth
    }
}

/// Configuration for bandwidth estimator.
public struct JPIPBandwidthEstimatorConfiguration: Sendable {
    /// Sample window size for moving average.
    public var sampleWindowSize: Int
    
    /// Minimum samples required for stable estimate.
    public var minimumSamples: Int
    
    /// Congestion detection threshold (RTT increase ratio).
    public var congestionThreshold: Double
    
    /// Smoothing factor for moving average (0.0-1.0).
    public var smoothingFactor: Double
    
    /// Measurement interval in seconds.
    public var measurementInterval: TimeInterval
    
    /// Creates bandwidth estimator configuration.
    ///
    /// - Parameters:
    ///   - sampleWindowSize: Sample window size (default: 20).
    ///   - minimumSamples: Minimum samples (default: 5).
    ///   - congestionThreshold: Congestion threshold (default: 1.5).
    ///   - smoothingFactor: Smoothing factor (default: 0.7).
    ///   - measurementInterval: Measurement interval (default: 1.0).
    public init(
        sampleWindowSize: Int = 20,
        minimumSamples: Int = 5,
        congestionThreshold: Double = 1.5,
        smoothingFactor: Double = 0.7,
        measurementInterval: TimeInterval = 1.0
    ) {
        self.sampleWindowSize = sampleWindowSize
        self.minimumSamples = minimumSamples
        self.congestionThreshold = congestionThreshold
        self.smoothingFactor = max(0.0, min(1.0, smoothingFactor))
        self.measurementInterval = measurementInterval
    }
}

/// Real-time bandwidth estimator for JPIP streaming.
///
/// Tracks network throughput, detects congestion, and predicts future
/// bandwidth availability for adaptive streaming decisions.
///
/// Example:
/// ```swift
/// let estimator = JPIPBandwidthEstimator()
///
/// // Record transfer
/// await estimator.recordTransfer(bytes: 100_000, duration: 0.5, rtt: 50.0)
///
/// // Get estimate
/// let estimate = await estimator.getEstimate()
/// print("Bandwidth: \(estimate.bandwidth) bytes/sec")
/// ```
public actor JPIPBandwidthEstimator {
    /// Configuration.
    public let configuration: JPIPBandwidthEstimatorConfiguration
    
    /// Sample history.
    private var samples: [JPIPBandwidthSample]
    
    /// Current bandwidth estimate.
    private var currentEstimate: Int
    
    /// Exponential moving average bandwidth.
    private var emaBandwidth: Double
    
    /// Baseline RTT (minimum observed).
    private var baselineRTT: Double
    
    /// Current average RTT.
    private var currentRTT: Double
    
    /// Last measurement timestamp.
    private var lastMeasurement: Date?
    
    /// Accumulated bytes since last measurement.
    private var accumulatedBytes: Int
    
    /// Accumulated duration since last measurement.
    private var accumulatedDuration: TimeInterval
    
    /// RTT samples for congestion detection.
    private var rttSamples: [Double]
    
    /// Creates a bandwidth estimator.
    ///
    /// - Parameter configuration: Estimator configuration.
    public init(configuration: JPIPBandwidthEstimatorConfiguration = JPIPBandwidthEstimatorConfiguration()) {
        self.configuration = configuration
        self.samples = []
        self.currentEstimate = 5_000_000 // Initial estimate: 5 MB/s
        self.emaBandwidth = 5_000_000.0
        self.baselineRTT = Double.infinity
        self.currentRTT = 0.0
        self.accumulatedBytes = 0
        self.accumulatedDuration = 0.0
        self.rttSamples = []
    }
    
    /// Records a data transfer for bandwidth measurement.
    ///
    /// - Parameters:
    ///   - bytes: Number of bytes transferred.
    ///   - duration: Transfer duration in seconds.
    ///   - rtt: Round-trip time in milliseconds (optional).
    public func recordTransfer(bytes: Int, duration: TimeInterval, rtt: Double = 0.0) {
        guard duration > 0 else { return }
        
        // Accumulate for interval-based measurement
        accumulatedBytes += bytes
        accumulatedDuration += duration
        
        // Update RTT tracking
        if rtt > 0 {
            currentRTT = rtt
            rttSamples.append(rtt)
            if rttSamples.count > configuration.sampleWindowSize {
                rttSamples.removeFirst()
            }
            
            // Update baseline RTT (minimum observed)
            baselineRTT = min(baselineRTT, rtt)
        }
        
        // Check if we should create a new sample
        let now = Date()
        if let last = lastMeasurement {
            if now.timeIntervalSince(last) >= configuration.measurementInterval {
                createSample()
            }
        } else {
            lastMeasurement = now
        }
    }
    
    /// Gets current bandwidth estimate.
    ///
    /// - Returns: Bandwidth estimate with trend and congestion info.
    public func getEstimate() -> JPIPBandwidthEstimate {
        // Calculate trend from recent samples
        let trend = calculateTrend()
        
        // Detect congestion
        let congestion = detectCongestion()
        
        // Calculate confidence
        let confidence = calculateConfidence()
        
        // Predict future bandwidth
        let predicted = predictBandwidth(trend: trend, congestion: congestion)
        
        return JPIPBandwidthEstimate(
            bandwidth: currentEstimate,
            trend: trend,
            confidence: confidence,
            congestionDetected: congestion,
            averageRTT: currentRTT,
            predictedBandwidth: predicted
        )
    }
    
    /// Resets bandwidth estimator state.
    public func reset() {
        samples.removeAll()
        currentEstimate = 5_000_000
        emaBandwidth = 5_000_000.0
        baselineRTT = Double.infinity
        currentRTT = 0.0
        lastMeasurement = nil
        accumulatedBytes = 0
        accumulatedDuration = 0.0
        rttSamples.removeAll()
    }
    
    /// Gets recent sample history.
    ///
    /// - Returns: Array of recent bandwidth samples.
    public func getSampleHistory() -> [JPIPBandwidthSample] {
        return samples
    }
    
    // MARK: - Private Methods
    
    /// Creates a sample from accumulated measurements.
    private func createSample() {
        guard accumulatedDuration > 0 else { return }
        
        let throughput = Int(Double(accumulatedBytes) / accumulatedDuration)
        
        let sample = JPIPBandwidthSample(
            throughput: throughput,
            rtt: currentRTT,
            bytesTransferred: accumulatedBytes,
            duration: accumulatedDuration
        )
        
        samples.append(sample)
        
        // Maintain window size
        if samples.count > configuration.sampleWindowSize {
            samples.removeFirst()
        }
        
        // Update estimate with exponential moving average
        updateEstimate(sample: sample)
        
        // Reset accumulators
        accumulatedBytes = 0
        accumulatedDuration = 0.0
        lastMeasurement = Date()
    }
    
    /// Updates bandwidth estimate with new sample.
    private func updateEstimate(sample: JPIPBandwidthSample) {
        // Use exponential moving average for smooth estimates
        let alpha = 1.0 - configuration.smoothingFactor
        emaBandwidth = alpha * Double(sample.throughput) + configuration.smoothingFactor * emaBandwidth
        currentEstimate = Int(emaBandwidth)
    }
    
    /// Calculates bandwidth trend from recent samples.
    private func calculateTrend() -> Double {
        guard samples.count >= 2 else { return 0.0 }
        
        // Use linear regression on recent samples
        let recentCount = min(10, samples.count)
        let recentSamples = Array(samples.suffix(recentCount))
        
        // Calculate trend using first and last sample
        let first = Double(recentSamples.first!.throughput)
        let last = Double(recentSamples.last!.throughput)
        
        guard first > 0 else { return 0.0 }
        
        // Normalize trend to -1.0 to 1.0 range
        let change = (last - first) / first
        return max(-1.0, min(1.0, change))
    }
    
    /// Detects network congestion based on RTT.
    private func detectCongestion() -> Bool {
        guard baselineRTT.isFinite, baselineRTT > 0, currentRTT > 0 else {
            return false
        }
        
        // Congestion if RTT increases significantly above baseline
        let rttRatio = currentRTT / baselineRTT
        return rttRatio > configuration.congestionThreshold
    }
    
    /// Calculates confidence in bandwidth estimate.
    private func calculateConfidence() -> Double {
        guard samples.count >= configuration.minimumSamples else {
            // Low confidence with few samples
            return Double(samples.count) / Double(configuration.minimumSamples)
        }
        
        // Calculate variance in recent samples
        let recentCount = min(10, samples.count)
        let recentSamples = Array(samples.suffix(recentCount))
        
        let mean = Double(recentSamples.map { $0.throughput }.reduce(0, +)) / Double(recentCount)
        let variance = recentSamples.map { sample in
            let diff = Double(sample.throughput) - mean
            return diff * diff
        }.reduce(0, +) / Double(recentCount)
        
        let stdDev = variance.squareRoot()
        
        // Lower variance = higher confidence
        // Confidence decreases as coefficient of variation increases
        guard mean > 0 else { return 0.5 }
        let coefficientOfVariation = stdDev / mean
        return max(0.0, min(1.0, 1.0 - coefficientOfVariation))
    }
    
    /// Predicts future bandwidth based on trend and congestion.
    private func predictBandwidth(trend: Double, congestion: Bool) -> Int {
        var predicted = Double(currentEstimate)
        
        // Apply trend prediction
        if trend > 0 {
            // Increasing trend: predict moderate increase
            predicted *= (1.0 + trend * 0.2)
        } else if trend < 0 {
            // Decreasing trend: predict sharper decrease
            predicted *= (1.0 + trend * 0.3)
        }
        
        // Apply congestion penalty
        if congestion {
            predicted *= 0.7
        }
        
        return max(100_000, Int(predicted)) // Minimum 100 KB/s
    }
}
