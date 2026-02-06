/// # JPIPBandwidthThrottle
///
/// Bandwidth throttling for JPIP server.

import Foundation
import J2KCore

/// Manages bandwidth throttling for the JPIP server.
///
/// Implements per-client and global bandwidth limits using a token bucket
/// algorithm for smooth rate limiting.
public actor JPIPBandwidthThrottle {
    /// Global bandwidth limit in bytes per second (nil = unlimited).
    private let globalLimit: Int?
    
    /// Per-client bandwidth limit in bytes per second (nil = unlimited).
    private let perClientLimit: Int?
    
    /// Global token bucket.
    private var globalBucket: TokenBucket?
    
    /// Per-client token buckets.
    private var clientBuckets: [String: TokenBucket]
    
    /// Bandwidth usage statistics.
    private var stats: Statistics
    
    /// Token bucket for rate limiting.
    private struct TokenBucket {
        /// Maximum number of tokens (burst capacity).
        let capacity: Int
        
        /// Current number of tokens.
        var tokens: Int
        
        /// Tokens added per second.
        let refillRate: Int
        
        /// Last refill timestamp.
        var lastRefill: Date
        
        /// Creates a new token bucket.
        ///
        /// - Parameters:
        ///   - capacity: Maximum tokens (burst capacity).
        ///   - refillRate: Tokens added per second.
        init(capacity: Int, refillRate: Int) {
            self.capacity = capacity
            self.tokens = capacity
            self.refillRate = refillRate
            self.lastRefill = Date()
        }
        
        /// Refills tokens based on elapsed time.
        mutating func refill() {
            let now = Date()
            let elapsed = now.timeIntervalSince(lastRefill)
            let newTokens = Int(elapsed * Double(refillRate))
            
            if newTokens > 0 {
                tokens = min(capacity, tokens + newTokens)
                lastRefill = now
            }
        }
        
        /// Tries to consume tokens.
        ///
        /// - Parameter count: Number of tokens to consume.
        /// - Returns: True if tokens were consumed, false otherwise.
        mutating func tryConsume(_ count: Int) -> Bool {
            refill()
            
            guard tokens >= count else {
                return false
            }
            
            tokens -= count
            return true
        }
    }
    
    /// Bandwidth statistics.
    public struct Statistics: Sendable {
        /// Total bytes sent.
        public var totalBytesSent: Int
        
        /// Total requests throttled (globally).
        public var globalThrottles: Int
        
        /// Total requests throttled (per-client).
        public var clientThrottles: Int
        
        /// Active clients being tracked.
        public var activeClients: Int
        
        /// Creates empty statistics.
        public init() {
            self.totalBytesSent = 0
            self.globalThrottles = 0
            self.clientThrottles = 0
            self.activeClients = 0
        }
    }
    
    /// Creates a new bandwidth throttle.
    ///
    /// - Parameters:
    ///   - globalLimit: Global bandwidth limit in bytes per second (nil = unlimited).
    ///   - perClientLimit: Per-client bandwidth limit in bytes per second (nil = unlimited).
    public init(globalLimit: Int? = nil, perClientLimit: Int? = nil) {
        self.globalLimit = globalLimit
        self.perClientLimit = perClientLimit
        
        // Create global bucket if limit is set
        if let limit = globalLimit {
            // Allow burst of 2x the per-second rate
            self.globalBucket = TokenBucket(capacity: limit * 2, refillRate: limit)
        } else {
            self.globalBucket = nil
        }
        
        self.clientBuckets = [:]
        self.stats = Statistics()
    }
    
    /// Checks if data can be sent to a client.
    ///
    /// - Parameters:
    ///   - clientID: The client identifier.
    ///   - bytes: Number of bytes to send.
    /// - Returns: True if the data can be sent, false if throttled.
    public func canSend(clientID: String, bytes: Int) -> Bool {
        // Check global limit
        if var bucket = globalBucket {
            if !bucket.tryConsume(bytes) {
                stats.globalThrottles += 1
                globalBucket = bucket
                return false
            }
            globalBucket = bucket
        }
        
        // Check per-client limit
        if let limit = perClientLimit {
            var bucket = clientBuckets[clientID] ?? TokenBucket(
                capacity: limit * 2,
                refillRate: limit
            )
            
            if !bucket.tryConsume(bytes) {
                stats.clientThrottles += 1
                clientBuckets[clientID] = bucket
                return false
            }
            
            clientBuckets[clientID] = bucket
        }
        
        return true
    }
    
    /// Records that data was sent to a client.
    ///
    /// - Parameters:
    ///   - clientID: The client identifier.
    ///   - bytes: Number of bytes sent.
    public func recordSent(clientID: String, bytes: Int) {
        stats.totalBytesSent += bytes
        
        // Ensure client bucket exists
        if perClientLimit != nil, clientBuckets[clientID] == nil {
            if let limit = perClientLimit {
                clientBuckets[clientID] = TokenBucket(
                    capacity: limit * 2,
                    refillRate: limit
                )
            }
        }
        
        stats.activeClients = clientBuckets.count
    }
    
    /// Removes tracking for a client (e.g., when session closes).
    ///
    /// - Parameter clientID: The client identifier.
    public func removeClient(_ clientID: String) {
        clientBuckets.removeValue(forKey: clientID)
        stats.activeClients = clientBuckets.count
    }
    
    /// Gets the current bandwidth statistics.
    ///
    /// - Returns: Bandwidth statistics.
    public func getStatistics() -> Statistics {
        return stats
    }
    
    /// Gets the current available bandwidth for a client.
    ///
    /// - Parameter clientID: The client identifier.
    /// - Returns: Available bytes, or nil if unlimited.
    public func getAvailableBandwidth(for clientID: String) -> Int? {
        if let bucket = clientBuckets[clientID] {
            return bucket.tokens
        }
        
        if let bucket = globalBucket {
            return bucket.tokens
        }
        
        return nil // Unlimited
    }
    
    /// Resets bandwidth statistics.
    public func resetStatistics() {
        stats = Statistics()
        stats.activeClients = clientBuckets.count
    }
    
    /// Clears all client buckets.
    public func clearClients() {
        clientBuckets.removeAll()
        stats.activeClients = 0
    }
}
