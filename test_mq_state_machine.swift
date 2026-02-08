#!/usr/bin/env swift

import Foundation

// Quick test to check MQ-coder state machine
// This replicates the exact sequence seen in the failing test

@main
struct MQTest {
    static func main() {
        print("Testing MQ-coder state machine synchronization...")
        
        // We need to check if encoding 5 consecutive false symbols
        // with context state starting at 30, mps=false
        // produces a bitstream that decodes correctly
        
        print("\nExpected behavior:")
        print("- Encoder: 30→30, 30→30, 30→30, 30→30, 30→31 (all false)")
        print("- Decoder: 30→30, 30→30, 30→30, 30→30, 30→?? (should all be false)")
        print("\nIssue: Decoder gets state=28 and reads TRUE on last decode")
        print("\nThis suggests the MQ-coder's state machine or flushing has a bug.")
    }
}
